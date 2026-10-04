// string_split ladder. Re-implements the `string_split` case of
// benchmarks/runtime/expanded/text/main.my (CONTRACT.md "string_split/string_join"):
//   untimed: fragments[j] = ["", "alpha", "café", "x", "naïve"][(seed + j) % 5], j < size
//            texts = ["|".join(fragments), "::".join(fragments)]
//   for step in range(iterations):                       # one iteration = one split_job
//       cursor = seed + step
//       parts  = texts[cursor % 2].split("|" if cursor % 2 == 0 else "::")
//       value  = 7 * len(parts) + sum(score(p) for p in parts)    # score = len(utf8) + sum(utf8 bytes)
//       checksum = (checksum + value) % 1000000007
// Usage: string_split VERSION SIZE ITERATIONS SEED [DOCFILE for versions >= 30]
//   DOCFILE: the two documents, each as a u64 byte length followed by the bytes, then one
//   separator per document (u64 length + bytes); the holdout reads them instead of building them.
// Prints "checksum elapsed_ns". Build with -fno-strict-aliasing.
#include "common.h"

/* ------------------------------------------------------------------------------
 * mylang's runtime objects, modelled with glibc malloc (src/native_text.h, native_bytes.h):
 *  - a `str` is a 24-byte header {length in scalars, byte count, flags, hash} followed by its UTF-8
 *    payload in one block, behind a 16-byte RC object header {refcount, flags};
 *  - a piece shorter than MYL_TEXT_VIEW_MIN (9) octets is copied into a new text;
 *  - `bytes` is a list-like object (header + a separate storage block) built by `encode()`;
 *  - `list[str]` is {len, cap, gen, elem, data} with doubling growth, and releasing it releases every
 *    element through a deferred drain queue (myl_rc_drain / drain_one in the B0 profile).
 */
typedef struct { uint64_t refcount, flags; } rc_head;
typedef struct { size_t length, bytes; uint32_t flags, hash; } text_head; /* payload follows */
typedef struct { rc_head rc; text_head head; } text_obj;                  /* payload follows */
typedef struct { int64_t len, cap, gen; const void *elem; unsigned char *data; } bytes_head;
typedef struct { rc_head rc; bytes_head head; } bytes_obj;
typedef struct { int64_t len, cap, gen; const void *elem; text_obj **data; } plist;
typedef struct { rc_head rc; plist head; } plist_obj;

static const void *g_elem_type = &g_elem_type;
/* the deferred release queue: dead objects are pushed here and freed by drain() */
static void *g_dead[1 << 16];
static size_t g_dead_n;
static void drain(void) {
    while (g_dead_n) free(g_dead[--g_dead_n]);
}
static inline void release_obj(void *obj, rc_head *rc) {
    if (--rc->refcount == 0) {
        if (g_dead_n == (1 << 16)) drain();
        g_dead[g_dead_n++] = obj;
    }
}

static inline unsigned char *text_payload(text_obj *t) { return (unsigned char *)(t + 1); }
static text_obj *new_text(const unsigned char *src, size_t n) {
    text_obj *t = malloc(sizeof *t + n + 1);
    t->rc.refcount = 1; t->rc.flags = 0;
    memcpy(text_payload(t), src, n);
    size_t scalars = 0;
    uint32_t ascii = 1;
    for (size_t i = 0; i < n; i++) { scalars += (src[i] & 0xC0) != 0x80; ascii &= src[i] < 0x80; }
    t->head.length = scalars; t->head.bytes = n; t->head.flags = ascii; t->head.hash = 0;
    return t;
}
/* myl_native_octets_find: leftmost occurrence of `needle` in hay[from..n), or -1 */
static int64_t octets_find(const unsigned char *hay, size_t n, size_t from, const unsigned char *needle, size_t k) {
    if (k == 1) {
        const unsigned char *p = memchr(hay + from, needle[0], n - from);
        return p ? (int64_t)(p - hay) : -1;
    }
    for (size_t i = from; i + k <= n; i++) {
        const unsigned char *p = memchr(hay + i, needle[0], n - i);
        if (!p) return -1;
        i = (size_t)(p - hay);
        if (i + k <= n && memcmp(hay + i, needle, k) == 0) return (int64_t)i;
    }
    return -1;
}

