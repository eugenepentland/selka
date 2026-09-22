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
/* Every managed payload — tracing-heap, arena or frozen literal — sits behind
 * a two-word header, so these read it directly and need no heap state. */
unsigned myl_native_object_region(const myl_native_heap *heap, const void *payload) {
    (void)heap;
    return payload ? myl_native_header_region(payload) : 0;
}
const myl_native_type *myl_native_object_element(const myl_native_heap *heap, const void *payload) {
    (void)heap;
    return payload ? ((const myl_native_object *)payload - 1)->element : NULL;
}
int myl_native_object_immortal(const myl_native_heap *heap, const void *payload) {
    (void)heap;
    if (!payload) return 0;
    return (((const myl_native_object *)payload - 1)->mark & MYL_NATIVE_OBJECT_IMMORTAL) != 0;
}
/* Element count recovered from the mark word's high bits. Never called for a
 * reclaimed slot, whose word is a free-list link instead. */
static size_t object_count(const myl_native_object *object) {
    return (size_t)(object->mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT);
}
/* The size classes every tracing-heap object is rounded up into. The sequence is
 * dense at the small sizes objects actually take and doubles past 256, so a
 * header (72 bytes of list, 8 of alignment) does not pay a power-of-two step.
 * `heap_strides` is asserted against MYL_NATIVE_CLASS_COUNT. */
static const size_t class_strides[MYL_NATIVE_CLASS_COUNT] = {
    16, 32, 48, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512,
    640, 768, 896, 1024, 1280, 1536, 1792, 2048, 2560, 3072, 3584, 4096,
    5120, 6144, 7168, 8192, 10240, 12288, 14336, 16384, 20480, 24576, 28672,
    32768, 40960, 49152, 57344, 65536, 81920, 98304, 114688, 131072, 163840,
    196608, 229376, 262144,
};
_Static_assert(sizeof class_strides / sizeof class_strides[0] == MYL_NATIVE_CLASS_COUNT,
               "size-class table matches MYL_NATIVE_CLASS_COUNT");
/* Round one object's charge to a segment stride. Zero means the size overflowed. */
static size_t round_stride(size_t bytes) {
    if (bytes > SIZE_MAX - (sizeof(max_align_t) - 1)) return 0;
    return (bytes + sizeof(max_align_t) - 1) & ~(sizeof(max_align_t) - 1);
}
/* Index of the smallest class whose stride holds `stride`, or
 * MYL_NATIVE_CLASS_COUNT for a bigger object that needs its own segment. */
static size_t class_for(size_t stride) {
    size_t low = 0, high = MYL_NATIVE_CLASS_COUNT;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (class_strides[middle] < stride) low = middle + 1;
        else high = middle;
    }
    return low;
}
/* Slots a fresh segment of one class reserves. A 64 KiB slab amortizes the host
 * reservation without leaving a mostly-empty tail per class, a slot count is
 * clamped so a tiny stride does not reserve a huge table, and an oversized
 * object gets exactly one slot. */
static size_t segment_slots(size_t stride) {
    if (stride > MYL_NATIVE_CLASS_LIMIT) return 1;
    size_t slots = (((size_t)64) << 10) / stride;
    if (slots < 1) slots = 1;
    if (slots > 4096) slots = 4096;
    return slots;
}
/* Reserve one zero-filled segment and link it into the heap. The host zeroes it,
 * which is what lets the bump path hand out object payload without a memset. */
static myl_native_segment *segment_new(myl_native_heap *heap, size_t stride, size_t class_index) {
    size_t slots = segment_slots(stride);
    if (slots > (SIZE_MAX - sizeof(myl_native_segment)) / stride) return NULL;
    size_t bytes = sizeof(myl_native_segment) + slots * stride;
    myl_native_segment *segment = calloc(1, bytes);
    if (!segment) return NULL;
    segment->stride = stride;
    segment->slots = slots;
    segment->class_index = class_index;
    segment->next = heap->segments;
    heap->segments = segment;
    return segment;
}
/* Pop one reclaimed slot of `class_index`, or NULL when the class has none. The
 * slot's payload is zeroed because the previous owner wrote it; a fresh bump
 * slot is already zero. */
