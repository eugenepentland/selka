/* Reference workload adapter over the installed dictionary runtime and LLVM probe.
 * The LLVM helper is extracted verbatim by layout_real.py and linked with LTO. */
#define CAT2(a, b) a##_##b
#define CAT(a, b) CAT2(a, b)
#define F(name) CAT(PFX, name)
typedef struct { myl_block *block; } PFX;
static core_dict_descriptor F(desc) = {16, 8, CORE_KEY_KIND, 8, NULL, NULL, NULL};
extern int64_t CORE_PROBE(const myl_block *, const void *, uint64_t);
static PFX *F(new)(uint32_t hint) {
    PFX *d = malloc(sizeof *d);
    d->block = myl_core_dict_new(hint, &F(desc));
    return d;
}
static void F(free)(PFX *d) { myl_core_release(d->block); free(d); }
static bool F(get)(PFX *d, KT key, int64_t *out) {
    int64_t entry = CORE_PROBE(d->block, &key, KHASH(key));
    if (entry < 0) return false;
    memcpy(out, dict_entry(d->block, (uint64_t)entry) + 8, 8);
    return true;
}
static int64_t *F(upsert)(PFX *d, KT key, int64_t fallback) {
    int64_t entry = CORE_PROBE(d->block, &key, KHASH(key));
    if (entry < 0) {
        d->block = myl_core_dict_insert(d->block, entry, &key, &fallback, false);
        entry = (int64_t)dict_meta(d->block)->elen - 1;
    }
    return (int64_t *)(dict_entry(d->block, (uint64_t)entry) + 8);
}
static void F(put)(PFX *d, KT key, int64_t value) { *F(upsert)(d, key, value) = value; }
static bool F(del)(PFX *d, KT key) {
    int64_t entry = CORE_PROBE(d->block, &key, KHASH(key));
    if (entry < 0) return false;
    d->block = myl_core_dict_remove(d->block, entry);
    return true;
}
static int64_t F(sum_items)(const PFX *d) {
    uint64_t total = 0;
    core_dict_meta *meta = dict_meta(d->block);
    for (uint64_t entry = 0; entry < meta->elen; ++entry) {
        if (!dict_live(meta, entry)) continue;
        KT key;
        int64_t value;
        memcpy(&key, dict_entry(d->block, entry), 8);
        memcpy(&value, dict_entry(d->block, entry) + 8, 8);
        total = total * 1000003u + KEYSUM(key) + value;
    }
    return (int64_t)total;
}
#undef F
#undef CAT
#undef CAT2
