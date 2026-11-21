import SwiftUI

struct SettingsPanel<Content: View>: View {
    let title: String
    let sub: String
    var isMaster: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(isMaster ? .eqT3 : .eqT1)
                    .foregroundStyle(Color.eqG95)
                Text(sub)
                    .font(.eqT0)
                    .foregroundStyle(Color.eqG60)
                Spacer()

            }
            .contentShape(Rectangle())
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        }
        .padding(10)
        .background(Color.eqG10)
        .overlay(Rectangle().strokeBorder(Color.eqG20, lineWidth: 1))
        .clipped()
    }
}

