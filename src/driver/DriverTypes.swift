// DriverTypes.swift
// Shared types for driver management

import Foundation

// MARK: - Driver Status

/// Driver installation status
public enum DriverStatus: Equatable {
    case notInstalled
    case installed(version: String)
    case needsUpdate(currentVersion: String, bundledVersion: String)
    case error(String)

    /// The status decision, pure so it can be pinned by tests.
    /// The bundle identity is checked before the version: a
    /// driver installed before the identity pass carries the
    /// same version number as the bundled one (1.1.0) under a
    /// different bundle ID, and a version-only comparison calls
    /// that "installed" forever — the app then never offers the
    /// update it ships (field report, 2026-11-16).
    public static func evaluate(
        bundleExists: Bool,
        installedVersion: String?,
        installedBundleID: String?,
        bundledVersion: String
    ) -> DriverStatus {
        guard bundleExists else { return .notInstalled }
        if let installedBundleID, installedBundleID != DRIVER_BUNDLE_ID {
            return .needsUpdate(
                currentVersion: installedVersion ?? "unknown",
                bundledVersion: bundledVersion
            )
        }
        guard let installedVersion else {
            return .installed(version: "unknown")
        }
        if installedVersion.compare(bundledVersion, options: .numeric) == .orderedAscending {
            return .needsUpdate(currentVersion: installedVersion, bundledVersion: bundledVersion)
        }
        return .installed(version: installedVersion)
    }
}

// MARK: - Driver Error

/// Driver-related errors
public enum DriverError: LocalizedError {
    case driverNotFoundInBundle
    case installationFailed(String)
    case uninstallationFailed(String)
    case deviceNotFound
    case propertySetFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .driverNotFoundInBundle:
            return "Driver not found in application bundle"
        case .installationFailed(let message):
            return "Installation failed: \(message)"
        case .uninstallationFailed(let message):
            return "Uninstallation failed: \(message)"
        case .deviceNotFound:
            return "Driver device not found in CoreAudio"
        case .propertySetFailed(let message):
            return "Failed to set driver property: \(message)"
        }
    }
}