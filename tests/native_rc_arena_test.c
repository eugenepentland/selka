#include "native_rc_collections.h"
#include "native_rc_dictionary.h"
#include <assert.h>
#include <stdio.h>
static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
static const myl_native_type pointer = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER};
static void start(myl_native_heap *heap) {
    myl_native_heap_init(heap, 64u << 20);
    if (!myl_rc_enabled(heap)) assert(myl_rc_storage_init(heap) == MYL_RC_OK);
}
static uintptr_t owners(const void *payload) { return ((const myl_rc_object *)payload - 1)->owners; }
static void finish(myl_native_heap *heap) {
    assert(!heap->objects_live);
    myl_native_heap_destroy(heap);
    assert(!heap->bytes);
}
static void collection_edges(void) {
    myl_native_heap heap;
    start(&heap);
    myl_native_list *leaf = myl_native_list_new(&heap, &number, 0);
    assert(leaf && myl_native_region_begin(&heap));
    myl_native_list *list = myl_native_list_new(&heap, &pointer, 9000);
    myl_native_dictionary *dict = myl_native_dictionary_new(&heap, &number, &pointer, 0);
    assert(list && dict);
    for (uint64_t i = 0; i < 100; ++i) {
        assert(myl_native_list_append(&heap, list, &leaf));
        assert(myl_native_dictionary_write(&heap, dict, &i, &leaf));
    }
    for (uint64_t i = 0; i < 100; i += 2) {
        myl_native_list *out = NULL;
        assert(myl_rc_dictionary_pop(&heap, dict, &i, &out) == 1);
        myl_rc_owner_release(&heap, out);
    }
    assert(owners(leaf) == 151 && heap.arena.chunks_live >= 2);
    myl_rc_scope scope;
    myl_rc_scope_begin(&heap, &scope);
    assert(myl_rc_scope_pin(&scope, leaf) == MYL_RC_OK);
    myl_rc_owner_release(&heap, leaf);
    myl_rc_arena_close(&heap, 1);
    assert(!scope.active && !heap.region_depth && !heap.arena.chunks_live);
    finish(&heap);
}
static void nested_and_charged_reuse(void) {
    myl_native_heap heap;
    start(&heap);
    myl_native_list *leaf = myl_native_list_new(&heap, &number, 0);
    assert(leaf && myl_native_region_begin(&heap));
    myl_native_list *outer = myl_native_list_new(&heap, &pointer, 1);
    assert(outer && myl_native_list_append(&heap, outer, &leaf));
    assert(myl_native_region_begin(&heap));
    myl_native_list *inner = myl_native_list_new(&heap, &pointer, 1);
    assert(inner && myl_native_list_append(&heap, inner, &leaf));
    size_t charged = heap.bytes;
    myl_native_region_end(&heap);
    assert(owners(leaf) == 2 && heap.bytes == charged);
    myl_native_region_end(&heap);
    assert(owners(leaf) == 1 && heap.bytes == charged && heap.arena.cached_bytes);
    heap.limit = heap.bytes;
    size_t reused = heap.arena.reused;
    assert(myl_native_region_begin(&heap));
    assert(myl_rc_storage_bytes(&heap, 16, 1));
    assert(heap.bytes == charged && heap.arena.reused == reused + 1);
    myl_native_region_end(&heap);
    myl_rc_owner_release(&heap, leaf);
    finish(&heap);
}
static unsigned finalized;
static unsigned expected_region;
static void finalize(myl_native_heap *heap, void *payload) {
    void *child = *(void **)payload;
    assert(child && *(uint64_t *)child == 79 && heap->region_depth == expected_region);
    ++finalized;
    assert(myl_native_region_begin(heap));
    assert(myl_rc_storage_bytes(heap, 32, heap->region_depth));
    myl_native_region_end(heap);
}
static void finalizer_and_abort(void) {
    myl_native_heap heap;
    start(&heap);
    const myl_rc_shape *shape = myl_rc_native_shape(&heap, &pointer);
    myl_native_type body = pointer;
    myl_rc_descriptor descriptor = {.type = &body, .shape = shape, .finalize = finalize};
    assert(shape && myl_rc_descriptor_register(&heap, &descriptor) == MYL_RC_OK);
    void *child = myl_rc_storage_bytes(&heap, 8, 0);
    assert(child);
    *(uint64_t *)child = 79;
    finalized = 0;
    for (unsigned abort_first = 0; abort_first < 2; ++abort_first) {
        assert(myl_native_region_begin(&heap));
        myl_rc_alloc_request request = {.element = &body, .count = 1, .region = 1};
        void *parent = NULL;
        assert(myl_rc_new(&heap, &request, &parent) == MYL_RC_OK);
        assert(myl_rc_owner_acquire(&heap, child) == MYL_RC_OK);
        *(void **)parent = child;
        expected_region = abort_first;
        if (abort_first) {
            myl_rc_construction_abort(&heap, parent);
            myl_rc_construction_abort(&heap, parent);
        }
        myl_native_region_end(&heap);
        assert(owners(child) == 1 && finalized == abort_first + 1);
    }
    myl_rc_owner_release(&heap, child);
    finish(&heap);
}
static void depth_reservation_refusal(void) {
    myl_native_heap heap;
    start(&heap);
    heap.limit = heap.bytes;
    assert(myl_native_region_begin(&heap));
    size_t before = heap.bytes;
    assert(!myl_rc_storage_bytes(&heap, 1, 1));
    assert(heap.bytes == before && !heap.arena_depth_capacity && !heap.arena.chunks_live);
    myl_native_region_end(&heap);
    finish(&heap);
}
static void inspect_arena_child(myl_native_heap *heap, void *payload) {
    void *child = *(void **)payload;
    assert(child && *(void **)child);
    finalize(heap, child);
}
static void parent_finalizer_sees_arena_child(void) {
    myl_native_heap heap;
    start(&heap);
    const myl_rc_shape *shape = myl_rc_native_shape(&heap, &pointer);
    myl_native_type parent_type = pointer;
    myl_rc_descriptor parent_descriptor = {.type = &parent_type, .shape = shape, .finalize = inspect_arena_child};
    assert(shape && myl_rc_descriptor_register(&heap, &parent_descriptor) == MYL_RC_OK);
    void *leaf = myl_rc_storage_bytes(&heap, 8, 0);
    assert(leaf);
    *(uint64_t *)leaf = 79;
    assert(myl_native_region_begin(&heap));
    myl_rc_alloc_request request = {.element = &pointer, .count = 1, .region = 1};
    void *child = NULL, *parent = NULL;
    assert(myl_rc_new(&heap, &request, &child) == MYL_RC_OK);
    *(void **)child = leaf;
    request.element = &parent_type;
    assert(myl_rc_new(&heap, &request, &parent) == MYL_RC_OK);
    *(void **)parent = child;
    expected_region = 0;
    finalized = 0;
    myl_native_region_end(&heap);
    assert(finalized == 1);
    finish(&heap);
}
static void close_preserves_older_scope(void) {
    myl_native_heap heap;
    start(&heap);
    void *value = myl_rc_storage_bytes(&heap, 8, 0);
    assert(value);
    *(uint64_t *)value = 123;
    myl_rc_scope outer, inner;
    myl_rc_scope_begin(&heap, &outer);
    assert(myl_rc_scope_pin(&outer, value) == MYL_RC_OK);
    assert(myl_native_region_begin(&heap));
    myl_rc_scope_begin(&heap, &inner);
    assert(myl_rc_scope_pin(&inner, value) == MYL_RC_OK);
    myl_rc_owner_release(&heap, value);
    myl_native_region_end(&heap);
    assert(!inner.active && outer.active && !heap.region_depth);
    myl_rc_object *header = (myl_rc_object *)value - 1;
    assert(!header->owners && header->holds == 1);
    assert((header->common.mark & MYL_NATIVE_OBJECT_PINNED) && *(uint64_t *)value == 123);
    myl_rc_scope_end(&outer);
    finish(&heap);
}
int myl_native_rc_arena_verify(void) {
    collection_edges();
    nested_and_charged_reuse();
    finalizer_and_abort();
    depth_reservation_refusal();
    parent_finalizer_sees_arena_child();
    close_preserves_older_scope();
    return 6;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) {
    assert(myl_native_rc_arena_verify() == 6);
    puts("native RC arena: 6 passed");
    return 0;
}
#endif
