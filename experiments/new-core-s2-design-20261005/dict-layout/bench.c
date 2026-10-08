/* S2 dictionary-layout microbenchmark (docs/design/new-core-s2.md §2).
   Three layouts x {int, str} keys, driven with the key/value distributions of the
   benchmark rows dict_lookup, dict_lookup_str, dict_update, dict_update_str, set_dedup and
   word_count (benchmarks/runtime/expanded/{collections,text}/main.my), plus sparse 64-bit
   keys, mixed-length string keys and a delete/re-insert churn whose order-sensitive
   checksum every layout must reproduce.  Run: ./run.sh (taskset -c 10). */
#include <stdio.h>
#include <time.h>
#include <malloc.h>
#include <linux/perf_event.h>
#include <sys/syscall.h>
#include <unistd.h>
#include "common.h"

#define KEYSUM_INT(k) ((uint64_t)(k))
#define KEYSUM_STR(k) ((uint64_t)(k)->len)
#define EQ_INT(a, b) ((a) == (b))

#define KT int64_t
#define KHASH hash_int
#define KEQ EQ_INT
#define KEYSUM KEYSUM_INT
#define PFX old_i
#include "layout_old.h"
#undef PFX
#define HINT
#define PFX oldh_i
#include "layout_old.h"
#undef PFX
#define PFX cpyh_i
#include "layout_cpy.h"
#undef PFX
#undef HINT
#define PFX cpy_i
#include "layout_cpy.h"
#undef PFX
#define PFX swiss_i
#include "layout_swiss.h"
#undef PFX
#define PFX hyb_i
#include "layout_hybrid.h"
#undef PFX
#undef KT
#undef KHASH
#undef KEQ
#undef KEYSUM

#define KT Str *
#define KHASH str_hash
#define KEQ str_eq
#define KEYSUM KEYSUM_STR
#define PFX old_s
#include "layout_old.h"
#undef PFX
#define HINT
#define PFX oldh_s
#include "layout_old.h"
#undef PFX
#undef HINT
#define PFX cpy_s
#include "layout_cpy.h"
#undef PFX
#define PFX swiss_s
#include "layout_swiss.h"
#undef PFX
#define PFX hyb_s
#include "layout_hybrid.h"
#undef PFX

/* User-mode core cycles from a perf counter (frequency-independent); falls back to ns. */
static int cycles_fd = -1;
static void cycles_open(void) {
    struct perf_event_attr a;
    memset(&a, 0, sizeof a);
    a.type = PERF_TYPE_HARDWARE; a.size = sizeof a; a.config = PERF_COUNT_HW_CPU_CYCLES;
    a.exclude_kernel = 1; a.exclude_hv = 1;
    cycles_fd = (int)syscall(SYS_perf_event_open, &a, 0, -1, -1, 0);
}
static double now_ns(void) {
    if (cycles_fd >= 0) {
        uint64_t c = 0;
        if (read(cycles_fd, &c, sizeof c) == sizeof c) return (double)c;
    }
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1e9 + (double)t.tv_nsec;
}

static uint64_t rng = 0x123456789abcdefull;
static uint64_t next_rand(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }

enum { SEED = 42 };
static int64_t *values;          /* (seed + j*13) % 1009 */
static Str **keys;               /* str(j), j < 2n */
static int64_t *sparse_keys, *sparse_queries;
static Str **mixed_keys, **mixed_queries;
static Str **words;              /* word_count's split pieces (hash reset per use) */
static int64_t nwords;
static int N;
static uint32_t presize; /* PRESIZE=1: reserve 2n entries up front (a builder-known count) */