static void plist_append(plist_obj *l, text_obj *piece) {
    if (l->head.len >= l->head.cap) {
        int64_t cap = l->head.cap < 4 ? 4 : l->head.cap * 2;
        l->head.data = realloc(l->head.data, (size_t)cap * sizeof(text_obj *));
        l->head.cap = cap;
    }
    piece->rc.refcount++;               /* the list retains the element ... */
    l->head.data[l->head.len++] = piece;
    l->head.gen++;
    release_obj(piece, &piece->rc);     /* ... and the local reference ends */
}
/* myl_native_text_split */
__attribute__((noinline)) static plist_obj *text_split(text_obj *doc, text_obj *sep) {
    plist_obj *out = calloc(1, sizeof *out);
    out->rc.refcount = 1; out->head.elem = g_elem_type;
    const unsigned char *d = text_payload(doc), *s = text_payload(sep);
    size_t n = doc->head.bytes, k = sep->head.bytes, at = 0;
    for (;;) {
        int64_t hit = octets_find(d, n, at, s, k);
        size_t end = hit < 0 ? n : (size_t)hit;
        plist_append(out, new_text(d + at, end - at));
        if (hit < 0) break;
        at = end + k;
    }
    return out;
}
static void plist_release(plist_obj *l) {
    if (--l->rc.refcount) return;
    for (int64_t i = 0; i < l->head.len; i++) release_obj(l->head.data[i], &l->head.data[i]->rc);
    free(l->head.data);
    drain();
    free(l);
}
/* text.encode(): a fresh bytes object with its own storage */
static bytes_obj *text_encode(const text_obj *t) {
    bytes_obj *b = malloc(sizeof *b);
    b->rc.refcount = 1; b->rc.flags = 0;
    b->head.len = b->head.cap = (int64_t)t->head.bytes; b->head.gen = 0; b->head.elem = g_elem_type;
    b->head.data = malloc(t->head.bytes ? t->head.bytes : 1);
    memcpy(b->head.data, (const unsigned char *)(t + 1), t->head.bytes);
    return b;
}
__attribute__((noinline)) static int64_t score_text(const text_obj *t) {
    bytes_obj *raw = text_encode(t);
    int64_t result = raw->head.len;
    for (int64_t i = 0; i < raw->head.len; i++) {
        if (__builtin_add_overflow(result, raw->head.data[i], &result)) trap("overflow");
    }
    free(raw->head.data);
    free(raw);
    return result;
}

/* ---- v1: today. split() builds a list[str] of owned pieces; each score() encodes the piece into a
 * fresh bytes object and sums it with checked adds; the list and every piece are released through the
 * RC drain queue at the end of split_job. */
__attribute__((noinline)) static int64_t v1(text_obj *const *texts, text_obj *const *seps, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    for (int64_t step = 0; step < iterations; step++) {
        int64_t cursor = seed + step;
        int which = (int)(cursor % 2);
        plist_obj *parts = text_split(texts[which], seps[which]);
        int64_t result = parts->head.len * 7;
        for (int64_t i = 0; i < parts->head.len; i++) {
            int64_t sc = score_text(parts->head.data[i]);
            if (__builtin_add_overflow(result, sc, &result)) trap("overflow");
        }
        plist_release(parts);
        checksum = floormod(checksum + result, MOD);
    }
    return checksum;
}

/* ---- v2: + RC and allocator facts (value semantics + L3): the pieces, the list and the encode buffers
 * never escape split_job and are immutable, so there are no refcounts, no deferred drain and no per-object
 * malloc: everything comes from a bump region reset at the end of each job (allocation is unobservable).
 * Still one copied piece and one encoded copy per part. */
