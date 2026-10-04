// Hand-written integer_math kernel variants. Same inputs, same checksum as
// benchmarks/runtime/expanded/compute/main.my kind 0. Prints "checksum elapsed_ns".
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int64_t now_ns(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

static _Noreturn void trap(const char *what) {
    fprintf(stderr, "trap: %s\n", what);
    exit(1);
}

static int64_t floordiv(int64_t a, int64_t b) {
    int64_t q = a / b;
    if ((a % b != 0) && ((a < 0) != (b < 0))) q -= 1;
    return q;
}
static int64_t floormod(int64_t a, int64_t b) {
    int64_t r = a % b;
    if (r != 0 && ((r < 0) != (b < 0))) r += b;
    return r;
}

/* V1: today's semantics, minus the per-iteration dispatch. Exact checked i64
 * arithmetic with a trap at the failing operation, Python floor // and %,
 * and a per-iteration bounds check against a length re-read from a header
 * the compiler cannot prove invariant. */
typedef struct { int64_t len; int64_t *data; } list;
__attribute__((noinline)) static int64_t v1(list *volatile values_slot, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        for (int64_t j = 0; j < size; j++) {
            list *values = values_slot;
            if ((uint64_t)j >= (uint64_t)values->len) trap("index");
            int64_t x = values->data[j], t;
            if (__builtin_add_overflow(x, phase, &t)) trap("overflow");
            if (__builtin_mul_overflow(t, 17, &t)) trap("overflow");
            if (__builtin_add_overflow(t, 23, &t)) trap("overflow");
            int64_t value = floormod(floordiv(t, 7), 1009);
            if (__builtin_add_overflow(pass_total, value, &pass_total)) trap("overflow");
        }
        checksum = floormod(checksum + pass_total, 1000000007);
    }
    return checksum;
}

/* V2: L2 + value-semantics facts. The list is immutable for the loop
 * (header in registers, one bounds check before the loop) and overflow is
 * tracked in a sticky flag tested after the inner loop. Still i64 and Python
 * floor semantics; no range knowledge about the elements. */
__attribute__((noinline)) static int64_t v2(const list *values, int64_t size, int64_t iterations) {
    const int64_t *restrict data = values->data;
    if (size > values->len) trap("index");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        int overflow = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t t, u, w;
            overflow |= __builtin_add_overflow(data[j], phase, &t);
            overflow |= __builtin_mul_overflow(t, 17, &u);
            overflow |= __builtin_add_overflow(u, 23, &w);
            int64_t value = floormod(floordiv(w, 7), 1009);
            overflow |= __builtin_add_overflow(pass_total, value, &pass_total);
        }
        if (overflow) trap("overflow");
        checksum = floormod(checksum + pass_total, 1000000007);
    }
    return checksum;
}

/* V3: V2 + element range facts: every element is in [0, 1009) because the
 * list was built by `[(seed + j * 37) % 1009 for j in range(size)]` and is
 * never mutated; phase is in [0, 17). Overflow is then impossible, floor ==
 * truncation, and every intermediate fits in 32 bits. */
__attribute__((noinline)) static int64_t v3(const list *values, int64_t size, int64_t iterations) {
    const int64_t *restrict data = values->data;
    if (size > values->len) trap("index");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        uint32_t phase = (uint32_t)(batch % 17);
        uint64_t pass_total = 0;
        for (int64_t j = 0; j < size; j++) {
            uint32_t x = (uint32_t)data[j];
            pass_total += ((x + phase) * 17u + 23u) / 7u % 1009u;
        }
        checksum = (int64_t)(((uint64_t)checksum + pass_total) % 1000000007u);
    }
    return checksum;
}

/* V4: V3 + representation choice: the list's element type is narrowed to
 * u16 storage because every element is proven < 1009 (a compiler that owns
 * the representation of an immutable list[int] may pick it). */
__attribute__((noinline)) static int64_t v4(const uint16_t *restrict data, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        uint32_t phase = (uint32_t)(batch % 17);
        uint64_t pass_total = 0;
        for (int64_t j = 0; j < size; j++) {
            uint32_t x = data[j];
            pass_total += ((x + phase) * 17u + 23u) / 7u % 1009u;
        }
        checksum = (int64_t)(((uint64_t)checksum + pass_total) % 1000000007u);
    }
    return checksum;
}


