import Combine
import Foundation

/// App-owned automation. Overrides are transient; saved manual pins remain intact.
@MainActor
final class SceneEngine: ObservableObject {
    struct Receipt: Equatable {
        let text: String
        let canUndo: Bool
    }
    @Published private(set) var receipt: Receipt?
    private weak var store: EqumaczerStore?
    private var cancellables = Set<AnyCancellable>()
    private var active: SceneRule?
    private var background: SceneRule?
    private var revision: UInt64 = 0
    private var lastDeviceUID: String?
    private var fired: [UUID: Date] = [:]
    private let rules: SceneRuleStore
    private let now: () -> Date
    private let calendar: Calendar
    private var clock: AnyCancellable?

    init(rules: SceneRuleStore = .shared, now: @escaping () -> Date = Date.init, calendar: Calendar = .autoupdatingCurrent) {
        self.rules = rules
        self.now = now
        self.calendar = calendar
    }

    func start(store: EqumaczerStore) {
        guard self.store == nil else { return }
        self.store = store
        lastDeviceUID = store.correctionController.currentDeviceUID
        store.channelController.$callAppActive.removeDuplicates().sink { [weak self] active in
            Task { @MainActor in self?.callChanged(active) }
        }.store(in: &cancellables)
        store.correctionController.$currentDeviceUID.removeDuplicates().sink { [weak self] uid in
            Task { @MainActor in self?.deviceChanged(uid) }
        }.store(in: &cancellables)
        rules.$rules.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.reconcileRules() }
        }.store(in: &cancellables)
        clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.checkHour()
        }
        checkHour()
    }

    func stop() {
        release(reason: "Scenes stopped")
        clock?.cancel(); clock = nil
        cancellables.removeAll()
        store = nil
    }

    func callChanged(_ active: Bool) {
        if active, let rule = rules.rules.first(where: { $0.enabled && $0.trigger == .callApp }) {
            _ = fire(rule, reason: "A call app is making sound")
        } else if !active, self.active?.trigger == .callApp {
            let mayResume = revision == store?.channelController.manualPinRevision
            release(reason: "Call audio ended")
            if let background, mayResume {
                self.background = nil
                if background.trigger != .hour || background.hour == calendar.component(.hour, from: now()) {
                    _ = fire(background, reason: "Previous scene resumed")
                }
            }
        }
    }

    func deviceChanged(_ uid: String?) {
        defer { if uid != nil { lastDeviceUID = uid } }
        guard let uid, let last = lastDeviceUID, uid != last,
              let rule = rules.rules.first(where: { $0.enabled && $0.trigger == .deviceChange }) else { return }
        _ = fire(rule, reason: "Output device changed")
    }

    func checkHour() {
        guard let store else { return }
        if active != nil && revision != store.channelController.manualPinRevision {
            active = nil; background = nil
            let date = now()
            let hour = calendar.component(.hour, from: date)
            for rule in rules.rules where rule.enabled && rule.trigger == .hour && rule.hour == hour {
                fired[rule.id] = date
            }
            receipt = Receipt(text: "Manual channel choice kept", canUndo: false)
            return
        }
        let date = now()
        let hour = calendar.component(.hour, from: date)
        if let active, active.trigger == .hour, active.hour != hour { release(reason: "Scheduled hour ended") }
        let day = calendar.startOfDay(for: date)
        fired = fired.filter { $0.value >= day }
        for rule in rules.rules where rule.enabled && rule.trigger == .hour && rule.hour == hour {
            guard fired[rule.id] == nil else { continue }
            if fire(rule, reason: "Scheduled hour started") { fired[rule.id] = date }
        }
    }

    @discardableResult
    func fire(_ rule: SceneRule, reason: String) -> Bool {
        guard let store else { return false }
        if active?.trigger == .callApp && rule.trigger != .callApp { return false }
        if active?.id == rule.id { return true }
        if rule.trigger == .callApp { background = active }
        revision = store.channelController.manualPinRevision
        active = rule
        store.channelController.setSceneOverride(rule.channel)
        store.activityJournal.record(.scene, "\(reason) — \(rule.channel.displayName)")
        receipt = Receipt(text: "\(reason) — \(rule.channel.displayName)", canUndo: true)
        return true
    }

    func undo() { background = nil; release(reason: "Scene undone") }

    private func reconcileRules() {
        if let active, !rules.rules.contains(where: { $0.id == active.id && $0.enabled && $0 == active }) {
            background = nil
            release(reason: "Scene rule changed")
        }
        if store?.channelController.callAppActive == true { callChanged(true) }
        checkHour()
    }

    private func release(reason: String) {
        guard let store else { return }
        if revision == store.channelController.manualPinRevision { store.channelController.setSceneOverride(nil) }
        active = nil
        store.activityJournal.record(.scene, "\(reason) — your edits stay")
        receipt = Receipt(text: "\(reason) — your edits stay", canUndo: false)
    }
}
