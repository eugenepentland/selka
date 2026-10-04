// branch_mixed ladder. Re-implements kind 3 of benchmarks/runtime/expanded/compute/main.my:
//   untimed: values[j] = (seed + j*37) % 1009;  flags[j] = (values[j]*73 + j*19 + seed) % 101 < 50
//   for batch in range(iterations):
//       phase = batch % 17
//       pass_total = sum over j of ((values[j] + phase)*3 + 1  if flags[j] else  (values[j] + phase)*5 + 7)
//       checksum = (checksum + pass_total) % 1000000007
// The flag pattern is pseudo-random (about half set), so the branch on flags[j] is hard to predict.
// Usage: branch_mixed VERSION SIZE ITERATIONS SEED [DATAFILE]
//   DATAFILE (any version): i64 values[SIZE] then u8 flags[SIZE]; used instead of the generated data.
// Prints "checksum elapsed_ns". Build with -fno-strict-aliasing.
#include "common.h"

/* ---- v1: today's semantics minus the per-iteration kind dispatch (as in the integer_math pilot):
 * bounds checks on both lists against headers the compiler cannot prove invariant, a data-dependent
 * branch on flags[j], checked multiply and add on whichever arm runs, checked accumulation. */
typedef struct { int64_t len; uint8_t *data; } list_bool;
__attribute__((noinline)) static int64_t v1(list_i64 *volatile vslot, list_bool *volatile fslot, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        for (int64_t j = 0; j < size; j++) {
            list_i64 *values = vslot;
            list_bool *flags = fslot;
            if ((uint64_t)j >= (uint64_t)values->len) trap("index");
            int64_t x = values->data[j], t, value;
            if ((uint64_t)j >= (uint64_t)flags->len) trap("index");
            if (__builtin_add_overflow(x, phase, &t)) trap("overflow");
            if (flags->data[j]) {
                if (__builtin_mul_overflow(t, 3, &value) || __builtin_add_overflow(value, 1, &value)) trap("overflow");
            } else {
                if (__builtin_mul_overflow(t, 5, &value) || __builtin_add_overflow(value, 7, &value)) trap("overflow");
            }
            if (__builtin_add_overflow(pass_total, value, &pass_total)) trap("overflow");
        }
        checksum = floormod(checksum + pass_total, MOD);
    }
    return checksum;
}

/* ---- v2: + value semantics and L2: both lists are immutable for the pass: headers in registers, one
 * bounds check each before the loop, sticky overflow flag tested after it. The branch on flags[j] is
 * still a branch: the untaken arm may trap on overflow, so it cannot be speculated. */
__attribute__((noinline)) static int64_t v2(const int64_t *restrict vals, const uint8_t *restrict flags, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        int bad = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t t, value;
            bad |= __builtin_add_overflow(vals[j], phase, &t);
            if (flags[j]) { bad |= __builtin_mul_overflow(t, 3, &value); bad |= __builtin_add_overflow(value, 1, &value); }
            else { bad |= __builtin_mul_overflow(t, 5, &value); bad |= __builtin_add_overflow(value, 7, &value); }
            bad |= __builtin_add_overflow(pass_total, value, &pass_total);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + pass_total, MOD);
    }
    return checksum;
}

/* ---- v3: + range facts: values in [0, 1009) (the `% 1009` comprehension), phase in [0, 17): neither arm
 * can overflow, so no arithmetic check remains in the loop (the accumulation keeps one sticky check). The
 * branch is still a branch; that is how a compiler without a speculation rule would leave it. */
__attribute__((noinline)) static int64_t v3(const int64_t *restrict vals, const uint8_t *restrict flags, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        int bad = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t x = vals[j];
            __builtin_assume(x >= 0 && x < 1009);
            int64_t t = x + phase, value;
            if (flags[j]) value = t * 3 + 1;
            else value = t * 5 + 7;
            bad |= __builtin_add_overflow(pass_total, value, &pass_total);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + pass_total, MOD);
    }
    return checksum;
}

/* ---- v4: + if-conversion: with no check left in either arm both are pure and cheap, so speculating the
 * untaken one is legal and the data-dependent branch becomes a select. (Written as a select; the compiler
 * is otherwise free to keep the branch.) i64 storage and arithmetic. */
