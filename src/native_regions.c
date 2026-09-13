/* Region allocation of ordinary managed objects. Every managed header carries
   the arena depth that owns it; depth 0 is the ordinary tracing heap and depth k
   is the k-th nested active `with arena()` scope. The invariant that an object
   never references an object of a younger arena is kept by a store barrier, so
   bulk release at scope exit frees a whole depth without tracing survivors. */
#include "native_regions.h"
#include <stdlib.h>
#include <string.h>
static void reach(const myl_native_type *type, const void *bytes, unsigned *deepest) {
    const unsigned char *raw = bytes;
    if (type->kind == MYL_NATIVE_POINTER) {
        void *pointer;
        memcpy(&pointer, raw, sizeof pointer);
        unsigned region = myl_native_object_region(pointer);
        if (region > *deepest) *deepest = region;
    } else if (type->kind == MYL_NATIVE_ARRAY) {
        for (size_t i = 0; i < type->count; ++i) reach(type->fields[0].type, raw + i * type->stride, deepest);
    } else if (type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT) {
        uint32_t tag = 0;
        if (type->kind == MYL_NATIVE_VARIANT) memcpy(&tag, raw, sizeof tag);
        for (size_t i = 0; i < type->field_count; ++i) {
            const myl_native_field *field = &type->fields[i];
            if (type->kind == MYL_NATIVE_RECORD || tag == field->tag)
                reach(field->type, raw + field->offset, deepest);
        }
    }
}
unsigned myl_native_region_reach(const myl_native_type *type, const void *value) {
    unsigned deepest = 0;
    reach(type, value, &deepest);
    return deepest;
}
int myl_native_region_check(myl_native_heap *heap, const void *container,
                            const myl_native_type *type, const void *value) {
    if (!heap->region_depth) return 1;
    return myl_native_region_reach(type, value) <= myl_native_object_region(container);
}
int myl_native_region_retains(myl_native_heap *heap, const myl_native_type *type, const void *value) {
    if (!heap->region_depth) return 0;
    return myl_native_region_reach(type, value) >= heap->region_depth;
}
/* One cloned managed object and the descriptor that shapes its contents. */
typedef struct { void *source, *clone; const myl_native_type *type; } Clone;
typedef struct {
    myl_native_heap *heap;
    unsigned dying;
    Clone *entries;
    size_t capacity, count;
    Clone *pending;
    size_t queued, reserved;
    int failed;
} Copier;
static size_t probe(const Clone *entries, size_t capacity, void *source) {
    size_t at = (size_t)(((uintptr_t)source >> 4) * (uintptr_t)0x9e3779b9u);
    at ^= at >> 13;
    at &= capacity - 1;
    while (entries[at].source && entries[at].source != source) at = (at + 1) & (capacity - 1);
    return at;
}
static int reserve(Copier *copier) {
    if (copier->capacity && copier->count * 2 < copier->capacity) return 1;
    size_t capacity = copier->capacity ? copier->capacity * 2 : 64;
    Clone *entries = calloc(capacity, sizeof *entries);
    if (!entries) return 0;
    for (size_t i = 0; i < copier->capacity; ++i)
        if (copier->entries[i].source) entries[probe(entries, capacity, copier->entries[i].source)] = copier->entries[i];
    free(copier->entries);
    copier->entries = entries;
    copier->capacity = capacity;
    return 1;
}
static int enqueue(Copier *copier, Clone item) {
    if (copier->queued == copier->reserved) {
        size_t reserved = copier->reserved ? copier->reserved * 2 : 32;
        Clone *pending = realloc(copier->pending, reserved * sizeof *pending);
        if (!pending) return 0;
        copier->pending = pending;
        copier->reserved = reserved;
    }
    copier->pending[copier->queued++] = item;
    return 1;
}
/* Allocate an empty clone with the source's shape in the enclosing region. */
static void *shallow(Copier *copier, const myl_native_type *type, void *source) {
    if (type->collection_kind == 3) {
        const myl_native_dictionary *from = source;
        return myl_native_dictionary_new(copier->heap, from->key, from->value, from->string_keys);
    }
    if (!type->collection_kind || type->collection_kind > 4) return NULL;
    const myl_native_list *from = source;
    myl_native_list *clone = myl_native_list_new(copier->heap, from->element, from->length);
    if (clone) clone->length = from->length;
    return clone;
}
static void *ensure(Copier *copier, const myl_native_type *type, void *source) {
    if (!source || myl_native_object_region(source) < copier->dying) return source;
    if (!reserve(copier)) { copier->failed = 1; return NULL; }
    size_t at = probe(copier->entries, copier->capacity, source);
    if (copier->entries[at].source) return copier->entries[at].clone;
    void *clone = shallow(copier, type, source);
    if (!clone) { copier->failed = 1; return NULL; }
    copier->entries[at] = (Clone){source, clone, type};
    copier->count++;
    if (!enqueue(copier, copier->entries[at])) copier->failed = 1;
    return clone;
}
static void patch(Copier *copier, const myl_native_type *type, void *bytes) {
    unsigned char *raw = bytes;
    if (type->kind == MYL_NATIVE_POINTER) {
        void *pointer;
        memcpy(&pointer, raw, sizeof pointer);
        void *clone = ensure(copier, type, pointer);
        memcpy(raw, &clone, sizeof clone);
    } else if (type->kind == MYL_NATIVE_ARRAY) {
        for (size_t i = 0; i < type->count; ++i) patch(copier, type->fields[0].type, raw + i * type->stride);
    } else if (type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT) {
        uint32_t tag = 0;
        if (type->kind == MYL_NATIVE_VARIANT) memcpy(&tag, raw, sizeof tag);
        for (size_t i = 0; i < type->field_count; ++i) {
            const myl_native_field *field = &type->fields[i];
            if (type->kind == MYL_NATIVE_RECORD || tag == field->tag)
                patch(copier, field->type, raw + field->offset);
        }
    }
}
static void translate(Copier *copier, const myl_native_type *type, const void *source, void *target) {
    if (type->size) memcpy(target, source, type->size);
    patch(copier, type, target);
}
static void fill_dictionary(Copier *copier, Clone item) {
    myl_native_dictionary *from = item.source, *clone = item.clone;
    size_t width = from->entry_type.size ? from->entry_type.size : 1;
    unsigned char *entry = malloc(width);
    if (!entry) { copier->failed = 1; return; }
    for (size_t i = 0; i < from->entries->length && !copier->failed; ++i) {
        const unsigned char *source = (const unsigned char *)from->entries->storage + i * from->entry_type.size;
        memcpy(entry, source, from->entry_type.size);
        patch(copier, item.type->key, entry);
        patch(copier, item.type->element, entry + from->value_offset);
        if (!myl_native_list_append(copier->heap, clone->entries, entry)) copier->failed = 1;
    }
    free(entry);
}
static void fill(Copier *copier, Clone item) {
    if (item.type->collection_kind == 3) return fill_dictionary(copier, item);
    myl_native_list *from = item.source, *clone = item.clone;
    size_t width = from->element->size;
    for (size_t i = 0; i < from->length && !copier->failed; ++i)
        translate(copier, item.type->element, (const unsigned char *)from->storage + i * width,
                  (unsigned char *)clone->storage + i * width);
}
int myl_native_region_escape(myl_native_heap *heap, const myl_native_type *type,
                             const void *value, void *output) {
    if (!heap->region_depth) {
        if (type->size) memcpy(output, value, type->size);
        return 1;
    }
    Copier copier = {.heap = heap, .dying = heap->region_depth};
    int suspended = heap->suspended;
    heap->suspended = 1;
    heap->region_depth = copier.dying - 1;
    translate(&copier, type, value, output);
    for (size_t i = 0; i < copier.queued && !copier.failed; ++i) fill(&copier, copier.pending[i]);
    heap->region_depth = copier.dying;
    heap->suspended = suspended;
    heap->arena.escaped += copier.count;
    int done = !copier.failed;
    free(copier.entries);
    free(copier.pending);
    if (!done && type->size) memset(output, 0, type->size);
    return done;
}
