#define _POSIX_C_SOURCE 200809L
#include "native_rc.h"
#include "native_rc_internal.h"
#include <assert.h>
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct { size_t live, retired, allocations; unsigned finalizing, max_finalizing; void *expect_unpinned; } TestAllocator;
static myl_rc_status allocate(myl_native_heap *heap, const myl_rc_alloc_request *request, void **out) {
    assert(!request->region);
    size_t bytes = MYL_RC_PREFIX_BYTES + request->element->size * request->count;
    if (heap->limit && bytes > heap->limit - heap->bytes) return MYL_RC_ALLOCATION_REFUSED;
    myl_rc_object *object = calloc(1, bytes);
    if (!object) return MYL_RC_ALLOCATION_REFUSED;
    object->owners = 1;
    object->common.mark = request->count << MYL_NATIVE_OBJECT_COUNT_SHIFT;
    object->common.element = request->element;
    *out = object + 1;
    heap->bytes += bytes;
    TestAllocator *state = myl_rc_allocator_context(heap);
    ++state->live;
    ++state->allocations;
    return MYL_RC_OK;
}
static void retire(myl_native_heap *heap, void *payload) {
    myl_rc_object *object = (myl_rc_object *)payload - 1;
    assert(object->common.mark & MYL_RC_OBJECT_DYING);
    size_t count = (object->common.mark & MYL_NATIVE_OBJECT_COUNT_BITS) >> MYL_NATIVE_OBJECT_COUNT_SHIFT;
    heap->bytes -= MYL_RC_PREFIX_BYTES + count * object->common.element->size;
    TestAllocator *state = myl_rc_allocator_context(heap);
    --state->live;
    ++state->retired;
    free(object);
}
static void destroy(myl_native_heap *heap) {
    TestAllocator *state = myl_rc_allocator_context(heap);
    assert(state->live == 0);
}
static const myl_rc_allocator allocator = {allocate, retire, destroy, NULL};
static const myl_rc_shape pointer_shape = {.size = sizeof(void *), .kind = MYL_RC_SHAPE_POINTER};
static const myl_rc_shape scalar_shape = {.size = sizeof(uint64_t), .kind = MYL_RC_SHAPE_NONE};
static const myl_native_type scalar_type = {.size = sizeof(uint64_t), .alignment = _Alignof(uint64_t), .kind = MYL_NATIVE_PLAIN};
static const myl_rc_descriptor scalar_descriptor = {.type = &scalar_type, .shape = &scalar_shape};
static const myl_rc_shape *const scalar_shapes[] = {&pointer_shape};
static const myl_rc_module scalar_module = {
    .abi = MYL_RC_ABI_VERSION, .shapes = scalar_shapes, .shape_count = 1,
    .descriptors = &scalar_descriptor, .descriptor_count = 1
};
static void start(myl_native_heap *heap, TestAllocator *state) {
    *heap = (myl_native_heap){.limit = ((size_t)256) << 20};
    *state = (TestAllocator){0};
    assert(myl_rc_heap_init(heap, &allocator, state) == MYL_RC_OK);
    assert(myl_rc_module_register(heap, &scalar_module) == MYL_RC_OK);
}
static void *new_value(myl_native_heap *heap, const myl_native_type *type, size_t count) {
    myl_rc_alloc_request request = {.element = type, .count = count};
    void *out = NULL;
    assert(myl_rc_new(heap, &request, &out) == MYL_RC_OK);
    return out;
}
static void finish(myl_native_heap *heap, TestAllocator *state) {
    myl_rc_heap_destroy(heap);
    assert(!heap->rc && !heap->bytes && state->live == 0 && state->allocations == state->retired);
}
// spec-case: RC-COUNTS-1
static void invariant_paths_test(void) {
    volatile unsigned evaluations = 0;
    myl_rc_invariant(++evaluations == 1);
    assert(evaluations == 1);
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        struct rlimit no_core = {0, 0};
        assert(!setrlimit(RLIMIT_CORE, &no_core));
        myl_rc_invariant(0);
        _exit(99);
    }
    int status;
    pid_t finished;
    do { finished = waitpid(child, &status, 0); } while (finished < 0 && errno == EINTR);
    assert(finished == child && WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
}
// spec: RC-LAYOUT-1
static void layout_test(void) {
    assert(sizeof(myl_rc_object) == 32);
    assert(sizeof(myl_native_object) == 16);
    assert(offsetof(myl_rc_object, common.mark) == 16);
    assert(offsetof(myl_rc_object, common.element) == 24);
    assert(offsetof(myl_native_heap, inline_windows) == MYL_NATIVE_HEAP_INLINE_OFFSET);
    assert(offsetof(myl_native_heap, arena_window) == MYL_NATIVE_HEAP_ARENA_OFFSET);
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    void *value = new_value(&heap, &scalar_type, 1);
    assert((uintptr_t)value % 16 == 0);
    assert(*((uintptr_t *)value - 4) == 1 && *((uintptr_t *)value - 3) == 0);
    assert(*((uintptr_t *)value - 2) == 4);
    assert(((const myl_native_type **)value)[-1] == &scalar_type);
    myl_rc_owner_release(&heap, value);
    finish(&heap, &state);
}
// spec: RC-COUNTS-1
static void hold_and_pin_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    void *value = new_value(&heap, &scalar_type, 1);
    myl_rc_object *object = (myl_rc_object *)value - 1;
    myl_rc_pin outer = {0}, inner = {0};
    assert(myl_rc_pin_acquire(&heap, value, &outer) == MYL_RC_OK);
    assert(myl_rc_pin_acquire(&heap, value, &inner) == MYL_RC_OK);
    assert(object->owners == 1 && object->holds == 2 && myl_rc_unique(&heap, value));
    assert(myl_rc_owner_acquire(&heap, value) == MYL_RC_OK);
    assert(!myl_rc_unique(&heap, value));
    myl_rc_owner_release(&heap, value);
    myl_rc_owner_release(&heap, value);
    assert(object->owners == 0 && object->holds == 2 && state.live == 1);
    myl_rc_pin_release(&heap, &inner);
    assert(object->holds == 1 && (object->common.mark & MYL_NATIVE_OBJECT_PINNED));
    myl_rc_pin_release(&heap, &outer);
    assert(!state.live && state.retired == 1);
    finish(&heap, &state);
}
// spec: RC-COUNTS-1
static void prefix_guard_and_limits_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    /* These really have no RC prefix; ASan checks the common-flag guard. */
    const struct { myl_native_object common; uint64_t value; } literal = {
        .common = {.mark = MYL_NATIVE_OBJECT_IMMORTAL, .element = &scalar_type}, .value = 7
    };
    struct { myl_native_object common; uint64_t value; } arena = {
        .common = {.mark = MYL_NATIVE_OBJECT_ARENA | ((uintptr_t)1 << MYL_NATIVE_ARENA_REGION_SHIFT), .element = &scalar_type}
    };
    myl_rc_pin pin = {0};
    assert(myl_rc_owner_acquire(&heap, (void *)&literal.value) == MYL_RC_OK);
    assert(myl_rc_pin_acquire(&heap, (void *)&literal.value, &pin) == MYL_RC_OK);
    myl_rc_pin_release(&heap, &pin);
    myl_rc_owner_release(&heap, (void *)&literal.value);
    assert(myl_rc_pin_acquire(&heap, &arena.value, &pin) == MYL_RC_OK);
    assert(myl_rc_unique(&heap, &arena.value));
    myl_rc_pin_release(&heap, &pin);
    myl_rc_owner_release(&heap, &arena.value);
    void *value = new_value(&heap, &scalar_type, 1);
    myl_rc_object *object = (myl_rc_object *)value - 1;
    object->owners = MYL_RC_COUNT_MAX;
    assert(myl_rc_owner_acquire(&heap, value) == MYL_RC_COUNT_LIMIT);
    assert(object->owners == MYL_RC_COUNT_MAX);
    object->owners = 1;
    object->holds = MYL_RC_COUNT_MAX;
    myl_rc_hold hold = {0};
    assert(myl_rc_hold_acquire(&heap, value, &hold) == MYL_RC_COUNT_LIMIT);
    assert(!hold.payload && object->holds == MYL_RC_COUNT_MAX);
    object->holds = 0;
    assert(!strcmp(myl_rc_status_code(MYL_RC_COUNT_LIMIT), "R_REFERENCE_COUNT_LIMIT"));
    myl_rc_record_failure(&heap, MYL_RC_COUNT_LIMIT);
    myl_rc_record_failure(&heap, MYL_RC_ALLOCATION_REFUSED);
    assert(myl_rc_take_failure(&heap) == MYL_RC_COUNT_LIMIT);
    assert(myl_rc_take_failure(&heap) == MYL_RC_OK);
    myl_rc_owner_release(&heap, value);
    finish(&heap, &state);
}
/* Build arbitrarily deep inline metadata without consuming native stack. */
static myl_rc_shape *deep_shapes(size_t depth, myl_rc_field **fields_out) {
    myl_rc_shape *shapes = calloc(depth + 1, sizeof *shapes);
    myl_rc_field *fields = calloc(depth, sizeof *fields);
    assert(shapes && fields);
    shapes[depth] = pointer_shape;
    for (size_t i = 0; i < depth; ++i) {
        fields[i].shape = &shapes[i + 1];
        shapes[i] = (myl_rc_shape){.size = sizeof(void *), .kind = MYL_RC_SHAPE_RECORD,
            .as.record = {.fields = &fields[i], .count = 1}};
    }
    *fields_out = fields;
    return shapes;
}
// spec: RC-REGISTER-1
static void reservation_failure_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    void *old = new_value(&heap, &scalar_type, 1);
    size_t before = heap.bytes, reserved = myl_rc_reserved_depth(&heap);
    size_t metadata = myl_rc_metadata_bytes(&heap);
    myl_rc_field *fields;
    myl_rc_shape *shapes = deep_shapes(64, &fields);
    const myl_rc_shape *imported = NULL;
    size_t refusals = 0;
    for (size_t allowance = 0; allowance < ((size_t)1 << 20); allowance += 127) {
        heap.limit = before + allowance;
        myl_rc_status status = myl_rc_shape_import(&heap, shapes, &imported);
        if (status == MYL_RC_OK) break;
        ++refusals;
        assert(status == MYL_RC_ALLOCATION_REFUSED && imported == NULL);
        assert(heap.bytes == before && myl_rc_metadata_bytes(&heap) == metadata);
        assert(myl_rc_reserved_depth(&heap) == reserved);
        assert(myl_rc_shape_resolve(&heap, &pointer_shape));
        assert(myl_rc_descriptor_find(&heap, &scalar_type));
    }
    assert(imported && refusals > 20 && myl_rc_reserved_depth(&heap) == 65);
    free(shapes);
    free(fields);
    /* Source addresses have no lifetime/identity after import; even reusing
     * stack storage for a different shape produces independent metadata. */
    myl_rc_shape local = pointer_shape;
    const myl_rc_shape *first, *second;
    heap.limit = ((size_t)256) << 20;
    assert(myl_rc_shape_import(&heap, &local, &first) == MYL_RC_OK);
    local = scalar_shape;
    assert(myl_rc_shape_import(&heap, &local, &second) == MYL_RC_OK);
    assert(first != second && first->kind == MYL_RC_SHAPE_POINTER && second->kind == MYL_RC_SHAPE_NONE);
    myl_rc_slot slot = {.shape = imported, .address = &old};
    heap.limit = heap.bytes;
    myl_rc_value_drop(&heap, &slot);
    assert(!old && state.live == 0);
    finish(&heap, &state);
}
// spec: RC-REGISTER-1
static void deep_inline_and_overflow_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    myl_rc_field *fields;
    myl_rc_shape *shapes = deep_shapes(32768, &fields);
    const myl_rc_shape *imported;
    assert(myl_rc_shape_import(&heap, shapes, &imported) == MYL_RC_OK);
    assert(myl_rc_reserved_depth(&heap) == 32769);
    free(shapes);
    free(fields);
    struct { myl_native_object header; uint64_t value; } arena = {
        .header = {.mark = MYL_NATIVE_OBJECT_ARENA | ((uintptr_t)7 << MYL_NATIVE_ARENA_REGION_SHIFT), .element = &scalar_type}
    };
    void *borrowed = &arena.value;
    heap.limit = heap.bytes;
    assert(myl_rc_value_region(&heap, imported, &borrowed) == 7 && borrowed == &arena.value);
    heap.limit = ((size_t)256) << 20;
    void *value = new_value(&heap, &scalar_type, 1);
    myl_rc_slot slot = {.shape = imported, .address = &value};
    heap.limit = heap.bytes;
    myl_rc_value_drop(&heap, &slot);
    assert(value == NULL && state.live == 0);
    myl_rc_shape overflow = {.size = SIZE_MAX, .kind = MYL_RC_SHAPE_ARRAY,
        .as.array = {.element = &pointer_shape, .count = SIZE_MAX, .stride = sizeof(void *)}};
    size_t before = heap.bytes;
    heap.limit = ((size_t)256) << 20;
    assert(myl_rc_shape_import(&heap, &overflow, &imported) == MYL_RC_ALLOCATION_REFUSED);
    assert(!imported && heap.bytes == before && myl_rc_reserved_depth(&heap) == 32769);
    finish(&heap, &state);
}
typedef struct { uint32_t tag; void *pointer; } Variant;
static const myl_rc_field variant_fields[] = {{.offset = offsetof(Variant, pointer), .shape = &pointer_shape, .tag = 1}};
static const myl_rc_shape variant_shape = {.size = sizeof(Variant), .kind = MYL_RC_SHAPE_VARIANT,
    .as.variant = {.fields = variant_fields, .count = 1, .tag_offset = offsetof(Variant, tag)}};
