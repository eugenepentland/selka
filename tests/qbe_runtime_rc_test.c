#include "qbe_runtime.h"
#include "native_rc_collections.h"
#include "native_rc_dictionary.h"
#include "native_rc_values.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <setjmp.h>
#include <string.h>
static const myl_rc_shape pointer = {.size = sizeof(void *), .kind = MYL_RC_SHAPE_POINTER};
static const myl_rc_shape *const shapes[] = {&pointer};
const myl_rc_module myl_rc_generated_module = {.abi = MYL_RC_ABI_VERSION, .shapes = shapes, .shape_count = 1};
/* Capture the same status delivered to the located native trap entry. These
 * tests exercise initialization before an active guest frame exists. */
#ifndef MYL_RC_CONTRACT_LIBRARY
void myl_qbe_fail(void *context, const char *code) { MylQbeContext *ctx=context; if (!ctx->trap) ctx->trap=code; }
#endif
static myl_rc_status no_allocate(myl_native_heap *heap, const myl_rc_alloc_request *request, void **out) {
    (void)heap;
    (void)request;
    *out = NULL;
    return MYL_RC_ALLOCATION_REFUSED;
}
static void no_retire(myl_native_heap *heap, void *payload) {
    (void)heap;
    (void)payload;
    assert(0 && "the metadata-only startup fixture allocates no managed payload");
}
static const myl_rc_allocator allocator = {.allocate = no_allocate, .retire = no_retire};
static const myl_native_type pointer_type = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER};
static const myl_rc_descriptor pointer_descriptor = {.type = &pointer_type, .shape = &pointer};
static const myl_native_type resource_type = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_RESOURCE};
typedef struct {
    myl_native_resource base;
    MylQbeContext *context;
    uint32_t *guard;
    myl_rc_object *object;
    unsigned closed;
} FrameResource;
static void close_resource(myl_native_resource *base) {
    FrameResource *resource = (FrameResource *)base;
    assert(!*resource->guard && !resource->object->holds);
    assert(!(resource->object->common.mark & MYL_NATIVE_OBJECT_PINNED));
    assert(resource->object->owners == 2);
    MylQbeRcFrame nested;
    myl_qbe_rc_frame_enter(resource->context, &nested, NULL, 0);
    myl_qbe_rc_frame_leave(resource->context, &nested);
    ++resource->closed;
}
typedef struct {
    MylQbeContext context;
    struct { myl_rc_object header; uintptr_t payload; } value;
    FrameResource resource;
    void *slots[2];
    uint32_t guards[2];
    MylQbeRcSlot entries[2];
    MylQbeRcFrame outer, inner;
    myl_rc_scope scope;
} FrameFixture;
static FrameFixture *frame_fixture(void) {
    FrameFixture *fixture = calloc(1, sizeof *fixture);
    assert(fixture);
    fixture->context.heap.limit = 65536;
    assert(myl_rc_heap_init(&fixture->context.heap, &allocator, NULL) == MYL_RC_OK);
    assert(myl_qbe_rc_initialize(&fixture->context));
    assert(myl_rc_descriptor_register(&fixture->context.heap, &pointer_descriptor) == MYL_RC_OK);
    fixture->value.header.owners = 2;
    fixture->resource = (FrameResource){.base = {.drop = close_resource}, .context = &fixture->context,
        .guard = &fixture->guards[1], .object = &fixture->value.header};
    fixture->slots[0] = &fixture->value.payload;
    fixture->slots[1] = &fixture->resource;
    fixture->guards[0] = fixture->guards[1] = 1;
    fixture->entries[0] = (MylQbeRcSlot){&pointer_type, &fixture->slots[0], &fixture->guards[0], MYL_QBE_RC_COUNTED};
    fixture->entries[1] = (MylQbeRcSlot){&resource_type, &fixture->slots[1], &fixture->guards[1], MYL_QBE_RC_UNIQUE_DROP};
    myl_qbe_rc_frame_enter(&fixture->context, &fixture->outer, NULL, 0);
    myl_qbe_rc_frame_enter(&fixture->context, &fixture->inner, fixture->entries, 2);
    myl_rc_scope_begin(&fixture->context.heap, &fixture->scope);
    assert(myl_rc_scope_pin(&fixture->scope, fixture->slots[0]) == MYL_RC_OK);
    return fixture;
}
static void frame_check(FrameFixture *fixture) {
    assert(fixture->resource.closed == 1 && fixture->value.header.owners == 1);
    assert(!fixture->slots[0] && !fixture->slots[1] && !fixture->guards[0] && !fixture->guards[1]);
    assert(!fixture->scope.active);
}
static void frame_cleanup_test(unsigned prefix) {
    FrameFixture *fixture = frame_fixture();
    if (prefix) myl_qbe_rc_unwind_to(&fixture->context, &fixture->outer);
    else {
        myl_qbe_rc_frame_cleanup(&fixture->context, &fixture->inner);
        myl_qbe_rc_frame_cleanup(&fixture->context, &fixture->inner);
        assert(fixture->context.rc_frames == &fixture->inner);
        myl_qbe_rc_frame_leave(&fixture->context, &fixture->inner);
    }
    frame_check(fixture);
    assert(fixture->context.rc_frames == &fixture->outer);
    myl_qbe_rc_frame_leave(&fixture->context, &fixture->outer);
    myl_rc_heap_destroy(&fixture->context.heap);
    free(fixture);
}
static void frame_trap_test(void) {
    FrameFixture *fixture = frame_fixture();
#ifdef MYL_RC_CONTRACT_LIBRARY
    jmp_buf landing;
    fixture->context.unwind = &landing;
    if (!setjmp(landing)) {
        myl_qbe_fail(&fixture->context, "R_REFERENCE_COUNT_LIMIT");
        assert(0 && "runtime must jump after cleaning live frame storage");
    }
    assert(!strcmp(fixture->context.trap, "R_REFERENCE_COUNT_LIMIT"));
#else
    myl_qbe_rc_unwind(&fixture->context);
#endif
    frame_check(fixture);
    assert(!fixture->context.rc_frames);
    myl_rc_heap_destroy(&fixture->context.heap);
    free(fixture);
}
static void construction_guard_test(void) {
    FrameFixture *fixture = frame_fixture();
    struct { myl_native_object header; void *child; } arena = {
        .header = {.mark = MYL_NATIVE_OBJECT_ARENA | ((uintptr_t)1 << MYL_NATIVE_ARENA_REGION_SHIFT) |
            ((uintptr_t)1 << MYL_NATIVE_OBJECT_COUNT_SHIFT), .element = &pointer_type}, .child = fixture->slots[0]
    };
    fixture->guards[0] = 0;
    fixture->slots[1] = &arena.child;
    fixture->entries[1].type = &pointer_type;
    fixture->entries[1].flags = MYL_QBE_RC_CONSTRUCTION;
    myl_qbe_rc_frame_cleanup(&fixture->context, &fixture->inner);
    assert(!arena.child && !fixture->slots[1] && !fixture->guards[1]);
    assert(fixture->value.header.owners == 1 && !fixture->value.header.holds);
    myl_rc_construction_abort(&fixture->context.heap, &arena.child);
    myl_qbe_rc_frame_leave(&fixture->context, &fixture->inner);
    myl_qbe_rc_frame_leave(&fixture->context, &fixture->outer);
    myl_rc_heap_destroy(&fixture->context.heap);
    free(fixture);
}
static void unique_bridge_test(void) {
    MylQbeContext context = {0};
    myl_native_heap_init(&context.heap, 1u << 20);
    if (!myl_rc_enabled(&context.heap)) assert(myl_rc_storage_init(&context.heap) == MYL_RC_OK);
    assert(myl_qbe_rc_initialize(&context));
    assert(myl_rc_native_shape(&context.heap, &pointer_type));
    static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
    myl_native_list *source = myl_native_list_new(&context.heap, &number, 0), *local = source;
    uint32_t owned = 0;
    assert(source && myl_qbe_rc_unique_local(&context, &pointer_type, &local, &owned));
    assert(!owned && local == source);
    assert(myl_rc_owner_acquire(&context.heap, source) == MYL_RC_OK);
    assert(myl_qbe_rc_unique_local(&context, &pointer_type, &local, &owned));
    assert(owned && local != source && ((myl_rc_object *)source - 1)->owners == 2);
    MylQbeRcSlot slot = {&pointer_type, &local, &owned, MYL_QBE_RC_COUNTED};
    myl_qbe_rc_slot_drop(&context, &slot);
    myl_rc_owner_release(&context.heap, source);
    local = source;
    assert(myl_rc_owner_acquire(&context.heap, source) == MYL_RC_OK);
    assert(myl_qbe_rc_unique_field(&context, &pointer_type, &local, NULL));
    assert(local != source && ((myl_rc_object *)source - 1)->owners == 1);
    myl_rc_owner_release(&context.heap, local);
    myl_rc_owner_release(&context.heap, source);
    myl_native_heap_destroy(&context.heap);
    assert(!context.heap.bytes);
}
static const myl_native_type pointer_list = {.size = sizeof(void *), .alignment = _Alignof(void *),
    .kind = MYL_NATIVE_POINTER, .collection_kind = 1, .element = &pointer_type};