/* ---- workloads, one instance per layout ---- */
#define WORKLOADS_INT(P)                                                                   \
static uint64_t P##_lookup(int iters) {                                                    \
    P *d = P##_new(presize);                                                                     \
    for (int j = 0; j < N; ++j) P##_put(d, j, values[j]);                                  \
    uint64_t total = 0;                                                                    \
    for (int b = 0; b < iters; ++b)                                                        \
        for (int j = 0; j < N; ++j) {                                                      \
            int64_t key = (SEED + (int64_t)j * 17 + b) % (2 * N), v;                       \
            total += P##_get(d, key, &v) ? v : 17;                                         \
        }                                                                                  \
    P##_free(d);                                                                           \
    return total;                                                                          \
}                                                                                          \
static uint64_t P##_update2(int iters) { /* get, then put: two probes */                   \
    uint64_t total = 0;                                                                    \
    for (int b = 0; b < iters; ++b) {                                                      \
        P *d = P##_new(presize);                                                                 \
        for (int j = 0; j < N; ++j) P##_put(d, j, values[j]);                              \
        for (int j = 0; j < 2 * N; ++j) {                                                  \
            int64_t key = (SEED + (int64_t)j * 17 + b) % (2 * N), v;                       \
            if (!P##_get(d, key, &v)) v = 17;                                              \
            P##_put(d, key, (v + j + b + 1) % 1000003);                                    \
        }                                                                                  \
        total += P##_sum_items(d);                                                         \
        P##_free(d);                                                                       \
    }                                                                                      \
    return total;                                                                          \
}                                                                                          \
static uint64_t P##_update1(int iters) { /* fused upsert: one probe */                     \
    uint64_t total = 0;                                                                    \
    for (int b = 0; b < iters; ++b) {                                                      \
        P *d = P##_new(presize);                                                                 \
        for (int j = 0; j < N; ++j) P##_put(d, j, values[j]);                              \
        for (int j = 0; j < 2 * N; ++j) {                                                  \
            int64_t key = (SEED + (int64_t)j * 17 + b) % (2 * N);                          \
            int64_t *v = P##_upsert(d, key, 17);                                           \
            *v = (*v + j + b + 1) % 1000003;                                               \
        }                                                                                  \
        total += P##_sum_items(d);                                                         \
        P##_free(d);                                                                       \
    }                                                                                      \
    return total;                                                                          \
}                                                                                          \
static uint64_t P##_dedup(int iters) {                                                     \
    uint64_t total = 0;                                                                    \
    int64_t limit = N / 4 > 2 ? N / 4 : 2;                                                 \
    for (int b = 0; b < iters; ++b) {                                                      \
        P *d = P##_new(presize);                                                                 \
        for (int j = 0; j < N; ++j) P##_upsert(d, (SEED + b + (int64_t)j * 13) % limit, 0); \
        total += P##_sum_items(d);                                                         \
        P##_free(d);                                                                       \
    }                                                                                      \
    return total;                                                                          \
}                                                                                          \
static uint64_t P##_sparse(int iters) { /* random 64-bit keys, half the queries miss */   \
    P *d = P##_new(presize);                                                                     \
    for (int j = 0; j < N; ++j) P##_put(d, sparse_keys[j], j);                             \
    uint64_t total = 0;                                                                    \
    for (int b = 0; b < iters; ++b)                                                        \
        for (int j = 0; j < 2 * N; ++j) {                                                  \
            int64_t v;                                                                     \
            total += P##_get(d, sparse_queries[j], &v) ? v : 17;                           \
        }                                                                                  \
    P##_free(d);                                                                           \
    return total;                                                                          \
}                                                                                          \
static uint64_t P##_churn(int iters) { /* insert / delete / re-insert; order-sensitive */  \
    uint64_t total = 0, r = 99;                                                            \
    for (int b = 0; b < iters; ++b) {                                                      \
        P *d = P##_new(presize);                                                                 \
        for (int j = 0; j < 4 * N; ++j) {                                                  \
            r ^= r << 13; r ^= r >> 7; r ^= r << 17;                                       \
            int64_t key = (int64_t)(r % (uint64_t)(N + 1)), v;                             \
            int op = (int)((r >> 40) % 10);                                                \
            if (op < 4) *P##_upsert(d, key, 0) += j;                                       \
            else if (op < 7) total += P##_del(d, key);                                     \
            else total += P##_get(d, key, &v) ? (uint64_t)v : 1;                           \
        }                                                                                  \
        total = total * 7 + P##_sum_items(d);                                              \
        P##_free(d);                                                                       \
    }                                                                                      \
    return total;                                                                          \
}