typedef struct { const unsigned char *ptr; size_t len; } span;
typedef struct { unsigned char *base; size_t used, cap; } region;
static inline void *region_alloc(region *r, size_t n) {
    n = (n + 15) & ~(size_t)15;
    if (r->used + n > r->cap) trap("region exhausted");
    void *p = r->base + r->used;
    r->used += n;
    return p;
}
/* one region big enough for any job over these documents: spans + copied pieces + encode copies */
static region region_for(const size_t *dlen, const size_t *slen) {
    size_t need = 0;
    for (int w = 0; w < 2; w++) {
        size_t parts = dlen[w] / (slen[w] ? slen[w] : 1) + 2;
        size_t one = parts * (sizeof(span) + 3 * 16) + 3 * dlen[w] + 256;
        if (one > need) need = one;
    }
    return (region){malloc(need), 0, need};
}

__attribute__((noinline)) static int64_t v2(const unsigned char *const *docs, const size_t *dlen,
                                            const unsigned char *const *seps, const size_t *slen,
                                            int64_t iterations, int64_t seed) {
    region reg = region_for(dlen, slen);
    int64_t checksum = 0;
    for (int64_t step = 0; step < iterations; step++) {
        int which = (int)((seed + step) % 2);
        const unsigned char *d = docs[which], *s = seps[which];
        size_t n = dlen[which], k = slen[which], at = 0;
        reg.used = 0;
        span *parts = region_alloc(&reg, sizeof(span) * (n / (k ? k : 1) + 2));
        int64_t cnt = 0;
        for (;;) {
            int64_t hit = octets_find(d, n, at, s, k);
            size_t end = hit < 0 ? n : (size_t)hit;
            unsigned char *copy = region_alloc(&reg, end - at + 1);
            memcpy(copy, d + at, end - at);
            parts[cnt++] = (span){copy, end - at};
            if (hit < 0) break;
            at = end + k;
        }
        int bad = 0;
        int64_t result = cnt * 7;
        for (int64_t i = 0; i < cnt; i++) {
            unsigned char *raw = region_alloc(&reg, parts[i].len + 1); /* encode() copy */
            memcpy(raw, parts[i].ptr, parts[i].len);
            int64_t sc = (int64_t)parts[i].len;
            for (size_t b = 0; b < parts[i].len; b++) bad |= __builtin_add_overflow(sc, raw[b], &sc);
            bad |= __builtin_add_overflow(result, sc, &result);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + result, MOD);
    }
    free(reg.base);
    return checksum;
}

/* ---- v3: + borrowed encode: score() only reads the encoded bytes and they do not escape, so encode()
 * is a view of the piece's own UTF-8 payload (L3 plus a lifetime proof; the plan's WP-4 step 6). */
__attribute__((noinline)) static int64_t v3(const unsigned char *const *docs, const size_t *dlen,
                                            const unsigned char *const *seps, const size_t *slen,
                                            int64_t iterations, int64_t seed) {
    region reg = region_for(dlen, slen);
    int64_t checksum = 0;
    for (int64_t step = 0; step < iterations; step++) {
        int which = (int)((seed + step) % 2);
        const unsigned char *d = docs[which], *s = seps[which];
        size_t n = dlen[which], k = slen[which], at = 0;
        reg.used = 0;
        span *parts = region_alloc(&reg, sizeof(span) * (n / (k ? k : 1) + 2));
        int64_t cnt = 0;
        for (;;) {
            int64_t hit = octets_find(d, n, at, s, k);
            size_t end = hit < 0 ? n : (size_t)hit;
            unsigned char *copy = region_alloc(&reg, end - at + 1);
            memcpy(copy, d + at, end - at);
            parts[cnt++] = (span){copy, end - at};
            if (hit < 0) break;
            at = end + k;
        }
        int bad = 0;
        int64_t result = cnt * 7;
        for (int64_t i = 0; i < cnt; i++) {
            int64_t sc = (int64_t)parts[i].len;
            for (size_t b = 0; b < parts[i].len; b++) bad |= __builtin_add_overflow(sc, parts[i].ptr[b], &sc);
            bad |= __builtin_add_overflow(result, sc, &result);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + result, MOD);
    }
    free(reg.base);
    return checksum;
}

