# Recovery continuation: 1.3.5

20 November 2026. Continues `RECOVERY.md`; its 1.3.4 evidence is preserved. Active source remains `working/`. The app bundle is now **1.3.5, build 20261120.4**, with **driver 1.1.3 installed and routing**.

## Additional defects found and repaired

**Driver updater:** The previous operation removed the installed driver before copying its replacement, interpolated the app path into nested shell/AppleScript strings, and synchronously waited for administrator interaction on the main actor. It now stages and verifies the replacement first, moves the previous bundle aside during replacement, restores it if replacement fails, and retains the backup if rollback itself fails. Paths are shell literals, the complete shell operation is an escaped AppleScript string, and process waiting runs off the main actor. This is failure recovery during a running update, not a claim of power-loss atomicity.

**Driver mapping lifetime:** The property setter could unmap shared memory while the render callback was writing through its pointer. Both paths now use the same small access guard. The callback makes one atomic-flag attempt and skips that shared-memory block if unavailable; it never spins or waits on this guard. The control thread may wait before replacing or unmapping storage. The existing HAL loopback I/O mutex is unchanged, so the entire driver is not claimed to be lock-free.

**Header publication:** Channel count and Float64 sample rate now use C11 atomic stores/loads, including compile-time ABI and lock-free checks. Previously sample rate could be written concurrently with a plain Swift pointer load. The bridge ABI regression includes the sample-rate field.

**Cross-account disconnect:** An active mapping records its owner's UID. A different account cannot clear or replace it by submitting an empty/invalid path. The same user's processes and administrators remain outside the isolation guarantee.

**Real-host compatibility and diagnosis:** Driver 1.1.2 installed but rejected the private file during live reconnection. Driver 1.1.3 keeps the caller/file ownership checks and adds a kernel `sysctl` credential lookup when `libproc` cannot supply the host-provided PID's UID. It reports distinct identity, owner, file validation, open and mapping failures. A fresh native test subsequently established the secured Shared Memory route. The exact cause of each earlier transient failure was not independently logged; the environment denied unified-log access.

**Failed-start reporting and recovery:** Driver capture errors now retain their underlying cause rather than becoming a misleading missing-audio-unit error. The health pane displays the complete failure, rejects stale capture-mode/no-pipeline facts, and says it is measuring until transport/load samples exist. Pipeline configuration/start failure restores the physical system output instead of leaving macOS on an unread virtual device.

## Verification

| Check | Result | Evidence |
|---|---|---|
| Full app suite | **647 tests, zero failures** | `continuation-tests.txt` |
| Swift publication under Thread Sanitizer | **3 tests, zero failures; no reported races** | `continuation-tsan.txt` |
| Installer regression tests | Shell path round-trip; complete AppleScript literal round-trip; missing source preserves old driver and cleans staging | `installer-tests.txt` |
| Driver lifetime under Thread Sanitizer | 20,000 replacements; 96,762 callback accesses; no reported races | `driver-lifetime-tsan.txt` |
| Driver lifetime under Address Sanitizer | 20,000 replacements; 1,502,764 callback accesses; no reported memory errors | `driver-lifetime-asan.txt` |
| Driver build | Universal arm64/x86_64 1.1.3 bundle succeeded; installed signature verifies | `continuation-driver-build.txt` |
| App release/package | Build succeeded; deep/strict signature verification passed | `continuation-build.txt`, `continuation-package.txt` |
| Release stress path | p50 **185.04 µs**, p99 **267.25 µs**, deadline **666.67 µs** | `continuation-stress.txt` |

The isolated lifetime test uses the actual access guard while freeing/replacing storage concurrently; it does not load the HAL plug-in or touch live audio. It also asserts the replacement policy for matching/different UIDs. Sanitizer success does not establish physical-device behaviour or the safety of every driver subsystem.

The release build used the previously documented native SwiftPM workaround. Stress excludes HAL scheduling and physical device latency. Patch whitespace checks passed.

## Native follow-up

Using macOS Window → Move & Resize → Top Left produced a constrained native window around 855 × 732 points. Engineer showed four usable band columns per page; Measure showed the Levels section and correctly unwrapped IN/OUT labels; Driver Settings retained its categories and proof controls. The inspected screenshots showed no overlap. This improves the evidence beyond the earlier wide-window inspection but is not the complete minimum-size/long-name/accessibility matrix.

The rebuilt app reopened natively as **Version 1.3.5**. Driver 1.1.2 installed but the live secured capture path failed. After the compatibility/diagnostic follow-up, **driver 1.1.3 installed** through the app. Reconnection initially coincided with native inspection timeouts; System Settings remained accessible. Selecting the built-in physical output prompted routing reevaluation, after which native inspection showed **Active route: Shared Memory** and **Driver installed v1.1.3**. The final health page reported **48,000 Hz input / processing / output, 100% transport and 16% of one core**, with matched-rate/full-transport status. This demonstrates a working secured transport in this session; it does not establish automatic recovery for every server restart or output transition.

The live backing file had mode 0600 and expected size 524,352 bytes. Only its 24-byte header was read for validation: two channels, 48 kHz and a 128-frame producer block. Audio sample contents were not read or saved.

The live Signal section showed −90 dB in/out and no incoming signal. Another low-volume command-line playback attempt failed with `AudioQueueStart failed (-66680)`. No listening or physical-device transition pass is claimed.

## CI and remaining gates

`.github/workflows/verify.yml` now prepares macOS 15 and macOS 26 checks for tests, publication Thread Sanitizer, driver lifetime Thread/Address Sanitizer, universal driver build, app packaging/signature verification and the full DSP stress path. Checkout is pinned and credentials are not persisted. The workflow has not run remotely: this checkout's origin still points to the original upstream project, and nothing was pushed.

Real listening/device transitions, automatic server-restart recovery, VoiceOver and complete keyboard traversal, Instruments profiling, rendered contrast/font checks, and Developer ID/notarised distribution remain open. Official APCA guidance was rechecked; the pinned npm package could not be downloaded because the execution environment could not resolve the registry host. The independent contrast calculations remain explicitly separate from upstream-package/font certification.

See the original audit's research table for Apple, Swift, W3C/APCA and audio-product references. Additional primary references for this follow-up:

- [Apple window resizability](https://developer.apple.com/documentation/swiftui/scene/windowresizability(_:))
- [GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Official APCA library and font lookup guidance](https://github.com/Myndex/apca-w3)

The app was left on **Settings → Driver → Health**, displaying the working Shared Memory route. Driver 1.1.3 is installed, its on-disk signature verifies, and no administrator operation remains pending. The next acceptance gate is controlled real listening and device/server transition testing.
