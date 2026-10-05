/* Layout SWISS: SwissTable-style control bytes (7-bit hash tag per slot, 16-slot SSE2
   group match) with {key, value} stored inline in the slots, load <= 7/8, plus an
   insertion-order array of u32 slot numbers. A deleted slot becomes DELETED and is never
   reused before the next rehash, so the order array stays valid: iteration skips order
   entries whose slot is DELETED, and a re-inserted key is appended at the end. The control
   line and the slot line of a probe are both addressed from the hash alone, so the CPU
   can fetch them in parallel. Template parameters: PFX, KT, KHASH(k), KEQ(a, b), KEYSUM(k). */
#include <immintrin.h>
#define CAT2(a, b) a##_##b
#define CAT(a, b) CAT2(a, b)
#define F(name) CAT(PFX, name)

enum { CAT(PFX, EMPTY) = 0x80, CAT(PFX, DELETED) = 0xFE };

typedef struct { KT key; int64_t val; } F(slot);
typedef struct {
    uint8_t *ctrl;      /* cap + 15 bytes; the first 15 mirrored at the end */
    F(slot) *slots;
    uint32_t *order;
    uint32_t cap, mask, used, live, olen, ocap;
    int shift;
} PFX;

static void F(alloc)(PFX *d, uint32_t cap) {
    d->cap = cap; d->mask = cap - 1; d->shift = 64 - __builtin_ctz(cap);
    d->ctrl = malloc(cap + 16);
    memset(d->ctrl, CAT(PFX, EMPTY), cap + 16);
    d->slots = malloc(sizeof(F(slot)) * cap);
    d->used = 0;
}

static inline void F(setctrl)(PFX *d, uint32_t i, uint8_t v) {
    d->ctrl[i] = v;
    if (i < 15) d->ctrl[d->cap + i] = v;
}

static PFX *F(new)(uint32_t hint) {
    PFX *d = xcalloc(1, sizeof(PFX));
    uint32_t cap = 16;
    while (cap * 7 / 8 < hint) cap *= 2;
    F(alloc)(d, cap);
    d->ocap = cap * 7 / 8 + 1;
    d->order = malloc(sizeof(uint32_t) * d->ocap);
    return d;
}

static void F(free)(PFX *d) { free(d->ctrl); free(d->slots); free(d->order); free(d); }

static inline int64_t F(find)(const PFX *d, KT k, uint64_t h) {
    uint32_t pos = (uint32_t)(h >> d->shift), step = 0;
    __m128i tag = _mm_set1_epi8((char)(h & 0x7f));
    __m128i empty = _mm_set1_epi8((char)CAT(PFX, EMPTY));
    for (;;) {
        __m128i g = _mm_loadu_si128((const __m128i *)(d->ctrl + pos));
        uint32_t m = (uint32_t)_mm_movemask_epi8(_mm_cmpeq_epi8(g, tag));
        while (m) {
            uint32_t i = (pos + (uint32_t)__builtin_ctz(m)) & d->mask;
            if (KEQ(d->slots[i].key, k)) return i;
            m &= m - 1;
        }
        if (_mm_movemask_epi8(_mm_cmpeq_epi8(g, empty))) return -1;
        step += 16;
        pos = (pos + step) & d->mask;
    }
}

static inline uint32_t F(free_slot)(const PFX *d, uint64_t h) {
    uint32_t pos = (uint32_t)(h >> d->shift), step = 0;
    __m128i empty = _mm_set1_epi8((char)CAT(PFX, EMPTY));
    for (;;) {
        __m128i g = _mm_loadu_si128((const __m128i *)(d->ctrl + pos));
        uint32_t m = (uint32_t)_mm_movemask_epi8(_mm_cmpeq_epi8(g, empty));
        if (m) return (pos + (uint32_t)__builtin_ctz(m)) & d->mask;
        step += 16;
        pos = (pos + step) & d->mask;
    }
}

static inline bool F(get)(PFX *d, KT k, int64_t *out) {
    int64_t i = F(find)(d, k, KHASH(k));
    if (i < 0) return false;
    *out = d->slots[i].val;
    return true;
}

static void F(rehash)(PFX *d) {
    uint8_t *octrl = d->ctrl; F(slot) *oslots = d->slots;
    uint32_t ncap = d->cap;
    if ((d->live + 1) * 16 > ncap * 7) ncap *= 2; /* live above 7/16: double, else clean in place */
    F(alloc)(d, ncap);
    uint32_t w = 0;
    for (uint32_t o = 0; o < d->olen; ++o) {
        uint32_t s = d->order[o];
        if (octrl[s] & 0x80) continue; /* deleted */
        uint64_t h = KHASH(oslots[s].key);
        uint32_t i = F(free_slot)(d, h);
        F(setctrl)(d, i, (uint8_t)(h & 0x7f));
        d->slots[i] = oslots[s];
        d->order[w++] = i;
    }
    d->olen = w; d->used = w;
    if (d->ocap < ncap * 7 / 8 + 1) { d->ocap = ncap * 7 / 8 + 1; d->order = realloc(d->order, sizeof(uint32_t) * d->ocap); }
    free(octrl); free(oslots);
}

static inline int64_t *F(upsert)(PFX *d, KT k, int64_t dflt) {
    uint64_t h = KHASH(k);
    int64_t i = F(find)(d, k, h);
    if (i >= 0) return &d->slots[i].val;
    if ((d->used + 1) * 8 > d->cap * 7) F(rehash)(d);
    uint32_t s = F(free_slot)(d, h);
    F(setctrl)(d, s, (uint8_t)(h & 0x7f));
    d->slots[s] = (F(slot)){k, dflt};
    d->order[d->olen++] = s;
    d->used++; d->live++;
    return &d->slots[s].val;
}

static inline void F(put)(PFX *d, KT k, int64_t v) { *F(upsert)(d, k, v) = v; }

static bool F(del)(PFX *d, KT k) {
    int64_t i = F(find)(d, k, KHASH(k));
    if (i < 0) return false;
    F(setctrl)(d, (uint32_t)i, CAT(PFX, DELETED));
    d->live--;
    return true;
}

static int64_t F(sum_items)(const PFX *d) {
    uint64_t total = 0;
    for (uint32_t o = 0; o < d->olen; ++o) {
        uint32_t s = d->order[o];
        if (!(d->ctrl[s] & 0x80)) total = total * 1000003u + KEYSUM(d->slots[s].key) + d->slots[s].val;
    }
    return total;
}

#undef F
#undef CAT
#undef CAT2
