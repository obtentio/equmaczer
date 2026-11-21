// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation
import Combine
import os.log

/// Auto-pause glue (A8): the channel poll reports the stage, the
/// engine owns the timing, this controller owns the consequences —
/// which apps we paused, and the listener's hand outranking us.
///
/// If an app we paused is playing again while the stage still
/// holds, the listener pressed play: the app leaves our care for
/// the rest of that stage session and is not re-paused. When the
/// feature is switched off mid-pause, what we paused is resumed —
/// leaving music paused behind a disabled feature would be a trap.
@MainActor
final class AutoPauseController: ObservableObject {
    @Published private(set) var isHoldingMusic = false
    /// True while other sound is lowered for a call (A3).
    @Published private(set) var isDucking = false
    /// The "During calls" setting. Wired by `EqumaczerStore` to the channel state.
    var modeProvider: (() -> DuringCallsMode)?
    /// Whether the current route can lower sound (a live mixer). False on the driver route.
    var canDuckProvider: (() -> Bool)?
    /// Lowers or restores everything that is not the call. Gain only: never a route change.
    var duckApplier: ((Bool) -> Void)?
    /// The apps that can be paused. Tests inject none so real players are never touched.
    var pauseTargets = MusicPauser.targets
    var now: () -> Date = Date.init
    private(set) var holding: CallDuckAction?

    private var engine = AutoPauseEngine()
    private var stageActive = false
    private var pausedByUs: [MusicPauser.Target] = []
    private var overridden: Set<String> = []
    private var tickTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "AutoPauseController")

    func start() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Fed by `ChannelController.onCallStageChanged`.
    func stageChanged(_ active: Bool) {
        stageActive = active
        if !active {
            overridden.removeAll()
        }
    }

    func tick() {
        defer {
            isHoldingMusic = !pausedByUs.isEmpty
            isDucking = holding == .duck
        }
        let mode = modeProvider?() ?? .nothing
        let action = CallDuckPolicy.action(mode: mode, canDuck: canDuckProvider?() ?? false)
        guard let action else {
            if engine.engaged {
                release()
                engine.reset()
            }
            return
        }

        // The setting changed mid-call: swap the method at once. A duck stays
        // a duck under Lower even if the route briefly has no mixer.
        if engine.engaged, let held = holding, held != action, !(held == .duck && mode == .lower) {
            release()
            engage(action)
        }

        // The listener's hand outranks the automation: an app we
        // paused that is playing again was resumed by them.
        if engine.engaged {
            for target in pausedByUs where MusicPauser.isRunning(target) {
                if MusicPauser.playerState(target) == "playing" {
                    overridden.insert(target.bundleID)
                    logger.info("Auto-pause overridden by the listener for \(target.appName, privacy: .public)")
                }
            }
            pausedByUs.removeAll { overridden.contains($0.bundleID) }
        }

        switch engine.update(stageActive: stageActive, now: now()) {
        case .pause:
            engage(action)
        case .resume:
            release()
        case nil:
            break
        }
    }

    private func engage(_ action: CallDuckAction) {
        holding = action
        switch action {
        case .duck: duckApplier?(true)
        case .pause: pauseAll()
        }
    }

    private func release() {
        if holding == .duck { duckApplier?(false) }
        resumeAll()
        holding = nil
    }

    private func pauseAll() {
        for target in pauseTargets where !overridden.contains(target.bundleID) {
            guard MusicPauser.isRunning(target),
                  MusicPauser.playerState(target) == "playing"
            else { continue }
            MusicPauser.pause(target)
            pausedByUs.append(target)
            logger.info("Auto-paused \(target.appName, privacy: .public)")
        }
    }

    private func resumeAll() {
        for target in pausedByUs where MusicPauser.isRunning(target) {
            MusicPauser.play(target)
            logger.info("Auto-resumed \(target.appName, privacy: .public)")
        }
        pausedByUs.removeAll()
    }
}
