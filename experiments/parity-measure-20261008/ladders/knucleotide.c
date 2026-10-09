/* PM-3 ladder 3: knucleotide's counting loop (bench/parity/suite/knucleotide.my).
 *
 *   for i in range(len(seq) - k + 1):
 *       key = seq[i:i + k]
 *       counts[key] = counts.get(key, 0) + 1
 *
 * The whole program is transcribed (the sequence, seven passes over k, the
 * sorted report) so every rung prints exactly what the mylang program prints;
 * the passes are the cost. The dictionary is the runtime's: dense entries
 * (key, value) with a stored 64-bit hash per entry, a linear scan while it has at
 * most 8 entries, then a 16-byte SSE2 control-group index (7-bit tags, 32-bit
 * entry numbers) at most half full.
 *
 *   0  what mylang emits today. Per position: myl_core_ir_str_slice (scalar
 *      count of seq by its ASCII flag, two clamps, then str_from: a block from
 *      the small free list, header stores, memcpy, NUL, len, and
 *      core_text_publish, which re-scans the k bytes for ASCII); the dict hash
 *      (myl_core_str_hash: the flag test, myl_core_span_hash, the hash cached in
 *      the header) and its 64-bit mix; one probe (the core already fuses get and
 *      set) whose candidate compare calls myl_core_str_eq (pointer, length,
 *      cached hashes, memcmp); the value incremented with an overflow check; the
 *      slice released (count to zero: back to its free list), or inserted as
 *      the new key.
 *   1  views: the slice is never materialized. The hash is computed on seq's
 *      bytes in place and the candidate is compared with seq's bytes; a key
 *      block is allocated only when a new key is inserted.
 *   2  rung 1 with the key compare inlined for short keys (length, then the
 *      bytes by word), no call.
 *   3  rung 2 with the span hash inlined into the loop (a view's hash is
 *      not a runtime call).
 */
#include <emmintrin.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef RUNG
#define RUNG 0
#endif

typedef struct block { uint32_t count, kind; int64_t len, cap; int64_t reserved; } block;
enum { ASCII = 1u << 8, HASHED = 1u << 9 };
#define DATA(b) ((unsigned char *)(b) + 32)

static __attribute__((noinline, cold, noreturn)) void trap(int code) { fprintf(stderr, "trap %d\n", code); exit(1); }

/* ---- the runtime's small-block allocator ---- */
static void *free_lists[33];
static unsigned char *chunk_next, *chunk_end;
static __attribute__((noinline)) void *small_alloc(uint32_t class) {
    void *b = free_lists[class];
    if (b) { free_lists[class] = *(void **)b; return b; }
    size_t bytes = (size_t)class * 32;
    if ((size_t)(chunk_end - chunk_next) < bytes) { chunk_next = aligned_alloc(32, 1 << 16); chunk_end = chunk_next + (1 << 16); }
    b = chunk_next; chunk_next += bytes; return b;
}
static block *text_new(size_t len) {
    uint32_t class = (uint32_t)((32 + len + 1 + 31) / 32);
    block *t = small_alloc(class);
    t->count = 1; t->kind = 3 | (class << 24); t->len = 0; t->reserved = 0; t->cap = (int64_t)len;
    return t;
}
static inline void free_small(block *b) { uint32_t class = b->kind >> 24; *(void **)b = free_lists[class]; free_lists[class] = b; }

static __attribute__((noinline)) bool text_ascii(const unsigned char *p, uint64_t n) {
    for (uint64_t i = 0; i < n; i++) if (p[i] & 0x80) return false;
    return true;
}
static __attribute__((noinline)) block *str_from(const unsigned char *bytes, size_t len) {
    block *t = text_new(len);
    memcpy(DATA(t), bytes, len);
    DATA(t)[len] = 0;
    t->len = (int64_t)len;
    t->kind &= ~(ASCII | HASHED); t->reserved = 0;
    if (text_ascii(DATA(t), (uint64_t)len)) t->kind |= ASCII;
    return t;
}
static inline int64_t clamp(int64_t i, int64_t n) { if (i < 0) { i += n; if (i < 0) i = 0; } return i > n ? n : i; }
static __attribute__((noinline)) block *str_slice(block *text, int64_t start, int64_t end) {
    int64_t n = (text->kind & ASCII) ? text->len : (trap(7), 0);
    start = clamp(start, n); end = clamp(end, n);
    uint64_t a = (uint64_t)start, b = a;
    if (end > start) b = (uint64_t)end;
    return str_from(DATA(text) + a, (size_t)(b - a));
}