/* ---- v4: + pieces as views: a non-escaping piece never needs its own bytes, so split() yields
 * (pointer, length) spans into the document: no copy and no per-piece allocation (the 9-octet copy
 * rule exists to stop a retained short piece from pinning a large owner; nothing is retained here). */
__attribute__((noinline)) static int64_t v4(const unsigned char *const *docs, const size_t *dlen,
                                            const unsigned char *const *seps, const size_t *slen,
                                            int64_t iterations, int64_t seed) {
    span *parts = NULL;
    size_t pcap = 0;
    int64_t checksum = 0;
    for (int64_t step = 0; step < iterations; step++) {
        int which = (int)((seed + step) % 2);
        const unsigned char *d = docs[which], *s = seps[which];
        size_t n = dlen[which], k = slen[which], at = 0;
        size_t need = n / (k ? k : 1) + 2;
        if (need > pcap) { pcap = need * 2; parts = realloc(parts, pcap * sizeof(span)); }
        int64_t cnt = 0;
        for (;;) {
            int64_t hit = octets_find(d, n, at, s, k);
            size_t end = hit < 0 ? n : (size_t)hit;
            parts[cnt++] = (span){d + at, end - at};
            if (hit < 0) break;
            at = end + k;
        }
        int bad = 0;
        int64_t result = cnt * 7;
        for (int64_t i = 0; i < cnt; i++) {
            int64_t sc = (int64_t)parts[i].len;
            for (size_t b = 0; b < parts[i].len; b++) bad |= __builtin_add_overflow(sc, parts[i].ptr[b], &sc);
            bad |= __builtin_add_overflow(result, sc, &result);
        }
        if (bad) trap("overflow");
        checksum = floormod(checksum + result, MOD);
    }
    free(parts);
    return checksum;
}

/* ---- v5: + loop fusion: the list of parts is consumed once by a reduction, so split() becomes a
 * generator feeding score(): no span array, one pass (what Rust's lazy iterator already does). */
__attribute__((noinline)) static int64_t v5(const unsigned char *const *docs, const size_t *dlen,
                                            const unsigned char *const *seps, const size_t *slen,
                                            int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    for (int64_t step = 0; step < iterations; step++) {
        int which = (int)((seed + step) % 2);
        const unsigned char *d = docs[which], *s = seps[which];
        size_t n = dlen[which], k = slen[which], at = 0;
        int bad = 0;
        int64_t cnt = 0, total = 0;
        for (;;) {
            int64_t hit = octets_find(d, n, at, s, k);
            size_t end = hit < 0 ? n : (size_t)hit;
            int64_t sc = (int64_t)(end - at);
            for (size_t b = at; b < end; b++) bad |= __builtin_add_overflow(sc, d[b], &sc);
            bad |= __builtin_add_overflow(total, sc, &total);
            cnt++;
            if (hit < 0) break;
            at = end + k;
        }
        int64_t result;
        bad |= __builtin_mul_overflow(cnt, 7, &result);
        bad |= __builtin_add_overflow(result, total, &result);
        if (bad) trap("overflow");
        checksum = floormod(checksum + result, MOD);
    }
    return checksum;
}

/* ---- v6: + a single-pass scalar scanner: the generator and the byte loop are one loop over the document
 * with a tiny state machine (single-byte and two-byte separators; any other separator uses v5's
 * search). Byte values are known to be <= 255, so sums are accumulated unchecked in a u64 (n * 255 cannot
 * overflow for any document that fits in memory) and totals are tested once per job. */
