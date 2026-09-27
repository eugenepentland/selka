#include "native_rc_dictionary.h"
#include "native_regions.h"
#include "native_rc_internal.h"
#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

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
/* A refused direct publication commits no history. The direct pointer path
 * needs no metadata, so it also publishes at the budget ceiling. */
static void metadata_refusal_preserves_history(void) {
    myl_native_heap heap; start(&heap);
    void *source=mapping(&heap),*out=NULL;
    header(source)->owners=MYL_RC_COUNT_MAX;
    assert(!myl_rc_native_publish(&heap,&pointer,&out,&source,0,MYL_RC_HISTORY_DIRECT));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    assert(!out && !shared(source) && header(source)->owners==MYL_RC_COUNT_MAX);
    header(source)->owners=1;
    size_t limit=heap.limit,bytes=heap.bytes; heap.limit=heap.bytes;
    assert(myl_rc_native_publish(&heap,&pointer,&out,&source,0,MYL_RC_HISTORY_DIRECT));
    assert(out==source && shared(source) && header(source)->owners==2 && heap.bytes==bytes && !heap.exhausted);
    heap.limit=limit;
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
// spec: RC-PHYSICAL-RETAIN-1
static void physical_retain_preserves_pinned_identity(void) {
    myl_native_heap heap; start(&heap);
    void *source=mapping(&heap),*out=NULL;
    myl_rc_pin pin={0}; assert(myl_rc_pin_acquire(&heap,source,&pin)==MYL_RC_OK);
    assert(myl_rc_native_retain(&heap,&pointer,&out,&source,0));
    assert(source==out && header(source)->owners==2 && !shared(source));
    myl_rc_native_drop(&heap,&pointer,&out); myl_rc_pin_release(&heap,&pin);
    myl_rc_owner_release(&heap,source); finish(&heap);
}
static void physical_retain_arena_has_no_history(void) {
    myl_native_heap heap; start(&heap); assert(myl_native_region_begin(&heap));
    void *source=mapping(&heap),*out=NULL;
    assert(myl_rc_native_retain(&heap,&pointer,&out,&source,1));
    assert(source==out && !shared(source));
    myl_rc_native_drop(&heap,&pointer,&out);
    assert(!myl_rc_native_retain(&heap,&pointer,&out,&source,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR && !out && !shared(source));
    myl_native_region_end(&heap); finish(&heap);
}
static void physical_retain_refusal_rolls_back_prefix(void) {
    myl_native_heap heap; start(&heap);
    void *source[]={mapping(&heap),mapping(&heap)},*out[2]={0};
    header(source[1])->owners=MYL_RC_COUNT_MAX;
    assert(!myl_rc_native_retain(&heap,&pair,out,source,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT && !out[0] && !out[1]);
    assert(header(source[0])->owners==1 && !shared(source[0]) && !shared(source[1]));
    header(source[1])->owners=1; myl_rc_native_drop(&heap,&pair,source); finish(&heap);
}
static void physical_retain_replace_commits_before_retiring(void) {
    myl_native_heap heap; start(&heap);
    void *source=mapping(&heap),*target=mapping(&heap),*old=target;
    myl_rc_hold view={0}; assert(myl_rc_hold_acquire(&heap,old,&view)==MYL_RC_OK);
    header(source)->owners=MYL_RC_COUNT_MAX;
    assert(!myl_rc_native_retain_replace(&heap,&pointer,&target,&source,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT && target==old && header(old)->owners==1);
    header(source)->owners=1;
    assert(myl_rc_native_retain_replace(&heap,&pointer,&target,&source,0));
    assert(target==source && header(source)->owners==2 && header(old)->owners==0);
    assert(read_value(view.payload)==7 && !shared(source));
    myl_rc_hold_release(&heap,&view); myl_rc_owner_release(&heap,target);
    myl_rc_owner_release(&heap,source); finish(&heap);
}
static void physical_retain_mixed_hold_refusal(void) {
    myl_native_heap heap; start(&heap);
    const myl_native_type mixed={.size=16,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=pair_fields,.field_count=2};
    const myl_rc_shape held={.size=8,.kind=MYL_RC_SHAPE_HOLD_POINTER};
    const myl_rc_field edges[]={{.shape=&owned},{.offset=8,.shape=&held}};
    const myl_rc_shape shape={.size=16,.kind=MYL_RC_SHAPE_RECORD,.as.record={edges,2}};
    const myl_rc_descriptor descriptor={.type=&mixed,.shape=&shape};
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    void *payload=mapping(&heap),*source[]={payload,payload},*out[2]={0};
    header(payload)->holds=MYL_RC_COUNT_MAX;
    assert(!myl_rc_native_retain(&heap,&mixed,out,source,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT && !out[0] && !out[1]);
    assert(header(payload)->owners==1 && header(payload)->holds==MYL_RC_COUNT_MAX && !shared(payload));
    header(payload)->holds=0; myl_rc_owner_release(&heap,payload); finish(&heap);
}
// spec-case: RC-SEMANTIC-LOWERING-1
static void immutable_box_detaches_without_alias_history(unsigned arena, unsigned scoped) {
    myl_native_heap heap; start(&heap);
    if (arena) assert(myl_native_region_begin(&heap));
    void *child=mapping(&heap),*source[]={child,NULL},*box=NULL;
    myl_rc_alloc_request request={.element=&pair,.count=1,.region=arena};
    assert(myl_rc_new(&heap,&request,&box)==MYL_RC_OK);
    assert(myl_rc_native_retain(&heap,&pair,box,source,arena));
    myl_rc_owner_release(&heap,child);
    void *saved=NULL; assert(myl_rc_native_retain(&heap,&pointer,&saved,&box,arena));
    assert(!shared(box) && !shared(child));
    myl_rc_hold view={0}; assert(myl_rc_hold_acquire(&heap,child,&view)==MYL_RC_OK);
    myl_rc_slot slot={.shape=&owned,.address=&box,.region=arena};
    myl_rc_scope scope={0};
    if (scoped) {
        const myl_rc_projection projection={.shape=&owned,.offset=0,.immutable_box=1};
        const myl_rc_place place={.receiver=slot,.path=&projection,.count=1};
        myl_rc_scope_begin(&heap,&scope); assert(myl_rc_scope_prepare(&scope,&place)==MYL_RC_OK);
    } else {
        assert(myl_rc_box_detach_owned(&heap,&slot)==MYL_RC_OK);
        unique(&heap,(void **)box);
    }
    assert(box!=saved && myl_native_header_region(box)==arena && !shared(box));
    write_value(&heap,*(void **)box,13);
    assert(read_value(view.payload)==7 && read_value(*(void **)saved)==7 && read_value(*(void **)box)==13);
    if (scoped) myl_rc_scope_end(&scope);
    myl_rc_hold_release(&heap,&view); myl_rc_owner_release(&heap,box); myl_rc_owner_release(&heap,saved);
    if (arena) myl_native_region_end(&heap);
    finish(&heap);
}
static void immutable_box_refusal_preserves_children(void) {
    myl_native_heap heap; start(&heap);
    void *left=mapping(&heap),*right=mapping(&heap),*source[]={left,right},*box=NULL;
    myl_rc_alloc_request request={.element=&pair,.count=1};
    assert(myl_rc_new(&heap,&request,&box)==MYL_RC_OK && myl_rc_native_retain(&heap,&pair,box,source,0));
    void *before=box; header(right)->owners=MYL_RC_COUNT_MAX;
    myl_rc_slot slot={.shape=&owned,.address=&box};
    assert(myl_rc_box_detach_owned(&heap,&slot)==MYL_RC_COUNT_LIMIT);
    assert(box==before && !shared(left) && !shared(right) && header(left)->owners==2);
    header(right)->owners=2; myl_rc_owner_release(&heap,box);
    myl_rc_native_drop(&heap,&pair,source); finish(&heap);
}
// spec: RC-PLACE-ROLE-1
static void inline_loan_leaf_preserves_identity(unsigned ownerless) {
    myl_native_heap heap; start(&heap);
    void *owner=mapping(&heap),*source[]={owner,NULL},*loan[2]={0};
    assert(myl_rc_native_loan(&heap,&pair,loan,source));
    if (ownerless) myl_rc_owner_release(&heap,owner);
    const myl_rc_projection path={.shape=&pair_shape,.offset=0};
    myl_rc_place place={.receiver={.shape=&pair_shape,.address=loan},.path=&path,.count=1};
    myl_rc_scope scope={0}; myl_rc_scope_begin(&heap,&scope);
    assert(myl_rc_scope_prepare_loan(&scope,&place)==MYL_RC_OK && loan[0]==owner);
    write_value(&heap,loan[0],13); myl_rc_scope_end(&scope);
    assert(read_value(owner)==13 && !shared(owner) && header(owner)->holds==1);
    assert(header(owner)->owners==!ownerless);
    myl_rc_native_unloan(&heap,&pair,loan);
    if (!ownerless) myl_rc_owner_release(&heap,owner);
    finish(&heap);
}
static void loan_box_path(unsigned arena,unsigned ownerless,unsigned failure) {
    myl_native_heap heap; start(&heap);
    if (arena) assert(myl_native_region_begin(&heap));
    void *children[]={mapping(&heap),mapping(&heap)},*box=NULL,*loan=NULL;
    myl_rc_alloc_request request={.element=&pair,.count=1,.region=arena};
    assert(myl_rc_new(&heap,&request,&box)==MYL_RC_OK);
    assert(myl_rc_native_retain(&heap,&pair,box,children,arena));
    myl_rc_native_drop(&heap,&pair,children);
    void *left=((void **)box)[0],*right=((void **)box)[1],*old=box;
    assert(myl_rc_native_loan(&heap,&pointer,&loan,&box));
    if (ownerless) myl_rc_owner_release(&heap,box);
    myl_rc_hold view={0}; assert(myl_rc_hold_acquire(&heap,left,&view)==MYL_RC_OK);
    const myl_rc_projection path={.shape=&owned,.offset=0,.immutable_box=1};
    myl_rc_place place={.receiver={.shape=&owned,.address=&loan,.region=arena},.path=&path,.count=1};
    myl_rc_scope scope={0}; myl_rc_scope_begin(&heap,&scope);
    size_t limit=heap.limit;
    if (failure==1) header(right)->owners=MYL_RC_COUNT_MAX;
    if (failure==2) heap.limit=heap.bytes;
    myl_rc_status status=myl_rc_scope_prepare_loan(&scope,&place);
    if (failure) {
        assert(status==(failure==1?MYL_RC_COUNT_LIMIT:MYL_RC_ALLOCATION_REFUSED));
        assert(loan==old && !shared(left) && !shared(right));
        assert(header(old)->holds==1 && header(left)->owners==1);
        if (failure==1) header(right)->owners=1;
        heap.limit=limit;
    } else {
        assert(status==MYL_RC_OK && loan!=old && !shared(loan));
        assert(myl_native_header_region(loan)==arena);
        write_value(&heap,*(void **)loan,13);
        assert(read_value(view.payload)==7 && read_value(*(void **)loan)==13);
        if (!ownerless) assert(read_value(*(void **)box)==7);
    }
    myl_rc_scope_end(&scope);
    if (!arena) assert(header(loan)->owners==(failure?!ownerless:0) && header(loan)->holds==1);
    myl_rc_native_unloan(&heap,&pointer,&loan);
    myl_rc_hold_release(&heap,&view);
    if (!ownerless) myl_rc_owner_release(&heap,box);
    if (arena) myl_native_region_end(&heap);
    finish(&heap);
}
static void array_loan_box_path(void) {
    myl_native_heap heap; start(&heap);
    const myl_native_field field={.type=&pointer};
    const myl_native_type array={.size=16,.alignment=8,.kind=MYL_NATIVE_ARRAY,.fields=&field,.field_count=1,.count=2,.stride=8};
    const myl_rc_shape shape={.size=16,.kind=MYL_RC_SHAPE_ARRAY,.as.array={&owned,2,8}};
    const myl_rc_descriptor descriptor={.type=&array,.shape=&shape};
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    void *child=mapping(&heap),*body[]={child,NULL},*box=NULL;
    myl_rc_alloc_request request={.element=&pair,.count=1};
    assert(myl_rc_new(&heap,&request,&box)==MYL_RC_OK && myl_rc_native_retain(&heap,&pair,box,body,0));
    myl_rc_owner_release(&heap,child);
    void *source[]={box,box},*loan[2]={0};
    assert(myl_rc_native_loan(&heap,&array,loan,source));
    const myl_rc_shape *imported=myl_rc_descriptor_find(&heap,&array)->shape;
    const myl_rc_projection path[]={{.shape=imported},{.shape=&owned,.offset=0,.immutable_box=1}};
    myl_rc_place place={.receiver={.shape=imported,.address=loan},.path=path,.count=2};
    myl_rc_scope scope={0}; myl_rc_scope_begin(&heap,&scope);
    assert(myl_rc_scope_prepare_loan(&scope,&place)==MYL_RC_OK);
    assert(loan[0]!=box && loan[1]!=box && loan[0]!=loan[1]);
    assert(header(loan[0])->owners==0 && header(*(void **)loan[0])->owners==1);
    assert(header(loan[1])->owners==0 && header(*(void **)loan[1])->owners==1);
    write_value(&heap,*(void **)loan[0],13);
    assert(read_value(*(void **)loan[1])==7 && read_value(*(void **)box)==7);
    myl_rc_scope_end(&scope); myl_rc_native_unloan(&heap,&array,loan);
    myl_rc_owner_release(&heap,box); finish(&heap);
}

/* spec: RC-PHYSICAL-RETAIN-1. Physical retention preserves padding and the
 * successful acquisition prefix even when duplicate aliases hit the limit. */
static const myl_native_field retained_fields[]={{.offset=8,.type=&pointer},{.offset=24,.type=&pointer}};
static const myl_native_type retained={.size=32,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=retained_fields,.field_count=2};
static const myl_rc_field retained_edges[]={{.offset=8,.shape=&owned},{.offset=24,.shape=&owned}};
static const myl_rc_shape retained_shape={.size=32,.kind=MYL_RC_SHAPE_RECORD,.as.record={retained_edges,2}};
static const myl_rc_descriptor retained_descriptor={.type=&retained,.shape=&retained_shape};
static void retained_prefix_and_ownerless(void) {
    myl_native_heap heap; start(&heap);
    assert(myl_rc_descriptor_import(&heap,&retained_descriptor)==MYL_RC_OK);
    void *value=myl_rc_storage_bytes(&heap,8,0); assert(value);
    uint64_t source[]={71,(uintptr_t)value,93,(uintptr_t)value},output[4]={0};
    header(value)->owners=MYL_RC_COUNT_MAX-1;
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    myl_rc_counters before,after; assert(myl_rc_stats_snapshot(&heap,&before));
#endif
    assert(!myl_rc_native_retain(&heap,&retained,output,source,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT && header(value)->owners==MYL_RC_COUNT_MAX-1);
    assert(!output[0] && !output[1] && !output[2] && !output[3]);
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    assert(myl_rc_stats_snapshot(&heap,&after));
    assert(after.events[MYL_RC_STAT_OWNER_ACQUIRE]==before.events[MYL_RC_STAT_OWNER_ACQUIRE]+1);
    assert(after.events[MYL_RC_STAT_OWNER_RELEASE]==before.events[MYL_RC_STAT_OWNER_RELEASE]+1);
    assert(after.events[MYL_RC_STAT_OWNER_LIMIT]==before.events[MYL_RC_STAT_OWNER_LIMIT]+1);
#endif
    header(value)->owners=1;
    myl_rc_pin pin={0}; assert(myl_rc_pin_acquire(&heap,value,&pin)==MYL_RC_OK);
    myl_rc_owner_release(&heap,value); assert(!header(value)->owners && header(value)->holds==1);
    uintptr_t mark=header(value)->common.mark; heap.limit=heap.bytes;
    assert(myl_rc_native_retain(&heap,&retained,output,source,0));
    assert(!memcmp(source,output,sizeof source) && header(value)->owners==2 && header(value)->holds==1);
    assert(header(value)->common.mark==mark);
    myl_rc_native_drop(&heap,&retained,output); assert(!header(value)->owners);
    myl_rc_pin_release(&heap,&pin); finish(&heap);
}
static void retained_region_and_literals(void) {
    myl_native_heap heap; start(&heap);
    assert(myl_rc_descriptor_import(&heap,&retained_descriptor)==MYL_RC_OK);
    void *value=myl_rc_storage_bytes(&heap,8,0); assert(value && myl_native_region_begin(&heap));
    void *arena=myl_rc_storage_bytes(&heap,8,1); assert(arena);
    uint64_t source[]={71,(uintptr_t)value,93,(uintptr_t)arena},output[4]={1,2,3,4};
    uintptr_t mark=((myl_native_object *)arena-1)->mark;
    assert(!myl_rc_native_retain(&heap,&retained,output,source,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR && header(value)->owners==1);
    assert(!output[0] && !output[1] && !output[2] && !output[3]);
    assert(!myl_rc_native_retain(&heap,&retained,output,source,2));
    assert(myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR && header(value)->owners==1);
    assert(myl_rc_native_retain(&heap,&retained,output,source,1));
    assert(!memcmp(source,output,sizeof source) && header(value)->owners==2);
    assert(((myl_native_object *)arena-1)->mark==mark);
    myl_rc_native_drop(&heap,&retained,output);
    struct { myl_native_object common; uint64_t value; } literal={.common={.mark=MYL_NATIVE_OBJECT_IMMORTAL},.value=17};
    source[1]=0; source[3]=(uintptr_t)&literal.value;
    assert(myl_rc_native_retain(&heap,&retained,output,source,0) && !memcmp(source,output,sizeof source));
    myl_rc_native_drop(&heap,&retained,output); myl_native_region_end(&heap);
    myl_rc_owner_release(&heap,value); finish(&heap);
}
static uint64_t *retained_callback_output,*retained_callback_source;
static uint64_t retained_callback_expected[4];
static unsigned retained_callback_count,retained_callback_order[2];
static void retained_finalizer(myl_native_heap *heap, void *payload) {
    assert(!memcmp(retained_callback_output,retained_callback_expected,sizeof retained_callback_expected));
    assert(retained_callback_count<2);
    retained_callback_order[retained_callback_count++]=(unsigned)*(uint64_t *)payload;
    retained_callback_source[0]=17;
    static const myl_native_type extra={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    const myl_rc_descriptor descriptor={.type=&extra,.shape=&none};
    assert(myl_rc_descriptor_import(heap,&descriptor)==MYL_RC_OK);
    uint64_t input=7,output=9;
    assert(!myl_rc_native_retain(heap,&extra,&output,&input,heap->region_depth+1) && !output);
    void *temporary=myl_native_heap_alloc(heap,&extra,1); assert(temporary);
    myl_rc_owner_release(heap,temporary);
}
/* Queued callbacks see only full publication or whole-value zeroing. Callback
 * failures keep first-failure precedence over a later outer count refusal. */
static void retained_callbacks(unsigned failure) {
    static const myl_native_type finalized={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&finalized,.shape=&none,.finalize=retained_finalizer};
    myl_native_heap heap; start(&heap);
    assert(myl_rc_descriptor_import(&heap,&retained_descriptor)==MYL_RC_OK);
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    void *value=myl_rc_storage_bytes(&heap,8,0); assert(value);
    uint64_t source[]={71,(uintptr_t)value,93,(uintptr_t)value},output[4]={1,2,3,4};
    retained_callback_output=output; retained_callback_source=source; retained_callback_count=0;
    memcpy(retained_callback_expected,source,sizeof source);
    if (failure) { memset(retained_callback_expected,0,sizeof retained_callback_expected); header(value)->owners=MYL_RC_COUNT_MAX-1; }
    for (unsigned i=1;i<=2;i++) {
        void *queued=myl_native_heap_alloc(&heap,&finalized,1); assert(queued);
        *(uint64_t *)queued=i; myl_rc_edge_release(&heap,queued);
    }
    assert(myl_rc_native_retain(&heap,&retained,output,source,0)==!failure);
    assert(retained_callback_count==2 && retained_callback_order[0]==2 && retained_callback_order[1]==1);
    assert(source[0]==17 && !heap.rc->dead.head && myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR);
    if (failure) { assert(header(value)->owners==MYL_RC_COUNT_MAX-1); header(value)->owners=1; }
    else { assert(header(value)->owners==3); myl_rc_native_drop(&heap,&retained,output); }
    retained_callback_output=retained_callback_source=NULL;
    myl_rc_owner_release(&heap,value); finish(&heap);
}
static unsigned retained_opaque_closes;
static void retained_opaque_finalizer(myl_native_heap *heap, void *payload) {
    (void)heap; assert(*(uint64_t *)payload==73); ++retained_opaque_closes;
}
static void retained_opaque_finalized_pointer(void) {
    static const myl_native_type finalized={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&finalized,.shape=&none,.finalize=retained_opaque_finalizer};
    myl_native_heap heap; start(&heap); assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    void *value=myl_native_heap_alloc(&heap,&finalized,1),*out=NULL; assert(value);
    *(uint64_t *)value=73; retained_opaque_closes=0;
    assert(myl_rc_native_retain(&heap,&pointer,&out,&value,0) && out==value && header(value)->owners==2);
    myl_rc_owner_release(&heap,value); assert(!retained_opaque_closes);
    myl_rc_native_drop(&heap,&pointer,&out); assert(retained_opaque_closes==1); finish(&heap);
}
static void retained_rejects(myl_native_heap *heap, const myl_native_type *type, unsigned aliases) {
    pid_t child=fork(); assert(child>=0);
    if (!child) {
        struct rlimit no_core={0,0}; assert(!setrlimit(RLIMIT_CORE,&no_core));
        void *source=NULL,*output=NULL;
        (void)myl_rc_native_retain(heap,type,aliases?&source:&output,&source,0); _exit(0);
    }
    int status=0; assert(waitpid(child,&status,0)==child && WIFSIGNALED(status) && WTERMSIG(status)==SIGABRT);
}
static void retained_static_unique_and_cold(void) {
    static const myl_native_type resource={.size=8,.alignment=8,.kind=MYL_NATIVE_RESOURCE};
    static const myl_rc_shape none={.size=8,.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor unique={.type=&resource,.shape=&none,.finalize=myl_rc_finalize_unique};
    static const myl_native_type box={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=5,.element=&resource};
    static const myl_rc_descriptor boxed={.type=&box,.shape=&owned};
    myl_native_heap heap; start(&heap);
    assert(myl_rc_descriptor_import(&heap,&unique)==MYL_RC_OK && myl_rc_descriptor_import(&heap,&boxed)==MYL_RC_OK);
    retained_rejects(&heap,&resource,0); retained_rejects(&heap,&box,0);
    retained_rejects(&heap,&pointer,1); /* Source and empty destination must be distinct. */
    static const myl_native_type cold={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER};
    void *source=NULL,*output=(void *)(uintptr_t)71; heap.limit=heap.bytes;
    assert(!myl_rc_native_retain(&heap,&cold,&output,&source,0));
    assert(!output && myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED && !myl_rc_descriptor_find(&heap,&cold));
    heap.limit=0; assert(myl_rc_native_retain(&heap,&cold,&output,&source,0) && !output);
    static const myl_native_type empty={.alignment=1,.kind=MYL_NATIVE_PLAIN};
    uint64_t from=71,to=93;
    assert(myl_rc_native_retain(&heap,&empty,&to,&from,0) && from==71 && to==93);
    finish(&heap);
}
/* Deep metadata retains transfer-frame allocation refusal; wide metadata keeps
 * the unbounded walker and rolls back eight acquired aliases before the ninth. */
static void retained_depth_and_width_fallback(void) {
    myl_native_heap heap; start(&heap);
    myl_native_type types[9]={0}; myl_native_field fields[8]={0};
    myl_rc_shape shapes[9]={0}; myl_rc_field edges[8]={0};
    types[8]=pointer; shapes[8]=owned;
    for (size_t i=8;i>0;i--) {
        fields[i-1]=(myl_native_field){.type=&types[i]};
        edges[i-1]=(myl_rc_field){.shape=&shapes[i]};
        types[i-1]=(myl_native_type){.size=8,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=&fields[i-1],.field_count=1};
        shapes[i-1]=(myl_rc_shape){.size=8,.kind=MYL_RC_SHAPE_RECORD,.as.record={&edges[i-1],1}};
    }
    const myl_rc_descriptor deep={.type=&types[0],.shape=&shapes[0]};
    assert(myl_rc_descriptor_import(&heap,&deep)==MYL_RC_OK);
    void *value=myl_rc_storage_bytes(&heap,8,0),*out=(void *)(uintptr_t)123; assert(value);
    heap.limit=heap.bytes;
    assert(!myl_rc_native_retain(&heap,&types[0],&out,&value,0));
    assert(!out && myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED && header(value)->owners==1);
    heap.limit=0; assert(myl_rc_native_retain(&heap,&types[0],&out,&value,0));
    myl_rc_native_drop(&heap,&types[0],&out);
    myl_native_field wide_fields[9]; myl_rc_field wide_edges[9];
    for (size_t i=0;i<9;i++) {
        wide_fields[i]=(myl_native_field){.offset=i*8,.type=&pointer};
        wide_edges[i]=(myl_rc_field){.offset=i*8,.shape=&owned};
    }
    const myl_native_type wide={.size=72,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=wide_fields,.field_count=9};
    const myl_rc_shape wide_shape={.size=72,.kind=MYL_RC_SHAPE_RECORD,.as.record={wide_edges,9}};
    const myl_rc_descriptor descriptor={.type=&wide,.shape=&wide_shape};
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    void *source[9],*output[9]; for (size_t i=0;i<9;i++) source[i]=value;
    header(value)->owners=MYL_RC_COUNT_MAX-8;
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    myl_rc_counters before,after; assert(myl_rc_stats_snapshot(&heap,&before));
#endif
    assert(!myl_rc_native_retain(&heap,&wide,output,source,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT && header(value)->owners==MYL_RC_COUNT_MAX-8);
    for (size_t i=0;i<9;i++) assert(!output[i]);
#if defined(MYL_NATIVE_RC_COUNTING) && MYL_NATIVE_RC_COUNTING
    assert(myl_rc_stats_snapshot(&heap,&after));
    assert(after.events[MYL_RC_STAT_OWNER_ACQUIRE]==before.events[MYL_RC_STAT_OWNER_ACQUIRE]+8);
    assert(after.events[MYL_RC_STAT_OWNER_RELEASE]==before.events[MYL_RC_STAT_OWNER_RELEASE]+8);
#endif
    header(value)->owners=1; myl_rc_owner_release(&heap,value); finish(&heap);
}

int myl_rc_history_verify(void) {
    both_mutation_orders(0); both_mutation_orders(1); loan_then_pinned_publication(); publication_then_pin();
    late_count_refusal(); semantic_clone_marks_reused_children(); pinned_snapshot_preserves_older_region();
    take_publishes_history_before_disarming(); physical_clone_does_not_mark_children();
    cloned_prefix_refusal_discards_marks(); metadata_refusal_preserves_history(); ownerless_view_publication(); children_preserve_unpinned_outer(); source_children_replace_only_output();
    repeated_pinned_mutable_snapshots_keep_distinct_identity(); whole_view_publication_preserves_identity();
    arena_mark_refusal_is_atomic(); physical_retain_preserves_pinned_identity();
    physical_retain_arena_has_no_history(); physical_retain_refusal_rolls_back_prefix();
    physical_retain_replace_commits_before_retiring(); physical_retain_mixed_hold_refusal();
    immutable_box_detaches_without_alias_history(0,0); immutable_box_detaches_without_alias_history(1,0);
    immutable_box_detaches_without_alias_history(0,1); immutable_box_detaches_without_alias_history(1,1);
    immutable_box_refusal_preserves_children();
    inline_loan_leaf_preserves_identity(0); inline_loan_leaf_preserves_identity(1);
    loan_box_path(0,0,0); loan_box_path(1,0,0); loan_box_path(0,1,0);
    loan_box_path(0,0,1); loan_box_path(0,0,2); array_loan_box_path();
    retained_prefix_and_ownerless(); retained_region_and_literals(); retained_callbacks(0); retained_callbacks(1);
    retained_opaque_finalized_pointer(); retained_static_unique_and_cold(); retained_depth_and_width_fallback(); return 42;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) { assert(myl_rc_history_verify()==42); puts("native rc semantic history: 42 passed"); }
#endif
