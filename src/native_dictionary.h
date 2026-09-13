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
int myl_native_dictionary_key_at(const myl_native_dictionary *, size_t index, void *output);
#endif
