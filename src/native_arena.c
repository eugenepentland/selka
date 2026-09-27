#include "native_arena.h"
#include "native_rc_internal.h"
#include <stdalign.h>
#include <stdlib.h>
#include <string.h>

/* Retention bound for released chunks. A loop of short scopes needs one chunk
 * at a time, so a handful covers nesting without letting a program that opened
 * one wide scope hold its whole reservation for the rest of the process. An
 * oversized one-off chunk is returned to the host rather than retained, and the
 * retained total never exceeds the memory budget itself. */
enum { MYL_ARENA_CACHE_CHUNKS = 4 };
#define MYL_ARENA_CACHE_BYTES (((size_t)2) << 20)
#define MYL_ARENA_CACHE_CHUNK_BYTES (((size_t)1) << 20)

/* A chunk's allocations are laid out one after another from `data`, each an
 * aligned two-word `myl_native_object` header immediately followed by its
 * payload, exactly as a tracing-heap slot is. The header's mark word carries
 * MYL_NATIVE_OBJECT_ARENA, the owning depth and the element count, so the
 * store barrier, the collector and escape copies read an arena payload's
 * region from the word before it rather than searching for its chunk. `used`
 * ends the last payload and `count` counts the allocations. */
struct myl_native_arena_chunk {
    struct myl_native_arena_chunk *next;
    size_t bytes, used, count;
    unsigned region;
    max_align_t payload_alignment;
    unsigned char data[];
};

/* Bytes one allocation of `count` elements occupies after its header; a
 * zero-byte request still takes one byte so every payload is distinct. */
static size_t payload_bytes(const myl_native_type *element, size_t count) {
    size_t bytes = element->size * count;
    return bytes ? bytes : 1;
}

static size_t capacity(const myl_native_arena_chunk *chunk) {
    return chunk->bytes - (size_t)(chunk->data - (const unsigned char *)chunk);
}

/* Aligned offset of the next header and whether it and `payload` fit. */
static int fits(const myl_native_arena_chunk *chunk, size_t payload, size_t *offset) {
    const size_t mask = alignof(max_align_t) - 1;
    if (chunk->used > SIZE_MAX - mask) return 0;
    *offset = (chunk->used + mask) & ~mask;
    size_t end = capacity(chunk);
    return *offset <= end && sizeof(myl_native_object) <= end - *offset &&
        payload <= end - *offset - sizeof(myl_native_object);
}

/* Take a retained chunk back into service. A chunk qualifies only when it holds
 * at least the request's minimum and no more than `ceiling`, the size the
 * sizing policy would have reserved from the host, so reuse never charges the
 * budget more than a fresh reservation would have; the largest qualifying chunk
 * wins because its spare capacity is free. Only the bytes the previous scope
 * wrote can be stale — its headers and payloads, which `used` bounds — so
 * zeroing exactly those restores a chunk that is byte-identical to a freshly
 * zero-filled one, which precise tracing needs. */
static myl_native_arena_chunk *uncache(myl_native_heap *heap, size_t minimum, size_t ceiling) {
    myl_native_arena_chunk **link = &heap->arena_cache, **best = NULL;
    for (; *link; link = &(*link)->next)
        if ((*link)->bytes >= minimum && (*link)->bytes <= ceiling &&
            (!best || (*link)->bytes > (*best)->bytes)) best = link;
    if (!best) return NULL;
    myl_native_arena_chunk *chunk = *best;
    *best = chunk->next;
    heap->arena.cached--;
    heap->arena.cached_bytes -= chunk->bytes;
    memset(chunk->data, 0, chunk->used);
    chunk->used = 0;
    chunk->count = 0;
    return chunk;
}
/* Retain a chunk the closing scope released instead of returning it to the
 * host. GC discharges retained bytes; RC keeps the complete reservation charged
 * until reuse or reclamation. Returns zero when the chunk must be freed. */
