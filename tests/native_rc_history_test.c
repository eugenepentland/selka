#include "native_rc_dictionary.h"
#include "native_regions.h"
#include <assert.h>
#include <stdio.h>

static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type pointer={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER};
static const myl_rc_shape owned={.size=8,.kind=MYL_RC_SHAPE_POINTER};
static const myl_native_field pair_fields[]={{.type=&pointer},{.offset=8,.type=&pointer}};
static const myl_native_type pair={.size=16,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=pair_fields,.field_count=2};
static const myl_rc_field pair_edges[]={{.shape=&owned},{.offset=8,.shape=&owned}};
static const myl_rc_shape pair_shape={.size=16,.kind=MYL_RC_SHAPE_RECORD,.as.record={pair_edges,2}};
static const myl_rc_descriptor descriptors[]={{.type=&pointer,.shape=&owned},{.type=&pair,.shape=&pair_shape}};
static const myl_rc_module module={.abi=MYL_RC_ABI_VERSION,.descriptors=descriptors,.descriptor_count=2};
static myl_rc_object *header(void *p) { return (myl_rc_object *)p-1; }
static void start(myl_native_heap *heap) {
    myl_native_heap_init(heap,64u<<20);
    if (!myl_rc_enabled(heap)) assert(myl_rc_storage_init(heap)==MYL_RC_OK);
    assert(myl_rc_module_register(heap,&module)==MYL_RC_OK);
}
static void finish(myl_native_heap *heap) {
    assert(!heap->objects_live); myl_native_heap_destroy(heap); assert(!heap->bytes);
}
static void write_value(myl_native_heap *heap,void *mapping,uint64_t value) {
    uint64_t key=1; assert(myl_native_dictionary_write(heap,mapping,&key,&value));
}
static void *mapping(myl_native_heap *heap) {
    void *value=myl_native_dictionary_new(heap,&number,&number,0);
    assert(value); write_value(heap,value,7); return value;
}
static uint64_t read_value(void *mapping) {
    uint64_t key=1,value=0; assert(myl_native_dictionary_read(mapping,&key,&value)); return value;
}
static void unique(myl_native_heap *heap,void **value) {
    myl_rc_slot slot={.shape=&owned,.address=value,.region=myl_native_header_region(*value)};
    assert(myl_rc_unique_owned(heap,&slot)==MYL_RC_OK);
}
static int shared(void *value) { return (header(value)->common.mark&MYL_NATIVE_OBJECT_SHARED)!=0; }
// spec: RC-SEMANTIC-HISTORY-1
static void both_mutation_orders(unsigned original_first) {
    myl_native_heap heap; start(&heap);
    void *original=mapping(&heap),*snapshot=NULL;
    myl_rc_hold view={0}; assert(myl_rc_hold_acquire(&heap,original,&view)==MYL_RC_OK);
    assert(myl_rc_native_publish(&heap,&pointer,&snapshot,&original,0,MYL_RC_HISTORY_DIRECT));
    assert(snapshot==original && shared(original));
    if (original_first) { unique(&heap,&original); write_value(&heap,original,13); }
    unique(&heap,&snapshot); write_value(&heap,snapshot,11);
    if (!original_first) { unique(&heap,&original); write_value(&heap,original,13); }
    assert(read_value(view.payload)==7 && read_value(snapshot)==11 && read_value(original)==13);
    assert(!shared(snapshot) && !shared(original));
    myl_rc_owner_release(&heap,original); myl_rc_owner_release(&heap,snapshot);
    myl_rc_hold_release(&heap,&view); finish(&heap);
}
static void loan_then_pinned_publication(void) {
    myl_native_heap heap; start(&heap);
    void *original=mapping(&heap),*loan=NULL,*snapshot=NULL;
    myl_rc_hold view={0}; assert(myl_rc_hold_acquire(&heap,original,&view)==MYL_RC_OK);
    assert(myl_rc_native_loan(&heap,&pointer,&loan,&original));
    myl_rc_pin pin={0}; assert(myl_rc_pin_acquire(&heap,original,&pin)==MYL_RC_OK);
    assert(myl_rc_native_publish(&heap,&pointer,&snapshot,&loan,0,MYL_RC_HISTORY_DIRECT));
    assert(snapshot!=original && !shared(original) && !shared(snapshot));
    myl_rc_native_unloan(&heap,&pointer,&loan); myl_rc_pin_release(&heap,&pin);
    unique(&heap,&snapshot); write_value(&heap,snapshot,11);
    unique(&heap,&original); write_value(&heap,original,13);
    assert(read_value(view.payload)==13 && read_value(snapshot)==11 && read_value(original)==13);
    myl_rc_owner_release(&heap,original); myl_rc_owner_release(&heap,snapshot);
    myl_rc_hold_release(&heap,&view); finish(&heap);
}
static void publication_then_pin(void) {
    myl_native_heap heap; start(&heap);
    void *original=mapping(&heap),*snapshot=NULL;
    myl_rc_hold view={0}; assert(myl_rc_hold_acquire(&heap,original,&view)==MYL_RC_OK);
    assert(myl_rc_native_publish(&heap,&pointer,&snapshot,&original,0,MYL_RC_HISTORY_DIRECT));
    unique(&heap,&original);
    myl_rc_pin pin={0}; assert(myl_rc_pin_acquire(&heap,original,&pin)==MYL_RC_OK);
    write_value(&heap,original,13); myl_rc_pin_release(&heap,&pin);
    unique(&heap,&snapshot); write_value(&heap,snapshot,11);
    assert(read_value(view.payload)==7 && read_value(snapshot)==11 && read_value(original)==13);
    myl_rc_owner_release(&heap,original); myl_rc_owner_release(&heap,snapshot);
    myl_rc_hold_release(&heap,&view); finish(&heap);
}
static void late_count_refusal(void) {
    myl_native_heap heap; start(&heap);
    void *a=mapping(&heap),*b=mapping(&heap),*source[]={a,b},*out[2]={0};
    header(b)->owners=MYL_RC_COUNT_MAX;
    assert(!myl_rc_native_publish(&heap,&pair,out,source,0,MYL_RC_HISTORY_DIRECT));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    assert(!out[0] && !out[1] && !shared(a) && !shared(b));
    assert(header(a)->owners==1 && header(b)->owners==MYL_RC_COUNT_MAX);
    header(b)->owners=1;
    assert(myl_rc_native_publish(&heap,&pair,out,source,0,MYL_RC_HISTORY_DIRECT));
    assert(shared(a) && shared(b)); myl_rc_native_drop(&heap,&pair,out);
    myl_rc_owner_release(&heap,a); myl_rc_owner_release(&heap,b); finish(&heap);
}
static void semantic_clone_marks_reused_children(void) {
    myl_native_heap heap; start(&heap);
    void *child=mapping(&heap);
    myl_native_list *parent=myl_native_list_new(&heap,&pointer,1); assert(parent);
    assert(myl_native_list_append(&heap,parent,&child));
    myl_rc_owner_release(&heap,child);
    void *original=parent,*snapshot=NULL;
    assert(myl_rc_native_publish(&heap,&pointer,&snapshot,&original,0,MYL_RC_HISTORY_DIRECT));
    assert(!shared(child));
    unique(&heap,&snapshot);
    assert(snapshot!=original && !shared(snapshot) && shared(child));
    myl_rc_owner_release(&heap,snapshot); myl_rc_owner_release(&heap,original); finish(&heap);
}
static void pinned_snapshot_preserves_older_region(void) {
    myl_native_heap heap; start(&heap);
    void *original=mapping(&heap),*snapshot=NULL;
    myl_rc_pin pin={0}; assert(myl_rc_pin_acquire(&heap,original,&pin)==MYL_RC_OK);
    assert(myl_native_region_begin(&heap));
    assert(myl_rc_native_publish(&heap,&pointer,&snapshot,&original,1,MYL_RC_HISTORY_DIRECT));
    assert(snapshot!=original && myl_native_header_region(snapshot)==0 && !shared(snapshot));
    myl_native_region_end(&heap); assert(read_value(snapshot)==7);
    myl_rc_pin_release(&heap,&pin); myl_rc_owner_release(&heap,snapshot); myl_rc_owner_release(&heap,original); finish(&heap);
}
static void take_publishes_history_before_disarming(void) {
    myl_native_heap heap; start(&heap);
    void *source=mapping(&heap),*out=NULL,*old=source;
    assert(myl_rc_native_publish(&heap,&pointer,&out,&source,0,MYL_RC_HISTORY_TAKE));
    assert(!source && out==old && shared(out) && header(out)->owners==1);
    unique(&heap,&out); assert(out!=old && !shared(out));
    myl_rc_owner_release(&heap,out); finish(&heap);
}
static void physical_clone_does_not_mark_children(void) {
    myl_native_heap heap; start(&heap);
    void *child=mapping(&heap);
    myl_native_list *parent=myl_native_list_new(&heap,&pointer,1); assert(parent);
    assert(myl_native_list_append(&heap,parent,&child)); myl_rc_owner_release(&heap,child);
    void *original=parent,*copy=NULL;
    assert(myl_rc_native_copy(&heap,&pointer,&copy,&original,0));
    assert(!shared(original) && !shared(child));
    unique(&heap,&copy); assert(copy!=original && !shared(copy) && !shared(child));
    myl_rc_owner_release(&heap,copy); myl_rc_owner_release(&heap,original); finish(&heap);
}
static void cloned_prefix_refusal_discards_marks(void) {
    myl_native_heap heap; start(&heap);
    void *left=mapping(&heap),*right=mapping(&heap);
    myl_native_list *parent=myl_native_list_new(&heap,&pointer,2); assert(parent);
    assert(myl_native_list_append(&heap,parent,&left) && myl_native_list_append(&heap,parent,&right));
    myl_rc_pin pin={0}; assert(myl_rc_pin_acquire(&heap,parent,&pin)==MYL_RC_OK);
    header(right)->owners=MYL_RC_COUNT_MAX; void *out=NULL; size_t live=heap.objects_live;
    assert(!myl_rc_native_publish(&heap,&pointer,&out,&parent,0,MYL_RC_HISTORY_DIRECT));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    assert(!out && !shared(parent) && !shared(left) && !shared(right));
    assert(heap.objects_live==live && header(left)->owners==2);
    header(right)->owners=2; myl_rc_pin_release(&heap,&pin);
    myl_rc_owner_release(&heap,left); myl_rc_owner_release(&heap,right); myl_rc_owner_release(&heap,parent); finish(&heap);
}
static void metadata_refusal_preserves_history(void) {
    myl_native_heap heap; start(&heap);
    void *source=mapping(&heap),*out=NULL; size_t limit=heap.limit; heap.limit=heap.bytes;
    assert(!myl_rc_native_publish(&heap,&pointer,&out,&source,0,MYL_RC_HISTORY_DIRECT));
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    assert(!out && !shared(source) && header(source)->owners==1);
    heap.limit=limit; heap.exhausted=0;
    assert(myl_rc_native_publish(&heap,&pointer,&out,&source,0,MYL_RC_HISTORY_DIRECT));
    myl_rc_owner_release(&heap,out); myl_rc_owner_release(&heap,source); finish(&heap);
}
static void ownerless_view_publication(void) {
    myl_native_heap heap; start(&heap);
    void *source=mapping(&heap),*loan=NULL,*out=NULL;
    myl_rc_hold view={0}; assert(myl_rc_hold_acquire(&heap,source,&view)==MYL_RC_OK);
    assert(myl_rc_native_loan(&heap,&pointer,&loan,&source)); myl_rc_owner_release(&heap,source);
    assert(myl_rc_native_publish(&heap,&pointer,&out,&loan,0,MYL_RC_HISTORY_DIRECT));
    assert(out==source && header(out)->owners==1 && shared(out));
    myl_rc_native_unloan(&heap,&pointer,&loan); unique(&heap,&out); write_value(&heap,out,11);
    assert(read_value(view.payload)==7 && read_value(out)==11);
    myl_rc_owner_release(&heap,out); myl_rc_hold_release(&heap,&view); finish(&heap);
}
static void children_preserve_unpinned_outer(void) {
    myl_native_heap heap; start(&heap);
    myl_native_type list_type=pointer; list_type.collection_kind=1; list_type.element=&pointer;
    void *child=mapping(&heap),*out=NULL;
    myl_native_list *list=myl_native_list_new(&heap,&pointer,1); assert(list);
    assert(myl_native_list_append(&heap,list,&child));
    assert(myl_rc_native_publish(&heap,&list_type,&out,&list,0,MYL_RC_HISTORY_CHILDREN));
    assert(out==list && !shared(list) && shared(child));
    myl_rc_owner_release(&heap,out); myl_rc_owner_release(&heap,list); myl_rc_owner_release(&heap,child); finish(&heap);
}
static void source_children_replace_only_output(void) {
    myl_native_heap heap; start(&heap);
    myl_native_type list_type=pointer; list_type.collection_kind=1; list_type.element=&pointer;
    void *child=mapping(&heap),*out=NULL,*observed=NULL;
    myl_native_list *list=myl_native_list_new(&heap,&pointer,1); assert(list);
    assert(myl_native_list_append(&heap,list,&child));
    myl_rc_pin pin={0}; assert(myl_rc_pin_acquire(&heap,child,&pin)==MYL_RC_OK);
    assert(myl_rc_native_publish(&heap,&list_type,&out,&list,0,MYL_RC_HISTORY_SOURCE_CHILDREN));
    assert(out!=list && !shared(list) && !shared(out) && !shared(child));
    assert(myl_native_list_get(list,0,&observed) && observed==child);
    assert(myl_native_list_get(out,0,&observed) && observed!=child && !shared(observed));
    write_value(&heap,child,13); assert(read_value(observed)==7);
    myl_rc_pin_release(&heap,&pin);
    myl_rc_owner_release(&heap,out); myl_rc_owner_release(&heap,list); myl_rc_owner_release(&heap,child); finish(&heap);
}
static void repeated_pinned_mutable_snapshots_keep_distinct_identity(void) {
    myl_native_heap heap; start(&heap);
    void *value=mapping(&heap),*source[]={value,value},*out[2]={0};
    assert(myl_rc_owner_acquire(&heap,value)==MYL_RC_OK);
    myl_rc_pin pin={0}; assert(myl_rc_pin_acquire(&heap,value,&pin)==MYL_RC_OK);
    assert(myl_rc_native_publish(&heap,&pair,out,source,0,MYL_RC_HISTORY_DIRECT));
    assert(out[0]!=out[1] && out[0]!=value && out[1]!=value && !shared(out[0]) && !shared(out[1]));
    myl_rc_hold view={0}; assert(myl_rc_hold_acquire(&heap,out[0],&view)==MYL_RC_OK);
    unique(&heap,&out[0]); write_value(&heap,out[0],13);
    assert(read_value(view.payload)==13 && read_value(out[1])==7 && read_value(value)==7);
    myl_rc_hold_release(&heap,&view); myl_rc_pin_release(&heap,&pin);
    myl_rc_native_drop(&heap,&pair,out); myl_rc_native_drop(&heap,&pair,source); finish(&heap);
}
static void whole_view_publication_preserves_identity(void) {
    myl_native_heap heap; start(&heap);
    const myl_native_field field={.type=&pointer};
    const myl_native_type view_type={.size=8,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=&field,.field_count=1};
    const myl_rc_shape held={.size=8,.kind=MYL_RC_SHAPE_HOLD_POINTER};
    const myl_rc_field edge={.shape=&held};
    const myl_rc_shape view_shape={.size=8,.kind=MYL_RC_SHAPE_RECORD,.as.record={&edge,1}};
    const myl_rc_descriptor descriptor={.type=&view_type,.shape=&view_shape};
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    void *original=mapping(&heap),*out=NULL;
    myl_rc_hold view={0}; assert(myl_rc_hold_acquire(&heap,original,&view)==MYL_RC_OK);
    myl_rc_pin pin={0}; assert(myl_rc_pin_acquire(&heap,original,&pin)==MYL_RC_OK);
    size_t live=heap.objects_live;
    assert(myl_rc_native_publish(&heap,&view_type,&out,&view.payload,0,MYL_RC_HISTORY_DIRECT));
    assert(out==original && !shared(original) && heap.objects_live==live && header(original)->owners==1);
    write_value(&heap,original,13); assert(read_value(out)==13);
    myl_rc_native_drop(&heap,&view_type,&out); myl_rc_pin_release(&heap,&pin);
    myl_rc_hold_release(&heap,&view); myl_rc_owner_release(&heap,original); finish(&heap);
}
static void arena_mark_refusal_is_atomic(void) {
    myl_native_heap heap; start(&heap);
    void *limit=mapping(&heap); assert(myl_native_region_begin(&heap));
    void *arena=mapping(&heap),*source[]={arena,limit},*out[2]={0};
    header(limit)->owners=MYL_RC_COUNT_MAX;
    assert(!myl_rc_native_publish(&heap,&pair,out,source,1,MYL_RC_HISTORY_DIRECT));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    assert(!out[0] && !out[1] && !(((myl_native_object *)arena-1)->mark&MYL_NATIVE_OBJECT_SHARED));
    assert(!shared(limit)); header(limit)->owners=1;
    myl_native_region_end(&heap); myl_rc_owner_release(&heap,limit); finish(&heap);
}
int myl_rc_history_verify(void) {
    both_mutation_orders(0); both_mutation_orders(1); loan_then_pinned_publication(); publication_then_pin();
    late_count_refusal(); semantic_clone_marks_reused_children(); pinned_snapshot_preserves_older_region();
    take_publishes_history_before_disarming(); physical_clone_does_not_mark_children();
    cloned_prefix_refusal_discards_marks(); metadata_refusal_preserves_history(); ownerless_view_publication(); children_preserve_unpinned_outer(); source_children_replace_only_output();
    repeated_pinned_mutable_snapshots_keep_distinct_identity(); whole_view_publication_preserves_identity();
    arena_mark_refusal_is_atomic(); return 17;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) { assert(myl_rc_history_verify()==17); puts("native rc semantic history: 17 passed"); }
#endif
