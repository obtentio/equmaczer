import SwiftUI

/// Shared manual-response plot, used by Clay, Landscape and Settings context.
struct ResponsePlotView: View {
    @EnvironmentObject var store: EqumaczerStore
    var body: some View {
        ZStack {
            if store.spectrumEnabled { SpectrumCanvas(meterStore: store.meterStore).padding(.horizontal, 12) }
            CompositeCurveCanvas().padding(.horizontal, 12)
        }
        .background(Color.eqG00)
        .accessibilityLabel("Manual EQ frequency response")
    }
}
