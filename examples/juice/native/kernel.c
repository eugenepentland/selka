/* A small, complete workload. Change SLOW to 0 to improve the application;
 * keep this file fixed and change compiler/flags to compare backends. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>

#ifndef SLOW
#define SLOW 1
#endif
#ifndef ATOMIC
#define ATOMIC 0
#endif
#ifndef EXTRA_COPY
#define EXTRA_COPY 0
#endif

static _Atomic uint64_t audit;

__attribute__((noinline)) unsigned bit_count(uint32_t value) {
#if SLOW
    unsigned result = 0;
    for (unsigned bit = 0; bit < 32; ++bit) result += (value >> bit) & 1;
    return result;
#else
    return (unsigned)__builtin_popcount(value);
#endif
}

__attribute__((noinline)) uint64_t process_records(const uint32_t *data, size_t count, unsigned rounds) {
    uint64_t result = 0;
    for (unsigned round = 0; round < rounds; ++round) {
        for (size_t i = 0; i < count; ++i) {
            uint32_t value = data[i];
#if EXTRA_COPY
            volatile uint32_t copy[8];
            /* Keep the copying fixture independent of tiny-loop delivery
             * variability. Volatile preserves all eight stores and the load. */
            copy[0] = value;
            copy[1] = value;
            copy[2] = value;
            copy[3] = value;
            copy[4] = value;
            copy[5] = value;
            copy[6] = value;
            copy[7] = value;
            value = copy[round % 8];
#endif
            unsigned bits = bit_count(value);
#if ATOMIC
            atomic_fetch_add_explicit(&audit, bits, memory_order_relaxed);
#endif
            result += bits;
        }
    }
    return result;
}

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    size_t count = strtoul(argv[1], NULL, 10);
    unsigned rounds = (unsigned)strtoul(argv[2], NULL, 10);
    if (!count || count > 1048576 || !rounds || rounds > 10000) return 2;
    uint32_t *data = malloc(count * sizeof(*data));
    if (!data) return 2;
    uint32_t state = 0x12345678;
    for (size_t i = 0; i < count; ++i) {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        data[i] = state;
    }
    printf("%llu\n", (unsigned long long)process_records(data, count, rounds));
    free(data);
    return 0;
}
