// Isolated lifetime test; does not load the HAL driver or touch live audio.
#include "../src/SharedMemoryAccess.h"
#include "../src/ClientIdentity.h"
#include <unistd.h>
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static EQSharedMemoryAccess accessGate = EQ_SHARED_MEMORY_ACCESS_INIT;
static _Atomic bool ready = false;
static _Atomic bool done = false;
static uint64_t *mapping;
static unsigned callbacks;
static unsigned skipped;
static void *render(void *unused) {
    (void)unused;
    while (!atomic_load_explicit(&done, memory_order_acquire)) {
        if (EQSharedMemoryTryAcquire(&accessGate)) {
            assert(mapping != NULL);
            assert(mapping[0] == UINT64_C(0xE0AC2345));
            mapping[1]++;
            callbacks++;
            atomic_store_explicit(&ready, true, memory_order_release);
            EQSharedMemoryRelease(&accessGate);
        } else { skipped++; }
    }
    return NULL;
}
int main(void) {
    uid_t uid;
    assert(EQClientUID(getpid(), &uid));
    assert(uid == geteuid());
    assert(!EQClientUID(-1, &uid));
    assert(!EQClientUID(0, &uid));
    assert(EQSharedMemoryMayReplace(false, (uid_t)-1, 501));
    assert(EQSharedMemoryMayReplace(true, 501, 501));
    assert(!EQSharedMemoryMayReplace(true, 501, 502));
    // The callback must return immediately when control owns the mapping.
    EQSharedMemoryAcquireForControl(&accessGate);
    assert(!EQSharedMemoryTryAcquire(&accessGate));
    EQSharedMemoryRelease(&accessGate);
    mapping = calloc(8, sizeof(uint64_t));
    assert(mapping);
    mapping[0] = UINT64_C(0xE0AC2345);
    pthread_t worker;
    assert(pthread_create(&worker, NULL, render, NULL) == 0);
    while (!atomic_load_explicit(&ready, memory_order_acquire)) { sched_yield(); }
    for (unsigned i = 0; i < 20000; i++) {
        EQSharedMemoryAcquireForControl(&accessGate);
        free(mapping);
        mapping = calloc(8, sizeof(uint64_t));
        assert(mapping);
        mapping[0] = UINT64_C(0xE0AC2345);
        EQSharedMemoryRelease(&accessGate);
        if (i % 8 == 0) { sched_yield(); }
    }
    atomic_store_explicit(&done, true, memory_order_release);
    assert(pthread_join(worker, NULL) == 0);
    assert(callbacks > 0);
    free(mapping);
    printf("PASS: 20000 replacements, %u callback accesses, %u nonblocking skips\n", callbacks, skipped);
    return 0;
}
