// float_math ladder. Re-implements kind 1 of benchmarks/runtime/expanded/compute/main.my:
//   value = int(((float(x)/8.0 + float(phase)/4.0) * (float(x)/16.0 + 1.0) + 0.5) * 128.0)
// x = values[j] = (seed + j*37) % 1009, phase = batch % 17,
// pass_total += value, checksum = (checksum + pass_total) % 1000000007 per pass.
// Usage: float_math VERSION SIZE ITERATIONS SEED [DATAFILE for versions >= 30]
// Prints "checksum elapsed_ns" like the benchmark binaries.
// Build with -ffp-contract=off so that only an explicit FMA ever fuses (mylang's
// FLOAT-DOMAIN-1: "separate arithmetic operations").
#include "common.h"
#include <immintrin.h>
#include <math.h>

/* ---- v1: today's semantics -------------------------------------------------
 * Checked i64 add into pass_total, bounds check against a header the compiler
 * cannot prove invariant, and int(float) as the out-of-line runtime call
 * myl_qbe_float_unary(ctx, 11, bits) that the B0 my-llvm binary makes (a `call`
 * per element; src/qbe_runtime.c:764). The op is a run-time argument. */
__attribute__((noinline)) static uint64_t float_unary(uint64_t op, uint64_t bits) {
    double a;
    memcpy(&a, &bits, 8);
    switch (op) {
    case 2: a = sqrt(a); memcpy(&bits, &a, 8); return bits;
    case 3: a = floor(a); memcpy(&bits, &a, 8); return bits;
    case 11:
        a = trunc(a);
        if (!isfinite(a) || a < -9223372036854775808.0 || a >= 9223372036854775808.0) trap("float conversion");
        return (uint64_t)(int64_t)a;
    default: trap("internal");
    }
}
static volatile uint64_t g_op11 = 11; /* keeps the op non-constant, as in the runtime image */

/* ---- v0: the fixture exactly as written: the `kind` dispatch stays inside the element
 * loop (a run-time switch; B0 my-llvm, Rust and Zig all keep it as a jump table) with the
 * other kinds' bodies present, and kind is read from memory each iteration like mylang's
 * stack slot. Everything else as v1. */
static volatile int64_t g_kind = 1;
__attribute__((noinline)) static int64_t v0(list_i64 *volatile slot, const uint8_t *flags, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        double p4 = (double)phase / 4.0;
        for (int64_t j = 0; j < size; j++) {
            list_i64 *values = slot;
            if ((uint64_t)j >= (uint64_t)values->len) trap("index");
            int64_t x = values->data[j], value = 0, t;
            switch (g_kind) {
            case 0:
                if (__builtin_add_overflow(x, phase, &t)) trap("overflow");
                if (__builtin_mul_overflow(t, 17, &t)) trap("overflow");
                if (__builtin_add_overflow(t, 23, &t)) trap("overflow");
                value = floormod(floordiv(t, 7), 1009);
                break;
            case 1: {
                double xf = (double)x;
                double a = xf / 8.0 + p4;
                double b = xf / 16.0 + 1.0;
                double v = (a * b + 0.5) * 128.0;
                uint64_t bits;
                memcpy(&bits, &v, 8);
                value = (int64_t)float_unary(g_op11, bits);
                break;
            }
            case 2: case 3:
                if (__builtin_add_overflow(x, phase, &t)) trap("overflow");
                if (flags[j]) { if (__builtin_mul_overflow(t, 3, &t) || __builtin_add_overflow(t, 1, &t)) trap("overflow"); }
                else { if (__builtin_mul_overflow(t, 5, &t) || __builtin_add_overflow(t, 7, &t)) trap("overflow"); }
                value = t;
                break;
            case 6:
                if (__builtin_add_overflow(x, phase, &t)) trap("overflow");
                if (__builtin_mul_overflow(t, 3, &t) || __builtin_add_overflow(t, 7, &t)) trap("overflow");
                value = t;
                break;
            default: trap("kind");
            }
            if (__builtin_add_overflow(pass_total, value, &pass_total)) trap("overflow");
        }
        checksum = floormod(checksum + pass_total, MOD);
    }
    return checksum;
}


