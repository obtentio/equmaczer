// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// C6: the CHECK menu for the compare row — Off / Phone /
/// Laptop / Car — and the caption that appears while a check is
/// running. The caption is part of the feature: an approximation
/// that is not labelled while it is audible would oversell
/// itself, which is the card's named failure mode.
struct TranslationCheckMenu: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject var controller: TranslationCheckController

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Off") { controller.stop() }
                ForEach(TranslationCheck.allCases, id: \.self) { target in
                    Button(target.displayName) { controller.start(target) }
                }
            } label: {
                Text(controller.active.map { "Check · " + $0.displayName } ?? "Check")
                    .font(.eqT1)
                    .foregroundStyle(Color.eqG80)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(store.eqConfiguration.channelMode == .stereo)
            .help(store.eqConfiguration.channelMode == .stereo
                ? "Translation checks borrow the edited channel's bands — switch to Linked to run one"
                : "Hear the current sound through a phone, laptop or car approximation. Your bands are restored when the check stops; edits made during a check are not kept")
        }
        // The standing label, overlaid below the row exactly
        // while an approximation is audible — an unlabelled
        // approximation would oversell itself.
        .overlay(alignment: .topLeading) {
            if let active = controller.active {
                HStack(spacing: 8) {
                    Text("Checking as \(active.displayName.lowercased()) — \(active.account) An approximation of a class of systems, not a simulation.")
                        .font(.eqT0)
                        .foregroundStyle(Color.eqG80)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Stop") { controller.stop() }
                        .font(.eqT0)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.eqG95)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.eqG10)
                .frame(width: 300, alignment: .leading)
                .offset(y: 24)
            }
        }
    }
}
