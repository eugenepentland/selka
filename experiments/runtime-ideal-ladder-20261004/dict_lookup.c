// dict_lookup ladder. Re-implements kind 3 of benchmarks/runtime/expanded/collections/main.my:
//   untimed: values[j] = (seed + 13 j) % 1009; lookup = {j: values[j] for j in range(size)}
//   for batch in range(iterations):
//       total = 0
//       for j in range(size):
//           key = (seed + j*17 + batch) % (size*2)
//           total += lookup.get(key, 17)            # half the keys hit, half miss
//       checksum = (checksum + total) % 1000000007
// Usage: dict_lookup VERSION SIZE ITERATIONS SEED [QUERYFILE]
//   QUERYFILE (versions >= 20): u64 keys[2*SIZE]; the first SIZE are inserted (value j ->
//   values[j]); query j of a batch asks keys[(seed + 17 j + batch) % (2 SIZE)]. A file of
//   identity keys reproduces the benchmark's checksum; a file of sparse ids does not
//   (compare against v20, the today-model reading the same file).
// Prints "checksum elapsed_ns". Build with -fno-strict-aliasing.
#include "common.h"

/* ------------------------------------------------------------------------------------
 * mylang's dictionary as the compiled code sees it (src/native_dictionary.[ch]):
 * an insertion-ordered entry list of {key,value} 16-byte entries, a linear-probing index
 * of 64-bit slots (hash << 32 | entry+1) at load <= 5/8, and a "last probe" hint record
 * that every read may rewrite. This is a faithful copy of recall/locate/probe_word/
 * read_walk for a word-keyed dictionary. */
enum { KEY_TEXT, KEY_WORD, KEY_NARROW, KEY_WIDE, KEY_STRUCT };
enum { PROBE_NONE, PROBE_FOUND, PROBE_ABSENT };
#define NO_ENTRY ((size_t)-1)
#define NO_SLOT 0xffffffffu
#define KEY_MIX 0x9e3779b97f4a7c15ULL
#define KEY_SPREAD 0xbf58476d1ce4e5b9ULL
typedef struct { uint64_t key; size_t entry; uint32_t slot, hash; unsigned state; size_t offset, bytes, epoch; } probe_t;
typedef struct { int64_t len, cap, gen; const void *elem; unsigned char *storage; } mlist;
typedef struct {
    mlist *entries;
    size_t key_size, value_size, value_offset, stride;
    unsigned key_kind;
    struct { uint64_t *slots; size_t capacity; } index;
    probe_t last;
} mdict;
typedef struct { size_t entry; uint32_t slot, hash; } located;

static inline uint64_t fold_multiply(uint64_t a, uint64_t b) {
    unsigned __int128 p = (unsigned __int128)a * b;
    return (uint64_t)p ^ (uint64_t)(p >> 64);
}
static inline uint32_t scalar_hash(uint64_t bits) {
    uint64_t h = fold_multiply(bits ^ KEY_MIX, KEY_SPREAD);
    return (uint32_t)(h ^ (h >> 32));
}
static inline const unsigned char *entry_at(const mdict *d, size_t i) { return d->entries->storage + i * d->stride; }