__attribute__((noinline)) static int64_t v1(list_i64 *volatile slot, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        double p4 = (double)phase / 4.0;
        for (int64_t j = 0; j < size; j++) {
            list_i64 *values = slot;
            if ((uint64_t)j >= (uint64_t)values->len) trap("index");
            int64_t x = values->data[j];
            double xf = (double)x;
            double a = xf / 8.0 + p4;
            double b = xf / 16.0 + 1.0;
            double v = (a * b + 0.5) * 128.0;
            uint64_t bits;
            memcpy(&bits, &v, 8);
            int64_t value = (int64_t)float_unary(g_op11, bits);
            if (__builtin_add_overflow(pass_total, value, &pass_total)) trap("overflow");
        }
        checksum = floormod(checksum + pass_total, MOD);
    }
    return checksum;
}

/* ---- v2: + int(float) lowered inline (cvttsd2si + range test). Same semantics. */
static inline int64_t checked_f2i(double a) {
    if (!(a >= -9223372036854775808.0 && a < 9223372036854775808.0)) trap("float conversion");
    return (int64_t)a;
}
__attribute__((noinline)) static int64_t v2(list_i64 *volatile slot, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        double p4 = (double)phase / 4.0;
        for (int64_t j = 0; j < size; j++) {
            list_i64 *values = slot;
            if ((uint64_t)j >= (uint64_t)values->len) trap("index");
            double xf = (double)values->data[j];
            double a = xf / 8.0 + p4;
            double b = xf / 16.0 + 1.0;
            int64_t value = checked_f2i((a * b + 0.5) * 128.0);
            if (__builtin_add_overflow(pass_total, value, &pass_total)) trap("overflow");
        }
        checksum = floormod(checksum + pass_total, MOD);
    }
    return checksum;
}

/* ---- v3: + value semantics and L2: the list is immutable for the pass (header in
 * registers, one bounds check), and the overflow and conversion checks are sticky
 * flags tested after the inner loop. No range knowledge. */
__attribute__((noinline)) static int64_t v3(const list_i64 *values, int64_t size, int64_t iterations) {
    const int64_t *restrict data = values->data;
    if (size > values->len) trap("index");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        double p4 = (double)phase / 4.0;
        int bad = 0;
        for (int64_t j = 0; j < size; j++) {
            double xf = (double)data[j];
            double a = xf / 8.0 + p4;
            double b = xf / 16.0 + 1.0;
            double v = (a * b + 0.5) * 128.0;
            bad |= !(v >= -9223372036854775808.0 && v < 9223372036854775808.0);
            int64_t value = _mm_cvttsd_si64(_mm_set_sd(v)); /* garbage when bad; trapped after the loop */
            bad |= __builtin_add_overflow(pass_total, value, &pass_total);
        }
        if (bad) trap("overflow or float conversion");
        checksum = floormod(checksum + pass_total, MOD);
    }
    return checksum;
}

/* ---- v4: + element range facts x in [0,1009), phase in [0,17) (the same fact as
 * the pilot's v5): float(x) exact, the whole expression is in [0, 1.07e6], so the
 * conversion cannot trap and pass_total cannot overflow. The front end emits no
 * checks. Arithmetic stays f64 -> i64, i64 storage. */
__attribute__((noinline)) static int64_t v4(const list_i64 *values, int64_t size, int64_t iterations) {
    const int64_t *restrict data = values->data;
    if (size > values->len) trap("index");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        double p4 = (double)phase / 4.0;
        for (int64_t j = 0; j < size; j++) {
            int64_t x = data[j];
            __builtin_assume(x >= 0 && x < 1009);
            double xf = (double)x;
            double a = xf / 8.0 + p4;
            double b = xf / 16.0 + 1.0;
            pass_total += (int64_t)((a * b + 0.5) * 128.0);
        }
        checksum = floormod(checksum + pass_total, MOD);
    }
    return checksum;
}

