import AppKit
import SwiftUI
import XCTest
@testable import equmaczer

@MainActor
final class ActivityHearingEvidenceTests: XCTestCase {
    /// Set EQ_7_9_EVIDENCE to a folder to regenerate the review PNGs.
    func testRenderActivityAndHearingEvidence() throws {
        guard let path = ProcessInfo.processInfo.environment["EQ_7_9_EVIDENCE"] else { return }
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let storage = UserDefaults(suiteName: "equmaczer.7-9-evidence.\(UUID())")!
        let journal = ActivityJournal(defaults: storage)
        let store = EqumaczerStore(persistence: AppStatePersistence(storage: storage),
            channelStore: ChannelStore(defaults: storage), activityJournal: journal, startAutomation: false)
        // Rows come from the real code paths, not hand-written fixtures.
        if let name = store.presetManager.presets.first?.metadata.name { store.loadPreset(named: name) }
        store.captureMode = .sharedMemory
        store.captureMode = .processTap
        store.switchToAutomaticMode()
        store.channelController.assign(bundleID: "com.spotify.client", to: .music)
        let hearing = HearingController(eqConfiguration: store.eqConfiguration,
            routingCoordinator: store.routingCoordinator, store: HearingStore(defaults: storage))
        hearing.setEnabled(true)
        for (index, db) in [Float(10), 15, 25, 35, 50, 60].enumerated() {
            hearing.setAudiogramThreshold(db, ear: .left, index: index)
        }
        for (index, db) in [Float(10), 10, 20, 30, 40, 45].enumerated() {
            hearing.setAudiogramThreshold(db, ear: .right, index: index)
        }
        try render(DriverSettingsTab(initialPage: "Activity").environmentObject(store),
            name: "activity", path: path)
        try render(HearingSettingsTab(controller: hearing, doseController: store.doseController,
            initialSection: "Audiogram").environmentObject(store), name: "hearing-audiogram", path: path)
        try render(HearingSettingsTab(controller: hearing, doseController: store.doseController)
            .environmentObject(store), name: "hearing-adjustments", path: path)
    }

    private func render(_ view: some View, name: String, path: String) throws {
        let framed = view.padding(24).frame(width: 900, height: 720, alignment: .topLeading)
            .background(Color.black)
        let host = NSHostingView(rootView: framed)
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 720)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: path).appendingPathComponent("\(name).png"))
    }
}