static inline int64_t scan_scalar(const unsigned char *d, size_t n, const unsigned char *s, size_t k, int64_t *cnt_out) {
    uint64_t sum = 0, seps = 0;
    if (k == 1) {
        unsigned char c = s[0];
        for (size_t i = 0; i < n; i++) {
            unsigned char b = d[i];
            seps += b == c;
            sum += b == c ? 0 : b;
        }
    } else { /* k == 2: leftmost non-overlapping, one pass */
        unsigned char c0 = s[0], c1 = s[1];
        size_t i = 0;
        while (i < n) {
            if (d[i] == c0 && i + 1 < n && d[i + 1] == c1) { seps++; i += 2; }
            else { sum += d[i]; i++; }
        }
    }
    *cnt_out = (int64_t)seps + 1;
    return (int64_t)sum; /* byte sum of the non-separator content */
}
__attribute__((noinline)) static int64_t v6(const unsigned char *const *docs, const size_t *dlen,
                                            const unsigned char *const *seps, const size_t *slen,
                                            int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    for (int64_t step = 0; step < iterations; step++) {
        int which = (int)((seed + step) % 2);
        size_t n = dlen[which], k = slen[which];
        if (k > 2) return v5(docs, dlen, seps, slen, iterations, seed); /* only for step 0; exact either way */
        int64_t cnt;
        int64_t nonsep_sum = scan_scalar(docs[which], n, seps[which], k, &cnt);
        /* parts = cnt; sum of lengths of the parts = n - (cnt-1)*k */
        int64_t lens = (int64_t)n - (cnt - 1) * (int64_t)k;
        int64_t result = cnt * 7 + lens + nonsep_sum;
        checksum = floormod(checksum + result, MOD);
    }
    return checksum;
}

/* ---- v9: the byte-level fusion of v5 WITHOUT the algebraic identity: one pass over the document with a
 * small matcher state (single-byte separator, or the leftmost non-overlapping two-byte separator with
 * one pending character); the per-part length and byte sum are accumulated per part and folded into the
 * job total at each separator, exactly the loops of v5 merged byte by byte (what perfect fusion of the
 * generator and the consumer yields once the search is specialised to the separator length). */
__attribute__((noinline)) static int64_t v9(const unsigned char *const *docs, const size_t *dlen,
                                            const unsigned char *const *seps, const size_t *slen,
                                            int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    for (int64_t step = 0; step < iterations; step++) {
        int which = (int)((seed + step) % 2);
        const unsigned char *d = docs[which], *s = seps[which];
        size_t n = dlen[which], k = slen[which];
        if (k > 2) return v5(docs, dlen, seps, slen, iterations, seed);
        uint64_t total = 0, cnt = 1, len = 0, psum = 0;
        if (k == 1) {
            unsigned char c = s[0];
            for (size_t i = 0; i < n; i++) {
                unsigned char b = d[i];
                if (b == c) { total += len + psum; cnt++; len = 0; psum = 0; }
                else { len++; psum += b; }
            }
        } else {
            unsigned char c0 = s[0], c1 = s[1];
            int pending = 0;
            for (size_t i = 0; i < n; i++) {
                unsigned char b = d[i];
                if (pending) {
                    pending = 0;
                    if (b == c1) { total += len + psum; cnt++; len = 0; psum = 0; continue; }
                    len++; psum += c0; /* the pending character was content */
                }
                if (b == c0) pending = 1;
                else { len++; psum += b; }
            }
            if (pending) { len++; psum += c0; }
        }
        total += len + psum;
        int64_t result = (int64_t)(cnt * 7 + total);
        checksum = floormod(checksum + result, MOD);
    }
    return checksum;
}

