// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

/// C5: the hearing setup as a ritual — pre-flight, scope, an
/// ordered tune, a summary. The machine is pure; the view drives
/// HearingController's setters and reads the live meter facts.
///
/// A5's law stands throughout: this flow measures nothing. The
/// pre-flight checks *conditions* (sound is arriving, the layer
/// is on), the steps order the listener's own judgments, and the
/// summary reports what was set — never what anyone's hearing
/// "is".
struct HearingRitual {
    enum Step: Int, CaseIterable {
        case preflight = 1
        case scope = 2
        case tune = 3
        case done = 4
    }

    enum Ears: Equatable {
        case together
        case separately
    }

    /// One shelf presentation in the tune step.
    enum Shelf: Equatable {
        case bothLow, bothHigh
        case leftLow, leftHigh, rightLow, rightHigh

        var label: String {
            switch self {
            case .bothLow: return "Low — both ears"
            case .bothHigh: return "High — both ears"
            case .leftLow: return "Low — left ear"
            case .leftHigh: return "High — left ear"
            case .rightLow: return "Low — right ear"
            case .rightHigh: return "High — right ear"
            }
        }
    }

    private(set) var step: Step = .preflight
    var ears: Ears = .separately
    /// 1 = Quick, 2 = Full.
    var passes: Int = 1
    private(set) var pass: Int = 1
    private(set) var shelfIndex: Int = 0

    var shelfOrder: [Shelf] {
        switch ears {
        case .together: return [.bothLow, .bothHigh]
        case .separately: return [.leftLow, .leftHigh, .rightLow, .rightHigh]
        }
    }

    var currentShelf: Shelf? {
        guard step == .tune, shelfIndex < shelfOrder.count else { return nil }
        return shelfOrder[shelfIndex]
    }

    /// Steps are a header, not a lock: any step may be jumped to
    /// at any time (the returning user's shortcut). Entering Tune
    /// restarts the current pass at the first shelf.
    mutating func goTo(_ target: Step) {
        step = target
        if target == .tune {
            pass = 1
            shelfIndex = 0
        }
    }

    /// Confirms the current shelf and advances; after the last
    /// shelf of the last pass, the ritual is done.
    mutating func confirmShelf() {
        guard step == .tune else { return }
        shelfIndex += 1
        if shelfIndex >= shelfOrder.count {
            if pass < passes {
                pass += 1
                shelfIndex = 0
            } else {
                step = .done
            }
        }
    }
}

/// The pre-flight's checkable facts, evaluated. The volume
/// instruction is deliberately absent from the gating: it cannot
/// be checked honestly, so it is stated on the surface and never
/// pretends to be a check.
enum RitualPreflight {
    struct Evaluation: Equatable {
        var routingActive: Bool
        var signalArriving: Bool
        var layerEnabled: Bool

        var canProceed: Bool {
            routingActive && signalArriving && layerEnabled
        }
    }

    /// Silence threshold shared with the processing proof (B2).
    static let silenceThresholdDB: Float = -70

    static func evaluate(
        routingActive: Bool,
        inputRMSDB: Float,
        layerEnabled: Bool
    ) -> Evaluation {
        Evaluation(
            routingActive: routingActive,
            signalArriving: routingActive && inputRMSDB > silenceThresholdDB,
            layerEnabled: layerEnabled
        )
    }
}