typedef struct { uint32_t tag; Variant value; } OuterVariant;
static const myl_rc_field outer_fields[] = {{.offset = offsetof(OuterVariant, value), .shape = &variant_shape, .tag = 2}};
static const myl_rc_shape outer_shape = {.size = sizeof(OuterVariant), .kind = MYL_RC_SHAPE_VARIANT,
    .as.variant = {.fields = outer_fields, .count = 1, .tag_offset = offsetof(OuterVariant, tag)}};
// spec: RC-RELEASE-1
static void variants_and_wide_array_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    const myl_rc_shape *variant;
    assert(myl_rc_shape_import(&heap, &outer_shape, &variant) == MYL_RC_OK);
    OuterVariant values[3] = {{.tag = 0, .value = {.tag = 1, .pointer = (void *)(uintptr_t)1}},
        {.tag = 2, .value = {.tag = 0, .pointer = (void *)(uintptr_t)1}},
        {.tag = 2, .value = {.tag = 1, .pointer = new_value(&heap, &scalar_type, 1)}}};
    OuterVariant seeded;
    myl_rc_value_seed(&heap, variant, &seeded, &values[2], 1);
    assert(seeded.tag == 2 && seeded.value.tag == 1 && !seeded.value.pointer);
    assert(values[2].value.pointer && ((myl_rc_object *)values[2].value.pointer - 1)->owners == 1);
    myl_rc_edges_release(&heap, variant, values, 3);
    myl_rc_drain(&heap);
    assert(state.live == 0 && state.retired == 1);
    const size_t count = 100000;
    myl_rc_shape array = {.size = count * sizeof(void *), .kind = MYL_RC_SHAPE_ARRAY,
        .as.array = {.element = &pointer_shape, .count = count, .stride = sizeof(void *)}};
    const myl_rc_shape *registered;
    assert(myl_rc_shape_import(&heap, &array, &registered) == MYL_RC_OK);
    void **edges = calloc(count, sizeof *edges);
    assert(edges);
    void *shared = new_value(&heap, &scalar_type, 1);
    for (size_t i = 0; i < count; ++i) {
        edges[i] = shared;
        assert(myl_rc_owner_acquire(&heap, shared) == MYL_RC_OK);
    }
    myl_rc_owner_release(&heap, shared);
    heap.limit = heap.bytes;
    myl_rc_slot slot = {.shape = registered, .address = edges};
    myl_rc_value_drop(&heap, &slot);
    assert(state.live == 0 && state.retired == 2);
    free(edges);
    finish(&heap, &state);
}
typedef struct Node { struct Node *next; } Node;
static const myl_rc_field node_fields[] = {{.offset = offsetof(Node, next), .shape = &pointer_shape}};
static const myl_rc_shape node_shape = {.size = sizeof(Node), .kind = MYL_RC_SHAPE_RECORD,
    .as.record = {.fields = node_fields, .count = 1}};
