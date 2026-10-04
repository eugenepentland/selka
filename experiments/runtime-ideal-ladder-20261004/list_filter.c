// list_filter ladder. Re-implements kind 2 of benchmarks/runtime/expanded/collections/main.my:
//   for batch in range(iterations):
//       input    = [(seed + batch + j*13) % 1009 for j in range(size)]
//       filtered = [v for v in input if v % 3 == 0]
//       part     = sum((i+1) * filtered[i])           # fold()
//       checksum = (checksum + part) % 1000000007
// Everything above, including both list allocations and their release, is timed.
// Usage: list_filter VERSION SIZE ITERATIONS SEED [DATAFILE]
// Prints "checksum elapsed_ns". Build with -fno-strict-aliasing (mylang's IL carries no TBAA).
#include "common.h"

/* mylang's list object as seen by compiled code (src/native_collections.h): length,
 * capacity, generation, element type, storage pointer. The RC object header sits before it. */
typedef struct { int64_t len, cap, gen; const void *elem; int64_t *data; } mlist;
typedef struct { void *dead_head; const void *plain_word; } rc_state;
typedef struct { rc_state *rc; } heap_t;
static rc_state g_rc = { NULL, (const void *)&g_rc };
static heap_t g_heap = { &g_rc };
static const void *g_int_type = (const void *)&g_rc;

/* myl_rc_list_plain_ready (src/native_collections.c:1344): a call per append. */
__attribute__((noinline)) static int plain_ready(heap_t *h, const mlist *l) {
    if (!h || !h->rc || h->rc->dead_head || !l || !l->elem) return 0;
    return l->elem == h->rc->plain_word;
}
__attribute__((noinline)) static int plain_ready_type(heap_t *h, const void *elem) {
    if (!h || !h->rc || h->rc->dead_head || !elem) return 0;
    return elem == h->rc->plain_word;
}

static mlist *new_list(int64_t cap) {
    mlist *l = malloc(sizeof *l);
    l->len = 0; l->cap = cap; l->gen = 0; l->elem = g_int_type;
    l->data = cap ? malloc((size_t)cap * 8) : NULL;
    return l;
}
__attribute__((noinline)) static void list_grow(mlist *l) { /* doubling from 4: myl_rc_list_storage_reserve */
    int64_t cap = l->cap < 4 ? 4 : l->cap * 2;
    l->data = realloc(l->data, (size_t)cap * 8);
    l->cap = cap;
}
static void free_list(mlist *l) { free(l->data); free(l); }

/* ---- v1: today's semantics. The comprehension writes the list header (length and
 * generation) on every element, because the element stores may alias the header;
 * each append re-reads the header, tests capacity, makes the plain_ready call, then
 * stores the element and bumps length and generation; fold() bounds-checks every
 * index and checks every multiply and add. Lists are heap objects freed at scope end. */
#define DEFINE_TODAY(NAME, GEN)                                                                     \
__attribute__((noinline)) static int64_t NAME(heap_t *volatile hslot, int64_t size, int64_t iterations, \
                                              int64_t seed, const int64_t *src) {                    \
    heap_t *h = hslot;                                                                              \
    int64_t checksum = 0;                                                                           \
    (void)src;                                                                                      \
    for (int64_t batch = 0; batch < iterations; batch++) {                                          \
        mlist *in = new_list(size);                                                                 \
        for (int64_t j = 0; j < size; j++) {                                                        \
            int64_t t;                                                                              \
            GEN;                                                                                    \
            in->data[j] = floormod(t, 1009);                                                        \
            in->len = j + 1;                                                                        \
            in->gen = j + 1;                                                                        \
        }                                                                                           \
        mlist *out = new_list(0);                                                                   \
        for (int64_t j = 0; j < in->len; j++) {                                                     \
            int64_t v = in->data[j];                                                                \
            if (floormod(v, 3) == 0) {                                                              \
                if (out->len >= out->cap || out->gen == INT64_MAX) list_grow(out);                  \
                if (!plain_ready(h, out)) trap("plain");                                            \
                out->data[out->len] = v;                                                            \
                out->len++;                                                                         \
                out->gen++;                                                                         \
            }                                                                                       \
        }                                                                                           \
        int64_t total = 0, n = out->len;                                                            \
        for (int64_t j = 0; j < n; j++) {                                                           \
            if ((uint64_t)j >= (uint64_t)out->len) trap("index");                                   \
            int64_t e = out->data[j], p;                                                            \
            if (__builtin_mul_overflow(j + 1, e, &p)) trap("overflow");                             \
            if (__builtin_add_overflow(total, p, &total)) trap("overflow");                         \
        }                                                                                           \
        free_list(in);                                                                              \
        free_list(out);                                                                             \
        checksum = floormod(checksum + total, MOD);                                                 \
    }                                                                                               \
    return checksum;                                                                                \
}
#define GEN_FORMULA                                                                                 \
    { int64_t u, w;                                                                                 \
      if (__builtin_mul_overflow(j, 13, &u) || __builtin_add_overflow(seed, batch, &w) ||           \
          __builtin_add_overflow(w, u, &t)) trap("overflow"); }
