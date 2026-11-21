// Test-only Darwin malloc logger. Counts allocation events on the calling thread,
// including transient allocations; it does not infer allocations from live bytes.
#include "RecordingAllocationProbe.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdatomic.h>

typedef void (*logger_t)(uint32_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uint32_t);
static logger_t previous;
static bool installed;
static pthread_once_t once = PTHREAD_ONCE_INIT;
static _Atomic(uintptr_t) measuredThread;
static _Atomic(uint64_t) allocations;

static void log_allocation(uint32_t type, uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t result, uint32_t skip) {
    // Darwin MALLOC_LOG_TYPE_ALLOCATE = 2; includes malloc/calloc/realloc.
    if (atomic_load_explicit(&measuredThread, memory_order_relaxed) == (uintptr_t)pthread_self() && (type & 2))
        atomic_fetch_add_explicit(&allocations, 1, memory_order_relaxed);
    if (previous) previous(type, a, b, c, result, skip);
}

static void install(void) {
    logger_t *slot = (logger_t *)dlsym(RTLD_DEFAULT, "malloc_logger");
    if (!slot) return;
    previous = *slot;
    *slot = log_allocation;
    installed = true;
}

bool recording_allocations_begin(void) {
    pthread_once(&once, install);
    atomic_store(&allocations, 0);
    atomic_store(&measuredThread, installed ? (uintptr_t)pthread_self() : 0);
    return installed;
}
uint64_t recording_allocations_end(void) {
    atomic_store(&measuredThread, 0);
    return atomic_load(&allocations);
}
void recording_allocation_probe_check(void) {
    // Volatile access prevents the optimiser removing the malloc/free pair.
    volatile char *p = malloc(37);
    if (p) { *p = 1; free((void *)p); }
}
