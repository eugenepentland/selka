/* Ordered hybrid dictionaries, independent of the Core operation vocabulary.
 * Entries keep their natural key/value layout. The index uses 16-byte SSE2
 * control groups and 32-bit entry numbers, at <= 1/2 occupancy including tombstones.
 * No mutable lookup hint is ever written. */
#include <emmintrin.h>

enum { DICT_EMPTY = 0x80, DICT_DELETED = 0xfe, DICT_SMALL = 8 };
typedef struct {
    uint32_t stride, value_offset, key_kind, key_size;
    myl_layout *layout;
    uint64_t (*hash)(const void *);
    bool (*same)(const void *, const void *);
} core_dict_descriptor;
typedef struct {
    uint32_t slots, used, elen, dead;
    unsigned char data[];
} core_dict_index;
typedef struct {
    const core_dict_descriptor *desc;
    core_dict_index *index;
    uint64_t *hashes;
    unsigned char *dead;
    uint64_t elen;
} core_dict_meta;

/* Published by the integrated text runtime. */
extern uint32_t myl_core_str_hash(const myl_block *);

void myl_core_s2_unsupported(int operation) {
    fprintf(stderr, "error[E_CORE_UNSUPPORTED]: S2 IR operation %d is not implemented\n", operation);
    os_exit(1);
}

static core_dict_meta *dict_meta(const myl_block *dict) { return (core_dict_meta *)(intptr_t)dict->reserved; }
static unsigned char *dict_entry(const myl_block *dict, uint64_t entry) {
    return (unsigned char *)dict + MYL_HEADER + entry * dict_meta(dict)->desc->stride;
}
static bool dict_live(const core_dict_meta *meta, uint64_t entry) {
    return !meta->dead || !(meta->dead[entry >> 3] & (1u << (entry & 7)));
}
static uint32_t *dict_numbers(core_dict_index *index) {
    return (uint32_t *)(index->data + ((index->slots + 15u + 15u) & ~15u));
}
static void dict_control(core_dict_index *index, uint32_t at, unsigned char tag) {
    index->data[at] = tag;
    if (at < 15) index->data[index->slots + at] = tag;
}
static uint64_t dict_hash_bits(uint64_t bits) {
    uint64_t mixed = bits * UINT64_C(0x9e3779b97f4a7c15);
    return mixed ^ (mixed >> 32);
}
static uint64_t dict_hash(const core_dict_descriptor *desc, const void *key) {
    if (desc->key_kind == 3) return desc->hash(key);
    if (desc->key_kind == 2) {
        myl_block *text;
        memcpy(&text, key, sizeof text);
        return dict_hash_bits(myl_core_str_hash(text));
    }
    uint64_t bits = 0;
    memcpy(&bits, key, desc->key_size);
    return dict_hash_bits(bits);
}
static bool dict_same(const core_dict_descriptor *desc, const void *left, const void *right) {
    if (desc->key_kind == 3) return desc->same(left, right);
    if (desc->key_kind != 2) return memcmp(left, right, desc->key_size) == 0;
    myl_block *a, *b;
    memcpy(&a, left, sizeof a);
    memcpy(&b, right, sizeof b);
    return myl_core_str_eq(a, b);
}
static uint32_t dict_home(uint64_t hash, uint32_t slots) { return (uint32_t)(hash >> (64 - __builtin_ctz(slots))); }

/* Empty slots, never deleted ones, are reused: a key deleted and reinserted
 * appends a new dense entry and keeps insertion order. */
static int64_t dict_probe_from(const myl_block *dict, const void *key, uint64_t hash, uint32_t start) {
    core_dict_meta *meta = dict_meta(dict);
    core_dict_index *index = meta->index;
    uint32_t pos = start, step = 0, mask = index->slots - 1;
    __m128i tags = _mm_set1_epi8((char)(hash & 0x7f));
    __m128i empty = _mm_set1_epi8((char)DICT_EMPTY);
    for (;;) {
        __m128i controls = _mm_loadu_si128((const __m128i *)(index->data + pos));
        unsigned candidates = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(controls, tags));
        while (candidates) {
            unsigned bit = (unsigned)__builtin_ctz(candidates);
            uint32_t slot = (pos + bit) & mask;
            uint32_t entry = dict_numbers(index)[slot];
            if (meta->hashes[entry] == hash && dict_same(meta->desc, dict_entry(dict, entry), key)) return entry;
            candidates &= candidates - 1;
        }
        unsigned holes = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(controls, empty));
        if (holes) return -(int64_t)(((pos + (unsigned)__builtin_ctz(holes)) & mask) + 1);
        step += 16;
        pos = (pos + step) & mask;
    }
}