/* ---- v13: v4 with BOTH the element range and the result range given to LLVM as
 * assumptions (x in [0,1009), result in [0, 2^21)), types left i64. Tests whether
 * LLVM narrows the conversions itself once it knows the ranges (WP-2/WP-6a question). */
__attribute__((noinline)) static int64_t v13(const list_i64 *values, int64_t size, int64_t iterations) {
    const int64_t *restrict data = values->data;
    if (size > values->len) trap("index");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17, pass_total = 0;
        double p4 = (double)phase / 4.0;
        for (int64_t j = 0; j < size; j++) {
            int64_t x = data[j];
            __builtin_assume(x >= 0 && x < 1009);
            double xf = (double)x;
            double a = xf / 8.0 + p4;
            double b = xf / 16.0 + 1.0;
            int64_t r = (int64_t)((a * b + 0.5) * 128.0);
            __builtin_assume(r >= 0 && r < (1 << 21));
            pass_total += r;
        }
        checksum = floormod(checksum + pass_total, MOD);
    }
    return checksum;
}

/* ---- v5: + narrow integer width at the conversions: x as i32 (so int->f64 is the
 * 4-wide vcvtdq2pd, not 64-bit vcvtsi2sd) and the result as i32 (vcvttpd2dq), summed
 * in a u64 accumulator. i64 storage still. Plain C; LLVM chooses the vector code. */
