// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// The Driver pane's pipeline health (B3): live device and
/// processing rates with the mismatch flagged, transport flow,
/// this app's CPU, and the session's route fallbacks — refreshed
/// once a second while the pane is on screen, like the proof
/// section above it. The audio server's own load is not readable
/// by an unprivileged app; the panel shows the rate mismatch that
/// loads it instead of inventing a figure.
struct PipelineHealthSection: View {
    let store: EqumaczerStore

    @State private var facts = PipelineHealthFacts(activeMode: nil, pipelineRate: nil, outputRate: nil, inputRate: nil)
    @State private var cpuSampler = ProcessCPUSampler()
    @State private var lastFrames: UInt64?
    @State private var lastSampleTime: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionHeader(title: "Pipeline health")

            if case .error(let message) = store.routingStatus {
                Text(message)
                    .font(.eqT2)
                    .foregroundStyle(Color.eqG95)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            }

            ForEach(PipelineHealth.rows(facts), id: \.label) { row in
                SettingsRow(label: row.label) {
                    Text(row.value)
                        .font(.eqT2Medium)
                        .foregroundStyle(row.level == .warn ? Color.eqG95 : Color.eqG80)
                }
            }

            Text(PipelineHealth.headline(facts))
                .font(.eqT2)
                .foregroundStyle(Color.eqG60)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
        }
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func refresh() {
        var next = store.routingCoordinator.healthFacts()
        next.appCPUPercent = cpuSampler.sample()

        let now = ProcessInfo.processInfo.systemUptime
        if let lastFrames, let lastSampleTime, let rate = next.pipelineRate {
            next.transportPercent = PipelineHealth.transportPercent(
                framesDelta: next.inputFramesReceived >= lastFrames ? next.inputFramesReceived - lastFrames : 0,
                seconds: now - lastSampleTime,
                rate: rate
            )
        }
        lastFrames = next.inputFramesReceived
        lastSampleTime = now
        facts = next
    }
}