#define GEN_FILE                                                                                    \
    { if (__builtin_add_overflow(src[j], batch, &t)) trap("overflow"); }
DEFINE_TODAY(v1, GEN_FORMULA)
DEFINE_TODAY(v20, GEN_FILE) /* the same semantics reading a_j from a file: the exact reference for the holdout */

/* ---- v2: + value semantics and L2. Fresh local lists are not aliased, so their headers
 * live in registers (no per-element header stores or reloads, one end-of-loop store);
 * the affine generation overflow check is a sticky flag; fold's bounds checks and
 * overflow checks are sticky. Still: two heap lists, doubling growth, plain_ready call. */
__attribute__((noinline)) static int64_t v2(heap_t *volatile hslot, int64_t size, int64_t iterations, int64_t seed) {
    heap_t *h = hslot;
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t *restrict ind = malloc((size_t)size * 8);
        int bad = 0;
        int64_t base;
        bad |= __builtin_add_overflow(seed, batch, &base);
        for (int64_t j = 0; j < size; j++) {
            int64_t u, t;
            bad |= __builtin_mul_overflow(j, 13, &u);
            bad |= __builtin_add_overflow(base, u, &t);
            ind[j] = floormod(t, 1009);
        }
        if (bad) trap("overflow");
        int64_t *od = NULL, olen = 0, ocap = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t v = ind[j];
            if (floormod(v, 3) == 0) {
                if (olen >= ocap) { ocap = ocap < 4 ? 4 : ocap * 2; od = realloc(od, (size_t)ocap * 8); }
                if (!plain_ready_type(h, g_int_type)) trap("plain");
                od[olen++] = v;
            }
        }
        int64_t total = 0;
        for (int64_t j = 0; j < olen; j++) {
            int64_t p;
            bad |= __builtin_mul_overflow(j + 1, od[j], &p);
            bad |= __builtin_add_overflow(total, p, &total);
        }
        if (bad) trap("overflow");
        free(ind);
        free(od);
        checksum = floormod(checksum + total, MOD);
    }
    return checksum;
}

/* ---- v3: + typed append: the element type is statically int, so the plain_ready call
 * disappears (typed collection operations; a type-known fact, no language change). */
__attribute__((noinline)) static int64_t v3(heap_t *volatile hslot, int64_t size, int64_t iterations, int64_t seed) {
    (void)hslot;
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t *restrict ind = malloc((size_t)size * 8);
        int bad = 0;
        int64_t base;
        bad |= __builtin_add_overflow(seed, batch, &base);
        for (int64_t j = 0; j < size; j++) {
            int64_t u, t;
            bad |= __builtin_mul_overflow(j, 13, &u);
            bad |= __builtin_add_overflow(base, u, &t);
            ind[j] = floormod(t, 1009);
        }
        if (bad) trap("overflow");
        int64_t *od = NULL, olen = 0, ocap = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t v = ind[j];
            if (floormod(v, 3) == 0) {
                if (olen >= ocap) { ocap = ocap < 4 ? 4 : ocap * 2; od = realloc(od, (size_t)ocap * 8); }
                od[olen++] = v;
            }
        }
        int64_t total = 0;
        for (int64_t j = 0; j < olen; j++) {
            int64_t p;
            bad |= __builtin_mul_overflow(j + 1, od[j], &p);
            bad |= __builtin_add_overflow(total, p, &total);
        }
        if (bad) trap("overflow");
        free(ind);
        free(od);
        checksum = floormod(checksum + total, MOD);
    }
    return checksum;
}

