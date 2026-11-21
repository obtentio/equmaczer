// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

struct BandCountControl: View {
    @EnvironmentObject var store: EqumaczerStore
    var menuOnly = false
    @State private var isEditing = false
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                editingCluster
            } else if menuOnly {
                Menu("\(store.bandCount) bands ▾") {
                    ForEach([10, 11, 16, 32, 48, 64], id: \.self) { count in
                        Button("\(count) bands") { applyBandCount(count) }
                    }
                    Button("Custom…") { isEditing = true }
                }.fixedSize()
            } else {
                segmentBar
            }
        }
        .onChange(of: store.bandCount) { _, newValue in
            text = "\(newValue)"
            isEditing = false
        }
    }

    /// One-tap counts as segments, the rest behind More — no list, and a
    /// custom count stays one menu item away.
    private var segmentBar: some View {
        HStack(spacing: 4) {
            ForEach([10, 16, 32], id: \.self) { count in
                segmentButton(count)
            }

            Menu("More") {
                ForEach([48, 64], id: \.self) { count in
                    Button("\(count) bands") { applyBandCount(count) }
                }
                Divider()
                Button("Custom…") {
                    text = "\(store.bandCount)"
                    isEditing = true
                }
            }
            .controlSize(.small)
            .frame(width: 62)

            if ![10, 16, 32, 48, 64].contains(store.bandCount) {
                Text("\(store.bandCount)")
                    .font(.eqT2Medium)
                    .foregroundStyle(Color.eqG60)
            }
        }
    }

    @ViewBuilder
    private func segmentButton(_ count: Int) -> some View {
        let button = Button("\(count)") { applyBandCount(count) }
            .controlSize(.small)
        if store.bandCount == count {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var editingCluster: some View {
        HStack(spacing: 4) {
            StepperButton(symbol: "-", action: { adjustBands(by: -1) })

            // Inline editable band count - matching gain control style
            Group {
                if isEditing {
                    TextField("", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .frame(width: 54)
                        .multilineTextAlignment(.center)
                        .focused($isFocused)
                        .onAppear {
                            text = "\(store.bandCount)"
                            DispatchQueue.main.async {
                                isFocused = true
                            }
                        }
                        .onSubmit(commit)
                        .onChange(of: text) { _, newValue in
                            let digitsOnly = newValue.filter { $0.isNumber }
                            if digitsOnly != newValue {
                                text = digitsOnly
                            }
                        }
                        .onChange(of: isFocused) { _, focused in
                            if !focused {
                                commit()
                            }
                        }
                } else {
                    Text("\(store.bandCount)")
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .frame(width: 54)
                        .onTapGesture {
                            text = "\(store.bandCount)"
                            isEditing = true
                        }
                }
            }

            StepperButton(symbol: "+", action: { adjustBands(by: 1) })
        }
    }

    private func adjustBands(by delta: Int) {
        let newCount = store.bandCount + delta
        applyBandCount(newCount)
    }

    private func commit() {
        guard isEditing else { return }
        defer { isEditing = false }
        if let value = Int(text) {
            applyBandCount(value)
        }
    }

    private func applyBandCount(_ count: Int) {
        let clamped = EQConfiguration.clampBandCount(count)
        let before = store.captureSoundState()
        store.updateBandCount(clamped)
        store.registerSoundUndo(label: "Band count", state: before)
        text = "\(clamped)"
    }
}
