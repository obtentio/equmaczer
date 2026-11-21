# Recovery 1.3.4

**Latest:** See [the 1.3.5 continuation](CONTINUATION.md) for additional updater/driver lifetime/health repairs, 647 passing tests, CI configuration and installed driver 1.1.3 with verified frame transport. This document preserves the first recovery build's evidence.

20 November 2026. Active source: `equmaczer/working`. Historical `rebrand/` and the `cgpt/` handoff were preserved. This report records the implemented response to `AUDIT.md`; that original audit remains historical evidence, not a description of the repaired checkout.

## Result

The app has been rebuilt, packaged and opened natively as 1.3.4. The main layout, sound-state, import, shortcut and scene defects have repairs with regression coverage. The audio coefficient handoff now has explicit buffer ownership instead of a sequence check around concurrently mutable payloads. The bundle includes driver 1.1.1; the system still has driver 1.1.0. **Driver-side validation is not deployed until the bundled driver is installed through Settings → Driver.**

This is a locally built, ad-hoc-signed recovery candidate. It is not a notarised distribution or a completed hardware/audio acceptance pass.

## What changed

| Audit | Implemented result | Evidence / remaining gate |
|---|---|---|
| A1 | Resolve master and secondary roles before partitioning rectangles. Only visible leaves mount. | Exhaustive role/selection grid at three sizes asserts visible master, containment and disjoint frames. Native promotion checked. |
| A2 | Add summoned tiles to the inventory before role resolution; summon makes the tile master. Split/Join has explicit ownership. | Native Correction master and Split/Join checked; layout regression passes. |
| A3 | Bands page according to available width; Monitoring has Levels/Loudness/Gain tabs; presets and growing lists use pages. | Native Engineer and Measure inspected. Minimum-size native sweep remains open. |
| A4 | Clay supports ordinary frequency/gain dragging; sketch commits through one sound transaction. | Source/build verified. Full gesture and precise-feedback acceptance on all filter types remains open. |
| A5 | Selected Settings pane gets the main area; curve is a small context tile in the category rail. Rules have a vertical editor and explicit pages. | Main-window and standard macOS Settings screenshots inspected; all eight categories present. |
| A6 | Arrangement, master, extra, split and Settings selection persist; selections normalise; Reduce Motion is respected. | Restored Settings selection observed after normal quit/relaunch. Frame-by-frame transition continuity is not certified. |
| B1 | Blend previews from an immutable baseline, zero restores exactly, one applies the full target, both channels and gains participate. Cancel restores; Apply owns one Undo. | Regression tests cover repeated preview, cancellation and complete stereo endpoint. Parameter interpolation is explicitly described; discrete type/bypass changes at 50%. Listening remains open. |
| B2 | Panic is temporary held bypass; release/interruption restores the prior state. Permanent Flatten is separate and handles both channels. | Native P hold/release and Cmd+P preserve the Night curve and System EQ state. Stereo Flatten regression passes. |
| B3 | Snapshot Apply commits through the store transaction, reapplies the pipeline, marks modified and registers Undo. | Snapshot transaction regression passes. Audible verification remains open. |
| B4 | Preset restoration uses explicit Left/Right destinations, independent of focus. | Right-focus regression and full stereo blend test pass. |
| B5 | Immutable sound state per Undo; repeated Flatten no longer shares the latest snapshot. Words offers a bounded proposal followed by Apply/Discard. Snapshot deletion is undoable. | Repeated Flatten and Snapshot Undo tests pass. |
| C1 | Validate import shape/counts/numeric bounds; stage pending import separately so ordinary quit cannot overwrite it. Export is accurately labelled EQ and routing. | Pending-import/save-on-quit and malformed-state tests pass. Complete backup of presets/profiles/rules/keys is not implemented or advertised. |
| C2 | Inert update button is disabled with a truthful explanation. Reset controls state their actual scope; tile reset includes its switches. Login item UI reflects approval status. | Native General inspected. No update distribution service was invented. |
| C3 | Both Settings entrances share the eight-category implementation and selection. Settings catalogue added to the command palette. Visiting Driver does not clear its condition. | Native Cmd+, and main Settings show the same Scenes category; palette navigation inspected. |
| C4 | Unmodified-key policy, owning-window/sheet/text/capture guards, exclusive rebinding and distinct bindings; explicit monitor teardown. Held actions release on key-up, focus loss, sheet or menu interruption. | Modifier policy tests; native P/Cmd+P and palette checked. Full keyboard/accessibility matrix remains open. |
| C5 | Scene engine belongs to app lifetime. Dedicated call-app audio fact is separate from music/film auto-pause logic. | Source and scene tests. This is polled app-audio activity, not microphone ownership or a call-service integration. |
| C6 | Temporary scene override is separate from saved manual pin. Revision checks preserve later manual choices; disabled/edited rules release; interrupted background rules can resume. | Transient pin/manual-choice and interrupted-hour tests pass. Supported payload is channel treatment only. |
| C7 | Full calendar date keys, bounded firing history, injectable clock/calendar, mark only accepted firings and release hour rules at the next hour. | Month-boundary and call-suppression regressions pass. Physical sleep/wake, DST and timezone changes remain acceptance gates. |
| D1 | Shared headers, sentence case, SF Pro/tabular readouts, consistent control corners and neutral controls replace the audited local exceptions. | Source sweep and native screenshots. This is not a complete visual review of every popover/error state. |
| D2 | Brighter label/body/primary inks; WCAG and APCA described separately. | `recovery-contrast.txt` records independent solid-colour calculations. Official pinned APCA implementation/font lookup and translucent/rendered-state checks remain open. |
| D3 | Hidden tiles no longer remain in the view hierarchy; semantic buttons, names and visible edit controls improve focus and activation. Reduce Motion handling added. | Native AX tree contains the visible tiles. VoiceOver and full keyboard traversal still require a dedicated pass. |
| D4 | Only visible tile content mounts; command ownership moves to the root; response graph uses the live sample rate and is labelled manual EQ; OPRA parsing leaves the main actor. | Native layouts/build verified. Instruments allocation/time profiling and a total four-layer graph are not completed. |
| E1 | Random exclusive private file creation, mode 0600 plus coreaudiod ACL; header bounds validation and C11 atomic access. Driver checks path/type/owner/size/link count/permissions before mapping. | Private-mode/unique-name and C11 ABI tests pass; live ACL inspected. Driver builds for arm64 and x86_64. Installed 1.1.0 still needs replacement. No claim of isolation against the same user/admin or completed hostile-process testing. |
| E2 | Preallocated SPSC triple-buffer snapshots with acquire/release ownership transfer; reset generation survives coalesced updates. Bounded consumer work without lock/retry/allocation. | Simultaneous producer/renderer test and Thread Sanitizer pass. Protocol requires one serialised producer and one consumer. |
| E3 | Added release stress path: stereo × four layers × 64 bands, limiting, loudness/spectrum, meters and ring transport, 64 frames at 96 kHz. | Final p50 96.62 µs / p99 147.33 µs against 666.67 µs deadline. Excludes HAL scheduling and physical device latency. |
| E4 | README, architecture and realtime guide updated for the actual backend, permission, persistence, export and publication contracts. | Original audit retained, recovery status separated here. |
| E5 | `working/` is the active source; old checkout preserved. Versioned local bundle and reproducible evidence recorded. | CI, Developer ID signing/notarisation and cross-version hardware release gates remain open. |

