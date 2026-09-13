#include "native_regions.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
/* A managed list of integers, described the way the generated descriptors do. */
static const myl_native_type integers={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=1,.element=&number};
static const myl_native_type nested={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=1,.element=&integers};
static myl_native_list *make(myl_native_heap *heap, const myl_native_type *element, size_t capacity) {
    return myl_native_list_new(heap, element, capacity);
}
static void append_number(myl_native_heap *heap, myl_native_list *list, int64_t value) {
    assert(myl_native_list_append(heap, list, &value));
}
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 22);
    myl_native_root roots[4];
    /* An older list grown from inside an arena keeps its backing past the scope. */
    myl_native_list *keeper = make(&heap, &number, 0);
    myl_native_root_push(&heap, &roots[0], &keeper, &pointer);
    myl_native_list *outer = make(&heap, &integers, 0);
    myl_native_root_push(&heap, &roots[1], &outer, &pointer);
    myl_native_region_begin(&heap);
    assert(heap.region_depth == 1 && heap.arena.scopes == 1);
    for (int64_t i = 0; i < 64; ++i) append_number(&heap, keeper, i);
    myl_native_list *scratch = make(&heap, &number, 4);
    append_number(&heap, scratch, 5);
    assert(myl_native_object_region(scratch) == 1);
    assert(myl_native_object_region(keeper) == 0);
    assert(myl_native_object_region(keeper->storage) == 0);
    /* The store barrier rejects a younger reference and accepts an older one. */
    assert(!myl_native_region_check(&heap, outer, &integers, &scratch));
    assert(myl_native_region_check(&heap, outer, &integers, &keeper));
    assert(myl_native_region_retains(&heap, &integers, &scratch));
    assert(!myl_native_region_retains(&heap, &integers, &keeper));
    /* Escape copies the arena's part of the graph and shares the older part. */
    myl_native_list *holder = make(&heap, &integers, 0);
    myl_native_root_push(&heap, &roots[2], &holder, &pointer);
    assert(myl_native_list_append(&heap, holder, &scratch));
    assert(myl_native_list_append(&heap, holder, &scratch));
    assert(myl_native_list_append(&heap, holder, &keeper));
    myl_native_list *escaped = NULL;
    assert(myl_native_region_escape(&heap, &nested, &holder, &escaped));
    myl_native_root_push(&heap, &roots[3], &escaped, &pointer);
    assert(escaped && escaped != holder && escaped->length == 3);
    myl_native_list **items = escaped->storage;
    assert(items[0] == items[1] && items[0] != scratch);
    assert(items[2] == keeper);
    assert(myl_native_object_region(escaped) == 0 && myl_native_object_region(items[0]) == 0);
    assert(heap.arena.escaped == 2);
    size_t before = heap.objects_live;
    /* Bindings introduced inside the block are cleared before the bulk free,
       exactly as the generated end_arena clears its own local slots. */
    holder = NULL;
    scratch = NULL;
    myl_native_region_end(&heap);
    assert(heap.region_depth == 0 && heap.arena.released > 0 && heap.objects_live < before);
    /* Survivors keep valid backing: the grown storage never joined the arena. */
    int64_t value = 0;
    assert(myl_native_list_get(keeper, 63, &value) && value == 63);
    myl_native_heap_collect(&heap);
    myl_native_list *survivor = NULL;
    assert(myl_native_list_get(escaped, 0, &survivor) && survivor != NULL);
    assert(myl_native_list_get(survivor, 0, &value) && value == 5);
    for (int i = 3; i >= 0; --i) assert(myl_native_root_pop(&heap, &roots[i]));
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 0);
    myl_native_heap_destroy(&heap);
    /* Nested arenas release innermost first and an escape crosses one level. */
    myl_native_heap_init(&heap, 1 << 22);
    myl_native_region_begin(&heap);
    myl_native_list *first = make(&heap, &number, 1);
    myl_native_root_push(&heap, &roots[0], &first, &pointer);
    myl_native_region_begin(&heap);
    myl_native_list *second = make(&heap, &number, 1);
    append_number(&heap, second, 9);
    assert(myl_native_object_region(second) == 2);
    myl_native_list *promoted = NULL;
    assert(myl_native_region_escape(&heap, &integers, &second, &promoted));
    assert(myl_native_object_region(promoted) == 1);
    second = NULL;
    myl_native_region_end(&heap);
    assert(heap.region_depth == 1);
    assert(myl_native_list_get(promoted, 0, &value) && value == 9);
    assert(myl_native_root_pop(&heap, &roots[0]));
    myl_native_region_end(&heap);
    assert(heap.region_depth == 0 && heap.objects_live == 0);
    myl_native_heap_destroy(&heap);
    puts("native region tests passed");
    return 0;
}