/* Pure lookup: all visible table writes belong to consuming update operations. */
int64_t myl_core_dict_find(const myl_block *dict, const void *key, uint64_t hash) {
    core_dict_meta *meta = dict_meta(dict);
    if (meta->index) return dict_probe_from(dict, key, hash, dict_home(hash, meta->index->slots));
    for (uint64_t i = 0; i < meta->elen; ++i)
        if (dict_live(meta, i) && meta->hashes[i] == hash && dict_same(meta->desc, dict_entry(dict, i), key)) return (int64_t)i;
    return -1;
}

uint64_t myl_core_dict_hash(const myl_block *dict, const void *key) { return dict_hash(dict_meta(dict)->desc, key); }

static void dict_rebuild(myl_block *dict, uint32_t slots) {
    core_dict_meta *meta = dict_meta(dict);
    if (meta->dead) {
        uint64_t next = 0;
        for (uint64_t i = 0; i < meta->elen; ++i) {
            if (!dict_live(meta, i)) continue;
            if (next != i) {
                memmove(dict_entry(dict, next), dict_entry(dict, i), meta->desc->stride);
                meta->hashes[next] = meta->hashes[i];
            }
            ++next;
        }
        meta->elen = next;
        free(meta->dead);
        meta->dead = NULL;
    }
    free(meta->index);
    meta->index = NULL;
    if (dict->len <= DICT_SMALL) return;
    while (slots < 32 || slots < (uint64_t)dict->len * 2) slots = slots ? slots * 2 : 32;
    size_t controls = (slots + 30u) & ~15u;
    core_dict_index *index = malloc(sizeof *index + controls + (size_t)slots * 4);
    if (!index) out_of_memory();
    *index = (core_dict_index){slots, (uint32_t)meta->elen, (uint32_t)meta->elen, 0};
    memset(index->data, DICT_EMPTY, controls);
    meta->index = index;
    /* A rebuild needs only an empty slot: scalar probing avoids full key compares. */
    for (uint32_t entry = 0; entry < meta->elen; ++entry) {
        uint64_t hash = meta->hashes[entry];
        uint32_t slot = dict_home(hash, slots);
        uint32_t step = 0;
        for (;;) {
            uint32_t bit = 0;
            while (bit < 16 && index->data[(slot + bit) & (slots - 1)] != DICT_EMPTY) ++bit;
            if (bit < 16) { slot = (slot + bit) & (slots - 1); break; }
            step += 16;
            slot = (slot + step) & (slots - 1);
        }
        dict_control(index, slot, (unsigned char)(hash & 0x7f));
        dict_numbers(index)[slot] = entry;
    }
}

myl_block *myl_core_dict_new(uint64_t hint, const core_dict_descriptor *desc) {
    if (hint > UINT32_MAX / 2) out_of_memory();
    uint64_t cap = hint > 8 ? hint : 8;
    myl_block *dict = block_new(MYL_KIND_DICT, (int64_t)cap, desc->stride);
    core_dict_meta *meta = calloc(1, sizeof *meta);
    if (!meta) out_of_memory();
    meta->desc = desc;
    meta->hashes = malloc((size_t)cap * sizeof(uint64_t));
    if (!meta->hashes) out_of_memory();
    dict->reserved = (int64_t)(intptr_t)meta;
    return dict;
}

static myl_block *dict_room(myl_block *dict) {
    core_dict_meta *meta = dict_meta(dict);
    if (meta->elen < (uint64_t)dict->cap) return dict;
    uint64_t cap = (uint64_t)dict->cap * 2;
    if (cap > UINT32_MAX / 2) out_of_memory();
    myl_block *grown = block_new(MYL_KIND_DICT, (int64_t)cap, meta->desc->stride);
    grown->len = dict->len;
    grown->reserved = dict->reserved;
    memcpy(block_data(grown), block_data(dict), (size_t)meta->elen * meta->desc->stride);
    uint64_t *hashes = realloc(meta->hashes, (size_t)cap * 8);
    if (!hashes) out_of_memory();
    meta->hashes = hashes;
    if (meta->dead) {
        unsigned char *dead = realloc(meta->dead, (size_t)(cap + 7) / 8);
        if (!dead) out_of_memory();
        memset(dead + ((uint64_t)dict->cap + 7) / 8, 0, (size_t)((cap + 7) / 8 - ((uint64_t)dict->cap + 7) / 8));
        meta->dead = dead;
    }
    block_free(dict);
    return grown;
}

static void dict_release_part(const core_dict_descriptor *desc, unsigned char *entry, bool key, bool value) {
    myl_layout *layout = desc->layout;
    if (!layout) return;
    for (int32_t r = 0; r < layout[1]; ++r) {
        int32_t offset = layout[3 + 2 * r];
        if ((offset < (int32_t)desc->value_offset && !key) || (offset >= (int32_t)desc->value_offset && !value)) continue;
        myl_core_release(reference_at(layout, entry, r));
    }
}

