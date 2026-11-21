# The equmaczer Engine

## Overview

equmaczer processes audio in a custom State-Variable Filter (SVF) engine written in Swift for real-time, low-latency operation on macOS.

Each channel passes through **4 pre-allocated filter layers** supporting up to 64 bands of parametric equalisation. Both left and right channels are designed by a single matched, decramped SVF designer and staged natively as state-variable filters from design to render, avoiding frequency cramping near Nyquist and eliminating intermediate biquad conversion.

- **Layer 0** carries your EQ bands.
- **Layer 1** carries the per-device correction profile for the current output device: measured correction bands, profile preamp, bass/treble preference trims, and the loudness-compensation shelves composed into it.
- **Layers 2 and 3** are reserved.

## State-Variable Filter Design

Traditional biquad filters designed with the bilinear transform (such as the RBJ Audio EQ Cookbook) suffer from frequency warping ("cramping") as filter frequencies approach half the sample rate (Nyquist). equmaczer computes matched, decramped SVF coefficients directly in 64-bit `Double` precision before staging them to the real-time audio thread as 32-bit `Float` state-variable sections.

## Filter Types

Seven filter types are supported: peaking (parametric), low-pass, high-pass, low shelf, high shelf, band-pass, and notch. Four legacy resonant variants from earlier versions migrate onto the corresponding shelf and pass types.

## Gain Staging and Headroom

Whenever bands are restaged, a composite-peak analyser evaluates the combined frequency response across the active layers and applies an automatic preamp reduction to offset net boosts, so stacked boosts cannot clip the chain internally.

At the end of the chain, a true-peak limiter enforces a ceiling of **−1.0 dBTP**. It detects inter-sample peaks with a 4x-oversampled BS.1770 detector, looks 12 samples ahead, and ramps its gain reduction linearly across 6 samples rather than stepping in a single sample. After a peak, gain holds for 25 ms (longer than a full 40 Hz cycle) and then releases with an 80 ms time constant; hold and release are scaled to the sample rate.

---

## Why Swift?

equmaczer's engine is written in **Swift**. Filtering runs as native state-variable filter sections on the audio thread; vectorised Accelerate routines support analysis work such as metering. This combination delivers native performance with clean, maintainable code.

### What Is vDSP?

vDSP is Apple's vectorised Digital Signal Processing library, optimised for Apple Silicon:

- **SIMD operations** — Process 4-8 samples per instruction
- **NEON acceleration** — Native ARM64 vector instructions
- **Zero allocation** — All operations work on pre-allocated buffers

### Why Not AVAudioUnitEQ?

Apple's `AVAudioUnitEQ` is convenient but limiting:

| Aspect | AVAudioUnitEQ | Custom SVF (equmaczer) |
|--------|---------------|---------------------------|
| Per-channel config | No | Yes (independent L/R) |
| Coefficient access | Limited | Full control |
| Real-time updates | Apple-controlled | Atomic, lock-free |
| Debugging | Black box | Transparent |

<details>
<summary>⚙️ Technical Details: Double-Precision Coefficients</summary>

equmaczer calculates filter coefficients using **Double** (64-bit) precision, then converts to **Float** (32-bit) for the vDSP operations.

Why Double for calculation?

- **Narrow filters** — A Q of 20 at low frequencies produces very small alpha values. Float precision can introduce audible errors.
- **Low frequencies** — Near DC, sin(ω) values become tiny. Double maintains precision.
- **Accurate shelf slopes** — Shelf filters involve sqrt(A) terms that benefit from extra precision.

The SVF sections operate on Float arrays at runtime — the audio samples are Float anyway. Only the coefficient calculation benefits from Double.

</details>

---

## Real-Time Safety

Audio processing must happen in **real-time** — the next buffer of samples must be ready before the speaker needs them. If processing takes too long, you get **dropouts**: clicks, pops, or gaps in the audio.

equmaczer's engine is designed from the ground up for real-time safety:

| Operation | Thread | Real-Time Safe? | How |
|-----------|--------|-----------------|-----|
| Calculate coefficients | Main | No | Pure maths, may allocate |
| Apply slider change | Main | No | Writes to pending buffer |
| Process audio | Audio | **Yes** | Pre-allocated buffers, atomics only |
| Update filter state | Audio | **Yes** | Only if dirty, bounded copy |

