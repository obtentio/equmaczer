#ifndef EQ_SHARED_MEMORY_ACCESS_H
#define EQ_SHARED_MEMORY_ACCESS_H
#include <stdatomic.h>
#include <stdbool.h>
#include <sched.h>
#include <sys/types.h>

// Callback: one lock-free attempt, never spin or wait. Control thread may wait
// for the current writer before replacing/unmapping its storage.
typedef struct { atomic_flag busy; } EQSharedMemoryAccess;
#define EQ_SHARED_MEMORY_ACCESS_INIT { ATOMIC_FLAG_INIT }
static inline bool EQSharedMemoryMayReplace(bool active, uid_t owner, uid_t caller) {
    return !active || owner == caller;
}
static inline bool EQSharedMemoryTryAcquire(EQSharedMemoryAccess *access) {
    return !atomic_flag_test_and_set_explicit(&access->busy, memory_order_acquire);
}
static inline void EQSharedMemoryAcquireForControl(EQSharedMemoryAccess *access) {
    while (!EQSharedMemoryTryAcquire(access)) { sched_yield(); }
}
static inline void EQSharedMemoryRelease(EQSharedMemoryAccess *access) {
    atomic_flag_clear_explicit(&access->busy, memory_order_release);
}
#endif
