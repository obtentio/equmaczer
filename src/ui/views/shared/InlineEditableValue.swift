import SwiftUI
import AppKit

/// Inline, tap-to-edit numeric value used for frequency/bandwidth fields.
struct InlineEditableValue: View {
    let value: Float
    let displayFormatter: (Float) -> String
    let inputFormatter: (Float) -> String
    let width: CGFloat
    let alignment: Alignment
    let onCommit: (Float) -> Void
    var onNavigateLeft: (() -> Void)? = nil
    var onNavigateRight: (() -> Void)? = nil
    var startEditing: Bool = false
    var delta: Float = 0.1
    /// Optional transform applied during arrow key adjustment to clamp before displaying.
    var onAdjust: ((Float) -> Float)? = nil

    @State private var isEditing = false
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @State private var keyMonitor: Any? = nil

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.eqT0).monospacedDigit()
                    .frame(width: width)
                    .focused($isFocused)
                    .onAppear {
                        text = inputFormatter(value)
                        DispatchQueue.main.async {
                            isFocused = true
                        }
                        // Monitor for Shift+Tab
                        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                            if event.keyCode == 48 && event.modifierFlags.contains(.shift) {
                                // Shift+Tab detected
                                if isEditing, let onNavigateLeft = onNavigateLeft {
                                    commit()
                                    onNavigateLeft()
                                }
                                return nil // Consume the event
                            }
                            return event
                        }
                    }
                    .onSubmit(commit)
                    .onChange(of: isFocused) { _, focused in
                        if !focused {
                            commit()
                        }
                    }
                    .onKeyPress(.tab) {
                        // Tab without Shift
                        if let onNavigateRight = onNavigateRight {
                            commit()
                            onNavigateRight()
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.upArrow) {
                        adjustValue(by: delta)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        adjustValue(by: -delta)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        commit()
                        return .handled
                    }
            } else {
                Button {
                    text = inputFormatter(value)
                    isEditing = true
                } label: {
                    Text(displayFormatter(value))
                        .font(.eqT0).monospacedDigit()
                        .frame(width: width, alignment: alignment)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit value: \(displayFormatter(value))")
                    .onChange(of: startEditing) { _, shouldStart in
                        if shouldStart {
                            text = inputFormatter(value)
                            isEditing = true
                        }
                    }
            }
        }
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .onChange(of: value) { _, newValue in
            if isEditing {
                text = inputFormatter(newValue)
            }
        }
    }

    private func commit() {
        guard isEditing else { return }
        defer {
            isEditing = false
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        if let newValue = Float(text), newValue != value {
            onCommit(newValue)
        }
    }

    private func adjustValue(by delta: Float) {
        let currentValue = Float(text) ?? value
        let newValue = currentValue + delta
        let adjustedValue = onAdjust?(newValue) ?? newValue
        text = inputFormatter(adjustedValue)
        onCommit(adjustedValue)
    }
}
