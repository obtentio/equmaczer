#include <stdbool.h>
#include <stdint.h>
bool recording_allocations_begin(void);
uint64_t recording_allocations_end(void);
void recording_allocation_probe_check(void);
