#include "native_arena.h"
#include <stdalign.h>
#include <stdlib.h>

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
    myl_native_arena_chunk *chunk = calloc(1, bytes);
    if (!chunk) return NULL;
    chunk->next = heap->arena_chunks;
    chunk->bytes = bytes;
    chunk->region = region;
    heap->arena_chunks = chunk;
    heap->bytes += bytes;
    heap->arena.chunks++;
    heap->arena.chunks_live++;
    heap->arena.reserved_bytes += bytes;
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
        free(chunk);
    }
}