static located probe_word(const mdict *d, uint64_t bits) {
    uint32_t hash = scalar_hash(bits);
    const uint64_t *slots = d->index.slots;
    const unsigned char *storage = d->entries->storage;
    size_t mask = d->index.capacity - 1, at = hash & mask, stride = d->stride;
    for (uint64_t slot; (slot = slots[at]); at = (at + 1) & mask) {
        if ((uint32_t)(slot >> 32) != hash) continue;
        size_t entry = (size_t)(slot & 0xffffffffu) - 1;
        uint64_t held;
        memcpy(&held, storage + entry * stride, 8);
        if (held == bits) return (located){entry, (uint32_t)at, hash};
    }
    return (located){NO_ENTRY, (uint32_t)at, hash};
}
static inline int record_key(const mdict *d, const void *key, uint64_t *bits) {
    switch (d->key_kind) {
    case KEY_TEXT: *bits = (uint64_t)(uintptr_t)key; return 1;
    case KEY_WORD: memcpy(bits, key, 8); return 1;
    case KEY_NARROW: *bits = 0; memcpy(bits, key, d->key_size); return 1;
    default: return 0;
    }
}
static inline size_t recall(const mdict *d, const void *key) {
    const probe_t *last = &d->last;
    uint64_t bits, held;
    if (last->state != PROBE_FOUND || !record_key(d, key, &bits) || bits != last->key) return NO_ENTRY;
    if ((int64_t)last->entry >= d->entries->len) return NO_ENTRY;
    const unsigned char *entry = entry_at(d, last->entry);
    record_key(d, entry, &held);
    return held == bits ? last->entry : NO_ENTRY;
}
static inline located locate(const mdict *d, const void *key) {
    probe_t *last = (probe_t *)&d->last;
    uint64_t bits = 0;
    int recorded = record_key(d, key, &bits);
    if (last->state == PROBE_ABSENT && recorded && bits == last->key) return (located){NO_ENTRY, last->slot, last->hash};
    located found;
    if (!d->index.capacity || d->key_kind >= KEY_WIDE) abort();
    found = probe_word(d, bits);
    if (!recorded) last->state = PROBE_NONE;
    else if (found.entry != NO_ENTRY) { last->key = bits; last->entry = found.entry; last->state = PROBE_FOUND; }
    else if (found.slot != NO_SLOT) *last = (probe_t){.key = bits, .slot = found.slot, .hash = found.hash, .state = PROBE_ABSENT};
    else last->state = PROBE_NONE;
    return found;
}
__attribute__((noinline)) static int read_walk(const mdict *d, const void *key, void *output) {
    size_t index = locate(d, key).entry;
    if (index == NO_ENTRY) return 0;
    memcpy(output, entry_at(d, index) + d->value_offset, d->value_size);
    return 1;
}
/* myl_native_dictionary_read */
__attribute__((noinline)) static int dict_read(const mdict *d, const void *key, void *output) {
    size_t index = recall(d, key);
    if (index == NO_ENTRY) return read_walk(d, key, output);
    memcpy(output, entry_at(d, index) + d->value_offset, d->value_size);
    return 1;
}

static mdict *build_mdict(const uint64_t *dkeys, const int64_t *values, int64_t size) {
    mdict *d = calloc(1, sizeof *d);
    d->entries = calloc(1, sizeof *d->entries);
    d->stride = 16; d->key_size = 8; d->value_size = 8; d->value_offset = 8; d->key_kind = KEY_WORD;
    d->entries->len = d->entries->cap = size;
    d->entries->storage = malloc((size_t)size * 16);
    size_t cap = 8;
    while ((size_t)size * 8 > cap * 5) cap *= 2;
    d->index.capacity = cap;
    d->index.slots = calloc(cap, 8);
    for (int64_t i = 0; i < size; i++) {
        memcpy(d->entries->storage + (size_t)i * 16, &dkeys[i], 8);
        memcpy(d->entries->storage + (size_t)i * 16 + 8, &values[i], 8);
        uint32_t h = scalar_hash(dkeys[i]);
        size_t at = h & (cap - 1);
        while (d->index.slots[at]) at = (at + 1) & (cap - 1);
        d->index.slots[at] = (uint64_t)h << 32 | (uint64_t)(i + 1);
    }
    return d;
}

/* ---- v1: today's semantics. The generic read call, hint record traffic, out-parameter,
 * checked arithmetic for the key and the running total. */
#define DEFINE_TODAY(NAME, KEYOF)                                                                  \
__attribute__((noinline)) static int64_t NAME(mdict *volatile slot, int64_t size, int64_t iterations, \
                                              int64_t seed, const uint64_t *qk) {                  \
    mdict *d = slot;                                                                               \
    int64_t checksum = 0, m;                                                                       \
    (void)qk;                                                                                      \
    if (__builtin_mul_overflow(size, 2, &m)) trap("overflow");                                     \
    for (int64_t batch = 0; batch < iterations; batch++) {                                         \
        int64_t total = 0;                                                                         \
        for (int64_t j = 0; j < size; j++) {                                                       \
            int64_t u, t, idx;                                                                     \
            if (__builtin_mul_overflow(j, 17, &u) || __builtin_add_overflow(seed, u, &t) ||        \
                __builtin_add_overflow(t, batch, &t)) trap("overflow");                            \
            idx = floormod(t, m);                                                                  \
            uint64_t key = KEYOF;                                                                  \
            int64_t out = 0;                                                                       \
            int found = dict_read(d, &key, &out);                                                  \
            int64_t value = found ? out : 17;                                                      \
            if (__builtin_add_overflow(total, value, &total)) trap("overflow");                    \
        }                                                                                          \
        checksum = floormod(checksum + total, MOD);                                                \
    }                                                                                              \
    return checksum;                                                                               \
}
DEFINE_TODAY(v1, (uint64_t)idx)
DEFINE_TODAY(v20, qk[idx])

