/* Region allocation of ordinary managed objects. Every managed header carries
   the arena depth that owns it; depth 0 is the ordinary tracing heap and depth k
   is the k-th nested active `with arena()` scope. The invariant that an object
   never references an object of a younger arena is kept by a store barrier, so
   bulk release at scope exit frees a whole depth without tracing survivors. */
#include "native_regions.h"
#include "native_rc_values.h"
#include <stdlib.h>
#include <string.h>
static void reach(const myl_native_heap *heap, const myl_native_type *type,
                  const void *bytes, unsigned *deepest) {
    const unsigned char *raw = bytes;
    if (type->kind == MYL_NATIVE_POINTER) {
        void *pointer;
        memcpy(&pointer, raw, sizeof pointer);
        unsigned region = pointer ? myl_native_header_region(pointer) : 0;
        if (region > *deepest) *deepest = region;
    } else if (type->kind == MYL_NATIVE_ARRAY) {
        for (size_t i = 0; i < type->count; ++i) reach(heap, type->fields[0].type, raw + i * type->stride, deepest);
    } else if (type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT) {
        uint32_t tag = 0;
        if (type->kind == MYL_NATIVE_VARIANT) memcpy(&tag, raw, sizeof tag);
        for (size_t i = 0; i < type->field_count; ++i) {
            const myl_native_field *field = &type->fields[i];
            if (type->kind == MYL_NATIVE_RECORD || tag == field->tag)
                reach(heap, field->type, raw + field->offset, deepest);
        }
    }
}
unsigned myl_native_region_reach(const myl_native_heap *heap,
                                 const myl_native_type *type, const void *value) {
    unsigned deepest = 0;
    reach(heap, type, value, &deepest);
    return deepest;
}
int myl_native_region_check(myl_native_heap *heap, const void *container,
                            const myl_native_type *type, const void *value) {
    if (!heap->region_depth) return 1;
    /* No live object is younger than the innermost open arena, so a container
     * that already lives there accepts every value without walking it. */
    unsigned owner = container ? myl_native_header_region(container) : 0;
    if (owner >= heap->region_depth) return 1;
    return myl_native_region_reach(heap, type, value) <= owner;
}
int myl_native_region_retains(myl_native_heap *heap, const myl_native_type *type, const void *value) {
    if (!heap->region_depth) return 0;
    return myl_native_region_reach(heap, type, value) >= heap->region_depth;
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
/* Element count of an arena payload's header: every object the copier clones
   lives in the dying arena, so its count sits between the flag bits and the
   arena depth. */
static size_t arena_count(const myl_native_object *header) {
    return (size_t)(header->mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT) & MYL_NATIVE_ARENA_COUNT_MAX;
}
/* Allocate an empty clone with the source's shape in the enclosing region. */
static void *shallow(Copier *copier, const myl_native_type *type, void *source) {
    if (type->collection_kind == 3) {
        const myl_native_dictionary *from = source;
        return myl_native_dictionary_new(copier->heap, from->key, from->value, from->string_keys);
    }
    /* A text's payload is UTF-8 octets with no pointer to patch, so the clone is
       the whole value: one allocation in the enclosing region and nothing left
       for `fill` to walk. */
    if (type->collection_kind == 2) return myl_native_text_clone(copier->heap, source);
    /* A `class` body (or a Cell) has no collection header: its pointer
       descriptor is opaque, and the shape lives in the payload's own header —
       the body descriptor and its element count. The clone is an ordinary
       allocation of that shape in the enclosing region, so it gets the same
       header, age and barrier descriptor (`cell`) a constructor would give it:
       a fresh tracing-heap object is young, and `fill` writes its fields
       before anything can observe it, so no store barrier is owed. */
    /* A box (RECURSIVE-VALUES-2) is a one-field record body like a class's, so
       it is cloned the same way; the copy is the enclosing region's own box. */
    if (!type->collection_kind || type->collection_kind == 5) {
        const myl_native_object *header = (const myl_native_object *)source - 1;
        if (!header->element) return NULL;
        return myl_native_heap_alloc(copier->heap, header->element, arena_count(header));
    }
    if (type->collection_kind > 4) return NULL;
    const myl_native_list *from = source;
    myl_native_list *clone = myl_native_list_new(copier->heap, from->element, from->length);
    if (clone) clone->length = from->length;
    return clone;
}
static void *ensure(Copier *copier, const myl_native_type *type, void *source) {
    if (!source || myl_native_object_region(copier->heap, source) < copier->dying) return source;
    if (!reserve(copier)) { copier->failed = 1; return NULL; }
    size_t at = probe(copier->entries, copier->capacity, source);
    if (copier->entries[at].source) return copier->entries[at].clone;
    void *clone = shallow(copier, type, source);
    if (!clone) { copier->failed = 1; return NULL; }
    /* COW-SHARED-1: every reference to a shared source becomes a reference to
     * this one clone, so the clone is shared exactly when its source was. */
    if (((const myl_native_object *)source - 1)->mark & MYL_NATIVE_OBJECT_SHARED)
        ((myl_native_object *)clone - 1)->mark |= MYL_NATIVE_OBJECT_SHARED;
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
    /* Removed entries still sit in the source's entry list until it settles. */
    myl_native_dictionary_settle(from);
    size_t width = from->entry_type.size ? from->entry_type.size : 1;
    unsigned char *entry = malloc(width);
    if (!entry) { copier->failed = 1; return; }
    for (size_t i = 0; i < from->entries->length && !copier->failed; ++i) {
        const unsigned char *source = (const unsigned char *)from->entries->storage + i * from->entry_type.size;
        memcpy(entry, source, from->entry_type.size);
        patch(copier, item.type->key, entry);
        patch(copier, item.type->element, entry + from->value_offset);
        /* Appended straight onto the entry list, never through the dictionary's
           own write: a cloned `str` key is still an empty shell at this point, so
           key equality and key hashes are not yet meaningful. The clone's index is
           built once every clone is filled, by reindex below. */
        if (!myl_native_list_append(copier->heap, clone->entries, entry)) copier->failed = 1;
    }
    free(entry);
}
static void fill(Copier *copier, Clone item) {
    if (item.type->collection_kind == 3) return fill_dictionary(copier, item);
    if (item.type->collection_kind == 2) return;
    if (!item.type->collection_kind || item.type->collection_kind == 5) {
        const myl_native_object *header = (const myl_native_object *)item.source - 1;
        const myl_native_type *body = header->element;
        size_t count = arena_count(header);
        for (size_t i = 0; i < count && !copier->failed; ++i)
            translate(copier, body, (const unsigned char *)item.source + i * body->size,
                      (unsigned char *)item.clone + i * body->size);
        return;
    }
    myl_native_list *from = item.source, *clone = item.clone;
    size_t width = from->element->size;
    for (size_t i = 0; i < from->length && !copier->failed; ++i)
        translate(copier, item.type->element, (const unsigned char *)from->storage + i * width,
                  (unsigned char *)clone->storage + i * width);
}
int myl_native_region_escape(myl_native_heap *heap, const myl_native_type *type,
                             const void *value, void *output) {
    if (myl_rc_enabled(heap)) {
        const myl_rc_shape *shape = myl_rc_native_shape(heap, type);
        if (!shape) return 0;
        myl_rc_slot source = {.shape = shape, .address = (void *)value};
        myl_rc_slot destination = {.shape = shape, .address = output, .region = heap->region_depth ? heap->region_depth - 1 : 0};
        myl_rc_status status = myl_rc_region_escape(heap, &destination, &source);
        if (status != MYL_RC_OK) myl_rc_record_failure(heap, status);
        return status == MYL_RC_OK;
    }
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
    /* Only now does every cloned key hold its final contents, so this is the
       first point at which a cloned dictionary can hash its own keys. */
    for (size_t i = 0; i < copier.queued && !copier.failed; ++i)
        if (copier.pending[i].type->collection_kind == 3)
            myl_native_dictionary_reindex(heap, copier.pending[i].clone);
    heap->region_depth = copier.dying;
    heap->suspended = suspended;
    heap->arena.escaped += copier.count;
    int done = !copier.failed;
    free(copier.entries);
    free(copier.pending);
    if (!done && type->size) memset(output, 0, type->size);
    return done;
}
