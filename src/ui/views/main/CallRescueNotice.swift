import SwiftUI

struct CallRescueNotice: View {
    @ObservedObject var controller: CallCliffController
    var remote = false

    var body: some View {
        CallRescueContent(
            headset: controller.offer?.headsetName,
            microphone: controller.offer?.microphone.name,
            candidates: controller.microphoneCandidates.map { ($0.uid, $0.name) },
            unavailableHeadset: controller.cliffWithoutAlternative ? controller.cliffHeadsetName : nil,
            restore: controller.restoreOffer?.name,
            remote: remote,
            useMicrophone: { controller.switchMicrophone() },
            selectMicrophone: { controller.selectMicrophone(uid: $0); controller.switchMicrophone() },
            restoreMicrophone: { controller.switchBack() }
        )
    }
}

/// Shared presentation also permits deterministic renders without changing system microphones.
struct CallRescueContent: View {
    var headset: String?
    var microphone: String?
    var candidates: [(uid: String, name: String)] = []
    var unavailableHeadset: String?
    var restore: String?
    var remote = true
    var useMicrophone: () -> Void = {}
    var selectMicrophone: (String) -> Void = { _ in }
    var restoreMicrophone: () -> Void = {}

    var body: some View {
        Group {
            if remote {
                VStack(alignment: .leading, spacing: 2) { content }
            } else {
                HStack(spacing: 4) { content }.lineLimit(1)
            }
        }
        .font(.system(size: 12)).foregroundStyle(remote ? RemotePalette.muted : Color.eqG80)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var content: some View {
        if let headset, let microphone {
            Text(remote ? CallRescueCopy.dropped(headset: headset) : CallRescueCopy.title(headset: headset))
            if remote {
                // Text wrapping keeps real, potentially long device names readable at 280 pt.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 3) { microphoneAction(microphone); Text(CallRescueCopy.stereo) }
                    VStack(alignment: .leading, spacing: 2) { microphoneAction(microphone); Text(CallRescueCopy.stereo) }
                }
            } else {
                microphoneAction(microphone)
            }
        } else if let unavailableHeadset {
            Text(CallRescueCopy.noMicrophone(headset: unavailableHeadset))
        } else if let restore {
            Button(CallRescueCopy.restore(microphone: restore), action: restoreMicrophone).buttonStyle(.plain)
        }
    }

    @ViewBuilder private func microphoneAction(_ name: String) -> some View {
        if candidates.count > 1 {
            Menu {
                Button(CallRescueCopy.use(microphone: name), action: useMicrophone)
                Divider()
                ForEach(candidates, id: \.uid) { mic in
                    Button(mic.name) { selectMicrophone(mic.uid) }
                }
            } label: {
                Text(CallRescueCopy.use(microphone: name) + " ▾").underline()
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        } else {
            Button(CallRescueCopy.use(microphone: name), action: useMicrophone)
                .buttonStyle(.plain).underline()
        }
    }
}