/* ---- v2: + value semantics: the dictionary is not written during the loop (no `mut`
 * access), so the hint record is dead (no recall, no PROBE_ABSENT test, no hint stores)
 * and its fields are hoisted. The probe is still a generic out-of-line call with an
 * out-parameter, hash fold_multiply, slot -> entry indirection. */
__attribute__((noinline)) static int probe_plain(const uint64_t *slots, size_t mask, const unsigned char *storage,
                                                 uint64_t key, int64_t *out) {
    uint32_t hash = scalar_hash(key);
    size_t at = hash & mask;
    for (uint64_t slot; (slot = slots[at]); at = (at + 1) & mask) {
        if ((uint32_t)(slot >> 32) != hash) continue;
        size_t entry = (size_t)(slot & 0xffffffffu) - 1;
        uint64_t held;
        memcpy(&held, storage + entry * 16, 8);
        if (held == key) { memcpy(out, storage + entry * 16 + 8, 8); return 1; }
    }
    return 0;
}
#define DEFINE_V2(NAME, KEYOF)                                                                     \
__attribute__((noinline)) static int64_t NAME(const mdict *d, int64_t size, int64_t iterations,   \
                                              int64_t seed, const uint64_t *qk) {                  \
    const uint64_t *slots = d->index.slots;                                                        \
    const unsigned char *storage = d->entries->storage;                                            \
    size_t mask = d->index.capacity - 1;                                                           \
    int64_t checksum = 0, m;                                                                       \
    (void)qk;                                                                                      \
    int bad = __builtin_mul_overflow(size, 2, &m);                                                 \
    for (int64_t batch = 0; batch < iterations; batch++) {                                         \
        int64_t total = 0;                                                                         \
        for (int64_t j = 0; j < size; j++) {                                                       \
            int64_t u, t, idx;                                                                     \
            bad |= __builtin_mul_overflow(j, 17, &u);                                              \
            bad |= __builtin_add_overflow(seed, u, &t);                                            \
            bad |= __builtin_add_overflow(t, batch, &t);                                           \
            idx = floormod(t, m);                                                                  \
            uint64_t key = KEYOF;                                                                  \
            int64_t out = 0;                                                                       \
            int found = probe_plain(slots, mask, storage, key, &out);                              \
            bad |= __builtin_add_overflow(total, found ? out : 17, &total);                        \
        }                                                                                          \
        if (bad) trap("overflow");                                                                 \
        checksum = floormod(checksum + total, MOD);                                                \
    }                                                                                              \
    return checksum;                                                                               \
}
DEFINE_V2(v2, (uint64_t)idx)
DEFINE_V2(v21, qk[idx])

/* ---- v3: + typed int/int dictionary: the probe is inlined into the loop and returns the
 * value in a register (the generic key-kind switch, the out-parameter and the call are
 * gone). Same hash, same slot -> entry layout. */
#define DEFINE_V3(NAME, KEYOF)                                                                     \
__attribute__((noinline)) static int64_t NAME(const mdict *d, int64_t size, int64_t iterations,   \
                                              int64_t seed, const uint64_t *qk) {                  \
    const uint64_t *restrict slots = d->index.slots;                                               \
    const unsigned char *restrict storage = d->entries->storage;                                   \
    size_t mask = d->index.capacity - 1;                                                           \
    int64_t checksum = 0, m;                                                                       \
    (void)qk;                                                                                      \
    int bad = __builtin_mul_overflow(size, 2, &m);                                                 \
    for (int64_t batch = 0; batch < iterations; batch++) {                                         \
        int64_t total = 0;                                                                         \
        for (int64_t j = 0; j < size; j++) {                                                       \
            int64_t u, t, idx;                                                                     \
            bad |= __builtin_mul_overflow(j, 17, &u);                                              \
            bad |= __builtin_add_overflow(seed, u, &t);                                            \
            bad |= __builtin_add_overflow(t, batch, &t);                                           \
            idx = floormod(t, m);                                                                  \
            uint64_t key = KEYOF;                                                                  \
            uint32_t hash = scalar_hash(key);                                                      \
            size_t at = hash & mask;                                                               \
            int64_t value = 17;                                                                    \
            for (uint64_t slot; (slot = slots[at]); at = (at + 1) & mask) {                        \
                if ((uint32_t)(slot >> 32) != hash) continue;                                      \
                size_t entry = (size_t)(slot & 0xffffffffu) - 1;                                   \
                uint64_t held;                                                                     \
                memcpy(&held, storage + entry * 16, 8);                                            \
                if (held == key) { memcpy(&value, storage + entry * 16 + 8, 8); break; }           \
            }                                                                                      \
            bad |= __builtin_add_overflow(total, value, &total);                                   \
        }                                                                                          \
        if (bad) trap("overflow");                                                                 \
        checksum = floormod(checksum + total, MOD);                                                \
    }                                                                                              \
    return checksum;                                                                               \
}
DEFINE_V3(v3, (uint64_t)idx)
DEFINE_V3(v22, qk[idx])