static int cache(myl_native_heap *heap, myl_native_arena_chunk *chunk) {
    size_t limit = heap->rc && !heap->limit ? SIZE_MAX : heap->limit;
    size_t ceiling = MYL_ARENA_CACHE_BYTES < limit ? MYL_ARENA_CACHE_BYTES : limit;
    if (chunk->bytes > MYL_ARENA_CACHE_CHUNK_BYTES) return 0;
    if (heap->arena.cached >= (size_t)MYL_ARENA_CACHE_CHUNKS) return 0;
    if (heap->arena.cached_bytes >= ceiling || chunk->bytes > ceiling - heap->arena.cached_bytes) return 0;
    chunk->next = heap->arena_cache;
    heap->arena_cache = chunk;
    heap->arena.cached++;
    heap->arena.cached_bytes += chunk->bytes;
    return 1;
}
void myl_native_arena_reclaim(myl_native_heap *heap) {
    while (heap->arena_cache) {
        myl_native_arena_chunk *chunk = heap->arena_cache;
        heap->arena_cache = chunk->next;
        if (heap->rc) heap->bytes -= chunk->bytes;
        free(chunk);
    }
    heap->arena.cached = 0;
    heap->arena.cached_bytes = 0;
}
/* Make room in the per-depth chunk lists for depth `region`. Zero when the
 * host refuses the growth. */
static int depth_room(myl_native_heap *heap, unsigned region) {
    if (region < heap->arena_depth_capacity) return 1;
    size_t capacity = heap->arena_depth_capacity ? heap->arena_depth_capacity : 8;
    while (capacity <= region) capacity *= 2;
    myl_native_arena_chunk **grown = realloc(heap->arena_chunks, capacity * sizeof *grown);
    if (!grown) return 0;
    memset(grown + heap->arena_depth_capacity, 0, (capacity - heap->arena_depth_capacity) * sizeof *grown);
    heap->arena_chunks = grown;
    heap->arena_depth_capacity = capacity;
    return 1;
}
static myl_native_arena_chunk *rc_chunk(myl_native_heap *heap, size_t minimum, size_t preferred) {
    myl_native_arena_chunk *chunk = uncache(heap, minimum, preferred);
    if (chunk) { heap->arena.reused++; return chunk; }
    size_t available = !heap->limit ? SIZE_MAX - heap->bytes : heap->bytes > heap->limit ? 0 : heap->limit - heap->bytes;
    if (minimum > available && heap->arena_cache) {
        myl_native_arena_reclaim(heap);
        available = !heap->limit ? SIZE_MAX - heap->bytes : heap->bytes > heap->limit ? 0 : heap->limit - heap->bytes;
    }
    if (minimum > available) { heap->exhausted = 1; return NULL; }
    size_t bytes = preferred < available ? preferred : available & ~(alignof(max_align_t) - 1);
    chunk = calloc(1, bytes);
    if (!chunk && heap->arena_cache) { myl_native_arena_reclaim(heap); chunk = calloc(1, bytes); }
    if (!chunk) return NULL;
    chunk->bytes = bytes;
    heap->bytes += bytes;
    heap->arena.chunks++;
    return chunk;
}
static void link_chunk(myl_native_heap *heap, myl_native_arena_chunk *chunk, unsigned region) {
    chunk->next = heap->arena_chunks[region];
    chunk->region = region;
    heap->arena_chunks[region] = chunk;
    if (heap->arena_depths <= region) heap->arena_depths = (size_t)region + 1;
    heap->arena.chunks_live++;
    heap->arena.reserved_bytes += chunk->bytes;
    if (heap->arena.reserved_bytes > heap->arena.peak_reserved_bytes)
        heap->arena.peak_reserved_bytes = heap->arena.reserved_bytes;
}
static myl_native_arena_chunk *rc_new_chunk(myl_native_heap *heap, size_t minimum, size_t preferred, unsigned region) {
    myl_native_arena_chunk **grown = NULL;
    size_t capacity = heap->arena_depth_capacity;
    if (region >= capacity) {
        capacity = capacity ? capacity : 8;
        while (capacity <= region) capacity *= 2;
        grown = myl_rc_meta_alloc(heap, capacity * sizeof *grown);
        if (!grown) return NULL;
        if (heap->arena_depth_capacity) memcpy(grown, heap->arena_chunks, heap->arena_depth_capacity * sizeof *grown);
    }
    myl_native_arena_chunk *chunk = rc_chunk(heap, minimum, preferred);
    if (!chunk) { myl_rc_meta_free(heap, grown, capacity * sizeof *grown); return NULL; }
    if (grown) {
        myl_rc_meta_free(heap, heap->arena_chunks, heap->arena_depth_capacity * sizeof *grown);
        heap->arena_chunks = grown;
        heap->arena_depth_capacity = capacity;
    }
    link_chunk(heap, chunk, region);
    return chunk;
}
static myl_native_arena_chunk *new_chunk(myl_native_heap *heap, size_t payload, unsigned region, size_t previous) {
    const size_t mask = alignof(max_align_t) - 1;
    size_t overhead = sizeof(myl_native_arena_chunk) + sizeof(myl_native_object);
    if (payload > SIZE_MAX - overhead - mask) return NULL;
    size_t minimum = (overhead + payload + mask) & ~mask;
    /* One oversized allocation must not make every later small reservation
     * equally large. Ordinary chunk growth stops at 1 MiB. */
    size_t preferred = previous < (512u << 10) ? previous * 2 : (1u << 20);
    if (preferred < (64u << 10)) preferred = 64u << 10;
    if (preferred < minimum) preferred = minimum;
    if (heap->rc) return rc_new_chunk(heap, minimum, preferred, region);
    if (!depth_room(heap, region)) return NULL;
    /* Collection may reclaim older GC storage but never any arena allocation.
     * Charge the actual host reservation, including descriptor space and slack. */
    if ((heap->bytes > heap->limit || minimum > heap->limit - heap->bytes) && !heap->suspended)
        myl_native_heap_collect(heap);
    size_t available = heap->bytes > heap->limit ? 0 : heap->limit - heap->bytes;
    if (minimum > available) { heap->exhausted = 1; return NULL; }
    size_t bytes = preferred < available ? preferred : available & ~mask;
    myl_native_arena_chunk *chunk = uncache(heap, minimum, bytes);
    if (chunk) heap->arena.reused++;
    else {
        chunk = calloc(1, bytes);
        /* Retained chunks are the one host reservation the runtime can give
         * back, so a refused request spends them before it fails. */
        if (!chunk && heap->arena.cached) { myl_native_arena_reclaim(heap); chunk = calloc(1, bytes); }
        if (!chunk) return NULL;
        chunk->bytes = bytes;
        heap->arena.chunks++;
    }
    heap->bytes += chunk->bytes;
    link_chunk(heap, chunk, region);
    return chunk;
}

