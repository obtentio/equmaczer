// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// A fully parametric EQ band column.
struct EQBandSliderView: View {
    let index: Int
    let band: EQBandConfiguration
    @Binding var gain: Float
    let frequencyUpdate: (Float) -> Void
    let qUpdate: (Float) -> Void
    let filterTypeUpdate: (FilterType) -> Void
    let bypassUpdate: (Bool) -> Void
    var onNavigateLeft: (() -> Void)? = nil
    var onNavigateRight: (() -> Void)? = nil
    var startEditing: Bool = false
    /// Compact density (32/64-band stages): no permanent editable fields;
    /// the detail popover carries full editing.
    var compact: Bool = false
    var compactGainWidth: CGFloat = 34
    var title: String? = nil
    var onSelect: (() -> Void)? = nil
    @EnvironmentObject private var store: EqumaczerStore
    @State private var editBaseline: SoundState?
    @State private var editGain: Float?

    @State private var isShowingDetail = false
    @State private var isHovered = false
    @State private var dragStartGain: Float? = nil

    var body: some View {
        VStack(spacing: compact ? 3 : 8) {
            if compact {
                compactHeader
            } else {
                header
            }
            slider
                .frame(maxHeight: .infinity)
            if compact {
                InlineEditableValue(value: gain,
                    displayFormatter: { String(format: "%+.1f", $0) },
                    inputFormatter: { String(format: "%.1f", $0) }, width: compactGainWidth, alignment: .center,
                    onCommit: commitGain, onAdjust: AudioConstants.clampGain)
                    .font(.eqT0).lineLimit(1).minimumScaleFactor(0.5)
            } else {
                InlineEditableValue(
                    value: gain,
                    displayFormatter: { $0 >= 0 ? String(format: "+%.1f", $0) : String(format: "%.1f", $0) },
                    inputFormatter: { String(format: "%.1f", $0) },
                    width: 56,
                    alignment: .center,
                    onCommit: { newGain in
                        commitGain(newGain)
                    },
                    onNavigateLeft: onNavigateLeft,
                    onNavigateRight: onNavigateRight,
                    startEditing: startEditing,
                    onAdjust: AudioConstants.clampGain
                )
                .font(.eqT2Medium)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, compact ? 1 : 4)
        // Bypass is structural in v2, never a dim: the column drops
        // to the void with a hairline border, its fill vanishes and
        // its thumb hollows.
        // Territory by outline, not wash (layout pass 2): every
        // column carries the hairline bypassed columns always had,
        // and the fill drops to a whisper — a rule separates the
        // controls from the spectrum behind them; a grey wash
        // muddied both planes into one.
        .background(band.bypass ? Color.eqG00 : Color.eqG10.opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 0 : EQDesign.cornerControl)
                .strokeBorder(Color.eqG20, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: compact ? 0 : EQDesign.cornerControl))
        .frame(width: compact ? nil : 68)
        .onHover { isHovered = $0 }
        .simultaneousGesture(TapGesture().onEnded { onSelect?() })
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
            onSelect?()
            if editBaseline == nil { editBaseline = store.captureSoundState(); editGain = gain }
        }.onEnded { _ in
            if let baseline = editBaseline, editGain != gain { store.registerSoundUndo(label: title.map { "\($0) gain" } ?? "Band \(index + 1) gain", state: baseline) }
            editBaseline = nil; editGain = nil
        })
    }

    private func commitGain(_ value: Float) {
        let before = store.captureSoundState()
        gain = AudioConstants.clampGain(value)
        store.registerSoundUndo(label: title.map { "\($0) gain" } ?? "Band \(index + 1) gain", state: before)
    }

    /// Compact header: just the detail gear, which opens the full editor.
    private var compactHeader: some View {
        HStack(spacing: 0) {
            if let title { Text(title) }
            else {
                Text(band.frequency >= 1000 ? String(format: "%.1fk", band.frequency / 1000) : String(format: "%.0f", band.frequency))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .overlay(alignment: .trailing) {
                        Button { isShowingDetail = true; onSelect?() } label: {
                            Image(systemName: "gearshape").font(.system(size: 9)).padding(2).background(Color.eqG10)
                        }.buttonStyle(.plain)
                        .opacity(isHovered || isShowingDetail ? 1 : 0)
                        .accessibilityLabel("Edit band \(index + 1)")
                        .popover(isPresented: $isShowingDetail) {
                            EQBandDetailPopover(band: band, gainUpdate: commitGain,
                                frequencyUpdate: frequencyUpdate, qUpdate: qUpdate,
                                filterTypeUpdate: filterTypeUpdate, bypassUpdate: bypassUpdate,
                                onClose: { isShowingDetail = false }).frame(width: 240)
                        }
                    }
            }
        }.font(.eqT0).frame(height: 16)
    }

    private var header: some View {
        VStack(alignment: .center, spacing: 4) {
            // The editor door is hover-revealed: eleven permanent
            // gears in a row read as noise and doubled the header
            // height (layout pass, 2026-11-16). Its space is
            // reserved, so the column never jumps; the gear is
            // fully visible while hovered or while its popover
            // is open.
            Button {
                isShowingDetail = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .bold))
                    .padding(4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit band \(index + 1)")
            .opacity(isHovered || isShowingDetail ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .popover(isPresented: $isShowingDetail, arrowEdge: .top) {
                EQBandDetailPopover(
                    band: band,
                    gainUpdate: { newGain in
                        gain = AudioConstants.clampGain(newGain)
                    },
                    frequencyUpdate: frequencyUpdate,
                    qUpdate: qUpdate,
                    filterTypeUpdate: filterTypeUpdate,
                    bypassUpdate: bypassUpdate,
                    onClose: { isShowingDetail = false }
                )
                .frame(width: 240)
            }

            InlineEditableValue(
                value: band.frequency,
                displayFormatter: { String(format: "%.0f Hz", $0) },
                inputFormatter: { String(format: "%.0f", $0) },
                width: 56,
                alignment: .center,
                onCommit: frequencyUpdate,
                delta: 10,
                onAdjust: AudioConstants.clampFrequency
            )
        }
    }

    private var slider: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let normalizedGain = CGFloat((gain - AudioConstants.minGain) / (AudioConstants.maxGain - AudioConstants.minGain))
            let thumbOffset = (0.5 - normalizedGain) * height

            ZStack {
                RoundedRectangle(cornerRadius: compact ? 0 : EQDesign.cornerControl)
                    .fill(Color.eqG20)
                    .frame(width: 8, height: height)

                Rectangle()
                    .fill(Color.eqG60)
                    .frame(width: 12, height: 1)
                    .offset(x: -15)

                // Tick marks every 6 dB from -30 to +30 (excluding 0 and edges)
                ForEach([-30, -24, -18, -12, -6, 6, 12, 18, 24, 30], id: \.self) { db in
                    Rectangle()
                        .fill(Color.eqG35)
                        .frame(width: 10, height: 1)
                        .offset(x: -15, y: (0.5 - CGFloat((Float(db) - AudioConstants.minGain) / (AudioConstants.maxGain - AudioConstants.minGain))) * height)
                }

                // Fill from the bottom to the thumb; a bypassed band
                // shows no fill at all.
                let fillHeight = band.bypass ? 0 : CGFloat((gain - AudioConstants.minGain) / (AudioConstants.maxGain - AudioConstants.minGain)) * height
                let fillOffset = height - fillHeight / 2

                RoundedRectangle(cornerRadius: compact ? 0 : EQDesign.cornerControl)
                    .fill(fillColor)
                    .frame(width: 8, height: fillHeight)
                    .offset(y: fillOffset - height / 2)
                    .animation(.easeOut(duration: 0.08), value: gain)

                // The v2 thumb: a chalk bar, hollow when bypassed.
                Rectangle()
                    .fill(band.bypass ? Color.eqG10 : Color.eqG95)
                    .overlay(
                        Rectangle()
                            .strokeBorder(band.bypass ? Color.eqG60 : Color.clear, lineWidth: 1)
                    )
                    .frame(width: 14, height: 5)
                    .offset(y: thumbOffset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartGain == nil {
                                    dragStartGain = gain
                                }
                                let translation = value.translation.height
                                let gainRange = AudioConstants.maxGain - AudioConstants.minGain
                                let gainDelta = Float(-translation / height * CGFloat(gainRange))
                                let newGain = (dragStartGain ?? 0) + gainDelta
                                gain = AudioConstants.clampGain(newGain)
                            }
                            .onEnded { _ in
                                dragStartGain = nil
                            }
                    )
                    .onTapGesture(count: 2) {
                        gain = 0
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Band \(index + 1) gain")
            .accessibilityValue("\(String(format: "%.1f", gain)) decibels\(band.bypass ? ", bypassed" : "")")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: gain = AudioConstants.clampGain(gain + 1)
                case .decrement: gain = AudioConstants.clampGain(gain - 1)
                @unknown default: break
                }
            }
        }
    }

    private var fillColor: Color {
        .eqG95
    }
}