myl_block *myl_core_dict_set(myl_block *dict, int64_t entry, const void *value) {
    core_dict_meta *meta = dict_meta(dict);
    unsigned char *data = dict_entry(dict, (uint64_t)entry);
    dict_release_part(meta->desc, data, false, true);
    memcpy(data + meta->desc->value_offset, value, meta->desc->stride - meta->desc->value_offset);
    return dict;
}

myl_block *myl_core_dict_insert(myl_block *dict, int64_t probe, const void *key, const void *value, bool verify) {
    core_dict_meta *meta = dict_meta(dict);
    uint64_t hash = dict_hash(meta->desc, key);
    if (verify && (probe >= 0 || !count_is_unique(dict))) abort();
    if (!meta->index && dict->len >= DICT_SMALL) {
        /* Crossing the small-table boundary builds the first index after append. */
    } else if (meta->index && meta->index->used * 2 >= meta->index->slots) {
        uint32_t slots = meta->index->slots;
        if ((uint64_t)dict->len * 4 > slots) slots *= 2;
        dict_rebuild(dict, slots);
        probe = myl_core_dict_find(dict, key, hash);
    }
    dict = dict_room(dict);
    meta = dict_meta(dict);
    unsigned char *entry = dict_entry(dict, meta->elen);
    memset(entry, 0, meta->desc->stride);
    memcpy(entry, key, meta->desc->key_size);
    if (value) memcpy(entry + meta->desc->value_offset, value, meta->desc->stride - meta->desc->value_offset);
    meta->hashes[meta->elen] = hash;
    if (meta->index) {
        uint32_t slot = (uint32_t)(-probe - 1);
        if (verify && meta->index->data[slot] != DICT_EMPTY) abort();
        dict_control(meta->index, slot, (unsigned char)(hash & 0x7f));
        dict_numbers(meta->index)[slot] = (uint32_t)meta->elen;
        meta->index->used++;
        meta->index->elen++;
    }
    meta->elen++;
    dict->len++;
    if (!meta->index && dict->len > DICT_SMALL) {
        uint32_t slots = 32;
        while (slots < (uint64_t)dict->cap * 2) slots *= 2;
        dict_rebuild(dict, slots);
    }
    return dict;
}

myl_block *myl_core_dict_remove(myl_block *dict, int64_t entry) {
    core_dict_meta *meta = dict_meta(dict);
    if (!meta->dead) {
        meta->dead = calloc(((size_t)dict->cap + 7) / 8, 1);
        if (!meta->dead) out_of_memory();
    }
    if (meta->index) {
        /* The entry number already identifies the exact key; no equality or hash recomputation. */
        uint64_t hash = meta->hashes[entry];
        uint32_t slots = meta->index->slots, slot = dict_home(hash, slots), step = 0;
        for (;;) {
            __m128i group = _mm_loadu_si128((const __m128i *)(meta->index->data + slot));
            unsigned hits = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(group, _mm_set1_epi8((char)(hash & 0x7f))));
            bool removed = false;
            while (hits) {
                uint32_t at = (slot + (unsigned)__builtin_ctz(hits)) & (slots - 1);
                if (dict_numbers(meta->index)[at] == (uint32_t)entry) {
                    dict_control(meta->index, at, DICT_DELETED);
                    removed = true;
                    break;
                }
                hits &= hits - 1;
            }
            if (removed) break;
            step += 16;
            slot = (slot + step) & (slots - 1);
        }
        meta->index->dead++;
    }
    dict_release_part(meta->desc, dict_entry(dict, (uint64_t)entry), true, true);
    memset(dict_entry(dict, (uint64_t)entry), 0, meta->desc->stride);
    meta->dead[(uint64_t)entry >> 3] |= (unsigned char)(1u << (entry & 7));
    dict->len--;
    return dict;
}

uint64_t myl_core_dict_entries(const myl_block *dict) { return dict_meta(dict)->elen; }
bool myl_core_dict_live(const myl_block *dict, uint64_t entry) { return dict_live(dict_meta(dict), entry); }
int64_t myl_core_dict_ordinal(const myl_block *dict, uint64_t ordinal) {
    core_dict_meta *meta = dict_meta(dict);
    if (!meta->dead) return (int64_t)ordinal;
    for (uint64_t i = 0; i < meta->elen; ++i)
        if (dict_live(meta, i) && ordinal-- == 0) return (int64_t)i;
    abort();
}

