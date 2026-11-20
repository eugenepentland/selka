/* Dictionary ordinals after deletes: every ordinal must name the same entry as a brute-force scan of
 * the entry bitmap, across whole dead words, the partial last word, growth and copies. */
#include "core_rt.c"
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
const myl_core_site myl_core_sites[1];
const char myl_core_source_path[] = "dict-rank-regression";

/* A u64 key with a u64 value at offset 8: stride 16, memcmp keys, no managed layout. */
static const core_dict_descriptor desc = { 16, 8, 0, 8, NULL, NULL, NULL };
static uint64_t checked;

static myl_block *put(myl_block *dict, uint64_t key, uint64_t value) {
    uint64_t hash = myl_core_dict_hash(dict, &key);
    int64_t probe = myl_core_dict_find(dict, &key, hash);
    if (probe >= 0) return dict;
    return myl_core_dict_insert(dict, probe, &key, &value, false);
}

static myl_block *drop(myl_block *dict, uint64_t key) {
    uint64_t hash = myl_core_dict_hash(dict, &key);
    int64_t entry = myl_core_dict_find(dict, &key, hash);
    if (entry < 0) return dict;
    return myl_core_dict_remove(dict, entry);
}

/* The entry of the k-th live entry by a plain scan of the bitmap: the reference the ordinal must match. */
static int64_t scan(const myl_block *dict, uint64_t k) {
    uint64_t entries = myl_core_dict_entries(dict);
    for (uint64_t e = 0; e < entries; ++e)
        if (myl_core_dict_live(dict, e) && k-- == 0) return (int64_t)e;
    return -1;
}

static void check_all(const myl_block *dict) {
    for (uint64_t k = 0; k < (uint64_t)dict->len; ++k) {
        int64_t want = scan(dict, k), got = myl_core_dict_ordinal(dict, k);
        if (want != got) {
            fprintf(stderr, "ordinal %llu of %lld: scan %lld, ordinal %lld\n", (unsigned long long)k, (long long)dict->len, (long long)want, (long long)got);
            exit(1);
        }
        ++checked;
    }
}

int main(void) {
    myl_block *dict = myl_core_dict_new(0, &desc);
    for (uint64_t key = 0; key < 300; ++key) dict = put(dict, key, key * 10);
    check_all(dict);
    for (uint64_t key = 64; key < 192; ++key) dict = drop(dict, key);
    dict = drop(dict, 0);
    dict = drop(dict, 250);
    dict = drop(dict, 299);
    for (uint64_t key = 200; key < 210; key += 3) dict = drop(dict, key);
    check_all(dict);
    for (uint64_t key = 300; key < 340; ++key) dict = put(dict, key, key * 10);
    check_all(dict);
    for (uint64_t key = 340; key < 1200; ++key) dict = put(dict, key, key);
    check_all(dict);
    myl_block *copy = myl_core_dict_copy(dict);
    for (uint64_t k = 0; k < (uint64_t)dict->len; ++k)
        if (myl_core_dict_ordinal(copy, k) != myl_core_dict_ordinal(dict, k)) { fprintf(stderr, "copy ordinal %llu differs\n", (unsigned long long)k); return 1; }
    check_all(copy);
    for (uint64_t key = 0; key < 1200; ++key)
        if (key % 97 != 5) dict = drop(dict, key);
    check_all(dict);
    for (uint64_t key = 0; key < 1200; ++key) dict = drop(dict, key);
    if (dict->len != 0) { fprintf(stderr, "dictionary not empty\n"); return 1; }
    printf("dict ordinals match a scan: %llu checked\n", (unsigned long long)checked);
    return 0;
}
