// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).

import Foundation

/// One-time migration of user settings and presets from a legacy
/// defaults domain into this application's domain.
///
/// The legacy domain name is never compiled into the application —
/// it would otherwise be baked into the shipped binary. It arrives
/// via the `-migrateFromLegacyDomain` launch argument, supplied by
/// the local upgrade script on a machine that ran the legacy build
/// (de-branding programme, Slice 4). Ordinary launches never receive
/// the argument and never migrate.
enum IdentityMigrationService {

    /// Defaults key recording that the migration has completed.
    static let completionKey = "com.obtentio.equmaczer.migration.v1.completed"

    /// Launch argument carrying the legacy defaults domain.
    static let domainArgument = "-migrateFromLegacyDomain"

    /// Key prefixes owned by macOS frameworks; never migrated.
    private static let systemKeyPrefixes = ["NS", "Apple", "AK", "PK", "WebKit", "com.apple."]

    /// Copies the legacy domain's application keys into `standard`
    /// when a legacy domain was supplied and the migration has not
    /// already completed. Returns true when data was copied and the
    /// completion sentinel was set. Call before the main store is
    /// created.
    @discardableResult
    static func migrateIfNeeded(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        standard: UserDefaults = .standard
    ) -> Bool {
        guard !standard.bool(forKey: completionKey) else { return false }
        guard let sourceDomain = legacyDomain(from: arguments) else { return false }

        // persistentDomain(forName:) reads only what was stored in
        // that exact domain. dictionaryRepresentation() would merge
        // the global domain in — dozens of system keys the source
        // application never wrote.
        guard let stored = standard.persistentDomain(forName: sourceDomain) else { return false }
        let values = stored.filter { !isSystemKey($0.key) }
        guard !values.isEmpty else { return false }

        for (key, value) in values {
            standard.set(value, forKey: key)
        }

        // Claim completion only when every copied key reads back.
        for (key, value) in values {
            guard let readBack = standard.object(forKey: key),
                  (readBack as? NSObject) == (value as? NSObject) else { return false }
        }
        standard.set(true, forKey: completionKey)
        return true
    }

    /// The legacy domain named by the launch arguments, if present.
    static func legacyDomain(from arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: domainArgument),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// Whether a defaults key belongs to a macOS framework rather
    /// than to the application.
    static func isSystemKey(_ key: String) -> Bool {
        systemKeyPrefixes.contains { key.hasPrefix($0) }
    }
}