void myl_native_arena_sync(myl_native_heap *heap) {
    myl_native_arena_chunk *chunk = heap->arena_window_chunk;
    if (!chunk) return;
    chunk->used = (size_t)(heap->arena_window.cursor - chunk->data);
    heap->arena_window = (myl_native_window){NULL, NULL};
    heap->arena_window_chunk = NULL;
}
/* Open generated code's arena window on the free tail of `chunk`, the chunk
 * the innermost arena allocates from, when bumping through it cannot bypass a
 * rule the runtime path enforces: never while an escape copy lowers the
 * depth, and never under `--gc-stress`, which collects at every allocation. */
static void open_window(myl_native_heap *heap, myl_native_arena_chunk *chunk, unsigned region) {
    const size_t mask = alignof(max_align_t) - 1;
    if (region != heap->region_depth || heap->suspended || heap->stress) return;
    size_t start = (chunk->used + mask) & ~mask;
    if (start >= capacity(chunk)) return;
    heap->arena_window = (myl_native_window){chunk->data + start, chunk->data + capacity(chunk)};
    heap->arena_mark = MYL_NATIVE_OBJECT_ARENA | ((uintptr_t)region << MYL_NATIVE_ARENA_REGION_SHIFT) |
        ((uintptr_t)1 << MYL_NATIVE_OBJECT_COUNT_SHIFT);
    heap->arena_window_chunk = chunk;
}

