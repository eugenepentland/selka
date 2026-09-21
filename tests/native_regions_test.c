#include "native_regions.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
/* A managed list of integers, described the way the generated descriptors do. */
static const myl_native_type integers={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=1,.element=&number};
static const myl_native_type nested={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=1,.element=&integers};
typedef struct Node { struct Node *next; int64_t value; } Node;
static const myl_native_field node_fields[]={{.offset=offsetof(Node,next),.type=&pointer}};
static const myl_native_type node={.size=sizeof(Node),.alignment=_Alignof(Node),.kind=MYL_NATIVE_RECORD,.fields=node_fields,.field_count=1};
static myl_native_list *make(myl_native_heap *heap, const myl_native_type *element, size_t capacity) {
    return myl_native_list_new(heap, element, capacity);
}
static void append_number(myl_native_heap *heap, myl_native_list *list, int64_t value) {
    assert(myl_native_list_append(heap, list, &value));
}
/* A tracing-heap object reachable only through a live arena allocation remains
   live. This uses public ownership/root operations and never assumes an object
   header immediately precedes arena storage. */
static void arena_to_gc_reference(void) {
    myl_native_heap heap;
    myl_native_root root;
    myl_native_heap_init(&heap,1<<20);
    Node *target=myl_native_heap_alloc(&heap,&node,1);
    assert(target);
    target->value=73;
    assert(myl_native_heap_alloc(&heap,&node,1)); /* unreachable older garbage */
    myl_native_region_begin(&heap);
    Node *owner=myl_native_heap_alloc(&heap,&node,1);
    assert(owner && myl_native_object_region(&heap,owner)==1);
    owner->next=target;
    target=NULL;
    myl_native_root_push(&heap,&root,&owner,&pointer);
    heap.stress=1;
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==2 && owner->next && owner->next->value==73);
    Node *retained=owner;
    owner=NULL; /* arena contents remain roots even after the local is cleared */
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==2 && retained->next && retained->next->value==73);
    assert(myl_native_root_pop(&heap,&root));
    owner=NULL;
    myl_native_region_end(&heap);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==0);
    myl_native_heap_destroy(&heap);
}
/* The entries allocation uses a descriptor embedded in its arena dictionary.
   Both remain live to the same scope end, so arena scanning may safely use the
   dynamic descriptor to retain an older tracing-heap value. */
static void dynamic_descriptor_reference(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    Node *target=myl_native_heap_alloc(&heap,&node,1);
    assert(target); target->value=84;
    myl_native_region_begin(&heap);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&pointer,0);
    int64_t key=7;
    assert(dict && myl_native_dictionary_write(&heap,dict,&key,&target));
    target=NULL;
    heap.stress=1;
    myl_native_heap_collect(&heap);
    Node *found=NULL;
    assert(myl_native_dictionary_read(dict,&key,&found) && found && found->value==84);
    dict=NULL;
    myl_native_heap_collect(&heap);
    myl_native_region_end(&heap);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==0);
    myl_native_heap_destroy(&heap);
}
/* Escape preserves cycles as well as duplicate sharing: the promoted edge must
   point to the promoted container, never back into the dying arena. */
static void cyclic_escape(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    myl_native_region_begin(&heap);
    myl_native_list *cycle=make(&heap,&integers,1);
    assert(cycle && myl_native_list_append(&heap,cycle,&cycle));
    myl_native_list *promoted=NULL;
    assert(myl_native_region_escape(&heap,&nested,&cycle,&promoted));
    myl_native_list *edge=NULL;
    assert(promoted && promoted!=cycle && myl_native_list_get(promoted,0,&edge));
    assert(edge==promoted && myl_native_object_region(&heap,promoted)==0);
    cycle=NULL;
    myl_native_region_end(&heap);
    myl_native_root root;
    myl_native_root_push(&heap,&root,&promoted,&pointer);
    myl_native_heap_collect(&heap);
    assert(myl_native_list_get(promoted,0,&edge) && edge==promoted);
    assert(myl_native_root_pop(&heap,&root));
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==0);
    myl_native_heap_destroy(&heap);
}
static void failed_escape_clears_output(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    myl_native_region_begin(&heap);
    myl_native_list *source=make(&heap,&number,1);
    append_number(&heap,source,12);
    heap.limit=heap.bytes; /* no enclosing-region clone can be charged */
    myl_native_list *output=(myl_native_list *)(uintptr_t)1;
    assert(!myl_native_region_escape(&heap,&integers,&source,&output));
    assert(output==NULL && heap.exhausted);
    myl_native_region_end(&heap);
    assert(!heap.objects_live && !heap.bytes);
    myl_native_heap_destroy(&heap);
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
    assert(myl_native_object_region(&heap,scratch) == 1);
    assert(myl_native_object_region(&heap,keeper) == 0);
    assert(myl_native_object_region(&heap,keeper->storage) == 0);
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
    assert(myl_native_object_region(&heap,escaped) == 0 && myl_native_object_region(&heap,items[0]) == 0);
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
    assert(myl_native_object_region(&heap,second) == 2);
    myl_native_list *promoted = NULL;
    assert(myl_native_region_escape(&heap, &integers, &second, &promoted));
    assert(myl_native_object_region(&heap,promoted) == 1);
    second = NULL;
    myl_native_region_end(&heap);
    assert(heap.region_depth == 1);
    assert(myl_native_list_get(promoted, 0, &value) && value == 9);
    assert(myl_native_root_pop(&heap, &roots[0]));
    myl_native_region_end(&heap);
    assert(heap.region_depth == 0 && heap.objects_live == 0);
    myl_native_heap_destroy(&heap);
    arena_to_gc_reference();
    dynamic_descriptor_reference();
    cyclic_escape();
    failed_escape_clears_output();
    puts("native region tests passed");
    return 0;
}
