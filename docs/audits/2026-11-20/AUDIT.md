# equmaczer: independent project and UI/UX audit

20 November 2026 · audited revision `f91cce7232f3bba1cde92db3a5ee69123119d667`

## Verdict

Keep the approved tiling concept. Repair the implementation and the verification process before another visual redesign.

The implementation does not satisfy the concept's central promise: tiles cannot overlap and every promoted job gets usable space. That promise fails in the layout functions themselves. The dominant problem is not insufficient padding. It is a layout system that assigns rectangles without knowing content requirements, then independently applies promotion, summoning and folding to those rectangles. Several new workflows also misrepresent what they do to the sound.

The project has substantial useful engineering: explicit capture-route fallback policies, a frame-delivery watchdog, a shared coefficient designer, composite headroom analysis, separate correction/channel/hearing layers, and a large working test suite. Preserve these. Passing those tests does not establish that the new UI works.

No application implementation was changed for this audit. The deliverables are this report, reproducible failing contract tests, a standalone reproduction of the shipped layout maths, and verification logs. No commit, driver installation, reset or deployment was performed.

## Scope and evidence

- Read the `cgpt/HANDOFF.md` context, design decisions and accompanying change inventory; inspected the actual diff from `879382d` to HEAD and the new implementation.
- Used `working/` as the authoritative checkout: initially clean, the original development branch. `rebrand/` is a separate, extensively modified older checkout; it was inventoried and left intact. It must not be used as a clean rollback source.
- Audited the main window, tiling, Settings, keyboard/veil handling, scene automation, blend, snapshots, presets, state persistence, drawing, capture, coefficient staging, driver lifecycle, build packaging, docs and test coverage. This is a cross-project audit, not a claim that every line has been formally verified.
- Ran the existing XCTest suite: **621 tests, 0 failures**. Debug build also succeeded. See `baseline-tests.txt`.
- Added seven temporary regression tests against public/internal app APIs. **All seven failed, with eight failed assertions.** Preserved them as `RevampAuditEvidenceTests.swift`, outside the active test target. See `regression-results.txt`.
- Executed extracted production layout functions in `layout-reproduction.swift`; reproduced hidden promoted content and overlapping visible frames without relying on screenshots.
- Researched first-party Apple, Swift, W3C, APCA and audio-product documentation. Sources and implications appear below.
- Initial native inspection timed out. After the user enabled access, native screenshot and accessibility inspection succeeded. Inspected the live Engineer, Shape, Measure, in-window Settings/Driver, and standard ⌘, Settings window. **Visible overflow and the mismatched Settings entry points are now directly confirmed.** See the native-validation addendum below. Audio probe playback failed; listening, physical-device transitions, release rebuild and new code-signing verification remain outstanding. The handoff's earlier release/signing claims remain historical claims.

Build command used after ordinary SwiftPM cache and nested-sandbox failures:

```zsh
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/equmaczer-module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/equmaczer-clang-cache \
swift test --disable-sandbox --cache-path /tmp/equmaczer-spm-cache
```

This disables SwiftPM's child-process sandbox for this invocation; it does not grant the agent broader filesystem access or change the app's entitlements.

## What the approved design actually requires

The handoff records approval of Model C, not of the unseen final application. The governing decisions are: a curve-centred tiling window; any tile can become master; minimum tile sizes and folding; SF Pro; neutral rounded surfaces; one actionable sound-blocking red; ordinary names for standard things; continuous spatial transitions; and automatic scenes with receipts, Undo and protection for user edits.

Preserve the latest decisions over earlier drafts. For example, §10.13 makes Tiles the tile-summoning door, so the absence of tile commands from the palette is not itself a defect. The palette still needs to find settings as promised by §10.11. The user's instruction to finish the build waived per-slice verdict pauses; it did not make screenshot inspection, fit checks or interaction validation unnecessary.

The document is not a sufficiently precise implementation contract. It promises infinite or growing collections on fixed, non-scrolling screens, but defines no paging/overflow policy. It says no audio changes while adding automation, blending and panic actions that alter sound state. The handoff also has duplicated build records and unverified market-exclusivity claims. Resolve these contradictions explicitly instead of treating every paragraph as simultaneously implementable.

## Findings

Priority meanings: **P1** blocks reliable use or release; **P2** materially breaks a workflow or the approved language; **P3** is maintenance/documentation debt. These are audit priorities, not claims that every issue has been observed on physical audio hardware.

### A. Layout and interaction

**A1 — P1 — Promotion and folding can hide the master and overlap visible tiles. Reproduced.**

`src/ui/views/main/TilingArea.swift`, `layout()` and `frames()`.

