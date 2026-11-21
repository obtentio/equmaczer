// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// Proof of processing (B2): a verdict computed only from measured
/// facts — the pipeline's own input/output levels and the pre/post
/// loudness delta — plus two state facts (routing, bypass). Pure,
/// so the judgment is testable as a matrix.
///
/// The honesty line this type is written to: a near-zero loudness
/// delta does NOT prove "not processing" (a loudness-neutral curve
/// measures zero while working exactly as staged), so no verdict
/// says that. What the numbers do prove is reach: if music is
/// playing on the Mac and the input sits at silence, the music is
/// not reaching this app — and the waiting verdict says exactly
/// that.
enum ProcessingProof {
    enum Verdict: Equatable {
        case notRouting
        case bypassed
        case comparingFlat(matchDB: Double)
        case comparingFlatUnmatched
        case comparingFlatUnmeasured
        case waitingForSignal
        case measuringEffect(inputDB: Float, outputDB: Float)
        case processing(inputDB: Float, outputDB: Float, effectLU: Double)
        case flowingNoMeasuredChange(inputDB: Float, outputDB: Float)

        /// The user-facing sentence for the Driver pane.
        var line: String {
            switch self {
            case .notRouting:
                return "Not routing — nothing is being processed."
            case .bypassed:
                return "Bypassed — EQ, gains and limiting off. Volume still applies, so 0% stays silent."
            case .comparingFlat(let matchDB):
                return "Comparing flat — EQ off, held at the EQ path's loudness (\(String(format: "%+.1f", matchDB)) dB match) so the comparison judges tone, not volume."
            case .comparingFlatUnmatched:
                return "Comparing flat — EQ off, no loudness match applied."
            case .comparingFlatUnmeasured:
                return "Comparing flat — EQ off; the loudness match lands once the EQ has been heard."
            case .waitingForSignal:
                return "No signal arriving. If music is playing on this Mac, it isn't reaching equmaczer."
            case .measuringEffect(let inputDB, let outputDB):
                return "Signal flowing — in \(Self.db(inputDB)), out \(Self.db(outputDB)). Measuring the effect…"
            case .processing(let inputDB, let outputDB, let effectLU):
                return "Processing — in \(Self.db(inputDB)), out \(Self.db(outputDB)); measured effect \(String(format: "%+.1f", effectLU)) LU."
            case .flowingNoMeasuredChange(let inputDB, let outputDB):
                return "Signal flowing — in \(Self.db(inputDB)), out \(Self.db(outputDB)); no measured loudness change. A flat or loudness-neutral curve measures like this."
            }
        }

        private static func db(_ value: Float) -> String {
            String(format: "%.1f dB", value)
        }
    }

    /// Input RMS at or below this counts as no signal.
    static let silenceThresholdDB: Float = -70
    /// Loudness deltas smaller than this read as no measured change.
    static let effectThresholdLU = 0.1

    static func verdict(
        routingActive: Bool,
        bypassed: Bool,
        comparingFlat: Bool = false,
        matchEnabled: Bool = false,
        inputRMSDB: Float,
        outputRMSDB: Float,
        effectLU: Double?
    ) -> Verdict {
        guard routingActive else { return .notRouting }
        if bypassed { return .bypassed }
        if comparingFlat {
            // Mode 2 (B7): the EQ is off and the loudness probes
            // are not fed, so the delta is a held measurement, not
            // a live one — the verdict must describe the compare,
            // never render a "processing" claim from the held value.
            guard matchEnabled else { return .comparingFlatUnmatched }
            guard let effectLU else { return .comparingFlatUnmeasured }
            return .comparingFlat(matchDB: min(12.0, max(-12.0, -effectLU)))
        }
        guard inputRMSDB > silenceThresholdDB else { return .waitingForSignal }
        guard let effectLU else {
            return .measuringEffect(inputDB: inputRMSDB, outputDB: outputRMSDB)
        }
        if abs(effectLU) >= effectThresholdLU {
            return .processing(inputDB: inputRMSDB, outputDB: outputRMSDB, effectLU: effectLU)
        }
        return .flowingNoMeasuredChange(inputDB: inputRMSDB, outputDB: outputRMSDB)
    }
}