void *myl_native_arena_alloc(myl_native_heap *heap, const myl_native_type *element, size_t count, unsigned region) {
    /* The header's mark word holds both, so a value that cannot fit is refused
     * rather than truncated. */
    if (count > MYL_NATIVE_ARENA_COUNT_MAX || region > MYL_NATIVE_ARENA_REGION_MAX) return NULL;
    size_t payload = payload_bytes(element, count);
    if (heap->stress && !heap->suspended) myl_native_heap_collect(heap);
    myl_native_arena_chunk *chunk = heap->arena_window_chunk;
    unsigned char *start = heap->arena_window.cursor;
    size_t room = chunk ? (size_t)(heap->arena_window.limit - start) : 0;
    if (chunk && chunk->region == region && room >= sizeof(myl_native_object) && payload <= room - sizeof(myl_native_object)) {
        /* The open window is this depth's current chunk: bump it exactly as
         * generated code does, keeping its cursor 16-aligned. */
        const size_t mask = alignof(max_align_t) - 1;
        myl_native_object *header = (myl_native_object *)start;
        header->mark = MYL_NATIVE_OBJECT_ARENA | ((uintptr_t)region << MYL_NATIVE_ARENA_REGION_SHIFT) |
            ((uintptr_t)count << MYL_NATIVE_OBJECT_COUNT_SHIFT);
        header->element = element;
        chunk->count++;
        size_t end = (size_t)(start - chunk->data) + sizeof(myl_native_object) + payload;
        size_t next = (end + mask) & ~mask;
        heap->arena_window.cursor = next < capacity(chunk) ? chunk->data + next : heap->arena_window.limit;
        heap->objects_live++;
        heap->allocations++;
        heap->arena.allocations++;
        return header + 1;
    }
    /* The window's free tail is exactly where this allocation may land. */
    myl_native_arena_sync(heap);
    /* The depth's current chunk is the head of its own list: one load,
     * however many chunks deeper or shallower scopes hold. */
    chunk = region < heap->arena_depths ? heap->arena_chunks[region] : NULL;
    size_t offset = 0;
    if (!chunk || !fits(chunk, payload, &offset)) {
        chunk = new_chunk(heap, payload, region, chunk ? chunk->bytes : 0);
        if (!chunk) return NULL;
        offset = 0;
    }
    myl_native_object *header = (myl_native_object *)(chunk->data + offset);
    header->mark = MYL_NATIVE_OBJECT_ARENA | ((uintptr_t)region << MYL_NATIVE_ARENA_REGION_SHIFT) |
        ((uintptr_t)count << MYL_NATIVE_OBJECT_COUNT_SHIFT);
    header->element = element;
    chunk->count++;
    chunk->used = offset + sizeof(myl_native_object) + payload;
    heap->objects_live++;
    heap->allocations++;
    heap->arena.allocations++;
    open_window(heap, chunk, region);
    return header + 1;
}

/* Walk every allocation of every chunk through its header. The used prefix
 * is a gapless sequence of 16-aligned headers and payloads — the runtime's and
 * the ones generated code bumped out of the window alike — so the walk steps
 * by each header's own size until it reaches `used`. */
void myl_native_arena_trace(myl_native_heap *heap, void (*trace)(myl_native_heap *, const myl_native_type *, const void *)) {
    const size_t mask = alignof(max_align_t) - 1;
    myl_native_arena_sync(heap);
    for (size_t depth = 0; depth < heap->arena_depths; ++depth)
    for (myl_native_arena_chunk *chunk = heap->arena_chunks[depth]; chunk; chunk = chunk->next) {
        size_t offset = 0;
        while (offset < chunk->used) {
            const myl_native_object *header = (const myl_native_object *)(chunk->data + offset);
            const myl_native_type *element = header->element;
            size_t count = (size_t)(header->mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT) & MYL_NATIVE_ARENA_COUNT_MAX;
            const unsigned char *payload = (const unsigned char *)(header + 1);
            offset = (offset + sizeof(myl_native_object) + payload_bytes(element, count) + mask) & ~mask;
            if (element->kind == MYL_NATIVE_PLAIN || element->trace_mode == MYL_NATIVE_TRACE_NONE) continue;
            for (size_t item = 0; item < count; ++item)
                trace(heap, element, payload + item * element->size);
        }
    }
}