## Verification

| Check | Result | Saved evidence |
|---|---|---|
| Baseline suite | 621 passing tests before recovery | `baseline-tests.txt` |
| Final suite | **642 tests, zero failures** | `recovery-tests.txt` |
| Thread Sanitizer | **3 selected tests, zero failures; no reported races** | `recovery-tsan.txt` |
| Release build | Succeeded | `recovery-build.txt` |
| Driver build | Universal arm64/x86_64 bundle succeeded | `recovery-driver-build.txt` |
| Packaging | 1.3.4 app with 1.1.1 driver; deep/strict codesign verification succeeded | `recovery-package.txt` |
| Full DSP stress | p99 147.33 µs, deadline 666.67 µs | `recovery-stress.txt` |
| Contrast | Brighter inks satisfy the recorded independent solid-neutral equation checks | `recovery-contrast.txt` |
| Patch whitespace | `git diff --check` passed | Run locally after edits |

Reproduction commands from the active source root:

```zsh
export SWIFTPM_MODULECACHE_OVERRIDE=/tmp/equmaczer-module-cache
export CLANG_MODULE_CACHE_PATH=/tmp/equmaczer-clang-cache
swift test --disable-sandbox --cache-path /tmp/equmaczer-spm-cache
swift test --disable-sandbox --cache-path /tmp/equmaczer-spm-cache --sanitize=thread --filter PublicationRecoveryTests
./driver/driver.sh bundle --quiet
swift build -c release --build-system native --disable-sandbox --cache-path /tmp/equmaczer-spm-cache -debug-info-format none
EQ_SKIP_BUILD=1 ./bundle.sh app
codesign --verify --deep --strict release/equmaczer.app
release/equmaczer.app/Contents/MacOS/equmaczer --stress-benchmark
```

