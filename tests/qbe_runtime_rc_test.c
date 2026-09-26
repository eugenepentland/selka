#include "qbe_runtime.h"
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
int myl_qbe_rc_contract_verify(void) {
    MylQbeContext context = {0};
    context.heap.limit = 65536;
    assert(myl_rc_heap_init(&context.heap, &allocator, NULL) == MYL_RC_OK);
    assert(!myl_rc_shape_resolve(&context.heap, &pointer));
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
    frame_cleanup_test(0);
    frame_cleanup_test(1);
    frame_trap_test();
    return 8;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) {
    assert(myl_qbe_rc_contract_verify() == 8);
    puts("RC startup and frame unwind: 8 checks passed");
    return 0;
}
#endif