myl_block *myl_core_dict_copy(const myl_block *dict) {
    core_dict_meta *meta = dict_meta(dict);
    myl_block *copy = myl_core_dict_new((uint64_t)dict->cap, meta->desc);
    core_dict_meta *other = dict_meta(copy);
    copy->len = dict->len;
    other->elen = meta->elen;
    memcpy(block_data(copy), (const unsigned char *)dict + MYL_HEADER, (size_t)meta->elen * meta->desc->stride);
    memcpy(other->hashes, meta->hashes, (size_t)meta->elen * 8);
    if (meta->dead) {
        size_t bytes = ((size_t)dict->cap + 7) / 8;
        other->dead = malloc(bytes);
        if (!other->dead) out_of_memory();
        memcpy(other->dead, meta->dead, bytes);
    }
    if (meta->index) {
        size_t bytes = sizeof(core_dict_index) + ((meta->index->slots + 30u) & ~15u) + (size_t)meta->index->slots * 4;
        other->index = malloc(bytes);
        if (!other->index) out_of_memory();
        memcpy(other->index, meta->index, bytes);
    }
    if (meta->desc->layout) for (uint64_t i = 0; i < meta->elen; ++i) {
        if (!dict_live(meta, i)) continue;
        for (int32_t r = 0; r < meta->desc->layout[1]; ++r) {
            myl_block *child = reference_at(meta->desc->layout, dict_entry(copy, i), r);
            count_retain(child);
        }
    }
    return copy;
}

myl_block *myl_core_dict_clear(myl_block *dict) {
    core_dict_meta *meta = dict_meta(dict);
    for (uint64_t i = 0; i < meta->elen; ++i)
        if (dict_live(meta, i)) dict_release_part(meta->desc, dict_entry(dict, i), true, true);
    free(meta->dead);
    meta->dead = NULL;
    meta->elen = 0;
    dict->len = 0;
    if (meta->index) {
        memset(meta->index->data, DICT_EMPTY, (meta->index->slots + 30u) & ~15u);
        meta->index->used = meta->index->elen = meta->index->dead = 0;
    }
    return dict;
}

/* Join the existing iterative RC worklist; a dictionary of deeply nested
 * managed values uses no recursive teardown and frees its untracked index. */
static void core_dict_free_pending(myl_block *dict, myl_block **pending) {
    core_dict_meta *meta = dict_meta(dict);
    if (meta->desc->layout) for (uint64_t i = 0; i < meta->elen; ++i) {
        if (!dict_live(meta, i)) continue;
        for (int32_t r = 0; r < meta->desc->layout[1]; ++r) {
            myl_block *child = reference_at(meta->desc->layout, dict_entry(dict, i), r);
            if (count_release(child)) {
                child->cap = (int64_t)(intptr_t)*pending;
                *pending = child;
            }
        }
    }
    free(meta->index);
    free(meta->hashes);
    free(meta->dead);
    free(meta);
}

/* A borrowed text span hashes its octets on every use and never escapes. */
extern uint32_t myl_core_span_hash(const unsigned char *, uint64_t);
static bool dict_span_same(const myl_block *dict, uint64_t entry, const unsigned char *data, uint64_t length) {
    myl_block *text;
    memcpy(&text, dict_entry(dict, entry), sizeof text);
    return (uint64_t)text->len == length && memcmp(block_data(text), data, (size_t)length) == 0;
}
int64_t myl_core_dict_find_span(const myl_block *dict, const unsigned char *data, uint64_t length) {
    core_dict_meta *meta = dict_meta(dict);
    uint64_t hash = dict_hash_bits(myl_core_span_hash(data, length));
    if (!meta->index) {
        for (uint64_t entry = 0; entry < meta->elen; ++entry)
            if (dict_live(meta, entry) && meta->hashes[entry] == hash && dict_span_same(dict, entry, data, length)) return (int64_t)entry;
        return -1;
    }
    core_dict_index *index = meta->index;
    uint32_t pos = dict_home(hash, index->slots), step = 0, mask = index->slots - 1;
    for (;;) {
        __m128i controls = _mm_loadu_si128((const __m128i *)(index->data + pos));
        unsigned candidates = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(controls, _mm_set1_epi8((char)(hash & 0x7f))));
        while (candidates) {
            uint32_t slot = (pos + (unsigned)__builtin_ctz(candidates)) & mask;
            uint32_t entry = dict_numbers(index)[slot];
            if (meta->hashes[entry] == hash && dict_span_same(dict, entry, data, length)) return entry;
            candidates &= candidates - 1;
        }
        unsigned holes = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(controls, _mm_set1_epi8((char)DICT_EMPTY)));
        if (holes) return -(int64_t)(((pos + (unsigned)__builtin_ctz(holes)) & mask) + 1);
        step += 16;
        pos = (pos + step) & mask;
    }
}
