// DeviceChangeEvent.swift
// Represents device enumeration changes for coordinator consumption

import Foundation

/// Represents device enumeration changes that require coordinator action.
/// Emitted by DeviceEnumerationService when the device list changes in meaningful ways.
enum DeviceChangeEvent: Sendable {
    /// Single built-in device was added (Apple Silicon: headphones plugged in).
    /// Parameter is the newly detected built-in device.
    case builtInDeviceAdded(AudioDevice)
    
    /// Built-in devices were removed (Apple Silicon: headphones unplugged).
    /// Used to clear missing device tracking.
    case builtInDevicesRemoved
    
    /// The currently selected output device is no longer available.
    /// Parameter is the UID of the missing device.
    case selectedOutputMissing(uid: String)

    /// A previously reported-missing selected output device is
    /// available again. Emitted only after a matching
    /// selectedOutputMissing, so it cannot fire on ordinary
    /// device churn. Without it, a coordinator that fell into
    /// its no-device error during a transient absence (a
    /// coreaudiod restart for a driver install, say) had no
    /// signal to retry with — the error was permanent until
    /// relaunch (field report, 2026-11-16).
    case selectedOutputRestored(uid: String)
}