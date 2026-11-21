#ifndef AUDIO_TRANSPORT_ATOMICS_H
#define AUDIO_TRANSPORT_ATOMICS_H
#include <stddef.h>
#include <stdint.h>
uint32_t audio_transport_load_acquire(const void *base, size_t offset);
void audio_transport_initialize_u32(void *base, size_t offset, uint32_t value);
double audio_transport_load_f64_acquire(const void *base, size_t offset);
void audio_transport_initialize_f64(void *base, size_t offset, double value);
#endif
