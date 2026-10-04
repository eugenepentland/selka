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
 * and is dropped by every change that could insert, move or remove a key.
 * A described slice (`myl_native_dictionary_read_range`) is recorded under
 * states of its own: `key` holds the text it ranges over and `offset` and
 * `bytes` the span, so the record nominates only that same query; an absence
 * also carries `epoch`, the heap's collection count, so it applies only while
 * that text cannot have been reclaimed and its address reused. */
/* A found ordinary probe publishes only key, entry and state. Other fields may
 * retain an earlier probe's bytes and are read only under their own state. */
typedef struct {
    uint64_t key;
    size_t entry;
    uint32_t slot, hash;
    unsigned state;
    size_t offset, bytes, epoch;
} myl_native_dictionary_probe;
typedef struct {
    myl_native_list *entries;
    const myl_native_type *key, *value;
    size_t value_offset;
    int string_keys;
    /* How keys hash and compare, fixed from the key type at creation: a text,
     * one eight-byte word, a narrower scalar, wider plain bytes, or a
     * structured value (a record, tuple, union, domain, fixed array, `bytes` or
     * a value holding a `str`) walked through its descriptor (HASH-KEYS-1). */
    unsigned key_kind;
    /* Entries removed from the middle of the entry list whose bytes still sit
     * there (DICT-REMOVE-1). The index names only live entries, so a removal is
     * one table deletion; `myl_native_dictionary_settle` squeezes the dead
     * entries out before anything reads the entry list by position. Nonzero only
     * while the dictionary carries an index, and the last entry is always live. */
    size_t dead;
    myl_native_type entry_type;
    myl_native_field entry_fields[2];
    myl_native_dictionary_index index;
    /* A read-modify-write probes one key twice in a row — a read immediately
     * followed by a write of the same key — so the second probe answers from
     * this record instead of another hash, table walk and key comparison. */
    myl_native_dictionary_probe last;
    /* The scan plan of `entry_type`, built with it when the dictionary is
     * created and named by its `scan` (GC-SCAN-PLAN-1): it lives and dies with
     * the dictionary, so a dictionary later built at this address builds the
     * plan of its own entries. An entry with more reference slots than this
     * holds has no plan and is traced by the collector's recursive walk. Two
     * slots keep the dictionary in its 320-byte size class. */
    myl_native_scan_entry entry_scan[2];
} myl_native_dictionary;
myl_native_dictionary *myl_native_dictionary_new(myl_native_heap *, const myl_native_type *key, const myl_native_type *value, int string_keys);
size_t myl_native_dictionary_length(const myl_native_dictionary *);
int myl_native_dictionary_contains(const myl_native_dictionary *, const void *key);
/* Read returns zero for missing key, preserving output. Write returns zero on
 * allocation failure without altering entries or insertion order. */
int myl_native_dictionary_read(const myl_native_dictionary *, const void *key, void *output);
/* A plain word-key/value read, retaining the full read for other shapes. It
 * allocates nothing, writes the ordinary probe hint, and leaves output on miss. */
int myl_native_dictionary_read_word(const myl_native_dictionary *, const void *key, void *output);
int myl_native_dictionary_write(myl_native_heap *, myl_native_dictionary *, const void *key, const void *value);
/* The half of `write` that allocates nothing: the value of a key already present
 * is replaced and 1 answered; an absent key answers 0 and changes nothing, so
 * generated code calls `write` — and links its roots — only for a new key
 * (DICT-OVERWRITE-1). A miss is recorded exactly as a lookup's is. */
int myl_native_dictionary_overwrite(myl_native_dictionary *, const void *key, const void *value);
/* `read`, `contains`, `overwrite` and `write` of a `str`-keyed dictionary whose
 * key is the slice `span` of `text`, which is never built (DICT-RANGE-KEY-1).
 * A lookup hashes and compares the octets in place, so it allocates nothing;
 * `write` allocates an owned key, in the dictionary's own region, only when the
 * key is new. Every answer is the one the built slice would get: the stored
 * keys, their order and their hashes are exactly those a `write` of the slice
 * would leave. The heap is read, never changed, by the lookups: it dates the
 * absence they record, which lets the `write` of a read-modify-write skip its
 * walk. */
int myl_native_dictionary_read_range(const myl_native_heap *, const myl_native_dictionary *, const myl_native_text *text, const myl_native_text_span *span, void *output);
int myl_native_dictionary_contains_range(const myl_native_heap *, const myl_native_dictionary *, const myl_native_text *text, const myl_native_text_span *span);
int myl_native_dictionary_overwrite_range(const myl_native_heap *, myl_native_dictionary *, const myl_native_text *text, const myl_native_text_span *span, const void *value);
int myl_native_dictionary_write_range(myl_native_heap *, myl_native_dictionary *, myl_native_text *text, const myl_native_text_span *span, const void *value);
myl_native_list *myl_native_dictionary_snapshot(myl_native_heap *, myl_native_dictionary *, int keys);
/* Borrow the next live key/value pair without moving RC entry storage. Start
 * cursor at zero; it advances through physical rows in insertion order. */
int myl_native_dictionary_next(const myl_native_dictionary *, size_t *cursor, const void **key, const void **value);
/* Insertion-order reads return zero outside the live entry range and preserve
 * output. They are internal iteration primitives, not source-level methods. */
int myl_native_dictionary_key_at(const myl_native_dictionary *, size_t index, void *output);
int myl_native_dictionary_value_at(const myl_native_dictionary *, size_t index, void *output);
/* Python-shaped dictionary methods. `pop` removes a matching entry and answers 1
 * found or 0 absent; `update`/`setdefault` may allocate and answer 0 on refusal.
 * `pop` takes its key's slot out of the table and leaves the entry's bytes for
 * `settle` (DICT-REMOVE-1), so it is expected constant time and allocates
 * nothing; a dictionary without a table shifts later entries down instead. */
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
/* Whether `payload` is a dictionary or set header, read from its object header. */
int myl_native_dictionary_header(const void *payload);
/* A fresh dictionary with `input`'s entries in `input`'s order, allocated with
 * its entry list and index at arena depth `region` (COW-UNIQUE-1). `input` is
 * settled first; the settled entries and the index slots naming them are
 * copied as they are, so no key is hashed or compared again. A refused table
 * leaves the copy answering lookups by scanning. The copy's copy-on-write
 * flags are clear; nothing inside the entries is marked. NULL on refusal. */
myl_native_dictionary *myl_native_dictionary_clone_at(myl_native_heap *, const myl_native_dictionary *input, unsigned region);
/* Squeeze removed entries out of the entry list, keeping the live ones in
 * insertion order and renumbering their index slots in place. It allocates
 * nothing and is a no-op when nothing was removed. Every reader of `entries`
 * by raw position must first settle or use the stable live-entry cursor. */
void myl_native_dictionary_settle(const myl_native_dictionary *);
/* The stored value for a key, or NULL when the key is absent: the lookup the
 * structural equality of two dictionaries asks for each entry. */
const void *myl_native_dictionary_find(const myl_native_dictionary *, const void *key);
/* `find` for the key a described slice names (DICT-RANGE-KEY-1): the stored
 * value's address, or NULL when the key is absent. Copy on write writes a
 * copied value back through it (COW-NESTED-1). */
const void *myl_native_dictionary_find_range(const myl_native_heap *, const myl_native_dictionary *, const myl_native_text *text, const myl_native_text_span *span);
/* Remove the most recently inserted live entry, copying its key to `output`;
 * zero when the dictionary is empty. A set's `pop` (SET-1). */
int myl_native_dictionary_pop_last(myl_native_dictionary *, void *output);
#endif
