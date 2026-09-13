#include "native_collections.h"
#include <assert.h>
#include <stdio.h>
static const myl_native_type number = { .size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN };
static const myl_native_type pointer = { .size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER };
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 20);
    heap.stress = 1;
    myl_native_list *list = myl_native_list_new(&heap, &number, 0);
    assert(list);
    myl_native_root root;
    myl_native_root_push(&heap, &root, &list, &pointer);
    myl_native_list *identity = list;
    for (int64_t i = 0; i < 100; ++i) assert(myl_native_list_append(&heap, list, &i));
    assert(list == identity && list->length == 100);
    for (int64_t i = 0; i < 100; ++i) {
        int64_t value;
        assert(myl_native_list_get(list, (size_t)i, &value) && value == i);
    }
    int64_t value;
    assert(!myl_native_list_get(list, 100, &value));
    assert(myl_native_list_pop(list, &value) && value == 99);
    myl_native_list_clear(list);
    assert(list->length == 0);
    myl_native_list *refs = myl_native_list_new(&heap, &pointer, 0);
    assert(refs);
    myl_native_root refs_root;
    myl_native_root_push(&heap, &refs_root, &refs, &pointer);
    /* Self cycle and child list survive allocation safepoints. */
    assert(myl_native_list_append(&heap, refs, &refs));
    assert(myl_native_list_append(&heap, refs, &list));
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 4);
    myl_native_list *child;
    assert(myl_native_list_get(refs, 0, &child) && child == refs);
    assert(myl_native_list_get(refs, 1, &child) && child == list);
    myl_native_root_pop(&heap, &refs_root);
    myl_native_root_pop(&heap, &root);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 0 && heap.bytes == 0);
    myl_native_heap_destroy(&heap);
    /* Failed growth leaves list contents and root chain intact. */
    myl_native_heap_init(&heap, 256);
    list = myl_native_list_new(&heap, &number, 0);
    assert(list);
    myl_native_root_push(&heap, &root, &list, &pointer);
    int64_t sentinel = 31;
    size_t accepted = 0;
    while (myl_native_list_append(&heap, list, &sentinel)) accepted++;
    assert(list->length == accepted && heap.roots == &root);
    for (size_t i = 0; i < accepted; i++) {
        assert(myl_native_list_get(list, i, &value) && value == sentinel);
    }
    list->generation = UINT64_MAX;
    assert(!myl_native_list_append(&heap, list, &sentinel));
    assert(list->generation == UINT64_MAX);
    myl_native_heap_destroy(&heap);
    puts("native collections tests passed");
}
