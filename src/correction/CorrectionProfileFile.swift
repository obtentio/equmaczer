import Foundation

/// File routing only; parsing and preview remain in the correction import flow.
enum CorrectionProfileFile: Equatable {
    case autoEq
    case opra

    static func type(for url: URL) -> Self? {
        guard url.isFileURL else { return nil }
        switch url.pathExtension.lowercased() {
        case "txt": return .autoEq
        case "json", "jsonl": return .opra
        default: return nil
        }
    }
}

struct CorrectionFileDrop: Identifiable {
    let id = UUID()
    let url: URL
}
