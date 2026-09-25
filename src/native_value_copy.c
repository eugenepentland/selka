/* Value-semantics copies (VALUE-SEMANTICS-2, stage 3a of D9).
 *
 * `myl_qbe_value_copy` is the one runtime entry the native emitter calls
 * wherever value semantics needs a real copy (`qbe_value_copy.zig`). It copies
 * the value at `value` into `output` and then replaces every list, dict, set
 * and byte string the copy reaches through its descriptor with a fresh copy
 * of its own, element by element, so the result shares no writable collection
 * with its source. `str`, `class` bodies and Cells are shared: text is
 * immutable, and a class stays a reference in this stage. With `children`
 * set the outer collection is already fresh (a shallow copy, slice or
 * concatenation) and only its elements are copied.
 *
 * Copies allocate wherever an ordinary allocation would, the innermost open
 * arena included. The copy is made top-down in place: `output` is rooted with
 * the value's descriptor, and every clone is stored into `output` (or into a
 * clone `output` already reaches) before the next allocation, so a collection
 * during the copy sees the original until it is replaced and the clone after.
 *
 * Stage 3b replaces this entry with copy-on-write. */
#include "native_bytes.h"
#include "native_collections.h"
#include "native_dictionary.h"
#include "native_value_copy.h"
#include "qbe_runtime.h"
#include <string.h>

typedef struct {
    myl_native_heap *heap;
    int failed;
} myl_value_copier;

static void copy_value(myl_value_copier *, unsigned char *, const myl_native_type *);

static void copy_list_elements(myl_value_copier *copier, myl_native_list *list) {
    const myl_native_type *element = list->element;
    if (!element || element->trace_mode == MYL_NATIVE_TRACE_NONE) return;
    for (size_t i = 0; i < list->length && !copier->failed; ++i)
        copy_value(copier, (unsigned char *)list->storage + i * element->size, element);
}

static void copy_dictionary_values(myl_value_copier *copier, myl_native_dictionary *dictionary) {
    const myl_native_type *value = dictionary->value;
    if (!value || value->trace_mode == MYL_NATIVE_TRACE_NONE || !dictionary->entries) return;
    myl_native_list *entries = dictionary->entries;
    for (size_t i = 0; i < entries->length && !copier->failed; ++i)
        copy_value(copier, (unsigned char *)entries->storage + i * dictionary->entry_type.size + dictionary->value_offset, value);
}

/* Replace the collection the pointer at `slot` names with a fresh copy, then
 * copy that copy's elements. Text, class bodies and Cells are shared. */
static void copy_pointer(myl_value_copier *copier, unsigned char *slot, const myl_native_type *type) {
    void *pointer;
    memcpy(&pointer, slot, sizeof pointer);
    if (!pointer) return;
    /* Collection kind 4 is both the immutable `bytes` and the mutable
     * `byte_buffer`; a descriptor does not tell them apart, so both are
     * copied, which no program can observe for the immutable one. */
    if (type->collection_kind == 1 || type->collection_kind == 4) {
        myl_native_list *from = pointer;
        myl_native_list *clone = from->element ? myl_native_list_copy(copier->heap, from) : myl_native_bytes_copy(copier->heap, from);
        if (!clone) {
            copier->failed = 1;
            return;
        }
        memcpy(slot, &clone, sizeof clone);
        copy_list_elements(copier, clone);
    } else if (type->collection_kind == 3) {
        myl_native_dictionary *clone = myl_native_dictionary_copy(copier->heap, pointer);
        if (!clone) {
            copier->failed = 1;
            return;
        }
        memcpy(slot, &clone, sizeof clone);
        copy_dictionary_values(copier, clone);
    }
}

static void copy_value(myl_value_copier *copier, unsigned char *slot, const myl_native_type *type) {
    if (copier->failed || type->trace_mode == MYL_NATIVE_TRACE_NONE) return;
    const myl_native_field *fields = type->trace_mode == MYL_NATIVE_TRACE_FIELDS ? type->trace_fields : type->fields;
    size_t count = type->trace_mode == MYL_NATIVE_TRACE_FIELDS ? type->trace_field_count : type->field_count;
    if (type->kind == MYL_NATIVE_POINTER) {
        copy_pointer(copier, slot, type);
    } else if (type->kind == MYL_NATIVE_ARRAY) {
        for (size_t i = 0; i < type->count && !copier->failed; ++i) copy_value(copier, slot + i * type->stride, fields[0].type);
    } else if (type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT) {
        uint32_t tag = 0;
        if (type->kind == MYL_NATIVE_VARIANT) memcpy(&tag, slot, sizeof tag);
        for (size_t i = 0; i < count && !copier->failed; ++i)
            if (type->kind == MYL_NATIVE_RECORD || fields[i].tag == tag) copy_value(copier, slot + fields[i].offset, fields[i].type);
    }
}

/* Copy only the elements of a collection that is already fresh. */
static void copy_children(myl_value_copier *copier, unsigned char *slot, const myl_native_type *type) {
    if (type->kind != MYL_NATIVE_POINTER) return copy_value(copier, slot, type);
    void *pointer;
    memcpy(&pointer, slot, sizeof pointer);
    if (!pointer) return;
    if (type->collection_kind == 1) copy_list_elements(copier, pointer);
    else if (type->collection_kind == 3) copy_dictionary_values(copier, pointer);
}

int myl_qbe_value_copy(void *context, const myl_native_type *type, const void *value, void *output, uint32_t children) {
    myl_native_heap *heap = myl_qbe_heap(context);
    if (output != value) memmove(output, value, type->size);
    myl_value_copier copier = {.heap = heap, .failed = 0};
    myl_native_root root;
    myl_native_root_push(heap, &root, output, type);
    if (children) copy_children(&copier, output, type);
    else copy_value(&copier, output, type);
    myl_native_root_pop(heap, &root);
    if (!copier.failed) return 1;
    myl_qbe_fail_allocation(context);
    return 0;
}
