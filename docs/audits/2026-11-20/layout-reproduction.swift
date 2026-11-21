import Foundation
import CoreGraphics

struct EQDesign { static let gapOut: CGFloat = 16; static let gapIn: CGFloat = 8 }
enum MainTileID: String, CaseIterable, Identifiable {
    case clay, bands, layers, presets, monitoring
    case correction, hearing, channels, snapshots, history, perApp, words, landscape

    /// The five tiles the named arrangements are built from. The
    /// rest are summoned into Engineer by the Tiles menu.
    static var arrangementTiles: [MainTileID] { [.clay, .bands, .layers, .presets, .monitoring] }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clay: return "Clay"
        case .bands: return "Bands"
        case .layers: return "Layers"
        case .presets: return "Presets"
        case .monitoring: return "Monitoring"
        case .correction: return "Correction"
        case .hearing: return "Hearing"
        case .channels: return "Channels"
        case .snapshots: return "Snapshots"
        case .history: return "History"
        case .perApp: return "Per-app"
        case .words: return "Words"
        case .landscape: return "Landscape"
        }
    }

    /// The arrangement where this tile leads — the Tiles menu's
    /// destination for a pick.
    var homeArrangement: ArrangementID {
        switch self {
        case .clay: return .shape
        case .monitoring: return .measure
        case .bands, .layers, .presets: return .engineer
        case .correction, .hearing, .channels, .snapshots, .history, .perApp, .words, .landscape: return .engineer
        }
    }
}

enum ArrangementID: String, CaseIterable, Identifiable {
    case shape, engineer, measure, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shape: return "Shape"
        case .engineer: return "Engineer"
        case .measure: return "Measure"
        case .settings: return "Settings"
        }
    }
}

struct AuditLayout {
    static var foldGroup: [MainTileID] { [.bands, .layers, .presets] }

    /// Frames + visibility for one state of the window, fold included.
    /// Kept out of the view body: the fold needs real control flow.
    static func layout(in size: CGSize, arrangement: ArrangementID, master: MainTileID, split: MainTileID?, extra: MainTileID? = nil, foldSelection: MainTileID)
        -> (frames: [MainTileID: CGRect], hidden: Set<MainTileID>, folded: Bool, groupFrame: CGRect)
    {
        var frames = frames(in: size, arrangement: arrangement, master: master, split: split)
        var hidden = hiddenTiles(arrangement: arrangement)
        // Every tile outside the arrangement starts hidden.
        for tile in MainTileID.allCases where frames[tile] == nil {
            hidden.insert(tile)
        }
        // A summoned tile tiles into Engineer: in the canonical
        // layout the column cascades down one slot to make room.
        if let extra, arrangement == .engineer, frames[extra] == nil {
            if master == .clay, split == nil,
               let bandsF = frames[.bands], let layersF = frames[.layers], let presetsF = frames[.presets] {
                frames[extra] = bandsF
                frames[.bands] = layersF
                frames[.layers] = presetsF
                hidden.insert(.presets)
                hidden.remove(extra)
            } else if let presetsF = frames[.presets] {
                frames[extra] = presetsF
                hidden.insert(.presets)
                hidden.remove(extra)
            }
        }
        let folded = arrangement == .engineer && split == nil
            && (size.width < 900 || size.height < 500)
            && foldGroup.allSatisfy { frames[$0] != nil }
        var groupFrame: CGRect = .zero
        if folded {
            let fs = foldGroup.compactMap { frames[$0] }
            groupFrame = fs.reduce(fs[0]) { $0.union($1) }
            let inner = CGRect(x: groupFrame.minX, y: groupFrame.minY + 30,
                               width: groupFrame.width, height: groupFrame.height - 30)
            for tile in foldGroup {
                frames[tile] = inner
                if tile != foldSelection { hidden.insert(tile) }
            }
        }
        return (frames, hidden, folded, groupFrame)
    }

    static func hiddenTiles(arrangement: ArrangementID) -> Set<MainTileID> {
        switch arrangement {
        case .shape: return [.bands, .layers, .presets, .monitoring]
        case .engineer: return []
        case .measure: return [.layers, .presets]
        case .settings: return [.bands, .layers, .presets, .monitoring]
        }
    }

