// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation
import os.log

/// One OPRA preset: a named author's correction for one product,
/// with the source's own details text (where rig and target live).
struct OpraPreset: Sendable {
    let author: String
    let details: String?
    let link: String?
    let preampDB: Float
    let bands: [PresetBand]
    /// Band types this app cannot stage (band pass / band stop),
    /// counted at parse time and reported at import time.
    let skippedBandCount: Int
}

/// One OPRA product and every preset published for it.
struct OpraProduct: Sendable {
    let id: String
    let name: String
    let vendorName: String?
    var presets: [OpraPreset]
}

/// A parsed OPRA database: the products that carry at least one
/// usable preset, sorted by name.
struct OpraCatalog: Sendable {
    let products: [OpraProduct]
    let skippedLineCount: Int
}

/// Imports OPRA database files (A7).
///
/// OPRA (github.com/opra-project/opra) publishes its database as
/// `database_v1.jsonl`: one JSON object per line —
/// `{"type":"vendor"|"product"|"eq","id":…,"data":{…}}`. An EQ
/// entry names its product in `data.product_id` (the entry's own
/// id is not a reliable join — its product segment uses a different
/// separator), its author, a free-text `details` (rig and target
/// live there, as prose), and parametric bands.
///
/// The data is CC BY-SA 4.0: the preset author's attribution must
/// be prominent and OPRA credited. The importer carries both into
/// the profile (`author`, `sourceDetails`) and the pane shows them;
/// the picker sheet carries the OPRA credit.
///
/// The app ships no OPRA data and fetches none — the user imports
/// the file, like an AutoEq file.
enum OpraImporter {
    private static let logger = Logger(subsystem: "com.obtentio.equmaczer", category: "OpraImporter")

    static func parseCatalog(from url: URL) throws -> OpraCatalog {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw REWImportError.readFailed(error)
        }
        return parseCatalog(text: content)
    }

    static func parseCatalog(text: String) -> OpraCatalog {
        var vendorNames: [String: String] = [:]
        var productInfo: [String: (name: String, vendorID: String?)] = [:]
        var presetsByProduct: [String: [OpraPreset]] = [:]
        var skipped = 0

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String,
                  let entryID = object["id"] as? String,
                  let entry = object["data"] as? [String: Any]
            else {
                skipped += 1
                continue
            }

            switch type {
            case "vendor":
                if let name = entry["name"] as? String {
                    vendorNames[entryID] = name
                }
            case "product":
                if let name = entry["name"] as? String {
                    productInfo[entryID] = (name, entry["vendor_id"] as? String)
                }
            case "eq":
                guard let productID = entry["product_id"] as? String,
                      let preset = parsePreset(entry)
                else {
                    skipped += 1
                    continue
                }
                presetsByProduct[productID, default: []].append(preset)
            default:
                skipped += 1
            }
        }

        var products: [OpraProduct] = []
        for (productID, presets) in presetsByProduct {
            guard let info = productInfo[productID] else { continue }
            products.append(OpraProduct(
                id: productID,
                name: info.name,
                vendorName: info.vendorID.flatMap { vendorNames[$0] },
                presets: presets
            ))
        }
        products.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        logger.info("Parsed OPRA catalog: \(products.count) products, \(skipped) lines skipped")
        return OpraCatalog(products: products, skippedLineCount: skipped)
    }

    private static func parsePreset(_ entry: [String: Any]) -> OpraPreset? {
        guard let author = entry["author"] as? String,
              let parameters = entry["parameters"] as? [String: Any],
              let rawBands = parameters["bands"] as? [[String: Any]]
        else { return nil }

        var bands: [PresetBand] = []
        var skippedBands = 0
        for raw in rawBands {
            guard let typeName = raw["type"] as? String,
                  let frequency = number(raw["frequency"])
            else {
                skippedBands += 1
                continue
            }
            let filterType: FilterType
            switch typeName {
            case "peak_dip": filterType = .parametric
            case "low_shelf": filterType = .lowShelf
            case "high_shelf": filterType = .highShelf
            case "low_pass": filterType = .lowPass
            case "high_pass": filterType = .highPass
            default:
                // band_pass / band_stop: no such stage on the
                // correction layer — skipped, and reported.
                skippedBands += 1
                continue
            }
            bands.append(PresetBand(
                frequency: Float(frequency),
                q: Float(number(raw["q"]) ?? 0.7),
                gain: Float(number(raw["gain_db"]) ?? 0),
                filterType: filterType,
                bypass: false
            ))
        }
        guard !bands.isEmpty else { return nil }

        return OpraPreset(
            author: author,
            details: entry["details"] as? String,
            link: entry["link"] as? String,
            preampDB: Float(number(parameters["gain_db"]) ?? 0),
            bands: bands,
            skippedBandCount: skippedBands
        )
    }

    /// Assembles the correction profile for a chosen preset, with
    /// the AutoEq importer's disciplines: preamp clamped at 0 dB,
    /// bands capped at the correction layer's maximum, every
    /// adjustment reported as a warning.
    static func makeProfile(
        product: OpraProduct,
        preset: OpraPreset,
        deviceUID: String,
        deviceName: String
    ) -> AutoEqImportResult {
        var warnings: [String] = []

        var preampDB = preset.preampDB
        if preampDB > 0 {
            warnings.append("Positive preamp (\(String(format: "%.1f", preampDB)) dB) clamped to 0 dB.")
            preampDB = 0
        }

        var bands = preset.bands
        if bands.count > CorrectionComposer.maxProfileBands {
            warnings.append("Preset has \(bands.count) bands; only the first \(CorrectionComposer.maxProfileBands) fit the correction layer.")
            bands = Array(bands.prefix(CorrectionComposer.maxProfileBands))
        }
        if preset.skippedBandCount > 0 {
            warnings.append("\(preset.skippedBandCount) band(s) skipped — band pass / band stop filters aren't supported on the correction layer.")
        }

        let profile = DeviceCorrectionProfile(
            deviceUID: deviceUID,
            deviceName: deviceName,
            sourceName: "OPRA: \(product.name)",
            author: preset.author,
            sourceDetails: preset.details,
            preampDB: preampDB,
            bands: bands
        )
        return AutoEqImportResult(profile: profile, warnings: warnings)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
