/* P1-0 scope probe: an emitted uniqueness read against shared-count updates.
 * Both owners stay alive throughout; this probes the count, not reclamation. */
#define _POSIX_C_SOURCE 200809L
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct {
    _Alignas(8) uint32_t count;
    uint32_t kind;
    int64_t len, cap, reserved;
} Block;

extern bool p1_is_unique(Block *block);
static Block block = { .count = UINT32_C(0x80000002) };
static pthread_barrier_t ready;

static void *worker(void *unused) {
    (void)unused;
    pthread_barrier_wait(&ready);
    for (unsigned i = 0; i < 1000000; ++i) {
        __atomic_fetch_add(&block.count, 1, __ATOMIC_RELAXED);
        __atomic_fetch_sub(&block.count, 1, __ATOMIC_RELEASE);
    }
    return NULL;
}

int main(void) {
    pthread_t thread;
    if (pthread_barrier_init(&ready, NULL, 2) ||
        pthread_create(&thread, NULL, worker, NULL)) return 2;
    pthread_barrier_wait(&ready);
    unsigned unique = 0;
    for (unsigned i = 0; i < 1000000; ++i) unique += p1_is_unique(&block);
    if (pthread_join(thread, NULL) || pthread_barrier_destroy(&ready)) return 2;
    printf("unique=%u count=%08x\n", unique, block.count);
    return unique != 0 || block.count != UINT32_C(0x80000002);
}