The default Xcode-backed release engine was blocked at dsymutil by this environment. The native engine with debug information disabled succeeded; it currently emits a deprecation warning. That workaround is recorded rather than silently changing ordinary release defaults. Existing compiler warnings remain in unrelated legacy tests/Core Audio bridging sites; a successful build is not a warning-free claim.

## Native observations

Native access succeeded. The final packaged build opened after the direct native launch helper timed out; opening the exact release bundle through Finder and reconnecting by bundle identifier worked. The visible version and driver-update state identify the new build.

- Engineer: Night curve, 11 bands, five controls on the first page; no overlap at the inspected window size.
- Bands promoted to master: seven controls on its wider page; secondary Layers remained visible.
- Correction summoned as master: Correction occupied the master rectangle, Bands occupied the secondary rectangle. Split changed to Join and exposed Clay; Join returned to the secondary layout.
- Main Settings and Cmd+, Settings: same eight categories and selected Scenes editor; the main pane was fully visible, with the small curve in the rail.
- Held P then release and Cmd+P: System EQ remained on and Night's 105 Hz band remained −3 dB; the curve was not flattened.
- Driver status accurately showed Needs updating; merely viewing Settings did not clear it.

Screenshots and AX trees were inspected during native testing. The final app was left open on Engineer. No claim is made that every screen, smallest supported size or focus path has been visually certified.

## Remaining release gates

1. Install bundled driver 1.1.1 through Settings → Driver with the required macOS administrator interaction, then verify fallback routing and driver reconnection. Its source/build is ready; the installed system driver was not changed by this pass.
2. Perform real listening and frame-delivery checks on both capture backends: cold start, output changes, unplug/replug, Bluetooth, rate changes, sleep/wake and quit/crash recovery. No successful listening test or physical-device transition matrix was completed. QuickTime inspection timed out and the earlier command-line playback attempt failed to start AudioQueue; neither is evidence of audible correctness.
3. Run the minimum-size/long-name UI matrix, VoiceOver, full keyboard access, reduced-motion/increased-contrast and interrupted-hold checks. Mathematical non-overlap does not prove readable content at every native size.
4. Validate rendered contrast using the pinned official APCA package and font guidance; profile UI allocations/drawing/imports with Instruments. Independent token calculations are useful evidence, not certification.
5. Establish CI and a signed/notarised release process, plus macOS 15 and current-version physical-device evidence.

Deliberate scope boundaries: exports contain EQ/routing only; scenes select temporary channel treatments only; response plots describe manual EQ; no automatic update service or complete backup system is claimed. Feature expansion should follow these verified contracts rather than restoring broader promises without implementation.
