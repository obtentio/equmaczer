// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation
import CoreAudio

protocol AppVolumePersisting {
    func load() -> [String: Float]
    func save(_ volumes: [String: Float])
}

final class AppVolumeStore: AppVolumePersisting {
    private let defaults: UserDefaults
    private let key = "equaliser.appVolumes.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> [String: Float] {
        guard let data = defaults.data(forKey: key),
              let values = try? JSONDecoder().decode([String: Float].self, from: data) else { return [:] }
        return values.filter { $0.value.isFinite && (0..<1).contains($0.value) }
    }
    func save(_ volumes: [String: Float]) {
        if let data = try? JSONEncoder().encode(volumes) { defaults.set(data, forKey: key) }
    }
}

/// A process already observed running audio output by Core Audio.
struct RunningAudioProcess {
    let objectID: AudioObjectID
    let processID: Int32
    let bundleID: String?
}

/// Control-side partition: every process belongs to at most one inclusive tap.
/// Volume apps take precedence over channel membership and skip-EQ exclusions.
enum AppTapPlan {
    /// Command-line players have no bundle identity; keep them audible in
    /// the default channel, excluding our own output to prevent feedback.
    static func includingUnbundledOutput(_ processes: [RunningAudioProcess], ownProcessID: Int32,
                                         assignments: [ChannelTapAssignment]) -> [ChannelTapAssignment] {
        // In global tap mode (no per-app/channel assignments), CoreAudio already taps
        // all processes including unbundled CLI/system sounds (e.g. screencapture).
        // Never spin up ChannelMixer just for a transient unbundled sound.
        guard !assignments.isEmpty else { return assignments }
        let ids = Set(processes.filter {
            ($0.bundleID == nil || $0.bundleID?.isEmpty == true) && $0.processID > 0 &&
                $0.processID != ownProcessID && $0.objectID != kAudioObjectUnknown
        }.map(\.objectID)).subtracting(assignments.flatMap(\.objectIDs))
        guard !ids.isEmpty else { return assignments }
        var result = assignments
        if let index = result.firstIndex(where: { $0.channel == .music && $0.bundleID == nil }) {
            result[index] = ChannelTapAssignment(channel: .music,
                objectIDs: Set(result[index].objectIDs).union(ids).sorted())
        } else {
            result.append(ChannelTapAssignment(channel: .music, objectIDs: ids.sorted()))
        }
        return result
    }

    static func assignments(processes: [String: [AudioObjectID]], channels: [String: AudioChannel],
                            volumes: [String: Float], excluded: Set<String>) -> [ChannelTapAssignment] {
        let apps = processes.keys.filter { volumes[$0] != nil && !processes[$0, default: []].isEmpty }
            .sorted().prefix(ChannelMixer.maximumAppSlots)
        let appIDs = Set(apps)
        var result = AudioChannel.allCases.compactMap { channel -> ChannelTapAssignment? in
            let ids = Set(processes.filter { !appIDs.contains($0.key) && !excluded.contains($0.key) && channels[$0.key] == channel }.values.flatMap { $0 })
            return ids.isEmpty ? nil : ChannelTapAssignment(channel: channel, objectIDs: ids.sorted())
        }
        for id in apps {
            result.append(ChannelTapAssignment(channel: channels[id] ?? .music,
                objectIDs: Array(Set(processes[id, default: []])).sorted(), bundleID: id,
                skipEQ: excluded.contains(id), treatsChannel: channels[id] != nil))
        }
        return result
    }
}
