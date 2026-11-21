import SwiftUI

struct AppsMenuView: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject private var channels: ChannelController
    @State private var isPresented = false
    init(store: EqumaczerStore) {
        self.store = store
        channels = store.channelController
    }
    var body: some View {
        Button("Apps \(channels.playingBundleIDs.count) ▾") { isPresented.toggle() }
            .popover(isPresented: $isPresented) {
                AppsListView(store: store).padding(14).frame(width: 300)
            }
    }
}

struct AppsListView: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject private var channels: ChannelController
    var remote = false
    init(store: EqumaczerStore, remote: Bool = false) {
        self.store = store
        self.remote = remote
        channels = store.channelController
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apps").font(.system(size: 11)).foregroundStyle(RemotePalette.muted)
            if channels.playingBundleIDs.isEmpty {
                Text("No apps playing").foregroundStyle(RemotePalette.muted)
            }
            ForEach(Array(channels.playingBundleIDs.prefix(remote ? 5 : channels.playingBundleIDs.count)), id: \.self) { id in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let icon = ChannelsSettingsTab.appIcon(forBundleID: id) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(ChannelsSettingsTab.appName(forBundleID: id)).lineLimit(1)
                    }
                    AppVolumeSlider(store: store, bundleID: id)
                }
            }
            AppVolumeNotice(store: store)
        }.font(.system(size: 12)).foregroundStyle(RemotePalette.bright)
    }
}

struct AppVolumeNotice: View {
    @ObservedObject var store: EqumaczerStore
    @ObservedObject private var channels: ChannelController
    init(store: EqumaczerStore) { self.store = store; channels = store.channelController }
    var body: some View {
        Group {
            if (store.routingCoordinator.currentCaptureMode ?? store.effectiveCaptureMode) != .processTap {
                Text("Per-app volume needs Process Tap. Moving a slider switches routes.")
            }
            if let notice = store.appVolumeNotice { Text(notice) }
            if channels.playingBundleIDs.filter({ store.appVolumes[$0] != nil }).count > ChannelMixer.maximumAppSlots {
                Text("Only \(ChannelMixer.maximumAppSlots) playing apps can have per-app volume. Set an app back to 100% to make room.")
            }
            if !channels.failedTapChannels.isEmpty {
                Text("An audio tap is unavailable. Some app volumes may not apply.")
            }
            if !store.appVolumes.isEmpty, let notice = store.captureFallbackNotice { Text(notice) }
        }.font(.system(size: 11)).foregroundStyle(RemotePalette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The same hairline/tick vocabulary as the remote's output fader.
struct AppVolumeSlider: View {
    @ObservedObject var store: EqumaczerStore
    let bundleID: String
    private var volume: Float { store.appVolume(for: bundleID) }
    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(RemotePalette.track).frame(height: 1)
                    Rectangle().fill(RemotePalette.bright).frame(width: max(0, geometry.size.width * CGFloat(volume)), height: 1)
                    Rectangle().fill(RemotePalette.bright).frame(width: 1, height: 11)
                        .offset(x: max(0, min(geometry.size.width - 1, geometry.size.width * CGFloat(volume))))
                }.frame(height: 22).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        store.updateAppVolume(bundleID: bundleID,
                            volume: Float(value.location.x / max(1, geometry.size.width)))
                    })
            }.frame(height: 22)
            Text("\(Int((volume * 100).rounded()))%")
                .monospacedDigit().frame(width: 34, alignment: .trailing)
        }.font(.system(size: 12)).foregroundStyle(RemotePalette.bright)
            .accessibilityElement().accessibilityLabel("\(ChannelsSettingsTab.appName(forBundleID: bundleID)) volume")
            .accessibilityValue("\(Int((volume * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                store.updateAppVolume(bundleID: bundleID, volume: volume + (direction == .increment ? 0.01 : -0.01))
            }
    }
}
