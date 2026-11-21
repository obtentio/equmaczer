# equmaczer Presets

A preset sets the band layout, the band gains, and an input preamp in one
action. Your own presets sit beside the factory library and are never
touched by updates; factory presets refresh when the library changes.

## The factory library (2026-11)

The library is built from controlled listener-preference research —
principally the Harman studies by Olive and colleagues (AES papers 7960,
8994, 9382, 10156) — not from genre folklore. Two findings shape it:

- Listeners asked to adjust a flat system choose **more bass and slightly
  less treble**: +6.6 dB below 105 Hz and −2.4 dB above 2.5 kHz on
  loudspeakers, about 2 dB less at both ends on headphones. Listeners
  differ from each other mainly in *how much bass* (a 17 dB spread), so
  the bass axis comes in graded steps.
- **Programme material does not significantly change those preferences**,
  and each genre's spectral balance is already in its master. There are
  therefore no genre presets: a "Rock" curve double-counts what the
  recording already does. The previous library (Rock, Jazz, Classical,
  Electronic, Acoustic, and friends) was retired for this reason.

| Preset | What it does | Basis |
| --- | --- | --- |
| Flat | All bands at 0 dB | The baseline every study starts from |
| Reference — Speakers | Low shelf 105 Hz +6.6 dB; high shelf 2.5 kHz −2.4 dB | The mean in-room loudspeaker preference (AES 135) |
| Reference — Headphones | Low shelf 105 Hz +4.5 dB | Headphone preference ≈ loudspeaker −2 dB at the ends |
| Bass − | Low shelf −3 dB | The −2 to −3 dB listener segment (AES 146) |
| Bass + | Low shelf +4 dB | One taste step; the +4–6 dB segment |
| Bass ++ | Low shelf +8 dB | The largest published preference step (Dirac/Harman +8) |
| De-Boom | Low shelf −4 dB; 250 Hz −2 dB | Boomy rooms, corner-loaded speakers |
| Bright | High shelf 10 kHz +3 dB | Treble preference deltas are only +2–3 dB |
| Soft | High shelf 10 kHz −3 dB | The inverse step, for harsh systems |
| Lyric Clarity | 3 kHz +2.5 dB; 300 Hz −1.5 dB | The 2–5 kHz intelligibility region, minus low-mid mud |
| Warmth | 250 Hz +2.5 dB; 3.5 kHz −1.5 dB | Measured "warmth" = low-mid body, less presence |
| Loudness — Low Volume | Low shelf 100 Hz +6 dB; high shelf 12 kHz +2.5 dB | ~Half of ISO 226 compensation at an assumed 50–60 phon listening level |
| Night | Low shelf −3 dB; 3 kHz +1.5 dB; high shelf −2 dB | The EQ half of quiet listening — see below |
| Small Speakers | 60 Hz shelf −5 dB; 180 Hz +3 dB; 3.5 kHz +2 dB | Shed sub-bass small drivers cannot reproduce; lift what they can |
| Spoken Word | 100 Hz shelf −4 dB; 3 kHz +3 dB | Rumble removal plus the intelligibility band |

Every preset's preamp (input gain) is minus its largest boost, so
switching presets does not change the overall level on its own. The
auto-preamp then covers the combined curve as you edit.

## Two honest limits

- **Night is an EQ, not a dynamics processor.** Products whose "late
  night" mode works (Apple's is the reference) compress dynamic range so
  quiet passages rise and peaks fall. equmaczer has no dynamics stage
  yet; Night only rebalances tone for low-level listening.
- **Loudness — Low Volume assumes a level.** A fixed curve cannot know
  how loud your room actually is. If you want compensation that tracks
  your real listening level, use the ISO 226 loudness compensation in the
  correction panel instead — it follows the output device's volume. The
  preset is the simple, predictable version.

## Presets and correction are different layers

A preset shapes your EQ layer. Per-device correction (measured response,
AutoEq profiles) lives on its own layer underneath, per output device.
They compose: pick a correction for the headphones, then a preset for
taste. Neither overwrites the other.

## Design rules for your own presets

The same grammar the factory library follows, if you want presets that
survive contact with your ears:

- Broad changes only: shelves and Q ≤ 2. Narrow peaks are the most
  audible artefact per decibel; narrow cuts are nearly inaudible.
- Steps worth taking are 3–4 dB in the bass, 2–3 dB in the treble. Two
  presets closer than ~1 dB (broad) are the same preset.
- Set the preamp to minus your largest boost.
- Boost nothing below 50 Hz or above 16 kHz; small speakers in
  particular only distort when fed sub-bass they cannot reproduce.
