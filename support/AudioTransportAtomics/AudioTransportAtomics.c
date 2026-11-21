#include "AudioTransportAtomics.h"
#include <stdatomic.h>
_Static_assert(sizeof(_Atomic(uint32_t)) == sizeof(uint32_t), "Driver header ABI requires 32-bit atomics");
_Static_assert(_Alignof(_Atomic(uint32_t)) == _Alignof(uint32_t), "Driver header alignment must match");
_Static_assert(sizeof(_Atomic(double)) == sizeof(double), "Driver sample-rate ABI must match");
_Static_assert(_Alignof(_Atomic(double)) == _Alignof(double), "Driver sample-rate alignment must match");
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "64-bit header access must be lock-free");
_Static_assert(__atomic_always_lock_free(sizeof(double), 0), "Sample-rate operations must be lock-free");
uint32_t audio_transport_load_acquire(const void *base, size_t offset) {
    const _Atomic(uint32_t) *field = (const _Atomic(uint32_t) *)((const unsigned char *)base + offset);
    return atomic_load_explicit(field, memory_order_acquire);
}
void audio_transport_initialize_u32(void *base, size_t offset, uint32_t value) {
    _Atomic(uint32_t) *field = (_Atomic(uint32_t) *)((unsigned char *)base + offset);
    atomic_init(field, value);
}
double audio_transport_load_f64_acquire(const void *base, size_t offset) {
    const _Atomic(double) *field = (const _Atomic(double) *)((const unsigned char *)base + offset);
    return atomic_load_explicit(field, memory_order_acquire);
}
void audio_transport_initialize_f64(void *base, size_t offset, double value) {
    _Atomic(double) *field = (_Atomic(double) *)((unsigned char *)base + offset);
    atomic_init(field, value);
}
