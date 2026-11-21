import Foundation

enum SettingsImport {
    enum ImportError: LocalizedError {
        case tooLarge
        case invalidDocument
        case invalidSettings

        var errorDescription: String? {
            switch self {
            case .tooLarge: "Import rejected — settings files must be no larger than 2 MB"
            case .invalidDocument: "That file is not an equmaczer settings export"
            case .invalidSettings: "Import rejected — invalid EQ or routing settings"
            }
        }
    }

    /// Saved preferences retain their legacy fallback; imports reject an explicitly
    /// invalid capture mode before that fallback can hide it.
    private struct RoutingPreference: Decodable {
        var captureMode: Int?
    }

    static func decode(_ data: Data) throws -> AppStateSnapshot {
        guard data.count <= 2_000_000 else { throw ImportError.tooLarge }
        let decoder = JSONDecoder()
        let snapshot: AppStateSnapshot
        let routing: RoutingPreference
        do {
            routing = try decoder.decode(RoutingPreference.self, from: data)
            snapshot = try decoder.decode(AppStateSnapshot.self, from: data)
        } catch { throw ImportError.invalidDocument }
        if let mode = routing.captureMode, CaptureMode(rawValue: mode) == nil {
            throw ImportError.invalidSettings
        }
        guard isValid(snapshot) else { throw ImportError.invalidSettings }
        return snapshot
    }

    /// A decoded document is not yet safe to use as array-backed audio state.
    static func isValid(_ snapshot: AppStateSnapshot) -> Bool {
        guard snapshot.inputGain.isFinite, snapshot.outputGain.isFinite,
              AudioConstants.gainRange.contains(snapshot.inputGain), AudioConstants.gainRange.contains(snapshot.outputGain),
              snapshot.loudnessStrength.isFinite, (0...1).contains(snapshot.loudnessStrength),
              CaptureMode(rawValue: snapshot.captureMode) != nil else { return false }
        return [snapshot.leftState, snapshot.rightState].allSatisfy { channel in
            guard (1...EQLayerConstants.maxLayerCount).contains(channel.layers.count) else { return false }
            return channel.layers.enumerated().allSatisfy { index, layer in
                guard layer.bands.count == EQConfiguration.maxBandCount,
                      (index == 0 ? 1...EQConfiguration.maxBandCount : 0...EQConfiguration.maxBandCount).contains(layer.activeBandCount)
                else { return false }
                return layer.bands.allSatisfy {
                    $0.frequency.isFinite && $0.frequency > 0 && $0.frequency <= 26001 &&
                    $0.q.isFinite && $0.q > 0 && $0.q <= 100 &&
                    $0.gain.isFinite && AudioConstants.gainRange.contains($0.gain)
                }
            }
        }
    }
}