static const myl_native_type node_type = {.size = sizeof(Node), .alignment = _Alignof(Node), .kind = MYL_NATIVE_RECORD};
static const myl_rc_descriptor node_descriptor = {.type = &node_type, .shape = &node_shape};
static const myl_rc_module node_module = {.abi = MYL_RC_ABI_VERSION, .descriptors = &node_descriptor, .descriptor_count = 1};
// spec: RC-RELEASE-1
static void million_chain_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    assert(myl_rc_module_register(&heap, &node_module) == MYL_RC_OK);
    size_t bytes = heap.bytes;
    assert(myl_rc_module_register(&heap, &node_module) == MYL_RC_OK);
    assert(heap.bytes == bytes);
    Node *head = NULL;
    for (size_t i = 0; i < 1000000; ++i) {
        Node *next = new_value(&heap, &node_type, 1);
        next->next = head; /* transfer the already-owned result into one edge */
        head = next;
    }
    heap.limit = heap.bytes;
    myl_rc_owner_release(&heap, head);
    assert(state.retired == 1000000 && state.live == 0 && heap.bytes == bytes);
    finish(&heap, &state);
}
static void finalizer(myl_native_heap *heap, void *payload) {
    Node *owner = payload;
    assert(owner->next && *(uint64_t *)owner->next == 73);
    assert(((myl_rc_object *)owner->next - 1)->owners == 1);
    TestAllocator *state = myl_rc_allocator_context(heap);
    if (state->expect_unpinned)
        assert(!(((myl_native_object *)state->expect_unpinned - 1)->mark & MYL_NATIVE_OBJECT_PINNED));
    ++state->finalizing;
    if (state->finalizing > state->max_finalizing) state->max_finalizing = state->finalizing;
    myl_rc_field *fields;
    myl_rc_shape *shapes = deep_shapes(128, &fields);
    const myl_rc_shape *imported;
    assert(myl_rc_shape_import(heap, shapes, &imported) == MYL_RC_OK);
    free(shapes);
    free(fields);
    void *child = new_value(heap, &scalar_type, 1);
    myl_rc_owner_release(heap, child); /* enqueue while the outer drain owns the loop */
    assert(state->live >= 2);
    --state->finalizing;
}
static const myl_native_type resource_type = {.size = sizeof(Node), .alignment = _Alignof(Node), .kind = MYL_NATIVE_RESOURCE};
static const myl_rc_descriptor resource_descriptor = {.type = &resource_type, .shape = &node_shape, .finalize = finalizer};
static const myl_rc_module resource_module = {.abi = MYL_RC_ABI_VERSION, .descriptors = &resource_descriptor, .descriptor_count = 1};
// spec: RC-REGISTER-1
static void temporary_binding_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    static const myl_native_type type = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER};
    const myl_rc_shape *shape;
    assert(myl_rc_shape_import(&heap, &pointer_shape, &shape) == MYL_RC_OK);
    myl_rc_descriptor descriptor = {.type = &type, .shape = shape};
    size_t before = heap.bytes;
    heap.limit = before;
    assert(myl_rc_descriptor_register(&heap, &descriptor) == MYL_RC_ALLOCATION_REFUSED);
    assert(heap.bytes == before && !myl_rc_descriptor_find(&heap, &type));
    heap.limit = ((size_t)256) << 20;
    assert(myl_rc_descriptor_register(&heap, &descriptor) == MYL_RC_OK);
    descriptor = (myl_rc_descriptor){0};
    assert(myl_rc_descriptor_find(&heap, &type)->shape == shape);
    void **box = new_value(&heap, &type, 1);
    *box = new_value(&heap, &scalar_type, 1);
    myl_rc_owner_release(&heap, box);
    assert(state.retired == 2);
    static const myl_native_type other = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER};
    descriptor = (myl_rc_descriptor){.type = &other, .shape = &pointer_shape};
    before = heap.bytes;
    heap.limit = before + 800;
    assert(myl_rc_descriptor_import(&heap, &descriptor) == MYL_RC_ALLOCATION_REFUSED);
    assert(heap.bytes == before && !myl_rc_descriptor_find(&heap, &other));
    heap.limit = ((size_t)256) << 20;
    assert(myl_rc_descriptor_import(&heap, &descriptor) == MYL_RC_OK);
    assert(myl_rc_descriptor_find(&heap, &other)->shape->kind == MYL_RC_SHAPE_POINTER);
    finish(&heap, &state);
}
// spec: RC-RELEASE-1
static void reentrant_finalizer_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    assert(myl_rc_module_register(&heap, &resource_module) == MYL_RC_OK);
    Node *value = new_value(&heap, &resource_type, 1);
    value->next = new_value(&heap, &scalar_type, 1);
    *(uint64_t *)value->next = 73;
    myl_rc_owner_release(&heap, value);
    assert(state.live == 0 && state.retired == 3 && state.max_finalizing == 1);
    assert(myl_rc_reserved_depth(&heap) == 129);
    finish(&heap, &state);
}
static void take_during_finalize(myl_native_heap *heap, void *payload) {
    Node *owner = payload;
    TestAllocator *state = myl_rc_allocator_context(heap);
    assert(heap->rc->dead.active && !heap->rc->walk.depth && !state->retired);
    for (unsigned i = 0; i < 2; ++i) {
        void *sibling = new_value(heap, &scalar_type, 1);
        myl_rc_owner_release(heap, sibling);
    }
    assert(heap->rc->dead.head && state->live == 4 && !state->retired);
    void *moved = NULL, *original = owner->next;
    myl_rc_slot source = {.shape = &pointer_shape, .address = &owner->next};
    myl_rc_slot destination = {.shape = &pointer_shape, .address = &moved};
    /* Models a guest's proven raw TAKE during callback reentry: no publication
     * or counts change, and the active outer drain retains all queued siblings. */
    myl_rc_value_relocate(&destination, &source);
    assert(!owner->next && moved == original && ((myl_rc_object *)moved - 1)->owners == 1);
    myl_rc_value_drop(heap, &destination);
    assert(!moved && state->live == 4 && !state->retired && heap->rc->dead.head);
}
// spec-case: RC-RELEASE-1
static void reentrant_relocation_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    const myl_rc_descriptor descriptor = {.type = &resource_type, .shape = &node_shape, .finalize = take_during_finalize};
    assert(myl_rc_descriptor_import(&heap, &descriptor) == MYL_RC_OK);
    Node *value = new_value(&heap, &resource_type, 1);
    value->next = new_value(&heap, &scalar_type, 1);
    myl_rc_owner_release(&heap, value);
    assert(!heap.rc->dead.active && !heap.rc->dead.head && !state.live && state.retired == 4);
    finish(&heap, &state);
}
static void registering_retire(myl_native_heap *heap, void *payload) {
    TestAllocator *state = myl_rc_allocator_context(heap);
    if (!state->retired) {
        static myl_native_type types[64];
        const myl_native_type *old_type = ((const myl_native_object *)payload - 1)->element;
        const myl_rc_descriptor *old = myl_rc_descriptor_repeat(heap, old_type);
        size_t capacity = heap->rc->metadata.bindings.mask;
        for (size_t i = 0; i < 64; ++i) {
            types[i] = scalar_type;
            myl_rc_descriptor descriptor = {.type = &types[i], .shape = &scalar_shape};
            assert(myl_rc_descriptor_import(heap, &descriptor) == MYL_RC_OK);
        }
        assert(heap->rc->metadata.bindings.mask > capacity);
        assert(myl_rc_descriptor_repeat(heap, old_type) == old);
    }
    retire(heap, payload);
}
// spec: RC-DRAIN-CACHE-1
static void drain_cache_registration_test(void) {
    static const myl_native_type pointer = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_POINTER};
    static const myl_native_field fields_a[] = {{.type = &scalar_type}, {.offset = 8, .type = &pointer}};
    static const myl_native_field fields_b[] = {{.type = &pointer}, {.offset = 8, .type = &scalar_type}};
    static const myl_native_type types[] = {
        {.size = 16, .alignment = 8, .kind = MYL_NATIVE_RECORD, .fields = fields_a, .field_count = 2},
        {.size = 16, .alignment = 8, .kind = MYL_NATIVE_RECORD, .fields = fields_b, .field_count = 2}};
    static const myl_rc_field edges_a[] = {{.shape = &scalar_shape}, {.offset = 8, .shape = &pointer_shape}};
    static const myl_rc_field edges_b[] = {{.shape = &pointer_shape}, {.offset = 8, .shape = &scalar_shape}};
    static const myl_rc_shape shapes[] = {
        {.size = 16, .kind = MYL_RC_SHAPE_RECORD, .as.record = {edges_a, 2}},
        {.size = 16, .kind = MYL_RC_SHAPE_RECORD, .as.record = {edges_b, 2}}};
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    assert(myl_rc_module_register(&heap, &resource_module) == MYL_RC_OK);
    for (unsigned i = 0; i < 2; ++i) {
        myl_rc_descriptor descriptor = {.type = &types[i], .shape = &shapes[i]};
        assert(myl_rc_descriptor_import(&heap, &descriptor) == MYL_RC_OK);
        assert(((const myl_rc_binding *)myl_rc_descriptor_find(&heap, &types[i]))->flat.count == 1);
    }
    Node *last = new_value(&heap, &resource_type, 1);
    last->next = new_value(&heap, &scalar_type, 1);
    *(uint64_t *)last->next = 73;
    void *head = last;
    for (unsigned i = 0; i < 64; ++i) {
        unsigned kind = (i / 2) % 2, edge = kind ? 0 : 8;
        unsigned char *next = new_value(&heap, &types[kind], 1);
        memset(next, 0xa5, 16);
        memcpy(next + edge, &head, sizeof head);
        head = next;
    }
    heap.rc->allocator.hooks.retire = registering_retire;
    myl_rc_owner_release(&heap, head);
    assert(state.retired == 67 && !state.live && state.max_finalizing == 1);
    assert(!heap.rc->dead.active && !heap.rc->dead.head);
    finish(&heap, &state);
}
// spec: RC-TRANSFER-1
static void pointer_transfers_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    void *source = new_value(&heap, &scalar_type, 1), *destination = NULL;
    *(uint64_t *)source = 47;
    myl_rc_slot from = {.shape = &pointer_shape, .address = &source};
    myl_rc_slot to = {.shape = &pointer_shape, .address = &destination};
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_OK);
    assert(source == destination && ((myl_rc_object *)source - 1)->owners == 2);
    myl_rc_value_drop(&heap, &to);
    myl_rc_pin pin = {0};
    assert(myl_rc_pin_acquire(&heap, source, &pin) == MYL_RC_OK);
    void *held = source;
    assert(myl_rc_value_take(&heap, &to, &from) == MYL_RC_OK);
    assert(!source && destination != held && *(uint64_t *)destination == 47);
    assert(((myl_rc_object *)held - 1)->owners == 0 && ((myl_rc_object *)held - 1)->holds == 1);
    myl_rc_value_drop(&heap, &to);
    myl_rc_pin_release(&heap, &pin);
    source = new_value(&heap, &scalar_type, 1);
    ((myl_rc_object *)source - 1)->owners = MYL_RC_COUNT_MAX;
    assert(myl_rc_value_take(&heap, &to, &from) == MYL_RC_OK);
    assert(!source && ((myl_rc_object *)destination - 1)->owners == MYL_RC_COUNT_MAX);
    ((myl_rc_object *)destination - 1)->owners = 1;
    myl_rc_value_drop(&heap, &to);
    source = new_value(&heap, &scalar_type, 1);
    destination = new_value(&heap, &scalar_type, 1);
    heap.limit = heap.bytes;
    assert(myl_rc_value_replace(&heap, &to, &from, MYL_RC_COPY) == MYL_RC_OK);
    assert(source == destination && ((myl_rc_object *)source - 1)->owners == 2);
    myl_rc_value_drop(&heap, &to);
    myl_rc_value_drop(&heap, &from);
    uint64_t old_scalar = 3, fresh_scalar = 5;
    to = (myl_rc_slot){.shape = &scalar_shape, .address = &old_scalar};
    from = (myl_rc_slot){.shape = &scalar_shape, .address = &fresh_scalar};
    heap.limit = heap.bytes;
    assert(myl_rc_value_replace(&heap, &to, &from, MYL_RC_COPY) == MYL_RC_OK);
    assert(old_scalar == 5 && fresh_scalar == 5);
    finish(&heap, &state);
}
typedef struct { void *first, *second; } Pair;
static const myl_rc_field pair_fields[] = {
    {.offset = offsetof(Pair, first), .shape = &pointer_shape},
    {.offset = offsetof(Pair, second), .shape = &pointer_shape}
};
static const myl_rc_shape pair_shape = {.size = sizeof(Pair), .kind = MYL_RC_SHAPE_RECORD,
    .as.record = {.fields = pair_fields, .count = 2}};