__attribute__((noinline)) static int64_t v4(const int64_t *restrict vals, const uint8_t *restrict flags, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        int bad = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t x = vals[j];
            __builtin_assume(x >= 0 && x < 1009);
            int64_t t = x + phase;
            int64_t a = t * 3 + 1, b = t * 5 + 7;
            int64_t value = flags[j] ? a : b;
            bad |= __builtin_add_overflow(pass_total, value, &pass_total);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + pass_total, MOD);
    }
    return checksum;
}

/* ---- v5: + narrow widths in plain C (i32 arithmetic, u64 accumulation): lets LLVM's loop vectorizer use
 * 8-lane blends; storage still i64 for the values and bytes for the flags. */
__attribute__((noinline)) static int64_t v5(const int64_t *restrict vals, const uint8_t *restrict flags, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int32_t phase = (int32_t)(batch % 17);
        uint64_t pass_total = 0;
        for (int64_t j = 0; j < size; j++) {
            int32_t t = (int32_t)vals[j] + phase;
            int32_t value = flags[j] ? t * 3 + 1 : t * 5 + 7;
            pass_total += (uint32_t)value;
        }
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

/* ---- v6: v5 over u16 value storage (the representation a proven range allows). */
__attribute__((noinline)) static int64_t v6(const uint16_t *restrict vals, const uint8_t *restrict flags, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int32_t phase = (int32_t)(batch % 17);
        uint64_t pass_total = 0;
        for (int64_t j = 0; j < size; j++) {
            int32_t t = (int32_t)vals[j] + phase;
            int32_t value = flags[j] ? t * 3 + 1 : t * 5 + 7;
            pass_total += (uint32_t)value;
        }
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

/* ---- v8: v6 with the accumulation chunked: the element range bounds each term by 5127, so up to 2^19
 * terms fit a 32-bit accumulator; an inner loop of at most 4096 elements accumulates in u32 (a shape LLVM
 * vectorizes without widening every lane to 64 bits) and the chunk total is added to the checked 64-bit
 * sum. Plain C, u16 storage. */
__attribute__((noinline)) static int64_t v8(const uint16_t *restrict vals, const uint8_t *restrict flags, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        uint32_t phase = (uint32_t)(batch % 17);
        uint64_t pass_total = 0;
        for (int64_t base = 0; base < size; base += 4096) {
            int64_t end = base + 4096 < size ? base + 4096 : size;
            uint32_t acc = 0;
            for (int64_t j = base; j < end; j++) {
                uint32_t t = (uint32_t)vals[j] + phase;
                acc += flags[j] ? t * 3 + 1 : t * 5 + 7;
            }
            pass_total += acc;
        }
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

#ifdef __AVX2__
/* ---- v7: hand AVX2 on u16 storage: 16 elements per step: flags bytes widened to u16 lane masks, both
 * arms computed and blended, pair-summed with vpmaddwd into i32 lanes, flushed to the 64-bit total every
 * 128 steps (16-bit arms: t*5+7 <= 5127 here; per-lane i32 sums cannot overflow in a chunk). */
__attribute__((noinline)) static int64_t v7(const uint16_t *restrict vals, const uint8_t *restrict flags, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    const __m256i one = _mm256_set1_epi16(1), seven = _mm256_set1_epi16(7);
    for (int64_t batch = 0; batch < iterations; batch++) {
        const __m256i phase = _mm256_set1_epi16((short)(batch % 17));
        uint64_t pass_total = 0;
        int64_t j = 0;
        while (j + 16 <= size) {
            int64_t steps = (size - j) / 16;
            if (steps > 128) steps = 128;
            __m256i acc = _mm256_setzero_si256();
            for (int64_t k = 0; k < steps; k++, j += 16) {
                __m256i x = _mm256_add_epi16(_mm256_loadu_si256((const __m256i *)(vals + j)), phase);
                __m256i f = _mm256_cvtepu8_epi16(_mm_loadu_si128((const __m128i *)(flags + j)));
                __m256i m = _mm256_cmpgt_epi16(f, _mm256_setzero_si256());
                __m256i a = _mm256_add_epi16(_mm256_mullo_epi16(x, _mm256_set1_epi16(3)), one);
                __m256i b = _mm256_add_epi16(_mm256_mullo_epi16(x, _mm256_set1_epi16(5)), seven);
                acc = _mm256_add_epi32(acc, _mm256_madd_epi16(_mm256_blendv_epi8(b, a, m), one));
            }
            pass_total += hsum_u32x8(acc);
        }
        for (; j < size; j++) {
            uint32_t t = vals[j] + (uint32_t)(batch % 17);
            pass_total += flags[j] ? t * 3 + 1 : t * 5 + 7;
        }
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}
#endif /* __AVX2__ */

/* ===================== holdout: values and flags read from a file ==================== */

/* v30: the best version with no range facts: L2 form (immutable lists, hoisted bounds, sticky
 * overflow), both arms with overflow checks but computed branch-free into the sticky flag (the checks
 * are flags, not traps, so speculating both arms is legal); selects the value; i64 arithmetic. */
__attribute__((noinline)) static int64_t v30(const int64_t *restrict vals, const uint8_t *restrict flags, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        int bad = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t t, a, b;
            int f = flags[j] != 0;
            int ot = __builtin_add_overflow(vals[j], phase, &t);
            int oa = __builtin_mul_overflow(t, 3, &a) | __builtin_add_overflow(a, 1, &a);
            int ob = __builtin_mul_overflow(t, 5, &b) | __builtin_add_overflow(b, 7, &b);
            bad |= ot | (f ? oa : ob);
            bad |= __builtin_add_overflow(pass_total, f ? a : b, &pass_total);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + pass_total, MOD);
    }
    return checksum;
}

#ifdef __AVX2__
/* v31: runtime range guard + AVX2. One pass over the immutable values proves 0 <= x < 2^26 (then the
 * arms fit in 31 bits); the batch loop uses 8 i32 lanes widened to i64 for the sum. Otherwise v30. */
__attribute__((noinline)) static int64_t v31(const int64_t *restrict vals, const uint8_t *restrict flags, int64_t size, int64_t iterations) {
    int64_t mn = 0, mx = 0;
    for (int64_t j = 0; j < size; j++) { if (vals[j] < mn) mn = vals[j]; if (vals[j] > mx) mx = vals[j]; }
    if (mn < 0 || mx >= (1 << 26)) return v30(vals, flags, size, iterations);
    int32_t *v32 = malloc((size_t)size * 4 + 64);
    for (int64_t j = 0; j < size; j++) v32[j] = (int32_t)vals[j];
    int64_t checksum = 0;
    const __m256i one = _mm256_set1_epi32(1), seven = _mm256_set1_epi32(7), three = _mm256_set1_epi32(3), five = _mm256_set1_epi32(5);
    for (int64_t batch = 0; batch < iterations; batch++) {
        const __m256i phase = _mm256_set1_epi32((int)(batch % 17));
        __m256i acc = _mm256_setzero_si256();
        int64_t j = 0;
        for (; j + 8 <= size; j += 8) {
            __m256i x = _mm256_add_epi32(_mm256_loadu_si256((const __m256i *)(v32 + j)), phase);
            __m256i m = _mm256_cmpgt_epi32(_mm256_cvtepu8_epi32(_mm_loadl_epi64((const __m128i *)(flags + j))), _mm256_setzero_si256());
            __m256i a = _mm256_add_epi32(_mm256_mullo_epi32(x, three), one);
            __m256i b = _mm256_add_epi32(_mm256_mullo_epi32(x, five), seven);
            __m256i v = _mm256_blendv_epi8(b, a, m);
            acc = _mm256_add_epi64(acc, _mm256_add_epi64(_mm256_cvtepu32_epi64(_mm256_castsi256_si128(v)),
                                                         _mm256_cvtepu32_epi64(_mm256_extracti128_si256(v, 1))));
        }
        uint64_t part[4];
        _mm256_storeu_si256((__m256i *)part, acc);
        int64_t pass_total = (int64_t)(part[0] + part[1] + part[2] + part[3]);
        for (; j < size; j++) {
            int64_t t = (int64_t)v32[j] + (batch % 17);
            pass_total += flags[j] ? t * 3 + 1 : t * 5 + 7;
        }
        checksum = floormod(checksum + pass_total, MOD);
    }
    free(v32);
    return checksum;
}
#endif /* __AVX2__ */

/* =========================================== main ====================================== */
int main(int argc, char **argv) {
    if (argc == 5 && !strcmp(argv[1], "gen")) {
        int64_t size = atoll(argv[2]), seed = atoll(argv[3]);
        FILE *f = fopen(argv[4], "wb");
        int64_t *v = malloc(8 * (size_t)size);
        uint8_t *fl = malloc((size_t)size);
        for (int64_t j = 0; j < size; j++) { v[j] = (seed + j * 37) % 1009; fl[j] = (v[j] * 73 + j * 19 + seed) % 101 < 50; }
        fwrite(v, 8, (size_t)size, f); fwrite(fl, 1, (size_t)size, f);
        fclose(f);
        return 0;
    }
    if (argc == 6 && !strcmp(argv[1], "genwide")) { /* genwide SIZE SEED MAX PATH: random values in [0, MAX], random flags */
        int64_t size = atoll(argv[2]), seed = atoll(argv[3]), max = atoll(argv[4]);
        FILE *f = fopen(argv[5], "wb");
        uint64_t s = (uint64_t)seed * 6364136223846793005ULL + 1442695040888963407ULL;
        int64_t *v = malloc(8 * (size_t)size);
        uint8_t *fl = malloc((size_t)size);
        for (int64_t j = 0; j < size; j++) {
            s = s * 6364136223846793005ULL + 1442695040888963407ULL;
            v[j] = (int64_t)((s >> 1) % (uint64_t)(max + 1));
            s = s * 6364136223846793005ULL + 1442695040888963407ULL;
            fl[j] = (s >> 62) & 1;
        }
        fwrite(v, 8, (size_t)size, f); fwrite(fl, 1, (size_t)size, f);
        fclose(f);
        return 0;
    }
    if (argc < 5) return 2;
    int which = atoi(argv[1]);
    int64_t size = atoll(argv[2]), iterations = atoll(argv[3]), seed = atoll(argv[4]);
    int64_t *data = malloc(8 * (size_t)size);
    uint8_t *flags = malloc((size_t)size + 64);
    if (argc == 6) {
        FILE *f = fopen(argv[5], "rb");
        if (!f || fread(data, 8, (size_t)size, f) != (size_t)size || fread(flags, 1, (size_t)size, f) != (size_t)size) { fprintf(stderr, "bad data file\n"); return 2; }
        fclose(f);
    } else {
        if (which >= 30) return 2;
        for (int64_t j = 0; j < size; j++) { data[j] = (seed + j * 37) % 1009; flags[j] = (data[j] * 73 + j * 19 + seed) % 101 < 50; }
    }
    uint16_t *narrow = malloc(2 * (size_t)size + 64);
    for (int64_t j = 0; j < size; j++) narrow[j] = (uint16_t)data[j];
    list_i64 values = {size, data};
    list_bool fl = {size, flags};
    list_i64 *volatile vslot = &values;
    list_bool *volatile fslot = &fl;
    int64_t start = now_ns(), checksum = 0;
    switch (which) {
    case 1: case 20: checksum = v1(vslot, fslot, size, iterations); break;
    case 2: checksum = v2(data, flags, size, iterations); break;
    case 3: checksum = v3(data, flags, size, iterations); break;
    case 4: checksum = v4(data, flags, size, iterations); break;
    case 5: checksum = v5(data, flags, size, iterations); break;
    case 6: checksum = v6(narrow, flags, size, iterations); break;
    case 8: checksum = v8(narrow, flags, size, iterations); break;
    case 30: checksum = v30(data, flags, size, iterations); break;
#ifdef __AVX2__
    case 7: checksum = v7(narrow, flags, size, iterations); break;
    case 31: checksum = v31(data, flags, size, iterations); break;
#endif
    default: return 2;
    }
    printf("%lld %lld\n", (long long)checksum, (long long)(now_ns() - start));
    return 0;
}
