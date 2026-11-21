// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// Settings › Driver › Activity: the journal, paged, never scrolling.
struct ActivitySection: View {
    @ObservedObject var journal: ActivityJournal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "Activity")
            Text("What actually happened, newest first: route changes, channel and scene switches, preset loads and driver events. The last \(journal.capacity) are kept.")
                .font(.eqT2)
                .foregroundStyle(Color.eqG60)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            if journal.events.isEmpty {
                Text("Nothing has happened yet.")
                    .font(.eqT2)
                    .foregroundStyle(Color.eqG60)
            }
            PagedList(items: journal.events, id: \.id, pageSize: 8) { event in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(event.date.formatted(date: .abbreviated, time: .standard))
                        .font(.eqT0)
                        .monospacedDigit()
                        .foregroundStyle(Color.eqG60)
                        .frame(width: 210, alignment: .leading)
                    Text(event.kind.rawValue)
                        .font(.eqT0)
                        .foregroundStyle(Color.eqG60)
                        .frame(width: 52, alignment: .leading)
                    Text(event.text)
                        .font(.eqT2)
                        .foregroundStyle(Color.eqG95)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 8)
    }
}