/* ---- the runtime's hash ---- */
static inline uint64_t fold(uint64_t a, uint64_t b) { __uint128_t p = (__uint128_t)a * b; return (uint64_t)p ^ (uint64_t)(p >> 64); }
static
#if RUNG < 3
__attribute__((noinline))
#endif
uint32_t span_hash(const unsigned char *bytes, uint64_t length) {
    size_t len = (size_t)length;
    const uint64_t wk = UINT64_C(0xa0761d6478bd642f), sk = UINT64_C(0xe7037ed1a0b428db);
    uint64_t state = UINT64_C(0x243f6a8885a308d3) ^ len, hash;
    if (len <= 8) {
        uint64_t low = 0, high = 0;
        if (len >= 4) { uint32_t f, l; memcpy(&f, bytes, 4); memcpy(&l, bytes + len - 4, 4); low = f; high = l; }
        else if (len) low = (uint64_t)bytes[0] << 16 | (uint64_t)bytes[len >> 1] << 8 | bytes[len - 1];
        hash = fold(low ^ wk, high ^ state ^ sk);
    } else {
        uint64_t word;
        for (size_t at = 0; at + 8 < len; at += 8) { memcpy(&word, bytes + at, 8); state = fold(word ^ wk, state ^ sk); }
        memcpy(&word, bytes + len - 8, 8);
        hash = fold(word ^ wk, state ^ sk);
    }
    return (uint32_t)(hash ^ (hash >> 32));
}
static __attribute__((noinline)) uint32_t str_hash(block *t) {
    if (t->kind & HASHED) return (uint32_t)t->reserved;
    uint32_t h = span_hash(DATA(t), (uint64_t)t->len);
    t->reserved = (int64_t)(((uint64_t)t->reserved & UINT64_C(0xffffffff00000000)) | h);
    t->kind |= HASHED;
    return h;
}
static inline uint64_t mix(uint64_t bits) { uint64_t m = bits * UINT64_C(0x9e3779b97f4a7c15); return m ^ (m >> 32); }
static __attribute__((noinline)) bool str_eq(const block *a, const block *b) {
    if (a == b) return true;
    if (a->len != b->len) return false;
    if ((a->kind & b->kind & HASHED) && (uint32_t)a->reserved != (uint32_t)b->reserved) return false;
    return memcmp(DATA(a), DATA(b), (size_t)a->len) == 0;
}
static inline bool span_eq(const block *key, const unsigned char *bytes, int64_t len) {
#if RUNG >= 2
    if (key->len != len) return false;
    const unsigned char *p = DATA(key);
    int64_t i = 0;
    for (; i + 8 <= len; i += 8) { uint64_t x, y; memcpy(&x, p + i, 8); memcpy(&y, bytes + i, 8); if (x != y) return false; }
    for (; i < len; i++) if (p[i] != bytes[i]) return false;
    return true;
#else
    return key->len == len && memcmp(DATA(key), bytes, (size_t)len) == 0;
#endif
}

/* ---- the runtime's dictionary (str -> int) ---- */
typedef struct entry { block *key; int64_t value; } entry;
typedef struct dict { entry *entries; uint64_t *hashes; uint64_t elen, ecap; uint32_t slots; unsigned char *control; uint32_t *numbers; } dict;

static void rebuild(dict *d, uint32_t slots) {
    free(d->control); free(d->numbers);
    d->slots = slots;
    d->control = malloc(slots + 16); memset(d->control, 0x80, slots + 16);
    d->numbers = malloc(sizeof(uint32_t) * slots);
    int lg = __builtin_ctz(slots);
    for (uint64_t e = 0; e < d->elen; e++) {
        uint64_t h = d->hashes[e];
        uint32_t pos = (uint32_t)(h >> (64 - lg)), step = 0, mask = slots - 1;
        for (;;) {
            __m128i c = _mm_loadu_si128((const __m128i *)(d->control + pos));
            unsigned holes = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(c, _mm_set1_epi8((char)0x80)));
            if (holes) {
                uint32_t s = (pos + (unsigned)__builtin_ctz(holes)) & mask;
                d->control[s] = (unsigned char)(h & 0x7f); if (s < 16) d->control[slots + s] = (unsigned char)(h & 0x7f);
                d->numbers[s] = (uint32_t)e; break;
            }
            step += 16; pos = (pos + step) & mask;
        }
    }
}
/* Entry number, or -(slot + 1) of the hole a new key goes in (-1: small, append). */
static inline int64_t find(dict *d, uint64_t h, block *key, const unsigned char *bytes, int64_t len) {
    if (!d->control) {
        for (uint64_t i = 0; i < d->elen; i++)
            if (d->hashes[i] == h && (key ? str_eq(d->entries[i].key, key) : span_eq(d->entries[i].key, bytes, len))) return (int64_t)i;
        return -1;
    }
    int lg = __builtin_ctz(d->slots);
    uint32_t pos = (uint32_t)(h >> (64 - lg)), step = 0, mask = d->slots - 1;
    __m128i tags = _mm_set1_epi8((char)(h & 0x7f));
    for (;;) {
        __m128i c = _mm_loadu_si128((const __m128i *)(d->control + pos));
        unsigned m = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(c, tags));
        while (m) {
            uint32_t s = (pos + (unsigned)__builtin_ctz(m)) & mask;
            uint32_t e = d->numbers[s];
            if (key ? str_eq(d->entries[e].key, key) : span_eq(d->entries[e].key, bytes, len)) return e;
            m &= m - 1;
        }
        unsigned holes = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(c, _mm_set1_epi8((char)0x80)));
        if (holes) return -(int64_t)(((pos + (unsigned)__builtin_ctz(holes)) & mask) + 1);
        step += 16; pos = (pos + step) & mask;
    }
}
static __attribute__((noinline)) void insert(dict *d, int64_t probe, uint64_t h, block *key, int64_t value) {
    if (d->elen == d->ecap) {
        d->ecap = d->ecap ? d->ecap * 2 : 8;
        d->entries = realloc(d->entries, d->ecap * sizeof(entry));
        d->hashes = realloc(d->hashes, d->ecap * sizeof(uint64_t));
    }
    uint64_t e = d->elen++;
    d->entries[e] = (entry){ key, value }; d->hashes[e] = h;
    if (!d->control) { if (d->elen > 8) rebuild(d, 32); return; }
    if (d->elen * 2 > d->slots) { rebuild(d, d->slots * 2); return; }
    uint32_t s = (uint32_t)(-probe - 1);
    d->control[s] = (unsigned char)(h & 0x7f); if (s < 16) d->control[d->slots + s] = (unsigned char)(h & 0x7f);
    d->numbers[s] = (uint32_t)e;
}