/* ---- v4: + library layout: open addressing with the {key,value} pair stored in the slot
 * itself (16 bytes, load <= 1/2); the insertion-order entry list still exists for iteration
 * but lookups never touch it. One cache line per probe instead of slot + entry, and a
 * one-multiply Fibonacci hash. Not observable: iteration order comes from the entry list. */
typedef struct { uint64_t key, value; } kv_t;
#define EMPTY_KEY (~0ULL)
typedef struct { kv_t *slots; size_t mask; unsigned shift; } kvtab;
static kvtab build_kvtab(const uint64_t *dkeys, const int64_t *values, int64_t size) {
    size_t cap = 8;
    while (cap < (size_t)size * 2) cap *= 2;
    kvtab t = { malloc(cap * sizeof(kv_t)), cap - 1, (unsigned)(64 - __builtin_ctzll(cap)) };
    for (size_t i = 0; i < cap; i++) t.slots[i] = (kv_t){EMPTY_KEY, 0};
    for (int64_t i = 0; i < size; i++) {
        size_t at = (dkeys[i] * 0x9E3779B97F4A7C15ULL) >> t.shift;
        while (t.slots[at].key != EMPTY_KEY) at = (at + 1) & t.mask;
        t.slots[at] = (kv_t){dkeys[i], (uint64_t)values[i]};
    }
    return t;
}
#define DEFINE_V4(NAME, KEYOF)                                                                     \
__attribute__((noinline)) static int64_t NAME(const kvtab *tab, int64_t size, int64_t iterations, \
                                              int64_t seed, const uint64_t *qk) {                  \
    const kv_t *restrict slots = tab->slots;                                                       \
    size_t mask = tab->mask;                                                                       \
    unsigned shift = tab->shift;                                                                   \
    int64_t checksum = 0, m;                                                                       \
    (void)qk;                                                                                      \
    int bad = __builtin_mul_overflow(size, 2, &m);                                                 \
    for (int64_t batch = 0; batch < iterations; batch++) {                                         \
        int64_t total = 0;                                                                         \
        for (int64_t j = 0; j < size; j++) {                                                       \
            int64_t u, t, idx;                                                                     \
            bad |= __builtin_mul_overflow(j, 17, &u);                                              \
            bad |= __builtin_add_overflow(seed, u, &t);                                            \
            bad |= __builtin_add_overflow(t, batch, &t);                                           \
            idx = floormod(t, m);                                                                  \
            uint64_t key = KEYOF;                                                                  \
            size_t at = (key * 0x9E3779B97F4A7C15ULL) >> shift;                                    \
            int64_t value = 17;                                                                    \
            for (;; at = (at + 1) & mask) {                                                        \
                if (slots[at].key == key) { value = (int64_t)slots[at].value; break; }             \
                if (slots[at].key == EMPTY_KEY) break;                                             \
            }                                                                                      \
            bad |= __builtin_add_overflow(total, value, &total);                                   \
        }                                                                                          \
        if (bad) trap("overflow");                                                                 \
        checksum = floormod(checksum + total, MOD);                                                \
    }                                                                                              \
    return checksum;                                                                               \
}
DEFINE_V4(v4, (uint64_t)idx)

/* ---- v10: v4's layout (inline {key,value} slots, load <= 1/2) but with mylang's own hash
 * (fold_multiply of key^MIX with SPREAD, folded to 32 bits, masked): isolates how much of
 * v4's gain comes from the hash function being lucky on sequential keys. */
