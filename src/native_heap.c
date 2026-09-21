#define _POSIX_C_SOURCE 200809L
#include "native_heap.h"
#include "native_arena.h"
#include <stdlib.h>
#include <string.h>
#include <stdalign.h>
#include <limits.h>
#include <sys/resource.h>
#if defined(__SANITIZE_ADDRESS__) || defined(__SANITIZE_THREAD__)
#define MYL_NATIVE_SANITIZED 1
#elif defined(__has_feature)
#if __has_feature(address_sanitizer) || __has_feature(thread_sanitizer) || __has_feature(memory_sanitizer)
#define MYL_NATIVE_SANITIZED 1
#endif
#endif
#ifndef MYL_NATIVE_SANITIZED
#define MYL_NATIVE_SANITIZED 0
#endif
/* The two-word header is a memory-layout contract: the payload behind it must
 * stay aligned to `max_align_t`, and the collector adds its size back to
 * recover an object's byte charge. */
_Static_assert(sizeof(myl_native_object) == 2 * sizeof(uintptr_t), "managed object header is two words");
_Static_assert(sizeof(myl_native_object) % _Alignof(max_align_t) == 0, "managed object header preserves payload alignment");
int myl_native_budget_parse(const char *text, size_t *out) {
    size_t value = 0, scale = 1;
    const char *cursor = text;
    if (!text || !out) return 0;
    for (; *cursor >= '0' && *cursor <= '9'; ++cursor) {
        size_t digit = (size_t)(*cursor - '0');
        if (value > (SIZE_MAX - digit) / 10) return 0;
        value = value * 10 + digit;
    }
    if (cursor == text) return 0;
    if (*cursor == 'K' || *cursor == 'k') scale = ((size_t)1) << 10;
    else if (*cursor == 'M' || *cursor == 'm') scale = ((size_t)1) << 20;
    else if (*cursor == 'G' || *cursor == 'g') scale = ((size_t)1) << 30;
    else if (*cursor) return 0;
    if (*cursor && cursor[1]) return 0;
    if (value > SIZE_MAX / scale) return 0;
    *out = value * scale;
    return 1;
}
size_t myl_native_budget_environment(int *valid) {
    const char *text = getenv(MYL_NATIVE_BUDGET_VARIABLE);
    size_t value = 0;
    if (valid) *valid = 1;
    if (!text || !*text) return 0;
    if (myl_native_budget_parse(text, &value)) return value;
    if (valid) *valid = 0;
    return 0;
}
int myl_native_budget_guard(size_t budget) {
    struct rlimit ceiling;
    rlim_t wanted;
    if (MYL_NATIVE_SANITIZED || !budget) return 0;
    if (budget > SIZE_MAX - MYL_NATIVE_BUDGET_HEADROOM) return 0;
    if (getrlimit(RLIMIT_AS, &ceiling)) return 0;
    wanted = (rlim_t)(budget + MYL_NATIVE_BUDGET_HEADROOM);
    if (ceiling.rlim_max != RLIM_INFINITY && wanted > ceiling.rlim_max) wanted = ceiling.rlim_max;
    if (ceiling.rlim_cur != RLIM_INFINITY && ceiling.rlim_cur <= wanted) return 0;
    ceiling.rlim_cur = wanted;
    return setrlimit(RLIMIT_AS, &ceiling) == 0;
}
unsigned myl_native_object_region(const myl_native_heap *heap, const void *payload) {
    return payload ? myl_native_arena_region(heap, payload) : 0;
}
const myl_native_type *myl_native_object_element(const myl_native_heap *heap, const void *payload) {
    if (!payload) return NULL;
    if (myl_native_arena_region(heap, payload)) return myl_native_arena_element(heap, payload);
    return ((const myl_native_object *)payload - 1)->element;
}
int myl_native_object_immortal(const myl_native_heap *heap, const void *payload) {
    if (!payload || myl_native_arena_region(heap, payload)) return 0;
    return (((const myl_native_object *)payload - 1)->mark & MYL_NATIVE_OBJECT_IMMORTAL) != 0;
}
/* Element count recovered from the mark word's high bits. */
static size_t object_count(const myl_native_object *object) {
    return (size_t)(object->mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT);
}
/* Reserve room for one more row in the collector's sweep array. */
static int reserve_object(myl_native_heap *heap) {
    if (heap->objects_len < heap->objects_capacity) return 1;
    size_t capacity = heap->objects_capacity ? heap->objects_capacity * 2 : 64;
    if (capacity <= heap->objects_capacity) return 0;
    if (capacity > SIZE_MAX / sizeof *heap->objects) return 0;
    myl_native_object_slot *grown = realloc(heap->objects, capacity * sizeof *grown);
    if (!grown) return 0;
    heap->objects = grown;
    heap->objects_capacity = capacity;
    return 1;
}
/* Append one marked object to the collector's worklist, growing it on demand.
 * A refused reservation is reported so the collection can abandon unmarked. */