static dict *frequencies(block *seq, int64_t k) {
    dict *d = calloc(1, sizeof *d);
    int64_t n = seq->len - k + 1;
    for (int64_t i = 0; i < n; i++) {
#if RUNG == 0
        block *key = str_slice(seq, i, i + k);
        uint64_t h = mix(str_hash(key));
        int64_t at = find(d, h, key, NULL, 0);
        if (at >= 0) {
            if (__builtin_add_overflow(d->entries[at].value, 1, &d->entries[at].value)) trap(0);
            if (--key->count == 0) free_small(key);
        } else {
            insert(d, at, h, key, 1);
        }
#else
        const unsigned char *bytes = DATA(seq) + i;
        uint64_t h = mix(span_hash(bytes, (uint64_t)k));
        int64_t at = find(d, h, NULL, bytes, k);
        if (at >= 0) {
            if (__builtin_add_overflow(d->entries[at].value, 1, &d->entries[at].value)) trap(0);
        } else {
            insert(d, at, h, str_from(bytes, (size_t)k), 1);
        }
#endif
    }
    return d;
}

static dict *sorting;
static int by_key(const void *a, const void *b) {
    const entry *x = &sorting->entries[*(const uint32_t *)a], *y = &sorting->entries[*(const uint32_t *)b];
    int64_t n = x->key->len < y->key->len ? x->key->len : y->key->len;
    int c = memcmp(DATA(x->key), DATA(y->key), (size_t)n);
    if (c) return c;
    return (x->key->len > y->key->len) - (x->key->len < y->key->len);
}

int main(void) {
    int64_t length = 1000000, seed = 42;
    block *seq = malloc(32 + (size_t)length + 1);
    seq->count = 1; seq->kind = 3 | ASCII; seq->reserved = 0; seq->len = length; seq->cap = length;
    for (int64_t i = 0; i < length; i++) { seed = (seed * 3877 + 29573) % 139968; DATA(seq)[i] = (unsigned char)"ACGT"[seed * 4 / 139968]; }
    for (int64_t k = 1; k <= 2; k++) {
        dict *d = frequencies(seq, k);
        uint32_t *order = malloc(d->elen * sizeof *order);
        for (uint32_t i = 0; i < d->elen; i++) order[i] = i;
        sorting = d;
        qsort(order, d->elen, sizeof *order, by_key);
        /* stable by count descending */
        for (uint64_t i = 1; i < d->elen; i++) {
            uint32_t v = order[i]; uint64_t j = i;
            while (j > 0 && d->entries[order[j - 1]].value < d->entries[v].value) { order[j] = order[j - 1]; j--; }
            order[j] = v;
        }
        for (uint64_t i = 0; i < d->elen; i++) printf("%.*s %lld\n", (int)d->entries[order[i]].key->len, DATA(d->entries[order[i]].key), (long long)d->entries[order[i]].value);
    }
    const char *keys[] = { "GGT", "GGTA", "GGTATT", "GGTATTTTAATT", "GGTATTTTAATTTATAGT" };
    for (int q = 0; q < 5; q++) {
        int64_t k = (int64_t)strlen(keys[q]);
        dict *d = frequencies(seq, k);
        uint64_t h = mix(span_hash((const unsigned char *)keys[q], (uint64_t)k));
        int64_t at = find(d, h, NULL, (const unsigned char *)keys[q], k);
        printf("%lld\t%s\n", (long long)(at >= 0 ? d->entries[at].value : 0), keys[q]);
    }
    return 0;
}