At a tiling-area size of 832 × 566, Engineer with Layers promoted still folds the hard-coded Bands/Layers/Presets group. Layers is hidden because the fold selection remains Bands. The union of the promoted frames crosses the curve's new slot; visible Bands and Clay intersect by 316.8 × 98.02 points. There is no invariant ensuring that the master is excluded from folding. This is a direct contradiction of “overlap impossible by construction”.

Repair: resolve a single layout tree from semantic roles; partition space once; fold secondary roles only. Assert that the master is visible and all visible leaves are disjoint. Never derive a fold region by unioning frames after promotion.

**A2 — P1 — Summoned tiles cannot actually become master; summon/fold states conflict. Reproduced.**

Promotion runs before the extra tile has a frame, so selecting Correction's Master button cannot swap it into the master slot. At the reproduced size it remains a 316.8 × 84.5-point tile instead of the 475.2 × 354-point master. A visible Bands/Correction overlap also occurs. Summoning an extra hides Presets; choosing the Presets fold tab never removes that hidden state, so the selected tab can be blank.

Repair: add the requested tile to the semantic inventory before choosing roles and computing rectangles. Fold selection must refer to an actually available member. Closing/summoning a tile must have one defined space-reclamation rule.

**A3 — P1 — Fixed content sizes make the named arrangements physically unworkable. Source-confirmed dimensions.**

`EQWindowView.swift`, `zoneB` and Bands content; `EQBandSliderView.swift`; `TilingArea.baseFrames()`.

- Monitoring retains fixed widths 176 + 264 + 216 + 176 = **832 points**, plus separators. In Measure at width 832, its master has only **471.04 points of content width** after shell padding. Even Engineer's full-width strip has less than 832 points after outer and shell padding.
- Ten ordinary band columns require at least 10 × 68 + 9 × 10 + 24 = **794 points**. The canonical Engineer sidebar offers roughly 297 points after shell padding at minimum width. Above 16 bands, spacing alone for 64 bands is 630 points before any control widths or padding.
- Band sliders fix their track height at 175 points, before headers, values, margins and the architecture controls. The sidebar Bands slot in the reproduction is only 155.48 points high before shell chrome.
- Presets packs a toolbar, up to 24 chips and destructive controls into a much smaller fixed slot. Clipping is used instead of a content-fit strategy.

Repair: Monitoring needs real tabs/adaptive sublayouts; Bands needs a selected-band editor or explicit band pages at constrained widths; preset cards need paging or a dedicated promoted browser. Breakpoints must depend on required content size and band count, not only window width.

**A4 — P2 — The default Shape view lacks ordinary curve editing. Source-confirmed.**

`src/ui/views/eq/EQBandGridView.swift` and `CompositeCurveCanvas.swift`.

Clay has rendering and an explicitly armed sketch gesture. There is no normal nearest-band curve drag. Shape hides the sliders, so the default daily surface cannot perform the approved direct adjustment without changing arrangements or entering sketch mode. A large graph is not equivalent to a working graph editor.

Repair: implement the specified direct curve gesture with selection and exact frequency/gain feedback; preserve sketch as a separate, explicit proposal workflow. Define behaviour for bypassed, shelf and cut bands.

**A5 — P2 — Settings “master” does not get the master share. Source-confirmed.**

`SettingsArrangementView.swift`, body and `masterContent`.

The curve and selected pane share the remaining width equally after a 208-point mini-tile rail. At width 832, each gets about 288 points before shell padding. Scenes rows alone contain fixed 190- and 110-point pickers, plus a switch, Remove, padding and optional hour control. Calling the pane master does not provide room for its contents. Generic ScrollView wrapping also nests existing scrolling panes and violates the agreed screen model.

Repair: give the selected category actual priority; collapse the curve to an appropriately small contextual view; use a category selector whose width does not dominate the workspace. For growing rules, specify pages and a separate selected-rule editor.

**A6 — P2 — Persistent workspace state and transitions are missing or inconsistent. Source-confirmed.**

`EQWindowView.swift` stores arrangement/master/split/extra only in `@State` and always starts Shape, contrary to the final “where you left it” decision. Arrangement buttons do not normalise the existing master. Settings removes the tiling hierarchy entirely; changing its category uses `.id(selected)` plus an opacity transition, destroying local category state rather than gliding one tile into its new role. Extra-tile changes have no explicit animation value; veils appear conditionally without continuity handling. Split vacates a partner's old slot without redistributing it.

Repair: persist a versioned WorkspaceState; validate every restored state; define transition source/destination identity; separate temporary overlays from durable tile state. Respect Reduce Motion, using stable placement and restrained alternatives.

### B. Sound state and trust

**B1 — P1 — 0% blend changes the sound; the upper endpoint changes semantics. Reproduced/source-confirmed.**

`Veils.swift`, `applyBlend`; `EQWindowView.applyCurrentBlend`.