static int worklist_push(myl_native_heap *heap, myl_native_object *object) {
    if (heap->pending_len == heap->pending_capacity) {
        size_t capacity = heap->pending_capacity ? heap->pending_capacity * 2 : 1024;
        if (capacity <= heap->pending_capacity) return 0;
        myl_native_object **grown = realloc(heap->pending, capacity * sizeof *grown);
        if (!grown) return 0;
        heap->pending = grown;
        heap->pending_capacity = capacity;
    }
    heap->pending[heap->pending_len++] = object;
    return 1;
}
int myl_native_region_begin(myl_native_heap *heap) {
    if (heap->region_depth == UINT_MAX) return 0;
    heap->region_depth++;
    heap->arena.scopes++;
    return 1;
}
void myl_native_region_end(myl_native_heap *heap) {
    if (!heap->region_depth) return;
    myl_native_arena_release(heap, heap->region_depth);
    heap->region_depth--;
}
static void trace(myl_native_heap *, const myl_native_type *, const void *);
static void mark(myl_native_heap *heap, void *payload) {
    if (!payload) return;
    /* Region storage is retained wholesale. Its outgoing GC edges are scanned
     * once separately, so arena cycles never enter the collector's work list. */
    if (myl_native_arena_region(heap, payload)) return;
    myl_native_object *object = (myl_native_object *)payload - 1;
    /* Immortal payloads live in the image, not the heap: they can never be
     * collected, so re-tracing one would only queue static storage. */
    if (object->mark & (MYL_NATIVE_OBJECT_MARKED | MYL_NATIVE_OBJECT_IMMORTAL)) return;
    if (!worklist_push(heap, object)) { heap->scratch_failed = 1; return; }
    object->mark |= MYL_NATIVE_OBJECT_MARKED;
}
static void trace(myl_native_heap *heap, const myl_native_type *type, const void *address) {
    const unsigned char *bytes = address;
    if (type->trace_mode == MYL_NATIVE_TRACE_NONE) return;
    if (type->kind == MYL_NATIVE_POINTER || type->kind == MYL_NATIVE_OWNED_BUFFER || type->kind == MYL_NATIVE_OWNED_POOL) {
        void *pointer;
        memcpy(&pointer, bytes, sizeof(pointer));
        mark(heap, pointer);
    } else if (type->kind == MYL_NATIVE_ARRAY) {
        const myl_native_field *fields = type->trace_mode == MYL_NATIVE_TRACE_FIELDS ? type->trace_fields : type->fields;
        for (size_t i = 0; i < type->count; ++i)
            trace(heap, fields[0].type, bytes + i * type->stride);
    } else if (type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT) {
        const myl_native_field *fields = type->trace_mode == MYL_NATIVE_TRACE_FIELDS ? type->trace_fields : type->fields;
        size_t field_count = type->trace_mode == MYL_NATIVE_TRACE_FIELDS ? type->trace_field_count : type->field_count;
        uint32_t tag = 0;
        if (type->kind == MYL_NATIVE_VARIANT) memcpy(&tag, bytes, sizeof(tag));
        for (size_t i = 0; i < field_count; ++i) {
            const myl_native_field *field = &fields[i];
            if (type->kind == MYL_NATIVE_RECORD || tag == field->tag)
                trace(heap, field->type, bytes + field->offset);
        }
    }
}
void myl_native_heap_init(myl_native_heap *heap, size_t limit) {
    memset(heap, 0, sizeof(*heap));
    heap->limit = limit;
    heap->next_pool_identity = 1;
    heap->next_collection = 1u << 20;
}
void myl_native_root_push(myl_native_heap *heap, myl_native_root *root,
                          void *address, const myl_native_type *type) {
    root->previous = heap->roots;
    root->address = address;
    root->type = type;
    heap->roots = root;
}
int myl_native_root_pop(myl_native_heap *heap, myl_native_root *root) {
    if (heap->roots != root) return 0;
    heap->roots = root->previous;
    return 1;
}
void myl_native_heap_collect(myl_native_heap *heap) {
    if (heap->suspended) return;
    heap->collections++;
    heap->pending_len = 0;
    heap->scratch_failed = 0;
    for (myl_native_root *root = heap->roots; root; root = root->previous)
        trace(heap, root->type, root->address);
    /* The immortal one-scalar ASCII table is rooted here, not on the root stack:
     * generated frames restore that stack to a per-frame mark, which would drop a
     * lazily pushed entry. */
    for (size_t i = 0; i < 128; i++) if (heap->text_scalars[i]) mark(heap, heap->text_scalars[i]);
    if (heap->objects_len) myl_native_arena_trace(heap, trace);
    /* A refused worklist reservation leaves the graph partly marked. Clearing
     * the marks and returning unwinds to an allocator that refuses the request,
     * so a partial mark is never swept and the heap stays consistent. */
    if (heap->scratch_failed) {
        for (size_t i = 0; i < heap->objects_len; ++i)
            heap->objects[i].object->mark &= ~(uintptr_t)MYL_NATIVE_OBJECT_MARKED;
        heap->pending_len = 0;
        return;
    }
    while (heap->pending_len) {
        myl_native_object *object = heap->pending[--heap->pending_len];
        const unsigned char *payload = (const unsigned char *)(object + 1);
        if (object->element->kind != MYL_NATIVE_PLAIN &&
            object->element->trace_mode != MYL_NATIVE_TRACE_NONE) {
            size_t count = object_count(object);
            for (size_t i = 0; i < count; ++i)
                trace(heap, object->element, payload + i * object->element->size);
        }
    }
    /* One in-place compaction both sweeps the dead and resets the survivors'
     * mark bit, so the array stays dense and carries no per-object link. The
     * charge comes from the row, never from the object's descriptor, which may
     * already be freed with an earlier garbage owner. */
    size_t live = 0;
    for (size_t i = 0; i < heap->objects_len; ++i) {
        myl_native_object_slot slot = heap->objects[i];
        if (slot.object->mark & MYL_NATIVE_OBJECT_MARKED) {
            slot.object->mark &= ~(uintptr_t)MYL_NATIVE_OBJECT_MARKED;
            heap->objects[live++] = slot;
        } else {
            heap->bytes -= slot.bytes;
            heap->objects_live--;
            free(slot.object);
        }
    }
    heap->objects_len = live;
    /* Marking cost is paid once per collection over the whole live set, so the
     * pause interval grows faster than the live set and keeps a fixed floor:
     * a steady workload then re-marks a few times instead of every time it
     * doubles. Collection timing is unobservable (no destructors, no counter a
     * program can read) and `--gc-stress` bypasses this trigger entirely. */
    size_t gc_bytes = heap->bytes - heap->arena.reserved_bytes;
    heap->next_collection = gc_bytes > (SIZE_MAX-(4u<<20))/3 ? SIZE_MAX : gc_bytes*3+(4u<<20);
}
void *myl_native_heap_alloc(myl_native_heap *heap, const myl_native_type *element, size_t count) {
    return myl_native_heap_alloc_at(heap, element, count, heap->region_depth);
}
/* A coallocated block's payload is raw bytes: PLAIN keeps the collector's drain
 * loop off it, and one-byte elements make the element count the payload size. */
