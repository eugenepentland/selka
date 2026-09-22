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
    size_t overhead = sizeof(myl_native_arena_chunk) + sizeof(myl_native_object);
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
    /* The header's mark word holds both, so a value that cannot fit is refused
     * rather than truncated. */
    if (count > MYL_NATIVE_ARENA_COUNT_MAX || region > MYL_NATIVE_ARENA_REGION_MAX) return NULL;
    size_t payload = payload_bytes(element, count);
    if (heap->stress && !heap->suspended) myl_native_heap_collect(heap);
    myl_native_arena_chunk *chunk = heap->arena_chunks;
    while (chunk && chunk->region != region) chunk = chunk->next;
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
    return header + 1;
}

/* Walk every allocation of every chunk through its header. */
void myl_native_arena_trace(myl_native_heap *heap, void (*trace)(myl_native_heap *, const myl_native_type *, const void *)) {
    const size_t mask = alignof(max_align_t) - 1;
    for (myl_native_arena_chunk *chunk = heap->arena_chunks; chunk; chunk = chunk->next) {
        size_t offset = 0;
        for (size_t index = 0; index < chunk->count; ++index) {
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