### Lock-Free Coefficient Updates

When you drag a slider, the main thread calculates new coefficients. But the audio thread is already running — how do we update without blocking?

equmaczer uses a **lock-free double-buffer** pattern:

```
[Main Thread]                              [Audio Thread]
     │                                          │
     ▼                                          │
BiquadMath.calculateCoefficients()              │
     │                                          │
     ▼                                          │
pendingCoefficients[index] = newCoeffs          │
     │                                          │
hasPendingUpdate.store(true, .releasing)        │
     │                                          │
     └─────── atomic flag ─────────────────────►│
                                                │
                                                ▼
                                       flag.exchange(false)
                                                │
                                                ▼
                                for each band where pending != active:
                                    filter.setCoefficients(pending, setup: preBuiltSetup)
                                    // vDSP setup pre-created on main thread
                                                │
                                                ▼
                                    process audio with new coefficients
```

Key points:

1. **No locks** — Atomic flag synchronises threads without blocking
2. **Dirty tracking** — Only changed bands trigger rebuild (`Equatable` comparison). A single-band slider drag rebuilds exactly 1 filter.
3. **Bounded setup recreation** — `vDSP_biquad_CreateSetup` is called on the audio thread, but only for dirty bands. The setup object doesn't allocate memory; it's a pre-sized data structure.
4. **State preserved** — Slider drags don't reset filter delay elements (no clicks). Only preset loads and sample rate changes reset state.

### Why This Matters

Without real-time safety:

- **Locks cause priority inversion** — Audio thread waits for UI thread
- **Allocations cause VM faults** — First access to new memory can take 100s of milliseconds
- **Unbounded work causes underruns** — Processing might not finish in time

equmaczer's engine guarantees: every filter operation completes in bounded time, every time.

<details>
<summary>⚙️ Technical Details: vDSP Biquad Setup</summary>

Each biquad filter requires a **setup object** (`vDSP_biquad_Setup`) that holds internal state. Creating and destroying these objects is expensive.

equmaczer's `BiquadFilter` manages this carefully:

```swift
// Init: create setup once
let setup = vDSP_biquad_CreateSetup(&coefficients, 1, .intersect)

// Runtime: reuse setup, only update coefficients
vDSP_biquad(setup, &input, &output, 1, frameCount)

// Coefficients change: destroy old setup, create new one
vDSP_biquad_DestroySetup(setup)
let newSetup = vDSP_biquad_CreateSetup(&newCoefficients, 1, .intersect)
```

The setup is only recreated when coefficients actually change, and the old setup is kept valid until the new one is ready. This prevents any gap in processing.

</details>

---

## Independent Stereo Processing

equmaczer supports **independent EQ for left and right channels** — each channel can have completely different curves.

### Architecture

Each EQ layer has two separate filter chains:

```
┌──────────────────────────────────────────────────────┐
│                       EQ Layer                       │
│                                                      │
│  ┌─────────────────┐           ┌─────────────────┐   │
│  │  Left Channel   │           │  Right Channel  │   │
│  │  EQChain        │           │  EQChain        │   │
│  │  (64 bands)     │           │  (64 bands)     │   │
│  └─────────────────┘           └─────────────────┘   │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### Linked vs Stereo Mode

| Mode | Behaviour |
|------|-----------|
| **Linked** (default) | Both channels share the same EQ curve. Editing any band updates both left and right. |
| **Stereo** | Left and right channels have independent curves. Edit each channel separately. |

Use cases for stereo mode:

- **Driver variation compensation** — Headphone drivers can have minor frequency response differences between left and right
- **Room correction** — Room acoustics affect left and right speakers differently
- **Hearing compensation** — Compensate for asymmetric hearing between left and right ears

---

## Further Reading

- **[How It Works](./How-It-Works.md)** — Overview of the complete audio pipeline
- **[EQ Presets Guide](./EQ-Presets-Guide.md)** — Understanding factory presets
- **[RBJ Audio EQ Cookbook](https://webaudio.github.io/Audio-EQ-Cookbook/Audio-EQ-Cookbook.txt)** — The original reference
- **[Apple vDSP Documentation](https://developer.apple.com/documentation/accelerate/vdsp)** — Apple's DSP framework
