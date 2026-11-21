/// Stable ties preserve the preset store's list order, including a fresh install.
enum PresetUsage {
    static func topFive(_ presets: [Preset], counts: [String: Int]) -> [Preset] {
        presets.enumerated().sorted {
            let lhs = counts[$0.element.id, default: 0]
            let rhs = counts[$1.element.id, default: 0]
            return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
        }.prefix(5).map(\.element)
    }
}