// spec: RC-TRANSFER-1
static void transfer_failure_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    const myl_rc_shape *shape;
    assert(myl_rc_shape_import(&heap, &pair_shape, &shape) == MYL_RC_OK);
    Pair source = {new_value(&heap, &scalar_type, 1), new_value(&heap, &scalar_type, 1)}, destination = {0};
    myl_rc_slot from = {.shape = shape, .address = &source};
    myl_rc_slot to = {.shape = shape, .address = &destination};
    myl_rc_object *first = (myl_rc_object *)source.first - 1, *second = (myl_rc_object *)source.second - 1;
    second->owners = MYL_RC_COUNT_MAX;
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_COUNT_LIMIT);
    assert(!destination.first && !destination.second && first->owners == 1 && second->owners == MYL_RC_COUNT_MAX);
    myl_rc_slot sources[2] = {{.shape = &pointer_shape, .address = &source.first},
        {.shape = &pointer_shape, .address = &source.second}};
    myl_rc_slot destinations[2] = {{.shape = &pointer_shape, .address = &destination.first},
        {.shape = &pointer_shape, .address = &destination.second}};
    assert(myl_rc_value_copy_many(&heap, destinations, sources, 2) == MYL_RC_COUNT_LIMIT);
    assert(!destination.first && !destination.second && first->owners == 1 && second->owners == MYL_RC_COUNT_MAX);
    second->owners = 1;
    myl_rc_pin pins[2] = {0};
    assert(myl_rc_pin_acquire(&heap, source.first, &pins[0]) == MYL_RC_OK);
    assert(myl_rc_pin_acquire(&heap, source.second, &pins[1]) == MYL_RC_OK);
    size_t before = heap.bytes;
    /* Inline operation frames reserve no heap bytes. One 40-byte clone fits;
     * the second refuses after the first acquired a real temporary owner. */
    heap.limit = before + 40;
    assert(myl_rc_value_take(&heap, &to, &from) == MYL_RC_ALLOCATION_REFUSED);
    assert(!destination.first && !destination.second && first->owners == 1 && second->owners == 1);
    assert(heap.bytes == before && state.live == 2);
    heap.limit = ((size_t)256) << 20;
    myl_rc_pin_release(&heap, &pins[1]);
    myl_rc_pin_release(&heap, &pins[0]);
    myl_rc_value_drop(&heap, &from);
    finish(&heap, &state);
}
// spec: RC-TRANSFER-1
static void uniqueness_and_alias_replace_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    void *source = new_value(&heap, &scalar_type, 1);
    assert(myl_rc_owner_acquire(&heap, source) == MYL_RC_OK);
    void *alias = source;
    myl_rc_slot slot = {.shape = &pointer_shape, .address = &source};
    myl_rc_edit edit = {0};
    assert(myl_rc_unique_borrow(&heap, &slot, NULL, &edit) == MYL_RC_OK);
    assert(edit.owned && edit.payload != source && ((myl_rc_object *)source - 1)->owners == 2);
    myl_rc_edit_abort(&heap, &edit);
    assert(!edit.owned && !edit.payload && state.live == 1);
    assert(myl_rc_unique_borrow(&heap, &slot, NULL, &edit) == MYL_RC_OK);
    myl_rc_edit_commit(&heap, &slot, &edit);
    assert(source != alias && ((myl_rc_object *)alias - 1)->owners == 1);
    assert(myl_rc_unique_borrow(&heap, &slot, NULL, &edit) == MYL_RC_OK);
    assert(!edit.owned && edit.payload == source);
    myl_rc_edit_commit(&heap, &slot, &edit);
    myl_rc_value_drop(&heap, &slot);
    myl_rc_owner_release(&heap, alias);
    assert(myl_rc_module_register(&heap, &node_module) == MYL_RC_OK);
    Node *parent = new_value(&heap, &node_type, 1);
    parent->next = new_value(&heap, &scalar_type, 1);
    *(uint64_t *)parent->next = 59;
    myl_rc_slot from = {.shape = &pointer_shape, .address = &parent->next};
    myl_rc_slot to = {.shape = &pointer_shape, .address = &parent};
    assert(myl_rc_value_replace(&heap, &to, &from, MYL_RC_COPY) == MYL_RC_OK);
    assert(*(uint64_t *)parent == 59 && state.live == 1);
    myl_rc_value_drop(&heap, &to);
    struct { myl_native_object header; Node node; } arena = {
        .header = {.mark = MYL_NATIVE_OBJECT_ARENA | ((uintptr_t)1 << MYL_NATIVE_ARENA_REGION_SHIFT) |
            ((uintptr_t)1 << MYL_NATIVE_OBJECT_COUNT_SHIFT), .element = &node_type},
        .node = {.next = new_value(&heap, &scalar_type, 1)}
    };
    edit = (myl_rc_edit){.payload = &arena.node, .owned = 1};
    myl_rc_edit_abort(&heap, &edit);
    assert(!edit.payload && !edit.owned);
    assert(!arena.node.next && state.live == 0);
    myl_rc_construction_abort(&heap, &arena.node);
    assert(state.live == 0);
    finish(&heap, &state);
}
// spec: RC-REGISTER-1
static void many_bindings_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    const size_t count = 4096;
    myl_native_type *types = calloc(count, sizeof *types);
    void **values = calloc(count, sizeof *values);
    assert(types && values);
    for (size_t i = 0; i < count; ++i) {
        types[i] = scalar_type;
        myl_rc_descriptor descriptor = {.type = &types[i], .shape = &scalar_shape};
        assert(myl_rc_descriptor_import(&heap, &descriptor) == MYL_RC_OK);
        values[i] = new_value(&heap, &types[i], 1);
        *(uint64_t *)values[i] = i;
    }
    size_t metadata = myl_rc_metadata_bytes(&heap);
    heap.limit = heap.bytes;
    for (size_t i = 0; i < count; ++i) {
        assert(myl_rc_descriptor_find(&heap, &types[i])->type == &types[i]);
        assert(*(uint64_t *)values[i] == i);
        myl_rc_owner_release(&heap, values[i]);
    }
    assert(heap.bytes == metadata && state.retired == count);
    finish(&heap, &state);
    free(values);
    free(types);
}
// spec: RC-TRANSFER-1
static void deep_pinned_clone_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    assert(myl_rc_module_register(&heap, &node_module) == MYL_RC_OK);
    const size_t count = 32768;
    myl_rc_pin *pins = calloc(count, sizeof *pins);
    assert(pins);
    Node *head = NULL;
    for (size_t i = 0; i < count; ++i) {
        Node *node = new_value(&heap, &node_type, 1);
        node->next = head;
        head = node;
        assert(myl_rc_pin_acquire(&heap, node, &pins[i]) == MYL_RC_OK);
    }
    Node *copy = NULL;
    myl_rc_slot from = {.shape = &pointer_shape, .address = &head};
    myl_rc_slot to = {.shape = &pointer_shape, .address = &copy};
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_OK);
    assert(state.live == count * 2);
    Node *old = head, *fresh = copy;
    for (size_t i = 0; i < count; ++i) {
        assert(old && fresh && old != fresh);
        assert(((myl_rc_object *)old - 1)->owners == 1 && ((myl_rc_object *)fresh - 1)->owners == 1);
        old = old->next;
        fresh = fresh->next;
    }
    assert(!old && !fresh);
    myl_rc_value_drop(&heap, &to);
    myl_rc_value_drop(&heap, &from);
    for (size_t i = 0; i < count; ++i) myl_rc_pin_release(&heap, &pins[i]);
    assert(state.live == 0 && state.retired == count * 2);
    free(pins);
    finish(&heap, &state);
}
// spec: RC-SCOPES-1
static void scope_unwind_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    void *value = new_value(&heap, &scalar_type, 1);
    myl_rc_scope outer, inner;
    myl_rc_scope_begin(&heap, &outer);
    assert(myl_rc_scope_pin(&outer, value) == MYL_RC_OK);
    myl_rc_scope_begin(&heap, &inner);
    assert(myl_rc_scope_pin(&inner, value) == MYL_RC_OK);
    myl_rc_owner_release(&heap, value);
    myl_rc_scope_end(&inner);
    assert(((myl_rc_object *)value - 1)->holds == 1 && (((myl_native_object *)value - 1)->mark & MYL_NATIVE_OBJECT_PINNED));
    myl_rc_scope_end(&outer);
    myl_rc_scope_end(&outer);
    assert(state.live == 0);
    assert(myl_rc_module_register(&heap, &resource_module) == MYL_RC_OK);
    Node *resource = new_value(&heap, &resource_type, 1);
    resource->next = new_value(&heap, &scalar_type, 1);
    *(uint64_t *)resource->next = 73;
    state.expect_unpinned = resource->next;
    myl_rc_scope_begin(&heap, &outer);
    assert(myl_rc_scope_pin(&outer, resource->next) == MYL_RC_OK);
    assert(myl_rc_scope_pin(&outer, resource) == MYL_RC_OK);
    myl_rc_owner_release(&heap, resource);
    myl_rc_scope_end(&outer);
    assert(state.live == 0 && state.retired == 4 && !outer.active && !outer.journal);
    finish(&heap, &state);
}
// spec: RC-SCOPES-1
static void partial_scope_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    myl_rc_shape array = {.size = 2 * sizeof(void *), .kind = MYL_RC_SHAPE_ARRAY,
        .as.array = {.element = &pointer_shape, .count = 2, .stride = sizeof(void *)}};
    const myl_rc_shape *shape;
    assert(myl_rc_shape_import(&heap, &array, &shape) == MYL_RC_OK);
    void *values[2] = {new_value(&heap, &scalar_type, 1), new_value(&heap, &scalar_type, 1)};
    myl_rc_object *second = (myl_rc_object *)values[1] - 1;
    second->holds = MYL_RC_COUNT_MAX;
    myl_rc_scope scope;
    myl_rc_scope_begin(&heap, &scope);
    myl_rc_projection projection = {.shape = shape};
    myl_rc_place place = {.receiver = {.shape = shape, .address = values}, .path = &projection, .count = 1};
    size_t before = heap.bytes;
    assert(myl_rc_scope_prepare(&scope, &place) == MYL_RC_COUNT_LIMIT);
    assert(scope.active && !scope.journal && heap.bytes == before);
    assert(((myl_rc_object *)values[0] - 1)->holds == 0);
    assert(!(((myl_native_object *)values[0] - 1)->mark & MYL_NATIVE_OBJECT_PINNED));
    assert(second->holds == MYL_RC_COUNT_MAX && second->owners == 1);
    second->holds = 0;
    assert(myl_rc_scope_prepare(&scope, &place) == MYL_RC_OK);
    assert(((myl_rc_object *)values[0] - 1)->holds == 1 && second->holds == 1);
    myl_rc_scope_end(&scope);
    myl_rc_edges_release(&heap, shape, values, 1);
    myl_rc_drain(&heap);
    assert(state.live == 0);
    finish(&heap, &state);
}
// spec: RC-TRANSFER-1
static void pinned_diamond_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    const myl_native_type pair_type = {.size = sizeof(Pair), .alignment = _Alignof(Pair), .kind = MYL_NATIVE_RECORD};
    const myl_rc_descriptor descriptor = {.type = &pair_type, .shape = &pair_shape};
    assert(myl_rc_descriptor_import(&heap, &descriptor) == MYL_RC_OK);
    enum { depth = 256 };
    myl_rc_pin pins[depth] = {0};
    Pair *head = NULL;
    for (size_t i = 0; i < depth; ++i) {
        Pair *node = new_value(&heap, &pair_type, 1);
        *node = (Pair){head, head};
        assert(myl_rc_owner_acquire(&heap, head) == MYL_RC_OK);
        head = node;
        assert(myl_rc_pin_acquire(&heap, node, &pins[i]) == MYL_RC_OK);
    }
    Pair *copy = NULL;
    myl_rc_slot from = {.shape = &pointer_shape, .address = &head};
    myl_rc_slot to = {.shape = &pointer_shape, .address = &copy};
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_OK);
    assert(state.allocations == depth * 2 && state.live == depth * 2);
    for (Pair *old = head, *fresh = copy; old; old = old->first, fresh = fresh->first)
        assert(fresh && fresh != old && fresh->first == fresh->second);
    myl_rc_value_drop(&heap, &to);
    myl_rc_value_drop(&heap, &from);
    for (size_t i = depth; i; --i) myl_rc_pin_release(&heap, &pins[i - 1]);
    finish(&heap, &state);
}
typedef struct { myl_native_resource base; void **slot; unsigned closed; myl_native_heap *heap; } DeepUnique;
static void deep_unique_close(myl_native_resource *base) {
    DeepUnique *resource = (DeepUnique *)base;
    assert(!*resource->slot);
    ++resource->closed;
    if (resource->heap) {
        myl_rc_field *fields;
        myl_rc_shape *shapes = deep_shapes(32772, &fields);
        const myl_rc_shape *imported;
        assert(myl_rc_shape_import(resource->heap, shapes, &imported) == MYL_RC_OK);
        free(shapes);
        free(fields);
        void *child = new_value(resource->heap, &scalar_type, 1);
        myl_rc_owner_release(resource->heap, child);
    }
}
// spec: RC-RELEASE-1
// spec: RC-REGISTER-1
static void deep_unique_test(void) {
    enum { depth = 32768 };
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    myl_rc_field *fields;
    myl_rc_shape *shapes = deep_shapes(depth, &fields);
    shapes[depth].kind = MYL_RC_SHAPE_NONE;
    myl_native_type *types = calloc(depth + 1, sizeof *types);
    myl_native_field *native_fields = calloc(depth, sizeof *native_fields);
    assert(types && native_fields);
    types[depth] = (myl_native_type){.size = sizeof(void *), .kind = MYL_NATIVE_RESOURCE};
    for (size_t i = 0; i < depth; ++i) {
        native_fields[i].type = &types[i + 1];
        types[i] = (myl_native_type){.size = sizeof(void *), .kind = MYL_NATIVE_RECORD, .fields = &native_fields[i], .field_count = 1};
    }
    const myl_rc_descriptor descriptor = {.type = types, .shape = shapes, .finalize = myl_rc_finalize_unique};
    assert(myl_rc_descriptor_import(&heap, &descriptor) == MYL_RC_OK);
    const myl_rc_shape *collapsed = myl_rc_descriptor_find(&heap, types)->shape;
    assert(collapsed->kind == MYL_RC_SHAPE_NONE && myl_rc_reserved_depth(&heap) == depth + 1);
    /* A new parent around an imported count-free shape must retain its full
     * unique traversal reservation, even though counted traversal is empty. */
    const myl_rc_field outer_field = {.shape = collapsed};
    const myl_rc_shape outer = {.size = sizeof(void *), .kind = MYL_RC_SHAPE_RECORD, .as.record = {&outer_field, 1}};
    const myl_rc_shape *imported;
    assert(myl_rc_shape_import(&heap, &outer, &imported) == MYL_RC_OK);
    assert(imported->kind == MYL_RC_SHAPE_NONE && myl_rc_reserved_depth(&heap) == depth + 2);
    void **body = new_value(&heap, types, 1);
    DeepUnique resource = {.base = {.drop = deep_unique_close}, .slot = body};
    *body = &resource;
    heap.limit = heap.bytes;
    myl_rc_owner_release(&heap, body);
    assert(resource.closed == 1 && state.live == 0);
    heap.limit = ((size_t)256) << 20;
    body = new_value(&heap, types, 1);
    resource = (DeepUnique){.base = {.drop = deep_unique_close}, .slot = body, .heap = &heap};
    *body = &resource;
    myl_rc_owner_release(&heap, body);
    assert(resource.closed == 1 && state.live == 0 && myl_rc_reserved_depth(&heap) == 32773);
    finish(&heap, &state);
    free(types);
    free(native_fields);
    free(shapes);
    free(fields);
}
// spec: RC-TRANSFER-1
static void local_transfer_frames_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    myl_rc_field *small_fields, *large_fields;
    myl_rc_shape *small = deep_shapes(7, &small_fields), *large = deep_shapes(8, &large_fields);
    const myl_rc_shape *small_shape, *large_shape;
    assert(myl_rc_shape_import(&heap, small, &small_shape) == MYL_RC_OK);
    assert(myl_rc_shape_import(&heap, large, &large_shape) == MYL_RC_OK);
    void *source = new_value(&heap, &scalar_type, 1), *destination = NULL;
    myl_rc_slot from = {.shape = small_shape, .address = &source};
    myl_rc_slot to = {.shape = small_shape, .address = &destination};
    size_t bytes = heap.bytes;
    heap.limit = bytes;
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_OK);
    assert(destination == source && ((myl_rc_object *)source - 1)->owners == 2 && heap.bytes == bytes);
    myl_rc_value_drop(&heap, &to);
    from.shape = large_shape;
    to.shape = large_shape;
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_ALLOCATION_REFUSED);
    assert(!destination && ((myl_rc_object *)source - 1)->owners == 1 && heap.bytes == bytes);
    heap.limit = ((size_t)256) << 20;
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_OK);
    assert(destination == source && ((myl_rc_object *)source - 1)->owners == 2 && heap.bytes == bytes);
    myl_rc_value_drop(&heap, &to);
    myl_rc_value_drop(&heap, &from);
    finish(&heap, &state);
    free(small); free(small_fields); free(large); free(large_fields);
}
/* Find deliberate collision keys for a tiny lookup fixture: the placement
 * function is the registry's own home slot, so these keys share one probe run. */
