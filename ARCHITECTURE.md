# equmaczer architecture

Updated for the 1.3.5 recovery, 20 November 2026. Earlier audit/build reports describe historical revisions; current source and the recovery tests are authoritative.

## State and commands

`EqumaczerStore` owns EQ configuration, feature controllers and the app-lifetime `SceneEngine`. SwiftUI views issue store commands. The configuration is a model, not an automatic audio binding: changes that affect sound must explicitly reach `AudioRoutingCoordinator`.

`SoundCapture` captures both sides of the manual EQ. `SoundState` adds gains, bypass, editing focus and preset identity/modified state. `SoundTransaction.swift` provides grouped model changes, explicit pipeline reapply and immutable undo entries. Preset loading targets channels explicitly. Snapshot and sketch commits use this boundary; blend previews derive from an immutable baseline and restore it on Cancel.

A logical sound transaction is not a claim that all per-channel DSP updates publish in the same hardware callback. Each EQ chain has its own bounded publication mechanism.

## Audio processing

The routing coordinator owns capture choice, lifecycle and fallback. `CaptureRoutePlanner` defines the ordered routes; the frame-delivery watchdog checks actual transport rather than assuming that a successful start delivers frames.

| Route | Capture | Output |
|---|---|---|
| Process Tap | Core Audio process tap | Single-clock aggregate device |
| Shared Memory | Bundled driver and restricted mapped file | HAL output |
| HAL Input | Selected input audio unit and SPSC ring buffers | HAL output |

Each stereo channel has four preallocated layers: manual EQ, device correction, channel treatment and hearing adjustment. `EQCoefficientStager` designs TPT SVF coefficients using one path for both channels and computes headroom. `RenderCallbackContext` processes the cascades, gain stages, limiting and metering; it does not perform file/network I/O.

`EQChain` transfers complete snapshots through three preallocated buffers and one atomic middle-index exchange. Producer and consumer have separate owned buffers; neither accesses the other's current buffer. See the real-time guide for the ownership protocol.

## Workspace and Settings

`EQWindowView` hosts one screen: Clay takes the remaining space, the preset row sits directly beneath it, and Bands take 24% of window height (120–220 pt). Measure occupies a 200 pt column (230 pt in large windows), becoming a strip below the EQ under 900 pt wide. Dense band sets and growing preset collections use explicit pages, never scrolling.

The unified toolbar owns the brand, output picker, Layers and System EQ. Layers reuses the full correction panel and existing hearing/channel/loudness controllers; the manual layer's switch uses its persisted layer bypass flags. Call rescue offers real non-Bluetooth microphones and remembers the chosen UID per headset.

Main commands and temporary key handling live above the workspace. The Edit menu names undo and redo actions; sound transactions retain both immutable endpoints. Settings remains a separate macOS Settings scene, with its existing category state and presentation preserved for card 1c. `SettingsPanel` is its presentation shell, with no tiling mechanics.

## Automation and persistence

Manual channel pins are saved in `ChannelState`. Scene overrides are transient and never written over the saved pin. Manual pin revision changes cancel scene ownership. Call-audio activity is separate from auto-pause's call-plus-music signal. Clock/calendar injection makes hour/date boundaries testable.

`AppStatePersistence` saves normal state on quit. External imports are validated and written to a separate pending key, promoted once on the next launch. Current export covers EQ/routing only; it is not a complete account backup. Scene rules, snapshots and other feature stores have separate persistence.

## Verification

The test suite contains the original DSP/domain tests plus recovery contracts and an intentionally simultaneous coefficient producer/consumer test. Run the latter under Thread Sanitizer. `--benchmark` is the historical ten-band diagnostic; `--stress-benchmark` measures the in-process stereo/four-layer/64-band render stack with limiting, loudness/spectrum and ring transport. Neither certifies real hardware scheduling, end-to-end latency or listening quality.
