/* Build from the repository root:
 *   cc -O2 -std=c11 -I src src/native_heap.c src/native_arena.c src/native_collections.c \
 *      src/native_text.c src/native_dictionary.c src/native_equal.c <this file> */
#define _POSIX_C_SOURCE 200809L
/* Minor-collection rescan cost: one old list of N small objects, then many minor collections. */
#include "native_heap.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static const myl_native_type ptr = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_POINTER};
static const myl_native_type leaf = {.size = 40, .alignment = 8, .kind = MYL_NATIVE_PLAIN, .trace_mode = MYL_NATIVE_TRACE_NONE};
int main(int argc, char **argv) {
    size_t n = argc > 1 ? (size_t)atol(argv[1]) : 200000;
    int minors = argc > 2 ? atoi(argv[2]) : 200;
    myl_native_heap heap;
    myl_native_heap_init(&heap, SIZE_MAX);
    void **list = myl_native_heap_alloc(&heap, &ptr, n);
    myl_native_root root;
    myl_native_root_push(&heap, &root, &list, &ptr);
    for (size_t i = 0; i < n; i++) list[i] = myl_native_heap_alloc(&heap, &leaf, 1);
    if (getenv("SHUFFLE")) {
        unsigned long long x = 88172645463325252ULL;
        for (size_t i = n - 1; i > 0; i--) {
            x ^= x << 13; x ^= x >> 7; x ^= x << 17;
            size_t j = (size_t)(x % (i + 1));
            void *t = list[i]; list[i] = list[j]; list[j] = t;
        }
    }
    myl_native_heap_collect(&heap);
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    for (int m = 0; m < minors; m++) {
        heap.next_collection = heap.bytes;
        myl_native_heap_alloc(&heap, &leaf, 1);
    }
    clock_gettime(CLOCK_MONOTONIC, &b);
    double ms = (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6;
    printf("n %zu minors %zu: %.3f ms per minor, %.2f ns per element\n", n, heap.generations.minor_collections, ms / minors, ms * 1e6 / minors / (double)n);
    return 0;
}