// spec-case: RC-FRAME-1
static void unique_elements_refusal_test(void) {
    MylQbeContext context = {0};
    myl_native_heap_init(&context.heap, 1u << 20);
    if (!myl_rc_enabled(&context.heap)) assert(myl_rc_storage_init(&context.heap) == MYL_RC_OK);
    static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
    myl_native_list *first = myl_native_list_new(&context.heap, &number, 1);
    myl_native_list *second = myl_native_list_new(&context.heap, &pointer_type, 1);
    myl_native_list *outer = myl_native_list_new(&context.heap, &pointer_type, 3);
    void *leaf = myl_rc_storage_bytes(&context.heap, 8, 0);
    uint64_t value = 73;
    assert(first && second && outer && leaf);
    assert(myl_rc_list_append(&context.heap, first, &value));
    assert(myl_rc_list_append(&context.heap, second, &leaf));
    assert(myl_rc_list_append(&context.heap, outer, &first));
    assert(myl_rc_list_append(&context.heap, outer, &first));
    assert(myl_rc_list_append(&context.heap, outer, &second));
    myl_rc_pin pin = {0};
    assert(myl_rc_pin_acquire(&context.heap, first, &pin) == MYL_RC_OK);
    ((myl_rc_object *)leaf - 1)->owners = MYL_RC_COUNT_MAX;
    assert(!myl_qbe_rc_unique_elements(&context, &pointer_list, outer));
    assert(!strcmp(context.trap, "R_REFERENCE_COUNT_LIMIT"));
    myl_native_list **rows = outer->storage;
    assert(rows[0] != first && rows[1] != first && rows[0] != rows[1] && rows[2] == second);
    assert(((myl_rc_object *)first - 1)->owners == 1 && ((myl_rc_object *)first - 1)->holds == 1);
    assert(((myl_native_object *)first - 1)->mark & MYL_NATIVE_OBJECT_PINNED);
    assert(*(uint64_t *)rows[0]->storage == 73 && *(uint64_t *)rows[1]->storage == 73);
    assert(((myl_rc_object *)leaf - 1)->owners == MYL_RC_COUNT_MAX);
    ((myl_rc_object *)leaf - 1)->owners = 2;
    context.trap = NULL;
    assert(myl_qbe_rc_unique_elements(&context, &pointer_list, outer) && rows[2] != second);
    assert(((myl_rc_object *)leaf - 1)->owners == 3);
    myl_rc_pin_release(&context.heap, &pin);
    myl_rc_owner_release(&context.heap, outer);
    myl_rc_owner_release(&context.heap, first);
    myl_rc_owner_release(&context.heap, second);
    myl_rc_owner_release(&context.heap, leaf);
    assert(!context.heap.objects_live);
    myl_native_heap_destroy(&context.heap);
    assert(!context.heap.bytes);
}
// spec-case: RC-FRAME-1
static void unique_elements_arena_test(void) {
    MylQbeContext context = {0};
    myl_native_heap_init(&context.heap, 1u << 20);
    if (!myl_rc_enabled(&context.heap)) assert(myl_rc_storage_init(&context.heap) == MYL_RC_OK);
    static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
    myl_native_list *source = myl_native_list_new(&context.heap, &number, 1);
    uint64_t value = 91;
    assert(source && myl_rc_list_append(&context.heap, source, &value));
    assert(myl_native_region_begin(&context.heap));
    myl_native_list *outer = myl_native_list_new(&context.heap, &pointer_type, 3);
    void *empty = NULL;
    assert(outer && myl_rc_list_append(&context.heap, outer, &source));
    assert(myl_rc_list_append(&context.heap, outer, &source));
    assert(myl_rc_list_append(&context.heap, outer, &empty));
    assert(myl_native_region_begin(&context.heap));
    assert(myl_qbe_rc_unique_elements(&context, &pointer_list, outer));
    myl_native_list **rows = outer->storage;
    assert(rows[0] != source && rows[1] != source && rows[0] != rows[1] && !rows[2]);
    assert(myl_native_header_region(rows[0]) == 1 && myl_native_header_region(rows[1]) == 1);
    assert(((myl_rc_object *)source - 1)->owners == 1);
    myl_rc_arena_close(&context.heap, 2);
    assert(*(uint64_t *)rows[0]->storage == 91 && *(uint64_t *)rows[1]->storage == 91);
    myl_rc_arena_close(&context.heap, 1);
    myl_rc_owner_release(&context.heap, source);
    assert(!context.heap.objects_live);
    myl_native_heap_destroy(&context.heap);
    assert(!context.heap.bytes);
}
static void unique_body_test(void) {
    MylQbeContext context = {0};
    myl_native_heap_init(&context.heap, 1u << 20);
    if (!myl_rc_enabled(&context.heap)) assert(myl_rc_storage_init(&context.heap) == MYL_RC_OK);
    typedef struct { void *resource, *child; } Body;
    const myl_native_field fields[] = {{.offset = 0, .type = &resource_type}, {.offset = sizeof(void *), .type = &pointer_type}};
    const myl_native_type body_type = {.size = sizeof(Body), .alignment = _Alignof(Body), .kind = MYL_NATIVE_RECORD,
        .fields = fields, .field_count = 2};
    const myl_rc_field child_field = {.offset = offsetof(Body, child), .shape = &pointer};
    const myl_rc_shape body_shape = {.size = sizeof(Body), .kind = MYL_RC_SHAPE_RECORD, .as.record = {&child_field, 1}};
    const myl_rc_descriptor descriptor = {.type = &body_type, .shape = &body_shape, .finalize = myl_rc_finalize_unique};
    assert(myl_rc_descriptor_import(&context.heap, &descriptor) == MYL_RC_OK);
    void *child = myl_rc_storage_bytes(&context.heap, 8, 0), *payload = NULL;
    assert(child && myl_rc_owner_acquire(&context.heap, child) == MYL_RC_OK);
    uint32_t guard = 0;
    FrameResource resource = {.base = {.drop = close_resource}, .context = &context,
        .guard = &guard, .object = (myl_rc_object *)child - 1};
    myl_rc_alloc_request request = {.element = &body_type, .count = 1};
    assert(myl_rc_new(&context.heap, &request, &payload) == MYL_RC_OK);
    *(Body *)payload = (Body){&resource, child};
    myl_rc_owner_release(&context.heap, payload);
    assert(resource.closed == 1 && ((myl_rc_object *)child - 1)->owners == 1);
    myl_rc_owner_release(&context.heap, child);
    myl_native_heap_destroy(&context.heap);
    assert(!context.heap.bytes);
}
static void partial_unique_body_test(void) {
    MylQbeContext context = {0};
    myl_native_heap_init(&context.heap, 2u << 20);
    if (!myl_rc_enabled(&context.heap)) assert(myl_rc_storage_init(&context.heap) == MYL_RC_OK);
    typedef struct { void *resource, *child; } Pair;
    const myl_native_field fields[] = {{.type = &resource_type}, {.offset = sizeof(void *), .type = &pointer_type}};
    const myl_native_type pair = {.size = sizeof(Pair), .kind = MYL_NATIVE_RECORD, .fields = fields, .field_count = 2};
    const myl_native_field element = {.type = &pair};
    const myl_native_type body = {.size = 2 * sizeof(Pair), .kind = MYL_NATIVE_ARRAY, .fields = &element, .count = 2, .stride = sizeof(Pair)};
    const myl_rc_shape raw = {.size = sizeof(void *), .kind = MYL_RC_SHAPE_NONE};
    const myl_rc_field edges[] = {{.shape = &raw}, {.offset = sizeof(void *), .shape = &pointer}};
    const myl_rc_shape pair_shape = {.size = sizeof(Pair), .kind = MYL_RC_SHAPE_RECORD, .as.record = {edges, 2}};
    const myl_rc_shape body_shape = {.size = 2 * sizeof(Pair), .kind = MYL_RC_SHAPE_ARRAY,
        .as.array = {.element = &pair_shape, .count = 2, .stride = sizeof(Pair)}};
    const myl_rc_descriptor descriptors[] = {{.type = &body, .shape = &body_shape, .finalize = myl_rc_finalize_unique}, {.type = &pair, .shape = &pair_shape}};
    const myl_rc_module module = {.abi = MYL_RC_ABI_VERSION, .descriptors = descriptors, .descriptor_count = 2};
    assert(myl_rc_module_register(&context.heap, &module) == MYL_RC_OK);
    assert(myl_rc_descriptor_import(&context.heap, &pointer_descriptor) == MYL_RC_OK);
    void *child = myl_rc_storage_bytes(&context.heap, 8, 0), *overflow = NULL;
    myl_rc_alloc_request node_request = {.element = &pointer_type, .count = 1};
    assert(myl_rc_new(&context.heap, &node_request, &overflow) == MYL_RC_OK);
    void *limit_child = myl_rc_storage_bytes(&context.heap, 8, 0);
    assert(limit_child);
    memcpy(overflow, &limit_child, sizeof limit_child);
    assert(child && overflow && myl_rc_owner_acquire(&context.heap, child) == MYL_RC_OK);
    uint32_t guard = 0;
    FrameResource committed = {.base = {.drop = close_resource}, .context = &context,
        .guard = &guard, .object = (myl_rc_object *)child - 1};
    FrameResource incoming = committed;
    assert(myl_native_region_begin(&context.heap));
    Pair *payload = NULL;
    myl_rc_alloc_request request = {.element = &body, .count = 1, .region = 1};
    assert(myl_rc_new(&context.heap, &request, (void **)&payload) == MYL_RC_OK);
    payload[0] = (Pair){&committed, child};
    Pair source = {&incoming, overflow};
    ((myl_rc_object *)limit_child - 1)->owners = MYL_RC_COUNT_MAX;
    myl_rc_pin pin = {0};
    /* TAKE preserves an ordinary unpinned token; pinning forces its fallible
     * detached copy, whose incoming raw resource must remain source-owned. */
    assert(myl_rc_pin_acquire(&context.heap, overflow, &pin) == MYL_RC_OK);
    assert(!myl_rc_native_take(&context.heap, &pair, &payload[1], &source, 1));
    assert(source.resource == &incoming && source.child == overflow);
    assert(!payload[1].resource && !payload[1].child && !incoming.closed);
    assert(myl_rc_take_failure(&context.heap) == MYL_RC_COUNT_LIMIT);
    ((myl_rc_object *)limit_child - 1)->owners = 1;
    myl_rc_pin_release(&context.heap, &pin);
    myl_native_owned_drop(&context.heap, &pair, &source);
    assert(incoming.closed == 1 && !source.resource);
    myl_rc_construction_abort(&context.heap, payload);
    assert(committed.closed == 1 && ((myl_rc_object *)child - 1)->owners == 1);
    myl_rc_arena_close(&context.heap, 1);
    assert(committed.closed == 1 && incoming.closed == 1);
    myl_rc_owner_release(&context.heap, child);
    myl_rc_owner_release(&context.heap, overflow);
    myl_native_heap_destroy(&context.heap);
    assert(!context.heap.bytes);
}
static void arena_frame_boundary_test(void) {
    MylQbeContext context = {0};
    myl_native_heap_init(&context.heap, 1u << 20);
    if (!myl_rc_enabled(&context.heap)) assert(myl_rc_storage_init(&context.heap) == MYL_RC_OK);
    assert(myl_rc_descriptor_import(&context.heap, &pointer_descriptor) == MYL_RC_OK);
    void *values[3] = {myl_rc_storage_bytes(&context.heap, 8, 0), NULL, NULL};
    assert(values[0] && myl_rc_owner_acquire(&context.heap, values[0]) == MYL_RC_OK);
    values[1] = values[0];
    uint32_t guards[3] = {1, 1, 1};
    MylQbeRcSlot entries[3];
    for (size_t i = 0; i < 3; ++i) entries[i] = (MylQbeRcSlot){&pointer_type, &values[i], &guards[i], MYL_QBE_RC_COUNTED};
    MylQbeRcFrame frame;
    myl_qbe_rc_frame_enter(&context, &frame, entries, 3);
    myl_rc_scope outer, inner;
    myl_rc_scope_begin(&context.heap, &outer);
    assert(myl_rc_scope_pin(&outer, values[0]) == MYL_RC_OK);
    assert(myl_native_region_begin(&context.heap));
    values[2] = myl_rc_storage_bytes(&context.heap, 8, 1);
    assert(values[2]);
    myl_rc_scope_begin(&context.heap, &inner);
    assert(myl_rc_scope_pin(&inner, values[0]) == MYL_RC_OK);
    myl_qbe_rc_arena_prepare(&context, &frame, 1);
    assert(guards[0] && !guards[1] && !guards[2] && !values[1] && !values[2]);
    assert(outer.active && !inner.active && ((myl_rc_object *)values[0] - 1)->owners == 1);
    assert(((myl_rc_object *)values[0] - 1)->holds == 1);
    assert(((myl_native_object *)values[0] - 1)->mark & MYL_NATIVE_OBJECT_PINNED);
    myl_qbe_rc_arena_prepare(&context, &frame, 1);
    myl_rc_arena_close(&context.heap, 1);
    myl_qbe_rc_frame_cleanup(&context, &frame);
    myl_qbe_rc_frame_leave(&context, &frame);
    assert(!context.heap.objects_live && !outer.active);
    myl_native_heap_destroy(&context.heap);
    assert(!context.heap.bytes);
}
static void rebox_bridge_test(void) {
    MylQbeContext context = {0};
    myl_native_heap_init(&context.heap, 1u << 20);
    if (!myl_rc_enabled(&context.heap)) assert(myl_rc_storage_init(&context.heap) == MYL_RC_OK);
    static const myl_rc_field fields[] = {{.shape = &pointer}, {.offset = sizeof(void *), .shape = &pointer}};
    static const myl_rc_shape shape = {.size = 2 * sizeof(void *), .kind = MYL_RC_SHAPE_RECORD, .as.record = {fields, 2}};
    static const myl_native_type body_type = {.size = 2 * sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_RECORD};
    static const myl_native_type box_type = {.size = sizeof(void *), .kind = MYL_NATIVE_POINTER, .collection_kind = 5, .element = &body_type};
    const myl_rc_descriptor descriptor = {.type = &body_type, .shape = &shape};
    assert(myl_rc_descriptor_import(&context.heap, &descriptor) == MYL_RC_OK);
    myl_rc_alloc_request request = {.element = &body_type, .count = 1};
    void *old = NULL, *owner;
    assert(myl_rc_new(&context.heap, &request, &old) == MYL_RC_OK);
    void *body[2] = {myl_rc_storage_bytes(&context.heap, 8, 0), NULL};
    assert(body[0]);
    owner = old;
    uint32_t owned = 0;
    assert(myl_qbe_rc_rebox_local(&context, &box_type, &owner, body, &owned));
    assert(owned && owner != old && ((myl_rc_object *)old - 1)->owners == 1);
    assert(((myl_rc_object *)body[0] - 1)->owners == 2);
    assert(myl_qbe_rc_rebox_local(&context, &box_type, &owner, body, &owned));
    assert(((myl_rc_object *)body[0] - 1)->owners == 2);
    myl_rc_owner_release(&context.heap, owner);
    myl_rc_owner_release(&context.heap, old);
    body[1] = myl_rc_storage_bytes(&context.heap, 8, 0);
    assert(body[1]);
    ((myl_rc_object *)body[1] - 1)->owners = MYL_RC_COUNT_MAX;
    assert(myl_native_region_begin(&context.heap));
    request.region = context.heap.region_depth;
    assert(myl_rc_new(&context.heap, &request, &old) == MYL_RC_OK);
    owner = old;
    owned = 0;
    assert(!myl_qbe_rc_rebox_local(&context, &box_type, &owner, body, &owned));
    assert(owner == old && !owned && !strcmp(context.trap, "R_REFERENCE_COUNT_LIMIT"));
    assert(((myl_rc_object *)body[0] - 1)->owners == 1);
    ((myl_rc_object *)body[1] - 1)->owners = 1;
    myl_rc_arena_close(&context.heap, 1);
    myl_rc_owner_release(&context.heap, body[0]);
    myl_rc_owner_release(&context.heap, body[1]);
    assert(!context.heap.objects_live);
    myl_native_heap_destroy(&context.heap);
    assert(!context.heap.bytes);
}
static void scope_bridge_test(void) {
    MylQbeContext context = {0};
    myl_native_heap_init(&context.heap, 1u << 20);
    if (!myl_rc_enabled(&context.heap)) assert(myl_rc_storage_init(&context.heap) == MYL_RC_OK);
    static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
    myl_native_list *items[2] = {myl_native_list_new(&context.heap, &number, 0), myl_native_list_new(&context.heap, &number, 0)};
    assert(items[0] && items[1]);
    const myl_native_field field = {.type = &pointer_type};
    const myl_native_type array = {.size = sizeof items, .alignment = _Alignof(void *), .kind = MYL_NATIVE_ARRAY,
        .fields = &field, .field_count = 1, .count = 2, .stride = sizeof(void *)};
    const myl_rc_shape shape = {.size = sizeof items, .kind = MYL_RC_SHAPE_ARRAY,
        .as.array = {.element = &pointer, .count = 2, .stride = sizeof(void *)}};
    const myl_rc_descriptor descriptor = {.type = &array, .shape = &shape};
    assert(myl_rc_descriptor_import(&context.heap, &descriptor) == MYL_RC_OK);
    const MylQbeRcPath path = {&array, 0};
    MylQbeRcPlace place = {.address = items, .path = &path, .count = 1};
    myl_rc_scope scope = {0};
    myl_qbe_rc_scope_end(&context, &scope);
    myl_qbe_rc_scope_begin(&context, &scope);
    assert(myl_qbe_rc_scope_prepare(&context, &scope, &place));
    for (size_t i = 0; i < 2; ++i) assert(((myl_rc_object *)items[i] - 1)->holds == 1);
    myl_qbe_rc_scope_end(&context, &scope);
    myl_qbe_rc_scope_begin(&context, &scope);
    place = (MylQbeRcPlace){.address = &items[0]};
    assert(myl_qbe_rc_scope_prepare(&context, &scope, &place));
    assert(myl_qbe_rc_scope_hold(&context, &scope, items[1]));
    assert(myl_qbe_rc_scope_pin(&context, &scope, items[1]));
    for (size_t i = 0; i < 2; ++i) myl_rc_owner_release(&context.heap, items[i]);
    myl_qbe_rc_scope_end(&context, &scope);
    assert(!context.heap.objects_live);
    myl_native_heap_destroy(&context.heap);
    assert(!context.heap.bytes);
}
static void backing_bridge_test(void) {
    MylQbeContext context = {0};
    myl_native_heap_init(&context.heap, 4u << 20);
    if (!myl_rc_enabled(&context.heap)) assert(myl_rc_storage_init(&context.heap) == MYL_RC_OK);
    static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
    myl_native_list *list = myl_native_list_new(&context.heap, &number, 1);
    uint64_t value = 17;
    assert(list && myl_native_list_append(&context.heap, list, &value));
    void *backing = list->storage;
    myl_rc_scope scope;
    myl_qbe_rc_scope_begin(&context, &scope);
    ((myl_rc_object *)backing - 1)->holds = MYL_RC_COUNT_MAX;
    size_t charged = context.heap.bytes;
    assert(!myl_qbe_rc_scope_pin(&context, &scope, list));
    assert(!scope.journal && context.heap.bytes == charged && !((myl_rc_object *)list - 1)->holds);
    assert(!(((myl_native_object *)list - 1)->mark & MYL_NATIVE_OBJECT_PINNED));
    context.trap = NULL;
    ((myl_rc_object *)backing - 1)->holds = 0;
    assert(myl_qbe_rc_scope_pin(&context, &scope, list));
    assert(myl_native_list_append(&context.heap, list, &value));
    assert(list->storage != backing && !((myl_rc_object *)backing - 1)->owners && *(uint64_t *)backing == value);
    myl_qbe_rc_scope_end(&context, &scope);
    myl_rc_owner_release(&context.heap, list);
    myl_native_dictionary *dict = myl_native_dictionary_new(&context.heap, &number, &number, 0);
    assert(dict);
    for (uint64_t i = 0; i < 16; ++i) assert(myl_native_dictionary_write(&context.heap, dict, &i, &value));
    void *entries = dict->entries->storage, *index = dict->index.slots;
    myl_qbe_rc_scope_begin(&context, &scope);
    assert(myl_qbe_rc_scope_pin(&context, &scope, dict));
    for (uint64_t i = 16; i < 256; ++i) assert(myl_native_dictionary_write(&context.heap, dict, &i, &value));
    assert(entries != dict->entries->storage && index != dict->index.slots);
    assert(((myl_rc_object *)entries - 1)->holds == 1 && ((myl_rc_object *)index - 1)->holds == 1);
    myl_qbe_rc_scope_end(&context, &scope);
    myl_rc_owner_release(&context.heap, dict);
    myl_native_heap_destroy(&context.heap);
    assert(!context.heap.bytes);
}
// spec: RC-HOLD-VIEW-1
static void held_slot_test(void) {
    MylQbeContext context = {0};
    myl_native_heap_init(&context.heap, 1024 * 1024);
    if (!myl_rc_enabled(&context.heap)) assert(myl_rc_storage_init(&context.heap) == MYL_RC_OK);
    void *payload = myl_rc_storage_bytes(&context.heap, 8, 0);
    assert(payload);
    myl_rc_hold hold = {0};
    assert(myl_rc_hold_acquire(&context.heap, payload, &hold) == MYL_RC_OK);
    myl_rc_owner_release(&context.heap, payload);
    uint32_t initialized = 1;
    MylQbeRcSlot slot = {&pointer_type, &payload, &initialized, MYL_QBE_RC_HOLD_POINTER};
    MylQbeRcFrame frame;
    myl_qbe_rc_frame_enter(&context, &frame, &slot, 1);
    myl_qbe_rc_unwind(&context);
    assert(!payload && !initialized && !context.rc_frames && !context.heap.objects_live);
    myl_qbe_rc_slot_drop(&context, &slot);
    myl_native_heap_destroy(&context.heap);
    assert(!context.heap.bytes);
}
static void held_unique_bridge_test(void) {
    MylQbeContext context = {0};
    myl_native_heap_init(&context.heap, 1u << 20);
    if (!myl_rc_enabled(&context.heap)) assert(myl_rc_storage_init(&context.heap) == MYL_RC_OK);
    void *source = myl_rc_storage_bytes(&context.heap, 8, 0), *view = source;
    assert(source && myl_rc_owner_acquire(&context.heap, source) == MYL_RC_OK);
    myl_rc_hold hold = {0};
    assert(myl_rc_hold_acquire(&context.heap, source, &hold) == MYL_RC_OK);
    context.heap.limit = context.heap.bytes;
    assert(!myl_qbe_rc_unique_held(&context, &pointer_type, &view, NULL));
    assert(!strcmp(context.trap, "R_MEMORY_BUDGET") && view == source);
    assert(((myl_rc_object *)source - 1)->owners == 2 && ((myl_rc_object *)source - 1)->holds == 1);
    context.trap = NULL;
    context.heap.exhausted = 0;
    context.heap.limit = 1u << 20;
    assert(myl_qbe_rc_unique_held(&context, &pointer_type, &view, NULL) && view != source);
    assert(((myl_rc_object *)view - 1)->owners == 0 && ((myl_rc_object *)view - 1)->holds == 1);
    uint32_t initialized = 1;
    MylQbeRcSlot slot = {&pointer_type, &view, &initialized, MYL_QBE_RC_HOLD_POINTER};
    myl_qbe_rc_slot_drop(&context, &slot);
    myl_rc_owner_release(&context.heap, source);
    myl_rc_owner_release(&context.heap, source);
    assert(!view && !initialized && !context.heap.objects_live);
    myl_native_heap_destroy(&context.heap);
    assert(!context.heap.bytes);
}
int myl_qbe_rc_contract_verify(void) {
    MylQbeContext context = {0};
    context.heap.limit = 65536;
    assert(myl_rc_heap_init(&context.heap, &allocator, NULL) == MYL_RC_OK);
    assert(!myl_rc_shape_resolve(&context.heap, &pointer));
    myl_rc_module stale = myl_rc_generated_module;
    stale.abi = MYL_RC_ABI_VERSION - 1;
    size_t before = context.heap.bytes;
    assert(!myl_qbe_rc_register(&context, &stale));
    assert(!strcmp(context.trap, "R_INTERNAL") && context.heap.bytes == before);
    assert(!myl_rc_shape_resolve(&context.heap, &pointer));
    context.trap = NULL;
    assert(myl_qbe_rc_initialize(&context));
    assert(!context.trap && myl_rc_shape_resolve(&context.heap, &pointer));
    size_t bytes = context.heap.bytes;
    assert(myl_qbe_rc_register(&context, &myl_rc_generated_module));
    assert(context.heap.bytes == bytes);
    assert(!myl_qbe_rc_status(&context, MYL_RC_COUNT_LIMIT));
    assert(!strcmp(context.trap, "R_REFERENCE_COUNT_LIMIT"));
    assert(!myl_qbe_rc_status(&context, MYL_RC_REGION_ERROR));
    assert(!strcmp(context.trap, "R_REFERENCE_COUNT_LIMIT"));
    context.trap = NULL;
    assert(!myl_qbe_rc_status(&context, MYL_RC_REGION_ERROR));
    assert(!strcmp(context.trap, "R_ARENA_ESCAPE"));
    context.trap = NULL;
    context.heap.exhausted = 0;
    assert(!myl_qbe_rc_status(&context, MYL_RC_ALLOCATION_REFUSED));
    assert(!strcmp(context.trap, "OutOfMemory"));
    context.trap = NULL;
    context.heap.exhausted = 1;
    assert(!myl_qbe_rc_status(&context, MYL_RC_ALLOCATION_REFUSED));
    assert(!strcmp(context.trap, "R_MEMORY_BUDGET"));
    myl_rc_heap_destroy(&context.heap);
    assert(context.heap.bytes == 0);
    context = (MylQbeContext){0};
    context.heap.limit = 1;
    assert(myl_rc_heap_init(&context.heap, &allocator, NULL) == MYL_RC_ALLOCATION_REFUSED);
    assert(!myl_qbe_rc_initialize(&context));
    assert(!strcmp(context.trap, "R_MEMORY_BUDGET") && !context.heap.rc);
    return 5;
}
int myl_qbe_rc_frame_verify(void) {
    frame_cleanup_test(0);
    frame_cleanup_test(1);
    frame_trap_test();
    construction_guard_test();
    unique_bridge_test();
    unique_elements_refusal_test();
    unique_elements_arena_test();
    unique_body_test();
    rebox_bridge_test();
    partial_unique_body_test();
    arena_frame_boundary_test();
    scope_bridge_test();
    backing_bridge_test();
    held_slot_test();
    held_unique_bridge_test();
    return 15;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) {
    assert(myl_qbe_rc_contract_verify() == 5);
    assert(myl_qbe_rc_frame_verify() == 15);
    puts("RC startup and frame unwind: 20 checks passed");
    return 0;
}
#endif
