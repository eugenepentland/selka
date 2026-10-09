/* PM-3 ladder 1: the matmul inner loop (bench/parity/suite/matmul.my).
 *
 * Lists are mylang blocks: a 32-byte header (count u32, kind u32, len i64, cap i64,
 * reserved) and the elements at offset 32. A list[list[float]] holds block
 * pointers. RUNG selects one transcription; every rung prints what matmul.my
 * prints (trace and total, each times 1000).
 *
 *   0  what mylang emits today: every element access reloads b's row pointer
 *      from the outer list and the row's length (a store of a float into
 *      element data may alias the pointer slot: one TBAA tag for all data),
 *      checks j against that length, reloads c's row pointer, and stores it
 *      back into c after each element (the list_set of `c[i][j] = ...`).
 *      c's row index check is already gone today (the core's length facts),
 *      so it is not transcribed.
 *      Built with -fno-strict-aliasing, so C has mylang's single data tag.
 *   1  rung 0 without the per-element bounds checks.
 *   2  rung 0 with the row pointers, lengths and c's row hoisted out of the j
 *      loop and the store-back gone (header loads hoisted); the bounds checks
 *      stay, against the hoisted lengths.
 *   3  rung 2 with the bounds check hoisted: n <= len checked once per row.
 *   4  rung 3 with `restrict` rows: c[i] is unique, so it shares no bytes
 *      with b[k] (value semantics) and the j loop vectorizes without a
 *      runtime overlap test.
 *   5  rung 0's code with element data typed (-fstrict-aliasing): float
 *      elements and block pointers are different C types, which is what
 *      splitting `myl.data` by element type gives LLVM. Nothing else changes.
 *   6  rung 5 with the bounds check hoisted to one test per j loop (loop
 *      versioning on n <= len(b[k])), the rows' loads left to the compiler.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct block {
    uint32_t count, kind;
    int64_t len, cap;
    void *reserved;
} block;

/* Element data at offset 32, read and written through its element type, as
   mylang's LLVM does (`load double` / `load ptr` on the data). */
#define F(b) ((double *)((char *)(b) + 32))
#define P(b) ((block **)((char *)(b) + 32))

#ifndef RUNG
#define RUNG 0
#endif

static __attribute__((noinline, cold, noreturn)) void trap(int64_t index, int64_t len) {
    fprintf(stderr, "R_LIST_BOUNDS %lld %lld\n", (long long)index, (long long)len);
    exit(1);
}

static block *list_new(int64_t n, int64_t size) {
    block *b = aligned_alloc(32, (size_t)(32 + n * size + 31) & ~(size_t)31);
    b->count = 1; b->kind = 0; b->len = n; b->cap = n; b->reserved = 0;
    return b;
}

static int64_t lcg(int64_t seed) { return (seed * 3877 + 29573) % 139968; }

static block *random_matrix(int64_t n, int64_t *seed) {
    block *rows = list_new(n, 8);
    for (int64_t i = 0; i < n; i++) {
        block *row = list_new(n, 8);
        for (int64_t j = 0; j < n; j++) {
            *seed = lcg(*seed);
            F(row)[j] = (double)*seed / 139968.0;
        }
        P(rows)[i] = row;
    }
    return rows;
}

/* Opaque so the compiler cannot see the matrices' shape. */
__attribute__((noinline)) static void multiply(block *a, block *b, block *c, int64_t n) {
    for (int64_t i = 0; i < n; i++) {
        for (int64_t k = 0; k < n; k++) {
            block *ra = P(a)[i];
            if ((uint64_t)k >= (uint64_t)ra->len) trap(k, ra->len);
            double aik = F(ra)[k];
#if RUNG == 6
            if (n > P(b)[k]->len) trap(n - 1, P(b)[k]->len);
#endif
#if RUNG == 0 || RUNG == 1 || RUNG == 5 || RUNG == 6
            for (int64_t j = 0; j < n; j++) {
                block *rb = P(b)[k];
#if RUNG != 1 && RUNG != 6
                if ((uint64_t)j >= (uint64_t)rb->len) trap(j, rb->len);
#endif
                block *rc = P(c)[i];
                F(rc)[j] = F(rc)[j] + aik * F(rb)[j];
                P(c)[i] = rc;
            }
#elif RUNG == 2
            block *rb = P(b)[k];
            block *rc = P(c)[i];
            int64_t lb = rb->len;
            double *fb = F(rb), *fc = F(rc);
            for (int64_t j = 0; j < n; j++) {
                if ((uint64_t)j >= (uint64_t)lb) trap(j, lb);
                fc[j] = fc[j] + aik * fb[j];
            }
#elif RUNG == 3
            block *rb = P(b)[k];
            block *rc = P(c)[i];
            if (n > rb->len) trap(n - 1, rb->len);
            if (n > rc->len) trap(n - 1, rc->len);
            double *fb = F(rb), *fc = F(rc);
            for (int64_t j = 0; j < n; j++) fc[j] = fc[j] + aik * fb[j];
#elif RUNG == 4
            block *rb = P(b)[k];
            block *rc = P(c)[i];
            if (n > rb->len) trap(n - 1, rb->len);
            if (n > rc->len) trap(n - 1, rc->len);
            const double *restrict fb = F(rb);
            double *restrict fc = F(rc);
            for (int64_t j = 0; j < n; j++) fc[j] = fc[j] + aik * fb[j];
#endif
        }
    }
}

int main(void) {
    int64_t n = 500, seed = 42;
    block *a = random_matrix(n, &seed);
    block *b = random_matrix(n, &seed);
    block *c = list_new(n, 8);
    for (int64_t i = 0; i < n; i++) {
        block *row = list_new(n, 8);
        for (int64_t j = 0; j < n; j++) F(row)[j] = 0.0;
        P(c)[i] = row;
    }
    multiply(a, b, c, n);
    double trace = 0.0, total = 0.0;
    for (int64_t i = 0; i < n; i++) trace += F(P(c)[i])[i];
    for (int64_t i = 0; i < n; i++)
        for (int64_t j = 0; j < n; j++) total += F(P(c)[i])[j];
    printf("%lld\n%lld\n", (long long)(trace * 1000.0), (long long)(total * 1000.0));
    return 0;
}
