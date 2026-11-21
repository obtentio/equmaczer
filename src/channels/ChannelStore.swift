// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation
import os.log

/// Everything the channel system remembers (A3), as one document:
/// which channel each app belongs to (the user's assignments only —
/// built-ins live in `ChannelResolver`), which factory preset treats
/// each channel, and the user's pinned channel if any.
/// What happens to music and other sound while a call or video plays.
enum DuringCallsMode: String, Codable, CaseIterable, Sendable {
    case lower, pause, nothing
}

struct ChannelState: Codable, Equatable {
    /// bundle ID → channel, as assigned by the user in the panel.
    var assignments: [String: AudioChannel] = [:]
    /// channel → factory preset name. Absent means Flat.
    var treatments: [AudioChannel: String] = [:]
    /// When set, this channel's treatment always applies.
    var pinned: AudioChannel?
    /// Channels with Dialogue mode on (A4). Only Film and Calls can
    /// be members — `ChannelController.setDialogue` enforces
    /// `AudioChannel.supportsDialogue`.
    var dialogue: Set<AudioChannel> = []

    /// What to do while a call or video takes the stage (A3). Lower is
    /// the default; a legacy saved Bool `autoPauseEnabled` loads as
    /// Pause (`true`) or Nothing (`false`).
    var duringCalls = DuringCallsMode.lower
    /// B4: watch for a call dropping a Bluetooth headset to
    /// hands-free quality and offer the microphone switch.
    var callCliffSaveEnabled = false

    private enum CodingKeys: String, CodingKey {
        case assignments, treatments, pinned, dialogue, duringCalls, autoPauseEnabled, callCliffSaveEnabled
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assignments = try c.decodeIfPresent([String: AudioChannel].self, forKey: .assignments) ?? [:]
        treatments = try c.decodeIfPresent([AudioChannel: String].self, forKey: .treatments) ?? [:]
        pinned = try c.decodeIfPresent(AudioChannel.self, forKey: .pinned)
        dialogue = try c.decodeIfPresent(Set<AudioChannel>.self, forKey: .dialogue) ?? []
        callCliffSaveEnabled = try c.decodeIfPresent(Bool.self, forKey: .callCliffSaveEnabled) ?? false
        if let raw = try? c.decodeIfPresent(String.self, forKey: .duringCalls) {
            duringCalls = DuringCallsMode(rawValue: raw) ?? .lower
        } else if c.contains(.duringCalls) {
            duringCalls = .lower
        } else if let legacy = try? c.decodeIfPresent(Bool.self, forKey: .autoPauseEnabled) {
            duringCalls = legacy ? .pause : .nothing
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(assignments, forKey: .assignments)
        try c.encode(treatments, forKey: .treatments)
        try c.encodeIfPresent(pinned, forKey: .pinned)
        try c.encode(dialogue, forKey: .dialogue)
        try c.encode(duringCalls, forKey: .duringCalls)
        try c.encode(callCliffSaveEnabled, forKey: .callCliffSaveEnabled)
    }

    /// The preset name treating a channel ("Flat" when unset).
    func treatmentName(for channel: AudioChannel) -> String {
        treatments[channel] ?? "Flat"
    }
}

/// UserDefaults persistence for `ChannelState`, following the
/// `DeviceCorrectionStore` pattern (JSON under one key, injectable
/// defaults so tests use a throwaway suite).
final class ChannelStore {
    private let defaults: UserDefaults
    private let key = "equaliser.channels.v1"
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "ChannelStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ChannelState {
        guard let data = defaults.data(forKey: key) else { return ChannelState() }
        do {
            return try JSONDecoder().decode(ChannelState.self, from: data)
        } catch {
            logger.error("Failed to decode channel state: \(error.localizedDescription)")
            return ChannelState()
        }
    }

    func save(_ state: ChannelState) {
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: key)
        } catch {
            logger.error("Failed to encode channel state: \(error.localizedDescription)")
        }
    }
}
