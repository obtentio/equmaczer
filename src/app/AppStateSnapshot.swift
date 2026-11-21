// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import AppKit
import AVFoundation
import Foundation
import os.log

struct AppStateSnapshot: Sendable {
    // MARK: - EQ Configuration

    var globalBypass: Bool
    var inputGain: Float
    var outputGain: Float
    var autoPreampEnabled: Bool = true
    var loudnessEnabled: Bool = false
    var loudnessStrength: Float = 0.5
    var loudnessMatchedBypassEnabled: Bool = true
    var spectrumEnabled: Bool = true
    var channelEnabled: Bool = true
    var correctionEnabled: Bool = true

    /// Channel processing mode.
    var channelMode: ChannelMode

    /// Which channel is being edited in stereo mode.
    var channelFocus: ChannelFocus

    /// Left channel EQ state (also used for linked mode).
    var leftState: ChannelEQState

    /// Right channel EQ state (only used in stereo mode).
    var rightState: ChannelEQState

    // MARK: - App State

    var inputDeviceID: String?
    var outputDeviceID: String?
    var bandwidthDisplayMode: String
    var manualModeEnabled: Bool
    var captureMode: Int  // CaptureMode.rawValue

    var automaticUpdateChecksEnabled = true
    var lastUpdateCheckDate: Date?

    var recordingEnabled = false
    var recordingIncludeMic = false
    var recordingMicrophoneUID: String?

    // MARK: - Meter State

    var metersEnabled: Bool

    // MARK: - Defaults

    static var `default`: AppStateSnapshot {
        AppStateSnapshot(
            globalBypass: false,
            inputGain: 0,
            outputGain: 0,
            autoPreampEnabled: true,
            loudnessEnabled: false,
            loudnessStrength: 0.5,
            loudnessMatchedBypassEnabled: true,
            spectrumEnabled: true,
            channelMode: .linked,
            channelFocus: .left,
            leftState: .default(),
            rightState: .default(),
            inputDeviceID: nil,
            outputDeviceID: nil,
            bandwidthDisplayMode: BandwidthDisplayMode.qFactor.rawValue,
            manualModeEnabled: false,
            captureMode: CaptureMode.defaultMode.rawValue,
            metersEnabled: true
        )
    }
}

// MARK: - Codable with Legacy Migration

