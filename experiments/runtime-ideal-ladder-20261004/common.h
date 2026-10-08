// Shared helpers for the ideal-ladder kernels (not part of any timed region's contract).
#ifndef LADDER_COMMON_H
#define LADDER_COMMON_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static inline int64_t now_ns(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

/* A failed compiler-inserted check: mylang traps (exit 1). */
static _Noreturn void trap(const char *what) {
    fprintf(stderr, "trap: %s\n", what);
    exit(1);
}

/* Python floor division / modulo on i64, as mylang's `//` and `%`. */
static inline int64_t floordiv(int64_t a, int64_t b) {
    int64_t q = a / b;
    if ((a % b != 0) && ((a < 0) != (b < 0))) q -= 1;
    return q;
}
static inline int64_t floormod(int64_t a, int64_t b) {
    int64_t r = a % b;
    if (r != 0 && ((r < 0) != (b < 0))) r += b;
    return r;
}

/* mylang list[int] today: a header (length, storage pointer) plus i64 elements. */
typedef struct { int64_t len; int64_t *data; } list_i64;

#define MOD 1000000007LL

#ifdef __AVX2__
#include <immintrin.h>
/* Horizontal sum of eight u32 lanes into a u64 (widen first: the lanes' sum can pass 2^32). */
static inline uint64_t hsum_u32x8(__m256i v) {
    __m256i w = _mm256_add_epi64(_mm256_cvtepu32_epi64(_mm256_castsi256_si128(v)),
                                 _mm256_cvtepu32_epi64(_mm256_extracti128_si256(v, 1)));
    __m128i a = _mm_add_epi64(_mm256_castsi256_si128(w), _mm256_extracti128_si256(w, 1));
    return (uint64_t)_mm_cvtsi128_si64(a) + (uint64_t)_mm_extract_epi64(a, 1);
}
#endif
#endif
