/* Shared pieces of the S2 dictionary-layout microbenchmark: string blocks in the
   new core's header shape, the hash functions, and the allocator wrappers.
   Exploratory code for docs/design/new-core-s2.md §2; not part of the compiler. */
#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

/* The new core's block header (core_rt.c): {u32 count, u32 kind, i64 len, i64 cap,
   i64 reserved}. A str keeps its cached hash in `reserved` (0 = not computed yet). */
typedef struct Str {
    uint32_t count, kind;
    int64_t len, cap;
    uint64_t hash;
    unsigned char data[];
} Str;

static inline uint64_t rotl64(uint64_t x, int r) { return (x << r) | (x >> (64 - r)); }

/* Integer hash: one multiply plus a fold of the high half into the low half (the
   table takes the TOP bits, so sequential keys spread; no fixture luck). */
static inline uint64_t hash_int(int64_t k) {
    uint64_t x = (uint64_t)k * 0x9E3779B97F4A7C15ull;
    return x ^ (x >> 32);
}

/* FNV-1a over the bytes (byte at a time) -- the shape of a classic text hash. */
static inline uint64_t hash_bytes_fnv(const unsigned char *p, int64_t n) {
    uint64_t h = 0xcbf29ce484222325ull;
    for (int64_t i = 0; i < n; ++i) { h ^= p[i]; h *= 0x100000001b3ull; }
    return h;
}

static inline uint64_t load_le(const unsigned char *p, int64_t n) {
    uint64_t v = 0;
    memcpy(&v, p, (size_t)n);
    return v;
}

/* Word-at-a-time multiply-xorshift hash (wyhash-like mixing, no seed): 8 bytes per
   step, a 1-7 byte tail read once, length folded in. */
static inline uint64_t mix64(uint64_t a, uint64_t b) {
    __uint128_t r = (__uint128_t)a * b;
    return (uint64_t)r ^ (uint64_t)(r >> 64);
}
static inline uint64_t hash_bytes_wide(const unsigned char *p, int64_t n) {
    uint64_t h = 0x243F6A8885A308D3ull ^ (uint64_t)n;
    int64_t i = 0;
    for (; i + 8 <= n; i += 8) h = mix64(h ^ load_le(p + i, 8), 0x9E3779B97F4A7C15ull);
    if (i < n) h = mix64(h ^ load_le(p + i, n - i), 0xBF58476D1CE4E5B9ull);
    return mix64(h, 0x94D049BB133111EBull);
}

#ifndef STR_HASH
#define STR_HASH hash_bytes_wide
#endif

static inline uint64_t str_hash(Str *s) {
    uint64_t h = s->hash;
    if (__builtin_expect(h == 0, 0)) {
        h = STR_HASH(s->data, s->len) | 1; /* never 0: 0 means "not cached" */
        s->hash = h;
    }
    return h;
}

/* A borrowed view key (word_count's split pieces): hashed on every lookup. */
static inline bool str_eq(const Str *a, const Str *b) {
    if (a == b) return true;
    if (a->len != b->len) return false;
    if (a->hash && b->hash && a->hash != b->hash) return false;
    return memcmp(a->data, b->data, (size_t)a->len) == 0;
}

static Str *str_new(const char *text, int64_t n) {
    Str *s = aligned_alloc(32, (size_t)(32 + ((n + 32) & ~31)));
    s->count = 1; s->kind = 1; s->len = n; s->cap = n; s->hash = 0;
    memcpy(s->data, text, (size_t)n);
    s->data[n] = 0;
    return s;
}

static inline void *xcalloc(size_t n, size_t size) {
    void *p = calloc(n, size);
    if (!p) abort();
    return p;
}