/* V5: V2's i64 code, but the compiler is only *told* the ranges (no manual
 * narrowing): elements in [0, 1009), phase in [0, 17). Checks that provably
 * cannot fire are dropped, as a range-aware compiler would. */
__attribute__((noinline)) static int64_t v5(const list *values, int64_t size, int64_t iterations) {
    const int64_t *restrict data = values->data;
    if (size > values->len) trap("index");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t x = data[j];
            __builtin_assume(x >= 0 && x < 1009);
            int64_t w = (x + phase) * 17 + 23;
            pass_total += floormod(floordiv(w, 7), 1009);
        }
        checksum = floormod(checksum + pass_total, 1000000007);
    }
    return checksum;
}

#include <immintrin.h>
/* 16 lanes of u16: every intermediate is <= 17448 given the range facts. */
static inline __m256i pass16(__m256i x, __m256i phase) {
    __m256i t = _mm256_add_epi16(x, phase);
    t = _mm256_add_epi16(_mm256_mullo_epi16(t, _mm256_set1_epi16(17)), _mm256_set1_epi16(23));
    __m256i q = _mm256_srli_epi16(_mm256_mulhi_epu16(t, _mm256_set1_epi16((short)18725)), 1);
    __m256i m = _mm256_set1_epi16(1009), lim = _mm256_set1_epi16(1008);
    q = _mm256_sub_epi16(q, _mm256_and_si256(_mm256_cmpgt_epi16(q, lim), m));
    q = _mm256_sub_epi16(q, _mm256_and_si256(_mm256_cmpgt_epi16(q, lim), m));
    return _mm256_madd_epi16(q, _mm256_set1_epi16(1));   /* 8 x i32 pair sums */
}
static inline uint64_t hsum32(__m256i v) {
    __m128i a = _mm_add_epi32(_mm256_castsi256_si128(v), _mm256_extracti128_si256(v, 1));
    a = _mm_add_epi32(a, _mm_shuffle_epi32(a, 0x4e));
    a = _mm_add_epi32(a, _mm_shuffle_epi32(a, 0xb1));
    return (uint32_t)_mm_cvtsi128_si32(a);
}
static inline uint32_t scalar1(uint32_t x, uint32_t phase) { return ((x + phase) * 17u + 23u) / 7u % 1009u; }

/* V6: hand-vectorized (intrinsics = instructions), i64 list storage as today.
 * Two packus levels turn 16 i64 elements into 16 u16 lanes; order is
 * irrelevant because the loop only sums. */
__attribute__((noinline)) static int64_t v6(const list *values, int64_t size, int64_t iterations) {
    const int64_t *restrict data = values->data;
    if (size > values->len) trap("index");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        uint32_t ph = (uint32_t)(batch % 17);
        __m256i phase = _mm256_set1_epi16((short)ph), acc = _mm256_setzero_si256();
        int64_t j = 0;
        for (; j + 16 <= size; j += 16) {
            const __m256i *p = (const __m256i *)(data + j);
            __m256i a = _mm256_packus_epi32(_mm256_loadu_si256(p), _mm256_loadu_si256(p + 1));
            __m256i b = _mm256_packus_epi32(_mm256_loadu_si256(p + 2), _mm256_loadu_si256(p + 3));
            acc = _mm256_add_epi32(acc, pass16(_mm256_packus_epi32(a, b), phase));
        }
        uint64_t pass_total = hsum32(acc);
        for (; j < size; j++) pass_total += scalar1((uint32_t)data[j], ph);
        checksum = (int64_t)(((uint64_t)checksum + pass_total) % 1000000007u);
    }
    return checksum;
}

/* V7: hand-vectorized with u16 storage (the representation a compiler could
 * pick for an immutable list whose elements are proven < 1009). */
