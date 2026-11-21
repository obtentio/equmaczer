// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// Capture mode for automatic routing with the equmaczer driver.
///
/// - halInput: Uses HAL input stream (AudioUnitRender). Triggers macOS TCC
///   microphone indicator. Works with any virtual driver in manual mode.
/// - sharedMemory: Uses lock-free shared memory ring buffer. No TCC indicator.
///   No glitches on volume change. Preferred when available.
enum CaptureMode: Int, Codable, CaseIterable, Sendable {
    case halInput = 0
    case sharedMemory = 1
    case processTap = 2

    static let defaultMode: CaptureMode = .processTap  // B1 (11-16): driverless front door; the HAL driver is the full-capability option

    static func restored(from rawValue: Int?) -> CaptureMode {
        rawValue.flatMap(CaptureMode.init(rawValue:)) ?? defaultMode
    }

    var displayName: String {
        switch self {
        case .halInput:
            return "HAL Input"
        case .sharedMemory:
            return "Shared Memory"
        case .processTap:
            return "Process Tap (CATap)"
        }
    }

    var description: String {
        switch self {
        case .halInput:
            return "Uses input stream capture. May show microphone indicator in Control Center."
        case .sharedMemory:
            return "Uses shared memory for lock-free capture. No microphone indicator. Requires equmaczer driver."
        case .processTap:
            return "Uses macOS CoreAudio Process Tap (CATapDescription) slaved to physical output device clock. Zero HAL driver required."
        }
    }
}

/// Result of capture mode determination.
/// Indicates which mode to use and whether permission is needed.
enum CaptureModeDecision: Equatable {
    /// Use this capture mode directly (no permission check needed for this step).
    case useMode(CaptureMode)
    /// Shared memory unavailable - fall back to HAL input (requires mic permission).
    case fallbackToHALInput
}