__attribute__((noinline)) static int64_t v5(const list_i64 *values, int64_t size, int64_t iterations) {
    const int64_t *restrict data = values->data;
    if (size > values->len) trap("index");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17;
        uint64_t pass_total = 0;
        double p4 = (double)phase / 4.0;
        for (int64_t j = 0; j < size; j++) {
            double xf = (double)(int32_t)data[j];
            double a = xf / 8.0 + p4;
            double b = xf / 16.0 + 1.0;
            pass_total += (uint32_t)(int32_t)((a * b + 0.5) * 128.0);
        }
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

/* ---- v6: v5 over u16 storage (list[int] with a proven range stored as u16). */
__attribute__((noinline)) static int64_t v6(const uint16_t *restrict data, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17;
        uint64_t pass_total = 0;
        double p4 = (double)phase / 4.0;
        for (int64_t j = 0; j < size; j++) {
            double xf = (double)(int32_t)data[j];
            double a = xf / 8.0 + p4;
            double b = xf / 16.0 + 1.0;
            pass_total += (uint32_t)(int32_t)((a * b + 0.5) * 128.0);
        }
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

#ifdef __AVX2__
/* ---- hand-written AVX2, f64 lanes, separate mul/add (no FMA): cvtdq2pd, 4 lanes. */
static inline __m128i pass4(__m256d xf, __m256d p4) {
    __m256d a = _mm256_add_pd(_mm256_mul_pd(xf, _mm256_set1_pd(0.125)), p4);
    __m256d b = _mm256_add_pd(_mm256_mul_pd(xf, _mm256_set1_pd(0.0625)), _mm256_set1_pd(1.0));
    __m256d v = _mm256_mul_pd(_mm256_add_pd(_mm256_mul_pd(a, b), _mm256_set1_pd(0.5)), _mm256_set1_pd(128.0));
    return _mm256_cvttpd_epi32(v);
}
static inline __m128i pass4_fma(__m256d xf, __m256d p4) {
    __m256d a = _mm256_fmadd_pd(xf, _mm256_set1_pd(0.125), p4);
    __m256d b = _mm256_fmadd_pd(xf, _mm256_set1_pd(0.0625), _mm256_set1_pd(1.0));
    __m256d v = _mm256_mul_pd(_mm256_fmadd_pd(a, b, _mm256_set1_pd(0.5)), _mm256_set1_pd(128.0));
    return _mm256_cvttpd_epi32(v);
}
/* Horizontal sum of eight u32 lanes into a u64 (widen first: the lanes' sum can pass 2^32). */
static inline uint64_t hsum_epi32(__m256i v) {
    __m256i w = _mm256_add_epi64(_mm256_cvtepu32_epi64(_mm256_castsi256_si128(v)),
                                 _mm256_cvtepu32_epi64(_mm256_extracti128_si256(v, 1)));
    __m128i a = _mm_add_epi64(_mm256_castsi256_si128(w), _mm256_extracti128_si256(w, 1));
    return (uint64_t)_mm_cvtsi128_si64(a) + (uint64_t)_mm_extract_epi64(a, 1);
}
static inline uint32_t scalar_value(uint32_t x, double p4) {
    double xf = (double)x;
    double a = xf / 8.0 + p4, b = xf / 16.0 + 1.0;
    return (uint32_t)(int32_t)((a * b + 0.5) * 128.0);
}

/* v7: hand AVX2, i64 storage: pack four i64 to four i32 lanes first (vpermd). */
__attribute__((noinline)) static int64_t v7(const list_i64 *values, int64_t size, int64_t iterations) {
    if (size > 32768) trap("size beyond the u32 lane accumulator bound");
    const int64_t *restrict data = values->data;
    if (size > values->len) trap("index");
    const __m256i sel = _mm256_setr_epi32(0, 2, 4, 6, 0, 2, 4, 6);
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17;
        double p4s = (double)phase / 4.0;
        __m256d p4 = _mm256_set1_pd(p4s);
        __m256i acc = _mm256_setzero_si256();
        int64_t j = 0;
        for (; j + 8 <= size; j += 8) {
            __m256i lo = _mm256_permutevar8x32_epi32(_mm256_loadu_si256((const __m256i *)(data + j)), sel);
            __m256i hi = _mm256_permutevar8x32_epi32(_mm256_loadu_si256((const __m256i *)(data + j + 4)), sel);
            __m128i r0 = pass4(_mm256_cvtepi32_pd(_mm256_castsi256_si128(lo)), p4);
            __m128i r1 = pass4(_mm256_cvtepi32_pd(_mm256_castsi256_si128(hi)), p4);
            acc = _mm256_add_epi32(acc, _mm256_set_m128i(r1, r0));
        }
        uint64_t pass_total = hsum_epi32(acc);
        for (; j < size; j++) pass_total += scalar_value((uint32_t)data[j], p4s);
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

/* v8: hand AVX2, u16 storage (vpmovzxwd then vcvtdq2pd). */
__attribute__((noinline)) static int64_t v8(const uint16_t *restrict data, int64_t size, int64_t iterations) {
    if (size > 32768) trap("size beyond the u32 lane accumulator bound");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17;
        double p4s = (double)phase / 4.0;
        __m256d p4 = _mm256_set1_pd(p4s);
        __m256i acc = _mm256_setzero_si256();
        int64_t j = 0;
        for (; j + 8 <= size; j += 8) {
            __m256i w = _mm256_cvtepu16_epi32(_mm_loadu_si128((const __m128i *)(data + j)));
            __m128i r0 = pass4(_mm256_cvtepi32_pd(_mm256_castsi256_si128(w)), p4);
            __m128i r1 = pass4(_mm256_cvtepi32_pd(_mm256_extracti128_si256(w, 1)), p4);
            acc = _mm256_add_epi32(acc, _mm256_set_m128i(r1, r0));
        }
        uint64_t pass_total = hsum_epi32(acc);
        for (; j < size; j++) pass_total += scalar_value(data[j], p4s);
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

/* v9: v8 + FMA contraction (a language rule: the result is exact here, but the
 * compiler may only fuse if "separate operations" is relaxed). */
__attribute__((noinline)) static int64_t v9(const uint16_t *restrict data, int64_t size, int64_t iterations) {
    if (size > 32768) trap("size beyond the u32 lane accumulator bound");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17;
        double p4s = (double)phase / 4.0;
        __m256d p4 = _mm256_set1_pd(p4s);
        __m256i acc = _mm256_setzero_si256();
        int64_t j = 0;
        for (; j + 8 <= size; j += 8) {
            __m256i w = _mm256_cvtepu16_epi32(_mm_loadu_si128((const __m128i *)(data + j)));
            __m128i r0 = pass4_fma(_mm256_cvtepi32_pd(_mm256_castsi256_si128(w)), p4);
            __m128i r1 = pass4_fma(_mm256_cvtepi32_pd(_mm256_extracti128_si256(w, 1)), p4);
            acc = _mm256_add_epi32(acc, _mm256_set_m128i(r1, r0));
        }
        uint64_t pass_total = hsum_epi32(acc);
        for (; j < size; j++) pass_total += scalar_value(data[j], p4s);
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

/* v10: v9 narrowed again to f32 lanes (8 per vector). Every intermediate is a dyadic
 * rational with <= 24 significant bits (x < 2^10, 3-4 fraction bits, product < 2^13
 * with 7 fraction bits), so the f32 result is bit-identical. The contract says f64:
 * this is a precision-narrowing counterfactual, not a contract-preserving step. */
__attribute__((noinline)) static int64_t v10(const uint16_t *restrict data, int64_t size, int64_t iterations) {
    if (size > 32768) trap("size beyond the u32 lane accumulator bound");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17;
        float p4s = (float)phase / 4.0f;
        __m256 p4 = _mm256_set1_ps(p4s);
        __m256i acc = _mm256_setzero_si256();
        int64_t j = 0;
        for (; j + 8 <= size; j += 8) {
            __m256 xf = _mm256_cvtepi32_ps(_mm256_cvtepu16_epi32(_mm_loadu_si128((const __m128i *)(data + j))));
            __m256 a = _mm256_fmadd_ps(xf, _mm256_set1_ps(0.125f), p4);
            __m256 b = _mm256_fmadd_ps(xf, _mm256_set1_ps(0.0625f), _mm256_set1_ps(1.0f));
            __m256 v = _mm256_mul_ps(_mm256_fmadd_ps(a, b, _mm256_set1_ps(0.5f)), _mm256_set1_ps(128.0f));
            acc = _mm256_add_epi32(acc, _mm256_cvttps_epi32(v));
        }
        uint64_t pass_total = hsum_epi32(acc);
        for (; j < size; j++) pass_total += scalar_value(data[j], (double)p4s);
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

/* v11: WORK ELIMINATION (excluded from conclusions). All operands are dyadic, so
 * value = (x + 2*phase) * (x + 16) + 64 exactly; the float computation becomes
 * 32-bit integer arithmetic. Proving it needs exact-float algebra that no compiler does. */
__attribute__((noinline)) static int64_t v11(const uint16_t *restrict data, int64_t size, int64_t iterations) {
    if (size > 32768) trap("size beyond the u32 lane accumulator bound");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17;
        __m256i p2 = _mm256_set1_epi32((int)(2 * phase)), c16 = _mm256_set1_epi32(16), c64 = _mm256_set1_epi32(64);
        __m256i acc = _mm256_setzero_si256();
        int64_t j = 0;
        for (; j + 8 <= size; j += 8) {
            __m256i x = _mm256_cvtepu16_epi32(_mm_loadu_si128((const __m128i *)(data + j)));
            __m256i v = _mm256_add_epi32(_mm256_mullo_epi32(_mm256_add_epi32(x, p2), _mm256_add_epi32(x, c16)), c64);
            acc = _mm256_add_epi32(acc, v);
        }
        uint64_t pass_total = hsum_epi32(acc);
        for (; j < size; j++) pass_total += (uint32_t)(data[j] + 2 * phase) * (uint32_t)(data[j] + 16) + 64;
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

/* v12: WORK ELIMINATION (excluded): with x summed once (S1 = sum x, S2 = sum x^2) the
 * whole pass is closed-form: sum (x+2p)(x+16)+64 = S2 + (16+2p) S1 + (32p + 64) n. */
__attribute__((noinline)) static int64_t v12(const uint16_t *restrict data, int64_t size, int64_t iterations) {
    uint64_t s1 = 0, s2 = 0;
    for (int64_t j = 0; j < size; j++) { s1 += data[j]; s2 += (uint64_t)data[j] * data[j]; }
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        uint64_t p = (uint64_t)(batch % 17);
        uint64_t pass_total = s2 + (16 + 2 * p) * s1 + (32 * p + 64) * (uint64_t)size;
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

#endif /* __AVX2__ */

/* ================= holdout: the data arrives from a file, no range facts ============ */

/* v30: the legitimate floor with NO range facts: immutable list, one bounds check,
 * sticky overflow and conversion flags (L2). Plain C, i64 data from the file. This is
 * v3 reading external data (kept as a distinct entry so the holdout set is explicit). */

#ifdef __AVX2__
/* v31: AVX2 with a runtime guard instead of a fixture fact. A single pre-pass over the
 * (immutable) list proves lo >= 0 and hi < 2^31 -- once, outside the iteration loop;
 * the guarded fast path is v7 (hand AVX2, i64 storage, i32 lanes). When the guard
 * fails, it falls back to v3. The fast path additionally needs the value bound:
 * with x < 2^31 the f64 value can be as large as ~2^31*2^31/128*128 = 2^62; so the
 * guard is x < 2^20 (value < 2^40: no conversion trap, i32 accumulate impossible)
 * -> the conversion is done to i64 lanes by splitting (cvttpd2dq is only i32). We use
 * the conservative guard hi < 5000, which keeps value < 2^31 (see range check below). */
static int guard_ok(const int64_t *data, int64_t size, int64_t *hi_out) {
    int64_t lo = 0, hi = 0;
    for (int64_t j = 0; j < size; j++) { if (data[j] < lo) lo = data[j]; if (data[j] > hi) hi = data[j]; }
    *hi_out = hi;
    /* value <= (hi + 32)*(hi + 16) + 64 must stay below 2^31 and every f64 step is exact */
    return lo >= 0 && hi <= 40000;
}
__attribute__((noinline)) static int64_t v31(const list_i64 *values, int64_t size, int64_t iterations) {
    const int64_t *restrict data = values->data;
    if (size > values->len) trap("index");
    int64_t hi;
    if (!guard_ok(data, size, &hi)) return v3(values, size, iterations);
    /* guarded fast path = v7 with the 32-bit lane accumulators flushed before they can wrap */
    uint64_t maxv = (uint64_t)(hi + 32) * (uint64_t)(hi + 16) + 64;
    int64_t chunk = (int64_t)(0xFFFFFFFFull / maxv);
    const __m256i sel = _mm256_setr_epi32(0, 2, 4, 6, 0, 2, 4, 6);
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t phase = batch % 17;
        double p4s = (double)phase / 4.0;
        __m256d p4 = _mm256_set1_pd(p4s);
        uint64_t pass_total = 0;
        int64_t j = 0;
        while (j + 8 <= size) {
            int64_t n = (size - j) / 8;
            if (n > chunk) n = chunk;
            __m256i acc = _mm256_setzero_si256();
            for (int64_t k = 0; k < n; k++, j += 8) {
                __m256i lo = _mm256_permutevar8x32_epi32(_mm256_loadu_si256((const __m256i *)(data + j)), sel);
                __m256i hv = _mm256_permutevar8x32_epi32(_mm256_loadu_si256((const __m256i *)(data + j + 4)), sel);
                __m128i r0 = pass4(_mm256_cvtepi32_pd(_mm256_castsi256_si128(lo)), p4);
                __m128i r1 = pass4(_mm256_cvtepi32_pd(_mm256_castsi256_si128(hv)), p4);
                acc = _mm256_add_epi32(acc, _mm256_set_m128i(r1, r0));
            }
            pass_total += hsum_epi32(acc);
        }
        for (; j < size; j++) pass_total += scalar_value((uint32_t)data[j], p4s);
        checksum = floormod(checksum + (int64_t)pass_total, MOD);
    }
    return checksum;
}

#endif /* __AVX2__ */

/* ============================================ main ================================== */
static int64_t *read_file(const char *path, int64_t size) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror("fopen"); exit(2); }
    int64_t *d = malloc(sizeof(int64_t) * size);
    if (fread(d, sizeof(int64_t), size, f) != (size_t)size) { fprintf(stderr, "short data file\n"); exit(2); }
    fclose(f);
    return d;
}

int main(int argc, char **argv) {
    if (argc == 5 && !strcmp(argv[1], "gen")) { /* gen SIZE SEED PATH: the benchmark's values */
        int64_t size = atoll(argv[2]), seed = atoll(argv[3]);
        FILE *f = fopen(argv[4], "wb");
        for (int64_t j = 0; j < size; j++) { int64_t v = (seed + j * 37) % 1009; fwrite(&v, 8, 1, f); }
        fclose(f);
        return 0;
    }
    if (argc == 6 && !strcmp(argv[1], "genwide")) { /* genwide SIZE SEED MAX PATH: other data, arbitrary range */
        int64_t size = atoll(argv[2]), seed = atoll(argv[3]), max = atoll(argv[4]);
        FILE *f = fopen(argv[5], "wb");
        uint64_t s = (uint64_t)seed * 6364136223846793005ULL + 1442695040888963407ULL;
        for (int64_t j = 0; j < size; j++) {
            s = s * 6364136223846793005ULL + 1442695040888963407ULL;
            int64_t v = (int64_t)((s >> 33) % (uint64_t)(max + 1));
            fwrite(&v, 8, 1, f);
        }
        fclose(f);
        return 0;
    }
    if (argc < 5) return 2;
    int which = atoi(argv[1]);
    int64_t size = atoll(argv[2]), iterations = atoll(argv[3]), seed = atoll(argv[4]);
    int64_t *data;
    if (argc == 6) {
        data = read_file(argv[5], size);
    } else if (which >= 30) {
        return 2;
    } else {
        data = malloc(sizeof(int64_t) * size);
        for (int64_t j = 0; j < size; j++) data[j] = (seed + j * 37) % 1009;
    }
    uint16_t *narrow = malloc(sizeof(uint16_t) * size);
    for (int64_t j = 0; j < size; j++) narrow[j] = (uint16_t)data[j];
    uint8_t *flags = calloc(size, 1);
    list_i64 values = {size, data};
    list_i64 *volatile slot = &values;
    int64_t start = now_ns(), checksum = 0;
    switch (which) {
    case 0: checksum = v0(slot, flags, size, iterations); break;
    case 1: checksum = v1(slot, size, iterations); break;
    case 2: checksum = v2(slot, size, iterations); break;
    case 3: case 30: checksum = v3(&values, size, iterations); break;
    case 4: checksum = v4(&values, size, iterations); break;
    case 5: checksum = v5(&values, size, iterations); break;
    case 13: checksum = v13(&values, size, iterations); break;
    case 6: checksum = v6(narrow, size, iterations); break;
#ifdef __AVX2__
    case 7: checksum = v7(&values, size, iterations); break;
    case 8: checksum = v8(narrow, size, iterations); break;
    case 9: checksum = v9(narrow, size, iterations); break;
    case 10: checksum = v10(narrow, size, iterations); break;
    case 11: checksum = v11(narrow, size, iterations); break;
    case 12: checksum = v12(narrow, size, iterations); break;
    case 31: checksum = v31(&values, size, iterations); break;
#endif
    default: return 2;
    }
    printf("%lld %lld\n", (long long)checksum, (long long)(now_ns() - start));
    return 0;
}