__attribute__((noinline)) static int64_t v7(const uint16_t *restrict data, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        uint32_t ph = (uint32_t)(batch % 17);
        __m256i phase = _mm256_set1_epi16((short)ph), acc = _mm256_setzero_si256();
        int64_t j = 0;
        for (; j + 16 <= size; j += 16)
            acc = _mm256_add_epi32(acc, pass16(_mm256_loadu_si256((const __m256i *)(data + j)), phase));
        uint64_t pass_total = hsum32(acc);
        for (; j < size; j++) pass_total += scalar1(data[j], ph);
        checksum = (int64_t)(((uint64_t)checksum + pass_total) % 1000000007u);
    }
    return checksum;
}

/* V8: work elimination. pass_total depends only on phase (17 values) and an
 * immutable list, so compute 17 totals once and look them up. Legal for a
 * compiler in principle; shown only to mark where "fastest possible" stops
 * meaning anything without a work contract. */
__attribute__((noinline)) static int64_t v8(const uint16_t *restrict data, int64_t size, int64_t iterations) {
    uint64_t table[17];
    for (uint32_t ph = 0; ph < 17; ph++) {
        uint64_t t = 0;
        for (int64_t j = 0; j < size; j++) t += scalar1(data[j], ph);
        table[ph] = t;
    }
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++)
        checksum = (int64_t)(((uint64_t)checksum + table[batch % 17]) % 1000000007u);
    return checksum;
}

/* V9/V10: plain C, but the arithmetic is written at the narrowest width the
 * range facts allow (u16), as a range-aware front end would emit it. No
 * intrinsics: LLVM chooses the vector code. V9 reads today's i64 storage,
 * V10 reads u16 storage. */
__attribute__((noinline)) static int64_t v9(const list *values, int64_t size, int64_t iterations) {
    const int64_t *restrict data = values->data;
    if (size > values->len) trap("index");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        uint16_t ph = (uint16_t)(batch % 17);
        uint32_t pass_total = 0;
        for (int64_t j = 0; j < size; j++) {
            uint16_t t = (uint16_t)((uint16_t)((uint16_t)data[j] + ph) * 17 + 23);
            uint16_t q = (uint16_t)(t / 7);
            pass_total += (uint16_t)(q % 1009);
        }
        checksum = (int64_t)(((uint64_t)checksum + pass_total) % 1000000007u);
    }
    return checksum;
}
__attribute__((noinline)) static int64_t v10(const uint16_t *restrict data, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        uint16_t ph = (uint16_t)(batch % 17);
        uint32_t pass_total = 0;
        for (int64_t j = 0; j < size; j++) {
            uint16_t t = (uint16_t)((uint16_t)(data[j] + ph) * 17 + 23);
            uint16_t q = (uint16_t)(t / 7);
            pass_total += (uint16_t)(q % 1009);
        }
        checksum = (int64_t)(((uint64_t)checksum + pass_total) % 1000000007u);
    }
    return checksum;
}

int main(int argc, char **argv) {
    if (argc != 5) return 2;
    int which = atoi(argv[1]);
    int64_t size = atoll(argv[2]), iterations = atoll(argv[3]), seed = atoll(argv[4]);
    int64_t *data = malloc(sizeof(int64_t) * size);
    uint16_t *narrow = malloc(sizeof(uint16_t) * size);
    for (int64_t j = 0; j < size; j++) { data[j] = (seed + j * 37) % 1009; narrow[j] = (uint16_t)data[j]; }
    list values = {size, data};
    list *volatile slot = &values;
    int64_t start = now_ns(), checksum = 0;
    switch (which) {
    case 1: checksum = v1(slot, size, iterations); break;
    case 2: checksum = v2(&values, size, iterations); break;
    case 3: checksum = v3(&values, size, iterations); break;
    case 4: checksum = v4(narrow, size, iterations); break;
    case 5: checksum = v5(&values, size, iterations); break;
    case 6: checksum = v6(&values, size, iterations); break;
    case 7: checksum = v7(narrow, size, iterations); break;
    case 8: checksum = v8(narrow, size, iterations); break;
    case 9: checksum = v9(&values, size, iterations); break;
    case 10: checksum = v10(narrow, size, iterations); break;
    default: return 2;
    }
    printf("%lld %lld\n", (long long)checksum, (long long)(now_ns() - start));
    return 0;
}
