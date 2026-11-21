// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// Persisted captures and the compact language editor, re-homed from tiles.

// MARK: - Snapshots

/// Named captures of the whole curve, kept across launches.
/// SoundCapture is the app's one "put the sound back" mechanism;
/// this store is only its shelf.
@MainActor
final class SnapshotStore: ObservableObject {
    static let shared = SnapshotStore()

    struct Entry: Codable, Identifiable {
        var id = UUID()
        var name: String
        var date: Date
        var leftBands: [EQBandConfiguration]
        var rightBands: [EQBandConfiguration]
        var leftCount: Int
        var rightCount: Int
        var channelMode: ChannelMode

        var capture: SoundCapture {
            SoundCapture(leftBands: leftBands, rightBands: rightBands,
                         leftCount: leftCount, rightCount: rightCount,
                         channelMode: channelMode)
        }
    }

    @Published var entries: [Entry] = [] {
        didSet { persist() }
    }

    private let defaultsKey = "snapshots.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

struct SavedSnapshotsView: View {
    @EnvironmentObject var store: EqumaczerStore
    @ObservedObject private var snapshots = SnapshotStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved snapshots from earlier versions").font(.eqT1)
            if snapshots.entries.isEmpty {
                Text("Use + Save current in the preset row to keep the whole curve.")
                    .font(.eqT2).foregroundStyle(Color.eqG60)
            }
            PagedList(items: snapshots.entries, id: \.id) { entry in
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.eqT2)
                        .foregroundStyle(Color.eqG80)
                        .lineLimit(1)
                    Spacer()
                    Button("Apply") { store.applySoundCapture(entry.capture, label: "Apply snapshot") }
                        .buttonStyle(.plain)
                        .font(.eqT1)
                        .foregroundStyle(Color.eqG95)
                    Button("Delete") {
                        let shelf = snapshots
                        let index = shelf.entries.firstIndex { $0.id == entry.id } ?? 0
                        shelf.remove(id: entry.id)
                        store.registerUndo(label: "Delete snapshot", redo: {
                            guard shelf.entries.contains(where: { $0.id == entry.id }) else { return false }
                            shelf.remove(id: entry.id)
                            return true
                        }) {
                            guard !shelf.entries.contains(where: { $0.id == entry.id }) else { return false }
                            shelf.entries.insert(entry, at: min(index, shelf.entries.count))
                            return true
                        }
                    }
                        .buttonStyle(.plain)
                        .font(.eqT1)
                        .foregroundStyle(Color.eqG60)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Words

/// Plain words for the curve (vocabulary and phrases: `WordParser`). Each known word moves the nearest
/// band by a stated amount — the receipt says exactly what it did.
/// Unknown words are answered honestly, never guessed at.
struct DescribeFieldView: View {
    @EnvironmentObject var store: EqumaczerStore
    @State private var text = ""
    @State private var report: [String] = []
    @State private var pending: [Int: Float] = [:]

    var body: some View {
        TextField("describe…", text: $text)
            .textFieldStyle(.plain)
            .font(.eqT0)
            .padding(5)
            .overlay(Rectangle().stroke(Color.eqG20, lineWidth: 1))
            .onSubmit { apply() }
            .help(report.joined(separator: " · "))
            .popover(isPresented: Binding(get: { !report.isEmpty }, set: { if !$0 { report = [] } })) {
                Text(report.joined(separator: " · ")).font(.eqT1).padding(10).frame(maxWidth: 420)
            }
    }

    private func apply() {
        let plan = WordParser.parse(text)
        var lines: [String] = []
        pending = [:]
        if let unknown = plan.unknownWord {
            report = ["Unknown word: \(unknown). Try warmer, fuller, thinner, brighter, darker, clearer, softer or punchier."]
            return
        }
        if let loose = plan.danglingModifier {
            report = ["“\(loose)” needs a word to go with it — for example “a bit warmer” or “less boomy”."]
            return
        }
        for move in plan.moves {
            guard let index = nearestBand(to: move.frequency) else { continue }
            let band = store.eqConfiguration.bands[index]
            let newGain = max(-18, min(18, (pending[index] ?? band.gain) + move.deltaDB))
            pending[index] = newGain
            lines.append("\(move.phrase) — \(move.effect): \(Self.fmt(band.gain)) → \(Self.fmt(newGain)) dB at \(Self.fmtFreq(band.frequency))")
        }
        report = lines.isEmpty && !plan.moves.isEmpty ? ["Enable a bell or shelf band before proposing a change."] : lines
        if !pending.isEmpty {
            let proposal = pending
            store.performSoundChange(label: "Describe curve") { config in
                for (index, gain) in proposal { config.updateBandGain(index: index, gain: gain) }
            }
            pending = [:]
        }
        text = ""
    }

    private func nearestBand(to frequency: Double) -> Int? {
        let bands = store.eqConfiguration.bands.prefix(store.bandCount)
        guard !bands.isEmpty else { return nil }
        return bands.indices.filter { !bands[$0].bypass && [.parametric, .lowShelf, .highShelf].contains(bands[$0].filterType) }.min {
            abs(log2(Double(bands[$0].frequency) / frequency)) < abs(log2(Double(bands[$1].frequency) / frequency))
        }
    }

    private static func fmt(_ v: Float) -> String { String(format: "%.1f", v) }

    private static func fmtFreq(_ v: Float) -> String {
        v >= 1000 ? String(format: "%.1f kHz", v / 1000) : "\(Int(v)) Hz"
    }
}