At 0%, the audit test changes a ten-band curve to three bands and re-enables a bypassed band. Changing band count can also redistribute untouched bands. Partial blends ignore preset bypass/global state and gains, blend only the focused channel, and interpolate parameters by array index. At ≥99.9%, the implementation switches to an ordinary full preset load, which may change both channels, mode, bypass and gains. The endpoint is therefore discontinuous. A halfway parameter interpolation is not mathematically halfway between two frequency responses. The dial itself changes only a number; it provides no audible preview before Apply. No aggregate Undo is registered.

Repair: specify the blend contract first. Zero must be exact identity; one must match the declared target scope; stereo/bypass/topology rules must be explicit; audition must restore on Cancel; commit must register one complete Undo. Use logarithmic frequency interpolation if parameter interpolation remains the chosen model. Do not promise response interpolation without implementing it.

**B2 — P1 — Panic is destructive flattening, not the approved held bypass, and does not clear both stereo sides. Reproduced.**

`EQWindowView.swift`, `onPanic`; `EqumaczerStore.flattenBands()`; `Veils.swift`, `PanicVeil`.

The approved primitive bypasses while held. The implementation permanently flattens the focused user-EQ channel, zeros input/output gain, forces global bypass off, and leaves correction/channel/hearing layers in place. In the test, the right channel remains at −3 dB after Panic's flatten path. The card nevertheless says everything is flat. Zeroing negative trims can increase level. Key release does not restore anything.

Repair: separate emergency/temporary bypass from intentional Flatten. Capture and restore the exact prior processing state on release, focus loss and interruption. Preserve a deliberate permanent Flatten action with its own transaction and Undo.

**B3 — P1 — Snapshot Apply updates the model without the store's audio commit path. Source-confirmed; audible effect not measured.**

`ExtraTiles.swift`, Snapshots Apply → `entry.capture.restore(to: store.eqConfiguration)`; `SoundCapture.swift`; `EqumaczerStore.swift` configuration-change sink and per-band updater paths.

SoundCapture restores configuration directly. The store's subscription only forwards view notifications; it does not reapply the pipeline. Normal store updaters explicitly stage each change; preset load explicitly calls `reapplyConfiguration()`. Snapshot Apply does neither, does not mark the preset modified and registers no Undo. The graph can therefore show state not committed to active audio processing.

Repair: one store-level sound transaction must handle snapshot/preset/sketch/blend/undo commits, stage the pipeline, refresh dependent layers/headroom, mark preset state and issue the receipt. Keep pure capture restoration as an internal mechanism, not a UI command.

**B4 — P1 — Stereo preset load can leave the left channel unchanged when right is focused. Reproduced; predates revamp.**

`PresetManager.applyPreset(_:to:)`, left-band loop.

The left loop calls focused-channel setters; the right loop then explicitly writes Right. With Right focused, both loops write Right and Left is untouched. The regression expected +6 dB in Left but found 0 dB. The partial/full blend threshold also exposes this existing defect.

Repair: always use explicit channel targets for complete preset restoration. Verify linked→stereo, stereo→linked, unequal counts, both focus states and exact round trips.

**B5 — P2 — Undo ownership is incomplete. Source-confirmed.**

`flattenBands`, `undoFlatten`, `PanicVeil`, `WordsTileView`.

Flatten registers closures that read a shared latest `lastFlattenSnapshot`, rather than capturing each action's own state. Repeated flattening overwrites the original recoverable state. Panic calls generic `undoLastAction()` instead of owning a transaction token. Words applies immediate gain edits rather than the plan's proposal/accept workflow, has no grouped Undo and can choose a bypassed band or a filter whose gain does not describe the advertised effect.

Repair: immutable before/after state per undo entry; transaction IDs for temporary workflows; Words must propose and identify the actual edited filter and frequency, then commit as one action.

### C. Settings, scenes and keyboard

**C1 — P1 — Import-for-restart is overwritten on ordinary quit. Source-confirmed control flow.**

`GeneralTileView.importSettings()` saves the imported AppStateSnapshot without applying it. `AppStatePersistence.handleAppWillTerminate()` subsequently saves the still-running store's currentSnapshot to the same key. A normal quit/restart discards the import. Export contains only AppStateSnapshot, not the preset catalogue, scene rules, keys, correction profiles or all other settings advertised by “Settings and presets”. Cancel is also reported as an invalid import.

Repair: define a versioned export envelope and exact inclusion policy. Either apply a validated import atomically to the live store or stage it under a separate pending-import key consumed at launch. Test export/import in a new isolated profile and a real normal quit/restart.

**C2 — P2 — Update and reset controls promise work they do not perform. Source-confirmed.**