static const myl_native_type block_type = {
    .size = 1, .alignment = 1, .kind = MYL_NATIVE_PLAIN
};
void *myl_native_heap_alloc_block(myl_native_heap *heap, size_t prefix, size_t extra) {
    if (prefix > SIZE_MAX - extra) return NULL;
    return myl_native_heap_alloc_at(heap, &block_type, prefix + extra, heap->region_depth);
}
void *myl_native_heap_alloc_at(myl_native_heap *heap, const myl_native_type *element, size_t count, unsigned region) {
    if (!element || !element->alignment || element->alignment > alignof(max_align_t)) return NULL;
    if ((element->alignment & (element->alignment - 1)) || element->size % element->alignment) return NULL;
    if (region > heap->region_depth) return NULL;
    /* The mark word stores the count above two flag bits, so a count that cannot
     * shift is refused rather than truncated. */
    if (count > (SIZE_MAX >> MYL_NATIVE_OBJECT_COUNT_SHIFT)) return NULL;
    if (element->size && count > (SIZE_MAX - sizeof(myl_native_object)) / element->size) return NULL;
    if (region) return myl_native_arena_alloc(heap, element, count, region);
    size_t bytes = sizeof(myl_native_object) + count * element->size;
    size_t gc_bytes = heap->bytes - heap->arena.reserved_bytes;
    int due = heap->stress || heap->bytes > heap->limit || bytes > heap->limit - heap->bytes;
    due = due || gc_bytes >= heap->next_collection || bytes > heap->next_collection - gc_bytes;
    /* An escape copy suspends collection because its clones are not yet rooted. */
    if (due && !heap->suspended) myl_native_heap_collect(heap);
    /* A collection the host could not finish (an unallocatable worklist) refuses
     * the request rather than allocating over a partly marked graph. */
    if (heap->scratch_failed) { heap->exhausted = 1; return NULL; }
    /* Refused after a collection, so the budget really is exhausted rather than
     * merely reached; the caller's trap names the budget, not the host. */
    if (heap->bytes > heap->limit || bytes > heap->limit - heap->bytes) {
        heap->exhausted = 1;
        return NULL;
    }
    if (!reserve_object(heap)) return NULL;
    myl_native_object *object = calloc(1, bytes);
    /* Chunks the arena retained for reuse are host bytes no live allocation
     * needs, so a refused reservation spends them before reporting failure. */
    if (!object && heap->arena.cached) { myl_native_arena_reclaim(heap); object = calloc(1, bytes); }
    if (!object) return NULL;
    object->mark = (uintptr_t)count << MYL_NATIVE_OBJECT_COUNT_SHIFT;
    object->element = element;
    heap->objects[heap->objects_len++] = (myl_native_object_slot){ .object = object, .bytes = bytes };
    heap->bytes += bytes;
    heap->objects_live++;
    heap->allocations++;
    return object + 1;
}
void myl_native_heap_destroy(myl_native_heap *heap) {
    myl_native_arena_release(heap, 0);
    myl_native_arena_reclaim(heap);
    for (size_t i = 0; i < heap->objects_len; ++i) {
        myl_native_object *object = heap->objects[i].object;
        if (!(object->mark & MYL_NATIVE_OBJECT_IMMORTAL)) free(object);
    }
    free(heap->objects);
    free(heap->pending);
    memset(heap, 0, sizeof(*heap));
}