#define WORKLOADS_STR(P)                                                                   \
static uint64_t P##_lookup(int iters) {                                                    \
    P *d = P##_new(presize);                                                                     \
    for (int j = 0; j < N; ++j) P##_put(d, keys[j], values[j]);                            \
    uint64_t total = 0;                                                                    \
    for (int b = 0; b < iters; ++b)                                                        \
        for (int j = 0; j < N; ++j) {                                                      \
            int64_t key = (SEED + (int64_t)j * 17 + b) % (2 * N), v;                       \
            total += P##_get(d, keys[key], &v) ? v : 17;                                   \
        }                                                                                  \
    P##_free(d);                                                                           \
    return total;                                                                          \
}                                                                                          \
static uint64_t P##_update2(int iters) {                                                   \
    uint64_t total = 0;                                                                    \
    for (int b = 0; b < iters; ++b) {                                                      \
        P *d = P##_new(presize);                                                                 \
        for (int j = 0; j < N; ++j) P##_put(d, keys[j], values[j]);                        \
        for (int j = 0; j < 2 * N; ++j) {                                                  \
            int64_t key = (SEED + (int64_t)j * 17 + b) % (2 * N), v;                       \
            if (!P##_get(d, keys[key], &v)) v = 17;                                        \
            P##_put(d, keys[key], (v + j + b + 1) % 1000003);                              \
        }                                                                                  \
        total += P##_sum_items(d);                                                         \
        P##_free(d);                                                                       \
    }                                                                                      \
    return total;                                                                          \
}                                                                                          \
static uint64_t P##_update1(int iters) {                                                   \
    uint64_t total = 0;                                                                    \
    for (int b = 0; b < iters; ++b) {                                                      \
        P *d = P##_new(presize);                                                                 \
        for (int j = 0; j < N; ++j) P##_put(d, keys[j], values[j]);                        \
        for (int j = 0; j < 2 * N; ++j) {                                                  \
            int64_t key = (SEED + (int64_t)j * 17 + b) % (2 * N);                          \
            int64_t *v = P##_upsert(d, keys[key], 17);                                     \
            *v = (*v + j + b + 1) % 1000003;                                               \
        }                                                                                  \
        total += P##_sum_items(d);                                                         \
        P##_free(d);                                                                       \
    }                                                                                      \
    return total;                                                                          \
}                                                                                          \
static uint64_t P##_mixed(int iters) { /* 4-40 byte keys, queries are equal copies */      \
    P *d = P##_new(presize);                                                                     \
    for (int j = 0; j < N; ++j) P##_put(d, mixed_keys[j], j);                              \
    uint64_t total = 0;                                                                    \
    for (int b = 0; b < iters; ++b)                                                        \
        for (int j = 0; j < 2 * N; ++j) {                                                  \
            int64_t v;                                                                     \
            total += P##_get(d, mixed_queries[j], &v) ? v : 17;                            \
        }                                                                                  \
    P##_free(d);                                                                           \
    return total;                                                                          \
}                                                                                          \
static uint64_t P##_words(int iters) { /* word_count: fresh pieces, 3 probes per word */   \
    uint64_t total = 0;                                                                    \
    for (int b = 0; b < iters; ++b) {                                                      \
        P *d = P##_new(presize);                                                                 \
        for (int64_t w = 0; w < nwords; ++w) {                                             \
            Str *word = words[w];                                                          \
            word->hash = 0;                                                                \
            int64_t v;                                                                     \
            if (P##_get(d, word, &v)) { P##_get(d, word, &v); P##_put(d, word, v + 1); }   \
            else P##_put(d, word, 1);                                                      \
        }                                                                                  \
        total += P##_sum_items(d);                                                         \
        P##_free(d);                                                                       \
    }                                                                                      \
    return total;                                                                          \
}