`GeneralTileView` and `UpdateCheckService.swift`.

Check now calls an intentionally inert service; the automatic-update preference has no operational consumer. Reset this tile does not reset loudness compensation or auto-preamp. Reset everything clears only keys/general/scenes prefixes, leaving most actual settings and persisted OS login-item registration untouched. Do not ship enabled controls for unavailable operations. Specify and test each reset boundary.

**C3 — P2 — Two Settings paths expose different feature sets. Source-confirmed.**

The toolbar opens the new eight-category arrangement. Standard ⌘, opens the old five-category Settings scene, omitting General, Keys and Scenes. The old pane also clears the update-required flag when merely visited. The palette has no settings catalogue despite the promised settings search. Repair with one shared navigation destination/model reached from all standard doors; viewing a warning must not acknowledge the underlying condition as fixed.

**C4 — P1 — Keyboard monitoring can change sound while handling another command or window. Source-confirmed logic; live event routing unverified.**

`AppKeyMonitor.Coordinator.handle`, `install`, `KeyCaptureMonitor`.

There is no modifier check or owner-window/sheet guard. Cmd+C or Cmd+P can trigger compare/panic when a text field is not first responder. Key capture and action monitors can both react during rebinding. Duplicate bindings are allowed. Hold-compare restores EQ unconditionally instead of the prior state; keyUp is ignored if focus has moved into a text editor, and there is no restoration on app/window deactivation. Toggle state is held separately from actual compareMode and can diverge after another control or the compare timeout changes it.

Important correction to the handoff: `self?.handle(...) ?? event` turns the handler's nil into the original event. **The installed AppKeyMonitor does not swallow the event as claimed.** It can perform an unintended audio action and still let the original command continue. The separate KeyCaptureMonitor directly returns nil and can consume events.

Repair: central command routing, unmodified-key policy, scoped active-window handling, exclusive capture mode, collision validation and exact pre-hold state restoration on every termination path. Explicitly dismantle monitors with the view lifecycle.

**C5 — P1 — Scene trigger semantics do not match the stated trigger. Source-confirmed.**

`SceneEngine.start()` subscribes to `ChannelController.callStageActive`. That signal was built for auto-pause: it requires music to be heard and either a film or a call with live input. A call by itself may not trigger, while film-plus-music can trigger “Call started”. The system uses polled process activity, not the claimed per-app signal ownership. Engine startup lives in the main window's onAppear, so a menu-bar-only session before opening the window has no scene engine.

Repair: dedicated, truthfully named trigger facts; start the engine from app lifecycle; make per-app identity and trigger evidence available for receipts. Keep auto-pause's different definition intact.

**C6 — P1 — Scene release can overwrite user changes and persist a temporary pin. Source-confirmed.**

`SceneEngine.fire/undo/release` and `ChannelController.setPinned`.

The engine saves one prior pin, but never checks whether the user later selected a different pin. Release/Undo restores the old pin anyway. Every automatic pin is persisted by setPinned; a crash/relaunch can turn temporary automation into a remembered preference with no saved scene ownership. Removing/disabling an active rule does not release it. An interrupted device/hour scene is not resumed after a call; only the original baseline pin is restored. Scenes apply no arrangement, output or shape bundle, despite that broader contract.

Repair: separate durable user intent from transient scene overrides, track ownership/revisions and precedence, and release only changes still owned by the scene. Specify the supported scene payload honestly before expanding it.

**C7 — P2 — Hour triggers have calendar and suppression defects. Source-confirmed.**

The fire key contains day-of-month and hour but no month/year. Long-lived sessions collide on the same date in later months. Keys are marked fired before a call can reject the rule, consuming the event without applying it. An already-active rule short-circuits subsequent daily firings; an hour scene has no defined end boundary. Rule edits, sleep/wake, DST and time-zone transitions have no explicit policy. Inject a clock/calendar and test accepted/rejected triggers separately; use complete dates and bounded history.

### D. Language, accessibility and performance

**D1 — P2 — The design-system migration is incomplete. Source-confirmed.**

Numbered pane titles remain verbatim: `01 // DISPLAY`, `02 // DRIVER`, `03 // ABOUT`, `HEARING`, `CHANNELS`. `SettingsPaneTitle` renders its input unchanged. Mono fonts remain in BandCountControl and InlineEditableValue. Band columns retain 2-point corners and hairline outlines. Native red/orange and additional status colours remain in correction, preset and routing code; General uses red for reset and login errors outside the narrowed signal meaning. Native control appearance also needs checking against the dark custom surfaces. Zero `.tracking` calls did not establish language conformance.

Repair: migrate actual components and text, not only tokens. Treat readout abbreviations separately from prose labels. Generate an explicit allowed-exception inventory.

