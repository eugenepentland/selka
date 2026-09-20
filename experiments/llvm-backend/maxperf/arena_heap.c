#define _POSIX_C_SOURCE 200809L
#include "arena_heap.h"

#include <stdalign.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>

#ifndef MYL_MAXPERF_ARENA_CHUNK_BYTES
#define MYL_MAXPERF_ARENA_CHUNK_BYTES (((size_t)4) << 20)
#endif

typedef struct ArenaChunk {
    struct ArenaChunk *next;
    size_t capacity, used;
    max_align_t payload_alignment;
    unsigned char data[];
} ArenaChunk;

typedef struct ArenaState {
    ArenaChunk *chunks;
    size_t reserved, chunks_count;
} ArenaState;

static ArenaState *find_state(const myl_native_heap *heap) {
    /* Tracing never runs in this arm, so its pending-work slot is the private
     * arena handle. This keeps allocation O(1) without changing the ABI. */
    return (ArenaState *)heap->pending;
}

static int add_size(size_t left, size_t right, size_t *out) {
    if (left > SIZE_MAX - right) return 0;
    *out = left + right;
    return 1;
}

static size_t align_up(size_t value, size_t alignment) {
    return (value + alignment - 1) & ~(alignment - 1);
}

static ArenaChunk *new_chunk(ArenaState *state, size_t required) {
    size_t capacity = MYL_MAXPERF_ARENA_CHUNK_BYTES;
    if (capacity < required) capacity = required;
    size_t total;
    if (!add_size(sizeof(ArenaChunk), capacity, &total)) return NULL;
    ArenaChunk *chunk = calloc(1, total);
    if (!chunk) return NULL;
    chunk->capacity = capacity;
    chunk->next = state->chunks;
    state->chunks = chunk;
    state->reserved += capacity;
    state->chunks_count++;
    return chunk;
}

