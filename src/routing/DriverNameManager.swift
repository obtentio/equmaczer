// DriverNameManager.swift
// Manages driver device naming with CoreAudio refresh workaround

import Foundation
import OSLog

/// Manages the equmaczer driver's display name.
///
/// The driver name is updated to reflect the current output device:
/// - Automatic mode: "{OutputDeviceName} (equmaczer)"
/// - Manual mode: "equmaczer"
///
/// ## CoreAudio Refresh Workaround
///
/// After renaming the driver, CoreAudio caches the old name. This manager
/// implements a workaround pattern that forces macOS to notice the change:
///
/// 1. Set driver name via CoreAudio property
/// 2. Set output device as default (triggers notification)
/// 3. After delay, set driver as default again (triggers notification)
/// 4. Refresh device list to get updated name
///
/// ## Important: Call Site Responsibility
///
/// This class only handles the UI refresh toggle (steps 2-4). The caller
/// (AudioRoutingCoordinator) is responsible for calling `setDriverAsDefault()`
/// synchronously before starting the audio pipeline to ensure correct routing.
///
/// The delay is necessary because CoreAudio notifications are asynchronous.
@MainActor
final class DriverNameManager {
    
    // MARK: - Dependencies
    
    private let driverAccess: DriverAccessing
    private let systemDefaultObserver: SystemDefaultObserver
    private let deviceProvider: DeviceProviding

    private let logger = Logger(
        subsystem: "com.obtentio.equmaczer",
        category: "DriverNameManager"
    )

    /// Last name applied to the driver; avoids bouncing macOS default output on
    /// same-device reconfigures (which interrupts active recorders like Voice Memos).
    private var lastAppliedName: String?

    // MARK: - Initialization

    init(
        driverAccess: DriverAccessing,
        systemDefaultObserver: SystemDefaultObserver,
        deviceProvider: DeviceProviding
    ) {
        self.driverAccess = driverAccess
        self.systemDefaultObserver = systemDefaultObserver
        self.deviceProvider = deviceProvider
    }
    
    // MARK: - Public API
    
    /// Updates the driver name based on current routing state.
    ///
    /// This method is **synchronous** and returns immediately. It handles:
    /// 1. Setting the driver name
    /// 2. Triggering macOS Control Center refresh (async, scheduled)
    ///
    /// The caller must call `systemDefaultObserver.setDriverAsDefault()` synchronously
    /// after this method returns, before starting the audio pipeline.
    ///
    /// - Parameters:
    ///   - manualMode: Whether manual mode is active
    ///   - selectedOutputUID: The currently selected output device UID
    ///   - selectedOutputDevice: The output device (if available)
    /// - Returns: `true` if name was set successfully, `false` otherwise
    @discardableResult
    func updateDriverName(
        manualMode: Bool,
        selectedOutputUID: String?,
        selectedOutputDevice: AudioDevice?
    ) -> Bool {
        // Manual mode: reset to default name
        guard !manualMode else {
            return resetDriverName(outputUID: selectedOutputUID)
        }
        
        // Automatic mode: need output device and visible driver
        guard let outputUID = selectedOutputUID,
              let outputDevice = selectedOutputDevice,
              driverAccess.isDriverVisible() else {
            logger.warning("updateDriverName: cannot update - no output device or driver not visible")
            return false
        }
        
        let driverName = "\(outputDevice.name) (equmaczer)"
        return setDriverName(driverName, outputUID: outputUID)
    }
    
    // MARK: - Private Implementation
    
    /// Resets driver name to "equmaczer" (manual mode).
    private func resetDriverName(outputUID: String?) -> Bool {
        if lastAppliedName == "equmaczer" { return true }
        let success = driverAccess.setDeviceName("equmaczer")
        if success { lastAppliedName = "equmaczer" }
        
        guard success, let outputUID = outputUID else {
            return success
        }
        
        systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)

        // Schedule UI refresh for 100ms later (fire-and-forget)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.deviceProvider.refreshDevices()
            self?.logger.debug("Device list refreshed after driver name reset")
        }
        
        return success
    }
    
    /// Sets driver name to reflect output device (automatic mode).
    private func setDriverName(_ name: String, outputUID: String) -> Bool {
        if lastAppliedName == name { return true }
        let success = driverAccess.setDeviceName(name)
        if success { lastAppliedName = name }
        
        guard success, driverAccess.deviceID != nil else {
            return success
        }
        
        // Trigger macOS Control Center refresh only when the name actually changed.
        systemDefaultObserver.restoreSystemDefaultOutput(to: outputUID)

        // Schedule UI refresh for 100ms later (fire-and-forget)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.deviceProvider.refreshDevices()
            self?.logger.debug("Device list refreshed after driver name change to '\(name)'")
        }
        
        return success
    }
}