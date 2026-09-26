#include "native_rc_collections.h"
#include "native_rc_dictionary.h"
#include "native_bytes.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_type text_pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=2};
static void init(myl_native_heap *heap) {
    myl_native_heap_init(heap,64u<<20);
    if (!myl_rc_enabled(heap)) assert(myl_rc_storage_init(heap)==MYL_RC_OK);
}
static uintptr_t owners(const void *payload) {
    return ((const myl_rc_object *)payload-1)->owners;
}
static void finish(myl_native_heap *heap) {
    assert(heap->objects_live==0);
    myl_native_heap_destroy(heap);
    assert(heap->bytes==0);
}
/* spec-case: RC-STORAGE-1. Immediate slot reuse resets every prefix/payload word;
 * large reservations preserve held storage, and all storage remains charged. */
static void storage_reuse_and_holds(void) {
    myl_native_heap heap;
    init(&heap);
    void *anchor=myl_rc_storage_bytes(&heap,1,0);
    void *old=myl_rc_storage_bytes(&heap,1,0);
    assert(anchor && old && (uintptr_t)old%16==0);
    *(unsigned char *)old=255;
    size_t epoch=heap.collections;
    myl_rc_owner_release(&heap,old);
    void *fresh=myl_rc_storage_bytes(&heap,1,0);
    assert(fresh==old && !*(unsigned char *)fresh && owners(fresh)==1);
    assert(((myl_rc_object *)fresh-1)->holds==0 && heap.collections>epoch);
    void *large=myl_rc_storage_bytes(&heap,20000,0);
    assert(large);
    memset(large,57,20000);
    myl_rc_hold hold={0};
    assert(myl_rc_hold_acquire(&heap,large,&hold)==MYL_RC_OK);
    size_t charged=heap.bytes;
    assert(!myl_rc_storage_extend(&heap,large,40000));
    myl_rc_owner_release(&heap,large);
    assert(owners(large)==0 && heap.bytes==charged && ((unsigned char *)large)[19999]==57);
    myl_rc_hold_release(&heap,&hold);
    assert(heap.bytes<charged);
    myl_rc_owner_release(&heap,fresh);
    myl_rc_owner_release(&heap,anchor);
    heap.collections=SIZE_MAX;
    fresh=myl_rc_storage_bytes(&heap,1,0);
    assert(fresh);
    myl_rc_owner_release(&heap,fresh);
    assert(heap.collections==SIZE_MAX);
    finish(&heap);
}
/* spec-case: RC-STORAGE-1. Classes include the complete 32-byte prefix; growth
 * keeps O/H and old bytes, refuses checked overflow, and cleans both heaps. */
static void storage_boundaries(void) {
    static const size_t widths[]={0,1,16,17,32,33,64,65,224,225,8160,8161,262145};
    myl_native_heap first, second;
    init(&first);
    init(&second);
    for (size_t i=0;i<sizeof widths/sizeof widths[0];i++) {
        void *a=myl_rc_storage_bytes(&first,widths[i],0);
        void *b=myl_rc_storage_bytes(&second,widths[i],0);
        assert(a && b && a!=b && (uintptr_t)a%16==0 && (uintptr_t)b%16==0);
        assert(owners(a)==1 && owners(b)==1);
        if (widths[i]) memset(a,12,widths[i]);
        myl_rc_owner_release(&first,a);
        myl_rc_owner_release(&second,b);
    }
    void *large=myl_rc_storage_bytes(&first,10000,0);
    assert(large);
    memset(large,81,10000);
    void *grown=myl_rc_storage_extend(&first,large,20000);
    assert(grown && owners(grown)==1 && ((unsigned char *)grown)[9999]==81 && !((unsigned char *)grown)[19999]);
    assert(!myl_rc_storage_extend(&first,grown,SIZE_MAX));
    myl_rc_owner_release(&first,grown);
    assert(!myl_rc_storage_bytes(&first,SIZE_MAX,0));
    finish(&second);
    finish(&first);
}
/* spec-case: RC-COLLECTION-1. Live list slots own one edge apiece; clone, replace,
 * pop, remove, clear and backing relocation preserve that exact accounting. */