int myl_native_budget_parse(const char *text, size_t *out) {
    size_t value = 0, scale = 1;
    const char *cursor = text;
    if (!text || !out) return 0;
    for (; *cursor >= '0' && *cursor <= '9'; cursor++) {
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

/* The diagnostic arena intentionally installs no process or per-allocation
 * ceiling. The benchmark harness remains responsible for its outer timeout. */
int myl_native_budget_guard(size_t budget) { (void)budget; return 0; }

void myl_native_heap_init(myl_native_heap *heap, size_t limit) {
    memset(heap, 0, sizeof(*heap));
    heap->limit = limit;
    heap->next_pool_identity = 1;
    heap->next_collection = SIZE_MAX;
    ArenaState *state = calloc(1, sizeof(*state));
    if (!state) { heap->exhausted = 1; return; }
    heap->pending = (myl_native_object *)state;
}

void myl_native_root_push(myl_native_heap *heap, myl_native_root *root,
                          void *address, const myl_native_type *type) {
#ifdef MYL_MAXPERF_ARENA_COMPACT
    (void)heap; (void)root; (void)address; (void)type;
#else
    root->previous = heap->roots;
    root->address = address;
    root->type = type;
    heap->roots = root;
#endif
}

int myl_native_root_pop(myl_native_heap *heap, myl_native_root *root) {
#ifdef MYL_MAXPERF_ARENA_COMPACT
    (void)heap; (void)root;
    return 1;
#else
    if (heap->roots != root) return 0;
    heap->roots = root->previous;
    return 1;
#endif
}

void myl_native_heap_collect(myl_native_heap *heap) { (void)heap; }

void *myl_native_heap_alloc_at(myl_native_heap *heap,
                               const myl_native_type *element,
                               size_t count, unsigned region) {
    ArenaState *state = find_state(heap);
#ifdef MYL_MAXPERF_ARENA_COMPACT
    /* Valid-input maximum-performance arm: allocation descriptors and size
     * products have already been checked by the compiler/runtime boundary.
     * Reserve one aligned slot for a zero-byte value so allocations remain
     * distinct without an object header or linked-list write. */
    (void)region;
    const size_t payload = count * element->size;
    const size_t alignment = alignof(max_align_t);
    const size_t reserved = payload ? align_up(payload, alignment) : alignment;
    ArenaChunk *chunk = state ? state->chunks : NULL;
    if (!chunk || reserved > chunk->capacity - chunk->used) {
        chunk = state ? new_chunk(state, reserved) : NULL;
        if (!chunk) return NULL;
    }
    void *result = chunk->data + chunk->used;
    chunk->used += reserved;
    heap->bytes += payload;
    heap->allocations++;
    return result;
#else
    if (!state || !element || !element->alignment ||
        element->alignment > alignof(max_align_t) ||
        (element->alignment & (element->alignment - 1)) ||
        element->size % element->alignment) return NULL;
    size_t payload;
    if (element->size && count > SIZE_MAX / element->size) return NULL;
    payload = count * element->size;
    size_t object_bytes;
    if (!add_size(sizeof(myl_native_object), payload, &object_bytes)) return NULL;
    const size_t alignment = alignof(max_align_t);
    if (object_bytes > SIZE_MAX - (alignment - 1)) return NULL;
    const size_t reserved = align_up(object_bytes, alignment);
    ArenaChunk *chunk = state->chunks;
    if (!chunk || reserved > chunk->capacity - chunk->used) {
        chunk = new_chunk(state, reserved);
        if (!chunk) return NULL;
    }
    myl_native_object *object = (myl_native_object *)(chunk->data + chunk->used);
    chunk->used += reserved;
    object->element = element;
    object->count = count;
    object->bytes = object_bytes;
    object->region = region;
    heap->bytes += object_bytes;
    heap->objects_live++;
    heap->allocations++;
    return object + 1;
#endif
}

void *myl_native_heap_alloc(myl_native_heap *heap,
                            const myl_native_type *element, size_t count) {
    return myl_native_heap_alloc_at(heap, element, count, heap->region_depth);
}

static const myl_native_type block_type = {
    .size = 1, .alignment = 1, .kind = MYL_NATIVE_PLAIN,
    .trace_mode = MYL_NATIVE_TRACE_NONE
};

void *myl_native_heap_alloc_block(myl_native_heap *heap,
                                  size_t prefix, size_t extra) {
#ifndef MYL_MAXPERF_ARENA_COMPACT
    if (prefix > SIZE_MAX - extra) return NULL;
#endif
    return myl_native_heap_alloc_at(heap, &block_type, prefix + extra,
                                    heap->region_depth);
}

unsigned myl_native_object_region(const void *payload) {
#ifdef MYL_MAXPERF_ARENA_COMPACT
    (void)payload;
    return 0;
#else
    return payload ? ((const myl_native_object *)payload - 1)->region : 0;
#endif
}

void myl_native_region_begin(myl_native_heap *heap) {
    heap->region_depth++;
    heap->arena.scopes++;
}

/* Whole-invocation mode deliberately retains inner-region storage. */
void myl_native_region_end(myl_native_heap *heap) {
    if (heap->region_depth) heap->region_depth--;
}

/* Explicit release is intentionally deferred to whole-arena destruction. */
void myl_native_heap_release(myl_native_heap *heap, void *payload) {
    (void)heap;
    (void)payload;
}

void myl_native_heap_destroy(myl_native_heap *heap) {
    ArenaState *state = find_state(heap);
    if (state) {
        ArenaChunk *chunk = state->chunks;
        while (chunk) {
            ArenaChunk *next = chunk->next;
            free(chunk);
            chunk = next;
        }
        free(state);
    }
    memset(heap, 0, sizeof(*heap));
}

static void schedule_drop(myl_native_drop_link **work,
                          const myl_native_type *type, void *value) {
    if (type->kind == MYL_NATIVE_RESOURCE) {
        void *owner = NULL;
        memcpy(&owner, value, sizeof owner);
        memset(value, 0, sizeof owner);
        if (!owner) return;
        myl_native_drop_link *item = &((myl_native_resource *)owner)->work;
        *item = (myl_native_drop_link){ .next = *work, .owner = owner,
                                       .kind = type->kind };
        *work = item;
    } else if (type->kind == MYL_NATIVE_ARRAY) {
        for (size_t i = 0; i < type->count; i++)
            schedule_drop(work, type->fields[0].type,
                          (unsigned char *)value + i * type->stride);
    } else if (type->kind == MYL_NATIVE_RECORD ||
               type->kind == MYL_NATIVE_VARIANT) {
        uint32_t tag = 0;
        if (type->kind == MYL_NATIVE_VARIANT) memcpy(&tag, value, sizeof tag);
        for (size_t i = 0; i < type->field_count; i++) {
            const myl_native_field *field = &type->fields[i];
            if (type->kind == MYL_NATIVE_RECORD || field->tag == tag)
                schedule_drop(work, field->type,
                              (unsigned char *)value + field->offset);
        }
    }
}

void myl_native_owned_drop(myl_native_heap *heap,
                           const myl_native_type *type, void *value) {
    (void)heap;
    myl_native_drop_link *work = NULL;
    schedule_drop(&work, type, value);
    while (work) {
        myl_native_resource *owner = work->owner;
        work = work->next;
        owner->drop(owner);
    }
}

int myl_maxperf_arena_get_report(const myl_native_heap *heap,
                                 myl_maxperf_arena_report *report) {
    ArenaState *state = find_state(heap);
    if (!state || !report) return 0;
    *report = (myl_maxperf_arena_report){
        .allocations = heap->allocations,
        .live_bytes = heap->bytes,
        .reserved_bytes = state->reserved,
        .chunks = state->chunks_count,
        .collections = heap->collections,
    };
    return 1;
}
