#define _POSIX_C_SOURCE 200809L
/* MAP_ANONYMOUS, for the pool mappings. */
#define _DEFAULT_SOURCE 1
#include "native_heap.h"
#include "native_arena.h"
#include "native_rc_values.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdalign.h>
#include <limits.h>
#include <sys/resource.h>
#include <sys/mman.h>
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
/* Generated inline allocation addresses the windows at these frozen offsets. */
_Static_assert(offsetof(myl_native_heap, inline_windows) == MYL_NATIVE_HEAP_INLINE_OFFSET, "inline allocation windows ABI");
_Static_assert(offsetof(myl_native_heap, arena_window) == MYL_NATIVE_HEAP_ARENA_OFFSET, "inline arena window ABI");
_Static_assert(offsetof(myl_native_heap, arena_mark) == MYL_NATIVE_HEAP_ARENA_OFFSET + 16, "inline arena mark ABI");
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
/* Element count recovered from the mark word's bits between the two flag bits
 * and the copy-on-write flags. Never called for a free slot. */
static size_t object_count(const myl_native_object *object) {
    return (size_t)((object->mark & MYL_NATIVE_OBJECT_COUNT_BITS) >> MYL_NATIVE_OBJECT_COUNT_SHIFT);
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
    /* The payload's alignment, not `sizeof(max_align_t)`: that is 32 on
     * x86-64, which rounded every charge to a multiple of 32 and left every
     * other small class (48, 80, 112 bytes) unused. */
    if (bytes > SIZE_MAX - (alignof(max_align_t) - 1)) return 0;
    return (bytes + alignof(max_align_t) - 1) & ~(alignof(max_align_t) - 1);
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
/* The classes whose segments are aligned blocks with side mark bits: strides
 * up to 8 KiB, so a 64 KiB block holds several slots. Larger classes, like
 * oversized objects, keep each object's mark in its header. */
#define MYL_NATIVE_BITMAP_CLASS_LIMIT ((size_t)8192)
/* Segments carved from one aligned host reservation. */
#define MYL_NATIVE_SEGMENT_POOL 32
/* Whether a class's segments carry side mark bits. */
static int bitmap_class(size_t class_index) {
    return class_index < MYL_NATIVE_CLASS_COUNT && class_strides[class_index] <= MYL_NATIVE_BITMAP_CLASS_LIMIT;
}
/* Byte offset of a bitmap segment's first slot inside its aligned block. */
#define MYL_NATIVE_SEGMENT_DATA_OFFSET ((offsetof(myl_native_segment, data) + 15) & ~(size_t)15)
/* Slots a fresh segment of one class reserves. A bitmap class fills one
 * aligned block; a larger class takes a 64 KiB slab (at least one slot) so the
 * host reservation is amortized without a mostly-empty tail; an oversized
 * object gets exactly one slot. */
static size_t segment_slots(size_t stride, size_t class_index) {
    if (stride > MYL_NATIVE_CLASS_LIMIT) return 1;
    if (bitmap_class(class_index)) return (MYL_NATIVE_SEGMENT_BYTES - MYL_NATIVE_SEGMENT_DATA_OFFSET) / stride;
    size_t slots = (((size_t)64) << 10) / stride;
    return slots < 1 ? 1 : slots;
}
/* Bytes of one pool mapping: MYL_NATIVE_SEGMENT_POOL segments, aligned to its
 * own size so its 2 MiB region number names it. */
#define MYL_NATIVE_POOL_BYTES (MYL_NATIVE_SEGMENT_BYTES * MYL_NATIVE_SEGMENT_POOL)
#define MYL_NATIVE_POOL_SHIFT 21
_Static_assert(MYL_NATIVE_POOL_BYTES == ((size_t)1 << MYL_NATIVE_POOL_SHIFT), "a pool is one 2 MiB region");
/* Slot of region `region` in the pool set: its own when present, else the
 * empty slot an insertion would fill. The table is never full. */
static size_t pool_slot(const myl_native_heap *heap, uintptr_t region) {
    size_t mask = heap->pool_set_capacity - 1;
    size_t at = (size_t)((region * UINT64_C(0x9E3779B97F4A7C15)) >> 32) & mask;
    while (heap->pool_set[at] && heap->pool_set[at] != region) at = (at + 1) & mask;
    return at;
}
/* Whether a header lies in a pool mapping, so it is a size-classed object
 * whose mark lives in its segment's bitmap. Answered from the address alone:
 * no read of the object itself. */
static inline int in_pool(myl_native_heap *heap, const void *object) {
    uintptr_t region = (uintptr_t)object >> MYL_NATIVE_POOL_SHIFT;
    uintptr_t *cached = &heap->pool_hits[region & (MYL_NATIVE_POOL_HITS - 1)];
    if (*cached == region) return 1;
    if (!heap->pool_set_capacity || heap->pool_set[pool_slot(heap, region)] != region) return 0;
    *cached = region;
    return 1;
}
/* Record one pool mapping's region, growing the table to stay at most half
 * full. Zero when the host refuses the growth. */
static int pool_record(myl_native_heap *heap, uintptr_t region) {
    if ((heap->pool_count + 1) * 2 > heap->pool_set_capacity) {
        size_t capacity = heap->pool_set_capacity ? heap->pool_set_capacity * 2 : 64;
        uintptr_t *grown = calloc(capacity, sizeof *grown);
        if (!grown) return 0;
        uintptr_t *old = heap->pool_set;
        size_t old_capacity = heap->pool_set_capacity;
        heap->pool_set = grown;
        heap->pool_set_capacity = capacity;
        for (size_t i = 0; i < old_capacity; ++i)
            if (old[i]) heap->pool_set[pool_slot(heap, old[i])] = old[i];
        free(old);
    }
    heap->pool_set[pool_slot(heap, region)] = region;
    return 1;
}
/* One 2 MiB-aligned, zero-filled pool mapping: twice the size is mapped and
 * the unaligned head and tail are unmapped again. NULL when the host
 * refuses. */
static unsigned char *pool_map(void) {
    size_t bytes = MYL_NATIVE_POOL_BYTES;
    unsigned char *raw = mmap(NULL, 2 * bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (raw == MAP_FAILED) return NULL;
    uintptr_t start = ((uintptr_t)raw + bytes - 1) & ~(uintptr_t)(bytes - 1);
    unsigned char *pool = (unsigned char *)start;
    if (pool != raw) munmap(raw, (size_t)(pool - raw));
    if (pool + bytes != raw + 2 * bytes) munmap(pool + bytes, (size_t)(raw + 2 * bytes - (pool + bytes)));
    return pool;
}
/* One aligned, zero-filled block for a bitmap segment, carved from the newest
 * pool mapping or from a fresh one. A fresh mapping reads as zeros, so the
 * block needs no clearing. NULL when the host refuses. */
static myl_native_segment *pool_take(myl_native_heap *heap) {
    if (heap->pool_next == heap->pool_end) {
        if (heap->pool_count == heap->pool_capacity) {
            size_t capacity = heap->pool_capacity ? heap->pool_capacity * 2 : 16;
            void **grown = realloc(heap->pools, capacity * sizeof *grown);
            if (!grown) return NULL;
            heap->pools = grown;
            heap->pool_capacity = capacity;
        }
        unsigned char *pool = pool_map();
        if (!pool) return NULL;
        if (!pool_record(heap, (uintptr_t)pool >> MYL_NATIVE_POOL_SHIFT)) {
            munmap(pool, MYL_NATIVE_POOL_BYTES);
            return NULL;
        }
        heap->pools[heap->pool_count++] = pool;
        heap->pool_next = pool;
        heap->pool_end = pool + MYL_NATIVE_POOL_BYTES;
    }
    myl_native_segment *segment = (myl_native_segment *)heap->pool_next;
    heap->pool_next += MYL_NATIVE_SEGMENT_BYTES;
    return segment;
}
/* The most recently spared block, with its header cleared and marked stale:
 * its slots still hold its previous objects' bytes. NULL when there is none. */
static myl_native_segment *spare_take(myl_native_heap *heap) {
    if (!heap->spare_length) return NULL;
    myl_native_segment *segment = heap->spare[--heap->spare_length];
    memset(segment, 0, offsetof(myl_native_segment, data));
    segment->stale = 1;
    return segment;
}
/* Give one empty bitmap segment to the spare list; zero when the list could not
 * grow, in which case the caller keeps the segment where it is. A spare keeps
 * its pages: returning them to the host after a full collection lowered no
 * program's peak and cost programs that free a phase's storage and refill it
 * at once up to 19% in page faults (`scan_split`). */
static int spare_put(myl_native_heap *heap, myl_native_segment *segment) {
    if (heap->spare_length == heap->spare_capacity) {
        size_t capacity = heap->spare_capacity ? heap->spare_capacity * 2 : 64;
        myl_native_segment **grown = realloc(heap->spare, capacity * sizeof *grown);
        if (!grown) return 0;
        heap->spare = grown;
        heap->spare_capacity = capacity;
    }
    heap->spare[heap->spare_length++] = segment;
    return 1;
}
/* Reserve one segment and link it into the heap: a spare block if there is
 * one (`GC-SPARE-1`), else a fresh zero-filled one. Fresh storage is what
 * lets the bump path hand out object payload without a memset; a spare block
 * whose pages stayed resident is stale, and its slots are cleared as they are
 * handed out, like a reused hole's. */
static myl_native_segment *segment_new(myl_native_heap *heap, size_t stride, size_t class_index) {
    size_t slots = segment_slots(stride, class_index);
    if (slots > (SIZE_MAX - sizeof(myl_native_segment)) / stride) return NULL;
    size_t bytes = sizeof(myl_native_segment) + slots * stride;
    myl_native_segment *segment = NULL;
    if (bitmap_class(class_index)) {
        segment = spare_take(heap);
        if (!segment) segment = pool_take(heap);
    } else segment = calloc(1, bytes);
    if (!segment) return NULL;
    segment->stride = stride;
    segment->slots = slots;
    segment->class_index = class_index;
    segment->dirty = 1;
    segment->next = heap->segments;
    heap->segments = segment;
    return segment;
}
/* One run of free slots handed to an allocator, the segment it belongs to, and
 * whether it is never-used (still zero-filled) storage. */
typedef struct {
    unsigned char *start, *end;
    myl_native_segment *segment;
    int fresh;
} hole_span;
/* Take the next hole of a class: the source segment's next hole, else the
 * first hole of the next segment with holes nobody started on, else the whole
 * never-used tail of the bump segment, else — when `grow` allows — a fresh
 * segment's whole storage. Every segment storage comes from is marked dirty,
 * so the next minor collection sweeps exactly the segments young objects can
 * be in. Returns zero when there is no hole and none may be reserved. */
static int hole_take(myl_native_heap *heap, size_t class_index, int grow, hole_span *span) {
    myl_native_class *state = &heap->classes[class_index];
    for (;;) {
        myl_native_segment *segment = state->source;
        if (segment && segment->holes) {
            myl_native_hole *hole = (myl_native_hole *)segment->holes;
            *span = (hole_span){segment->holes, hole->end, segment, 0};
            segment->holes = hole->next;
            return 1;
        }
        segment = state->available;
        if (segment) {
            state->available = segment->available;
            segment->available = NULL;
            segment->listed = 0;
            segment->dirty = 1;
            state->source = segment;
            continue;
        }
        segment = state->current;
        if (!segment || segment->used == segment->slots) {
            if (!grow) return 0;
            segment = segment_new(heap, class_strides[class_index], class_index);
            if (!segment) return 0;
            state->current = segment;
        }
        segment->dirty = 1;
        *span = (hole_span){segment->data + segment->used * segment->stride,
                            segment->data + segment->slots * segment->stride, segment, !segment->stale};
        segment->used = segment->slots;
        return 1;
    }
}
/* Give an unconsumed run back to its segment as a hole, so a later allocation
 * of the class finds it again before the next sweep does. */
static void hole_return(myl_native_heap *heap, myl_native_segment *segment, unsigned char *start, unsigned char *end) {
    if (start == end) return;
    myl_native_hole *hole = (myl_native_hole *)start;
    hole->end = end;
    hole->next = segment->holes;
    segment->holes = start;
    myl_native_class *state = &heap->classes[segment->class_index];
    if (state->source != segment && !segment->listed) {
        segment->listed = 1;
        segment->available = state->available;
        state->available = segment;
    }
}
/* Take one slot of `stride`: a one-slot segment for an oversized object, and
 * otherwise the next slot of the class's runtime window, opening a window on
 * the next hole or on fresh storage when it is empty. Returns NULL when the
 * host refuses. A reused slot's payload is zeroed because its previous owner
 * wrote it — unless `zero` is clear, for a payload the caller overwrites in
 * full and the collector never interprets; fresh storage is already zero. */
static myl_native_object *slot_take(myl_native_heap *heap, size_t stride, size_t class_index, int zero) {
    if (class_index >= MYL_NATIVE_CLASS_COUNT) {
        myl_native_segment *segment = segment_new(heap, stride, class_index);
        if (!segment) return NULL;
        segment->used = 1;
        return (myl_native_object *)segment->data;
    }
    myl_native_class *state = &heap->classes[class_index];
    if (state->runtime.cursor == state->runtime.limit) {
        hole_span span;
        if (!hole_take(heap, class_index, 1, &span)) return NULL;
        state->runtime = (myl_native_window){span.start, span.end};
        state->runtime_fresh = span.fresh;
    }
    myl_native_object *object = (myl_native_object *)state->runtime.cursor;
    state->runtime.cursor += stride;
    if (zero && !state->runtime_fresh) memset(object + 1, 0, stride - sizeof(myl_native_object));
    object->mark = 0;
    return object;
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
    /* Generated inline allocation never tests the depth, so every inline list
     * is emptied here and none is refilled until the depth is 0 again: an
     * allocation inside the arena always takes the runtime path into it. */
    myl_native_heap_settle(heap);
    /* The arena window belongs to the enclosing depth. */
    myl_native_arena_sync(heap);
    heap->region_depth++;
    heap->arena.scopes++;
    return 1;
}
void myl_native_region_end(myl_native_heap *heap) {
    if (!heap->region_depth) return;
    myl_native_arena_release(heap, heap->region_depth);
    heap->region_depth--;
}
/* The mark bit of a size-classed object: its segment is the aligned block
 * around it, and the bit indexes the object's first 16-byte granule. `age` is
 * the same bit's word in the segment's aging bits. */
typedef struct { uint64_t *word, *age; uint64_t bit; } mark_slot;
static mark_slot mark_bit(const myl_native_object *object) {
    uintptr_t address = (uintptr_t)object;
    myl_native_segment *segment = (myl_native_segment *)(address & ~(uintptr_t)(MYL_NATIVE_SEGMENT_BYTES - 1));
    size_t granule = (size_t)(address - (uintptr_t)segment) >> 4;
    return (mark_slot){&segment->marks[granule >> 6], &segment->ages[granule >> 6], (uint64_t)1 << (granule & 63)};
}
/* Whether an object is marked: in its header when it is large, else in its
 * segment's mark bits. Outside a collection a marked object is old. */
static int marked(const myl_native_object *object) {
    if (object->mark & MYL_NATIVE_OBJECT_LARGE) return (object->mark & MYL_NATIVE_OBJECT_MARKED) != 0;
    mark_slot slot = mark_bit(object);
    return (*slot.word & slot.bit) != 0;
}
static void trace(myl_native_heap *, const myl_native_type *, const void *);
static void mark(myl_native_heap *heap, void *payload) {
    if (!payload) return;
    myl_native_object *object = (myl_native_object *)payload - 1;
    myl_native_generations *generations = &heap->generations;
    if (in_pool(heap, object)) {
        /* A size-classed object: its mark and age bits answer without a read
         * of the object, so rescanning references to old objects costs the
         * bitmap, not a load of every child's header. */
        mark_slot slot = mark_bit(object);
        if (*slot.word & slot.bit) {
            /* Marked already. Its age bit is set exactly when this collection
             * keeps it young (see below). */
            if (*slot.age & slot.bit) generations->young_edge = 1;
            return;
        }
        if (!worklist_push(heap, object)) { heap->scratch_failed = 1; return; }
        *slot.word |= slot.bit;
        /* Aging: a minor collection promotes a young object only the second
         * time it finds it reachable. The first time its age bit is set and
         * its header bit 0 stays clear; the sweep clears its mark bit again,
         * so it stays young. Promotion clears the age bit and sets header bit
         * 0, the store barrier's "old" flag. While a collection marks, a set
         * age bit on a marked object therefore means "kept young"; on an
         * unmarked one, "survived the last minor collection". A full
         * collection promotes every survivor. */
        if (generations->aging == MYL_NATIVE_AGING_KEEP && !(*slot.age & slot.bit)) {
            *slot.age |= slot.bit;
            generations->young_edge = 1;
            return;
        }
        /* A full collection zeroed every age bit before marking. */
        if (generations->aging != MYL_NATIVE_AGING_OFF) *slot.age &= ~slot.bit;
        object->mark |= MYL_NATIVE_OBJECT_MARKED;
        return;
    }
    uintptr_t word = object->mark;
    /* Immortal payloads live in the image, not the heap: they can never be
     * collected, so re-tracing one would only queue static storage. Region
     * storage is retained wholesale; its outgoing GC edges are scanned once
     * separately, so arena cycles never enter the collector's work list.
     * Everything else outside the pools is a large object, marked in its
     * header and never kept young. */
    if (word & (MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_ARENA)) return;
    if (word & MYL_NATIVE_OBJECT_MARKED) return;
    if (!worklist_push(heap, object)) { heap->scratch_failed = 1; return; }
    object->mark = word | MYL_NATIVE_OBJECT_MARKED;
}
static inline const myl_native_scan_entry *followed_plan(const myl_native_heap *, const myl_native_type *);
static void scan_elements(myl_native_heap *, const myl_native_scan_entry *, size_t, const unsigned char *, size_t, size_t);
static void trace(myl_native_heap *heap, const myl_native_type *type, const void *address) {
    const unsigned char *bytes = address;
    if (type->trace_mode == MYL_NATIVE_TRACE_NONE) return;
    if (type->kind == MYL_NATIVE_POINTER || type->kind == MYL_NATIVE_OWNED_BUFFER || type->kind == MYL_NATIVE_OWNED_POOL) {
        void *pointer;
        memcpy(&pointer, bytes, sizeof(pointer));
        mark(heap, pointer);
    } else if (type->scan) {
        scan_elements(heap, followed_plan(heap, type), type->scan_count, bytes, 1, type->size);
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
#if defined(MYL_NATIVE_RC) && MYL_NATIVE_RC
    if (myl_rc_storage_init(heap)!=MYL_RC_OK) heap->scratch_failed=1;
#endif
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
/* Push one header onto a collector-owned stack. Zero when the host refuses the
 * growth, which the caller turns into a forced full collection. */
static int stack_push(myl_native_object_stack *stack, myl_native_object *object) {
    if (stack->length == stack->capacity) {
        size_t capacity = stack->capacity ? stack->capacity * 2 : 256;
        if (capacity <= stack->capacity || capacity > SIZE_MAX / sizeof *stack->items) return 0;
        myl_native_object **grown = realloc(stack->items, capacity * sizeof *grown);
        if (!grown) return 0;
        stack->items = grown;
        stack->capacity = capacity;
    }
    stack->items[stack->length++] = object;
    return 1;
}
/* Whether the collector interprets one object's payload at all. */
static int traced_payload(const myl_native_object *object) {
    return object->element->kind != MYL_NATIVE_PLAIN && object->element->trace_mode != MYL_NATIVE_TRACE_NONE;
}
/* Whether an old object must be rescanned by every minor collection: it holds
 * references and no barrier reports a store into it. */
static int rescanned(const myl_native_object *object) {
    return traced_payload(object) && !object->element->cell;
}
/* A plan under construction: `count` of the `capacity` slots at `entries`
 * are filled. */
typedef struct {
    myl_native_scan_entry *entries;
    size_t capacity, count;
} scan_builder;
/* Whether a descriptor is one reference: the collector marks its word itself. */
static inline int reference_kind(const myl_native_type *type) {
    return type->kind == MYL_NATIVE_POINTER || type->kind == MYL_NATIVE_OWNED_BUFFER || type->kind == MYL_NATIVE_OWNED_POOL;
}
/* Append the reference slots of `type` at `base` under `condition` (a tag
 * offset and value, or MYL_NATIVE_SCAN_ALWAYS). Returns zero when the shape
 * does not fit a flat plan. The traversal mirrors `trace` exactly. */
static int flatten(scan_builder *plan, const myl_native_type *type, size_t base, myl_native_scan_entry condition) {
    if (type->trace_mode == MYL_NATIVE_TRACE_NONE) return 1;
    if (base > UINT32_MAX - type->size) return 0;
    if (reference_kind(type)) {
        if (plan->count == plan->capacity) return 0;
        plan->entries[plan->count++] = (myl_native_scan_entry){(uint32_t)base, condition.tag_offset, condition.tag};
        return 1;
    }
    const myl_native_field *fields = type->trace_mode == MYL_NATIVE_TRACE_FIELDS ? type->trace_fields : type->fields;
    if (type->kind == MYL_NATIVE_ARRAY) {
        for (size_t i = 0; i < type->count; ++i)
            if (!flatten(plan, fields[0].type, base + i * type->stride, condition)) return 0;
        return 1;
    }
    if (type->kind != MYL_NATIVE_RECORD && type->kind != MYL_NATIVE_VARIANT) return 1;
    size_t field_count = type->trace_mode == MYL_NATIVE_TRACE_FIELDS ? type->trace_field_count : type->field_count;
    if (type->kind == MYL_NATIVE_VARIANT && condition.tag_offset != MYL_NATIVE_SCAN_ALWAYS) return 0;
    for (size_t i = 0; i < field_count; ++i) {
        myl_native_scan_entry inner = condition;
        if (type->kind == MYL_NATIVE_VARIANT) inner = (myl_native_scan_entry){0, (uint32_t)base, fields[i].tag};
        if (!flatten(plan, fields[i].type, base + fields[i].offset, inner)) return 0;
    }
    return 1;
}
int myl_native_scan_flatten(const myl_native_type *type, myl_native_scan_entry *entries, size_t capacity, size_t *count) {
    scan_builder plan = {entries, capacity, 0};
    if (!flatten(&plan, type, 0, (myl_native_scan_entry){0, MYL_NATIVE_SCAN_ALWAYS, 0})) return 0;
    *count = plan.count;
    return 1;
}
/* Whether the plan attached to `type` names exactly the slots its fields
 * flatten to, in the same order. */
static int plan_agrees(const myl_native_type *type) {
    myl_native_scan_entry entries[MYL_NATIVE_SCAN_ENTRIES];
    size_t count;
    if (!myl_native_scan_flatten(type, entries, MYL_NATIVE_SCAN_ENTRIES, &count)) return 0;
    return count == type->scan_count && (!count || !memcmp(entries, type->scan, count * sizeof *entries));
}
/* The plan the collector follows for `type`: the one attached to the
 * descriptor, read with one load — no table, no lookup and no hash, so no two
 * descriptors can share or evict one another's plan, and a descriptor built
 * inside a managed object (a dictionary's entries) carries the plan of its own
 * layout wherever that object lives (GC-SCAN-PLAN-1). The compiler and the
 * runtime each build plans, so under `--gc-stress` every plan followed is first
 * checked against a fresh flattening of its descriptor, and a disagreement
 * aborts rather than tracing the wrong slots (GC-SCAN-PLAN-2). */
static inline const myl_native_scan_entry *followed_plan(const myl_native_heap *heap, const myl_native_type *type) {
    const myl_native_scan_entry *scan = type->scan;
    if (scan && heap->stress && !plan_agrees(type)) {
        fputs("mylang runtime: a descriptor's scan plan disagrees with its fields\n", stderr);
        abort();
    }
    return scan;
}
/* Mark every slot `scan` names in `count` consecutive elements of `size` bytes. */
static void scan_elements(myl_native_heap *heap, const myl_native_scan_entry *scan, size_t entries,
                          const unsigned char *payload, size_t count, size_t size) {
    for (size_t i = 0; i < count; ++i, payload += size)
        for (size_t e = 0; e < entries; ++e) {
            const myl_native_scan_entry *entry = &scan[e];
            if (entry->tag_offset != MYL_NATIVE_SCAN_ALWAYS) {
                uint32_t tag;
                memcpy(&tag, payload + entry->tag_offset, sizeof tag);
                if (tag != entry->tag) continue;
            }
            void *pointer;
            memcpy(&pointer, payload + entry->offset, sizeof pointer);
            mark(heap, pointer);
        }
}
/* Trace every element of one object's payload: a reference element's word
 * directly, an element with a plan by that plan, and any other by the
 * recursive walk. */
static void scan_payload(myl_native_heap *heap, const myl_native_object *object) {
    if (!traced_payload(object)) return;
    const unsigned char *payload = (const unsigned char *)(object + 1);
    size_t count = object_count(object);
    const myl_native_type *element = object->element;
    if (reference_kind(element)) {
        for (size_t i = 0; i < count; ++i, payload += element->size) {
            void *pointer;
            memcpy(&pointer, payload, sizeof pointer);
            mark(heap, pointer);
        }
        return;
    }
    const myl_native_scan_entry *scan = followed_plan(heap, element);
    if (scan) {
        if (element->scan_count) scan_elements(heap, scan, element->scan_count, payload, count, element->size);
        return;
    }
    for (size_t i = 0; i < count; ++i) trace(heap, element, payload + i * element->size);
}
/* Clear every tracing-heap mark, so every object is young again: a bitmap
 * segment's mark bits at once, and the header bit of every object in any
 * other segment. A free slot of such a segment is never marked — a hole
 * header's first word is an aligned address — so clearing it changes nothing.
 * A bitmap segment's header bits are only the barrier's "old" flags; the drain
 * sets them again for every object this collection marks. */
static void clear_marks(myl_native_heap *heap) {
    for (myl_native_segment *segment = heap->segments; segment; segment = segment->next) {
        if (bitmap_class(segment->class_index)) {
            memset(segment->marks, 0, sizeof segment->marks);
            memset(segment->ages, 0, sizeof segment->ages);
            continue;
        }
        for (size_t i = 0; i < segment->used; ++i) {
            myl_native_object *object = (myl_native_object *)(segment->data + i * segment->stride);
            object->mark &= ~(uintptr_t)MYL_NATIVE_OBJECT_MARKED;
        }
    }
}
/* A minor collection's extra roots: every old object that may reference a
 * young one. The rescan set lists the old size-classed objects no barrier
 * watches, each checked to still be old — an object explicitly released since
 * is a free slot and any later occupant is young, so neither is followed. The
 * oversized objects are found on the segment list instead, because growing one
 * may move it and a saved address would dangle. A remembered body's payload is
 * traced directly and its old flag set again; a large one's mark bit is that
 * flag, which the barrier cleared, so setting it keeps the body alive. A
 * remembered slot released since has no descriptor and is skipped: nothing can
 * reuse it before the sweep that follows makes it a hole. */
static void mark_old_references(myl_native_heap *heap) {
    myl_native_generations *generations = &heap->generations;
    /* An entry that is no longer marked names a slot released since, which
     * is dropped: every entry left names a live object, so no entry can point
     * into a segment this collection's sweep empties and spares. */
    size_t kept = 0;
    for (size_t i = 0; i < generations->rescan.length; ++i) {
        myl_native_object *object = generations->rescan.items[i];
        if (!marked(object)) continue;
        generations->rescan.items[kept++] = object;
        scan_payload(heap, object);
    }
    generations->rescan.length = kept;
    for (myl_native_segment *segment = heap->segments; segment; segment = segment->next) {
        if (segment->class_index < MYL_NATIVE_CLASS_COUNT) continue;
        const myl_native_object *object = (const myl_native_object *)segment->data;
        if ((object->mark & MYL_NATIVE_OBJECT_MARKED) && rescanned(object)) scan_payload(heap, object);
    }
    /* Every listed body is old again before any is traced, so a reference
     * from one listed body to another is not mistaken for a young one. A
     * listed body's bit 0 is clear until this point, so a set bit names an
     * entry already kept, or a large body a root reached first, which the
     * drain traces; either way the entry is dropped here. */
    size_t listed = 0;
    myl_native_object **items = generations->remembered.items;
    for (size_t i = 0; i < generations->remembered.length; ++i) {
        myl_native_object *object = items[i];
        if (!object->element || (object->mark & MYL_NATIVE_OBJECT_MARKED)) continue;
        object->mark |= MYL_NATIVE_OBJECT_MARKED;
        items[listed++] = object;
    }
    generations->remembered.length = 0;
    for (size_t i = 0; i < listed; ++i) {
        myl_native_object *object = items[i];
        if (!object->element) continue;
        generations->young_edge = 0;
        scan_payload(heap, object);
        /* A body that still references an object this collection keeps young
         * stays listed, or the next minor collection would miss that object.
         * The list only shrinks here, so the push never reallocates. */
        if (generations->young_edge) stack_push(&generations->remembered, object);
    }
}
/* Collection policy: a minor collection runs once the young generation grows
 * by half the live bytes, never less than the floor, and a full one once the
 * old generation reaches `full_threshold`, twice the bytes the last full
 * collection kept plus the floor. A tighter threshold (1.5x, a full collection
 * as soon as promotion reaches it, and no young interval past it) lowered
 * text_ops' and knucleotide's peaks by 4 and 2 MB but cost programs with a
 * large, growing live set more full collections and more minor rescans of
 * their old lists (scan_split +20%); see
 * docs/audits/memory-footprint-2026-09-23.md. */
#define MYL_NATIVE_YOUNG_FLOOR (((size_t)4) << 20)
#define MYL_NATIVE_FULL_FLOOR (((size_t)4) << 20)
static size_t saturating_add(size_t a, size_t b) { return a > SIZE_MAX - b ? SIZE_MAX : a + b; }
/* Set the next collection's triggers from the bytes that survived this one. */
static void schedule(myl_native_heap *heap, int full) {
    size_t live = heap->bytes - heap->arena.reserved_bytes;
    size_t young = live / 2;
    if (young < MYL_NATIVE_YOUNG_FLOOR) young = MYL_NATIVE_YOUNG_FLOOR;
    heap->next_collection = saturating_add(live, young);
    /* An object kept young is not old: only promotion grows the old
     * generation toward the full threshold. */
    heap->generations.old_bytes = live - heap->generations.young_bytes;
    if (full) {
        size_t grown = live > SIZE_MAX / 2 ? SIZE_MAX : live * 2;
        heap->generations.full_threshold = saturating_add(grown, MYL_NATIVE_FULL_FLOOR);
    }
}
/* Whether an object has a one-slot segment of its own: its charge is past the
 * largest size class. Such a segment may move when it grows, so the rescan set
 * never records its address. */
static int oversized(const myl_native_object *object) {
    size_t size = object->element->size, count = object_count(object);
    if (size && count > (MYL_NATIVE_CLASS_LIMIT - sizeof(myl_native_object)) / size) return 1;
    return round_stride(sizeof(myl_native_object) + count * size) > MYL_NATIVE_CLASS_LIMIT;
}
/* Rebuild one size-classed segment's holes from its marks: every maximal run
 * of unmarked slots in the used prefix becomes a hole, in address order, and
 * every marked slot survives as old. A bitmap segment's marks are read from
 * its mark bits, so a free or dead slot is not touched at all unless it starts
 * a run, whose first slot receives the hole header. */
/* The holes one sweep threads through a segment, in address order. */
typedef struct { unsigned char *first; myl_native_hole *last; } hole_chain;
/* Append the run [start, end) to a chain unless it is empty. */
static void hole_append(hole_chain *chain, unsigned char *start, unsigned char *end) {
    if (start >= end) return;
    myl_native_hole *hole = (myl_native_hole *)start;
    hole->end = end;
    hole->next = NULL;
    if (chain->last) chain->last->next = start;
    else chain->first = start;
    chain->last = hole;
}
/* Sweep a bitmap segment by its set mark bits alone: each marks one live
 * object's first granule, so the runs between consecutive live objects are
 * the holes. A word of mark bits with nothing set is skipped whole, which is
 * what makes sweeping a segment of dead young objects cost its bitmap rather
 * than its slots. */
static size_t sweep_bitmap(myl_native_segment *segment, unsigned char *end, hole_chain *chain) {
    unsigned char *base = (unsigned char *)segment, *cursor = segment->data;
    size_t first = (size_t)(segment->data - base) >> 4, last = (size_t)(end - base) >> 4, live = 0;
    for (size_t word = first >> 6; word < (last + 63) >> 6; ++word) {
        uint64_t bits = segment->marks[word];
        while (bits) {
            size_t granule = word * 64 + (size_t)__builtin_ctzll(bits);
            bits &= bits - 1;
            if (granule < first || granule >= last) continue;
            unsigned char *slot = base + granule * 16;
            hole_append(chain, cursor, slot);
            cursor = slot + segment->stride;
            live++;
        }
    }
    hole_append(chain, cursor, end);
    return live;
}
/* After a bitmap segment's holes are rebuilt, the objects this collection
 * kept young lose their mark bit again: their age bit is set, and every other
 * age bit (an object that died young, or one promoted since) is cleared. A
 * segment holding a young object stays dirty, so the next minor collection
 * sweeps it. Returns the number of objects kept young. */
static size_t settle_ages(myl_native_segment *segment) {
    size_t young = 0;
    for (size_t word = 0; word < MYL_NATIVE_SEGMENT_MARK_WORDS; ++word) {
        uint64_t ages = segment->ages[word] & segment->marks[word];
        segment->ages[word] = ages;
        segment->marks[word] &= ~ages;
        young += (size_t)__builtin_popcountll(ages);
    }
    return young;
}
static size_t sweep_segment(myl_native_segment *segment) {
    hole_chain chain = {NULL, NULL};
    size_t live = 0, young = 0;
    unsigned char *end = segment->data + segment->used * segment->stride;
    if (bitmap_class(segment->class_index)) {
        live = sweep_bitmap(segment, end, &chain);
        young = settle_ages(segment);
    } else {
        unsigned char *cursor = segment->data;
        for (unsigned char *slot = segment->data; slot < end; slot += segment->stride) {
            if (!(((myl_native_object *)slot)->mark & MYL_NATIVE_OBJECT_MARKED)) continue;
            hole_append(&chain, cursor, slot);
            cursor = slot + segment->stride;
            live++;
        }
        hole_append(&chain, cursor, end);
    }
    segment->holes = chain.first;
    segment->live = live;
    segment->dirty = young != 0;
    return young;
}
/* The sweep walks segments, not a link chain. A full collection sweeps every
 * segment; a minor one sweeps only the dirty ones — those storage was handed
 * out from since the last sweep — because an object in a clean segment is old
 * or already free, and a minor collection frees no old object. An oversized
 * segment whose one object died returns to the host whole. Every segment left
 * with holes is offered to its class again, and the tracing heap's bytes and
 * objects are recounted from what survived: that discharges every freed
 * object, and every prepaid slot of a window nobody took, exactly once. */
static void sweep(myl_native_heap *heap, int full) {
    size_t bytes = 0, objects = 0, young = 0;
    myl_native_segment **link = &heap->segments;
    while (*link) {
        myl_native_segment *segment = *link;
        if (segment->class_index >= MYL_NATIVE_CLASS_COUNT) {
            myl_native_object *object = (myl_native_object *)segment->data;
            if (object->mark & MYL_NATIVE_OBJECT_MARKED) {
                bytes += segment->stride;
                objects++;
                link = &segment->next;
            } else {
                *link = segment->next;
                free(segment);
            }
            continue;
        }
        if (full || segment->dirty) young += sweep_segment(segment) * segment->stride;
        /* A bitmap segment with no object left in it serves whichever class
         * next needs a fresh one: every such segment is one aligned block of
         * the same size. The bump segment of its class stays, and a spare
         * list that cannot grow leaves the segment where it is. */
        if (!segment->live && bitmap_class(segment->class_index) &&
            heap->classes[segment->class_index].current != segment && spare_put(heap, segment)) {
            *link = segment->next;
            continue;
        }
        bytes += segment->live * segment->stride;
        objects += segment->live;
        segment->available = NULL;
        segment->listed = segment->holes != NULL;
        if (segment->listed) {
            myl_native_class *state = &heap->classes[segment->class_index];
            segment->available = state->available;
            state->available = segment;
        }
        link = &segment->next;
    }
    heap->bytes = heap->arena.reserved_bytes + bytes;
    heap->objects_live = heap->objects_live - heap->gc_objects + objects;
    heap->gc_objects = objects;
    heap->generations.young_bytes = young;
}
/* One collection. A full one clears every mark first and reclaims every
 * unreachable object; a minor one keeps the old generation marked, follows
 * no reference into it, and reclaims only unreachable young objects. Either
 * way every survivor stays marked and so becomes old. */
static void collect(myl_native_heap *heap, int full) {
    if (heap->suspended) return;
    myl_native_generations *generations = &heap->generations;
    if (generations->force_full) full = 1;
    heap->collections++;
    heap->pending_len = 0;
    heap->scratch_failed = 0;
    /* Every window and hole source is dropped: the storage behind them is in
     * dirty segments, which the sweep turns back into holes, and the prepaid
     * slots of an inline window nobody took are unmarked, so the recount after
     * the sweep discharges them. The lists of segments with holes are rebuilt
     * from every segment. */
    memset(heap->inline_windows, 0, sizeof heap->inline_windows);
    for (size_t class_index = 0; class_index < MYL_NATIVE_CLASS_COUNT; ++class_index) {
        myl_native_class *state = &heap->classes[class_index];
        state->source = state->available = state->inline_segment = NULL;
        state->runtime = (myl_native_window){NULL, NULL};
    }
    if (full) {
        clear_marks(heap);
        generations->remembered.length = 0;
        generations->rescan.length = 0;
        generations->force_full = 0;
        generations->full_collections++;
    } else generations->minor_collections++;
    generations->aging = full ? MYL_NATIVE_AGING_OFF : MYL_NATIVE_AGING_KEEP;
    for (myl_native_root *root = heap->roots; root; root = root->previous)
        trace(heap, root->type, root->address);
    /* The immortal one-scalar ASCII table is rooted here, not on the root stack:
     * generated frames restore that stack to a per-frame mark, which would drop a
     * lazily pushed entry. */
    for (size_t i = 0; i < 128; i++) if (heap->text_scalars[i]) mark(heap, heap->text_scalars[i]);
    if (heap->segments) myl_native_arena_trace(heap, trace);
    /* A young object first reached through an old one — stored into an old
     * list, dictionary or class body — is promoted at once rather than aged:
     * the old container will keep it, and aging it would only trace it twice.
     * Aging is for what the stack and the young generation hold. This also
     * lists the remembered bodies that must stay listed and empties the rest. */
    if (!full) {
        generations->aging = MYL_NATIVE_AGING_PROMOTE;
        mark_old_references(heap);
        generations->aging = MYL_NATIVE_AGING_KEEP;
    }
    /* Every object marked by this collection passes through the worklist once,
     * so the objects a later minor collection must rescan are listed here: a
     * promoted size-classed survivor whose references no barrier watches. A
     * promoted `cell` body that references an object this collection keeps
     * young is listed as remembered instead, exactly as if a store had
     * reached it. An object kept young is neither: the next minor collection
     * traces it anyway. */
    while (heap->pending_len) {
        myl_native_object *object = heap->pending[--heap->pending_len];
        generations->young_edge = 0;
        scan_payload(heap, object);
        if (!(object->mark & MYL_NATIVE_OBJECT_MARKED) || !traced_payload(object)) continue;
        if (!object->element->cell) {
            if (!oversized(object) && !stack_push(&generations->rescan, object)) generations->force_full = 1;
        } else if (generations->young_edge && !stack_push(&generations->remembered, object))
            generations->force_full = 1;
    }
    generations->aging = MYL_NATIVE_AGING_OFF;
    /* A refused worklist reservation leaves the graph partly marked. Clearing
     * every mark and returning unwinds to an allocator that refuses the request,
     * so a partial mark is never swept and the heap stays consistent; with the
     * old generation unmarked too, only a full collection may run next. */
    if (heap->scratch_failed) {
        clear_marks(heap);
        heap->pending_len = 0;
        generations->force_full = 1;
        return;
    }
    sweep(heap, full);
    /* A listed body keeps header bit 0 clear until the next minor collection
     * traces it, as the store barrier leaves it, so a later store does not
     * list it twice. A large body's bit 0 is its mark; the next minor
     * collection sets it again before its sweep, as for a barrier's entry. */
    for (size_t i = 0; i < generations->remembered.length; ++i)
        generations->remembered.items[i]->mark &= ~(uintptr_t)MYL_NATIVE_OBJECT_MARKED;
    /* Collection timing is unobservable (no destructors, no counter a program
     * can read) and `--gc-stress` bypasses these triggers entirely. */
    schedule(heap, full);
}
void myl_native_heap_collect(myl_native_heap *heap) {
    if (myl_rc_enabled(heap)) { myl_rc_drain(heap); return; }
    collect(heap, 1);
}
/* The collection an allocation of `bytes` more runs when it is due. Budget
 * pressure always runs a full one, because only a full collection reclaims
 * old garbage and the request is refused if even that is not enough. Under
 * `--gc-stress` every third collection is full and the two between are
 * minor, so both kinds run at every allocation and an object a minor
 * collection kept young is promoted by the next one. Otherwise a minor collection runs unless the tracing
 * heap has reached the full threshold. */
static void collect_due(myl_native_heap *heap, size_t bytes) {
    int pressure = heap->bytes > heap->limit || bytes > heap->limit - heap->bytes;
    int full = heap->stress ? heap->collections % 3 == 0 : heap->generations.old_bytes >= heap->generations.full_threshold;
    collect(heap, full || pressure);
}
/* Whether an allocation charging `bytes` more must first collect: always
 * under `--gc-stress`, and otherwise when it would cross the budget or the
 * collection trigger. */
static int allocation_due(const myl_native_heap *heap, size_t bytes) {
    size_t gc_bytes = heap->bytes - heap->arena.reserved_bytes;
    int due = heap->stress || heap->bytes > heap->limit || bytes > heap->limit - heap->bytes;
    return due || gc_bytes >= heap->next_collection || bytes > heap->next_collection - gc_bytes;
}
/* Collect before an allocation of `bytes` when it is due. Prepaid inline
 * slots are returned first, so the decision — and a budget refusal after it —
 * counts only bytes a program actually holds, exactly as if every inline
 * allocation had been charged one at a time. */
static void prepare(myl_native_heap *heap, size_t bytes) {
    if (!allocation_due(heap, bytes)) return;
    myl_native_heap_settle(heap);
    /* An escape copy suspends collection because its clones are not yet rooted. */
    if (allocation_due(heap, bytes) && !heap->suspended) collect_due(heap, bytes);
}
void *myl_native_heap_alloc(myl_native_heap *heap, const myl_native_type *element, size_t count) {
    return myl_native_heap_alloc_at(heap, element, count, heap->region_depth);
}
/* A coallocated block's payload is raw bytes: PLAIN keeps the collector's drain
 * loop off it, and one-byte elements make the element count the payload size. */
static const myl_native_type block_type = {
    .size = 1, .alignment = 1, .kind = MYL_NATIVE_PLAIN
};
static void *alloc_object(myl_native_heap *heap, const myl_native_type *element, size_t count, unsigned region, int zero);
/* A block's payload is not cleared (`GC-NOZERO-1`): its caller writes every
 * octet it will read before the next safepoint, and its PLAIN descriptor keeps
 * the collector out of it, so stale bytes of a reused slot are never
 * observed. An arena block is carved from a zero-filled chunk as before. */
void *myl_native_heap_alloc_block(myl_native_heap *heap, size_t prefix, size_t extra) {
#if defined(MYL_NATIVE_RC) && MYL_NATIVE_RC
    if (!myl_rc_enabled(heap)) return NULL;
#endif
    if (prefix > SIZE_MAX - extra) return NULL;
    if (myl_rc_enabled(heap)) return myl_rc_storage_bytes(heap,prefix+extra,heap->region_depth);
    return alloc_object(heap, &block_type, prefix + extra, heap->region_depth, 0);
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
    if (myl_rc_enabled(heap)) return myl_rc_storage_extend(heap,payload,count);
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
    if (allocation_due(heap, growth)) {
        prepare(heap, growth);
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
    /* Growth does not change an object's age: an old block stays marked, so a
     * minor collection neither frees it nor needs its referrers to be young. */
    object->mark = ((uintptr_t)count << MYL_NATIVE_OBJECT_COUNT_SHIFT) | (object->mark & (MYL_NATIVE_OBJECT_MARKED | MYL_NATIVE_OBJECT_LARGE | MYL_NATIVE_OBJECT_COW));
    object->element = element;
    heap->bytes += growth;
    return grown->data + sizeof(myl_native_object);
}
void *myl_native_heap_alloc_at(myl_native_heap *heap, const myl_native_type *element, size_t count, unsigned region) {
#if defined(MYL_NATIVE_RC) && MYL_NATIVE_RC
    if (!myl_rc_enabled(heap)) return NULL;
#endif
    if (myl_rc_enabled(heap)) {
        if (!myl_rc_native_shape(heap,element)) return NULL;
        myl_rc_alloc_request request={element,count,region};
        void *result=NULL;
        myl_rc_status status=myl_rc_new(heap,&request,&result);
        if (status!=MYL_RC_OK) myl_rc_record_failure(heap,status);
        return result;
    }
    return alloc_object(heap, element, count, region, 1);
}
static void *alloc_object(myl_native_heap *heap, const myl_native_type *element, size_t count, unsigned region, int zero) {
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
    prepare(heap, stride);
    /* A collection the host could not finish (an unallocatable worklist) refuses
     * the request rather than allocating over a partly marked graph. */
    if (heap->scratch_failed) { heap->exhausted = 1; return NULL; }
    /* Refused after a collection, so the budget really is exhausted rather than
     * merely reached; the caller's trap names the budget, not the host. */
    if (heap->bytes > heap->limit || stride > heap->limit - heap->bytes) {
        heap->exhausted = 1;
        return NULL;
    }
    myl_native_object *object = slot_take(heap, stride, class_index, zero);
    /* Chunks the arena retained for reuse are host bytes no live allocation
     * needs, so a refused reservation spends them before reporting failure. */
    if (!object && heap->arena.cached) { myl_native_arena_reclaim(heap); object = slot_take(heap, stride, class_index, zero); }
    if (!object) return NULL;
    object->mark = ((uintptr_t)count << MYL_NATIVE_OBJECT_COUNT_SHIFT) | (bitmap_class(class_index) ? 0 : MYL_NATIVE_OBJECT_LARGE);
    object->element = element;
    heap->bytes += stride;
    heap->objects_live++;
    heap->gc_objects++;
    heap->allocations++;
    return object + 1;
}
/* Charge `slots` objects of `stride` at once, as that many allocations. */
static void charge(myl_native_heap *heap, size_t slots, size_t stride) {
    heap->bytes += slots * stride;
    heap->objects_live += slots;
    heap->gc_objects += slots;
    heap->allocations += slots;
}
/* Open inline class `class_index`'s window on the next hole (or fresh
 * storage), keep its first slot for the caller and charge the whole window
 * now: exactly as many slots as the budget and the collection trigger still
 * admit, so bumping through every one of them crosses neither, and the part
 * of the hole past that is given back. Returns the first slot, or NULL when
 * the host refuses. A reused slot keeps its previous owner's bytes: the inline
 * path initializes every payload word before the next safepoint, and the
 * caller zeroes the one returned here. */
static myl_native_object *open_window(myl_native_heap *heap, size_t class_index, int *fresh) {
    size_t stride = class_strides[class_index];
    size_t gc_bytes = heap->bytes - heap->arena.reserved_bytes;
    size_t room = heap->limit - heap->bytes;
    size_t until = heap->next_collection > gc_bytes ? heap->next_collection - gc_bytes : 0;
    if (until < room) room = until;
    size_t admitted = room / stride ? room / stride : 1;
    hole_span span;
    if (!hole_take(heap, class_index, 1, &span)) {
        /* Chunks the arena retained for reuse are host bytes no live allocation
         * needs, so a refused reservation spends them before reporting failure. */
        if (!heap->arena.cached) return NULL;
        myl_native_arena_reclaim(heap);
        if (!hole_take(heap, class_index, 1, &span)) return NULL;
    }
    size_t slots = (size_t)(span.end - span.start) / stride;
    if (slots > admitted) {
        hole_return(heap, span.segment, span.start + admitted * stride, span.end);
        slots = admitted;
    }
    charge(heap, slots, stride);
    heap->inline_windows[class_index] = (myl_native_window){span.start + stride, span.start + slots * stride};
    heap->classes[class_index].inline_segment = span.segment;
    *fresh = span.fresh;
    return (myl_native_object *)span.start;
}
void *myl_native_heap_alloc_small(myl_native_heap *heap, const myl_native_type *element, size_t class_index) {
#if defined(MYL_NATIVE_RC) && MYL_NATIVE_RC
    if (!myl_rc_enabled(heap)) return NULL;
#endif
    if (myl_rc_enabled(heap)) return myl_native_heap_alloc(heap,element,1);
    /* The class is the smallest stride that holds the object: a constant-time
     * check of the compiler's choice against the runtime's own table. */
    size_t stride = element && element->size < MYL_NATIVE_CLASS_LIMIT ? round_stride(sizeof(myl_native_object) + element->size) : 0;
    if (class_index >= MYL_NATIVE_INLINE_CLASSES || !stride || class_strides[class_index] < stride ||
        (class_index && class_strides[class_index - 1] >= stride)) abort();
    if (heap->region_depth || heap->stress || heap->suspended) return myl_native_heap_alloc(heap, element, 1);
    if (element->alignment > alignof(max_align_t)) return NULL;
    stride = class_strides[class_index];
    myl_native_window *window = &heap->inline_windows[class_index];
    myl_native_object *object;
    int fresh = 0;
    if (window->cursor != window->limit) {
        /* Generated code calls only on an empty window; any other caller takes
         * the next prepaid slot like the inline path would. */
        object = (myl_native_object *)window->cursor;
        window->cursor += stride;
    } else {
        prepare(heap, stride);
        /* A collection the host could not finish (an unallocatable worklist)
         * refuses the request rather than allocating over a partly marked
         * graph; after a collection the budget really is exhausted. */
        if (heap->scratch_failed || heap->bytes > heap->limit || stride > heap->limit - heap->bytes) {
            heap->exhausted = 1;
            return NULL;
        }
        object = open_window(heap, class_index, &fresh);
        if (!object) return NULL;
    }
    if (!fresh) memset(object + 1, 0, stride - sizeof(myl_native_object));
    object->mark = (uintptr_t)1 << MYL_NATIVE_OBJECT_COUNT_SHIFT;
    object->element = element;
    return object + 1;
}
void myl_native_heap_settle(myl_native_heap *heap) {
    for (size_t class_index = 0; class_index < MYL_NATIVE_INLINE_CLASSES; ++class_index) {
        myl_native_window *window = &heap->inline_windows[class_index];
        if (window->cursor == window->limit) continue;
        size_t stride = class_strides[class_index];
        size_t slots = (size_t)(window->limit - window->cursor) / stride;
        heap->bytes -= slots * stride;
        heap->objects_live -= slots;
        heap->gc_objects -= slots;
        heap->allocations -= slots;
        hole_return(heap, heap->classes[class_index].inline_segment, window->cursor, window->limit);
        *window = (myl_native_window){NULL, NULL};
    }
}
void myl_native_heap_remember(myl_native_heap *heap, void *payload) {
    if (myl_rc_enabled(heap)) return;
    myl_native_object *object = (myl_native_object *)payload - 1;
    if (!(object->mark & MYL_NATIVE_OBJECT_MARKED)) return;
    if (!stack_push(&heap->generations.remembered, object)) heap->generations.force_full = 1;
    object->mark &= ~(uintptr_t)MYL_NATIVE_OBJECT_MARKED;
}
void myl_native_heap_destroy(myl_native_heap *heap) {
    myl_native_arena_destroy(heap);
    if (myl_rc_enabled(heap)) {
        for (size_t i=0;i<128;i++) myl_rc_owner_release(heap,heap->text_scalars[i]);
        myl_rc_heap_destroy(heap);
    }
    while (heap->segments) {
        myl_native_segment *segment = heap->segments;
        heap->segments = segment->next;
        /* A bitmap segment is part of a pool reservation, freed below. */
        if (!bitmap_class(segment->class_index)) free(segment);
    }
    for (size_t i = 0; i < heap->pool_count; ++i) munmap(heap->pools[i], MYL_NATIVE_POOL_BYTES);
    free(heap->pool_set);
    free(heap->pools);
    free(heap->spare);
    free(heap->pending);
    free(heap->generations.rescan.items);
    free(heap->generations.remembered.items);
    memset(heap, 0, sizeof(*heap));
}

void myl_native_heap_release(myl_native_heap *heap, void *payload) {
    if (myl_rc_enabled(heap)) { myl_rc_owner_release(heap,payload); return; }
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
            heap->gc_objects--;
            if (segment->class_index >= MYL_NATIVE_CLASS_COUNT) {
                /* A one-slot segment: releasing its object returns the whole
                 * reservation to the host. */
                *link = segment->next;
                free(segment);
            } else {
                /* Unmarked and without a descriptor, the slot is free; the
                 * segment is marked dirty, so the next sweep folds it into a
                 * hole. Nothing reuses it before then. */
                if (bitmap_class(segment->class_index)) {
                    mark_slot slot = mark_bit(object);
                    *slot.word &= ~slot.bit;
                }
                object->element = NULL;
                object->mark = 0;
                segment->dirty = 1;
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
    if (myl_rc_enabled(heap)) { myl_rc_owned_drop(heap, type, value); return; }
    (void)heap;
    myl_native_drop_link *work = NULL;
    myl_native_schedule(&work, type, value);
    while (work) {
        myl_native_resource *owner = work->owner;
        work = work->next;
        owner->drop(owner);
    }
}
