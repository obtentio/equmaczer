// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// The Zone A correction pill: at a glance, which device's correction is
/// live (acid dot when a profile is active); one click opens the full
/// correction panel — profiles, AutoEq import, ISO 226 loudness — in a
/// popover, so the panel no longer occupies the main window.
struct CorrectionPillView: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject var controller: CorrectionController

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(controller.activeProfile != nil ? Color.eqG95 : Color.eqG60)
                    .frame(width: 8, height: 8)

                Text(label)
                    .font(.eqT2)
                    .foregroundStyle(Color.eqG95)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.eqG60)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.eqG10)
            .overlay(
                RoundedRectangle(cornerRadius: EQDesign.cornerControl)
                    .strokeBorder(Color.eqG20, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: EQDesign.cornerControl))
        }
        .buttonStyle(.plain)
        .help("Per-device output correction: measured profiles, AutoEq import, and ISO 226 loudness compensation")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            DeviceCorrectionView(store: store, controller: controller)
                .padding(12)
        }
    }

    private var label: String {
        if let profile = controller.activeProfile {
            return "Correction: \(profile.sourceName)"
        }
        if let deviceName = controller.currentDeviceName {
            return "Correction: \(deviceName)"
        }
        return "Correction"
    }
}

#Preview("Correction Pill") {
    let store = EqumaczerStore()
    return CorrectionPillView(store: store, controller: store.correctionController)
        .padding()
}