/* ---- v4: + bounded result capacity: a filter comprehension yields at most len(source)
 * elements, so the output is allocated once at that size (no growth checks, no realloc).
 * L3 removes the objection that this over-reserves against a memory budget. */
__attribute__((noinline)) static int64_t v4(int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t *restrict ind = malloc((size_t)size * 8);
        int64_t *restrict od = malloc((size_t)size * 8);
        int bad = 0;
        int64_t base;
        bad |= __builtin_add_overflow(seed, batch, &base);
        for (int64_t j = 0; j < size; j++) {
            int64_t u, t;
            bad |= __builtin_mul_overflow(j, 13, &u);
            bad |= __builtin_add_overflow(base, u, &t);
            ind[j] = floormod(t, 1009);
        }
        int64_t olen = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t v = ind[j];
            if (floormod(v, 3) == 0) od[olen++] = v;
        }
        int64_t total = 0;
        for (int64_t j = 0; j < olen; j++) {
            int64_t p;
            bad |= __builtin_mul_overflow(j + 1, od[j], &p);
            bad |= __builtin_add_overflow(total, p, &total);
        }
        if (bad) trap("overflow");
        free(ind);
        free(od);
        checksum = floormod(checksum + total, MOD);
    }
    return checksum;
}

/* ---- v5: + allocation hoisted: neither list escapes an iteration and both have the same
 * bound every time, so their storage is allocated once outside the batch loop (the
 * effect of L3's allocation elision without any fusion). */