// spec: RC-REGISTER-1
static void repeated_lookup_table_test(void) {
    myl_native_heap heap = {0};
    assert(!myl_rc_descriptor_repeat(NULL, &scalar_type));
    assert(!myl_rc_descriptor_repeat(&heap, &scalar_type));
    myl_rc_state state = {0};
    myl_rc_metadata_init(&state);
    heap.rc = &state;
    assert(!myl_rc_descriptor_repeat(&heap, &scalar_type) && !myl_rc_descriptor_find(&heap, NULL));
    myl_rc_map_entry bindings[8] = {{0}}, shapes[8] = {{0}};
    state.metadata.bindings = (myl_rc_map){.entries = bindings, .mask = 7, .shift = 61};
    state.metadata.shapes = (myl_rc_map){.entries = shapes, .mask = 7, .shift = 61};
    assert(!myl_rc_descriptor_repeat(&heap, &scalar_type));
    myl_native_type types[512] = {0};
    const myl_native_type *keys[4];
    size_t count = 0;
    for (size_t i = 0; i < 512 && count < 4; ++i)
        if (!myl_rc_map_home(&types[i], 61, 7)) keys[count++] = &types[i];
    assert(count == 4);
    myl_rc_binding descriptors[3] = {0};
    for (unsigned i = 0; i < 3; ++i) {
        descriptors[i].descriptor = (myl_rc_descriptor){.type = keys[i], .shape = &scalar_shape};
        bindings[i] = (myl_rc_map_entry){.key = keys[i], .value = &descriptors[i]};
    }
    /* The same key in another registry map must never satisfy a binding hit. */
    shapes[0] = (myl_rc_map_entry){.key = keys[3], .value = &scalar_shape};
    for (unsigned i = 0; i < 32; ++i) {
        assert(myl_rc_descriptor_repeat(&heap, keys[0]) == &descriptors[0].descriptor);
        assert(myl_rc_descriptor_find(&heap, keys[1]) == &descriptors[1].descriptor);
        assert(myl_rc_descriptor_repeat(&heap, keys[2]) == &descriptors[2].descriptor);
        assert(myl_rc_binding_find(&heap, keys[2]) == &descriptors[2]);
        assert(!myl_rc_descriptor_repeat(&heap, keys[3]));
        assert(myl_rc_shape_resolve(&heap, (const myl_rc_shape *)keys[3]) == &scalar_shape);
        assert(!myl_rc_shape_resolve(&heap, (const myl_rc_shape *)keys[0]));
        assert(!myl_rc_descriptor_repeat(&heap, NULL));
    }
    assert(state.metadata.bytes == 0 && state.failure == MYL_RC_OK && !state.dead.head);
}
// spec: RC-REGISTER-1
static void repeated_lookup_growth_test(void) {
    myl_native_heap heap;
    TestAllocator state;
    start(&heap, &state);
    const myl_rc_descriptor *original = myl_rc_descriptor_repeat(&heap, &scalar_type);
    const myl_rc_shape *shape = original->shape;
    myl_native_type types[128];
    const myl_rc_descriptor *bindings[128];
    unsigned growths = 0;
    for (size_t i = 0; i < 128; ++i) {
        types[i] = scalar_type;
        myl_rc_descriptor next = {.type = &types[i], .shape = shape};
        size_t bytes = heap.bytes, capacity = heap.rc->metadata.bindings.mask;
        const myl_rc_map_entry *old = heap.rc->metadata.bindings.entries;
        assert(myl_rc_descriptor_repeat(&heap, &scalar_type) == original);
        assert(!myl_rc_descriptor_repeat(&heap, &types[i]));
        /* Allow the private binding, but no replacement index: exactly the
         * registration transaction's last reservation must refuse on growth. */
        heap.limit = bytes + sizeof(myl_rc_batch) + sizeof(myl_rc_binding);
        myl_rc_status status = myl_rc_descriptor_register(&heap, &next);
        if (status != MYL_RC_OK) {
            assert(status == MYL_RC_ALLOCATION_REFUSED);
            assert(heap.bytes == bytes && heap.rc->metadata.bindings.entries == old);
            assert(heap.rc->metadata.bindings.mask == capacity);
            assert(!myl_rc_descriptor_repeat(&heap, &types[i]));
            assert(myl_rc_descriptor_repeat(&heap, &scalar_type) == original);
            heap.limit = ((size_t)256) << 20;
            assert(myl_rc_descriptor_register(&heap, &next) == MYL_RC_OK);
            assert(heap.rc->metadata.bindings.mask > capacity);
            ++growths;
        }
        heap.limit = ((size_t)256) << 20;
        bindings[i] = myl_rc_descriptor_repeat(&heap, &types[i]);
        for (size_t j = 0; j <= i; ++j)
            assert(myl_rc_descriptor_repeat(&heap, &types[j]) == bindings[j]);
        assert(myl_rc_descriptor_repeat(&heap, &scalar_type) == original);
        assert(myl_rc_shape_resolve(&heap, &scalar_shape) == shape);
        size_t stable = heap.bytes;
        assert(myl_rc_module_register(&heap, &scalar_module) == MYL_RC_OK && heap.bytes == stable);
    }
    assert(growths >= 3 && heap.rc->failure == MYL_RC_OK);
    finish(&heap, &state);
}
static void lookup_only_finalizer(myl_native_heap *heap, void *payload) {
    (void)heap;
    (void)payload;
}
// spec: RC-REGISTER-1
static void repeated_lookup_lifetime_test(void) {
    myl_native_heap first, second;
    TestAllocator a, b;
    start(&first, &a);
    start(&second, &b);
    static const myl_native_type local = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
    myl_rc_descriptor descriptor = {.type = &local, .shape = &scalar_shape};
    assert(myl_rc_descriptor_import(&first, &descriptor) == MYL_RC_OK);
    descriptor.finalize = lookup_only_finalizer;
    assert(myl_rc_descriptor_import(&second, &descriptor) == MYL_RC_OK);
    const myl_rc_descriptor *plain = myl_rc_descriptor_repeat(&first, &local);
    const myl_rc_descriptor *finalized = myl_rc_descriptor_repeat(&second, &local);
    assert(plain != finalized && !plain->finalize && finalized->finalize == lookup_only_finalizer);
    for (unsigned i = 0; i < 64; ++i) {
        assert(myl_rc_descriptor_repeat(&first, &local) == plain);
        assert(myl_rc_descriptor_repeat(&second, &local) == finalized);
    }
    finish(&first, &a);
    start(&first, &a);
    assert(!myl_rc_descriptor_repeat(&first, &local));
    assert(myl_rc_descriptor_import(&first, &descriptor) == MYL_RC_OK);
    assert(myl_rc_descriptor_repeat(&first, &local)->finalize == lookup_only_finalizer);
    assert(myl_rc_descriptor_repeat(&second, &local) == finalized);
    finish(&first, &a);
    finish(&second, &b);
}