#ifdef __AVX2__
/* ---- v7: hand AVX2. Same identity as v6 (parts = separators + 1; sum of part lengths = n - separators*k;
 * sum of part bytes = document byte sum - separators * separator byte sum) but the single pass is
 * 32-byte vectors: vpsadbw for the byte sum, vpcmpeqb + popcnt for the separators. A two-byte separator
 * of two equal characters ("::") pairs up non-overlapping inside runs; the vector path handles runs of
 * length 1 and 2 (the mask-and-shift pair test) and any longer run, or a block-crossing pair that cannot
 * be decided locally, sends the document to the exact scalar scan. */
/* Returns the byte sum of the NON-separator content and the separator count, or -1 when the document
 * needs the exact scalar scan (a run of three or more separator characters for "cc"). */
static int64_t scan_avx2(const unsigned char *d, size_t n, const unsigned char *s, size_t k, int64_t *cnt_out) {
    __m256i acc = _mm256_setzero_si256();
    uint64_t seps = 0;
    size_t i = 0;
    const __m256i zero = _mm256_setzero_si256();
    if (k == 1) {
        const __m256i c = _mm256_set1_epi8((char)s[0]);
        for (; i + 64 <= n; i += 64) {
            __m256i a = _mm256_loadu_si256((const __m256i *)(d + i)), b = _mm256_loadu_si256((const __m256i *)(d + i + 32));
            acc = _mm256_add_epi64(acc, _mm256_add_epi64(_mm256_sad_epu8(a, zero), _mm256_sad_epu8(b, zero)));
            uint64_t m = (uint32_t)_mm256_movemask_epi8(_mm256_cmpeq_epi8(a, c)) |
                         ((uint64_t)(uint32_t)_mm256_movemask_epi8(_mm256_cmpeq_epi8(b, c)) << 32);
            seps += (uint64_t)__builtin_popcountll(m);
        }
        uint64_t part[4];
        _mm256_storeu_si256((__m256i *)part, acc);
        uint64_t sum = part[0] + part[1] + part[2] + part[3];
        for (; i < n; i++) { sum += d[i]; seps += d[i] == s[0]; }
        *cnt_out = (int64_t)seps + 1;
        return (int64_t)(sum - seps * s[0]);
    }
    if (k == 2 && s[0] == s[1] && s[0] != 0) {
        /* Runs of the character c of length r hold floor(r/2) non-overlapping separators:
         * pairs = (ones - odd_runs) / 2. Odd-length runs are found with the carry-propagation trick
         * (simdjson's odd-backslash-sequence algorithm): adding a run's start bit to the mask carries
         * through the run and lands on the byte after it; the parity of that byte's position against the
         * start's decides odd or even. Runs may span 64-byte blocks (prev_odd carries the sense across).
         * A final zero-padded block terminates a run that touches the end of the document. */
        const uint64_t EVEN = 0x5555555555555555ULL, ODD = 0xAAAAAAAAAAAAAAAAULL;
        const __m256i c = _mm256_set1_epi8((char)s[0]);
        uint64_t ones = 0, odd_runs = 0, prev_odd = 0;
        unsigned char pad[64] __attribute__((aligned(32)));
        for (size_t base = 0; base <= n; base += 64) {
            const unsigned char *p = d + base;
            if (base + 64 > n) { /* last (partial or empty) block, zero padded */
                memset(pad, 0, 64);
                if (n > base) memcpy(pad, d + base, n - base);
                p = pad;
            }
            __m256i a = _mm256_loadu_si256((const __m256i *)p), b = _mm256_loadu_si256((const __m256i *)(p + 32));
            acc = _mm256_add_epi64(acc, _mm256_add_epi64(_mm256_sad_epu8(a, zero), _mm256_sad_epu8(b, zero)));
            uint64_t m = (uint32_t)_mm256_movemask_epi8(_mm256_cmpeq_epi8(a, c)) |
                         ((uint64_t)(uint32_t)_mm256_movemask_epi8(_mm256_cmpeq_epi8(b, c)) << 32);
            ones += (uint64_t)__builtin_popcountll(m);
            uint64_t starts = m & ~(m << 1);
            uint64_t even_start_mask = EVEN ^ prev_odd;
            uint64_t even_starts = starts & even_start_mask, odd_starts = starts & ~even_start_mask;
            uint64_t even_carries = m + even_starts, odd_carries;
            uint64_t out = (uint64_t)__builtin_add_overflow(m, odd_starts, &odd_carries);
            odd_carries |= prev_odd;
            prev_odd = out;
            uint64_t odd_ends = ((even_carries & ~m) & ODD) | ((odd_carries & ~m) & EVEN);
            odd_runs += (uint64_t)__builtin_popcountll(odd_ends);
        }
        uint64_t part[4];
        _mm256_storeu_si256((__m256i *)part, acc);
        uint64_t sum = part[0] + part[1] + part[2] + part[3];
        seps = (ones - odd_runs) / 2;
        *cnt_out = (int64_t)seps + 1;
        return (int64_t)(sum - seps * (uint64_t)(2 * s[0]));
    }
    return -1;
}
__attribute__((noinline)) static int64_t v7(const unsigned char *const *docs, const size_t *dlen,
                                            const unsigned char *const *seps, const size_t *slen,
                                            int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    for (int64_t step = 0; step < iterations; step++) {
        int which = (int)((seed + step) % 2);
        size_t n = dlen[which], k = slen[which];
        int64_t cnt = 0, nonsep = -1, result;
        if (k == 1 || k == 2) nonsep = scan_avx2(docs[which], n, seps[which], k, &cnt);
        if (nonsep >= 0) {
            int64_t lens = (int64_t)n - (cnt - 1) * (int64_t)k;
            result = cnt * 7 + lens + nonsep;
        } else {
            /* exact scalar fallback for separators or documents the vector path declines */
            result = v5(&docs[which], &dlen[which], &seps[which], &slen[which], 1, 0);
        }
        checksum = floormod(checksum + result, MOD);
    }
    return checksum;
}
#endif /* __AVX2__ */

