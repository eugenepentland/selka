/* Layout CPY: CPython 3.6's compact dict: an insertion-ordered entry array {hash, key,
   value} and a separate open-addressing index of i32 entry numbers, linear probing, index
   load <= 1/2..2/3. Every probe step reads the entry (a second, dependent cache line) to
   compare the stored hash. With HINT defined, reads also write a last-probe record and
   upserts consult it first. Template parameters: PFX, KT, KHASH(k), KEQ(a, b), KEYSUM(k). */
#define CAT2(a, b) a##_##b
#define CAT(a, b) CAT2(a, b)
#define F(name) CAT(PFX, name)

typedef struct { uint64_t hash; KT key; int64_t val; } F(entry);
typedef struct {
    F(entry) *entries;
    int32_t *index;
    uint32_t elen, ecap, live, mask;
    int shift;
    int32_t hint_entry; /* last probe's entry, -1 = none */
    KT hint_key;
} PFX;

enum { CAT(PFX, EMPTY) = -1, CAT(PFX, DEAD) = -2 };

static void F(rebuild)(PFX *d, uint32_t icap) {
    free(d->index);
    d->index = malloc(sizeof(int32_t) * icap);
    memset(d->index, 0xff, sizeof(int32_t) * icap);
    d->mask = icap - 1;
    d->shift = 64 - __builtin_ctz(icap);
    uint32_t w = 0;
    for (uint32_t e = 0; e < d->elen; ++e) {
        if (d->entries[e].hash == 0) continue; /* deleted (hash 0 never stored live) */
        d->entries[w] = d->entries[e];
        uint32_t i = (uint32_t)(d->entries[w].hash >> d->shift);
        while (d->index[i] != CAT(PFX, EMPTY)) i = (i + 1) & d->mask;
        d->index[i] = (int32_t)w++;
    }
    d->elen = w;
    d->hint_entry = -1;
}

static PFX *F(new)(uint32_t hint) {
    PFX *d = xcalloc(1, sizeof(PFX));
    uint32_t ecap = 8;
    while (ecap < hint) ecap *= 2;
    d->ecap = ecap;
    d->entries = malloc(sizeof(F(entry)) * ecap);
    d->hint_entry = -1;
    F(rebuild)(d, ecap * 2); /* index 2x entries: load <= 1/2 .. 2/3 */
    return d;
}

static void F(free)(PFX *d) { free(d->entries); free(d->index); free(d); }

static inline uint64_t F(h)(KT k) { uint64_t h = KHASH(k); return h ? h : 1; }

/* Returns the entry number or -1; *slot gets the index slot (or the first empty one). */
static inline int32_t F(find)(const PFX *d, KT k, uint64_t h, uint32_t *slot) {
    uint32_t i = (uint32_t)(h >> d->shift);
    for (;;) {
        int32_t e = d->index[i];
        if (e == CAT(PFX, EMPTY)) { *slot = i; return -1; }
        if (e >= 0 && d->entries[e].hash == h && KEQ(d->entries[e].key, k)) { *slot = i; return e; }
        i = (i + 1) & d->mask;
    }
}

static inline bool F(get)(PFX *d, KT k, int64_t *out) {
    uint32_t slot;
    int32_t e = F(find)(d, k, F(h)(k), &slot);
#ifdef HINT
    d->hint_entry = e;
    d->hint_key = k;
#endif
    if (e < 0) return false;
    *out = d->entries[e].val;
    return true;
}

static void F(grow)(PFX *d) {
    if (d->live * 2 > d->ecap) {
        d->ecap *= 2;
        d->entries = realloc(d->entries, sizeof(F(entry)) * d->ecap);
    }
    F(rebuild)(d, d->ecap * 2);
}

static inline int64_t *F(upsert)(PFX *d, KT k, int64_t dflt) {
#ifdef HINT
    if (d->hint_entry >= 0 && d->hint_key == k) return &d->entries[d->hint_entry].val;
#endif
    uint64_t h = F(h)(k);
    uint32_t slot;
    int32_t e = F(find)(d, k, h, &slot);
    if (e >= 0) return &d->entries[e].val;
    if (d->elen == d->ecap) { F(grow)(d); F(find)(d, k, h, &slot); }
    e = (int32_t)d->elen++;
    d->entries[e] = (F(entry)){h, k, dflt};
    d->index[slot] = e;
    d->live++;
    return &d->entries[e].val;
}

static inline void F(put)(PFX *d, KT k, int64_t v) { *F(upsert)(d, k, v) = v; }

static bool F(del)(PFX *d, KT k) {
    uint32_t slot;
    int32_t e = F(find)(d, k, F(h)(k), &slot);
    if (e < 0) return false;
    d->index[slot] = CAT(PFX, DEAD);
    d->entries[e].hash = 0;
    d->live--;
    d->hint_entry = -1;
    return true;
}

static int64_t F(sum_items)(const PFX *d) {
    uint64_t total = 0;
    for (uint32_t e = 0; e < d->elen; ++e)
        if (d->entries[e].hash) total = total * 1000003u + KEYSUM(d->entries[e].key) + d->entries[e].val;
    return total;
}

#undef F
#undef CAT
#undef CAT2
