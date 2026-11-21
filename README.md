# equmaczer

A Mac equaliser for speakers and headphones. Adjust a curve, keep it as a preset, and add separate corrections for your output device and your ears.

## Getting started

Use this to install the app and hear your first adjustment. The app requires macOS 15 or later. The packaged build targets Apple Silicon.

1. Download `equmaczer-<version>.zip` from [the latest release](https://github.com/obtentio/equmaczer/releases/latest). Extract the ZIP and drag `equmaczer.app` into `Applications`.
2. On first open, macOS may block the unnotarized app. Open System Settings → Privacy & Security, scroll to the bottom, and click "Open Anyway" for equmaczer (macOS 15+ requires Privacy & Security rather than right-click → Open).
3. Click the five-bar menu bar icon, then "Open equmaczer". The app starts in the menu bar; the main window need not open by itself.
4. Start some music. The default capture method is "Process Tap", which routes audio without installing the virtual driver or changing your macOS default output. Allow macOS's audio-capture permission when requested, then turn "System EQ" on.
5. Open "Settings…" with ⌘, and choose "Driver", "Setup" only if you want the optional virtual driver (for Shared Memory capture, HAL Input, or the recording feed described below).

The virtual driver is optional: Process Tap runs driverless, while installing the driver enables Shared Memory capture and the recording feed. For permission problems, see Troubleshooting.

## The window

Use the main window to edit and watch the sound at once.

1. In the toolbar, click the output device name to inspect routing. "Apps n ▾" opens playing-app volumes. "Layers ▾" opens the processing layers. "System EQ" bypasses or enables processing.
2. Above the graph, "Spectrum" shows the live spectrum. Drag the curve horizontally to move frequency and vertically to change gain. Use the sliders below for precise changes.
3. Click "Sketch", draw across the graph, and release to fit bands. Inspect the proposed curve before clicking "Use bands"; "Discard" discards it.
4. Choose a band count from the menu labelled, for example, "11 bands ▾". Choices include "10 bands", "11 bands", "16 bands", "32 bands", "48 bands", "64 bands" and "Custom…".
5. Watch "Measure" for "dB out peak", "LUFS integrated", "LUFS short-term", and "dose today n%". LUFS describes loudness over time; the peak readout helps spot overload. Below 900 points wide, meters and listening controls move below the curve.

## The remote

Use the menu bar remote for quick changes while another app is open.

1. Click the five-bar menu bar icon. Filled bars mean on, outlined bars mean off, and crossed bars mean blocked.
2. Click the large "On" or "Off" row to toggle processing. When off, the subtitle says "Sound passes through untouched".
3. Click a preset under "Preset", or drag "Output" to change the overall output gain in dB. The active preset has a small square.
4. Adjust a playing app under "Apps". The remote shows at most five apps. Recording controls also appear here.
5. Click "Open equmaczer" for the full window, "Open equmaczer to fix" for a blocked route, or "Quit" to stop the app.

A daily dose estimate appears only from 80% in the remote. Call notices can say "Music lowered for a call" or "Music paused for a call".

## Bands and presets

Use bands to change individual frequency ranges. Use presets to keep and recall a complete curve.

1. Drag a band slider up to boost or down to cut. Double-click its fader to reset gain. Hover over the frequency label and click the gear, accessible as "Edit band n", for "Band options".
2. Enter "Gain (dB)", "Frequency (Hz)", and bandwidth, pressing Return to apply each number. Under "Filter Type", choose "Parametric", "Low Shelf", "High Shelf", "Low Pass", "High Pass", "Band Pass" or "Notch", or enable "Bypass Band". Gain spans −36 to +36 dB; frequency spans 20 Hz to 20 kHz. Higher Q makes a narrower change; larger octave widths make a broader change. Dense band sets use "Prev" and "Next" pages.
3. Adjust "in" before processing or "out" after it. Select "in" to reveal "Auto headroom" and "CUT", "CORR", "TOTAL". Leave automatic headroom on when boosting.
4. Click a preset chip, or "+ n" for more. The 15 factory choices are "Flat", "Reference — Speakers", "Reference — Headphones", "Bass −", "Bass +", "Bass ++", "De-Boom", "Bright", "Soft", "Lyric Clarity", "Warmth", "Loudness — Low Volume", "Night", "Small Speakers" and "Spoken Word".
5. Click "+ Save current", enter "Preset Name", then "Save". Right-click a chip for "Rename preset…", "Delete preset", "Save current preset" or "Save current EQ as…". These actions also live in "File".
6. To blend, drag a preset chip onto the graph, adjust the slider between "Yours" and the preset, then choose "Apply" or "Cancel". This changes both channels; filter types and bypass switch at 50%.
7. Use "Import preset" or "Export preset", then "equmaczer…", "REW…" or "EasyEffects…". For a REW import, choose "Linked" for one file or "Stereo" for separate left and right files, click "Select File..." for each, name it, and click "Create Preset". This import dialog chooses its own stereo mode.
8. Right-click "+ Save current" for "Saved snapshots…". Older snapshots have "Apply" and "Delete". New curves are saved through "+ Save current".

Start with 1 or 2 dB changes. Use "Edit" → "Undo" (⌘Z) or "Redo" (⇧⌘Z) to reverse edits. "Edit" → "Flatten" clears band gains. ⌘S opens preset saving; ⌘B toggles bypass.

## Left and right

Use separate curves when you want a different frequency response on each side. These are stereo audio channels, separate from the Music and Calls profiles below.

1. Open "Linked ▾" above the graph and choose "Left" or "Right".
2. Edit that side's bands. Switch to the other side and edit it separately.
3. Choose "Linked" to return to a shared curve. Save through "+ Save current" to retain your curve.

This is frequency shaping, not a left/right balance slider. For broad per-ear adjustments, use Hearing.

## Layers

Use layers to combine your taste with a device correction, hearing adjustments and content profiles without rebuilding a preset.

1. Open "Layers ▾" in the toolbar.
2. Toggle "My EQ", "Correction", "Hearing", "Channel" or "Loudness" to hear each contribution. Each row shows its current source.
3. Use "Open…" beside "Correction" for its editor. Adjust the slider below "Loudness" to change its strength; its curve follows volume.

"System EQ" is the overall bypass. Individual layer switches let you retain the other contributions.

## Channels

Channels apply treatments for "Music", "Calls", "Film" and "Games". Use them when different kinds of audio need different treatment.

1. Open "Settings…" → "Channels". Set "Pin" to "Auto" for automatic selection, or choose a named channel to keep it selected. "Active channel" shows the current choice.
2. Under "Treatments", pick a factory preset for each channel. These are the same 15 factory choices listed above. "Dialogue" is available for Calls and Film to improve speech clarity.
3. Under "Apps", use the channel menu beside an app to assign it, or choose "Unassign". "Add app…" → "Add to Music" (or another channel) lets you choose an installed app. Rows use "Previous" and "Next" when there are more than four.
4. Enable "Skip EQ" for an app you want excluded from processing, or use "Exclude app…" to select one. Turn "Skip EQ" off to include it again. Exclusions apply on Process Tap.
5. Under "Rules", click "Add a rule". Turn "Enabled" on. Choose "When" as "A call app makes sound", "Output device changes" or "At an hour"; set the hour when relevant and choose "Channel". "Remove" deletes a rule.
6. Use "Layers ▾" → "Channel" to enable or disable the layer. Rules temporarily select a treatment. Calls take priority; otherwise the latest trigger wins. The rule receipt offers "Undo" when available.

Scheduled rules release at the next hour. Device rules last until another rule or a manual channel choice. The Channels pane contains Channels, Apps and Rules sections; these are not separate tabs.

## App volume

Use app volume to quiet one playing app while leaving others alone.

1. Play sound in the app. In the main toolbar, click "Apps n ▾". Playing apps appear with names and available icons. "No apps playing" means none are currently detected.
2. Drag that app's slider from 0% to 100%. A change on a driver route switches to Process Tap; the notice says "Per-app volume needs Process Tap. Moving a slider switches routes."
3. The remote's "Apps" section offers the same sliders for up to five playing apps. "Settings…" → "Channels" → "Apps" also has volume beside assignments and "Skip EQ".
4. Return an app to 100% to remove its separate volume setting. There are 16 simultaneous separate app-volume slots; use 100% on one to make room if the app reports the limit.

An unavailable audio tap or capture fallback can prevent app volume from applying. Read the notice below the sliders and check "Active route" in Driver setup.

## During calls

Use this to keep calls audible while other audio becomes quieter, or to pause supported music players instead.

1. Open "Settings…" → "Channels". Set "During calls" to "Lower to 15%", "Pause" or "Nothing". Lower is the default for new settings.
2. On Process Tap, Lower reduces non-call sound to 15% while the Calls channel stays full. App volume multiplies with this reduction. Calls must be classified correctly under "Apps". On the sound driver, Lower uses Pause instead and leaves the route alone.
3. Pause controls Spotify and Apple Music. Allow Automation permission when asked. Your own play action takes precedence. Nothing leaves playback alone.
4. If Bluetooth call quality makes your headset sound muffled, use "Use {Mic}" in the window or remote notice. Pick a non-Bluetooth microphone. If the notice says "Plug in a mic to get stereo back.", connect one first. The microphone choice is remembered per headset.
5. After the call, the remote offers "Restore {Mic}". Settings can instead offer "Switch microphone back to {name}". Use it to return to the previous microphone. Call apps must follow the system default input for this rescue to help.

The remote confirms "Music lowered for a call" or "Music paused for a call" while the action holds. "Call-cliff save" in Channels controls the Bluetooth rescue offer.

## Your hearing

Use Hearing for relative per-ear adjustments, or to enter an existing audiogram. These are estimates, not a hearing measurement or medical advice.

1. Open "Settings…" → "Hearing" → "Adjustments" and enable "Hearing layer". Adjust "Low" and "High" under "Left ear" and "Right ear", or choose "Reset both ears".
2. For a guided route, click "Guided setup…". Play familiar speech or music at your normal volume. In "Pre-flight", satisfy "Audio is routing", "Music is reaching equmaczer" and "Hearing layer is on"; "Turn it on" enables the layer. Click "Continue".
3. In "Scope", choose "Each ear separately" or "Both ears together", and "Quick — one pass" or "Full — two passes". Click "Start tuning". Adjust each presented shelf, then click "Sounds right". In "Done", review the values and click "Done". Values save as you go.
4. For an existing audiogram, click "Enter audiogram…" or "Audiogram". Enter dB HL thresholds for each ear at the displayed frequencies from 250 Hz to 8 kHz. Enable "Use audiogram" to use those thresholds. Turning it off restores the by-ear shelves; "Clear audiogram" removes the entered values.
5. In "Layers ▾", "Hearing" shows "audiogram, L/R" or "by-ear test". Toggle it to compare. Open "Estimated dose" for seven days of estimated exposure and the weekly reference percentage.

Dose depends on an assumed full-scale level. Your headphones and volume change the real sound level. The main window shows today's estimate; it is not a calibrated sound-level measurement.

## Your devices

Use device selection to choose where sound plays. Device correction keeps a headphone or speaker profile separate from your own presets.

1. Click the output device name in the toolbar. "Follow macOS sound settings" follows your Mac's selected output. Turn it off for manual "Output" and "Input" selection; manual routing needs microphone permission. Use "Audio Routing" there to start or stop manual routing.
2. Open "Layers ▾", then "Open…" beside "Correction". Choose "Import AutoEq…" for a parametric `.txt` file, "Import OPRA…" for a local `.json` or `.jsonl` database, or "Use current EQ" to save your present EQ as that device's correction. OPRA opens "Choose a correction". Type in "Search headphones", then click the wanted author/profile row. You can also drop supported correction files on the main window.
3. For built-in speakers, "Speaker guard…" stages a generic protective shape. It is not a measurement of your particular Mac.
4. In a staged preview, adjust "Bass", "Treble" and "Blend". "Hear preview" and "Hear current" compare them at matched levels. "Import" keeps the correction for this device; "Cancel" discards it. "Hear blind" runs the blind comparison before keeping or discarding it.
5. "Clear correction for this device" removes a saved correction. Switching presets does not overwrite a separate device correction.
6. Enable "Loudness" here or in Layers, and adjust "Strength" here or the Layers slider for comfortable balance at low output volume. "General" calls the same switch "Loudness compensation".

New measured corrections start at 70% blend. REW files are preset imports through "File" → "Import preset" → "REW…", not this correction drop target. Bluetooth output uses a −2 dBTP peak ceiling while EQ runs; its tooltip says "Bluetooth headroom".

## Compare

Use Compare to judge tone at matched loudness. Use Check to hear a rough small-speaker approximation, or Blind test to hide the preset identity.

1. In "Listen", click "Flat" then "EQ". The matching difference is shown in dB when available. Flat returns to EQ automatically after five minutes.
2. Choose "Check" → "Phone", "Laptop" or "Car". The caption explains that this is an approximation. Choose "Off" or click "Stop" to restore the original bands. Edits during a check are not kept. Check requires "Linked" mode.
3. Click "Blind test", then choose a preset. Hear both "A" and "B" before clicking "I prefer A" or "I prefer B". The app reveals the winner and plays it. "Done" keeps that choice; "Use the other one" switches to the other. "End test" cancels while listening.
4. In "Settings…" → "Keys", enable "Hold" for momentary Compare or turn it off for toggle. Click its key button and type a letter or number; Escape cancels. The default Compare key is C. Panic defaults to P; holding it bypasses until release. Keys must differ. "Reset keys" restores defaults.

Compare and Panic are app keyboard controls. Command shortcuts remain available.

## Words

Use plain words for small tonal changes instead of adjusting each band yourself. Words move the nearest enabled bell or shelf band, so the result depends on your band layout.

1. Click "describe…" on the preset row. Type "warmer but less boomy" and press Return.
2. Read the receipt showing frequencies and before/after gains. Use "a bit warmer" for a smaller move or "much warmer" for a larger one. "a bit", "slightly", "a little", "a touch", "tad" and "somewhat" halve a move; "much", "a lot", "lots", "way", "far", "very" and "really" double it.
3. Combine traits with "and", "but", "then" or "while". "more" increases a trait; "less", "fewer", "reduce" or "lower" reverses it. Unknown words or a dangling modifier change nothing and produce a hint.
4. Use ⌘Z to undo. Changes from words are limited to ±18 dB per affected band.

| Words | Normal move |
| --- | --- |
| warm, warmer, cosy, cosier | +2 dB near 250 Hz |
| full, fuller, rich, richer | +2 dB near 120 Hz |
| thin, thinner | −2 dB near 120 Hz |
| bright, brighter | +2 dB near 8 kHz |
| airy, airier | +2 dB near 10 kHz |
| dark, darker, dull, duller | −2 dB near 8 kHz |
| clear, clearer, crisp, crisper | +1.5 dB near 3 kHz |
| soft, softer, gentle, gentler | −1.5 dB near 3 kHz |
| punchy, punchier | +2 dB near 60 Hz |
| bassy, bassier | +2 dB near 80 Hz |
| boomy, muddy, boxy, nasal, harsh, sharp or sibilant | −2 dB near 100, 250, 500, 1000, 3500 or 7000 Hz respectively |

Complaint words such as "boomy" mean less of that quality by default. "more boomy" explicitly boosts it.

## Mac sound in recordings

Use this to give an external recorder the processed sound you hear, with an optional microphone mix. equmaczer supplies the feed; your recorder saves the file.

1. Install the driver in "Settings…" → "Driver" → "Setup" if needed. Set "Method" to "Process Tap". Other routes show "Works on the Process Tap route." and disable recording controls.
2. In the main window or remote, turn on "Mac sound in recordings". In the recorder's microphone selector, choose "equmaczer". The hint says "In the recorder, choose equmaczer as the microphone." Start a recording with your chosen recorder.
3. To include your voice, enable "Include my mic" and allow microphone permission. In "Settings…" → "Display" → "Recordings", choose "Microphone" or leave "System default input". The equmaczer driver is excluded from that input list.
4. If permission is denied, the switch turns off and the app says "Allow equmaczer under Microphone in Privacy & Security." Grant it there, then enable the switch again.
5. Stop your recorder when finished. Turn off "Include my mic" or "Mac sound in recordings" when you no longer need the feed.

The feed includes final EQ and app volumes. The microphone is mixed only into the recording feed, not into the speakers or headphones. Make a short test recording to check the chosen recorder and microphone before recording something important.

## Activity

Use Activity after an unexpected device, channel or sound change to see what the app recorded.

1. Open "Settings…" → "Driver" → "Activity".
2. Read the newest entries first. The journal keeps up to 200 real route, scene, channel, preset and driver events; it is not a complete audio trace.
3. Use "Next" and "Previous" for pages of eight entries. "Nothing has happened yet." means the saved journal is empty.

## Settings

Use Settings for persistent preferences and routing diagnostics. Open "Settings…" with ⌘, from the app menu.

1. Choose "Display" for "Routing mode", "Band width shows as", "Level meters", "Live spectrum" and "Recordings".
2. Choose "Driver" for "Setup", "Signal", "Health", "Activity" or "Safety and files". Setup changes "Method" and shows "Active route". Signal shows "Processing proof", "Signal in", "Signal out" and "Measured effect". Health shows "Pipeline health", including "Output device", "Input device", "Processing", "Transport", "This app's CPU" and "Route fallbacks" when available. Use these when sound is missing or unreliable.
3. Choose "Channels" for profiles, app assignments and rules, or "Hearing" for per-ear settings and dose estimates.
4. Choose "Keys" to set Compare and Panic, or "General" for "Start at login", "Loudness compensation", "Auto-preamp" and "EQ and routing".
5. Under "EQ and routing", click "Export" to save current EQ/routing as JSON. Click "Import" to choose a settings file and apply it immediately. ⌘Z undoes that import. Preset files, correction profiles, rules and keys are not part of this transfer.
6. "Reset General" → "Reset" resets that category's switches. "Reset rules and keys" → "Reset" asks again; "Keep" cancels. That reset cannot be undone.
7. Choose "About and legal" to read versions and "Open Source Acknowledgements" → "View" for the licence. "READ THE FULL LICENCE" expands its text. "Help" → "Search everything" (⌘K) searches actions, settings and presets.

## Updates

equmaczer checks GitHub Releases for a newer version. It never installs anything by itself.

1. Open "Settings…" → "General" and find "Updates". The line under it says what the last check found, such as "Up to date".
2. Click "Check now" to check straight away.
3. When a newer version is out, click "Download". It opens the release page on GitHub. Quit equmaczer, replace the copy in Applications, and open it again. If asked, use "Update Driver" for the bundled driver.
4. "Check for updates automatically" checks once a day, a few seconds after launch. Turn it off to check only by hand. The remote also shows "Update available" when there is one.

The check sends one anonymous request to GitHub with the app version. Nothing about you or your sound is sent.

## Privacy

Use these controls to decide what audio the app can access and when it supplies audio to a recorder.

1. For Process Tap, allow audio capture under macOS System Settings → Privacy & Security → Screen & System Audio Recording. It captures Mac playback for local processing and does not use the microphone permission check used by HAL Input.
2. "Shared Memory" needs the installed driver but no microphone permission or microphone indicator. "HAL Input" and manual routing need microphone permission and can show its indicator. "Include my mic" also requests microphone permission.
3. Grant Automation only when you want the Pause call action to control Spotify or Apple Music.
4. Leave "Mac sound in recordings" off if you do not want the driver recording feed. When enabled, an external recorder can save it. equmaczer itself does not write audio recordings to disk.

EQ processing, presets, hearing settings and the activity journal stay on the Mac. Update checks contact GitHub Releases when enabled or requested. Device-correction import reads local files. There is no usage analytics feature in the inspected source.

## Troubleshooting

Use these checks when sound is missing, distorted, on the wrong output or missing from a recording.

1. Open the remote. If it says "Sound is blocked.", read the reason and click "Open equmaczer to fix". In Driver setup use "Install Driver" or "Update Driver" if required.
2. Play known audio, then open "Settings…" → "Driver" → "Setup". Read "Active route", not just "Method": the watchdog can fall back when a route hears nothing. For "Process Tap heard no audio", allow equmaczer in System Settings → Privacy & Security → Screen & System Audio Recording. Quit and reopen after changing permission, then retry "Process Tap".
3. For manual routing or "HAL Input", grant Microphone permission. "Shared Memory" plus automatic routing avoids that microphone capture path. A driver update can be needed before Shared Memory works.
4. For wrong-device sound, open the toolbar device popover and enable "Follow macOS sound settings". Select the real headphones or speakers in macOS Sound settings. On a driver route, the virtual device is named "equmaczer" by default; do not mistake it for your physical output. A customised driver name may differ.
5. For distortion, reduce boosted bands or "in" and "out", and enable "Auto headroom". Compare with "Flat" briefly, then return to "EQ". Bypass and Flat also bypass the EQ's peak limiter; keep listening volume comfortable.
6. For missing app volumes or "Skip EQ", return to Process Tap and read any tap-unavailable notice. A driver route carries apps already mixed together. "During calls" → "Lower to 15%" pauses supported music instead on that route.
7. For a missing recording feed, confirm the driver is installed, Process Tap is active, "Mac sound in recordings" is on and the recorder uses equmaczer as its microphone. For missing voice, also check "Include my mic", "Microphone" selection and Microphone permission.
8. For an install failure, read the displayed error and retry "Install Driver" after checking your administrator password. Use "Driver" → "Signal", "Health" and "Activity" to inspect processing and recent changes. Restart the Mac if the driver remains unavailable.

## Uninstall

Use this to remove the driver and app while choosing whether to keep your presets and preferences.

1. Back up any wanted presets from `~/Library/Application Support/equmaczer/Presets/`. Export EQ/routing through General if useful.
2. While the app is still installed, open "Settings…" → "Driver" → "Setup". Click "Uninstall" next to the installed driver. Confirm "Uninstall" in the "Uninstall Driver" dialog and authorise removal. This removes the current driver and an older driver if present, moves the default sound device to real hardware if needed, and restarts Core Audio. Your saved data is kept.
3. Inspect "Safety and files" for driver and data locations. The driver location is `/Library/Audio/Plug-Ins/HAL/equmaczer.driver`.
4. Click "Quit" in the remote. In Finder, move `/Applications/equmaczer.app` to the Bin. Remove the preset folder only if you do not want its contents.
5. To discard the app's saved preferences as well, after quitting run `defaults delete com.obtentio.equmaczer` in Terminal. This removes the preferences domain, including saved settings, corrections and hearing adjustments. Keep it if you plan to reinstall. A missing-domain message means there was nothing there to remove.

## Credits

Made by obtentio

Based on Equaliser by Christophe Knage and contributors, originally `cvknage/equaliser`.

Audio driver derived from BlackHole by Existential Audio and contributors. Swift Atomics by Apple and contributors. Imported AutoEq and OPRA profiles retain their own authors and provenance; the correction panel displays available author details.

Released under GNU GPL version 3. The original Git history, copyright notices and licence remain part of the source distribution. This is the independent `obtentio/equmaczer` repository. Read "About and legal" → "Open Source Acknowledgements" → "View" for the app's legal disclosure; use "READ THE FULL LICENCE" to expand it.