extension AppStateSnapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case globalBypass
        case inputGain
        case outputGain
        case autoPreampEnabled
        case loudnessEnabled
        case loudnessStrength
        case loudnessMatchedBypassEnabled
        case spectrumEnabled
        case channelEnabled
        case correctionEnabled
        case channelMode
        case channelFocus
        case leftState
        case rightState
        case inputDeviceID
        case outputDeviceID
        case bandwidthDisplayMode
        case manualModeEnabled
        case captureMode
        case recordingEnabled, recordingIncludeMic, recordingMicrophoneUID
        case automaticUpdateChecksEnabled, lastUpdateCheckDate
        case metersEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // EQ configuration
        globalBypass = try container.decode(Bool.self, forKey: .globalBypass)
        inputGain = try container.decode(Float.self, forKey: .inputGain)
        outputGain = try container.decode(Float.self, forKey: .outputGain)
        autoPreampEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoPreampEnabled) ?? true
        loudnessEnabled = try container.decodeIfPresent(Bool.self, forKey: .loudnessEnabled) ?? false
        loudnessStrength = try container.decodeIfPresent(Float.self, forKey: .loudnessStrength) ?? 0.5
        loudnessMatchedBypassEnabled = try container.decodeIfPresent(Bool.self, forKey: .loudnessMatchedBypassEnabled) ?? true
        spectrumEnabled = try container.decodeIfPresent(Bool.self, forKey: .spectrumEnabled) ?? true
        channelEnabled = try container.decodeIfPresent(Bool.self, forKey: .channelEnabled) ?? true
        correctionEnabled = try container.decodeIfPresent(Bool.self, forKey: .correctionEnabled) ?? true
        channelMode = try container.decodeIfPresent(ChannelMode.self, forKey: .channelMode) ?? .linked
        channelFocus = try container.decodeIfPresent(ChannelFocus.self, forKey: .channelFocus) ?? .left
        leftState = try container.decodeIfPresent(ChannelEQState.self, forKey: .leftState) ?? .default()
        rightState = try container.decodeIfPresent(ChannelEQState.self, forKey: .rightState) ?? .default()

        recordingEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordingEnabled) ?? false
        recordingIncludeMic = try container.decodeIfPresent(Bool.self, forKey: .recordingIncludeMic) ?? false
        recordingMicrophoneUID = try container.decodeIfPresent(String.self, forKey: .recordingMicrophoneUID)

        automaticUpdateChecksEnabled = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdateChecksEnabled) ?? true
        lastUpdateCheckDate = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheckDate)

        // App state
        inputDeviceID = try container.decodeIfPresent(String.self, forKey: .inputDeviceID)
        outputDeviceID = try container.decodeIfPresent(String.self, forKey: .outputDeviceID)
        bandwidthDisplayMode = try container.decodeIfPresent(String.self, forKey: .bandwidthDisplayMode)
            ?? BandwidthDisplayMode.qFactor.rawValue
        manualModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .manualModeEnabled) ?? false
        captureMode = CaptureMode.restored(from: try? container.decode(Int.self, forKey: .captureMode)).rawValue
        metersEnabled = try container.decodeIfPresent(Bool.self, forKey: .metersEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode new format only (no legacy fields)
        try container.encode(globalBypass, forKey: .globalBypass)
        try container.encode(inputGain, forKey: .inputGain)
        try container.encode(outputGain, forKey: .outputGain)
        try container.encode(autoPreampEnabled, forKey: .autoPreampEnabled)
        try container.encode(loudnessEnabled, forKey: .loudnessEnabled)
        try container.encode(loudnessStrength, forKey: .loudnessStrength)
        try container.encode(loudnessMatchedBypassEnabled, forKey: .loudnessMatchedBypassEnabled)
        try container.encode(spectrumEnabled, forKey: .spectrumEnabled)
        try container.encode(channelEnabled, forKey: .channelEnabled)
        try container.encode(correctionEnabled, forKey: .correctionEnabled)
        try container.encode(channelMode, forKey: .channelMode)
        try container.encode(channelFocus, forKey: .channelFocus)
        try container.encode(leftState, forKey: .leftState)
        try container.encode(rightState, forKey: .rightState)

        try container.encode(recordingEnabled, forKey: .recordingEnabled)
        try container.encode(recordingIncludeMic, forKey: .recordingIncludeMic)
        try container.encodeIfPresent(recordingMicrophoneUID, forKey: .recordingMicrophoneUID)

        try container.encode(automaticUpdateChecksEnabled, forKey: .automaticUpdateChecksEnabled)
        try container.encodeIfPresent(lastUpdateCheckDate, forKey: .lastUpdateCheckDate)

        // App state
        try container.encodeIfPresent(inputDeviceID, forKey: .inputDeviceID)
        try container.encodeIfPresent(outputDeviceID, forKey: .outputDeviceID)
        try container.encode(bandwidthDisplayMode, forKey: .bandwidthDisplayMode)
        try container.encode(manualModeEnabled, forKey: .manualModeEnabled)
        try container.encode(captureMode, forKey: .captureMode)
        try container.encode(metersEnabled, forKey: .metersEnabled)
    }
}

@MainActor
final class AppStatePersistence {
    private let storage: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private weak var store: EqumaczerStore?
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "AppStatePersistence")

    private enum Keys {
        static let appState = "equalizer.appState"
        static let pendingImport = "equalizer.pendingImport.v1"
    }

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        encoder.outputFormatting = [.sortedKeys]

        // Subscribe to app quit notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    func setStore(_ store: EqumaczerStore) {
        self.store = store
    }

    func stageImport(_ snapshot: AppStateSnapshot) throws {
        guard SettingsImport.isValid(snapshot) else { throw CocoaError(.fileReadCorruptFile) }
        storage.set(try encoder.encode(snapshot), forKey: Keys.pendingImport)
    }

    func load() -> AppStateSnapshot? {
        if let data = storage.data(forKey: Keys.pendingImport),
           let pending = try? decoder.decode(AppStateSnapshot.self, from: data), SettingsImport.isValid(pending) {
            storage.set(data, forKey: Keys.appState)
            storage.removeObject(forKey: Keys.pendingImport)
            return pending
        }
        guard let data = storage.data(forKey: Keys.appState) else { return nil }
        do {
            let snapshot = try decoder.decode(AppStateSnapshot.self, from: data)
            return SettingsImport.isValid(snapshot) ? snapshot : nil
        } catch {
            logger.error("Failed to decode app state: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ snapshot: AppStateSnapshot) {
        do {
            let data = try encoder.encode(snapshot)
            storage.set(data, forKey: Keys.appState)
            logger.debug("Saved app state successfully")
        } catch {
            logger.error("Failed to encode app state: \(error.localizedDescription)")
        }
    }

    @objc private func handleAppWillTerminate(_ notification: Notification) {
        guard let store = store else { return }
        save(store.currentSnapshot)
        logger.info("Saved app state on quit")
    }
}