WORKLOADS_INT(old_i)
WORKLOADS_INT(oldh_i)
WORKLOADS_INT(cpy_i)
WORKLOADS_INT(cpyh_i)
WORKLOADS_INT(swiss_i)
WORKLOADS_INT(hyb_i)
WORKLOADS_STR(old_s)
WORKLOADS_STR(oldh_s)
WORKLOADS_STR(cpy_s)
WORKLOADS_STR(swiss_s)
WORKLOADS_STR(hyb_s)

typedef uint64_t (*workload)(int);
typedef struct { const char *name; workload fn[5]; double ops_per_iter_n; /* ops = factor*N per iter */ } Row;
static const char *layouts_int[] = {"old", "old+hint", "cpython", "cpython+hint", "swiss", "hybrid"};
static const char *layouts_str[] = {"old", "old+hint", "cpython", "swiss", "hybrid"};

static Str *make_str(const char *t) { return str_new(t, (int64_t)strlen(t)); }

static void setup(int n) {
    N = n;
    values = malloc(sizeof(int64_t) * (size_t)n);
    for (int j = 0; j < n; ++j) values[j] = (SEED + (int64_t)j * 13) % 1009;
    keys = malloc(sizeof(Str *) * (size_t)(2 * n));
    char buf[64];
    for (int j = 0; j < 2 * n; ++j) { snprintf(buf, sizeof buf, "%d", j); keys[j] = make_str(buf); }
    sparse_keys = malloc(sizeof(int64_t) * (size_t)n);
    sparse_queries = malloc(sizeof(int64_t) * (size_t)(2 * n));
    for (int j = 0; j < n; ++j) sparse_keys[j] = (int64_t)next_rand();
    for (int j = 0; j < 2 * n; ++j) sparse_queries[j] = (next_rand() & 1) ? sparse_keys[next_rand() % (uint64_t)n] : (int64_t)next_rand();
    mixed_keys = malloc(sizeof(Str *) * (size_t)n);
    mixed_queries = malloc(sizeof(Str *) * (size_t)(2 * n));
    for (int j = 0; j < n; ++j) {
        int len = 4 + (int)(next_rand() % 37);
        for (int c = 0; c < len; ++c) buf[c] = (char)('a' + next_rand() % 26);
        buf[len] = 0;
        mixed_keys[j] = make_str(buf);
    }
    for (int j = 0; j < 2 * n; ++j) {
        if (next_rand() & 1) mixed_queries[j] = make_str((char *)mixed_keys[next_rand() % (uint64_t)n]->data);
        else {
            int len = 4 + (int)(next_rand() % 37);
            for (int c = 0; c < len; ++c) buf[c] = (char)('a' + next_rand() % 26);
            buf[len] = 0;
            mixed_queries[j] = make_str(buf);
        }
        str_hash(mixed_queries[j]); /* a query key built once, used many times */
    }
    static const char *vocabulary[] = {"red", "blue", "caf\xc3\xa9", "red", "green", "blue", "na\xc3\xafve", "red"};
    nwords = n + 1;
    words = malloc(sizeof(Str *) * (size_t)nwords);
    for (int j = 0; j < n; ++j) words[j] = make_str(vocabulary[(SEED + j) % 8]);
    words[n] = make_str("red");
}

static int cmp_double(const void *a, const void *b) { double x = *(const double *)a, y = *(const double *)b; return (x > y) - (x < y); }

