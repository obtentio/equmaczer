// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// A scene rule (revamp plan §10.9, §10.12): when a signal the app
/// already holds fires, a scene applies itself at zero clicks — a
/// channel treatment, with a receipt and one-tap Undo, releasing
/// when the signal ends. The rules live here; the engine that fires
/// them reads the same store. Priority, stated on the Settings tile:
/// a call outranks everything; otherwise the latest trigger wins.
struct SceneRule: Codable, Identifiable, Equatable {
    enum Trigger: String, Codable, CaseIterable, Identifiable {
        case callApp
        case deviceChange
        case hour

        var id: String { rawValue }

        var title: String {
            switch self {
            case .callApp: return "A call app makes sound"
            case .deviceChange: return "Output device changes"
            case .hour: return "At an hour"
            }
        }
    }

    var id = UUID()
    var trigger: Trigger = .callApp
    var hour: Int = 21
    var channel: AudioChannel = .calls
    var enabled: Bool = true
}

@MainActor
final class SceneRuleStore: ObservableObject {
    static let shared = SceneRuleStore()

    @Published var rules: [SceneRule] = [] {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let defaultsKey = "scenes.rules.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([SceneRule].self, from: data) {
            rules = decoded
        }
    }

    func addRule() {
        rules.append(SceneRule())
    }

    func removeRule(id: UUID) {
        rules.removeAll { $0.id == id }
    }

    func reset() {
        rules = []
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
