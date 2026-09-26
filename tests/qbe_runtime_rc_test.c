#include "qbe_runtime.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static const myl_rc_shape pointer = {.size = sizeof(void *), .kind = MYL_RC_SHAPE_POINTER};
static const myl_rc_shape *const shapes[] = {&pointer};
const myl_rc_module myl_rc_generated_module = {.abi = MYL_RC_ABI_VERSION, .shapes = shapes, .shape_count = 1};
/* Capture the same status delivered to the located native trap entry. These
 * tests exercise initialization before an active guest frame exists. */
void myl_qbe_fail(void *context, const char *code) { ((MylQbeContext *)context)->trap = code; }
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
    assert(!strcmp(context.trap, "R_ARENA_ESCAPE"));
    context.heap.exhausted = 0;
    assert(!myl_qbe_rc_status(&context, MYL_RC_ALLOCATION_REFUSED));
    assert(!strcmp(context.trap, "OutOfMemory"));
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
    return 4;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) {
    assert(myl_qbe_rc_contract_verify() == 4);
    puts("RC startup: 4 checks passed");
    return 0;
}
#endif
