#ifndef MYLANG_NATIVE_DICTIONARY_H
#define MYLANG_NATIVE_DICTIONARY_H
#include "native_text.h"
/* Open-addressing hash index over the insertion-ordered entry list. A slot packs
 * the key's 32-bit hash above one past an entry index, so zero means empty and a
 * probe compares the stored hash before it loads the entry it names — a
 * mismatch skips the entry, and a table grows or loses an entry without
 * rehashing a single key. `capacity` is a power of two and a zero capacity means
 * the dictionary carries no index and every lookup scans. `slots` is an untraced
 * managed block owned by the dictionary's own region, so the collector keeps it
 * alive through the dictionary and an arena releases the two together. Nothing
 * outside native_dictionary.c may append to `entries`: the index names entry
 * positions and only this module keeps it in step. */
typedef struct {
    uint64_t *slots;
    size_t capacity;
} myl_native_dictionary_index;
/* One past the entry index a slot names, or zero for an empty slot. */
#define MYL_NATIVE_DICTIONARY_SLOT_ENTRY(slot) ((size_t)((slot)&0xffffffffu))
/* Where the last probe landed, and on which key. `key` holds a text key's object
 * pointer or a scalar key's bytes; `state` says whether the probe found `entry`
 * or found the key absent with `slot` the empty slot a write would fill. The
 * record is a hint, never an answer: a found entry is revalidated against the
 * live entry list, and an absence is recorded only for keys compared by value
 * and is dropped by every change that could insert, move or remove a key. */
typedef struct {
    uint64_t key;
    size_t entry;
    uint32_t slot, hash;
    unsigned state;
} myl_native_dictionary_probe;
typedef struct {
    myl_native_list *entries;
    const myl_native_type *key, *value;
    size_t value_offset;
    int string_keys;
    /* How keys hash and compare, fixed from the key type at creation: a text,
     * one eight-byte word, a narrower scalar, or wider bytes (only from C). */
    unsigned key_kind;
    myl_native_type entry_type;
    myl_native_field entry_fields[2];
    myl_native_dictionary_index index;
    /* A read-modify-write probes one key twice in a row — a read immediately
     * followed by a write of the same key — so the second probe answers from
     * this record instead of another hash, table walk and key comparison. */
    myl_native_dictionary_probe last;
} myl_native_dictionary;
myl_native_dictionary *myl_native_dictionary_new(myl_native_heap *, const myl_native_type *key, const myl_native_type *value, int string_keys);
size_t myl_native_dictionary_length(const myl_native_dictionary *);
int myl_native_dictionary_contains(const myl_native_dictionary *, const void *key);
/* Read returns zero for missing key, preserving output. Write returns zero on
 * allocation failure without altering entries or insertion order. */
int myl_native_dictionary_read(const myl_native_dictionary *, const void *key, void *output);
int myl_native_dictionary_write(myl_native_heap *, myl_native_dictionary *, const void *key, const void *value);
myl_native_list *myl_native_dictionary_snapshot(myl_native_heap *, myl_native_dictionary *, int keys);
/* Insertion-order reads return zero outside the live entry range and preserve
 * output. They are internal iteration primitives, not source-level methods. */
int myl_native_dictionary_key_at(const myl_native_dictionary *, size_t index, void *output);
int myl_native_dictionary_value_at(const myl_native_dictionary *, size_t index, void *output);
/* Python-shaped dictionary methods. `pop` removes a matching entry and answers 1
 * found or 0 absent; `update`/`setdefault` may allocate and answer 0 on refusal.
 * `pop` shifts every later entry down, so it also renumbers the index in place,
 * without allocating or rehashing, and is the one operation that stays linear
 * in the dictionary's size. */
int myl_native_dictionary_pop(myl_native_dictionary *, const void *key, void *output);
int myl_native_dictionary_update(myl_native_heap *, myl_native_dictionary *, const myl_native_dictionary *source);
int myl_native_dictionary_setdefault(myl_native_heap *, myl_native_dictionary *, const void *key, const void *fallback, void *output);
void myl_native_dictionary_clear(myl_native_dictionary *);
/* Size and refill the index from the entry list. The one caller is the arena
 * escape copier, which appends entries whose managed keys are still empty shells
 * and so cannot be hashed until every clone is filled. A refused table leaves the
 * dictionary answering lookups by scanning, which is slower and just as correct. */
void myl_native_dictionary_reindex(myl_native_heap *, myl_native_dictionary *);
myl_native_dictionary *myl_native_dictionary_copy(myl_native_heap *, const myl_native_dictionary *input);
#endif
