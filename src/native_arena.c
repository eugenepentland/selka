#include "native_arena.h"
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

typedef struct {
    const myl_native_type *element;
    size_t count, offset;
} Allocation;

struct myl_native_arena_chunk {
    struct myl_native_arena_chunk *next;
    size_t bytes, used, count;
    unsigned region;
    max_align_t payload_alignment;
    unsigned char data[];
};

/* An integer range comparison also works when the pointer belongs to a GC
 * object or a static literal; relational comparisons on unrelated C pointers do
 * not. Interior storage is recognized as region-owned but never as an object. */
static myl_native_arena_chunk *containing(const myl_native_heap *heap, const void *payload) {
    uintptr_t address = (uintptr_t)payload;
    for (myl_native_arena_chunk *chunk = heap->arena_chunks; chunk; chunk = chunk->next) {
        uintptr_t start = (uintptr_t)chunk->data;
        if (address >= start && address - start < chunk->used) return chunk;
    }
    return NULL;
}

unsigned myl_native_arena_region(const myl_native_heap *heap, const void *payload) {
    myl_native_arena_chunk *chunk = containing(heap, payload);
    return chunk ? chunk->region : 0;
}

static Allocation *records(const myl_native_arena_chunk *chunk) {
    return (Allocation *)((unsigned char *)chunk + chunk->bytes) - chunk->count;
}

const myl_native_type *myl_native_arena_element(const myl_native_heap *heap, const void *payload) {
    myl_native_arena_chunk *chunk = containing(heap, payload);
    if (!chunk) return NULL;
    size_t offset = (size_t)((const unsigned char *)payload - chunk->data);
    const Allocation *entries = records(chunk);
    size_t low = 0, high = chunk->count;
    /* Records are reverse allocation order, hence descending payload offsets. */
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (entries[middle].offset > offset) low = middle + 1;
        else high = middle;
    }
    return low < chunk->count && entries[low].offset == offset ? entries[low].element : NULL;
}

static int fits(const myl_native_arena_chunk *chunk, size_t payload, size_t *offset) {
    const size_t mask = alignof(max_align_t) - 1;
    if (chunk->used > SIZE_MAX - mask) return 0;
    *offset = (chunk->used + mask) & ~mask;
    size_t end = (size_t)((unsigned char *)records(chunk) - chunk->data);
    return *offset <= end && sizeof(Allocation) <= end - *offset &&
        payload <= end - *offset - sizeof(Allocation);
}

/* Take a retained chunk back into service. A chunk qualifies only when it holds
 * at least the request's minimum and no more than `ceiling`, the size the
 * sizing policy would have reserved from the host, so reuse never charges the
 * budget more than a fresh reservation would have; the largest qualifying chunk
 * wins because its spare capacity is free. Only the bytes the previous scope
 * wrote can be stale — its payload prefix, which `used` bounds, and its side
 * records at the top — so zeroing exactly those restores a chunk that is
 * byte-identical to a freshly zero-filled one, which precise tracing needs. */
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
    memset(records(chunk), 0, chunk->count * sizeof(Allocation));
    chunk->used = 0;
    chunk->count = 0;
    return chunk;
}
/* Retain a chunk the closing scope released instead of returning it to the
 * host. The caller has already discharged it from `heap->bytes` and from every
 * arena reservation counter, so a retained chunk is charged to nothing and can
 * never refuse a later allocation; the bounds below cap the host bytes held
 * that way. Returns zero when the chunk must be freed. */
static int cache(myl_native_heap *heap, myl_native_arena_chunk *chunk) {
    size_t ceiling = MYL_ARENA_CACHE_BYTES < heap->limit ? MYL_ARENA_CACHE_BYTES : heap->limit;
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
        free(chunk);
    }
    heap->arena.cached = 0;
    heap->arena.cached_bytes = 0;
}
static myl_native_arena_chunk *new_chunk(myl_native_heap *heap, size_t payload, unsigned region, size_t previous) {
    const size_t mask = alignof(max_align_t) - 1;
    size_t overhead = sizeof(myl_native_arena_chunk) + sizeof(Allocation);
    if (payload > SIZE_MAX - overhead - mask) return NULL;
    size_t minimum = (overhead + payload + mask) & ~mask;
    /* One oversized allocation must not make every later small reservation
     * equally large. Ordinary chunk growth stops at 1 MiB. */
    size_t preferred = previous < (512u << 10) ? previous * 2 : (1u << 20);
    if (preferred < (64u << 10)) preferred = 64u << 10;
    if (preferred < minimum) preferred = minimum;
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
    chunk->next = heap->arena_chunks;
    chunk->region = region;
    heap->arena_chunks = chunk;
    heap->bytes += chunk->bytes;
    heap->arena.chunks_live++;
    heap->arena.reserved_bytes += chunk->bytes;
    if (heap->arena.reserved_bytes > heap->arena.peak_reserved_bytes)
        heap->arena.peak_reserved_bytes = heap->arena.reserved_bytes;
    return chunk;
}

void *myl_native_arena_alloc(myl_native_heap *heap, const myl_native_type *element, size_t count, unsigned region) {
    size_t payload = element->size * count;
    if (!payload) payload = 1;
    if (heap->stress && !heap->suspended) myl_native_heap_collect(heap);
    myl_native_arena_chunk *chunk = heap->arena_chunks;
    while (chunk && chunk->region != region) chunk = chunk->next;
    size_t offset = 0;
    if (!chunk || !fits(chunk, payload, &offset)) {
        chunk = new_chunk(heap, payload, region, chunk ? chunk->bytes : 0);
        if (!chunk) return NULL;
        offset = 0;
    }
    chunk->count++;
    *records(chunk) = (Allocation){.element = element, .count = count, .offset = offset};
    chunk->used = offset + payload;
    heap->objects_live++;
    heap->allocations++;
    heap->arena.allocations++;
    return chunk->data + offset;
}

void myl_native_arena_trace(myl_native_heap *heap, void (*trace)(myl_native_heap *, const myl_native_type *, const void *)) {
    for (myl_native_arena_chunk *chunk = heap->arena_chunks; chunk; chunk = chunk->next) {
        const Allocation *entries = records(chunk);
        for (size_t index = 0; index < chunk->count; ++index) {
            const Allocation *entry = &entries[index];
            if (entry->element->kind == MYL_NATIVE_PLAIN || entry->element->trace_mode == MYL_NATIVE_TRACE_NONE) continue;
            for (size_t item = 0; item < entry->count; ++item)
                trace(heap, entry->element, chunk->data + entry->offset + item * entry->element->size);
        }
    }
}

void myl_native_arena_release(myl_native_heap *heap, unsigned region) {
    myl_native_arena_chunk **link = &heap->arena_chunks;
    while (*link) {
        myl_native_arena_chunk *chunk = *link;
        if (chunk->region < region) { link = &chunk->next; continue; }
        *link = chunk->next;
        heap->bytes -= chunk->bytes;
        heap->objects_live -= chunk->count;
        heap->arena.released += chunk->count;
        heap->arena.reserved_bytes -= chunk->bytes;
        heap->arena.chunks_live--;
        if (!cache(heap, chunk)) free(chunk);
    }
}