**D2 — P2 — Contrast claims substitute incompatible metrics. Measured/reference-equation check.**

The tokens describe WCAG ratios as equivalents of APCA Lc gates. They are different measurements; that equivalence is invalid. For solid sRGB inks on #181818:

| Ink | WCAG 2 ratio | APCA reverse-polarity Lc, approximately | Claimed plan role |
|---|---:|---:|---|
| #838383 | 4.68:1 | −35.1 | labels, magnitude ≥60 |
| #A4A4A4 | 7.12:1 | −51.9 | body, magnitude ≥75 |
| #D4D4D4 | 11.98:1 | −79.4 | primary |

The Lc values above were independently calculated from the 0.0.98G-family reverse-polarity equations, not certified by running the upstream npm package; confirm with the pinned official implementation before choosing final inks. Even without that calculation, WCAG passing cannot prove APCA passing. Small text additionally needs font-size/weight judgement. Overlays/opacity change rendered contrast; #838383 on #262626 is only 3.99:1. See `contrast-reproduction.py` and the official APCA/W3C references.

**D3 — P2 — Accessibility and hidden-content behaviour lack acceptance coverage. Source gaps; live verification required.**

The tile system hides content with opacity and mouse hit-testing, while keeping every tile mounted. It has no explicit hidden accessibility/focus policy. The motion system never reads accessibilityReduceMotion. Several icon/picker controls lack meaningful names, and preset chips use tap gestures on Text rather than semantic Buttons. Verify VoiceOver order, invisible focus targets, keyboard activation, hover-only detail controls and focus restoration. Do not claim a proven VoiceOver failure solely from an opacity modifier; inspect the resulting tree.

**D4 — P2 — Hidden work and synchronous drawing/imports have no measured budget. Source-confirmed architecture; performance impact unmeasured.**

All 13 tiles are constructed even in Shape, including duplicate graph renderers and feature subviews. A hidden Monitoring subtree owns palette shortcuts and a TranslationCheckController onAppear. Its mounting and work lifetime are accidentally coupled to visibility through opacity. CompositeCurveCanvas constructs a fresh stager at a default 48 kHz on each draw, re-designs coefficients, and shows the focused manual response rather than the full four-layer response. The displayed “whole curve” can disagree with active higher/lower sample-rate processing and added layers. OPRA parsing and several catalogue operations run synchronously on the main actor.

Repair: keep durable models alive but render/subscribe only visible or transitioning content; own commands/controllers above tile visibility; render from an immutable, sample-rate-correct response snapshot. Decide whether each graph means manual or total response and label it accurately. Measure Instruments/Allocations/Time Profiler on a real M1-class target before optimising speculatively.

### E. Wider project findings

**E1 — P1 — Shared-memory audio is still world-readable and world-writable. Source-confirmed; exploit not attempted.**

`SharedMemoryCapture.create()` uses predictable `/tmp/equaliser-audio-<pid>.shm`, unlinks it, opens with O_CREAT|O_RDWR and forces 0666. While that backend is active, other local processes with filesystem access can read or tamper with system audio. Creation has a pathname race and no O_EXCL/O_NOFOLLOW ownership validation. The driver accepts and maps a supplied path without a strong owner/size/type validation contract. The current default is process tap; fallback or an explicit preference still exposes this backend.

Repair separately from UI work: authenticated/validated transport and restricted access for the app/coreaudiod relationship, secure creation and driver-side validation. Add hostile-path/header and truncation tests in an isolated environment. Do not demonstrate attacks against the user's live audio session.

**E2 — P1 — Coefficient staging's sequence check does not prevent concurrent consumption of inconsistent data. Source-confirmed algorithm; no TSan/stress run performed.**

`EQChain.swift`, lines around 125–207.

Main-thread writers update plain pointer-backed coefficient structs. The audio reader checks an even sequence, then copies coefficients directly into live filters. If the writer starts during those reads, the reader can observe concurrently modified fields. It checks the sequence only after changing filters and merely schedules another update; it does not discard that inconsistent state. An atomic sequence counter alone does not make the plain shared payload accesses data-race-free under Swift's memory model. The comments' race-free guarantee is unsupported.

The existing concurrency test explicitly uses semaphores to ensure staging completes before reading. It tests cross-thread handoff, not simultaneous access. Main-thread seriality does not serialise a separate audio callback.

Repair: design a bounded real-time-safe ownership/publication protocol where the writer cannot modify the payload being consumed. Publish only complete validated snapshots; don't add locks or an unbounded retry loop on the audio thread. Run genuinely overlapping producer/consumer tests with TSan and worst-case release stress. Linux seqcount documentation is useful for the copy/validate principle; it is not permission to transplant kernel memory rules into Swift.

**E3 — P2 — Green DSP benchmarks are narrower than the product claims. Source-confirmed.**