void myl_native_heap_release(myl_native_heap *heap, void *payload) {
    if (!payload) return;
    if (myl_native_arena_region(heap, payload)) return;
    myl_native_object *object = (myl_native_object *)payload - 1;
    if (object->mark & MYL_NATIVE_OBJECT_IMMORTAL) return;
    for (size_t i = 0; i < heap->objects_len; ++i) {
        if (heap->objects[i].object != object) continue;
        /* The sweep walks the array in order and never depends on it, so the
         * last row fills the hole instead of shifting the tail. */
        heap->bytes -= heap->objects[i].bytes;
        heap->objects[i] = heap->objects[--heap->objects_len];
        heap->objects_live--;
        free(object);
        return;
    }
}

/* Release every external resource reachable from a value, nesting through
   ordinary records, arrays and variants. Managed collections are traced by the
   collector instead, so they are not owners here. */
static void myl_native_schedule(myl_native_drop_link **work, const myl_native_type *type, void *value) {
    if (type->kind == MYL_NATIVE_RESOURCE) {
        void *owner = NULL;
        memcpy(&owner, value, sizeof owner);
        memset(value, 0, sizeof owner);
        if (!owner) return;
        myl_native_drop_link *link = &((myl_native_resource *)owner)->work;
        *link = (myl_native_drop_link){.next = *work, .owner = owner, .kind = type->kind};
        *work = link;
    } else if (type->kind == MYL_NATIVE_ARRAY) {
        for (size_t i = 0; i < type->count; i++)
            myl_native_schedule(work, type->fields[0].type, (unsigned char *)value + i * type->stride);
    } else if (type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT) {
        uint32_t tag = 0;
        if (type->kind == MYL_NATIVE_VARIANT) memcpy(&tag, value, sizeof tag);
        for (size_t i = 0; i < type->field_count; i++) {
            const myl_native_field *field = &type->fields[i];
            if (type->kind == MYL_NATIVE_RECORD || field->tag == tag)
                myl_native_schedule(work, field->type, (unsigned char *)value + field->offset);
        }
    }
}

void myl_native_owned_drop(myl_native_heap *heap, const myl_native_type *type, void *value) {
    (void)heap;
    myl_native_drop_link *work = NULL;
    myl_native_schedule(&work, type, value);
    while (work) {
        myl_native_resource *owner = work->owner;
        work = work->next;
        owner->drop(owner);
    }
}