/* v8: WORK ELIMINATION (excluded from conclusions): the result is a pure function of the document
 * (two distinct documents), so compute each once and replay. */
__attribute__((noinline)) static int64_t v8(const unsigned char *const *docs, const size_t *dlen,
                                            const unsigned char *const *seps, const size_t *slen,
                                            int64_t iterations, int64_t seed) {
    int64_t memo[2];
    for (int w = 0; w < 2; w++) {
        int64_t cnt, nonsep = scan_scalar(docs[w], dlen[w], seps[w], slen[w], &cnt);
        memo[w] = cnt * 7 + ((int64_t)dlen[w] - (cnt - 1) * (int64_t)slen[w]) + nonsep;
    }
    int64_t checksum = 0;
    for (int64_t step = 0; step < iterations; step++) checksum = floormod(checksum + memo[(seed + step) % 2], MOD);
    return checksum;
}

/* ================================== main ================================== */
static unsigned char *build_doc(const char *sep, const char *const *frag, int64_t size, int64_t seed, size_t *len) {
    size_t cap = 0, k = strlen(sep);
    for (int64_t j = 0; j < size; j++) cap += strlen(frag[(seed + j) % 5]) + k;
    unsigned char *d = malloc(cap + 64), *p = d;
    for (int64_t j = 0; j < size; j++) {
        const char *f = frag[(seed + j) % 5];
        size_t fl = strlen(f);
        memcpy(p, f, fl); p += fl;
        if (j + 1 < size) { memcpy(p, sep, k); p += k; }
    }
    *len = (size_t)(p - d);
    return d;
}
static void write_u64(FILE *f, uint64_t v) { fwrite(&v, 8, 1, f); }
static uint64_t read_u64(FILE *f) {
    uint64_t v;
    if (fread(&v, 8, 1, f) != 1) { fprintf(stderr, "short data file\n"); exit(2); }
    return v;
}
int main(int argc, char **argv) {
    static const char *options[5] = {"", "alpha", "caf\xc3\xa9", "x", "na\xc3\xafve"};
    if (argc == 5 && (!strcmp(argv[1], "gen") || !strcmp(argv[1], "genwide"))) {
        /* gen SIZE SEED PATH: the benchmark's two documents and separators. genwide: other fragments and
         * separator "ab" / "|" with runs of ':' of length 3 inside, to exercise the fallbacks. */
        int64_t size = atoll(argv[2]), seed = atoll(argv[3]);
        FILE *f = fopen(argv[4], "wb");
        int wide = !strcmp(argv[1], "genwide");
        static const char *odd[5] = {":::", "a:b", "::::x", "|", "\xc3\xa9\xe2\x82\xac"};
        const char *const *frag = wide ? odd : options;
        const char *seps[2] = {"|", "::"};
        for (int w = 0; w < 2; w++) {
            size_t len;
            unsigned char *d = build_doc(seps[w], frag, size, seed, &len);
            write_u64(f, len); fwrite(d, 1, len, f);
            write_u64(f, strlen(seps[w])); fwrite(seps[w], 1, strlen(seps[w]), f);
            free(d);
        }
        fclose(f);
        return 0;
    }
    if (argc < 5) return 2;
    int which = atoi(argv[1]);
    int64_t size = atoll(argv[2]), iterations = atoll(argv[3]), seed = atoll(argv[4]);
    unsigned char *docs[2];
    unsigned char *sepb[2];
    size_t dlen[2], slen[2];
    if (argc == 6) {
        FILE *f = fopen(argv[5], "rb");
        if (!f) { perror("fopen"); return 2; }
        for (int w = 0; w < 2; w++) {
            dlen[w] = read_u64(f);
            docs[w] = malloc(dlen[w] + 64);
            if (fread(docs[w], 1, dlen[w], f) != dlen[w]) return 2;
            slen[w] = read_u64(f);
            sepb[w] = malloc(slen[w] + 8);
            if (fread(sepb[w], 1, slen[w], f) != slen[w]) return 2;
        }
        fclose(f);
    } else {
        if (which >= 30) return 2;
        const char *seps[2] = {"|", "::"};
        for (int w = 0; w < 2; w++) {
            docs[w] = build_doc(seps[w], options, size, seed, &dlen[w]);
            slen[w] = strlen(seps[w]);
            sepb[w] = (unsigned char *)strdup(seps[w]);
        }
    }
    /* mylang objects for v1 (untimed construction) */
    text_obj *texts[2], *sepobj[2];
    for (int w = 0; w < 2; w++) { texts[w] = new_text(docs[w], dlen[w]); sepobj[w] = new_text(sepb[w], slen[w]); }
    const unsigned char *cdocs[2] = {docs[0], docs[1]}, *cseps[2] = {sepb[0], sepb[1]};
    int64_t start = now_ns(), checksum = 0;
    switch (which) {
    case 1: case 20: checksum = v1(texts, sepobj, iterations, seed); break;
    case 2: checksum = v2(cdocs, dlen, cseps, slen, iterations, seed); break;
    case 3: checksum = v3(cdocs, dlen, cseps, slen, iterations, seed); break;
    case 4: checksum = v4(cdocs, dlen, cseps, slen, iterations, seed); break;
    case 5: case 30: checksum = v5(cdocs, dlen, cseps, slen, iterations, seed); break;
    case 6: checksum = v6(cdocs, dlen, cseps, slen, iterations, seed); break;
#ifdef __AVX2__
    case 7: case 31: checksum = v7(cdocs, dlen, cseps, slen, iterations, seed); break;
#endif
    case 8: checksum = v8(cdocs, dlen, cseps, slen, iterations, seed); break;
    case 9: checksum = v9(cdocs, dlen, cseps, slen, iterations, seed); break;
    default: return 2;
    }
    printf("%lld %lld\n", (long long)checksum, (long long)(now_ns() - start));
    return 0;
}
