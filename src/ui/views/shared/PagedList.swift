import SwiftUI

/// Growing collections use explicit pages instead of overflowing a static tile.
struct PagedList<Item, ID: Hashable, Content: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    var pageSize = 5
    @ViewBuilder let row: (Item) -> Content
    @State private var page = 0

    var body: some View {
        let pages = max(1, (items.count + pageSize - 1) / pageSize)
        let current = min(page, pages - 1)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.dropFirst(current * pageSize).prefix(pageSize)), id: id) { item in row(item) }
            if pages > 1 {
                HStack {
                    Button("Previous") { page = max(0, current - 1) }.disabled(current == 0)
                    Spacer()
                    Text("\(current + 1) of \(pages)").font(.eqT0)
                    Spacer()
                    Button("Next") { page = min(pages - 1, current + 1) }.disabled(current == pages - 1)
                }.buttonStyle(.plain)
            }
        }
    }
}
