# Real-time audio safety

Updated for recovery 1.3.5, 20 November 2026.

## Render-thread rules

Never allocate or free memory, acquire locks, block, perform I/O, log, invoke UI/Objective-C APIs or schedule tasks inside the audio callback. Preallocate buffers and filter state. Use bounded work. Actor isolation does not itself protect raw pointers crossing to Core Audio callbacks.

## EQ coefficient publication

Each `EQChain` has three preallocated snapshots. The producer alone owns a canonical staging state and a back snapshot. The consumer alone owns a front snapshot. An atomic integer holds the middle snapshot index and a dirty bit.

1. Producer updates its canonical state and copies it into its owned back snapshot.
2. Producer exchanges back with middle using acquire/release ordering, publishing a complete snapshot with the dirty bit set.
3. At a callback boundary, the consumer checks the dirty bit. If set, it exchanges its front with middle using acquire/release ordering.
4. Consumer applies only its newly owned front snapshot. The producer cannot obtain that buffer until the consumer exchanges it out on a subsequent callback.

Publication is latest-value-wins; intermediate edits can coalesce. A monotonically increasing full-reset generation survives coalescing of full and incremental updates. Callback consumption uses one exchange and a fixed-size pass, with no spin loop or allocations.

This is single-producer/single-consumer. All staging calls for a chain must be serialised on the producer side. Do not call staging from a second producer. Do not reuse snapshots or change ownership without an atomic exchange.

The old pattern—read plain shared coefficients, apply them to live filters, then check a sequence counter—was unsafe. An atomic flag/counter does not protect the payload from concurrent mutation.

## Capture and lifecycle

`AudioRingBuffer` uses SPSC producer/consumer indices. Shared-memory file creation, ACL setup, mapping and cleanup occur off the render thread. Shared-memory header indices/rates/counts are treated as external input and checked before buffer access. Driver 1.1.3 checks mapped file ownership against the property caller, regular-file type, link count, permissions, size and allowed path.

The mapped header's UInt32 fields use the small `AudioTransportAtomics` C11 bridge for atomic initialisation and acquire loads, paired with the driver's release stores. A Swift raw-pointer load followed by a memory barrier is not an atomic load. Compile-time size/alignment assertions and an ABI test protect the shared layout.

Channel count and sample rate also use C11 atomics, including verified lock-free 64-bit sample-rate access. The HAL shared-memory writer makes one atomic-flag attempt before touching the mapping; if control owns the flag, it skips that shared-memory block. The property setter may wait off the render thread before replacing/unmapping storage. This protects mapping lifetime without adding a blocking callback lock. The existing HAL loopback path still has its own legacy I/O mutex; this change does not certify the entire driver as lock-free.

`driver/tests/SharedMemoryLifetimeTests.c` exercises the actual access guard while replacing/freeing backing storage 20,000 times concurrently. Run it under Thread Sanitizer and Address Sanitizer as shown in `.github/workflows/verify.yml`. It does not load the HAL driver or manipulate live audio.

Stop callbacks before destroying contexts, rings, mapped memory or filter buffers. Unsafe/nonisolated fields require explicit ownership or synchronisation; compiler silence is not a proof of safety.

## Verification

Run `swift test --sanitize=thread --filter PublicationRecoveryTests` with the required local build/cache options. Its writer and renderer intentionally overlap; the historical semaphore test verifies handoff order but does not test overlap.

Run the release executable with `--stress-benchmark` for the 64-frame/96 kHz, stereo, four-layer, 64-band stress measurement. It includes ring transport, limiting and loudness/spectrum processing, but excludes OS scheduling, HAL device I/O and actual end-to-end latency. Test those on physical devices separately.

`Task.sleep` suspends an async task; it does not block its thread. Neither an arbitrary sleep nor a dispatch delay is a reliable device-readiness acknowledgement. Prefer explicit lifecycle/device signals and verify the actual frame stream.