/* Detach before callbacks so reentrant arenas cannot use dying chunks. */
static myl_native_arena_chunk *detach(myl_native_heap *heap, unsigned region) {
    myl_native_arena_chunk *all = NULL;
    while (heap->arena_depths > region) {
        size_t depth = --heap->arena_depths;
        myl_native_arena_chunk *chunk = heap->arena_chunks[depth];
        heap->arena_chunks[depth] = NULL;
        while (chunk) {
            myl_native_arena_chunk *next = chunk->next;
            chunk->next = all;
            all = chunk;
            chunk = next;
        }
    }
    return all;
}
static void release_pass(myl_native_heap *heap, myl_native_arena_chunk *chunk, unsigned finalizing) {
    const size_t mask = alignof(max_align_t) - 1;
    size_t offset = 0;
    while (offset < chunk->used) {
        myl_native_object *header = (myl_native_object *)(chunk->data + offset);
        size_t count = (header->mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT) & MYL_NATIVE_ARENA_COUNT_MAX;
        offset = (offset + sizeof *header + payload_bytes(header->element, count) + mask) & ~mask;
        if (finalizing && (header->mark & MYL_RC_OBJECT_DYING)) continue;
        const myl_rc_descriptor *descriptor = myl_rc_descriptor_find(heap, header->element);
        myl_rc_invariant(descriptor != NULL);
        if (finalizing) {
            header->mark |= MYL_RC_OBJECT_DYING;
            if (descriptor->finalize) descriptor->finalize(heap, header + 1);
        } else if (descriptor->edges) descriptor->edges(heap, header + 1, count);
        else myl_rc_edges_release(heap, descriptor->shape, header + 1, count);
    }
}
/* Return detached chunks to the retention cache or the host. */
static void rc_retire_chunks(myl_native_heap *heap, myl_native_arena_chunk *chunks) {
    while (chunks) {
        myl_native_arena_chunk *chunk = chunks;
        chunks = chunk->next;
        heap->objects_live -= chunk->count;
        heap->arena.released += chunk->count;
        heap->arena.reserved_bytes -= chunk->bytes;
        heap->arena.chunks_live--;
        if (!cache(heap, chunk)) { heap->bytes -= chunk->bytes; free(chunk); }
    }
}
static void rc_release(myl_native_heap *heap, unsigned region) {
    myl_native_arena_chunk *chunks = detach(heap, region);
    unsigned saved = heap->region_depth;
    heap->region_depth = region ? region - 1 : 0;
    myl_rc_scopes_close_region(heap, region);
    /* Keep every backing and descriptor alive until all logical owners drop.
     * Raw bytes must not be zeroed before their list or dictionary owner. */
    for (myl_native_arena_chunk *chunk = chunks; chunk; chunk = chunk->next) release_pass(heap, chunk, 1);
    for (myl_native_arena_chunk *chunk = chunks; chunk; chunk = chunk->next) release_pass(heap, chunk, 0);
    myl_rc_drain(heap);
    myl_rc_invariant(heap->region_depth == (region ? region - 1 : 0));
    heap->region_depth = saved;
    rc_retire_chunks(heap, chunks);
}
void myl_native_arena_discard(myl_native_heap *heap) {
    myl_rc_invariant(heap && heap->rc);
    myl_native_arena_sync(heap);
    rc_retire_chunks(heap, detach(heap, 0));
}
void myl_native_arena_release(myl_native_heap *heap, unsigned region) {
    /* A reused chunk is zeroed up to `used`, which must cover what generated
     * code bumped out of the window. */
    myl_native_arena_sync(heap);
    if (heap->rc) { rc_release(heap, region); return; }
    /* Only the lists of `region` and deeper are visited, deepest first, so
     * closing a scope costs the chunks it frees, not every open chunk. */
    while (heap->arena_depths > region) {
        size_t depth = --heap->arena_depths;
        myl_native_arena_chunk *chunk = heap->arena_chunks[depth];
        heap->arena_chunks[depth] = NULL;
        while (chunk) {
            myl_native_arena_chunk *next = chunk->next;
            heap->bytes -= chunk->bytes;
            heap->objects_live -= chunk->count;
            heap->arena.released += chunk->count;
            heap->arena.reserved_bytes -= chunk->bytes;
            heap->arena.chunks_live--;
            if (!cache(heap, chunk)) free(chunk);
            chunk = next;
        }
    }
    while (heap->arena_depths && !heap->arena_chunks[heap->arena_depths - 1]) heap->arena_depths--;
}
void myl_native_arena_destroy(myl_native_heap *heap) {
    myl_native_arena_release(heap, 0);
    myl_native_arena_reclaim(heap);
    if (heap->rc) myl_rc_meta_free(heap, heap->arena_chunks, heap->arena_depth_capacity * sizeof *heap->arena_chunks);
    else free(heap->arena_chunks);
    heap->arena_chunks = NULL;
    heap->arena_depth_capacity = 0;
}
void myl_rc_arena_close(myl_native_heap *heap, unsigned depth) {
    myl_rc_invariant(heap && heap->rc && depth && depth == heap->region_depth);
    myl_native_region_end(heap);
}
