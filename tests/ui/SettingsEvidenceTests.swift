import AppKit
import SwiftUI
import XCTest
@testable import equmaczer

@MainActor
final class SettingsEvidenceTests: XCTestCase {
    func testSettingsCategoryOrder() {
        XCTAssertEqual(SettingsTileID.allCases.map(\.title),
            ["Display", "Driver", "Channels", "Hearing", "Keys", "General", "About and legal"])
    }

    /// Render the production panes; set EQ_SETTINGS_EVIDENCE to regenerate review PNGs.
    func testRenderSettingsEvidence() throws {
        guard let path = ProcessInfo.processInfo.environment["EQ_SETTINGS_EVIDENCE"] else { return }
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let storage = UserDefaults(suiteName: "equmaczer.settings-evidence.\(UUID())")!
        let store = EqumaczerStore(persistence: AppStatePersistence(storage: storage),
            channelStore: ChannelStore(defaults: storage), startAutomation: false)
        let rules = SceneRuleStore(defaults: storage)
        rules.rules = [SceneRule(trigger: .callApp, channel: .calls)]
        store.channelController.assign(bundleID: "com.spotify.client", to: .music)
        for category in SettingsTileID.allCases {
            try render(SettingsArrangementView(category: category, sceneRules: rules).environmentObject(store),
                size: NSSize(width: 1280, height: 900), name: category.rawValue, path: path)
        }
        try render(SettingsArrangementView(category: .channels, sceneRules: rules).environmentObject(store),
            size: NSSize(width: 1024, height: 720), name: "channels-stacked", path: path)
    }

    private func render(_ view: some View, size: NSSize, name: String, path: String) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: path).appendingPathComponent("\(name).png"))
    }
}