static void list_edges_and_retired_backing(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *child=myl_native_list_new(&heap,&number,0);
    myl_native_list *list=myl_native_list_new(&heap,&pointer,1);
    assert(child && list && myl_native_list_append(&heap,list,&child));
    assert(owners(child)==2);
    myl_rc_hold backing={0};
    void *old=list->storage;
    assert(myl_rc_hold_acquire(&heap,old,&backing)==MYL_RC_OK);
    assert(myl_native_list_append(&heap,list,&child));
    assert(list->storage!=old && owners(old)==0 && owners(child)==3);
    assert(*(myl_native_list **)old==child);
    myl_rc_hold_release(&heap,&backing);
    myl_native_list *clone=myl_native_list_copy(&heap,list);
    assert(clone && owners(child)==5);
    assert(myl_rc_list_set(&heap,list,0,&child) && owners(child)==5);
    myl_native_list *popped=NULL;
    assert(myl_rc_list_pop(&heap,list,&popped)==1 && popped==child && owners(child)==5);
    myl_rc_owner_release(&heap,popped);
    assert(owners(child)==4);
    assert(myl_rc_list_remove(&heap,list,&child)==1 && owners(child)==3);
    assert(myl_rc_list_clear(&heap,clone) && owners(child)==1);
    myl_rc_owner_release(&heap,clone);
    myl_rc_owner_release(&heap,list);
    myl_rc_owner_release(&heap,child);
    finish(&heap);
}
/* spec-case: RC-COLLECTION-1. Constructors and clones release initialized
 * headers/edges when a backing reservation is refused by the heap ceiling. */
static void construction_refusal(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *warm=myl_native_list_new(&heap,&number,0);
    assert(warm);
    myl_rc_owner_release(&heap,warm);
    size_t baseline=heap.objects_live;
    heap.limit=heap.bytes;
    assert(!myl_native_list_new(&heap,&number,1000000));
    assert(heap.objects_live==baseline && heap.exhausted);
    heap.limit=64u<<20;
    myl_native_list *live=myl_native_list_new(&heap,&pointer,0);
    myl_native_list *child=myl_native_list_new(&heap,&number,0);
    assert(live && child && myl_native_list_append(&heap,live,&child));
    uintptr_t count=owners(child);
    heap.limit=heap.bytes;
    live->capacity=1000000;
    assert(!myl_native_list_copy(&heap,live));
    assert(owners(child)==count && live->length==1);
    live->capacity=4;
    heap.limit=64u<<20;
    myl_rc_owner_release(&heap,live);
    myl_rc_owner_release(&heap,child);
    finish(&heap);
}
/* spec-case: RC-DICTIONARY-1. Removed key/value bytes immediately stop owning;
 * compaction uses stable hash markers, and held bookkeeping/backing never
 * follows dictionary-embedded metadata after the dictionary dies. */
