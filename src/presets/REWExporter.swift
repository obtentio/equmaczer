import Foundation

/// One ear's filters in the same REW text grammar accepted by REWImporter.
/// Global gain and stereo pairing belong to the native preset format.
enum REWExporter {
    static func export(bands: [PresetBand]) -> String {
        let types: [FilterType: String] = [.parametric: "PK", .lowShelf: "LS", .highShelf: "HS",
            .lowPass: "LP", .highPass: "HP", .bandPass: "BP", .notch: "NOTCH"]
        let lines = bands.enumerated().map { index, band in
            String(format: "Filter %d: %@ %@ Fc %.6f Hz Gain %.6f dB Q %.6f",
                locale: Locale(identifier: "en_US_POSIX"), index + 1, band.bypass ? "OFF" : "ON",
                types[band.filterType]!, band.frequency, band.gain, band.q)
        }
        return (["Filter Settings file", "Equaliser: Generic"] + lines).joined(separator: "\n") + "\n"
    }
}
