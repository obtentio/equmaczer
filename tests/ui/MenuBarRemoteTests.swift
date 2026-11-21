import AppKit
import SwiftUI
import XCTest
@testable import equmaczer

final class MenuBarRemoteTests: XCTestCase {
    func testTopFiveFallsBackToListOrder() {
        let presets = Array(FactoryPresets.all.reversed())
        XCTAssertEqual(PresetUsage.topFive(presets, counts: [:]).map(\.id), Array(presets.prefix(5)).map(\.id))
    }

    func testTopFiveRanksUsageWithStableTies() {
        let presets = FactoryPresets.all
        let counts = [presets[8].id: 3, presets[7].id: 7, presets[6].id: 3]
        XCTAssertEqual(PresetUsage.topFive(presets, counts: counts).map(\.id),
            [presets[7].id, presets[6].id, presets[8].id, presets[0].id, presets[1].id])
    }

    func testTopFiveHandlesEmptyAndShortListsAndUnknownNames() {
        XCTAssertTrue(PresetUsage.topFive([], counts: ["Gone": 99]).isEmpty)
        let presets = Array(FactoryPresets.all.prefix(2))
        XCTAssertEqual(PresetUsage.topFive(presets, counts: ["Gone": 99]).map(\.id), presets.map(\.id))
    }

    @MainActor
    func testUsagePersistsAndSelectionRestorationDoesNotCount() {
        let suite = "MenuBarRemoteTests.\(UUID())"
        let storage = UserDefaults(suiteName: suite)!
        defer { storage.removePersistentDomain(forName: suite) }
        let manager = PresetManager(storage: storage)
        XCTAssertTrue(manager.useCounts.isEmpty)
        manager.selectPreset(named: "Flat")
        manager.restoreSelection(named: "Flat", modified: true)
        XCTAssertTrue(manager.useCounts.isEmpty)
        manager.recordUse(of: "Flat")
        manager.recordUse(of: "Flat")
        manager.recordUse(of: "Unknown preset")
        let restored = PresetManager(storage: storage)
        XCTAssertEqual(restored.useCounts, ["Flat": 2])
        XCTAssertEqual(restored.mostUsedPresets.first?.id, "Flat")
    }

    func testIconChoiceForActivePowerStates() {
        let active = RoutingStatus.active(inputName: "Input", outputName: "Output")
        XCTAssertEqual(MenuBarIconState.choose(status: active, isBypassed: false), .on)
        XCTAssertEqual(MenuBarIconState.choose(status: active, isBypassed: true), .off)
    }

    func testIconBlockTakesPriorityOverBypass() {
        for status in [RoutingStatus.error("No frames"), .driverNotInstalled] {
            for bypassed in [true, false] {
                XCTAssertEqual(MenuBarIconState.choose(status: status, isBypassed: bypassed), .blocked)
            }
        }
    }

    func testIconDoesNotClaimProcessingWhileIdleOrStarting() {
        for status in [RoutingStatus.idle, .starting] {
            XCTAssertEqual(MenuBarIconState.choose(status: status, isBypassed: false), .off)
            XCTAssertEqual(MenuBarIconState.choose(status: status, isBypassed: true), .off)
        }
    }

    func testSublineAndRealBlockedReason() {
        XCTAssertEqual(RemotePresentation.subtitle(state: .on, paused: true, preset: "Flat", output: "USB"), "Music paused for a call")
        XCTAssertEqual(RemotePresentation.subtitle(state: .on, paused: false, preset: "Flat", output: "USB"), "Flat · USB")
        XCTAssertEqual(RemotePresentation.subtitle(state: .off, paused: false, preset: "Flat", output: "USB"), "Sound passes through untouched")
        XCTAssertEqual(RemotePresentation.blockedReason(status: .error("No audio frames arrived.")), "Sound is blocked. No audio frames arrived.")
        XCTAssertEqual(RemotePresentation.blockedReason(status: .driverNotInstalled,
            driverStatus: .needsUpdate(currentVersion: "1", bundledVersion: "2")),
            "Sound is blocked. The driver needs an update.")
        XCTAssertNil(RemotePresentation.blockedReason(status: .active(inputName: "In", outputName: "Out")))
    }

    /// Set EQ_REMOTE_EVIDENCE to a directory to regenerate the actual SwiftUI remote renders.
    @MainActor
    func testRenderRemoteEvidence() throws {
        guard let path = ProcessInfo.processInfo.environment["EQ_REMOTE_EVIDENCE"] else { return }
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let names = ["Night", "Flat", "Bass", "Voice", "Film"]
        for scenario in ["on", "off", "blocked", "call-rescue", "call-no-mic", "call-one-mic", "dose-80", "update-available"] {
            let state: MenuBarIconState = scenario == "off" ? .off : scenario == "blocked" ? .blocked : .on
            let view = MenuBarRemoteView(
                state: state,
                subtitle: RemotePresentation.subtitle(state: state, paused: scenario.hasPrefix("call"), preset: "Night", output: "MacBook Air Speakers"),
                blockedReason: scenario == "blocked" ? "Sound is blocked. The driver needs an update." : nil,
                presets: names, selectedPreset: "Night", outputGain: .constant(0),
                dosePercent: scenario == "dose-80" ? 80 : 34, hasCall: scenario.hasPrefix("call"),
                updateURL: scenario == "update-available" ? URL(string: "https://github.com/obtentio/equmaczer/releases/tag/v2.0") : nil
            ) {
                CallRescueContent(
                    headset: scenario == "call-no-mic" ? nil : "WH-1000XM5",
                    microphone: scenario == "call-no-mic" ? nil : "MacBook Air Microphone",
                    candidates: scenario == "call-one-mic" ? [("builtin", "MacBook Air Microphone")] : [("builtin", "MacBook Air Microphone"), ("usb", "Shure MV7")],
                    unavailableHeadset: scenario == "call-no-mic" ? "WH-1000XM5" : nil)
            }
            let host = NSHostingView(rootView: view)
            host.appearance = NSAppearance(named: .darkAqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: path).appendingPathComponent("\(scenario).png"))
            XCTAssertEqual(host.bounds.width, 280)
        }
        for state in [MenuBarIconState.on, .off, .blocked] {
            let icon = state.image()
            XCTAssertTrue(icon.isTemplate)
            let bitmap = NSBitmapImageRep(data: try XCTUnwrap(icon.tiffRepresentation))!
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path).appendingPathComponent("icon-\(state).png"))
        }
    }
}