The latency benchmark uses ten bands and a chain microbenchmark, not the shipped worst case of stereo, multiple active layers, up to 64 user bands per side, limiting, metering and capture/output integration. The measured test result is useful but cannot certify the full callback deadline or actual end-to-end latency. Add realistic release benchmarks and device transition testing; retain the current microbenchmarks as diagnostics.

**E4 — P2 — Public docs and engineering guides are stale enough to misdirect future work. Source-confirmed.**

README claims light/dark adaptation, launch-time microphone prompting and shared-memory default despite current dark-token design, deferred permission logic and process-tap default. Screenshots predate the redesign. Architecture/realtime docs describe old biquad/vDSP staging and a flag-based publication pattern rather than the current TPT-SVF chain. Some advice confuses task suspension with blocking. Earlier audit reports identify already-fixed issues as current. Add a version/revision header and separate historical findings from open ones.

**E5 — P3 — Release and repository ownership need an explicit baseline.**

There is no checked-in CI workflow in the audited checkout. bundle.sh produces ad-hoc-signed output; successful codesign verification is not evidence of a notarised distribution build or functional audio routing. `working/` and dirty `rebrand/` are easy to confuse. Select and document one active source root, preserve the historical checkout, and define build/test/screenshot/device evidence per release. Do not treat the old checkout as expendable.

## Corrections to earlier audit/handoff claims

| Earlier claim | Current evidence |
|---|---|
| No audio files changed, so listening behaviour is unchanged by construction | The diff does avoid DSP/pipeline/driver files. New UI actions and automation still alter band, gain, bypass and channel state; unchanged internals do not prove unchanged behaviour. |
| AppKeyMonitor swallows bound keys | Its `?? event` wrapper returns the original event. Unwanted side effects remain possible. |
| ProcessTapCapture is dead code | Stale. RenderPipeline instantiates it and owns teardown; current defaults prefer it. |
| Left and right use different coefficient designers | Stale for current EQCoefficientStager, which shares designCoefficient. A different, reproduced stereo preset focus bug remains. |
| HeadroomAnalyzer has no production callers | Stale. Current coefficient staging computes cascade data and preamp. |
| All caps/numbering/mono were removed | False for actual pane titles and local controls; see D1. |
| The full feature inventory was built | No: some gaps are honestly recorded, while other shipped controls are inert or substantially narrower than their contract. |
| Competitors have none of these capabilities | Not established by the available local research. Current Pro-Q documentation explicitly describes sketch and direct graph editing; eqMac documents graphical parametric EQ and arrangement customisation. Drop universal exclusivity claims unless systematically verified. |

## Research synthesis: what to use, and why

These are workflow lessons to fit the user's chosen language, not a proposal to copy competitors' colours or chrome.