static void dictionary_dead_edges(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&text_pointer,&pointer,1);
    myl_native_list *child=myl_native_list_new(&heap,&number,0);
    assert(dict && child);
    for (unsigned i=0;i<16;i++) {
        unsigned char octet=(unsigned char)('a'+i);
        myl_native_text *key=myl_native_text_from_utf8(&heap,&octet,1);
        assert(key && myl_native_dictionary_write(&heap,dict,&key,&child));
        myl_rc_owner_release(&heap,key);
    }
    assert(owners(child)==17);
    myl_native_text *key=myl_native_text_from_utf8(&heap,(const unsigned char *)"h",1);
    myl_native_list *out=NULL;
    assert(myl_rc_dictionary_pop(&heap,dict,&key,&out)==1 && out==child);
    myl_rc_owner_release(&heap,out);
    myl_rc_owner_release(&heap,key);
    assert(owners(child)==16 && dict->dead==1);
    myl_native_dictionary_settle(dict);
    assert(!dict->dead && myl_native_dictionary_length(dict)==15);
    myl_rc_hold entries={0}, backing={0};
    assert(myl_rc_hold_acquire(&heap,dict->entries,&entries)==MYL_RC_OK);
    assert(myl_rc_hold_acquire(&heap,dict->entries->storage,&backing)==MYL_RC_OK);
    myl_rc_owner_release(&heap,dict);
    assert(owners(child)==1);
    myl_rc_hold_release(&heap,&entries);
    myl_rc_hold_release(&heap,&backing);
    myl_rc_owner_release(&heap,child);
    finish(&heap);
}
/* spec-case: RC-VIEWS-1. Byte views own canonical blocks, text views own canonical
 * text, and a buffer's snapshot marker never counts as a duplicate edge. */
static void views_and_snapshots(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_bytes *buffer=myl_native_bytes_new(&heap,(const unsigned char *)"abcdef",6);
    assert(buffer);
    void *backing=buffer->storage;
    myl_native_bytes *snapshot=myl_native_bytes_buffer_snapshot(&heap,buffer);
    myl_native_bytes *view=myl_native_bytes_view(&heap,snapshot,1,4);
    assert(snapshot && view && owners(backing)==3 && view->work.owner==backing);
    assert(myl_native_bytes_buffer_append_byte(&heap,buffer,'g')==MYL_BYTES_WROTE);
    assert(buffer->storage!=backing && owners(backing)==2);
    myl_rc_owner_release(&heap,snapshot);
    myl_rc_owner_release(&heap,buffer);
    assert(view->length==3 && !memcmp(view->storage,"bcd",3));
    myl_rc_owner_release(&heap,view);
    unsigned char letters[1024];
    memset(letters,'x',sizeof letters);
    myl_native_text *text=myl_native_text_from_utf8(&heap,letters,sizeof letters);
    myl_native_text *piece=myl_native_text_substring(&heap,text,128,896);
    assert(text && piece && (piece->flags&MYL_TEXT_VIEW) && owners(text)==2);
    myl_native_text *whole=myl_native_text_substring(&heap,text,0,1024);
    assert(whole==text && owners(text)==3);
    myl_rc_owner_release(&heap,whole);
    myl_rc_owner_release(&heap,text);
    assert(myl_native_text_storage(piece)[767]=='x');
    myl_rc_owner_release(&heap,piece);
    finish(&heap);
}
/* spec-case: RC-COLLECTION-1. A removed pinned receiver can reach O=0,H>0;
 * its returned snapshot is separate, and an overflowed copy commits no slot. */
static void pinned_pop_and_count_refusal(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *child=myl_native_list_new(&heap,&number,0);
    myl_native_list *parent=myl_native_list_new(&heap,&pointer,0);
    int64_t one=1, two=2;
    assert(child && parent && myl_native_list_append(&heap,child,&one));
    assert(myl_native_list_append(&heap,parent,&child));
    myl_rc_owner_release(&heap,child);
    myl_rc_pin pin={0};
    assert(myl_rc_pin_acquire(&heap,child,&pin)==MYL_RC_OK);
    myl_native_list *result=NULL;
    assert(myl_rc_list_pop(&heap,parent,&result)==1);
    assert(result!=child && owners(result)==1 && owners(child)==0);
    assert(myl_native_list_append(&heap,child,&two));
    assert(result->length==1 && child->length==2);
    myl_rc_pin_release(&heap,&pin);
    ((myl_rc_object *)result-1)->owners=MYL_RC_COUNT_MAX;
    assert(!myl_native_list_append(&heap,parent,&result));
    assert(parent->length==0 && owners(result)==MYL_RC_COUNT_MAX);
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    ((myl_rc_object *)result-1)->owners=1;
    myl_rc_owner_release(&heap,result);
    myl_rc_owner_release(&heap,parent);
    finish(&heap);
}
/* spec-case: RC-DICTIONARY-1. A span absence cannot survive pointer reuse,
 * including after the allocator's invalidation epoch saturates. */