static kvtab build_kvtab_mix(const uint64_t *dkeys, const int64_t *values, int64_t size) {
    kvtab t = build_kvtab(dkeys, values, size);
    size_t cap = t.mask + 1;
    for (size_t i = 0; i < cap; i++) t.slots[i] = (kv_t){EMPTY_KEY, 0};
    for (int64_t i = 0; i < size; i++) {
        size_t at = scalar_hash(dkeys[i]) & t.mask;
        while (t.slots[at].key != EMPTY_KEY) at = (at + 1) & t.mask;
        t.slots[at] = (kv_t){dkeys[i], (uint64_t)values[i]};
    }
    return t;
}
__attribute__((noinline)) static int64_t v10(const kvtab *tab, int64_t size, int64_t iterations, int64_t seed) {
    const kv_t *restrict slots = tab->slots;
    size_t mask = tab->mask;
    int64_t checksum = 0, m;
    int bad = __builtin_mul_overflow(size, 2, &m);
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t total = 0;
        for (int64_t j = 0; j < size; j++) {
            int64_t u, t, idx;
            bad |= __builtin_mul_overflow(j, 17, &u);
            bad |= __builtin_add_overflow(seed, u, &t);
            bad |= __builtin_add_overflow(t, batch, &t);
            idx = floormod(t, m);
            uint64_t key = (uint64_t)idx;
            size_t at = scalar_hash(key) & mask;
            int64_t value = 17;
            for (;; at = (at + 1) & mask) {
                if (slots[at].key == key) { value = (int64_t)slots[at].value; break; }
                if (slots[at].key == EMPTY_KEY) break;
            }
            bad |= __builtin_add_overflow(total, value, &total);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    return checksum;
}

/* ---- v5: + query-key arithmetic hoisted (L2/range): idx_j = (base + 17 j) mod m is an
 * induction variable: one add and one compare-subtract per query, no division and no
 * overflow flags in the loop (m = 2 size is checked once; seed, batch, j >= 0). The file
 * version v30 is the same loop with key = keys[idx]. */
#define DEFINE_V5(NAME, KEYOF)                                                                     \
__attribute__((noinline)) static int64_t NAME(const kvtab *tab, int64_t size, int64_t iterations, \
                                              int64_t seed, const uint64_t *qk) {                  \
    const kv_t *restrict slots = tab->slots;                                                       \
    size_t mask = tab->mask;                                                                       \
    unsigned shift = tab->shift;                                                                   \
    int64_t checksum = 0, m;                                                                       \
    (void)qk;                                                                                      \
    int bad = __builtin_mul_overflow(size, 2, &m);                                                 \
    int64_t step = 17 % m;                                                                         \
    for (int64_t batch = 0; batch < iterations; batch++) {                                         \
        int64_t base;                                                                              \
        bad |= __builtin_add_overflow(seed, batch, &base);                                         \
        int64_t total = 0;                                                                         \
        int64_t idx = (int64_t)((uint64_t)base % (uint64_t)m);                                     \
        for (int64_t j = 0; j < size; j++) {                                                       \
            uint64_t key = KEYOF;                                                                  \
            size_t at = (key * 0x9E3779B97F4A7C15ULL) >> shift;                                    \
            int64_t value = 17;                                                                    \
            for (;; at = (at + 1) & mask) {                                                        \
                if (slots[at].key == key) { value = (int64_t)slots[at].value; break; }             \
                if (slots[at].key == EMPTY_KEY) break;                                             \
            }                                                                                      \
            bad |= __builtin_add_overflow(total, value, &total);                                   \
            idx += step;                                                                           \
            idx = idx >= m ? idx - m : idx;                                                        \
        }                                                                                          \
        if (bad) trap("overflow");                                                                 \
        checksum = floormod(checksum + total, MOD);                                                \
    }                                                                                              \
    return checksum;                                                                               \
}
DEFINE_V5(v5, (uint64_t)idx)
DEFINE_V5(v30, qk[idx]) /* holdout: the best general scalar table, queries from the file */

/* ---- v6: representation choice that needs no static fact: a dictionary whose keys are
 * exactly 0..n-1 in insertion order (checked as it is built: key == length at every
 * insert) keeps one flag, and a lookup becomes `k < n ? values[k] : miss`. */
__attribute__((noinline)) static int64_t v6(const int64_t *values, int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0, m;
    int bad = __builtin_mul_overflow(size, 2, &m);
    int64_t step = (17 % m);
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t base;
        bad |= __builtin_add_overflow(seed, batch, &base);
        int64_t total = 0;
        uint64_t key = (uint64_t)base % (uint64_t)m;
        for (int64_t j = 0; j < size; j++) {
            int64_t value = key < (uint64_t)size ? values[key] : 17;
            bad |= __builtin_add_overflow(total, value, &total);
            key += (uint64_t)step;
            key = key >= (uint64_t)m ? key - (uint64_t)m : key;
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    return checksum;
}

#ifdef __AVX2__
/* ---- v7: hand AVX2 on the dense representation: eight keys per step (u32 lanes, the
 * induction vector advances by 8*17 mod m), a masked gather of i64 values (two 4-lane
 * gathers), 17 on a miss, a per-lane signed-overflow sticky flag. */
__attribute__((noinline)) static int64_t v7(const int64_t *values, int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0, m;
    int bad = __builtin_mul_overflow(size, 2, &m);
    if (m >= (1LL << 30)) trap("size beyond the u32 key lanes");
    const int64_t step8 = (17 * 8) % m;
    const __m256i vm = _mm256_set1_epi32((int)m), vs = _mm256_set1_epi32((int)size);
    const __m256i vstep8 = _mm256_set1_epi32((int)step8);
    const __m256i seventeen = _mm256_set1_epi64x(17);
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t base;
        bad |= __builtin_add_overflow(seed, batch, &base);
        /* lane i holds key for j = i, i.e. (base + 17 i) mod m; every step adds 17*8 mod m */
        int32_t lane[8];
        for (int i = 0; i < 8; i++) lane[i] = (int32_t)(((uint64_t)base + 17u * (uint64_t)i) % (uint64_t)m);
        __m256i key = _mm256_loadu_si256((const __m256i *)lane);
        __m256i acc0 = _mm256_setzero_si256(), acc1 = _mm256_setzero_si256(), ov = _mm256_setzero_si256();
        int64_t j = 0;
        for (; j + 8 <= size; j += 8) {
            __m256i hit = _mm256_cmpgt_epi32(vs, key); /* key < size (keys are non-negative) */
            __m256i lo = _mm256_cvtepi32_epi64(_mm256_castsi256_si128(key));
            __m256i hi = _mm256_cvtepi32_epi64(_mm256_extracti128_si256(key, 1));
            __m256i mlo = _mm256_cvtepi32_epi64(_mm256_castsi256_si128(hit));
            __m256i mhi = _mm256_cvtepi32_epi64(_mm256_extracti128_si256(hit, 1));
            __m256i v0 = _mm256_mask_i64gather_epi64(seventeen, (const long long *)values, lo, mlo, 8);
            __m256i v1 = _mm256_mask_i64gather_epi64(seventeen, (const long long *)values, hi, mhi, 8);
            __m256i r0 = _mm256_add_epi64(acc0, v0), r1 = _mm256_add_epi64(acc1, v1);
            ov = _mm256_or_si256(ov, _mm256_or_si256(_mm256_and_si256(_mm256_xor_si256(acc0, r0), _mm256_xor_si256(v0, r0)),
                                                     _mm256_and_si256(_mm256_xor_si256(acc1, r1), _mm256_xor_si256(v1, r1))));
            acc0 = r0; acc1 = r1;
            key = _mm256_add_epi32(key, vstep8);
            key = _mm256_sub_epi32(key, _mm256_and_si256(_mm256_cmpgt_epi32(key, _mm256_sub_epi32(vm, _mm256_set1_epi32(1))), vm));
        }
        int64_t total = 0;
        int64_t parts[8];
        _mm256_storeu_si256((__m256i *)parts, acc0);
        _mm256_storeu_si256((__m256i *)(parts + 4), acc1);
        for (int i = 0; i < 8; i++) bad |= __builtin_add_overflow(total, parts[i], &total);
        bad |= _mm256_movemask_pd(_mm256_castsi256_pd(ov)) != 0;
        for (; j < size; j++) {
            uint64_t k = ((uint64_t)base + 17u * (uint64_t)j) % (uint64_t)m;
            bad |= __builtin_add_overflow(total, k < (uint64_t)size ? values[k] : 17, &total);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    return checksum;
}

/* ---- v7n: v7 with u32 value storage (needs the value range, which is not local to this
 * function: the dictionary arrives as a parameter). 8-lane i32 gather, u32 lane sums
 * flushed to a checked 64-bit total every 256 steps. */
__attribute__((noinline)) static int64_t v7n(const uint32_t *values, int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0, m;
    int bad = __builtin_mul_overflow(size, 2, &m);
    if (m >= (1LL << 30)) trap("size beyond the u32 key lanes");
    const int64_t step8 = (17 * 8) % m;
    const __m256i vm = _mm256_set1_epi32((int)m), vs = _mm256_set1_epi32((int)size);
    const __m256i vstep8 = _mm256_set1_epi32((int)step8);
    const __m256i seventeen = _mm256_set1_epi32(17);
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t base;
        bad |= __builtin_add_overflow(seed, batch, &base);
        int32_t lane[8];
        for (int i = 0; i < 8; i++) lane[i] = (int32_t)(((uint64_t)base + 17u * (uint64_t)i) % (uint64_t)m);
        __m256i key = _mm256_loadu_si256((const __m256i *)lane);
        int64_t total = 0, j = 0;
        while (j + 8 <= size) {
            int64_t steps = (size - j) / 8;
            if (steps > 256) steps = 256;
            __m256i acc = _mm256_setzero_si256();
            for (int64_t k = 0; k < steps; k++, j += 8) {
                __m256i hit = _mm256_cmpgt_epi32(vs, key);
                acc = _mm256_add_epi32(acc, _mm256_mask_i32gather_epi32(seventeen, (const int *)values, key, hit, 4));
                key = _mm256_add_epi32(key, vstep8);
                key = _mm256_sub_epi32(key, _mm256_and_si256(_mm256_cmpgt_epi32(key, _mm256_sub_epi32(vm, _mm256_set1_epi32(1))), vm));
            }
            bad |= __builtin_add_overflow(total, (int64_t)hsum_u32x8(acc), &total);
        }
        for (; j < size; j++) {
            uint64_t k = ((uint64_t)base + 17u * (uint64_t)j) % (uint64_t)m;
            bad |= __builtin_add_overflow(total, k < (uint64_t)size ? (int64_t)values[k] : 17, &total);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + total, MOD);
    }
    return checksum;
}

/* ---- v8 / v31: a general table that works for sparse keys, built for a vector unit:
 * 4-slot buckets (one 32-byte key vector, aligned), keys and values in separate arrays,
 * load <= 1/2. A lookup is hash -> bucket, one 256-bit compare, a movemask, a branch-free
 * select of the value; a full bucket without a match (rare) continues to the next. */
typedef struct { uint64_t *keys; int64_t *vals; size_t bmask; unsigned shift; } btab;
static btab build_btab(const uint64_t *dkeys, const int64_t *values, int64_t size) {
    size_t cap = 16;
    while (cap < (size_t)size * 2) cap *= 2;
    btab t;
    t.keys = aligned_alloc(64, cap * 8);
    t.vals = aligned_alloc(64, cap * 8);
    for (size_t i = 0; i < cap; i++) { t.keys[i] = EMPTY_KEY; t.vals[i] = 0; }
    t.bmask = cap / 4 - 1;
    t.shift = (unsigned)(64 - __builtin_ctzll(cap / 4));
    for (int64_t i = 0; i < size; i++) {
        size_t b = (dkeys[i] * 0x9E3779B97F4A7C15ULL) >> t.shift;
        for (;; b = (b + 1) & t.bmask) {
            int placed = 0;
            for (int s = 0; s < 4; s++)
                if (t.keys[b * 4 + s] == EMPTY_KEY) { t.keys[b * 4 + s] = dkeys[i]; t.vals[b * 4 + s] = values[i]; placed = 1; break; }
            if (placed) break;
        }
    }
    return t;
}
#define DEFINE_BUCKET(NAME, KEYOF)                                                                 \
__attribute__((noinline)) static int64_t NAME(const btab *tab, int64_t size, int64_t iterations,  \
                                              int64_t seed, const uint64_t *qk) {                  \
    const uint64_t *restrict keys = tab->keys;                                                     \
    const int64_t *restrict vals = tab->vals;                                                      \
    size_t bmask = tab->bmask;                                                                     \
    unsigned shift = tab->shift;                                                                   \
    int64_t checksum = 0, m;                                                                       \
    (void)qk;                                                                                      \
    int bad = __builtin_mul_overflow(size, 2, &m);                                                 \
    const __m256i vempty = _mm256_set1_epi64x(-1);                                                 \
    for (int64_t batch = 0; batch < iterations; batch++) {                                         \
        int64_t base;                                                                              \
        bad |= __builtin_add_overflow(seed, batch, &base);                                         \
        int64_t total = 0;                                                                         \
        int64_t idx = (int64_t)((uint64_t)base % (uint64_t)m);                                     \
        int64_t step = 17 % m;                                                                     \
        for (int64_t j = 0; j < size; j++) {                                                       \
            uint64_t key = KEYOF;                                                                  \
            size_t b = (key * 0x9E3779B97F4A7C15ULL) >> shift;                                     \
            int64_t value = 17;                                                                    \
            for (;; b = (b + 1) & bmask) {                                                         \
                __m256i kv = _mm256_load_si256((const __m256i *)(keys + b * 4));                   \
                unsigned hit = (unsigned)_mm256_movemask_pd(_mm256_castsi256_pd(_mm256_cmpeq_epi64(kv, _mm256_set1_epi64x((long long)key)))); \
                unsigned any_empty = (unsigned)_mm256_movemask_pd(_mm256_castsi256_pd(_mm256_cmpeq_epi64(kv, vempty))); \
                if (__builtin_expect(hit | any_empty, 1)) {                                        \
                    int64_t cand = vals[b * 4 + (__builtin_ctz(hit | 8u) & 3)];                    \
                    value = hit ? cand : 17;                                                       \
                    break;                                                                         \
                }                                                                                  \
            }                                                                                      \
            bad |= __builtin_add_overflow(total, value, &total);                                   \
            idx += step;                                                                           \
            idx = idx >= m ? idx - m : idx;                                                        \
        }                                                                                          \
        if (bad) trap("overflow");                                                                 \
        checksum = floormod(checksum + total, MOD);                                                \
    }                                                                                              \
    return checksum;                                                                               \
}
#define IDENT_KEY ((uint64_t)idx)
DEFINE_BUCKET(v8, IDENT_KEY)
DEFINE_BUCKET(v31, qk[idx])
#endif /* __AVX2__ */

/* ================================== main ================================================ */
static uint64_t *read_keys(const char *path, int64_t n) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror("fopen"); exit(2); }
    uint64_t *d = malloc(sizeof(uint64_t) * (size_t)n);
    if (fread(d, 8, (size_t)n, f) != (size_t)n) { fprintf(stderr, "short data file\n"); exit(2); }
    fclose(f);
    return d;
}
static uint64_t mix40(uint64_t x) { /* an invertible mixer on 40 bits: distinct inputs give distinct ids */
    const uint64_t M = (1ULL << 40) - 1;
    for (int r = 0; r < 3; r++) { x ^= x >> 19; x = (x * 0x9E3779B97Full) & M; x ^= x >> 23; }
    return x;
}
int main(int argc, char **argv) {
    if (argc == 5 && (!strcmp(argv[1], "gen") || !strcmp(argv[1], "gensparse"))) {
        int64_t size = atoll(argv[2]), seed = atoll(argv[3]);
        int sparse = !strcmp(argv[1], "gensparse");
        FILE *f = fopen(argv[4], "wb");
        for (int64_t i = 0; i < 2 * size; i++) {
            uint64_t k = sparse ? mix40((uint64_t)(i + seed * 7919)) : (uint64_t)i;
            fwrite(&k, 8, 1, f);
        }
        fclose(f);
        return 0;
    }
    if (argc < 5) return 2;
    int which = atoi(argv[1]);
    int64_t size = atoll(argv[2]), iterations = atoll(argv[3]), seed = atoll(argv[4]);
    uint64_t *qkeys = malloc(sizeof(uint64_t) * 2 * (size_t)size);
    if (argc == 6) { free(qkeys); qkeys = read_keys(argv[5], 2 * size); }
    else for (int64_t i = 0; i < 2 * size; i++) qkeys[i] = (uint64_t)i;
    if (which >= 20 && argc != 6) return 2;
    int64_t *values = malloc(sizeof(int64_t) * (size_t)size);
    uint32_t *values32 = malloc(sizeof(uint32_t) * (size_t)size);
    for (int64_t j = 0; j < size; j++) { values[j] = (seed + j * 13) % 1009; values32[j] = (uint32_t)values[j]; }
    mdict *d = build_mdict(qkeys, values, size);
    kvtab kt = build_kvtab(qkeys, values, size);
#ifdef __AVX2__
    btab bt = build_btab(qkeys, values, size);
#endif
    mdict *volatile slot = d;
    int64_t start = now_ns(), checksum = 0;
    switch (which) {
    case 1: checksum = v1(slot, size, iterations, seed, NULL); break;
    case 20: checksum = v20(slot, size, iterations, seed, qkeys); break;
    case 2: checksum = v2(d, size, iterations, seed, NULL); break;
    case 21: checksum = v21(d, size, iterations, seed, qkeys); break;
    case 22: checksum = v22(d, size, iterations, seed, qkeys); break;
    case 3: checksum = v3(d, size, iterations, seed, NULL); break;
    case 4: checksum = v4(&kt, size, iterations, seed, NULL); break;
    case 30: checksum = v30(&kt, size, iterations, seed, qkeys); break;
    case 5: checksum = v5(&kt, size, iterations, seed, NULL); break;
    case 10: { kvtab mt = build_kvtab_mix(qkeys, values, size); start = now_ns(); checksum = v10(&mt, size, iterations, seed); break; }
    case 6: checksum = v6(values, size, iterations, seed); break;
#ifdef __AVX2__
    case 7: checksum = v7(values, size, iterations, seed); break;
    case 9: checksum = v7n(values32, size, iterations, seed); break;
    case 8: checksum = v8(&bt, size, iterations, seed, NULL); break;
    case 31: checksum = v31(&bt, size, iterations, seed, qkeys); break;
#endif
    default: return 2;
    }
    printf("%lld %lld\n", (long long)checksum, (long long)(now_ns() - start));
    return 0;
}