| First-party source | Verified lesson | Consequence for equmaczer |
|---|---|---|
| [Apple HIG: Layout](https://developer.apple.com/design/human-interface-guidelines/layout.md) | Adapt to window/text sizes; use progressive disclosure and meaningful grouping | Derive minimum sizes from content. Fold/paginate optional depth before controls become unusable. |
| [Apple: NSEvent local monitors](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)) and [Monitoring Events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html) | Local monitoring precedes dispatch; nil suppresses dispatch; lifecycle removal matters | Treat monitor ownership, modifiers and return values as application correctness, not UI polish. |
| [Apple: Reduce Motion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion.md) | A system preference is exposed to SwiftUI | Preserve spatial clarity while adapting movement to that preference. |
| [Apple: Accessibility modifiers](https://developer.apple.com/documentation/SwiftUI/View-Accessibility) | Accessibility has an explicit view semantics layer | Test hidden tiles, controls, names and focus with VoiceOver. |
| [Apple: SMAppService.register](https://developer.apple.com/documentation/servicemanagement/smappservice/register()) and [Status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum) | Registration and authorisation have distinct states | Login UI must reflect enabled/pending/error/revoked states, not just a local Bool. |
| [Apple: Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps.md) | Taps capture selected process outputs through an aggregate device | Verify the app's real capture lifecycle and permissions; don't repeat historical “dead backend” findings. The current sample's availability does not establish the deployment availability of every API. |
| [Swift: Data Race Safety](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/dataracesafety/) | Concurrent mutation of shared memory requires actual protection | Audit unsafe pointer publication even in a Swift 6 build. |
| [Linux: Sequence counters](https://www.kernel.org/doc/html/latest/locking/seqlock.html) | A changed sequence invalidates the copied dataset | Never commit an unvalidated snapshot to live filters. Use a Swift-compatible publication design. |
| [W3C: Contrast minimum](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html) | Small text generally requires 4.5:1 under WCAG 2 | Use WCAG as its own measurable gate, not as a claimed APCA conversion. |
| [APCA official documentation](https://apcaw3.myndex.com/) | Polarity and font size/weight matter; implementation/version must be identified | Pin the algorithm and test rendered surface combinations. APCA is not interchangeable with WCAG 2 conformance. |
| [FabFilter: Display/workflow](https://www.fabfilter.com/help/pro-q/using/eqdisplay) and [resizing/scaling](https://www.fabfilter.com/help/pro-q/using/fullscreenandresize) | Direct manipulation and precise editing coexist; constrained sizes are deliberate | Make Shape editable; use a selected-band inspector and layouts validated at each supported size. |
| [SoundSource: Keyboard controls](https://rogueamoeba.com/support/manuals/soundsource/?page=keyboard-controls) | Scope distinguishes global, window and selected-item commands | Preserve ordinary macOS commands and visible keyboard focus. |
| [SoundID Reference: Standalone setup](https://support.sonarworks.com/hc/en-us/articles/360019916480-Setting-up-with-the-SoundID-Reference-standalone-app) | Device/profile/DSP presets have explicit scope | Keep correction identity separate from user shaping and export those scopes truthfully. |
| [eqMac](https://eqmac.app/) | Parametric graphical controls and custom feature arrangement already exist in the category | Differentiate on reliability, workflow and the user's visual language; avoid unsupported novelty claims. |

## Recovery plan

### 1. Establish trustworthy behaviour

Keep the current revision as a named recovery point without resetting history or copying over the dirty older checkout. Bring the seven regression contracts into the active suite as fixes land. Fix B1–B4, C1 and C4–C7 through state/transaction APIs before dressing those flows. Handle E1/E2 in separate engineering changes with focused verification; a UI repair should not quietly change the audio engine.

Replace scattered mutation paths with a SoundTransaction boundary: immutable before-state, validated candidate, atomic logical commit, explicit pipeline apply, preset-modified state, receipt and action-specific Undo. Separate manual user settings from transient scenes and preview state.

### 2. Rebuild the tiling mechanism around constraints

One WorkspaceState should describe arrangement, visible tiles, master, optional split and selected tabs. Each tile declares a minimum usable size and a compact presentation. Resolve one layout tree and partition its bounds once. Promotion/summon/fold must be inputs to that operation, not sequential rectangle patches.

Core invariants: visible leaves are disjoint and inside bounds; dimensions are nonnegative; exactly one master or one declared split pair exists; master is visible; selected tab exists and is visible; every visible control has sufficient space; closing a tile redistributes its space. Test invariants over all reachable states and representative boundary sizes, including both sides of the current 900/500 breakpoints.

Retain Shape, Engineer, Measure and Settings as job-based arrangements. Shape needs direct curve manipulation and a compact selected-band editor. Engineer should expose full detail by promotion, not tiny simultaneous panels. Measure should give one monitoring view the space it requires, with tabs for other readings. Settings needs one real promoted pane, shared with ⌘, and its other entry points.

### 3. Finish the visual language on verified screens

Migrate real controls, labels, contrast, corners and selection/focus/disabled/error states. Avoid continuing the feature inventory while core tiles are broken. Keep unavailable Match/Dynamics unavailable; do not fabricate controls for missing engines. Rename or constrain History, Words and per-app functionality to what actually exists. Lists that grow require an explicit paging/disclosure decision rather than overflow hidden behind clipping.

Only then review screenshots and live transitions at supported sizes. Compare against the approved concept, not an invented new style. The user need only review concrete representative screens, not arbitrate implementation minutiae.

## Acceptance matrix: evidence needed to close this audit

| Area | Required checks | Completion evidence |
|---|---|---|
| Layout | All arrangements; every promotion; summon/remove; split; fold selection; breakpoint crossing | Automated invariant grid plus screenshots at 832×680, 1024×768 and 1440×900 where the display permits |
| Bands | 1/10/16/17/32/64; linked and stereo; both focus states; shelves/cuts/bypass | All editing controls reachable and usable without accidental overlap |
| Shape | Select/drag/fine-adjust/type exact values/sketch/cancel/undo | Graph and audio use the same committed parameters |
| Blend | 0/partial/1; unequal counts; unequal channels; bypass; mode/gain differences; Cancel | Exact endpoint tests, reversible preview, one complete Undo |
| Panic/compare | Hold/release; app switch; close/minimise; field focus; sheet; duplicate key; rebinding; Cmd combinations | Prior state restored exactly; ordinary commands preserved |
| Snapshots/undo | Apply while routing; subsequent edit; repeated operations; restart | Pipeline and displayed state agree; correct transaction undone |
| Settings transfer | New isolated profile; all advertised settings; malformed file; Cancel; quit/restart | Export/import round trip with no overwritten pending state |
| Scenes | Call alone; call+music; film+music; manual pin during scene; disable/remove; crash/relaunch; precedence | Truthful trigger receipts; manual edits win; transient state does not become a saved pin |
| Time | Date/month rollover; DST; timezone; sleep/wake; suppressed hour event | Deterministic injected-clock tests and defined release policy |
| Accessibility | VoiceOver; full keyboard access; reduced motion; increased contrast; long names | Named visible controls, sensible order, no hidden focus targets |
| Audio | Every backend; cold start; unplug/replug; Bluetooth; rate switch; sleep/wake; fallback; quit/crash | Listening and frame-delivery evidence on macOS 15 and current macOS, using real devices |
| Realtime/security | Overlapping stage/apply under TSan; maximal layer workload; hostile shared-memory inputs | No data races, bounded callback execution, validated restricted transport |
| Release | Clean build; bundle/signature; installation/uninstallation; permissions; docs | Revision-linked release record; distribution signing/notarisation assessed separately |

The native follow-up closes the initial screenshot/accessibility-access blocker and confirms representative layout failures. Full size/transition/accessibility coverage, listening and physical-device validation remain explicit gates, rather than being inferred from 621 green unit tests.

## Native-validation addendum: access enabled

The user's follow-up enabled native inspection. The built app at `working/release/equmaczer.app` responded immediately to the next inspection attempt. Screenshots and native accessibility trees were captured in the conversation; they have not been exported as separate image files. The running bundle's version is 1.3.3; no embedded commit identity was established, so these observations corroborate the audited source without claiming binary/source identity.

| Surface or check | Direct observation | Audit effect |
|---|---|---|
| Engineer, existing Presets master, 11 bands | Band columns extend upward over the route bar and beyond the right edge. Layers and the small Clay tile sit under the oversized content; the Clay axis labels crowd together. Reproduced again after leaving and returning to the arrangement. | A3 is visually confirmed on the live app, beyond the source-level size calculation. |
| Shape | Full graph, axes, Sketch and ceiling visible; no accessible band-editor controls exposed in the captured tree. | Confirms the large graph presentation; direct manipulation remains absent in the inspected source, rather than inferred from a screenshot alone. |
| Measure | The fixed-width Monitoring content extends beyond its allocation; left-side input labels/values are cut off, and oversized band controls extend outside the right-hand region. | Visually confirms A3 in a second arrangement. |
| In-window Settings, Display | Curve and category pane share comparable space; the heading visibly reads `01 // DISPLAY`. | Confirms A5's hierarchy and D1's incomplete text migration. |
| In-window Settings, Driver | Heading visibly reads `02 // DRIVER`; the pane scrolls. Installed driver v1.1.0; active/preferred route Shared Memory; input/output/processing rates 48000 Hz. | Confirms live route/device state, not sound quality. |
| Standard ⌘, | Opens a separate `equmaczer Settings` window with only Display, Driver, Channels, Hearing and About. | Directly confirms C3: General, Keys and Scenes are absent from this entry point. |
| Live processing proof | Input/output −90.0 dB, no measured effect, “No signal arriving.” Later health observation: transport 99% of rate and app CPU 12% of one core. | Frame transport is reported active while programme audio is silent. This is not sufficient to diagnose failed routing: silent frames can be valid transport. |
| Quiet audio probe | Generated a 12-second stereo 1 kHz WAV at −36 dBFS with fades in scratch. `afplay` failed with `AudioQueueStart failed (-66680)` before playback. Opening QuickTime via native control then timed out with error −10005. | No successful stimulus, captured output or listening judgement. Error alone does not establish its cause or implicate equmaczer. |

The follow-up changed navigation only: it did not alter the user's bands, preset, gains, routing method or device. Closed the temporary standard Settings window and returned the main window to its original Engineer arrangement with Presets master. No external device was connected/disconnected, and no microphone/speaker recording was obtained. Screenshot access and audio capture/playback are separate capabilities; successful screen inspection does not close those audio tests.

## Reproducing the new evidence

From the `working/` root, on macOS with the Swift toolchain:

```zsh
CLANG_MODULE_CACHE_PATH=/tmp/equmaczer-clang-cache \
swift docs/audits/2026-11-20/layout-reproduction.swift

python3 docs/audits/2026-11-20/contrast-reproduction.py
```

The standalone layout file is a snapshot of the production functions at this revision, not a second maintained layout implementation. For regression testing, copy `RevampAuditEvidenceTests.swift` into `tests/` and run the earlier SwiftPM command with `--filter RevampAuditEvidenceTests`. Those tests intentionally assert correct contracts and fail at the audited revision. They are archived outside the active suite so this audit does not silently leave the existing test target failing.