static void dictionary_probe_reuse(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&text_pointer,&number,1);
    myl_native_text *stored=myl_native_text_from_utf8(&heap,(const unsigned char *)"yes",3);
    int64_t value=73, output=0;
    assert(dict && stored && myl_native_dictionary_write(&heap,dict,&stored,&value));
    myl_rc_owner_release(&heap,stored);
    const myl_native_text_span span={.offset=0,.bytes=3};
    for (unsigned saturated=0;saturated<2;saturated++) {
        if (saturated) heap.collections=SIZE_MAX;
        myl_native_text *query=myl_native_text_from_utf8(&heap,(const unsigned char *)"no!",3);
        assert(query && !myl_native_dictionary_read_range(&heap,dict,query,&span,&output));
        void *old=query;
        myl_rc_owner_release(&heap,query);
        query=myl_native_text_from_utf8(&heap,(const unsigned char *)"yes",3);
        assert(query==old);
        assert(myl_native_dictionary_read_range(&heap,dict,query,&span,&output) && output==73);
        myl_rc_owner_release(&heap,query);
    }
    myl_rc_owner_release(&heap,dict);
    finish(&heap);
}
/* spec-case: RC-STORAGE-1. Production slabs drain a million-deep chain at
 * their memory ceiling and then reuse capacity for a wide shared DAG. */
static void production_deep_and_wide(void) {
    static const myl_native_type node_type={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_RECORD};
    static const myl_rc_shape edge_shape={.size=sizeof(void *),.kind=MYL_RC_SHAPE_POINTER};
    static const myl_rc_descriptor descriptor={.type=&node_type,.shape=&edge_shape};
    static const myl_rc_module module={.abi=MYL_RC_ABI_VERSION,.descriptors=&descriptor,.descriptor_count=1};
    myl_native_heap heap;
    init(&heap);
    assert(myl_rc_module_register(&heap,&module)==MYL_RC_OK);
    myl_rc_alloc_request request={.element=&node_type,.count=1,.region=0};
    void *head=NULL;
    for (size_t i=0;i<1000000;i++) {
        void *node=NULL;
        assert(myl_rc_new(&heap,&request,&node)==MYL_RC_OK);
        memcpy(node,&head,sizeof head);
        head=node;
    }
    assert(heap.objects_live==1000000);
    heap.limit=heap.bytes;
    myl_rc_owner_release(&heap,head);
    assert(heap.objects_live==0);
    heap.limit=64u<<20;
    void *child=myl_rc_storage_bytes(&heap,1,0);
    myl_native_list *dag=myl_native_list_new(&heap,&pointer,50000);
    assert(child && dag);
    for (size_t i=0;i<50000;i++) assert(myl_native_list_append(&heap,dag,&child));
    assert(owners(child)==50001);
    myl_rc_owner_release(&heap,child);
    heap.limit=heap.bytes;
    myl_rc_owner_release(&heap,dag);
    finish(&heap);
}
int myl_rc_collections_verify(void) {
    storage_reuse_and_holds();
    storage_boundaries();
    list_edges_and_retired_backing();
    construction_refusal();
    dictionary_dead_edges();
    views_and_snapshots();
    pinned_pop_and_count_refusal();
    dictionary_probe_reuse();
    production_deep_and_wide();
    return 9;
}
#ifndef MYL_RC_COLLECTIONS_LIBRARY
int main(void) {
    assert(myl_rc_collections_verify()==9);
    puts("native RC collections: 9 passed");
    return 0;
}
#endif
