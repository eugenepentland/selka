#ifndef MYLANG_NATIVE_DICTIONARY_H
#define MYLANG_NATIVE_DICTIONARY_H
#include "native_text.h"
typedef struct {
    myl_native_list *entries;
    const myl_native_type *key, *value;
    size_t value_offset;
    int string_keys;
    myl_native_type entry_type;
    myl_native_field entry_fields[2];
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
 * found or 0 absent; `update`/`setdefault` may allocate and answer 0 on refusal. */
int myl_native_dictionary_pop(myl_native_dictionary *, const void *key, void *output);
int myl_native_dictionary_update(myl_native_heap *, myl_native_dictionary *, const myl_native_dictionary *source);
int myl_native_dictionary_setdefault(myl_native_heap *, myl_native_dictionary *, const void *key, const void *fallback, void *output);
void myl_native_dictionary_clear(myl_native_dictionary *);
myl_native_dictionary *myl_native_dictionary_copy(myl_native_heap *, const myl_native_dictionary *input);
#endif
