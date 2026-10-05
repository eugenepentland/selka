/* Layout OLD: the old core's shape (src/native_dictionary.c): an insertion-ordered entry
   array {key, value} and an open-addressing index of u64 slots `hash32 << 32 | entry + 1`
   (0 = empty), linear probing, load <= 5/8, backward-shift deletion (no index tombstones),
   dead entries compacted on growth. A slot whose stored hash differs is skipped without
   loading its entry. With HINT defined, every read writes the last-probe record (state,
   key, entry, slot) and an upsert answers from it first (DICT-GETORPUT-1 / PY-DICT-4).
   Template parameters: PFX, KT, KHASH(k), KEQ(a, b), KEYSUM(k). */
#define CAT2(a, b) a##_##b
#define CAT(a, b) CAT2(a, b)
#define F(name) CAT(PFX, name)

typedef struct { KT key; int64_t val; } F(entry);
typedef struct {
    F(entry) *entries;
    uint64_t *slots;
    uint8_t *dead;            /* per entry, allocated on the first deletion */
    uint32_t elen, ecap, live, mask, ndead;
    int shift;
    int hint_state;           /* 0 none, 1 found, 2 absent */
    uint32_t hint_entry, hint_slot, hint_tag;
    KT hint_key;
} PFX;

static inline uint32_t F(tag)(KT k) { return (uint32_t)(KHASH(k) >> 32) | 1; }
static inline uint32_t F(home)(const PFX *d, uint32_t tag) { return (uint32_t)(((uint64_t)tag * 0x9E3779B97F4A7C15ull) >> d->shift); }

static void F(rebuild)(PFX *d, uint32_t cap) {
    free(d->slots);
    d->slots = xcalloc(cap, sizeof(uint64_t));
    d->mask = cap - 1;
    d->shift = 64 - __builtin_ctz(cap);
    uint32_t w = 0;
    for (uint32_t e = 0; e < d->elen; ++e) {
        if (d->dead && d->dead[e]) continue;
        d->entries[w] = d->entries[e];
        uint32_t tag = F(tag)(d->entries[w].key);
        uint32_t i = F(home)(d, tag);
        while (d->slots[i]) i = (i + 1) & d->mask;
        d->slots[i] = (uint64_t)tag << 32 | (w + 1);
        ++w;
    }
    if (d->dead) memset(d->dead, 0, d->ecap);
    d->elen = w;
    d->ndead = 0;
    d->hint_state = 0;
}

static PFX *F(new)(uint32_t hint) {
    PFX *d = xcalloc(1, sizeof(PFX));
    uint32_t ecap = 8;
    while (ecap < hint) ecap *= 2;
    d->ecap = ecap;
    d->entries = malloc(sizeof(F(entry)) * ecap);
    F(rebuild)(d, ecap * 2);
    return d;
}

static void F(free)(PFX *d) { free(d->entries); free(d->slots); free(d->dead); free(d); }

static inline int64_t F(find)(const PFX *d, KT k, uint32_t tag, uint32_t *slot) {
    uint32_t i = F(home)(d, tag);
    for (;;) {
        uint64_t s = d->slots[i];
        if (!s) { *slot = i; return -1; }
        if ((uint32_t)(s >> 32) == tag) {
            uint32_t e = (uint32_t)s - 1;
            if (KEQ(d->entries[e].key, k)) { *slot = i; return e; }
        }
        i = (i + 1) & d->mask;
    }
}

static inline bool F(get)(PFX *d, KT k, int64_t *out) {
    uint32_t slot, tag = F(tag)(k);
    int64_t e = F(find)(d, k, tag, &slot);
#ifdef HINT
    d->hint_state = e >= 0 ? 1 : 2;
    d->hint_key = k; d->hint_entry = (uint32_t)e; d->hint_slot = slot; d->hint_tag = tag;
#endif
    if (e < 0) return false;
    *out = d->entries[e].val;
    return true;
}

static inline int64_t *F(upsert)(PFX *d, KT k, int64_t dflt) {
    uint32_t slot, tag;
    int64_t e;
#ifdef HINT
    if (d->hint_state && d->hint_key == k) {
        if (d->hint_state == 1) return &d->entries[d->hint_entry].val;
        slot = d->hint_slot; tag = d->hint_tag; e = -1;
        goto insert;
    }
#endif
    tag = F(tag)(k);
    e = F(find)(d, k, tag, &slot);
    if (e >= 0) return &d->entries[e].val;
#ifdef HINT
insert:
#endif
    if (d->elen == d->ecap || (d->elen + 1) * 8 > (d->mask + 1) * 5) {
        if (d->live * 2 >= d->ecap) {
            d->ecap *= 2;
            d->entries = realloc(d->entries, sizeof(F(entry)) * d->ecap);
            if (d->dead) d->dead = realloc(d->dead, d->ecap);
        }
        F(rebuild)(d, d->ecap * 2);
        F(find)(d, k, tag, &slot);
    }
    e = d->elen++;
    d->entries[e] = (F(entry)){k, dflt};
    d->slots[slot] = (uint64_t)tag << 32 | (uint32_t)(e + 1);
    d->live++;
    d->hint_state = 0;
    return &d->entries[e].val;
}

static inline void F(put)(PFX *d, KT k, int64_t v) { *F(upsert)(d, k, v) = v; }

static bool F(del)(PFX *d, KT k) {
    uint32_t slot, tag = F(tag)(k);
    int64_t e = F(find)(d, k, tag, &slot);
    if (e < 0) return false;
    if (!d->dead) d->dead = xcalloc(d->ecap, 1);
    d->dead[e] = 1; d->ndead++; d->live--;
    /* backward-shift deletion */
    uint32_t i = slot, j = slot;
    for (;;) {
        j = (j + 1) & d->mask;
        uint64_t s = d->slots[j];
        if (!s) break;
        uint32_t h = F(home)(d, (uint32_t)(s >> 32));
        if (((j - h) & d->mask) >= ((j - i) & d->mask)) { d->slots[i] = s; i = j; }
    }
    d->slots[i] = 0;
    d->hint_state = 0;
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