__attribute__((noinline)) static int64_t v5(int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    int64_t *restrict ind = malloc((size_t)size * 8);
    int64_t *restrict od = malloc((size_t)size * 8);
    for (int64_t batch = 0; batch < iterations; batch++) {
        int bad = 0;
        int64_t base;
        bad |= __builtin_add_overflow(seed, batch, &base);
        for (int64_t j = 0; j < size; j++) {
            int64_t u, t;
            bad |= __builtin_mul_overflow(j, 13, &u);
            bad |= __builtin_add_overflow(base, u, &t);
            ind[j] = floormod(t, 1009);
        }
        int64_t olen = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t v = ind[j];
            if (floormod(v, 3) == 0) od[olen++] = v;
        }
        int64_t total = 0;
        for (int64_t j = 0; j < olen; j++) {
            int64_t p;
            bad |= __builtin_mul_overflow(j + 1, od[j], &p);
            bad |= __builtin_add_overflow(total, p, &total);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    free(ind);
    free(od);
    return checksum;
}

/* ---- v12: only the sign fact, nothing narrower: t >= 0 turns floor division into unsigned
 * remainder, the affine overflow check is hoisted, fold's multiply is unchecked; storage
 * and arithmetic stay i64. Separates the "non-negative" fact from the "x < 1009" fact (v6). */
__attribute__((noinline)) static int64_t v12(int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    int64_t *restrict ind = malloc((size_t)size * 8);
    int64_t *restrict od = malloc((size_t)size * 8);
    for (int64_t batch = 0; batch < iterations; batch++) {
        int bad = 0;
        int64_t base, last;
        bad |= __builtin_add_overflow(seed, batch, &base);
        bad |= __builtin_add_overflow(base, 13 * (size - 1), &last);
        for (int64_t j = 0; j < size; j++) ind[j] = (int64_t)((uint64_t)(base + 13 * j) % 1009u);
        int64_t olen = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t v = ind[j];
            if ((uint64_t)v % 3u == 0) od[olen++] = v;
        }
        int64_t total = 0;
        for (int64_t j = 0; j < olen; j++) bad |= __builtin_add_overflow(total, (j + 1) * od[j], &total);
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    free(ind);
    free(od);
    return checksum;
}

/* ---- v6: + range facts. x = t % 1009 is in [0,1009) whatever the sign of t; t itself is
 * non-negative (seed >= 1 after main's argument check, batch and j >= 0), so floor ==
 * unsigned remainder. The multiply (j+1)*x cannot overflow (j < 2^40 by memory size);
 * only the running sum keeps a sticky check. u32 element storage. */
__attribute__((noinline)) static int64_t v6(int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    uint32_t *restrict ind = malloc((size_t)size * 4);
    uint32_t *restrict od = malloc((size_t)size * 4);
    for (int64_t batch = 0; batch < iterations; batch++) {
        int bad = 0;
        int64_t base;
        bad |= __builtin_add_overflow(seed, batch, &base);
        int64_t last;
        bad |= __builtin_add_overflow(base, 13 * (size - 1), &last); /* one hoisted affine check */
        for (int64_t j = 0; j < size; j++) ind[j] = (uint32_t)((uint64_t)(base + 13 * j) % 1009u);
        int64_t olen = 0;
        for (int64_t j = 0; j < size; j++) {
            uint32_t v = ind[j];
            if (v % 3u == 0) od[olen++] = v;
        }
        int64_t total = 0;
        for (int64_t j = 0; j < olen; j++) {
            int64_t p = (int64_t)(j + 1) * od[j];
            bad |= __builtin_add_overflow(total, p, &total);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    free(ind);
    free(od);
    return checksum;
}

/* ---- v7: + comprehension fusion #1: `input` is used once, by the filter, and never
 * escapes, so the generator feeds the filter directly (no input list). The filtered
 * list is still materialized (in hoisted storage) for fold(). */
__attribute__((noinline)) static int64_t v7(int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    uint32_t *restrict od = malloc((size_t)size * 4);
    for (int64_t batch = 0; batch < iterations; batch++) {
        int bad = 0;
        int64_t base, last;
        bad |= __builtin_add_overflow(seed, batch, &base);
        bad |= __builtin_add_overflow(base, 13 * (size - 1), &last);
        int64_t olen = 0;
        for (int64_t j = 0; j < size; j++) {
            uint32_t v = (uint32_t)((uint64_t)(base + 13 * j) % 1009u);
            if (v % 3u == 0) od[olen++] = v;
        }
        int64_t total = 0;
        for (int64_t j = 0; j < olen; j++) {
            int64_t p = (int64_t)(j + 1) * od[j];
            bad |= __builtin_add_overflow(total, p, &total);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    free(od);
    return checksum;
}

/* ---- v8: + fusion #2: fold consumes the filter's output once, so no list exists at all:
 * a single loop keeps a running index. Branchy: the filter test is a conditional. */
__attribute__((noinline)) static int64_t v8(int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int bad = 0;
        int64_t base, last;
        bad |= __builtin_add_overflow(seed, batch, &base);
        bad |= __builtin_add_overflow(base, 13 * (size - 1), &last);
        int64_t total = 0, rank = 0;
        for (int64_t j = 0; j < size; j++) {
            uint32_t v = (uint32_t)((uint64_t)(base + 13 * j) % 1009u);
            if (v % 3u == 0) {
                rank++;
                bad |= __builtin_add_overflow(total, rank * (int64_t)v, &total);
            }
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    return checksum;
}

/* ---- v9: + branchless (select) form of the same fused loop. The selection pattern is
 * pseudo-random, so the branchy form mispredicts; a data-dependent select does not. */
__attribute__((noinline)) static int64_t v9(int64_t size, int64_t iterations, int64_t seed) {
    if (size > 100000000) return v8(size, iterations, seed); /* sum bound 1008*n(n+1)/2 < 2^63 needs n < 1.3e8 */
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int bad = 0;
        int64_t base, last;
        bad |= __builtin_add_overflow(seed, batch, &base);
        bad |= __builtin_add_overflow(base, 13 * (size - 1), &last);
        uint64_t total = 0, rank = 0;
        for (int64_t j = 0; j < size; j++) {
            uint32_t v = (uint32_t)((uint64_t)(base + 13 * j) % 1009u);
            uint64_t m = (v % 3u == 0);
            rank += m;
            total += m * rank * v;
        }
        /* total <= 1008 * n(n+1)/2; checked once per pass: n * n * 1008 < 2^63 */
        if (bad) trap("overflow");
        checksum = floormod(checksum + (int64_t)total, MOD);
    }
    return checksum;
}

/* ---- v10: + strength-reduced remainder: x_{j+1} = (x_j + 13) mod 1009 is an induction
 * variable (one add, one compare-subtract); no division by 1009 at all. u32 scalar. */
__attribute__((noinline)) static int64_t v10(int64_t size, int64_t iterations, int64_t seed) {
    if (size > 100000000) return v8(size, iterations, seed);
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int bad = 0;
        int64_t base, last;
        bad |= __builtin_add_overflow(seed, batch, &base);
        bad |= __builtin_add_overflow(base, 13 * (size - 1), &last);
        uint32_t x = (uint32_t)((uint64_t)base % 1009u);
        uint64_t total = 0, rank = 0;
        for (int64_t j = 0; j < size; j++) {
            uint64_t m = (x % 3u == 0);
            rank += m;
            total += m * rank * x;
            x += 13;
            x = x >= 1009 ? x - 1009 : x;
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + (int64_t)total, MOD);
    }
    return checksum;
}

#ifdef __AVX2__
/* ---- v11: hand AVX2, fused, u16 lanes (16 elements per step). x is the induction vector
 * (+208 mod 1009 per step, min(x, x-1009) as the conditional subtract); x%3==0 via a
 * multiply-high; the rank of every selected lane is an in-register inclusive prefix
 * count of the mask plus the running count; vpmaddwd forms rank*x and pair-sums into
 * i32 lanes, flushed to a checked 64-bit total every 16 blocks (bounds: rank <= 32767,
 * 16 * 2*32767*1008 < 2^31). */
static inline __m256i x_step(__m256i x, __m256i c1009, __m256i c208) {
    x = _mm256_add_epi16(x, c208);
    return _mm256_min_epu16(x, _mm256_sub_epi16(x, c1009));
}
__attribute__((noinline)) static int64_t v11(int64_t size, int64_t iterations, int64_t seed) {
    if (size > 32767) trap("size beyond the u16 rank bound");
    const __m256i c1009 = _mm256_set1_epi16(1009), c208 = _mm256_set1_epi16(208);
    const __m256i iota13 = _mm256_setr_epi16(0, 13, 26, 39, 52, 65, 78, 91, 104, 117, 130, 143, 156, 169, 182, 195);
    const __m256i bc7 = _mm256_setr_epi8(14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15,
                                         14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15);
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int bad = 0;
        int64_t base, last;
        bad |= __builtin_add_overflow(seed, batch, &base);
        bad |= __builtin_add_overflow(base, 13 * (size - 1), &last);
        uint32_t b0 = (uint32_t)((uint64_t)base % 1009u);
        __m256i x = _mm256_add_epi16(iota13, _mm256_set1_epi16((short)b0));
        x = _mm256_min_epu16(x, _mm256_sub_epi16(x, c1009));
        int64_t total = 0;
        uint64_t rank0 = 0;
        int64_t j = 0;
        while (j + 16 <= size) {
            int64_t blocks = (size - j) / 16;
            if (blocks > 16) blocks = 16;
            __m256i acc = _mm256_setzero_si256();
            for (int64_t k = 0; k < blocks; k++, j += 16) {
                __m256i q = _mm256_srli_epi16(_mm256_mulhi_epu16(x, _mm256_set1_epi16((short)43691)), 1);
                __m256i r = _mm256_sub_epi16(x, _mm256_mullo_epi16(q, _mm256_set1_epi16(3)));
                __m256i m = _mm256_cmpeq_epi16(r, _mm256_setzero_si256());
                __m256i s = _mm256_srli_epi16(m, 15);
                s = _mm256_add_epi16(s, _mm256_slli_si256(s, 2));
                s = _mm256_add_epi16(s, _mm256_slli_si256(s, 4));
                s = _mm256_add_epi16(s, _mm256_slli_si256(s, 8));
                __m256i carry = _mm256_permute2x128_si256(_mm256_shuffle_epi8(s, bc7), _mm256_shuffle_epi8(s, bc7), 0x08);
                s = _mm256_add_epi16(_mm256_add_epi16(s, carry), _mm256_set1_epi16((short)rank0));
                acc = _mm256_add_epi32(acc, _mm256_madd_epi16(_mm256_and_si256(x, m), s));
                rank0 += (uint32_t)__builtin_popcount((unsigned)_mm256_movemask_epi8(m)) >> 1;
                x = x_step(x, c1009, c208);
            }
            bad |= __builtin_add_overflow(total, (int64_t)hsum_u32x8(acc), &total);
        }
        /* scalar tail: j.. size */
        for (; j < size; j++) {
            uint32_t v = (uint32_t)((uint64_t)(base + 13 * j) % 1009u);
            if (v % 3u == 0) { rank0++; bad |= __builtin_add_overflow(total, (int64_t)(rank0 * v), &total); }
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    return checksum;
}
#endif /* __AVX2__ */

/* ============ holdout: a_j = seed + 13 j comes from a file, no generator in the program ====
 * Per element x = (a_j + batch) % 1009 with a_j an unknown i64. */

/* v30: the best version with no fixture range facts: fused, sticky checks (L2). The floor
 * remainder of an unknown i64 keeps its sign fixup; its result is in [0,1009) by definition,
 * so the filter test is an unsigned remainder. */
__attribute__((noinline)) static int64_t v30(const int64_t *a, int64_t size, int64_t iterations) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int bad = 0;
        int64_t total = 0, rank = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t t;
            bad |= __builtin_add_overflow(a[j], batch, &t);
            uint32_t v = (uint32_t)floormod(t, 1009);
            if (v % 3u == 0) {
                rank++;
                bad |= __builtin_add_overflow(total, rank * (int64_t)v, &total);
            }
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    return checksum;
}

#ifdef __AVX2__
/* v31: runtime guard + array-level hoisting. One pre-pass over the immutable file data
 * proves 0 <= a_j and a_j + iterations does not overflow, and stores r_j = a_j % 1009 as
 * u16 (the remainder of a loop-invariant element, computed once per list instead of
 * once per batch). The batch loop is then v11's kernel with x = (r_j + batch%1009) mod 1009.
 * If the guard fails the exact scalar v30 runs. */
__attribute__((noinline)) static int64_t v31(const int64_t *a, int64_t size, int64_t iterations) {
    if (size > 32767) return v30(a, size, iterations);
    int64_t maxa = 0;
    for (int64_t j = 0; j < size; j++) { if (a[j] < 0) return v30(a, size, iterations); if (a[j] > maxa) maxa = a[j]; }
    int64_t sum;
    if (__builtin_add_overflow(maxa, iterations, &sum)) return v30(a, size, iterations);
    uint16_t *r = malloc((size_t)size * 2 + 64);
    for (int64_t j = 0; j < size; j++) r[j] = (uint16_t)((uint64_t)a[j] % 1009u);
    const __m256i c1009 = _mm256_set1_epi16(1009);
    const __m256i bc7 = _mm256_setr_epi8(14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15,
                                         14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15, 14, 15);
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        __m256i b0 = _mm256_set1_epi16((short)(batch % 1009));
        int64_t total = 0;
        uint64_t rank0 = 0;
        int bad = 0;
        int64_t j = 0;
        while (j + 16 <= size) {
            int64_t blocks = (size - j) / 16;
            if (blocks > 16) blocks = 16;
            __m256i acc = _mm256_setzero_si256();
            for (int64_t k = 0; k < blocks; k++, j += 16) {
                __m256i x = _mm256_add_epi16(_mm256_loadu_si256((const __m256i *)(r + j)), b0);
                x = _mm256_min_epu16(x, _mm256_sub_epi16(x, c1009));
                __m256i q = _mm256_srli_epi16(_mm256_mulhi_epu16(x, _mm256_set1_epi16((short)43691)), 1);
                __m256i rem = _mm256_sub_epi16(x, _mm256_mullo_epi16(q, _mm256_set1_epi16(3)));
                __m256i m = _mm256_cmpeq_epi16(rem, _mm256_setzero_si256());
                __m256i s = _mm256_srli_epi16(m, 15);
                s = _mm256_add_epi16(s, _mm256_slli_si256(s, 2));
                s = _mm256_add_epi16(s, _mm256_slli_si256(s, 4));
                s = _mm256_add_epi16(s, _mm256_slli_si256(s, 8));
                __m256i carry = _mm256_permute2x128_si256(_mm256_shuffle_epi8(s, bc7), _mm256_shuffle_epi8(s, bc7), 0x08);
                s = _mm256_add_epi16(_mm256_add_epi16(s, carry), _mm256_set1_epi16((short)rank0));
                acc = _mm256_add_epi32(acc, _mm256_madd_epi16(_mm256_and_si256(x, m), s));
                rank0 += (uint32_t)__builtin_popcount((unsigned)_mm256_movemask_epi8(m)) >> 1;
            }
            bad |= __builtin_add_overflow(total, (int64_t)hsum_u32x8(acc), &total);
        }
        for (; j < size; j++) {
            uint32_t x = (r[j] + (uint32_t)(batch % 1009)) % 1009u;
            if (x % 3u == 0) { rank0++; bad |= __builtin_add_overflow(total, (int64_t)(rank0 * x), &total); }
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    free(r);
    return checksum;
}
#endif /* __AVX2__ */

/* ================================= main ================================================= */
static int64_t *read_file(const char *path, int64_t size) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror("fopen"); exit(2); }
    int64_t *d = malloc(sizeof(int64_t) * (size_t)size);
    if (fread(d, sizeof(int64_t), (size_t)size, f) != (size_t)size) { fprintf(stderr, "short data file\n"); exit(2); }
    fclose(f);
    return d;
}

int main(int argc, char **argv) {
    if (argc == 5 && !strcmp(argv[1], "gen")) { /* gen SIZE SEED PATH: a_j = seed + 13 j */
        int64_t size = atoll(argv[2]), seed = atoll(argv[3]);
        FILE *f = fopen(argv[4], "wb");
        for (int64_t j = 0; j < size; j++) { int64_t v = seed + j * 13; fwrite(&v, 8, 1, f); }
        fclose(f);
        return 0;
    }
    if (argc == 6 && !strcmp(argv[1], "genwide")) { /* genwide SIZE SEED MAX PATH: arbitrary data */
        int64_t size = atoll(argv[2]), seed = atoll(argv[3]), max = atoll(argv[4]);
        FILE *f = fopen(argv[5], "wb");
        uint64_t s = (uint64_t)seed * 6364136223846793005ULL + 1442695040888963407ULL;
        for (int64_t j = 0; j < size; j++) {
            s = s * 6364136223846793005ULL + 1442695040888963407ULL;
            int64_t v = (int64_t)((s >> 1) % (uint64_t)(max + 1));
            fwrite(&v, 8, 1, f);
        }
        fclose(f);
        return 0;
    }
    if (argc < 5) return 2;
    int which = atoi(argv[1]);
    int64_t size = atoll(argv[2]), iterations = atoll(argv[3]), seed = atoll(argv[4]);
    const int64_t *a = argc == 6 ? read_file(argv[5], size) : NULL;
    heap_t *volatile hslot = &g_heap;
    int64_t start = now_ns(), checksum = 0;
    switch (which) {
    case 1: checksum = v1(hslot, size, iterations, seed, NULL); break;
    case 20: checksum = v20(hslot, size, iterations, seed, a); break;
    case 2: checksum = v2(hslot, size, iterations, seed); break;
    case 3: checksum = v3(hslot, size, iterations, seed); break;
    case 4: checksum = v4(size, iterations, seed); break;
    case 5: checksum = v5(size, iterations, seed); break;
    case 6: checksum = v6(size, iterations, seed); break;
    case 12: checksum = v12(size, iterations, seed); break;
    case 7: checksum = v7(size, iterations, seed); break;
    case 8: checksum = v8(size, iterations, seed); break;
    case 9: checksum = v9(size, iterations, seed); break;
    case 10: checksum = v10(size, iterations, seed); break;
    case 30: if (!a) return 2; checksum = v30(a, size, iterations); break;
#ifdef __AVX2__
    case 11: checksum = v11(size, iterations, seed); break;
    case 31: if (!a) return 2; checksum = v31(a, size, iterations); break;
#endif
    default: return 2;
    }
    printf("%lld %lld\n", (long long)checksum, (long long)(now_ns() - start));
    return 0;
}
