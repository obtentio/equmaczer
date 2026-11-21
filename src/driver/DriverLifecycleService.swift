// DriverLifecycleService.swift
// Driver installation and lifecycle management

import Foundation
import CoreAudio
import OSLog

/// Manages driver installation, uninstallation, and status.
@MainActor
public final class DriverLifecycleService: ObservableObject, DriverLifecycleManaging {
    
    // MARK: - Published Properties
    
    @Published public private(set) var status: DriverStatus = .notInstalled
    @Published public var isInstalling: Bool = false
    @Published public var installError: String?
    
    // MARK: - Private Properties
    
    private var installedVersion: String?
    private let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "DriverLifecycleService")
    
    // MARK: - Computed Properties
    
    public var isReady: Bool {
        if case .installed(_) = status {
            return true
        }
        
        // Fallback: check if driver actually exists on disk
        // This handles race conditions during app initialization
        let exists = FileManager.default.fileExists(atPath: DRIVER_BUNDLE_PATH)
        return exists
    }
    
    // MARK: - Initialization
    
    public init() {
        checkInstallationStatus()
    }
    
    // MARK: - Installation
    
    public func installDriver() async throws {
        guard !isInstalling else { return }
        
        isInstalling = true
        installError = nil
        
        do {
            guard let bundledURL = Bundle.main.url(forResource: "equmaczer", withExtension: "driver") else {
                throw DriverError.driverNotFoundInBundle
            }
            
            logger.info("Installing driver from \(bundledURL.path)")
            
            let script = DriverInstallScript.install(source: bundledURL.path,
                directory: DRIVER_INSTALL_PATH, destination: DRIVER_BUNDLE_PATH,
                legacy: LEGACY_DRIVER_BUNDLE_PATH)
            
            try await executeWithAdminPrivileges(script: script)
            
            try await Task.sleep(for: .seconds(2))
            
            checkInstallationStatus()
            
            guard case .installed = status else {
                throw DriverError.installationFailed("The installed driver did not match the bundled update")
            }
            
            logger.info("Driver installed successfully")
            
            // Notify that driver was installed so DeviceManager can refresh
            NotificationCenter.default.post(name: .driverDidInstall, object: nil)
            
        } catch {
            isInstalling = false
            throw error
        }
        
        isInstalling = false
    }
    
    public func uninstallDriver() async throws {
        guard !isInstalling else { return }

        isInstalling = true

        do {
            // D1: if one of our virtual devices is the system
            // default, move the default to a real device first —
            // a default that vanishes lands wherever macOS drops
            // it, which is how the 2026-11-13 silence happened.
            moveDefaultsOffVirtualDevices()

            // Remove both bundles — ours and the pre-rename
            // predecessor's — and restart coreaudiod if either
            // was present.
            let script = "removed=0; if [ -d '\(DRIVER_BUNDLE_PATH)' ]; then rm -rf '\(DRIVER_BUNDLE_PATH)'; removed=1; fi; if [ -d '\(LEGACY_DRIVER_BUNDLE_PATH)' ]; then rm -rf '\(LEGACY_DRIVER_BUNDLE_PATH)'; removed=1; fi; if [ $removed -eq 1 ]; then killall coreaudiod; fi"

            try await executeWithAdminPrivileges(script: script)

            try await Task.sleep(for: .seconds(1))

            checkInstallationStatus()

            // Verified, or it says so: a bundle still on disk
            // means the uninstall did not happen, whatever the
            // script reported.
            let fm = FileManager.default
            if fm.fileExists(atPath: DRIVER_BUNDLE_PATH) || fm.fileExists(atPath: LEGACY_DRIVER_BUNDLE_PATH) {
                throw DriverError.uninstallationFailed("A driver bundle is still present after uninstall")
            }

            logger.info("Driver uninstalled successfully")

            // Notify that driver was uninstalled so DeviceManager can refresh
            NotificationCenter.default.post(name: .driverDidUninstall, object: nil)

        } catch {
            isInstalling = false
            throw error
        }

        isInstalling = false
    }

    // MARK: - Default device rescue (D1)

    /// Moves the system default output/input off our virtual
    /// devices (by UID, or any virtual-transport device carrying
    /// our name) to a real device, built-in preferred. Plain
    /// CoreAudio — no privileges needed for defaults.
    private func moveDefaultsOffVirtualDevices() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let devices = allDeviceIDs(system: system)
        guard !devices.isEmpty else { return }

        func isOurs(_ device: AudioDeviceID) -> Bool {
            if deviceUID(device) == DRIVER_DEVICE_UID { return true }
            guard deviceTransport(device) == kAudioDeviceTransportTypeVirtual else { return false }
            let name = deviceName(device).lowercased()
            return name.contains("equmaczer") || name.contains("equaliser")
        }

        for (selector, scope) in [
            (kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeOutput),
            (kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeInput),
        ] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var current = AudioDeviceID(0)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &current) == noErr,
                  isOurs(current) else { continue }

            let candidates = devices.filter { device in
                device != current && !isOurs(device) && hasStreams(device, scope: scope)
            }
            let replacement = candidates.first { deviceTransport($0) == kAudioDeviceTransportTypeBuiltIn }
                ?? candidates.first
            guard var replacement else { continue }
            let setSize = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = AudioObjectSetPropertyData(system, &address, 0, nil, setSize, &replacement)
            if status == noErr {
                logger.info("Moved a default device off the virtual driver before uninstall")
            } else {
                logger.warning("Could not move a default device before uninstall (status \(status))")
            }
        }
    }

    private func allDeviceIDs(system: AudioObjectID) -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    private func deviceUID(_ device: AudioDeviceID) -> String? {
        stringProperty(device, selector: kAudioDevicePropertyDeviceUID)
    }

    private func deviceName(_ device: AudioDeviceID) -> String {
        stringProperty(device, selector: kAudioDevicePropertyDeviceNameCFString) ?? ""
    }

    private func stringProperty(_ device: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value as String
    }

    private func deviceTransport(_ device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private func hasStreams(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }
    
    // MARK: - Status Checking
    
    public func checkInstallationStatus() {
        logger.debug("Checking installation status...")
        logger.debug("Driver bundle path: \(DRIVER_BUNDLE_PATH)")
        
        let fileExists = FileManager.default.fileExists(atPath: DRIVER_BUNDLE_PATH)
        logger.debug("Driver bundle exists: \(fileExists)")
        
        guard fileExists else {
            logger.warning("Driver not found at \(DRIVER_BUNDLE_PATH)")
            status = .notInstalled
            return
        }
        
        installedVersion = getInstalledDriverVersion()
        let versionStr = installedVersion ?? "unknown"
        logger.debug("Installed version: \(versionStr)")

        let bundledVersion = getBundledDriverVersion()
        logger.debug("Bundled version: \(bundledVersion)")
        status = DriverStatus.evaluate(
            bundleExists: true,
            installedVersion: installedVersion,
            installedBundleID: getInstalledDriverBundleID(),
            bundledVersion: bundledVersion
        )
        
        let statusStr = String(describing: status)
        logger.info("Installation status: \(statusStr)")
    }
    
    // MARK: - Private Helpers
    
    private func getBundledDriverVersion() -> String {
        // Read from bundled driver in app's Resources folder
        guard let resourcePath = Bundle.main.resourcePath else { return "1.0" }
        let driverInfoPath = resourcePath + "/equmaczer.driver/Contents/Info.plist"
        guard let info = NSDictionary(contentsOfFile: driverInfoPath),
              let version = info["CFBundleShortVersionString"] as? String else {
            return "1.0"
        }
        return version
    }
    
    private func getInstalledDriverVersion() -> String? {
        let infoPath = DRIVER_BUNDLE_PATH + "/Contents/Info.plist"
        guard let info = NSDictionary(contentsOfFile: infoPath) else {
            return nil
        }
        return info["CFBundleShortVersionString"] as? String
    }

    private func getInstalledDriverBundleID() -> String? {
        let infoPath = DRIVER_BUNDLE_PATH + "/Contents/Info.plist"
        guard let info = NSDictionary(contentsOfFile: infoPath) else {
            return nil
        }
        return info["CFBundleIdentifier"] as? String
    }
    
    private func executeWithAdminPrivileges(script: String) async throws {
        // Process waiting and administrator interaction must not block AppKit.
        try await Task.detached {
            try Self.runAdminScript(script)
        }.value
    }

    nonisolated private static func runAdminScript(_ script: String) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", "do shell script \(DriverInstallScript.appleScriptLiteral(script)) with administrator privileges"]
        
        let errorPipe = Pipe()
        task.standardOutput = FileHandle.nullDevice
        task.standardError = errorPipe
        
        try task.run()
        // Drain stderr before waiting so a verbose failure cannot fill the pipe.
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw DriverError.installationFailed("Script failed (status \(task.terminationStatus)): \(errorMessage)")
        }
    }
}
