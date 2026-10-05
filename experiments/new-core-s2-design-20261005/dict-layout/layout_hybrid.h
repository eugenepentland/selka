/* Layout HYBRID: the old core's dense insertion-ordered entry array {key, value}, indexed
   by SwissTable-style control bytes (7-bit tag, 16-slot SSE2 group match) beside an array
   of u32 entry numbers; load <= 1/2. A miss resolves in the control line (no entry read);
   a hit reads the control and index lines (both addressed from the hash, so fetched in
   parallel) and then the entry. Iteration walks the dense entries. A deleted key's control
   byte becomes DELETED (never reused before the next rebuild) and its entry is marked dead;
   growth rebuilds control and index from the live entries, compacting them in order.
   Template parameters: PFX, KT, KHASH(k), KEQ(a, b), KEYSUM(k). */
#include <immintrin.h>
#define CAT2(a, b) a##_##b
#define CAT(a, b) CAT2(a, b)
#define F(name) CAT(PFX, name)

enum { CAT(PFX, EMPTY) = 0x80, CAT(PFX, DELETED) = 0xFE };

typedef struct { KT key; int64_t val; } F(entry);
typedef struct {
    uint8_t *ctrl;          /* cap + 16 bytes, the first 15 mirrored at the end */
    uint32_t *index;        /* entry number per slot */
    F(entry) *entries;
    uint8_t *dead;          /* per entry, allocated on the first deletion */
    uint32_t cap, mask, used, live, elen, ecap, ndead;
    int shift;
} PFX;

static inline void F(setctrl)(PFX *d, uint32_t i, uint8_t v) {
    d->ctrl[i] = v;
    if (i < 15) d->ctrl[d->cap + i] = v;
}

/* The control/index slot of key k, or -1 with *ins = the first EMPTY slot of the probe
   sequence (DELETED is never reused, so the group where the probe stops holds it). */
static inline int64_t F(find)(const PFX *d, KT k, uint64_t h, uint32_t *ins) {
    uint32_t pos = (uint32_t)(h >> d->shift), step = 0;
    __m128i tag = _mm_set1_epi8((char)(h & 0x7f));
    __m128i empty = _mm_set1_epi8((char)CAT(PFX, EMPTY));
    for (;;) {
        __m128i g = _mm_loadu_si128((const __m128i *)(d->ctrl + pos));
        uint32_t m = (uint32_t)_mm_movemask_epi8(_mm_cmpeq_epi8(g, tag));
        while (m) {
            uint32_t i = (pos + (uint32_t)__builtin_ctz(m)) & d->mask;
            if (KEQ(d->entries[d->index[i]].key, k)) return i;
            m &= m - 1;
        }
        uint32_t e = (uint32_t)_mm_movemask_epi8(_mm_cmpeq_epi8(g, empty));
        if (e) { *ins = (pos + (uint32_t)__builtin_ctz(e)) & d->mask; return -1; }
        step += 16;
        pos = (pos + step) & d->mask;
    }
}

static void F(rebuild)(PFX *d, uint32_t cap) {
    free(d->ctrl); free(d->index);
    d->cap = cap; d->mask = cap - 1; d->shift = 64 - __builtin_ctz(cap);
    d->ctrl = malloc(cap + 16);
    memset(d->ctrl, CAT(PFX, EMPTY), cap + 16);
    d->index = malloc(sizeof(uint32_t) * cap);
    uint32_t w = 0;
    for (uint32_t e = 0; e < d->elen; ++e) {
        if (d->ndead && d->dead[e]) continue;
        d->entries[w] = d->entries[e];
        uint64_t h = KHASH(d->entries[w].key);
        uint32_t ins;
        F(find)(d, d->entries[w].key, h, &ins); /* a fresh table: the probe only finds EMPTY */
        F(setctrl)(d, ins, (uint8_t)(h & 0x7f));
        d->index[ins] = w++;
    }
    if (d->dead) memset(d->dead, 0, d->ecap);
    d->elen = w; d->used = w; d->ndead = 0;
}

static PFX *F(new)(uint32_t hint) {
    PFX *d = xcalloc(1, sizeof(PFX));
    uint32_t cap = 16;
    while (cap / 2 < hint) cap *= 2;
    d->ecap = cap / 2;
    d->entries = malloc(sizeof(F(entry)) * d->ecap);
    F(rebuild)(d, cap);
    return d;
}

static void F(free)(PFX *d) { free(d->ctrl); free(d->index); free(d->entries); free(d->dead); free(d); }

static inline bool F(get)(PFX *d, KT k, int64_t *out) {
    uint32_t ins;
    int64_t i = F(find)(d, k, KHASH(k), &ins);
    if (i < 0) return false;
    *out = d->entries[d->index[i]].val;
    return true;
}

static inline int64_t *F(upsert)(PFX *d, KT k, int64_t dflt) {
    uint64_t h = KHASH(k);
    uint32_t ins;
    int64_t i = F(find)(d, k, h, &ins);
    if (i >= 0) return &d->entries[d->index[i]].val;
    if (d->used + 1 > d->cap / 2) {
        uint32_t cap = (d->live + 1) * 4 > d->cap ? d->cap * 2 : d->cap;
        if (cap / 2 > d->ecap) {
            d->ecap = cap / 2;
            d->entries = realloc(d->entries, sizeof(F(entry)) * d->ecap);
            if (d->dead) d->dead = realloc(d->dead, d->ecap);
        }
        F(rebuild)(d, cap);
        F(find)(d, k, h, &ins);
    }
    uint32_t e = d->elen++;
    d->entries[e] = (F(entry)){k, dflt};
    F(setctrl)(d, ins, (uint8_t)(h & 0x7f));
    d->index[ins] = e;
    d->used++; d->live++;
    return &d->entries[e].val;
}

static inline void F(put)(PFX *d, KT k, int64_t v) { *F(upsert)(d, k, v) = v; }

static bool F(del)(PFX *d, KT k) {
    uint32_t ins;
    int64_t i = F(find)(d, k, KHASH(k), &ins);
    if (i < 0) return false;
    if (!d->dead) d->dead = xcalloc(d->ecap, 1);
    d->dead[d->index[i]] = 1; d->ndead++;
    F(setctrl)(d, (uint32_t)i, CAT(PFX, DELETED));
    d->live--;
    return true;
}

static int64_t F(sum_items)(const PFX *d) {
    uint64_t total = 0;
    for (uint32_t e = 0; e < d->elen; ++e)
        if (!d->ndead || !d->dead[e]) total = total * 1000003u + KEYSUM(d->entries[e].key) + d->entries[e].val;
    return total;
}

#undef F
#undef CAT
#undef CAT2