int myl_rc_contract_verify(void) {
    struct rlimit stack, original;
    assert(!getrlimit(RLIMIT_STACK, &stack));
    original = stack;
    if (stack.rlim_cur > 262144) { stack.rlim_cur = 262144; assert(!setrlimit(RLIMIT_STACK, &stack)); }
    repeated_lookup_table_test();
    repeated_lookup_growth_test();
    repeated_lookup_lifetime_test();
    invariant_paths_test();
    layout_test();
    hold_and_pin_test();
    prefix_guard_and_limits_test();
    reservation_failure_test();
    deep_inline_and_overflow_test();
    variants_and_wide_array_test();
    million_chain_test();
    reentrant_finalizer_test();
    reentrant_relocation_test();
    drain_cache_registration_test();
    temporary_binding_test();
    pointer_transfers_test();
    transfer_failure_test();
    uniqueness_and_alias_replace_test();
    many_bindings_test();
    deep_pinned_clone_test();
    scope_unwind_test();
    partial_scope_test();
    pinned_diamond_test();
    deep_unique_test();
    local_transfer_frames_test();
    assert(!setrlimit(RLIMIT_STACK, &original));
    return 25;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) {
    assert(myl_rc_contract_verify() == 25);
    puts("native RC contract: 25 tests passed");
    return 0;
}
#endif