    /// The layouts. Every arrangement is the same tiles at different
    /// ratios — nothing is created or destroyed, frames glide.
    static func frames(in size: CGSize, arrangement: ArrangementID, master: MainTileID = .clay, split: MainTileID? = nil) -> [MainTileID: CGRect] {
        var result = baseFrames(in: size, arrangement: arrangement)
        let defaultMaster: MainTileID = arrangement == .measure ? .monitoring : .clay
        // Promotion is a swap: the promoted tile takes the master
        // frame, the old master takes the promoted tile's frame.
        // Nothing is created or destroyed — the continuity law.
        if master != defaultMaster, let masterFrame = result[master], let defaultFrame = result[defaultMaster] {
            result[master] = defaultFrame
            result[defaultMaster] = masterFrame
        }
        // Split: the master frame divides in two; the split partner
        // leaves its own slot and stands beside the master.
        if let split, split != master, result[split] != nil, let f = result[master] {
            let half = (f.width - EQDesign.gapIn) / 2
            result[master] = CGRect(x: f.minX, y: f.minY, width: half, height: f.height)
            result[split] = CGRect(x: f.minX + half + EQDesign.gapIn, y: f.minY, width: half, height: f.height)
        }
        return result
    }

    static func baseFrames(in size: CGSize, arrangement: ArrangementID) -> [MainTileID: CGRect] {
        let out = EQDesign.gapOut
        let gap = EQDesign.gapIn
        let area = CGRect(origin: .zero, size: size)
        switch arrangement {
        case .settings:
            // Never reached: EQWindowView hosts the Settings
            // arrangement itself. Clay alone keeps the switch total.
            return [.clay: area]
        case .shape:
            // Smart gaps: the master alone goes full-bleed.
            return [.clay: area]
        case .engineer:
            let a = area.insetBy(dx: out, dy: out)
            let monitorH: CGFloat = 172
            let topH = a.height - monitorH - gap
            let masterW = (a.width - gap) * 0.60
            let rightX = a.minX + masterW + gap
            let rightW = a.width - masterW - gap
            let bandsH = (topH - 2 * gap) * 0.46
            let layersH = (topH - 2 * gap) * 0.29
            let presetsH = topH - bandsH - layersH - 2 * gap
            return [
                .clay: CGRect(x: a.minX, y: a.minY, width: masterW, height: topH),
                .bands: CGRect(x: rightX, y: a.minY, width: rightW, height: bandsH),
                .layers: CGRect(x: rightX, y: a.minY + bandsH + gap, width: rightW, height: layersH),
                .presets: CGRect(x: rightX, y: a.minY + bandsH + layersH + 2 * gap, width: rightW, height: presetsH),
                .monitoring: CGRect(x: a.minX, y: a.minY + topH + gap, width: a.width, height: monitorH),
            ]
        case .measure:
            let a = area.insetBy(dx: out, dy: out)
            let masterW = (a.width - gap) * 0.62
            let rightX = a.minX + masterW + gap
            let rightW = a.width - masterW - gap
            let clayH = (a.height - gap) * 0.55
            return [
                .monitoring: CGRect(x: a.minX, y: a.minY, width: masterW, height: a.height),
                .clay: CGRect(x: rightX, y: a.minY, width: rightW, height: clayH),
                .bands: CGRect(x: rightX, y: a.minY + clayH + gap, width: rightW, height: a.height - clayH - gap),
            ]
        }
    }
}

func inspect(_ name: String, _ master: MainTileID, _ extra: MainTileID? = nil, _ selection: MainTileID = .bands) {
 let r = AuditLayout.layout(in: CGSize(width: 832, height: 566), arrangement: .engineer, master: master, split: nil, extra: extra, foldSelection: selection)
 let visible = r.frames.filter { !r.hidden.contains($0.key) }
 print(name, "folded:", r.folded, "master visible:", !r.hidden.contains(master))
 for (a, fa) in visible { for (b, fb) in visible where a.rawValue < b.rawValue { if fa.intersects(fb) { print("OVERLAP",a.rawValue,b.rawValue,fa.intersection(fb)) } } }
 if let extra { print("extra frame:", r.frames[extra] ?? .zero) }
}
inspect("promote Layers", .layers)
inspect("summon Correction", .clay, .correction)
inspect("promote Correction", .correction, .correction)
inspect("select Presets after summon", .clay, .correction, .presets)
let m = AuditLayout.frames(in: CGSize(width:832,height:566), arrangement:.measure, master:.monitoring)
print("Measure monitoring available",m[.monitoring]!.width - 20,"fixed content minimum",176+264+216+176)