struct EQBandDetailPopover: View {
    @EnvironmentObject var store: EqumaczerStore

    let gainUpdate: (Float) -> Void
    let frequencyUpdate: (Float) -> Void
    let qUpdate: (Float) -> Void
    let filterTypeUpdate: (FilterType) -> Void
    let bypassUpdate: (Bool) -> Void
    let onClose: () -> Void

    @State private var gain: Float
    @State private var frequency: Float
    @State private var q: Float
    @State private var filterType: FilterType
    @State private var bypass: Bool

    @State private var gainText: String = ""
    @State private var frequencyText: String = ""
    @State private var bandwidthText: String = ""
    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case gain, frequency, bandwidth
    }

    init(band: EQBandConfiguration,
         gainUpdate: @escaping (Float) -> Void,
         frequencyUpdate: @escaping (Float) -> Void,
         qUpdate: @escaping (Float) -> Void,
         filterTypeUpdate: @escaping (FilterType) -> Void,
         bypassUpdate: @escaping (Bool) -> Void,
         onClose: @escaping () -> Void) {
        _gain = State(initialValue: band.gain)
        _frequency = State(initialValue: band.frequency)
        _q = State(initialValue: band.q)
        _filterType = State(initialValue: band.filterType)
        _bypass = State(initialValue: band.bypass)
        _gainText = State(initialValue: String(format: "%.1f", band.gain))
        _frequencyText = State(initialValue: String(format: "%.0f", band.frequency))
        // Bandwidth text is initialized in onAppear based on display mode
        _bandwidthText = State(initialValue: "")
        self.gainUpdate = gainUpdate
        self.frequencyUpdate = frequencyUpdate
        self.qUpdate = qUpdate
        self.filterTypeUpdate = filterTypeUpdate
        self.bypassUpdate = bypassUpdate
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Band options")
                .font(.eqT1)
                .foregroundStyle(Color.eqG60)

            // Gain
            HStack {
                Text("Gain (dB)")
                Spacer()
                TextField("0.0", text: $gainText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .gain)
                    .onSubmit {
                        if let value = Float(gainText) {
                            let clamped = AudioConstants.clampGain(value)
                            gain = clamped
                            gainText = String(format: "%.1f", clamped)
                            gainUpdate(clamped)
                        }
                        focusedField = .frequency
                    }
                    .onKeyPress(.upArrow) {
                        adjustGain(by: 0.1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        adjustGain(by: -0.1)
                        return .handled
                    }
            }

            // Frequency
            HStack {
                Text("Frequency (Hz)")
                Spacer()
                TextField("1000", text: $frequencyText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .frequency)
                    .onSubmit {
                        if let value = Float(frequencyText) {
                            let clamped = AudioConstants.clampFrequency(value)
                            frequency = clamped
                            frequencyText = String(format: "%.0f", clamped)
                            frequencyUpdate(clamped)
                        }
                        focusedField = .bandwidth
                    }
                    .onKeyPress(.upArrow) {
                        adjustFrequency(by: 10)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        adjustFrequency(by: -10)
                        return .handled
                    }
            }

            // Bandwidth / Q Factor
            // UI displays bandwidth or Q based on user preference, but model stores Q.
            // Conversion happens at the boundary.
            HStack {
                Text(bandwidthLabel)
                Spacer()
                TextField("1.0", text: $bandwidthText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .bandwidth)
                    .onSubmit {
                        // parseInput returns the raw value in the mode's unit:
                        // .octaves → bandwidth in octaves, .qFactor → Q factor
                        if let inputValue = BandwidthConverter.parseInput(bandwidthText, mode: store.bandwidthDisplayMode) {
                            let qValue: Float
                            switch store.bandwidthDisplayMode {
                            case .octaves:
                                let clampedBandwidth = BandwidthConverter.clampBandwidth(inputValue)
                                qValue = BandwidthConverter.bandwidthToQ(clampedBandwidth)
                            case .qFactor:
                                qValue = BandwidthConverter.clampQ(inputValue)
                            }
                            q = qValue
                            bandwidthText = BandwidthConverter.formatForInput(q: qValue, mode: store.bandwidthDisplayMode)
                            qUpdate(qValue)
                        }
                    }
                    .onKeyPress(.upArrow) {
                        adjustBandwidth(by: 0.01)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        adjustBandwidth(by: -0.01)
                        return .handled
                    }
            }
            .onAppear {
                bandwidthText = BandwidthConverter.formatForInput(q: q, mode: store.bandwidthDisplayMode)
            }
            .onChange(of: store.bandwidthDisplayMode) { _, newMode in
                bandwidthText = BandwidthConverter.formatForInput(q: q, mode: newMode)
            }

            Divider()

            Picker("Filter Type", selection: $filterType) {
                ForEach(FilterType.allCasesInUIOrder, id: \.self) { type in
                    Text(type.displayName)
                        .tag(type)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: filterType) { _, newValue in
                filterTypeUpdate(newValue)
            }

            Toggle("Bypass Band", isOn: $bypass)
                .onChange(of: bypass) { _, newValue in
                    bypassUpdate(newValue)
                }

            Spacer(minLength: 0)
        }
        .padding(16)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onAppear {
            focusedField = .gain
        }
    }

    private var bandwidthLabel: String {
        switch store.bandwidthDisplayMode {
        case .octaves:
            return "Bandwidth (oct)"
        case .qFactor:
            return "Q Factor"
        }
    }

    private func adjustGain(by delta: Float) {
        let current = Float(gainText) ?? gain
        let newGain = AudioConstants.clampGain(current + delta)
        gain = newGain
        gainText = String(format: "%.1f", newGain)
        gainUpdate(newGain)
    }

    private func adjustFrequency(by delta: Float) {
        let current = Float(frequencyText) ?? frequency
        let newFreq = AudioConstants.clampFrequency(current + delta)
        frequency = newFreq
        frequencyText = String(format: "%.0f", newFreq)
        frequencyUpdate(newFreq)
    }

    private func adjustBandwidth(by delta: Float) {
        guard let current = BandwidthConverter.parseInput(bandwidthText, mode: store.bandwidthDisplayMode) else { return }
        let newValue = current + delta

        let qValue: Float
        switch store.bandwidthDisplayMode {
        case .octaves:
            let clamped = BandwidthConverter.clampBandwidth(newValue)
            qValue = BandwidthConverter.bandwidthToQ(clamped)
        case .qFactor:
            qValue = BandwidthConverter.clampQ(newValue)
        }

        q = qValue
        bandwidthText = BandwidthConverter.formatForInput(q: qValue, mode: store.bandwidthDisplayMode)
        qUpdate(qValue)
    }
}
