import SwiftUI

/// Quiet square controls for the main instrument surface.
struct WindowChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(configuration.isPressed ? Color.eqG20 : Color.eqG10)
            .overlay(Rectangle().stroke(Color.eqG20, lineWidth: 1))
    }
}
