// equmaczer — modified by obtentio, 2026. Based on work Copyright (C) Christophe Knage and contributors. Licensed under the GNU GPL v3 (see LICENSE).
import Foundation

@MainActor
protocol UpdateChecking: ObservableObject {
    var updateAvailable: Bool { get }
    var latestVersion: String? { get }
    var releaseURL: URL? { get }
    var isChecking: Bool { get }
    func checkForUpdates() async
    func forceCheckForUpdates() async
}