static myl_native_object *free_list_pop(myl_native_heap *heap, size_t class_index) {
    myl_native_object *object = heap->free_lists[class_index];
    if (!object) return NULL;
    heap->free_lists[class_index] = (myl_native_object *)(object->mark & ~MYL_NATIVE_OBJECT_FREE);
    memset(object + 1, 0, class_strides[class_index] - sizeof(myl_native_object));
    object->mark = 0;
    return object;
}
/* Thread one reclaimed slot onto its class's free list. */
static void free_list_push(myl_native_heap *heap, size_t class_index, myl_native_object *object) {
    object->mark = (uintptr_t)heap->free_lists[class_index] | MYL_NATIVE_OBJECT_FREE;
    heap->free_lists[class_index] = object;
}
/* Take one slot of `stride`, preferring a reclaimed slot, then the class's bump
 * segment, then a fresh segment. Returns NULL when the host refuses. */
static myl_native_object *slot_take(myl_native_heap *heap, size_t stride, size_t class_index) {
    if (class_index >= MYL_NATIVE_CLASS_COUNT) {
        myl_native_segment *segment = segment_new(heap, stride, class_index);
        if (!segment) return NULL;
        segment->used = 1;
        return (myl_native_object *)segment->data;
    }
    myl_native_object *object = free_list_pop(heap, class_index);
    if (object) return object;
    myl_native_segment *segment = heap->current[class_index];
    if (!segment || segment->used == segment->slots) {
        segment = segment_new(heap, class_strides[class_index], class_index);
        if (!segment) return NULL;
        heap->current[class_index] = segment;
    }
    return (myl_native_object *)(segment->data + segment->used++ * segment->stride);
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
    /* Each arena allocation records its depth in its header, which bounds it. */
    if (heap->region_depth >= MYL_NATIVE_ARENA_REGION_MAX) return 0;
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
    myl_native_object *object = (myl_native_object *)payload - 1;
    /* Immortal payloads live in the image, not the heap: they can never be
     * collected, so re-tracing one would only queue static storage. Region
     * storage is retained wholesale; its outgoing GC edges are scanned once
     * separately, so arena cycles never enter the collector's work list. */
    if (object->mark & (MYL_NATIVE_OBJECT_MARKED | MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_ARENA)) return;
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
    if (heap->segments) myl_native_arena_trace(heap, trace);
    /* A refused worklist reservation leaves the graph partly marked. Clearing
     * the marks and returning unwinds to an allocator that refuses the request,
     * so a partial mark is never swept and the heap stays consistent. */
    if (heap->scratch_failed) {
        for (myl_native_segment *segment = heap->segments; segment; segment = segment->next)
            for (size_t i = 0; i < segment->used; ++i) {
                myl_native_object *object = (myl_native_object *)(segment->data + i * segment->stride);
                if (object->mark & MYL_NATIVE_OBJECT_MARKED) object->mark &= ~(uintptr_t)MYL_NATIVE_OBJECT_MARKED;
            }
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
    /* The sweep walks segments, not a link chain: each slot's mark bit decides
     * whether it stays or joins its class's free list, and an oversized segment
     * whose one object died returns to the host whole. A slot already on a free
     * list is recognized by its free tag and left alone, so no freed slot is
     * charged twice. */
    myl_native_segment **link = &heap->segments;
    while (*link) {
        myl_native_segment *segment = *link;
        if (segment->class_index >= MYL_NATIVE_CLASS_COUNT) {
            myl_native_object *object = (myl_native_object *)segment->data;
            if (object->mark & MYL_NATIVE_OBJECT_MARKED) {
                object->mark &= ~(uintptr_t)MYL_NATIVE_OBJECT_MARKED;
                link = &segment->next;
            } else {
                heap->bytes -= segment->stride;
                heap->objects_live--;
                *link = segment->next;
                free(segment);
            }
            continue;
        }
        for (size_t i = 0; i < segment->used; ++i) {
            myl_native_object *object = (myl_native_object *)(segment->data + i * segment->stride);
            uintptr_t word = object->mark;
            if (word & MYL_NATIVE_OBJECT_FREE) continue;
            if (word & MYL_NATIVE_OBJECT_MARKED) {
                object->mark = word & ~(uintptr_t)MYL_NATIVE_OBJECT_MARKED;
            } else {
                heap->bytes -= segment->stride;
                heap->objects_live--;
                free_list_push(heap, segment->class_index, object);
            }
        }
        link = &segment->next;
    }
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
/* The list slot naming the one-slot segment whose whole payload is `payload`, or
 * NULL when the payload is anything else. Only an oversized segment — one whose
 * single object owns the entire reservation — can be handed back to the host to
 * resize, so a size-class slot, an arena allocation and a null pointer all
 * answer NULL. */
static myl_native_segment **extendable_slot(myl_native_heap *heap, const void *payload) {
    for (myl_native_segment **link = &heap->segments; *link; link = &(*link)->next) {
        myl_native_segment *segment = *link;
        if (segment->class_index < MYL_NATIVE_CLASS_COUNT) continue;
        if ((const unsigned char *)segment->data + sizeof(myl_native_object) == payload) return link;
    }
    return NULL;
}
/* An element descriptor whose bytes the collector never interprets, so an
 * extension of such a block needs no zeroing: every octet a reader can reach
 * was written by the caller. The test is the collector's own — `trace` returns
 * at once for `MYL_NATIVE_TRACE_NONE` and reads nothing for a plain kind, and
 * the drain loop walks a block only when neither holds — so a descriptor this
 * accepts is one no collection can follow into the bytes left uninitialized. */
static int opaque_elements(const myl_native_type *element) {
    return element->kind == MYL_NATIVE_PLAIN || element->trace_mode == MYL_NATIVE_TRACE_NONE;
}
void *myl_native_heap_extend(myl_native_heap *heap, void *payload, size_t count) {
    if (!payload) return NULL;
    myl_native_object *object = (myl_native_object *)payload - 1;
    if (object->mark & (MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_ARENA)) return NULL;
    const myl_native_type *element = object->element;
    if (!element || !element->size) return NULL;
    if (count > MYL_NATIVE_OBJECT_COUNT_MAX) return NULL;
    if (count > (SIZE_MAX - sizeof(myl_native_object)) / element->size) return NULL;
    /* The count and stride the ordinary allocation path would charge for the
     * same request, so a grown block is indistinguishable from a fresh one. */
    size_t stride = round_stride(sizeof(myl_native_object) + count * element->size);
    if (!stride || class_for(stride) < MYL_NATIVE_CLASS_COUNT) return NULL;
    myl_native_segment **link = extendable_slot(heap, payload);
    if (!link) return NULL;
    size_t previous = (*link)->stride;
    if (stride <= previous) return NULL;
    size_t growth = stride - previous;
    size_t gc_bytes = heap->bytes - heap->arena.reserved_bytes;
    int due = heap->stress || heap->bytes > heap->limit || growth > heap->limit - heap->bytes;
    due = due || gc_bytes >= heap->next_collection || growth > heap->next_collection - gc_bytes;
    /* An escape copy suspends collection because its clones are not yet rooted. */
    if (due && !heap->suspended) {
        myl_native_heap_collect(heap);
        /* The sweep rebuilds the segment list, so the slot that names this
         * segment — and the segment itself, which the buffer keeps alive — are
         * found again rather than reused across the collection. */
        link = extendable_slot(heap, payload);
        if (!link) return NULL;
    }
    /* A collection the host could not finish (an unallocatable worklist) refuses
     * the request rather than growing over a partly marked graph. */
    if (heap->scratch_failed) { heap->exhausted = 1; return NULL; }
    if (heap->bytes > heap->limit || growth > heap->limit - heap->bytes) {
        heap->exhausted = 1;
        return NULL;
    }
    myl_native_segment *grown = realloc(*link, sizeof(myl_native_segment) + stride);
    if (!grown) return NULL;
    grown->stride = stride;
    *link = grown;
    object = (myl_native_object *)grown->data;
    if (!opaque_elements(element)) memset(grown->data + previous, 0, growth);
    object->mark = (uintptr_t)count << MYL_NATIVE_OBJECT_COUNT_SHIFT;
    object->element = element;
    heap->bytes += growth;
    return grown->data + sizeof(myl_native_object);
}
void *myl_native_heap_alloc_at(myl_native_heap *heap, const myl_native_type *element, size_t count, unsigned region) {
    if (!element || !element->alignment || element->alignment > alignof(max_align_t)) return NULL;
    if ((element->alignment & (element->alignment - 1)) || element->size % element->alignment) return NULL;
    if (region > heap->region_depth) return NULL;
    /* The mark word stores the count above two flag bits and below the arena
     * flag, so a count that cannot fit there is refused rather than truncated. */
    if (count > MYL_NATIVE_OBJECT_COUNT_MAX) return NULL;
    if (element->size && count > (SIZE_MAX - sizeof(myl_native_object)) / element->size) return NULL;
    if (region) return myl_native_arena_alloc(heap, element, count, region);
    size_t stride = round_stride(sizeof(myl_native_object) + count * element->size);
    if (!stride) return NULL;
    size_t class_index = class_for(stride);
    if (class_index < MYL_NATIVE_CLASS_COUNT) stride = class_strides[class_index];
    size_t gc_bytes = heap->bytes - heap->arena.reserved_bytes;
    int due = heap->stress || heap->bytes > heap->limit || stride > heap->limit - heap->bytes;
    due = due || gc_bytes >= heap->next_collection || stride > heap->next_collection - gc_bytes;
    /* An escape copy suspends collection because its clones are not yet rooted. */
    if (due && !heap->suspended) myl_native_heap_collect(heap);
    /* A collection the host could not finish (an unallocatable worklist) refuses
     * the request rather than allocating over a partly marked graph. */
    if (heap->scratch_failed) { heap->exhausted = 1; return NULL; }
    /* Refused after a collection, so the budget really is exhausted rather than
     * merely reached; the caller's trap names the budget, not the host. */
    if (heap->bytes > heap->limit || stride > heap->limit - heap->bytes) {
        heap->exhausted = 1;
        return NULL;
    }
    myl_native_object *object = slot_take(heap, stride, class_index);
    /* Chunks the arena retained for reuse are host bytes no live allocation
     * needs, so a refused reservation spends them before reporting failure. */
    if (!object && heap->arena.cached) { myl_native_arena_reclaim(heap); object = slot_take(heap, stride, class_index); }
    if (!object) return NULL;
    object->mark = (uintptr_t)count << MYL_NATIVE_OBJECT_COUNT_SHIFT;
    object->element = element;
    heap->bytes += stride;
    heap->objects_live++;
    heap->allocations++;
    return object + 1;
}
void myl_native_heap_destroy(myl_native_heap *heap) {
    myl_native_arena_release(heap, 0);
    myl_native_arena_reclaim(heap);
    while (heap->segments) {
        myl_native_segment *segment = heap->segments;
        heap->segments = segment->next;
        free(segment);
    }
    free(heap->pending);
    memset(heap, 0, sizeof(*heap));
}

void myl_native_heap_release(myl_native_heap *heap, void *payload) {
    if (!payload) return;
    myl_native_object *object = (myl_native_object *)payload - 1;
    if (object->mark & (MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_ARENA)) return;
    /* Release is rare (owned storage, not the tracing path), so the containing
     * segment is found by walking the list rather than by an address map. */
    myl_native_segment **link = &heap->segments;
    while (*link) {
        myl_native_segment *segment = *link;
        uintptr_t start = (uintptr_t)segment->data, address = (uintptr_t)object;
        if (address >= start && address - start < segment->used * segment->stride) {
            heap->bytes -= segment->stride;
            heap->objects_live--;
            if (segment->class_index >= MYL_NATIVE_CLASS_COUNT) {
                /* A one-slot segment: releasing its object returns the whole
                 * reservation to the host. */
                *link = segment->next;
                free(segment);
            } else {
                object->element = NULL;
                free_list_push(heap, segment->class_index, object);
            }
            return;
        }
        link = &segment->next;
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
