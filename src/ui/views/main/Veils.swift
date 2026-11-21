// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

@MainActor
enum KeyCaptureSession { static var isActive = false }

/// The veils and the keys that raise them (revamp plan §10.4).
/// A veil dims the whole window so one fact owns the screen: the
/// compare veil while you hear the other side, the panic veil after
/// the panic key flattens everything. Both carry their way back.

/// Applies one undoable parameter blend to both channels. Endpoints are exact.
@MainActor
func applyBlend(store: EqumaczerStore, preset: Preset, blend: Double) {
    guard blend.isFinite, blend > 0 else { return }
    if blend >= 1 { store.loadPreset(preset); return }
    let before = store.captureSoundState()
    store.previewBlend(preset: preset, amount: blend, from: before)
    store.registerSoundUndo(label: "Blend preset", state: before)
}

/// Watches the app's own key events for the panic and compare keys
/// (Keys tile bindings). Typing in a text field is never hijacked.
struct AppKeyMonitor: NSViewRepresentable {
    var isEnabled = true
    let panicKey: String
    let compareKey: String
    let compareHold: Bool
    let onPanic: (Bool) -> Void
    let onCompare: (Bool) -> Void  // true = show the other side (flat)

    func makeNSView(context: Context) -> NSView {
        context.coordinator.sync(isEnabled: isEnabled, panicKey: panicKey, compareKey: compareKey, compareHold: compareHold, onPanic: onPanic, onCompare: onCompare)
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.sync(isEnabled: isEnabled, panicKey: panicKey, compareKey: compareKey, compareHold: compareHold, onPanic: onPanic, onCompare: onCompare)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.remove() }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        private var panicDown = false
        private var observers: [NSObjectProtocol] = []
        private var isEnabled = true
        private var panicKey = "P"
        private var compareKey = "C"
        private var compareHold = true
        private var onPanic: (Bool) -> Void = { _ in }
        private var onCompare: (Bool) -> Void = { _ in }
        private var monitors: [Any] = []
        private var compareDown = false

        func sync(isEnabled: Bool, panicKey: String, compareKey: String, compareHold: Bool, onPanic: @escaping (Bool) -> Void, onCompare: @escaping (Bool) -> Void) {
            if !isEnabled || self.panicKey != panicKey || self.compareKey != compareKey || self.compareHold != compareHold {
                releaseHeldKeys()
            }
            self.isEnabled = isEnabled
            self.panicKey = panicKey
            self.compareKey = compareKey
            self.compareHold = compareHold
            self.onPanic = onPanic
            self.onCompare = onCompare
        }

        func install() {
            guard monitors.isEmpty else { return }
            let down = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                let consumed = MainActor.assumeIsolated { self.handle(event, isDown: true) == nil }
                return consumed ? nil : event
            }
            let up = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self else { return event }
                let consumed = MainActor.assumeIsolated { self.handle(event, isDown: false) == nil }
                return consumed ? nil : event
            }
            monitors = [down, up].compactMap { $0 }
            for name in [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification, NSWindow.willBeginSheetNotification, NSMenu.didBeginTrackingNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.releaseHeldKeys() }
                })
            }
        }

        private func handle(_ event: NSEvent, isDown: Bool) -> NSEvent? {
            guard let chars = event.charactersIgnoringModifiers?.uppercased(), chars.count == 1 else { return event }
            // Releases must be handled even if focus or modifiers changed mid-hold.
            if !isDown {
                if chars == panicKey && panicDown { panicDown = false; onPanic(false); return nil }
                if chars == compareKey && compareHold && compareDown {
                    compareDown = false; onCompare(false); return nil
                }
                return event
            }
            guard isEnabled, view?.window != nil, view?.window === NSApp.keyWindow,
                  NSApp.keyWindow?.attachedSheet == nil,
                  !KeyCaptureSession.isActive, !Self.isTyping(),
                  ShortcutPolicy.isUnmodified(event.modifierFlags),
                  !event.isARepeat else { return event }
            if chars == panicKey {
                panicDown = true; onPanic(true); return nil
            }
            if chars == compareKey && compareKey != panicKey {
                if compareHold {
                    if !compareDown { compareDown = true; onCompare(true) }
                } else {
                    // The view supplies actual compare state through a separate toggle command.
                    onCompare(true)
                }
                return nil
            }
            return event
        }

        private func releaseHeldKeys() {
            if panicDown { panicDown = false; onPanic(false) }
            if compareDown { compareDown = false; onCompare(false) }
        }

        func remove() {
            releaseHeldKeys()
            monitors.forEach { NSEvent.removeMonitor($0) }
            monitors = []
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
        }

        private static func isTyping() -> Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else { return false }
            return responder is NSTextView || responder is NSTextField
        }


    }
}

/// The compare veil: the room dims, the banner names the side you
/// are hearing. Non-blocking — the stage stays touchable.
struct CompareVeil: View {
    let compareKey: String
    let hold: Bool

    var body: some View {
        ZStack {
            Color.eqG00.opacity(0.45)
            VStack {
                HStack(spacing: 8) {
                    Text("Comparing — flat")
                        .font(.eqT1)
                        .foregroundStyle(Color.eqG95)
                    Text(hold ? "Release \(compareKey) to return" : "Press \(compareKey) to return")
                        .font(.eqT0)
                        .foregroundStyle(Color.eqG80)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: EQDesign.cornerControl, style: .continuous)
                        .fill(Color.eqG10)
                )
                .padding(.top, 10)
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }
}

/// Held emergency bypass never edits the user's curve or gain settings.
struct PanicVeil: View {
    var body: some View {
        ZStack {
            Color.eqG00.opacity(0.6)
            Text("Bypassed while held — release to return")
                .font(.eqT3).foregroundStyle(Color.eqG95)
                .padding(20).bay()
        }
        .allowsHitTesting(false)
    }
}

/// The blend dial: a dropped preset hovers over the clay until you
/// choose how far to take it. Release applies; the dial is the
/// preview's terms, stated before anything changes.
struct BlendDial: View {
    let presetName: String
    @Binding var blend: Double
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blend \(presetName)")
                .font(.eqT3)
                .foregroundStyle(Color.eqG95)
            Text("Both channels. Filter types and bypass switch at 50%.")
                .font(.eqT0).foregroundStyle(Color.eqG80)
            HStack(spacing: 12) {
                Text("Yours")
                    .font(.eqT0)
                    .foregroundStyle(Color.eqG60)
                Slider(value: $blend, in: 0...1)
                Text(presetName)
                    .font(.eqT0)
                    .foregroundStyle(Color.eqG60)
                    .lineLimit(1)
                Text("\(Int((blend * 100).rounded()))%")
                    .font(.eqT3)
                    .foregroundStyle(Color.eqG95)
                    .frame(width: 52, alignment: .trailing)
            }
            HStack(spacing: 10) {
                Button("Apply") { onApply() }
                    .buttonStyle(.plain)
                    .font(.eqT1)
                    .foregroundStyle(Color.eqG00)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: EQDesign.cornerControl, style: .continuous)
                            .fill(Color.eqG95)
                    )
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(.eqT1)
                    .foregroundStyle(Color.eqG80)
            }
        }
        .padding(16)
        .frame(width: 420)
        .bay()
    }
}