static const char *only_row, *only_layout;
static void run(const char *name, const char **names, int nl, workload *fns, double ops, int iters, int rounds) {
    if (only_row && strcmp(only_row, name) != 0) return;
    if (only_layout) { for (int l = 0; l < nl; ++l) if (!strcmp(names[l], only_layout)) { names += l; fns += l; nl = 1; break; } }
    double samples[8][32];
    uint64_t sums[8];
    for (int r = 0; r < rounds; ++r)
        for (int l = 0; l < nl; ++l) {
            double t0 = now_ns();
            uint64_t s = fns[l](iters);
            double t1 = now_ns();
            samples[l][r] = (t1 - t0) / (ops * iters);
            if (r == 0) sums[l] = s;
            else if (sums[l] != s) { fprintf(stderr, "nondeterministic %s %s\n", name, names[l]); exit(1); }
        }
    printf("%-14s n=%-7d", name, N);
    for (int l = 0; l < nl; ++l) {
        qsort(samples[l], (size_t)rounds, sizeof(double), cmp_double);
        printf("  %s %.2f", names[l], samples[l][rounds / 2]);
        if (sums[l] != sums[0]) printf(" [CHECKSUM MISMATCH %llu vs %llu]", (unsigned long long)sums[l], (unsigned long long)sums[0]);
    }
    printf("   (median of %d)\n", rounds);
}

int main(int argc, char **argv) {
    mallopt(M_MMAP_THRESHOLD, 1 << 30); /* no mmap/munmap page-fault noise per batch */
    mallopt(M_TRIM_THRESHOLD, 1 << 30);
    int n = argc > 1 ? atoi(argv[1]) : 4096;
    int rounds = argc > 2 ? atoi(argv[2]) : 7;
    only_row = argc > 3 ? argv[3] : NULL;
    only_layout = argc > 4 ? argv[4] : NULL;
    cycles_open();
    fprintf(stderr, cycles_fd >= 0 ? "unit: user cycles/op\n" : "unit: ns/op\n");
    setup(n);
    presize = getenv("PRESIZE") ? (uint32_t)(2 * n) : 0;
    int64_t target = 4000000; /* operations per measurement */
    int it1 = (int)(target / n) > 0 ? (int)(target / n) : 1;
    int it2 = (int)(target / (3 * n)) > 0 ? (int)(target / (3 * n)) : 1;
#define I5(w) {old_i_##w, oldh_i_##w, cpy_i_##w, cpyh_i_##w, swiss_i_##w, hyb_i_##w}
#define S4(w) {old_s_##w, oldh_s_##w, cpy_s_##w, swiss_s_##w, hyb_s_##w}
    workload lookup[] = I5(lookup), update2[] = I5(update2), update1[] = I5(update1), dedup[] = I5(dedup), sparse[] = I5(sparse), churn[] = I5(churn);
    workload slookup[] = S4(lookup), supdate2[] = S4(update2), supdate1[] = S4(update1), mixed[] = S4(mixed), wordsw[] = S4(words);
    run("dict_lookup", layouts_int, 6, lookup, 1.0 * n, it1, rounds);
    run("dict_update/2", layouts_int, 6, update2, 3.0 * n, it2, rounds);
    run("dict_update/1", layouts_int, 6, update1, 3.0 * n, it2, rounds);
    run("set_dedup", layouts_int, 6, dedup, 1.0 * n, it1, rounds);
    run("sparse_int", layouts_int, 6, sparse, 2.0 * n, it1 / 2 > 0 ? it1 / 2 : 1, rounds);
    run("churn", layouts_int, 6, churn, 4.0 * n, it1 / 4 > 0 ? it1 / 4 : 1, rounds);
    run("lookup_str", layouts_str, 5, slookup, 1.0 * n, it1, rounds);
    run("update_str/2", layouts_str, 5, supdate2, 3.0 * n, it2, rounds);
    run("update_str/1", layouts_str, 5, supdate1, 3.0 * n, it2, rounds);
    run("mixed_str", layouts_str, 5, mixed, 2.0 * n, it1 / 2 > 0 ? it1 / 2 : 1, rounds);
    run("word_count", layouts_str, 5, wordsw, 1.0 * (n + 1), it1, rounds);
    return 0;
}
