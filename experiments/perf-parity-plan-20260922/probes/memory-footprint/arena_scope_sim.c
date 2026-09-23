/* Build from the repository root:
 *   cc -O2 -std=c11 -I src src/native_heap.c src/native_arena.c src/native_collections.c \
 *      src/native_text.c src/native_dictionary.c src/native_equal.c <this file> */
#define _POSIX_C_SOURCE 200809L
/* Closing short inner arena scopes under an outer arena that holds many chunks. */
#include "native_heap.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static const myl_native_type wide = {.size = 64, .alignment = 16, .kind = MYL_NATIVE_PLAIN, .trace_mode = MYL_NATIVE_TRACE_NONE};
int main(int argc, char **argv) {
    size_t outer = argc > 1 ? (size_t)atol(argv[1]) : 100000;
    int rounds = argc > 2 ? atoi(argv[2]) : 100000;
    myl_native_heap heap;
    myl_native_heap_init(&heap, SIZE_MAX);
    myl_native_region_begin(&heap);
    for (size_t i = 0; i < outer; i++) myl_native_heap_alloc(&heap, &wide, 16);
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    for (int r = 0; r < rounds; r++) {
        myl_native_region_begin(&heap);
        myl_native_heap_alloc(&heap, &wide, 1);
        myl_native_heap_alloc_at(&heap, &wide, 1, 1);
        myl_native_region_end(&heap);
    }
    clock_gettime(CLOCK_MONOTONIC, &b);
    double ns = ((b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec)) / rounds;
    printf("outer chunks %zu: %.0f ns per inner scope\n", heap.arena.chunks_live, ns);
    return 0;
}
