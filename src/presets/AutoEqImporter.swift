// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation
import os.log

/// Result of an AutoEq import operation.
struct AutoEqImportResult {
    let profile: DeviceCorrectionProfile
    let warnings: [String]
}

/// Imports AutoEq parametric equaliser settings as a device correction
/// profile.
///
/// AutoEq (github.com/jaakkopasanen/AutoEq) publishes per-headphone
/// corrections as text files:
///
///     Preamp: -6.4 dB
///     Filter 1: ON PK Fc 1957 Hz Gain -2.9 dB Q 1.41
///     Filter 2: ON LSC Fc 105 Hz Gain 4.3 dB Q 0.71
///
/// The filter-line grammar is REW's, so band parsing is delegated to
/// `REWImporter`; this importer owns the header, the preamp line, and
/// the profile assembly (band cap, preamp clamp).
enum AutoEqImporter {
    private static let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "AutoEqImporter")

    /// Imports an AutoEq parametric file for the given device.
    static func importProfile(
        from url: URL,
        deviceUID: String,
        deviceName: String
    ) throws -> AutoEqImportResult {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw REWImportError.readFailed(error)
        }
        let sourceName = "AutoEq: \(url.deletingPathExtension().lastPathComponent)"
        return try parseProfile(
            text: content,
            deviceUID: deviceUID,
            deviceName: deviceName,
            sourceName: sourceName
        )
    }

    /// Parses AutoEq parametric text into a correction profile.
    static func parseProfile(
        text: String,
        deviceUID: String,
        deviceName: String,
        sourceName: String
    ) throws -> AutoEqImportResult {
        var warnings: [String] = []

        // Preamp line: "Preamp: -6.4 dB" (the only header value we need).
        var preampDB: Float = 0
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("preamp:") else { continue }
            let valuePart = trimmed.dropFirst("preamp:".count)
                .replacingOccurrences(of: "dB", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let parsed = Float(valuePart) {
                preampDB = parsed
            } else {
                warnings.append("Could not parse the preamp line; assumed 0 dB (headroom analysis still applies).")
            }
            break
        }
        if preampDB > 0 {
            warnings.append("Positive preamp (\(String(format: "%.1f", preampDB)) dB) clamped to 0 dB.")
            preampDB = 0
        }

        // Bands: REW grammar. Throws REWImportError.noFiltersFound when
        // the file carries no parseable filter lines.
        let bandResult = try REWImporter.parseFilterText(text, filename: sourceName)
        warnings.append(contentsOf: bandResult.warnings)

        var bands = bandResult.bands
        if bands.count > CorrectionComposer.maxProfileBands {
            warnings.append("Profile has \(bands.count) bands; only the first \(CorrectionComposer.maxProfileBands) fit the correction layer.")
            bands = Array(bands.prefix(CorrectionComposer.maxProfileBands))
        }

        let profile = DeviceCorrectionProfile(
            deviceUID: deviceUID,
            deviceName: deviceName,
            sourceName: sourceName,
            preampDB: preampDB,
            bands: bands
        )
        logger.info("Imported AutoEq profile '\(sourceName)' for device \(deviceUID): \(bands.count) bands, preamp \(preampDB) dB")
        return AutoEqImportResult(profile: profile, warnings: warnings)
    }
}
