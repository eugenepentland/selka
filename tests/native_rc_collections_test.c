#include "native_rc_collections.h"
#include "native_rc_internal.h"
#include "native_rc_dictionary.h"
#include "native_bytes.h"
#include "native_text_methods.h"
#include "native_print.h"
#include "native_equal.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>

static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_type text_pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=2};
myl_native_list *myl_native_text_split_whitespace(myl_native_heap *, myl_native_text *);
myl_native_list *myl_native_bytes_split_whitespace(myl_native_heap *, myl_native_bytes *);
static void init(myl_native_heap *heap) {
    myl_native_heap_init(heap,64u<<20);
    if (!myl_rc_enabled(heap)) assert(myl_rc_storage_init(heap)==MYL_RC_OK);
}
static uintptr_t owners(const void *payload) {
    return ((const myl_rc_object *)payload-1)->owners;
}
static size_t allocation_count(const void *payload) {
    uintptr_t mark=((const myl_native_object *)payload-1)->mark;
    return (mark>>MYL_NATIVE_OBJECT_COUNT_SHIFT) &
        (mark&MYL_NATIVE_OBJECT_ARENA?MYL_NATIVE_ARENA_COUNT_MAX:MYL_NATIVE_OBJECT_COUNT_MAX);
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
/* spec-case: RC-STORAGE-1. Cached admission belongs to this heap and type;
 * reused slots reset their complete prefix and payload across size classes. */
static void native_allocation_cache(void) {
    static const size_t widths[]={0,1,16,17,224,225,8160,8161};
    myl_native_type types[sizeof widths/sizeof widths[0]];
    for (size_t i=0;i<sizeof widths/sizeof widths[0];i++)
        types[i]=(myl_native_type){.size=widths[i],.alignment=1,.kind=MYL_NATIVE_PLAIN};
    myl_native_heap heap;
    for (unsigned round=0;round<2;round++) {
        init(&heap);
        assert(!myl_rc_descriptor_find(&heap,&types[0]));
        for (size_t i=0;i<sizeof widths/sizeof widths[0];i++) for (unsigned repeated=0;repeated<2;repeated++) {
            void *value=myl_native_heap_alloc(&heap,&types[i],1);
            assert(value && (uintptr_t)value%16==0 && owners(value)==1);
            myl_rc_object *header=(myl_rc_object *)value-1;
            assert(!header->holds && header->common.element==&types[i]);
            assert(allocation_count(value)==1 && !myl_native_header_region(value));
            for (size_t at=0;at<widths[i];at++) assert(((unsigned char *)value)[at]==0);
            memset(value,0xa5,widths[i]);
            myl_rc_owner_release(&heap,value);
        }
        /* Return to an earlier type after a different cached classification. */
        void *value=myl_native_heap_alloc(&heap,&types[1],1);
        assert(value && !*(unsigned char *)value && owners(value)==1);
        myl_rc_owner_release(&heap,value);
        finish(&heap);
    }
}
/* spec-case: RC-STORAGE-1. Cold metadata refusal is atomic; a full cached slab
 * refuses before publication, and trimming cannot leave a cached slab pointer. */
static void native_allocation_budget(void) {
    myl_native_heap heap;
    init(&heap);
    static const myl_native_type byte={.size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN};
    static const myl_native_type missing={.size=9,.alignment=1,.kind=MYL_NATIVE_PLAIN};
    assert(myl_rc_native_shape(&heap,&number) && myl_rc_native_shape(&heap,&byte));
    size_t metadata=heap.bytes;
    heap.limit=metadata;
    assert(!myl_native_heap_alloc(&heap,&missing,1));
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    assert(heap.bytes==metadata && !myl_rc_descriptor_find(&heap,&missing));
    heap.limit=0;
    heap.exhausted=0;
    void *retry=myl_native_heap_alloc(&heap,&missing,1);
    assert(retry && myl_rc_descriptor_find(&heap,&missing) && owners(retry)==1);
    myl_rc_owner_release(&heap,retry);
    finish(&heap);
    init(&heap);
    assert(myl_rc_native_shape(&heap,&number) && myl_rc_native_shape(&heap,&byte));
    metadata=heap.bytes;
    heap.limit=metadata;
    assert(!myl_native_heap_alloc(&heap,&number,1));
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED && !heap.objects_live);
    heap.exhausted=0;
    heap.limit=metadata+65536;
    void *values[2048];
    size_t count=0;
    while (count<sizeof values/sizeof values[0]) {
        void *value=myl_native_heap_alloc(&heap,&number,1);
        if (!value) break;
        values[count++]=value;
    }
    /* The 80-byte slab metadata leaves exactly 1363 48-byte slots. */
    assert(count==1363 && heap.bytes==heap.limit && heap.objects_live==count);
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    for (size_t i=0;i<count;i++) myl_rc_owner_release(&heap,values[i]);
    /* A generic large request trims the empty cached type's slab. The cache
     * stores its class only and must safely refill on the next count=1 hit. */
    heap.exhausted=0;
    void *large=myl_native_heap_alloc(&heap,&byte,9000);
    assert(large && heap.bytes<heap.limit);
    myl_rc_owner_release(&heap,large);
    assert(heap.bytes==metadata);
    void *again=myl_native_heap_alloc(&heap,&number,1);
    assert(again && owners(again)==1 && *(uint64_t *)again==0 && heap.bytes==heap.limit);
    myl_rc_owner_release(&heap,again);
    finish(&heap);
}
/* spec-case: RC-STORAGE-1. A warm heap-body cache cannot bypass the requested
 * arena, count, alignment or overflow semantics of generic allocation. */
static void native_allocation_regions_and_counts(void) {
    myl_native_heap heap;
    init(&heap);
    static const myl_native_type over_aligned={.size=32,.alignment=32,.kind=MYL_NATIVE_PLAIN};
    assert(myl_rc_native_shape(&heap,&over_aligned));
    void *kept=myl_native_heap_alloc(&heap,&number,1);
    assert(kept && myl_native_region_begin(&heap));
    void *arena=myl_native_heap_alloc(&heap,&number,1);
    assert(arena && myl_native_header_region(arena)==1 && allocation_count(arena)==1);
    assert(*(uint64_t *)arena==0);
    void *empty=myl_native_heap_alloc_at(&heap,&number,0,0);
    void *many=myl_native_heap_alloc_at(&heap,&number,3,0);
    assert(empty && many && owners(empty)==1 && owners(many)==1);
    assert(!allocation_count(empty) && allocation_count(many)==3);
    for (size_t i=0;i<3;i++) assert(((uint64_t *)many)[i]==0);
    size_t live=heap.objects_live, charged=heap.bytes;
    assert(!myl_native_heap_alloc_at(&heap,&number,1,2));
    assert(myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR);
    assert(!myl_native_heap_alloc_at(&heap,&number,SIZE_MAX,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    assert(!myl_native_heap_alloc_at(&heap,&over_aligned,1,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    assert(heap.objects_live==live && heap.bytes==charged);
    myl_native_region_end(&heap);
    myl_rc_owner_release(&heap,empty);
    myl_rc_owner_release(&heap,many);
    myl_rc_owner_release(&heap,kept);
    finish(&heap);
}
typedef struct { unsigned allocations, retirements, refuse; } AllocatorProbe;
static myl_rc_status probe_allocate(myl_native_heap *heap, const myl_rc_alloc_request *request, void **out) {
    AllocatorProbe *probe=myl_rc_allocator_context(heap);
    ++probe->allocations;
    *out=NULL;
    if (probe->refuse) return MYL_RC_ALLOCATION_REFUSED;
    assert(!request->region && request->element==&number);
    size_t bytes=sizeof(myl_rc_object)+request->count*number.size;
    myl_rc_object *object=calloc(1,bytes);
    assert(object);
    object->owners=1;
    object->common=(myl_native_object){.element=&number,.mark=request->count<<MYL_NATIVE_OBJECT_COUNT_SHIFT};
    heap->bytes+=bytes;
    *out=object+1;
    return MYL_RC_OK;
}
static void probe_retire(myl_native_heap *heap, void *payload) {
    AllocatorProbe *probe=myl_rc_allocator_context(heap);
    ++probe->retirements;
    size_t bytes=sizeof(myl_rc_object)+allocation_count(payload)*number.size;
    assert(heap->bytes>=bytes);
    heap->bytes-=bytes;
    free((myl_rc_object *)payload-1);
}
/* spec-case: RC-STORAGE-1. The public native adapter still invokes custom
 * allocation/retirement hooks, including a refused request after a success. */
static void native_allocation_custom_hooks(void) {
    myl_native_heap heap;
    init(&heap);
    void *value=myl_native_heap_alloc(&heap,&number,1);
    assert(value);
    myl_rc_owner_release(&heap,value);
    myl_rc_heap_destroy(&heap);
    AllocatorProbe probe={0};
    static const myl_rc_allocator hooks={.allocate=probe_allocate,.retire=probe_retire};
    assert(myl_rc_heap_init(&heap,&hooks,&probe)==MYL_RC_OK);
    value=myl_native_heap_alloc(&heap,&number,1);
    assert(value && owners(value)==1 && probe.allocations==1);
    myl_rc_owner_release(&heap,value);
    assert(probe.retirements==1);
    probe.refuse=1;
    size_t charged=heap.bytes;
    assert(!myl_native_heap_alloc(&heap,&number,1) && probe.allocations==2);
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED && heap.bytes==charged);
    assert(probe.retirements==1);
    myl_native_heap_destroy(&heap);
    assert(!heap.bytes);
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
    static const myl_native_field field={.type=&pointer};
    static const myl_native_type node_type={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_RECORD,.fields=&field,.field_count=1};
    static const myl_rc_shape edge_shape={.size=sizeof(void *),.kind=MYL_RC_SHAPE_POINTER};
    static const myl_rc_field edge={.shape=&edge_shape};
    static const myl_rc_shape node_shape={.size=sizeof(void *),.kind=MYL_RC_SHAPE_RECORD,.as.record={.fields=&edge,.count=1}};
    static const myl_rc_descriptor descriptor={.type=&node_type,.shape=&node_shape};
    static const myl_rc_module module={.abi=MYL_RC_ABI_VERSION,.descriptors=&descriptor,.descriptor_count=1};
    myl_native_heap heap;
    init(&heap);
    assert(myl_rc_module_register(&heap,&module)==MYL_RC_OK);
    assert(((const myl_rc_binding *)myl_rc_descriptor_find(&heap,&node_type))->flat.count==1);
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
/* spec-case: RC-VIEWS-1. Nonempty text and byte transforms transfer each
 * temporary success token once, including split helpers that append pieces. */
static void transforms_release_temporaries(void) {
    myl_native_heap heap;
    init(&heap);
    const unsigned char raw[]=" a,b\nc\r\nd ";
    myl_native_text *input=myl_native_text_from_utf8(&heap,raw,sizeof raw-1);
    myl_native_text *comma=myl_native_text_from_utf8(&heap,(const unsigned char *)",",1);
    myl_native_text *insert=myl_native_text_from_utf8(&heap,(const unsigned char *)"::",2);
    assert(input && comma && insert);
    myl_native_text *trim=myl_native_text_trim(&heap,input,MYL_TEXT_BOTH);
    myl_native_text *upper=myl_native_text_case(&heap,input,1);
    myl_native_text *padded=myl_native_text_zfill(&heap,input,20);
    myl_native_text *replaced=myl_native_text_replace(&heap,input,comma,insert);
    myl_native_list *lines=myl_native_text_lines(&heap,input);
    myl_native_list *words=myl_native_text_split_whitespace(&heap,input);
    myl_native_list *pieces=myl_native_text_split(&heap,input,comma);
    assert(trim && upper && padded && replaced && lines && words && pieces);
    assert(trim->bytes==sizeof raw-3 && padded->length==20 && lines->length==3 && words->length==3 && pieces->length==2);
    myl_native_text *joined=myl_native_text_join(&heap,comma,pieces);
    myl_native_bytes *bytes=myl_native_bytes_encode(&heap,input);
    myl_native_bytes *delimiter=myl_native_bytes_encode(&heap,comma);
    assert(joined && myl_native_text_equal(joined,input) && bytes && delimiter);
    myl_native_list *byte_parts=myl_native_bytes_split(&heap,bytes,delimiter);
    myl_native_list *byte_words=myl_native_bytes_split_whitespace(&heap,bytes);
    myl_native_bytes *byte_joined=myl_native_bytes_join(&heap,delimiter,byte_parts);
    myl_native_text *hex=myl_native_bytes_hex(&heap,bytes);
    int status=-1;
    myl_native_bytes *unhex=myl_native_bytes_from_hex(&heap,hex,&status);
    assert(byte_parts && byte_words && byte_joined && hex && unhex && status==MYL_BYTES_OK);
    assert(byte_words->length==3 && byte_joined->length==sizeof raw-1 && !memcmp(unhex->storage,raw,sizeof raw-1));
    myl_native_text *decoded=myl_native_bytes_decode(&heap,bytes,&status);
    assert(decoded && status==MYL_BYTES_OK && myl_native_text_equal(decoded,input));
    void *owned[]={input,comma,insert,trim,upper,padded,replaced,lines,words,pieces,joined,bytes,delimiter,byte_parts,byte_words,byte_joined,hex,unhex,decoded};
    for (size_t i=0;i<sizeof owned/sizeof owned[0];i++) myl_rc_owner_release(&heap,owned[i]);
    finish(&heap);
}
/* spec-case: RC-COLLECTION-1. Sorting relocates existing owners; keyed sorted
 * copies acquire their own edges, and failed pinned cloning unwinds its prefix. */
static void sorting_and_partial_clone(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *values=myl_native_list_new(&heap,&text_pointer,0);
    myl_native_list *keys=myl_native_list_new(&heap,&number,0);
    myl_native_list *sorted=myl_native_list_new(&heap,&text_pointer,3);
    assert(values && keys && sorted);
    myl_native_list *empty=myl_native_list_new(&heap,&text_pointer,0);
    myl_rc_sort_request empty_request={.values=empty,.source=values,.keys=keys,.shape=1};
    assert(empty && myl_rc_list_sort_keyed(&heap,&empty_request));
    assert(empty->length==0 && empty->storage==NULL && values->storage==NULL);
    myl_rc_owner_release(&heap,empty);
    for (unsigned i=0;i<3;i++) {
        unsigned char letter=(unsigned char)('c'-i);
        myl_native_text *text=myl_native_text_from_utf8(&heap,&letter,1);
        int64_t key=(int64_t)i;
        assert(text && myl_native_list_append(&heap,values,&text) && myl_native_list_append(&heap,keys,&key));
        myl_rc_owner_release(&heap,text);
    }
    assert(myl_native_list_sort(values,3));
    myl_rc_sort_request request={.values=sorted,.source=values,.keys=keys,.shape=1,.reverse=1};
    assert(myl_rc_list_sort_keyed(&heap,&request));
    assert(myl_native_text_storage(*(myl_native_text **)sorted->storage)[0]=='c');
    myl_rc_owner_release(&heap,values);
    assert(myl_native_text_storage(*(myl_native_text **)sorted->storage)[0]=='c');
    myl_rc_owner_release(&heap,keys);
    myl_rc_owner_release(&heap,sorted);
    myl_native_list *a=myl_native_list_new(&heap,&number,4);
    myl_native_list *b=myl_native_list_new(&heap,&number,4);
    myl_native_list *parent=myl_native_list_new(&heap,&pointer,2);
    assert(a && b && parent && myl_native_list_append(&heap,parent,&a) && myl_native_list_append(&heap,parent,&b));
    myl_rc_pin first={0}, second={0};
    assert(myl_rc_pin_acquire(&heap,a,&first)==MYL_RC_OK && myl_rc_pin_acquire(&heap,b,&second)==MYL_RC_OK);
    size_t live=heap.objects_live;
    myl_native_list *fresh=myl_native_list_copy(&heap,parent), *published=NULL;
    assert(fresh && *(void **)fresh->storage==a && owners(a)==3 && owners(b)==3);
    const myl_native_type list_pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=1};
    b->capacity=1000000;
    heap.limit=heap.bytes;
    assert(!myl_rc_native_publish(&heap,&list_pointer,&published,&fresh,0,MYL_RC_HISTORY_CHILDREN|MYL_RC_HISTORY_TAKE));
    assert(!published && fresh && owners(a)==3 && owners(b)==3);
    myl_rc_owner_release(&heap,fresh);
    assert(heap.objects_live==live && owners(a)==2 && owners(b)==2);
    b->capacity=4;
    heap.limit=64u<<20;
    myl_rc_pin_release(&heap,&second);
    myl_rc_pin_release(&heap,&first);
    myl_rc_owner_release(&heap,parent);
    myl_rc_owner_release(&heap,a);
    myl_rc_owner_release(&heap,b);
    finish(&heap);
}
/* spec-case: RC-DICTIONARY-1. Existing/new setdefault, self update, snapshots,
 * copies and clear each establish or consume exactly their declared edges. */
static void dictionary_method_results(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&pointer,0);
    myl_native_list *child=myl_native_list_new(&heap,&number,0);
    int64_t first=1, second=2;
    myl_native_list *one=NULL, *two=NULL;
    assert(dict && child && myl_native_dictionary_write(&heap,dict,&first,&child));
    assert(myl_native_dictionary_setdefault(&heap,dict,&first,&child,&one));
    assert(myl_native_dictionary_setdefault(&heap,dict,&second,&child,&two));
    assert(one==child && two==child && owners(child)==5);
    assert(myl_native_dictionary_update(&heap,dict,dict) && owners(child)==5);
    myl_native_list *snapshot=myl_native_dictionary_snapshot(&heap,dict,0);
    myl_native_dictionary *clone=myl_native_dictionary_clone_at(&heap,dict,0);
    assert(snapshot && clone && owners(child)==9);
    myl_rc_dictionary_clear(&heap,dict);
    assert(!myl_native_dictionary_length(dict) && owners(child)==7);
    myl_rc_owner_release(&heap,dict);
    myl_rc_owner_release(&heap,clone);
    myl_rc_owner_release(&heap,snapshot);
    myl_rc_owner_release(&heap,one);
    myl_rc_owner_release(&heap,two);
    assert(owners(child)==1);
    myl_rc_owner_release(&heap,child);
    finish(&heap);
}
/* spec-case: RC-COLLECTION-1. Unpublished arena containers undo committed
 * heap edges immediately; their empty headers remain safe for bulk close. */
static void arena_construction_abort(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *child=myl_native_list_new(&heap,&number,0);
    assert(child && myl_native_region_begin(&heap));
    myl_native_list *list=myl_native_list_new(&heap,&pointer,1);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&pointer,0);
    int64_t key=1;
    assert(list && dict && myl_native_list_append(&heap,list,&child));
    assert(myl_native_dictionary_write(&heap,dict,&key,&child) && owners(child)==3);
    assert(myl_native_header_region(list)==1);
    assert(!myl_rc_storage_extend(&heap,list->storage,1024));
    myl_rc_native_abort(&heap,list);
    assert(owners(child)==2 && list->length==0 && !list->storage);
    myl_rc_native_abort(&heap,dict);
    assert(owners(child)==1 && !dict->entries);
    myl_native_region_end(&heap);
    assert(heap.region_depth==0 && heap.objects_live==1);
    myl_rc_owner_release(&heap,child);
    finish(&heap);
}
/* spec-case: RC-COLLECTION-1. A long finite pinned path is copied and released
 * under a 256 KiB host-stack ceiling using staged logical-edge traversal. */
static void deep_pinned_snapshot(void) {
    enum { depth=4096 };
    myl_native_heap heap;
    init(&heap);
    myl_native_list **nodes=calloc(depth,sizeof *nodes);
    myl_rc_pin *pins=calloc(depth,sizeof *pins);
    assert(nodes && pins);
    myl_native_list *head=NULL;
    for (size_t i=0;i<depth;i++) {
        myl_native_list *node=myl_native_list_new(&heap,&pointer,head?1:0);
        assert(node);
        if (head) { assert(myl_native_list_append(&heap,node,&head)); myl_rc_owner_release(&heap,head); }
        nodes[i]=node;
        head=node;
    }
    for (size_t i=0;i<depth;i++) assert(myl_rc_pin_acquire(&heap,nodes[i],&pins[i])==MYL_RC_OK);
    struct rlimit original, reduced;
    assert(!getrlimit(RLIMIT_STACK,&original));
    reduced=original;
    if (reduced.rlim_cur>262144) { reduced.rlim_cur=262144; assert(!setrlimit(RLIMIT_STACK,&reduced)); }
    myl_native_list *copy=NULL;
    assert(myl_rc_native_copy(&heap,&pointer,&copy,&head,0));
    assert(copy && copy!=head);
    myl_native_list *left=head, *right=copy;
    for (size_t i=0;i<depth;i++) {
        assert(left!=right && left->length==right->length);
        if (left->length) { left=*(myl_native_list **)left->storage; right=*(myl_native_list **)right->storage; }
    }
    myl_rc_owner_release(&heap,copy);
    myl_rc_owner_release(&heap,head);
    for (size_t i=depth;i;i--) myl_rc_pin_release(&heap,&pins[i-1]);
    assert(!setrlimit(RLIMIT_STACK,&original));
    free(pins);
    free(nodes);
    finish(&heap);
}
/* spec-case: RC-DICTIONARY-1. Staged dictionary cloning keeps dead-entry
 * positions stable in a pinned source while the copy acquires live owners. */
static void pinned_sparse_dictionary(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&pointer,0);
    myl_native_list *child=myl_native_list_new(&heap,&number,0);
    assert(dict && child);
    for (int64_t i=0;i<8;i++) assert(myl_native_dictionary_write(&heap,dict,&i,&child));
    int64_t key=3;
    myl_native_list *removed=NULL;
    assert(myl_rc_dictionary_pop(&heap,dict,&key,&removed)==1);
    myl_rc_owner_release(&heap,removed);
    assert(dict->dead==1);
    void *backing=dict->entries->storage;
    myl_rc_pin pin={0};
    assert(myl_rc_pin_acquire(&heap,dict,&pin)==MYL_RC_OK);
    myl_native_dictionary *copy=NULL;
    assert(myl_rc_native_copy(&heap,&pointer,&copy,&dict,0));
    assert(copy && copy!=dict && dict->dead==1 && dict->entries->storage==backing);
    assert(myl_native_dictionary_length(copy)==7 && owners(child)==15);
    myl_rc_owner_release(&heap,copy);
    myl_rc_pin_release(&heap,&pin);
    myl_rc_owner_release(&heap,dict);
    assert(owners(child)==1);
    myl_rc_owner_release(&heap,child);
    finish(&heap);
}
/* spec-case: RC-COLLECTION-1. A failed staged arena clone undoes edges acquired
 * by an earlier nested clone before returning, even before bulk arena close. */
static void arena_snapshot_rollback(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *leaf=myl_native_list_new(&heap,&number,0);
    myl_native_list *branch=myl_native_list_new(&heap,&pointer,1);
    myl_native_list *overflow=myl_native_list_new(&heap,&number,0);
    myl_native_list *root=myl_native_list_new(&heap,&pointer,2);
    assert(leaf && branch && overflow && root);
    assert(myl_native_list_append(&heap,branch,&leaf));
    assert(myl_native_list_append(&heap,root,&branch));
    assert(myl_native_list_append(&heap,root,&overflow));
    myl_rc_pin root_pin={0}, branch_pin={0};
    assert(myl_rc_pin_acquire(&heap,root,&root_pin)==MYL_RC_OK);
    assert(myl_rc_pin_acquire(&heap,branch,&branch_pin)==MYL_RC_OK);
    size_t live=heap.objects_live;
    ((myl_rc_object *)overflow-1)->owners=MYL_RC_COUNT_MAX;
    assert(myl_native_region_begin(&heap));
    myl_native_list *copy=NULL;
    assert(!myl_rc_native_copy(&heap,&pointer,&copy,&root,1));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    assert(!copy && owners(leaf)==2 && owners(branch)==2 && owners(root)==1);
    assert(owners(overflow)==MYL_RC_COUNT_MAX && heap.objects_live>live);
    myl_native_region_end(&heap);
    assert(owners(leaf)==2 && heap.objects_live==live);
    ((myl_rc_object *)overflow-1)->owners=2;
    myl_rc_pin_release(&heap,&branch_pin);
    myl_rc_pin_release(&heap,&root_pin);
    myl_rc_owner_release(&heap,root);
    myl_rc_owner_release(&heap,branch);
    myl_rc_owner_release(&heap,overflow);
    myl_rc_owner_release(&heap,leaf);
    finish(&heap);
}
/* spec-case: RC-COLLECTION-1. A refused pinned pop leaves caller output and
 * receiver unchanged; aliased append inputs survive backing relocation. */
static void publication_refusal_output(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *child=myl_native_list_new(&heap,&number,0);
    myl_native_list *list=myl_native_list_new(&heap,&pointer,1);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&pointer,0);
    int64_t key=1;
    assert(child && list && dict && myl_native_list_append(&heap,list,&child));
    assert(myl_native_dictionary_write(&heap,dict,&key,&child));
    myl_rc_pin pin={0};
    assert(myl_rc_pin_acquire(&heap,child,&pin)==MYL_RC_OK);
    child->capacity=1000000;
    heap.limit=heap.bytes;
    myl_native_list *output=child;
    assert(myl_rc_list_pop(&heap,list,&output)==-1 && output==child && list->length==1);
    assert(myl_rc_dictionary_pop(&heap,dict,&key,&output)==-1 && output==child);
    assert(myl_native_dictionary_length(dict)==1 && owners(child)==3);
    child->capacity=0;
    heap.limit=64u<<20;
    myl_rc_pin_release(&heap,&pin);
    myl_rc_owner_release(&heap,list);
    myl_rc_owner_release(&heap,dict);
    myl_rc_owner_release(&heap,child);
    myl_native_list *numbers=myl_native_list_new(&heap,&number,1);
    assert(numbers && myl_native_list_append(&heap,numbers,&key));
    assert(myl_native_list_append(&heap,numbers,numbers->storage));
    assert(numbers->length==2 && ((int64_t *)numbers->storage)[1]==key);
    myl_rc_owner_release(&heap,numbers);
    finish(&heap);
}
/* spec-case: RC-COLLECTION-1. Reserve refusal precedes a pinned arena snapshot,
 * so an unpublished append cannot strand the snapshot's heap child edges. */
static void arena_append_refusal(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *leaf=myl_native_list_new(&heap,&number,0);
    myl_native_list *branch=myl_native_list_new(&heap,&pointer,1);
    assert(leaf && branch && myl_native_list_append(&heap,branch,&leaf));
    assert(myl_native_region_begin(&heap));
    myl_native_list *list=myl_native_list_new(&heap,&pointer,4096);
    assert(list);
    for (size_t i=0;i<4096;i++) assert(myl_native_list_append(&heap,list,&branch));
    myl_rc_pin pin={0};
    assert(myl_rc_pin_acquire(&heap,branch,&pin)==MYL_RC_OK);
    heap.limit=heap.bytes;
    assert(!myl_native_list_append(&heap,list,&branch));
    assert(list->length==4096 && owners(leaf)==2 && owners(branch)==4097);
    heap.limit=64u<<20;
    myl_rc_native_abort(&heap,list);
    assert(owners(branch)==1);
    myl_native_region_end(&heap);
    myl_rc_pin_release(&heap,&pin);
    myl_rc_owner_release(&heap,branch);
    myl_rc_owner_release(&heap,leaf);
    finish(&heap);
}
/* spec-case: RC-DICTIONARY-1. Physical key/value and setdefault result retains
 * share one rollback journal; an earlier language SHARE owns pin snapshots. */
static void dictionary_publication_rollback(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *key=myl_native_list_new(&heap,&number,0);
    myl_native_list *leaf=myl_native_list_new(&heap,&number,0);
    myl_native_list *overflow=myl_native_list_new(&heap,&number,0);
    myl_native_list *value=myl_native_list_new(&heap,&pointer,2);
    assert(key && leaf && overflow && value);
    assert(myl_native_list_append(&heap,value,&leaf));
    assert(myl_native_list_append(&heap,value,&overflow));
    myl_rc_pin pin={0};
    assert(myl_rc_pin_acquire(&heap,value,&pin)==MYL_RC_OK);
    ((myl_rc_object *)value-1)->owners=MYL_RC_COUNT_MAX;
    assert(myl_native_region_begin(&heap));
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&pointer,&pointer,0);
    assert(dict && !myl_native_dictionary_write(&heap,dict,&key,&value));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    assert(owners(key)==1 && owners(leaf)==2 && owners(value)==MYL_RC_COUNT_MAX);
    myl_native_list *output=key;
    assert(!myl_native_dictionary_setdefault(&heap,dict,&key,&value,&output));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    assert(output==key && owners(key)==1 && owners(leaf)==2 && !myl_native_dictionary_length(dict));
    myl_rc_native_abort(&heap,dict);
    myl_native_region_end(&heap);
    ((myl_rc_object *)value-1)->owners=1;
    myl_rc_pin_release(&heap,&pin);
    myl_rc_owner_release(&heap,value);
    myl_rc_owner_release(&heap,overflow);
    myl_rc_owner_release(&heap,leaf);
    myl_rc_owner_release(&heap,key);
    finish(&heap);
}
/* spec-case: RC-COLLECTION-1. An unpublished conditional edit in an arena
 * releases the cloned container's heap child immediately when abandoned. */
static void arena_edit_abort(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *leaf=myl_native_list_new(&heap,&number,0);
    myl_native_list *list=myl_native_list_new(&heap,&pointer,1);
    assert(leaf && list && myl_native_list_append(&heap,list,&leaf));
    assert(myl_rc_owner_acquire(&heap,list)==MYL_RC_OK);
    assert(myl_native_region_begin(&heap));
    myl_rc_slot slot={.shape=myl_rc_native_shape(&heap,&pointer),.address=&list,.region=1};
    myl_rc_edit edit={0};
    assert(myl_rc_unique_borrow(&heap,&slot,NULL,&edit)==MYL_RC_OK);
    assert(edit.owned && edit.payload!=list && owners(leaf)==3);
    myl_rc_edit_abort(&heap,&edit);
    assert(!edit.owned && !edit.payload && owners(leaf)==2 && owners(list)==2);
    myl_native_region_end(&heap);
    myl_rc_owner_release(&heap,list);
    myl_rc_owner_release(&heap,list);
    myl_rc_owner_release(&heap,leaf);
    finish(&heap);
}
static void print_number(MylPrint *out, const void *value, unsigned depth) {
    myl_print_integer(out,value,depth,8,1);
}
/* spec-case: RC-DICTIONARY-1. Read-only iteration, snapshots, update, equality
 * and printing preserve a pinned sparse receiver's captured entry addresses. */
static void pinned_dictionary_readers(void) {
    static const myl_native_type dictionary_pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=3,.element=&number};
    myl_native_heap heap;
    init(&heap);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&number,0);
    assert(dict);
    for (int64_t key=0;key<8;key++) {
        int64_t value=key+10;
        assert(myl_native_dictionary_write(&heap,dict,&key,&value));
    }
    int64_t removed=3, last=7, output=0;
    assert(myl_rc_dictionary_pop(&heap,dict,&removed,&output)==1 && output==13);
    const void *captured=myl_native_dictionary_find(dict,&last);
    uint64_t generation=dict->entries->generation;
    myl_rc_pin pin={0};
    assert(myl_rc_pin_acquire(&heap,dict,&pin)==MYL_RC_OK);
    myl_native_dictionary *copy=myl_native_dictionary_clone_at(&heap,dict,0);
    myl_native_list *keys=myl_native_dictionary_snapshot(&heap,dict,1);
    assert(copy && keys && keys->length==7 && myl_native_dictionary_update(&heap,copy,dict));
    for (size_t i=0;i<7;i++) {
        int64_t key=-1, value=-1, expected=(int64_t)(i<3?i:i+1);
        assert(myl_native_dictionary_key_at(dict,i,&key) && key==expected);
        assert(myl_native_dictionary_value_at(dict,i,&value) && value==expected+10);
    }
    assert(myl_native_equal(&dictionary_pointer,&dict,&copy)==1);
    MylPrint rendered={0};
    myl_print_dictionary(&rendered,&dict,0,print_number,print_number);
    const char *expected="{0: 10, 1: 11, 2: 12, 4: 14, 5: 15, 6: 16, 7: 17}";
    assert(!rendered.failed && rendered.length==strlen(expected) && !memcmp(rendered.bytes,expected,rendered.length));
    free(rendered.bytes);
    rendered=(MylPrint){0};
    myl_print_set(&rendered,&dict,0,print_number);
    expected="{0, 1, 2, 4, 5, 6, 7}";
    assert(!rendered.failed && rendered.length==strlen(expected) && !memcmp(rendered.bytes,expected,rendered.length));
    free(rendered.bytes);
    assert(dict->dead==1 && dict->entries->generation==generation);
    assert(myl_native_dictionary_find(dict,&last)==captured && *(const int64_t *)captured==17);
    myl_rc_pin_release(&heap,&pin);
    myl_rc_owner_release(&heap,keys);
    myl_rc_owner_release(&heap,copy);
    myl_rc_owner_release(&heap,dict);
    finish(&heap);
}
/* spec-case: RC-VIEWS-1. Failed arena split construction immediately releases
 * heap backing retained by earlier fresh text views, before arena bulk close. */
static void arena_text_split_rollback(void) {
    myl_native_heap heap;
    init(&heap);
    unsigned char raw[1025];
    memset(raw,'x',sizeof raw);
    raw[512]=' ';
    myl_native_text *input=myl_native_text_from_utf8(&heap,raw,sizeof raw);
    myl_native_text *separator=myl_native_text_from_utf8(&heap,(const unsigned char *)" ",1);
    assert(input && separator);
    for (unsigned mode=0;mode<3;mode++) {
        ((unsigned char *)myl_native_text_storage(input))[512]=mode==2?'\n':' ';
        ((myl_rc_object *)input-1)->owners=MYL_RC_COUNT_MAX-1;
        assert(myl_native_region_begin(&heap));
        myl_native_list *parts=mode==0?myl_native_text_split(&heap,input,separator):
            mode==1?myl_native_text_split_whitespace(&heap,input):myl_native_text_lines(&heap,input);
        assert(!parts && myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
        assert(owners(input)==MYL_RC_COUNT_MAX-1);
        ((myl_rc_object *)input-1)->owners=1;
        myl_native_region_end(&heap);
        assert(owners(input)==1);
    }
    /* Leave precisely enough room for the result header and its first view,
     * then refuse the append's initial raw backing after that view was made. */
    ((unsigned char *)myl_native_text_storage(input))[512]='x';
    assert(myl_native_region_begin(&heap));
    assert(myl_rc_storage_bytes(&heap,1,1));
    size_t room=(size_t)(heap.arena_window.limit-heap.arena_window.cursor);
    size_t needed=sizeof(myl_native_object)*2+sizeof(myl_native_list)+sizeof(myl_native_text_view);
    assert(room>needed+sizeof(myl_native_object));
    assert(myl_rc_storage_bytes(&heap,room-needed-sizeof(myl_native_object),1));
    heap.limit=heap.bytes;
    assert(!myl_native_text_lines(&heap,input) && owners(input)==1);
    heap.limit=64u<<20;
    myl_native_region_end(&heap);
    myl_rc_owner_release(&heap,separator);
    myl_rc_owner_release(&heap,input);
    finish(&heap);
}
/* spec-case: RC-TRANSFER-1. The native pointer path keeps copy/take publication
 * rules at the count ceiling and tight budget, and falls back for pinned/arena
 * pointers without inventing an ordinary owner for a non-heap payload. */
static void native_pointer_transactions(void) {
    myl_native_heap heap;
    init(&heap);
    assert(myl_rc_native_shape(&heap,&pointer));
    void *source=myl_rc_storage_bytes(&heap,8,0), *target=NULL;
    assert(source);
    heap.limit=heap.bytes;
    assert(myl_rc_native_copy(&heap,&pointer,&target,&source,0));
    assert(target==source && owners(source)==2);
    myl_rc_native_drop(&heap,&pointer,&target);
    assert(!target && owners(source)==1);
    ((myl_rc_object *)source-1)->owners=MYL_RC_COUNT_MAX;
    assert(!myl_rc_native_copy(&heap,&pointer,&target,&source,0));
    assert(!target && owners(source)==MYL_RC_COUNT_MAX && myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    assert(myl_rc_native_take(&heap,&pointer,&target,&source,0));
    assert(!source && owners(target)==MYL_RC_COUNT_MAX);
    ((myl_rc_object *)target-1)->owners=1;
    myl_rc_native_drop(&heap,&pointer,&target);
    heap.limit=64u<<20;
    source=myl_rc_storage_bytes(&heap,200000,0);
    assert(source);
    heap.limit=heap.bytes;
    myl_rc_pin pin={0};
    assert(myl_rc_pin_acquire(&heap,source,&pin)==MYL_RC_OK);
    size_t live=heap.objects_live;
    void *sentinel=(void *)(uintptr_t)1234;
    assert(!myl_rc_native_take(&heap,&pointer,&sentinel,&source,0));
    assert(sentinel==(void *)(uintptr_t)1234 && source && owners(source)==1 && heap.objects_live==live);
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    myl_rc_pin_release(&heap,&pin);
    myl_rc_native_drop(&heap,&pointer,&source);
    heap.limit=64u<<20;
    assert(myl_native_region_begin(&heap));
    source=myl_rc_storage_bytes(&heap,8,heap.region_depth);
    assert(source && myl_rc_native_copy(&heap,&pointer,&target,&source,heap.region_depth));
    assert(target==source && (((myl_native_object *)source-1)->mark&MYL_NATIVE_OBJECT_SHARED));
    myl_rc_native_drop(&heap,&pointer,&target);
    assert(!target && !myl_rc_native_copy(&heap,&pointer,&target,&source,0));
    assert(!target && myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR);
    myl_native_region_end(&heap);
    source=NULL;
    assert(myl_rc_native_copy(&heap,&pointer,&target,&source,0) && !target);
    finish(&heap);
}
static const myl_rc_shape flat_pointer={.size=8,.kind=MYL_RC_SHAPE_POINTER};
static const myl_rc_shape flat_scalar={.size=8,.kind=MYL_RC_SHAPE_NONE};
static const myl_native_type flat_array_type={.size=64,.alignment=8,.kind=MYL_NATIVE_ARRAY,.element=&pointer,.count=8,.stride=8};
static const myl_rc_shape flat_array_shape={.size=64,.kind=MYL_RC_SHAPE_ARRAY,.as.array={.element=&flat_pointer,.count=8,.stride=8}};
static const myl_native_type wide_array_type={.size=72,.alignment=8,.kind=MYL_NATIVE_ARRAY,.element=&pointer,.count=9,.stride=8};
static const myl_rc_shape wide_array_shape={.size=72,.kind=MYL_RC_SHAPE_ARRAY,.as.array={.element=&flat_pointer,.count=9,.stride=8}};
static unsigned flat_count(myl_native_heap *heap, const myl_native_type *type, const myl_rc_shape *shape) {
    myl_rc_descriptor descriptor={.type=type,.shape=shape};
    assert(myl_rc_descriptor_import(heap,&descriptor)==MYL_RC_OK);
    return ((const myl_rc_binding *)myl_rc_descriptor_find(heap,type))->flat.count;
}
/* spec-case: RC-TRANSFER-1. Repeated aliases consume eight count units, not one;
 * preflight refuses atomically and take preserves overlap/self staging. */
static void flat_array_transactions(void) {
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&flat_array_type,&flat_array_shape)==8);
    assert(flat_count(&heap,&wide_array_type,&wide_array_shape)>8);
    void *leaf=myl_rc_storage_bytes(&heap,8,0);
    assert(leaf);
    void *source[9]={0}, *target[8]={0};
    for (unsigned i=0;i<8;i++) {
        source[i]=leaf;
        assert(myl_rc_owner_acquire(&heap,leaf)==MYL_RC_OK);
    }
    myl_rc_object *object=(myl_rc_object *)leaf-1;
    object->owners=MYL_RC_COUNT_MAX-7;
    memset(target,0xa5,sizeof target);
    assert(!myl_rc_native_copy(&heap,&flat_array_type,target,source,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT && object->owners==MYL_RC_COUNT_MAX-7);
    for (unsigned i=0;i<8;i++) assert(source[i]==leaf && !target[i]);
    object->owners=MYL_RC_COUNT_MAX-8;
    size_t bytes=heap.bytes;
    heap.limit=bytes;
    assert(myl_rc_native_copy(&heap,&flat_array_type,target,source,0));
    assert(object->owners==MYL_RC_COUNT_MAX && heap.bytes==bytes);
    myl_rc_native_drop(&heap,&flat_array_type,target);
    assert(object->owners==MYL_RC_COUNT_MAX-8);
    object->owners=MYL_RC_COUNT_MAX;
    assert(myl_rc_native_take(&heap,&flat_array_type,target,source,0));
    assert(object->owners==MYL_RC_COUNT_MAX && heap.bytes==bytes);
    for (unsigned i=0;i<8;i++) assert(!source[i] && target[i]==leaf);
    object->owners=9;
    assert(myl_rc_native_take(&heap,&flat_array_type,source,target,0));
    assert(myl_rc_native_take(&heap,&flat_array_type,source,source,0));
    assert(object->owners==9);
    assert(myl_rc_native_take(&heap,&flat_array_type,source+1,source,0));
    assert(!source[0] && object->owners==9);
    for (unsigned i=1;i<9;i++) assert(source[i]==leaf);
    myl_rc_native_drop(&heap,&flat_array_type,source+1);
    assert(object->owners==1);
    heap.limit=64u<<20;
    source[0]=leaf;
    for (unsigned i=1;i<8;i++) source[i]=leaf;
    myl_rc_pin pin={0};
    assert(myl_rc_pin_acquire(&heap,leaf,&pin)==MYL_RC_OK);
    assert(myl_rc_native_copy(&heap,&flat_array_type,target,source,0));
    assert(target[0]!=leaf && owners(target[0])==8 && owners(leaf)==1);
    for (unsigned i=1;i<8;i++) assert(target[i]==target[0]);
    myl_rc_pin_release(&heap,&pin);
    myl_rc_native_drop(&heap,&flat_array_type,target);
    void *wide[9]={0};
    source[8]=leaf;
    assert(myl_rc_native_copy(&heap,&wide_array_type,wide,source,0) && owners(leaf)==10);
    myl_rc_native_drop(&heap,&wide_array_type,wide);
    assert(owners(leaf)==1);
    myl_rc_owner_release(&heap,leaf);
    finish(&heap);
}
/* spec-case: RC-TRANSFER-1. Admission pairs full native fields with RC token
 * kinds, excluding H/variants/raw resources even when GC tracing looks alike. */
static void flat_record_admission(void) {
    static const myl_native_type resource={.size=8,.kind=MYL_NATIVE_RESOURCE};
    static const myl_native_field fields[]={{.offset=0,.type=&pointer},{.offset=8,.type=&number}};
    static const myl_rc_field edges[]={{.offset=0,.shape=&flat_pointer},{.offset=8,.shape=&flat_scalar}};
    static const myl_native_type record={.size=16,.kind=MYL_NATIVE_RECORD,.fields=fields,.field_count=2};
    static const myl_rc_shape shape={.size=16,.kind=MYL_RC_SHAPE_RECORD,.as.record={.fields=edges,.count=2}};
    static const myl_native_field unique_fields[]={{.offset=0,.type=&pointer},{.offset=8,.type=&resource}};
    static const myl_native_type unique={.size=16,.kind=MYL_NATIVE_RECORD,.fields=unique_fields,.field_count=2};
    static const myl_rc_shape held={.size=8,.kind=MYL_RC_SHAPE_HOLD_POINTER};
    static const myl_rc_field held_edges[]={{.offset=0,.shape=&held},{.offset=8,.shape=&flat_scalar}};
    static const myl_native_type view={.size=16,.kind=MYL_NATIVE_RECORD,.fields=fields,.field_count=2};
    static const myl_rc_shape view_shape={.size=16,.kind=MYL_RC_SHAPE_RECORD,.as.record={.fields=held_edges,.count=2}};
    static const myl_native_type variant={.size=16,.kind=MYL_NATIVE_VARIANT,.fields=fields,.field_count=2};
    static const myl_rc_field cases[]={{.offset=8,.shape=&flat_pointer,.tag=1}};
    static const myl_rc_shape variant_shape={.size=16,.kind=MYL_RC_SHAPE_VARIANT,.as.variant={.fields=cases,.count=1,.tag_offset=0}};
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&record,&shape)==1);
    assert(flat_count(&heap,&unique,&shape)>8);
    assert(flat_count(&heap,&view,&view_shape)>8);
    assert(flat_count(&heap,&variant,&variant_shape)>8);
    struct { void *value; uint64_t number; } source={myl_rc_storage_bytes(&heap,8,0),12345}, target={0};
    assert(source.value && myl_rc_native_copy(&heap,&record,&target,&source,0));
    assert(source.value==target.value && target.number==12345 && owners(source.value)==2);
    myl_rc_native_drop(&heap,&record,&target);
    ((myl_rc_object *)source.value-1)->owners=MYL_RC_COUNT_MAX;
    target.number=54321;
    assert(!myl_rc_native_copy(&heap,&record,&target,&source,0));
    assert(!target.value && !target.number && source.number==12345 && myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    ((myl_rc_object *)source.value-1)->owners=1;
    assert(myl_native_region_begin(&heap));
    myl_rc_native_drop(&heap,&record,&source);
    source.value=myl_rc_storage_bytes(&heap,8,heap.region_depth);
    source.number=67890;
    assert(source.value && !myl_rc_native_copy(&heap,&record,&target,&source,0));
    assert(!target.value && !target.number && source.number==67890 && myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR);
    myl_native_region_end(&heap);
    finish(&heap);
}
typedef struct { const unsigned char *value; size_t bytes; unsigned order[3], count; size_t others; } DropLog;
typedef struct { DropLog *log; unsigned id; } DropObserver;
static void observe_drop(myl_native_heap *heap, void *payload) {
    DropObserver *observer=payload;
    DropLog *log=observer->log;
    assert(!heap->rc->walk.depth && heap->rc->dead.active && log->count<3);
    if (!log->value) assert(heap->objects_live==3-log->count+log->others);
    for (size_t i=0;i<log->bytes;i++) assert(!log->value[i]);
    log->order[log->count++]=observer->id;
}
static const myl_native_type drop_observer_type={.size=sizeof(DropObserver),.alignment=_Alignof(DropObserver),.kind=MYL_NATIVE_PLAIN};
static DropObserver *drop_observer(myl_native_heap *heap, DropLog *log, unsigned id) {
    static const myl_rc_shape shape={.size=sizeof(DropObserver),.kind=MYL_RC_SHAPE_NONE};
    static const myl_rc_descriptor descriptor={.type=&drop_observer_type,.shape=&shape,.finalize=observe_drop};
    assert(myl_rc_descriptor_import(heap,&descriptor)==MYL_RC_OK);
    myl_rc_alloc_request request={.element=&drop_observer_type,.count=1};
    void *payload=NULL;
    assert(myl_rc_new(heap,&request,&payload)==MYL_RC_OK);
    *(DropObserver *)payload=(DropObserver){.log=log,.id=id};
    return payload;
}
/* spec-case: RC-RELEASE-1. Flat slot drops preserve descriptor traversal order,
 * zero the complete value before callbacks, and never treat holds as owners. */
static void flat_drop_order(void) {
    static const myl_native_field fields[]={
        {.offset=16,.type=&pointer},{.offset=0,.type=&pointer},{.offset=24,.type=&pointer},{.offset=8,.type=&pointer},
        {.offset=40,.type=&pointer},{.offset=48,.type=&pointer},{.offset=56,.type=&pointer},{.offset=64,.type=&pointer},
        {.offset=32,.type=&number}};
    static const myl_rc_field edges[]={
        {.offset=16,.shape=&flat_pointer},{.offset=0,.shape=&flat_pointer},{.offset=24,.shape=&flat_pointer},{.offset=8,.shape=&flat_pointer},
        {.offset=40,.shape=&flat_pointer},{.offset=48,.shape=&flat_pointer},{.offset=56,.shape=&flat_pointer},{.offset=64,.shape=&flat_pointer},
        {.offset=32,.shape=&flat_scalar}};
    static const myl_native_type type={.size=72,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=fields,.field_count=9};
    static const myl_rc_shape shape={.size=72,.kind=MYL_RC_SHAPE_RECORD,.as.record={.fields=edges,.count=9}};
    struct { void *a,*b,*alias,*c; uint64_t scalar; void *pinned,*arena,*literal,*nil; } value={0};
    struct { myl_native_object header; uint64_t data; } literal={.header={.mark=MYL_NATIVE_OBJECT_IMMORTAL}};
    DropLog log={.value=(const unsigned char *)&value,.bytes=sizeof value};
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&type,&shape)==8);
    value.a=drop_observer(&heap,&log,1);
    value.b=drop_observer(&heap,&log,2);
    value.c=drop_observer(&heap,&log,3);
    value.alias=value.a;
    assert(myl_rc_owner_acquire(&heap,value.a)==MYL_RC_OK);
    value.scalar=123456;
    value.pinned=myl_rc_storage_bytes(&heap,8,0);
    myl_rc_pin pin={0};
    assert(value.pinned && myl_rc_pin_acquire(&heap,value.pinned,&pin)==MYL_RC_OK);
    assert(myl_native_region_begin(&heap));
    value.arena=myl_rc_storage_bytes(&heap,8,1);
    value.literal=&literal.data;
    assert(value.arena);
    heap.limit=heap.bytes;
    myl_rc_native_drop(&heap,&type,&value);
    assert(log.count==3 && log.order[0]==2 && log.order[1]==3 && log.order[2]==1);
    assert(owners(pin.hold.payload)==0 && ((myl_rc_object *)pin.hold.payload-1)->holds==1);
    assert(literal.header.mark==MYL_NATIVE_OBJECT_IMMORTAL);
    myl_rc_pin_release(&heap,&pin);
    myl_native_region_end(&heap);
    finish(&heap);
}
/* spec-case: RC-RELEASE-1. Repeated allocation elements enqueue their ordinary
 * leaves in the same order as the generic walker before retiring the parent. */
static void flat_body_order(void) {
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&flat_array_type,&flat_array_shape)==8);
    DropLog log={0};
    void *a=drop_observer(&heap,&log,1), *b=drop_observer(&heap,&log,2), *c=drop_observer(&heap,&log,3);
    myl_rc_alloc_request request={.element=&flat_array_type,.count=2};
    void *payload=NULL;
    assert(myl_rc_new(&heap,&request,&payload)==MYL_RC_OK);
    void **body=payload;
    body[0]=a;
    body[7]=b;
    body[8]=a;
    body[15]=c;
    assert(myl_rc_owner_acquire(&heap,a)==MYL_RC_OK);
    heap.limit=heap.bytes;
    myl_rc_owner_release(&heap,payload);
    assert(log.count==3 && log.order[0]==3 && log.order[1]==1 && log.order[2]==2);
    finish(&heap);
}
/* spec: RC-FLAT-SINGLE-DESTRUCTION-1. One-element bodies retain descriptor
 * order, defer callbacks, and keep a pinned last owner alive until H release. */
static void flat_single_body_order(void) {
    static const myl_native_field fields[]={
        {.offset=16,.type=&pointer},{.offset=0,.type=&pointer},{.offset=24,.type=&pointer},{.offset=8,.type=&pointer},
        {.offset=32,.type=&pointer},{.offset=40,.type=&pointer},{.offset=48,.type=&pointer},{.offset=56,.type=&pointer}};
    static const myl_rc_field edges[]={
        {.offset=16,.shape=&flat_pointer},{.offset=0,.shape=&flat_pointer},{.offset=24,.shape=&flat_pointer},{.offset=8,.shape=&flat_pointer},
        {.offset=32,.shape=&flat_pointer},{.offset=40,.shape=&flat_pointer},{.offset=48,.shape=&flat_pointer},{.offset=56,.shape=&flat_pointer}};
    static const myl_native_type type={.size=64,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=fields,.field_count=8};
    static const myl_rc_shape shape={.size=64,.kind=MYL_RC_SHAPE_RECORD,.as.record={.fields=edges,.count=8}};
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&type,&shape)==8);
    myl_rc_alloc_request request={.element=&type,.count=0};
    void *payload=NULL;
    assert(myl_rc_new(&heap,&request,&payload)==MYL_RC_OK);
    myl_rc_owner_release(&heap,payload);
    DropLog log={.others=1};
    void *a=drop_observer(&heap,&log,1), *b=drop_observer(&heap,&log,2), *c=drop_observer(&heap,&log,3);
    request.count=1;
    assert(myl_rc_new(&heap,&request,&payload)==MYL_RC_OK);
    void **body=payload;
    body[0]=a;body[1]=b;body[2]=a;body[3]=c;
    assert(myl_rc_owner_acquire(&heap,a)==MYL_RC_OK);
    myl_rc_pin pin={0};
    assert(myl_rc_pin_acquire(&heap,a,&pin)==MYL_RC_OK);
    assert(myl_native_region_begin(&heap));
    body[4]=myl_rc_storage_bytes(&heap,8,heap.region_depth);
    struct { myl_native_object header; uint64_t data; } literal={.header={.mark=MYL_NATIVE_OBJECT_IMMORTAL}};
    body[5]=&literal.data;
    assert(body[4]);
    heap.limit=heap.bytes;
    myl_rc_owner_release(&heap,payload);
    assert(log.count==2 && log.order[0]==2 && log.order[1]==3);
    assert(owners(a)==0 && ((myl_rc_object *)a-1)->holds==1);
    assert(literal.header.mark==MYL_NATIVE_OBJECT_IMMORTAL);
    myl_rc_pin_release(&heap,&pin);
    assert(log.count==3 && log.order[2]==1);
    myl_native_region_end(&heap);
    finish(&heap);
}
static const myl_native_field plain_pair_fields[]={{.type=&number},{.offset=8,.type=&number}};
static const myl_native_type plain_pair={.size=16,.alignment=8,.kind=MYL_NATIVE_RECORD,
    .fields=plain_pair_fields,.field_count=2};
static const myl_rc_shape plain_pair_shape={.size=16,.kind=MYL_RC_SHAPE_NONE};
/* spec-case: RC-PLAIN-REPLACE-1. Plain record replacement is memmove-compatible,
 * preserves source bits, refuses invalid regions atomically, and needs no extra
 * allocation for a wide nested array once its metadata is registered. */
static void plain_retain_replace(void) {
    static const myl_native_type wide={.size=256,.alignment=8,.kind=MYL_NATIVE_ARRAY,
        .element=&plain_pair,.count=16,.stride=16};
    static const myl_rc_shape wide_shape={.size=256,.kind=MYL_RC_SHAPE_NONE};
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&plain_pair,&plain_pair_shape)==0);
    assert(flat_count(&heap,&wide,&wide_shape)==0);
    uint64_t bits[]={1,2,3,4};
    assert(myl_rc_native_retain_replace(&heap,&plain_pair,bits+1,bits,0));
    assert(bits[0]==1 && bits[1]==1 && bits[2]==2 && bits[3]==4);
    assert(myl_rc_native_retain_replace(&heap,&plain_pair,bits,bits+1,0));
    assert(bits[0]==1 && bits[1]==2 && bits[2]==2 && bits[3]==4);
    assert(myl_rc_native_retain_replace(&heap,&plain_pair,bits,bits,~0u));
    assert(!myl_rc_native_retain_replace(&heap,&plain_pair,bits+2,bits,1));
    assert(bits[2]==2 && bits[3]==4 && myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR);
    assert(myl_native_region_begin(&heap));
    assert(myl_rc_native_retain_replace(&heap,&plain_pair,bits+2,bits,1));
    assert(bits[2]==1 && bits[3]==2);
    myl_native_region_end(&heap);
    unsigned char source[256], destination[256];
    for (size_t i=0;i<sizeof source;i++) source[i]=(unsigned char)i;
    size_t bytes=heap.bytes, allocations=heap.allocations;
    heap.limit=bytes;
    assert(myl_rc_native_retain_replace(&heap,&wide,destination,source,0));
    assert(!memcmp(source,destination,sizeof source) && heap.bytes==bytes && heap.allocations==allocations);
    static const myl_native_type cold={.size=16,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    memset(destination,0x5a,sizeof destination);
    assert(!myl_rc_native_retain_replace(&heap,&cold,destination,source,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    for (size_t i=0;i<sizeof destination;i++) assert(destination[i]==0x5a);
    finish(&heap);
}
static uint64_t *plain_callback_source;
static void replace_source_finalizer(myl_native_heap *heap, void *payload) {
    (void)heap; (void)payload;
    plain_callback_source[0]=99;
}
/* spec-case: RC-PLAIN-REPLACE-1. A queued finalizer can alter the original source;
 * retain replacement must stage its bits before draining that callback. */
static void plain_replace_pending_death(void) {
    static const myl_native_type finalized={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_descriptor descriptor={.type=&finalized,.shape=&flat_scalar,.finalize=replace_source_finalizer};
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&plain_pair,&plain_pair_shape)==0);
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    assert(((const myl_rc_binding *)myl_rc_descriptor_find(&heap,&finalized))->flat.count>MYL_RC_FLAT_LEAVES);
    void *queued=myl_native_heap_alloc(&heap,&finalized,1);
    assert(queued);
    uint64_t source[]={7,8}, target[]={1,2};
    plain_callback_source=source;
    heap.rc->dead.active=1;
    myl_rc_owner_release(&heap,queued);
    heap.rc->dead.active=0;
    assert(heap.rc->dead.head);
    assert(myl_rc_native_retain_replace(&heap,&plain_pair,target,source,0));
    assert(source[0]==99 && source[1]==8 && target[0]==7 && target[1]==8);
    assert(!heap.rc->dead.head);
    plain_callback_source=NULL;
    finish(&heap);
}
/* spec-case: RC-PLAIN-REPLACE-1. Held tokens remain H and counted-shape NONE
 * cannot grant copying of a raw resource hidden in an inline record. */
static void plain_replace_excludes_ownership(void) {
    static const myl_rc_shape held_shape={.size=8,.kind=MYL_RC_SHAPE_HOLD_POINTER};
    static const myl_native_type held_type={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER};
    static const myl_native_type resource={.size=8,.alignment=8,.kind=MYL_NATIVE_RESOURCE};
    static const myl_native_field fields[]={{.type=&resource},{.offset=8,.type=&number}};
    static const myl_native_type unique={.size=16,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=fields,.field_count=2};
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&held_type,&held_shape)>MYL_RC_FLAT_LEAVES);
    assert(flat_count(&heap,&unique,&plain_pair_shape)>MYL_RC_FLAT_LEAVES);
    void *source=myl_rc_storage_bytes(&heap,8,0), *target=myl_rc_storage_bytes(&heap,8,0);
    myl_rc_hold source_hold={0}, target_hold={0};
    assert(myl_rc_hold_acquire(&heap,source,&source_hold)==MYL_RC_OK);
    assert(myl_rc_hold_acquire(&heap,target,&target_hold)==MYL_RC_OK);
    myl_rc_owner_release(&heap,source);
    myl_rc_owner_release(&heap,target);
    assert(myl_rc_native_retain_replace(&heap,&held_type,&target_hold.payload,&source_hold.payload,0));
    assert(target_hold.payload==source && owners(source)==0 && ((myl_rc_object *)source-1)->holds==2);
    myl_rc_hold_release(&heap,&target_hold);
    myl_rc_hold_release(&heap,&source_hold);
    pid_t child=fork();
    assert(child>=0);
    if (!child) {
        struct rlimit no_core={0,0};
        assert(!setrlimit(RLIMIT_CORE,&no_core));
        uint64_t input[]={123,456}, output[2]={0};
        (void)myl_rc_native_retain_replace(&heap,&unique,output,input,0);
        _exit(0);
    }
    int status=0;
    assert(waitpid(child,&status,0)==child && WIFSIGNALED(status) && WTERMSIG(status)==SIGABRT);
    finish(&heap);
}
/* spec-case: RC-PLAIN-RETAIN-1. Adjacent slots in either direction are disjoint;
 * region refusal clears only the output, including an overlapping refusal. */
static void plain_retain_regions(void) {
    static const myl_native_field wide_field={.type=&plain_pair};
    static const myl_native_type wide={.size=256,.alignment=8,.kind=MYL_NATIVE_ARRAY,
        .fields=&wide_field,.field_count=1,.element=&plain_pair,.count=16,.stride=16};
    static const myl_rc_shape wide_shape={.size=256,.kind=MYL_RC_SHAPE_ARRAY,
        .as.array={.element=&plain_pair_shape,.count=16,.stride=16}};
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&plain_pair,&plain_pair_shape)==0);
    assert(flat_count(&heap,&wide,&wide_shape)==0);
    uint64_t bits[]={7,8,0,0};
    assert(myl_rc_native_retain(&heap,&plain_pair,bits+2,bits,0));
    assert(bits[0]==7 && bits[1]==8 && bits[2]==7 && bits[3]==8);
    bits[0]=bits[1]=0;
    assert(myl_rc_native_retain(&heap,&plain_pair,bits,bits+2,0));
    assert(bits[0]==7 && bits[1]==8 && bits[2]==7 && bits[3]==8);
    assert(!myl_rc_native_retain(&heap,&plain_pair,bits+2,bits,1));
    assert(bits[0]==7 && bits[1]==8 && !bits[2] && !bits[3]);
    assert(myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR);
    assert(!myl_rc_native_retain(&heap,&plain_pair,bits+1,bits,1));
    assert(bits[0]==7 && !bits[1] && !bits[2] && !bits[3]);
    assert(myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR);
    assert(myl_native_region_begin(&heap));
    assert(myl_rc_native_retain(&heap,&plain_pair,bits+2,bits,1));
    assert(bits[2]==7 && !bits[3]);
    myl_native_region_end(&heap);
    unsigned char source[256], target[256];
    for (size_t i=0;i<sizeof source;i++) source[i]=(unsigned char)i;
    size_t bytes=heap.bytes, allocations=heap.allocations;
    heap.limit=bytes;
    assert(myl_rc_native_retain(&heap,&wide,target,source,0));
    assert(!memcmp(source,target,sizeof source) && heap.bytes==bytes && heap.allocations==allocations);
    static const myl_native_type cold={.size=16,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    memset(target,0x5a,sizeof target);
    assert(!myl_rc_native_retain(&heap,&cold,target,source,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    for (size_t i=0;i<sizeof target;i++) assert(target[i]==(i<16?0:0x5a));
    finish(&heap);
}
/* spec-case: RC-PLAIN-RETAIN-1. Empty layouts keep region validation without
 * touching neighboring bytes; a same-address retain remains an invariant. */
static void plain_retain_empty_and_alias(void) {
    static const myl_native_type empty={.alignment=1,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_shape empty_shape={.kind=MYL_RC_SHAPE_NONE};
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&empty,&empty_shape)==0);
    assert(flat_count(&heap,&plain_pair,&plain_pair_shape)==0);
    uint64_t source=7, target=8;
    assert(myl_rc_native_retain(&heap,&empty,&target,&source,0));
    assert(source==7 && target==8);
    assert(!myl_rc_native_retain(&heap,&empty,&target,&source,1));
    assert(source==7 && target==8 && myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR);
    pid_t child=fork();
    assert(child>=0);
    if (!child) {
        struct rlimit no_core={0,0};
        assert(!setrlimit(RLIMIT_CORE,&no_core));
        uint64_t bits[]={7,8};
        (void)myl_rc_native_retain(&heap,&plain_pair,bits,bits,0);
        _exit(0);
    }
    int status=0;
    assert(waitpid(child,&status,0)==child && WIFSIGNALED(status) && WTERMSIG(status)==SIGABRT);
    finish(&heap);
}
/* spec-case: RC-PLAIN-RETAIN-1. The original copy completes before a queued
 * finalizer mutates its source; admission cannot remove this drain boundary. */
static void plain_retain_pending_death(void) {
    static const myl_native_type finalized={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_descriptor descriptor={.type=&finalized,.shape=&flat_scalar,.finalize=replace_source_finalizer};
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&plain_pair,&plain_pair_shape)==0);
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    assert(((const myl_rc_binding *)myl_rc_descriptor_find(&heap,&finalized))->flat.count>MYL_RC_FLAT_LEAVES);
    void *queued=myl_native_heap_alloc(&heap,&finalized,1);
    assert(queued);
    uint64_t source[]={7,8}, target[2]={0};
    plain_callback_source=source;
    heap.rc->dead.active=1;
    myl_rc_owner_release(&heap,queued);
    heap.rc->dead.active=0;
    assert(heap.rc->dead.head);
    assert(myl_rc_native_retain(&heap,&plain_pair,target,source,0));
    assert(source[0]==99 && source[1]==8 && target[0]==7 && target[1]==8 && !heap.rc->dead.head);
    plain_callback_source=NULL;
    finish(&heap);
}
/* spec-case: RC-PLAIN-RETAIN-1. Physical managed and held tokens keep their
 * distinct counters and transactional count-limit refusal with empty output. */
static void plain_retain_excludes_tokens(void) {
    static const myl_rc_shape held_shape={.size=8,.kind=MYL_RC_SHAPE_HOLD_POINTER};
    static const myl_native_type held_type={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER};
    myl_native_heap heap;
    init(&heap);
    assert(flat_count(&heap,&pointer,&flat_pointer)==1);
    assert(flat_count(&heap,&held_type,&held_shape)>MYL_RC_FLAT_LEAVES);
    void *source=myl_rc_storage_bytes(&heap,8,0), *target=NULL;
    assert(source);
    myl_rc_object *object=(myl_rc_object *)source-1;
    object->owners=MYL_RC_COUNT_MAX;
    target=(void *)(uintptr_t)0xfeed;
    assert(!myl_rc_native_retain(&heap,&pointer,&target,&source,0));
    assert(!target && object->owners==MYL_RC_COUNT_MAX && myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    object->owners=1;
    myl_rc_hold source_hold={0}, target_hold={0};
    assert(myl_rc_hold_acquire(&heap,source,&source_hold)==MYL_RC_OK);
    myl_rc_owner_release(&heap,source);
    assert(myl_rc_native_retain(&heap,&held_type,&target_hold.payload,&source_hold.payload,0));
    assert(target_hold.payload==source && !owners(source) && object->holds==2);
    myl_rc_hold_release(&heap,&target_hold);
    object->holds=MYL_RC_COUNT_MAX;
    target=(void *)(uintptr_t)0xfeed;
    assert(!myl_rc_native_retain(&heap,&held_type,&target,&source_hold.payload,0));
    assert(!target && object->holds==MYL_RC_COUNT_MAX && myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    object->holds=1;
    myl_rc_hold_release(&heap,&source_hold);
    finish(&heap);
}
/* spec-case: RC-PLAIN-READY-NESTED-1. Both callable aliases answer the same
 * refusal/success without admitting a different binding or queued callback. */
static int same_plain_ready(myl_native_heap *heap, const myl_native_list *list) {
    int ordinary=myl_rc_list_plain_ready(heap,list);
    assert(ordinary==myl_rc_list_plain_ready_hot(heap,list));
    return ordinary;
}
/* spec-case: RC-PLAIN-POP-1.
 * spec-case: RC-PLAIN-APPEND-1. Admission neither registers cold metadata nor
 * allocates, and excludes empty/aggregate/managed/held/unique/finalized types. */
static void plain_append_admission(void) {
    static const myl_native_type scalar[]={
        {.size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN},
        {.size=2,.alignment=2,.kind=MYL_NATIVE_PLAIN},
        {.size=4,.alignment=4,.kind=MYL_NATIVE_PLAIN},
        {.size=8,.alignment=8,.kind=MYL_NATIVE_FLOAT}
    };
    static const myl_native_type empty={.alignment=1,.kind=MYL_NATIVE_PLAIN};
    static const myl_native_type held={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER};
    static const myl_native_type unique={.size=8,.alignment=8,.kind=MYL_NATIVE_RESOURCE};
    static const myl_native_type finalized={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_shape held_shape={.size=8,.kind=MYL_RC_SHAPE_HOLD_POINTER};
    static const myl_rc_descriptor final_descriptor={.type=&finalized,.shape=&flat_scalar,.finalize=replace_source_finalizer};
    myl_native_heap heap;
    init(&heap);
    myl_native_list probe={0};
    assert(!same_plain_ready(NULL,&probe) && !same_plain_ready(&heap,NULL));
    assert(!myl_rc_list_plain_pop_ready(NULL,&probe) && !myl_rc_list_plain_pop_ready(&heap,NULL));
    for (size_t i=0;i<4;i++) {
        probe.element=&scalar[i];
        size_t bytes=heap.bytes, allocations=heap.allocations;
        assert(!same_plain_ready(&heap,&probe));
        assert(!myl_rc_list_plain_pop_ready(&heap,&probe));
        assert(!myl_rc_descriptor_find(&heap,probe.element));
        assert(heap.bytes==bytes && heap.allocations==allocations);
        myl_native_list *list=myl_native_list_new(&heap,probe.element,4);
        assert(list && same_plain_ready(&heap,list));
        assert(myl_rc_list_plain_pop_ready(&heap,list));
        myl_rc_owner_release(&heap,list);
    }
    assert(flat_count(&heap,&plain_pair,&plain_pair_shape)==0);
    assert(flat_count(&heap,&held,&held_shape)>MYL_RC_FLAT_LEAVES);
    assert(myl_rc_descriptor_import(&heap,&final_descriptor)==MYL_RC_OK);
    const myl_native_type *refused[]={&empty,&plain_pair,&pointer,&held,&unique,&finalized};
    for (size_t i=0;i<sizeof refused/sizeof refused[0];i++) {
        probe.element=refused[i];
        assert(!same_plain_ready(&heap,&probe));
        assert(myl_rc_list_plain_pop_ready(&heap,&probe)==(refused[i]==&plain_pair));
    }
    finish(&heap);
}
static myl_native_list *append_observed;
static void append_observer(myl_native_heap *heap, void *payload) {
    (void)heap; (void)payload;
    assert(append_observed->length==1 && append_observed->generation==1);
    *(uint64_t *)append_observed->storage=99;
}
/* spec-case: RC-PLAIN-APPEND-1. A queued finalizer observes the old length;
 * generic append stages an aliased scalar before the callback changes it. */
static void plain_append_pending_death(void) {
    static const myl_native_type finalized={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_descriptor descriptor={.type=&finalized,.shape=&flat_scalar,.finalize=append_observer};
    myl_native_heap heap;
    init(&heap);
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    myl_native_list *list=myl_native_list_new(&heap,&number,4);
    uint64_t value=7;
    assert(list && myl_rc_list_append(&heap,list,&value));
    void *queued=myl_native_heap_alloc(&heap,&finalized,1);
    assert(queued);
    assert(same_plain_ready(&heap,list)); /* Warm identity before queueing. */
    assert(myl_rc_list_plain_pop_ready(&heap,list));
    append_observed=list;
    heap.rc->dead.active=1;
    myl_rc_owner_release(&heap,queued);
    heap.rc->dead.active=0;
    assert(heap.rc->dead.head && !same_plain_ready(&heap,list));
    assert(!myl_rc_list_plain_pop_ready(&heap,list));
    assert(list->length==1 && *(uint64_t *)list->storage==7 && heap.rc->dead.head);
    assert(myl_rc_list_append(&heap,list,list->storage));
    assert(list->length==2 && list->generation==2 && !heap.rc->dead.head);
    assert(((uint64_t *)list->storage)[0]==99 && ((uint64_t *)list->storage)[1]==7);
    assert(same_plain_ready(&heap,list));
    append_observed=NULL;
    myl_rc_owner_release(&heap,list);
    finish(&heap);
}
/* spec-case: RC-PLAIN-APPEND-1. Full capacity and generation overflow keep the
 * original helper. Aliased growth and an older receiver in an arena preserve
 * the element bits, receiver region and unchanged state on budget refusal. */
static void plain_append_fallback(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_list *list=myl_native_list_new(&heap,&number,1);
    uint64_t value=7;
    assert(list && myl_rc_list_append(&heap,list,&value));
    assert(same_plain_ready(&heap,list));
    assert(myl_native_region_begin(&heap));
    assert(myl_rc_list_append(&heap,list,list->storage));
    assert(list->length==2 && !myl_native_header_region(list->storage));
    assert(((uint64_t *)list->storage)[0]==7 && ((uint64_t *)list->storage)[1]==7);
    myl_native_region_end(&heap);
    list->generation=UINT64_MAX;
    assert(!myl_rc_list_append(&heap,list,&value) && list->length==2 && list->generation==UINT64_MAX);
    list->generation=2;
    myl_rc_owner_release(&heap,list);
    list=myl_native_list_new(&heap,&number,1024);
    assert(list);
    while (list->length<list->capacity) assert(myl_rc_list_append(&heap,list,&value));
    size_t length=list->length, generation=list->generation;
    void *storage=list->storage;
    heap.limit=1;
    assert(!myl_rc_list_append(&heap,list,&value));
    assert(list->length==length && list->generation==generation && list->storage==storage);
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    myl_rc_owner_release(&heap,list);
    finish(&heap);
}

/* spec-case: RC-DICTIONARY-WORD-1. A hit captures all source bytes before the
 * store, including unaligned and overlapping ranges in its own live backing. */
static void dictionary_word_overlap(void) {
    myl_native_heap heap;
    init(&heap);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&number,0);
    uint64_t key=1, other=2, value=0x123456789abcdef0, output;
    assert(dict && myl_native_dictionary_write(&heap,dict,&key,&value));
    assert(myl_native_dictionary_write(&heap,dict,&other,&other));
    unsigned char *slot=(unsigned char *)dict->entries->storage+dict->value_offset;
    unsigned char *second=slot+dict->entry_type.size;
    size_t bytes=heap.bytes, allocations=heap.allocations;
    uint64_t generation=dict->entries->generation;
    heap.limit=bytes;
    const void *sources[]={slot,slot-1,slot+1,second};
    for (size_t i=0;i<sizeof sources/sizeof sources[0];i++) {
        memcpy(&value,sources[i],8);
        assert(myl_native_dictionary_write(&heap,dict,&key,sources[i]));
        assert(myl_native_dictionary_read(dict,&key,&output) && output==value);
        assert(myl_native_dictionary_read(dict,&other,&output) && output==other);
    }
    assert(myl_native_dictionary_length(dict)==2 && dict->entries->generation==generation);
    assert(heap.bytes==bytes && heap.allocations==allocations);
    myl_rc_record_failure(&heap,MYL_RC_COUNT_LIMIT);
    assert(myl_native_dictionary_write(&heap,dict,&key,&value));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT);
    myl_rc_owner_release(&heap,dict);
    finish(&heap);
}
/* spec-case: RC-DICTIONARY-WORD-1. Actual destination regions remain checked;
 * same-address replacement keeps its earlier no-op even in injected bad state. */
static void dictionary_word_regions(void) {
    myl_native_heap heap;
    init(&heap);
    uint64_t key=1, value=7, output=0;
    myl_native_dictionary *older=myl_native_dictionary_new(&heap,&number,&number,0);
    assert(older && myl_native_dictionary_write(&heap,older,&key,&value));
    assert(myl_native_region_begin(&heap));
    myl_native_dictionary *inner=myl_native_dictionary_new(&heap,&number,&number,0);
    assert(inner && myl_native_dictionary_write(&heap,inner,&key,&value));
    value=13;
    assert(myl_native_dictionary_write(&heap,older,&key,&value));
    assert(myl_native_dictionary_write(&heap,inner,&key,&value));
    assert(!myl_native_header_region(older) && myl_native_header_region(inner)==1);
    void *slot=(unsigned char *)inner->entries->storage+inner->value_offset;
    heap.region_depth=0; /* Fault injection, restored before arena teardown. */
    assert(myl_native_dictionary_write(&heap,inner,&key,slot));
    assert(myl_rc_take_failure(&heap)==MYL_RC_OK);
    value=99;
    assert(!myl_native_dictionary_write(&heap,inner,&key,&value));
    assert(myl_rc_take_failure(&heap)==MYL_RC_REGION_ERROR && value==99);
    assert(myl_native_dictionary_read(inner,&key,&output) && output==13);
    heap.region_depth=1;
    assert(myl_native_dictionary_write(&heap,inner,&key,&value));
    myl_native_region_end(&heap);
    assert(myl_native_dictionary_read(older,&key,&output) && output==13);
    myl_rc_owner_release(&heap,older);
    finish(&heap);
}
static myl_native_dictionary *word_observed, *word_reentrant;
static uint64_t word_source, word_phase;
static myl_native_type word_registered[96];
static void dictionary_word_observer(myl_native_heap *heap, void *payload) {
    uint64_t id=*(uint64_t *)payload, key=1, output=0, value=17;
    assert(myl_native_dictionary_read(word_observed,&key,&output) && output==3);
    assert(++word_phase==id);
    if (id==2) return;
    word_source=99;
    size_t capacity=heap->rc->metadata.bindings.mask;
    for (size_t i=0;i<96;i++) {
        word_registered[i]=(myl_native_type){.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
        assert(myl_rc_native_shape(heap,&word_registered[i]));
    }
    assert(heap->rc->metadata.bindings.mask>capacity);
    /* The sibling is queued, but an active outer drain defers it across this
     * nested dictionary replacement and unrelated backing growth. */
    assert(heap->rc->dead.head && heap->rc->dead.active);
    assert(myl_native_dictionary_write(heap,word_reentrant,&key,&value));
    for (key=2;key<64;key++) assert(myl_native_dictionary_write(heap,word_reentrant,&key,&value));
    assert(word_phase==1 && heap->rc->dead.head);
}
/* spec-case: RC-DICTIONARY-WORD-1. Queued callbacks see old destination bytes;
 * publication uses the pre-callback source despite reentrant metadata growth. */
static void dictionary_word_queue(void) {
    static const myl_native_type finalized={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_descriptor descriptor={.type=&finalized,.shape=&flat_scalar,.finalize=dictionary_word_observer};
    myl_native_heap heap;
    init(&heap);
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    word_observed=myl_native_dictionary_new(&heap,&number,&number,0);
    word_reentrant=myl_native_dictionary_new(&heap,&number,&number,0);
    uint64_t key=1, old=3, output=0;
    assert(word_observed && word_reentrant);
    assert(myl_native_dictionary_write(&heap,word_observed,&key,&old));
    assert(myl_native_dictionary_write(&heap,word_reentrant,&key,&old));
    assert(myl_native_dictionary_write(&heap,word_observed,&key,&old)); /* Warm hit before queueing. */
    uint64_t *first=myl_native_heap_alloc(&heap,&finalized,1);
    uint64_t *second=myl_native_heap_alloc(&heap,&finalized,1);
    assert(first && second);
    *first=1; *second=2;
    word_source=7; word_phase=0;
    heap.rc->dead.active=1;
    myl_rc_owner_release(&heap,second);
    myl_rc_owner_release(&heap,first); /* The death worklist is LIFO. */
    heap.rc->dead.active=0;
    void *slot=(unsigned char *)word_observed->entries->storage+word_observed->value_offset;
    assert(heap.rc->dead.head && myl_native_dictionary_write(&heap,word_observed,&key,slot));
    assert(!word_phase && heap.rc->dead.head);
    assert(myl_native_dictionary_write(&heap,word_observed,&key,&word_source));
    assert(word_phase==2 && word_source==99 && !heap.rc->dead.head);
    assert(myl_native_dictionary_read(word_observed,&key,&output) && output==7);
    assert(myl_native_dictionary_write(&heap,word_observed,&key,&word_source));
    assert(myl_native_dictionary_read(word_observed,&key,&output) && output==99);
    myl_rc_owner_release(&heap,word_reentrant);
    myl_rc_owner_release(&heap,word_observed);
    word_reentrant=NULL; word_observed=NULL;
    finish(&heap);
}
/* spec-case: RC-DICTIONARY-WORD-1. Native kind/width alone cannot bypass a
 * registered ownership shape; other plain widths/records keep full copies. */
static void dictionary_word_fallback(void) {
    static const myl_native_type opaque={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_rc_descriptor descriptor={.type=&opaque,.shape=&flat_pointer};
    static const myl_native_type widths[]={
        {.size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN},
        {.size=2,.alignment=2,.kind=MYL_NATIVE_PLAIN},
        {.size=4,.alignment=4,.kind=MYL_NATIVE_PLAIN},
        {.size=8,.alignment=8,.kind=MYL_NATIVE_FLOAT}
    };
    myl_native_heap heap;
    init(&heap);
    assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    assert(((const myl_rc_binding *)myl_rc_descriptor_find(&heap,&opaque))->flat.count>MYL_RC_FLAT_LEAVES);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&opaque,0);
    void *first=myl_rc_storage_bytes(&heap,8,0), *second=myl_rc_storage_bytes(&heap,8,0), *output=NULL;
    uint64_t key=1;
    assert(dict && first && second && myl_native_dictionary_write(&heap,dict,&key,&first));
    ((myl_rc_object *)second-1)->owners=MYL_RC_COUNT_MAX;
    assert(!myl_native_dictionary_write(&heap,dict,&key,&second));
    assert(myl_rc_take_failure(&heap)==MYL_RC_COUNT_LIMIT && owners(first)==2);
    assert(myl_native_dictionary_read(dict,&key,&output) && output==first);
    ((myl_rc_object *)second-1)->owners=1;
    assert(myl_native_dictionary_write(&heap,dict,&key,&second));
    assert(owners(first)==1 && owners(second)==2);
    myl_rc_owner_release(&heap,dict);
    myl_rc_owner_release(&heap,first);
    myl_rc_owner_release(&heap,second);
    assert(flat_count(&heap,&plain_pair,&plain_pair_shape)==0);
    const myl_native_type *types[]={&widths[0],&widths[1],&widths[2],&widths[3],&plain_pair};
    for (size_t i=0;i<sizeof types/sizeof types[0];i++) {
        uint64_t source[]={7,8}, old[]={1,2}, result[2]={0};
        dict=myl_native_dictionary_new(&heap,&number,types[i],0);
        assert(dict && myl_native_dictionary_write(&heap,dict,&key,old));
        assert(myl_native_dictionary_write(&heap,dict,&key,source));
        assert(myl_native_dictionary_read(dict,&key,result) && !memcmp(source,result,types[i]->size));
        myl_rc_owner_release(&heap,dict);
    }
    finish(&heap);
}
/* spec-case: RC-DICTIONARY-WORD-1. Ordinary construction must establish the
 * exact value binding; cold admission keeps registration/budget failure. */
static void dictionary_word_registration(void) {
    static const myl_native_type cold={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    static const myl_native_type floating={.size=8,.alignment=8,.kind=MYL_NATIVE_FLOAT};
    myl_native_heap heap;
    init(&heap);
    assert(myl_rc_native_shape(&heap,&number));
    size_t bytes=heap.bytes;
    assert(!myl_rc_descriptor_repeat(&heap,&cold));
    heap.limit=bytes;
    assert(!myl_native_dictionary_new(&heap,&number,&cold,0));
    assert(myl_rc_take_failure(&heap)==MYL_RC_ALLOCATION_REFUSED);
    assert(!myl_rc_descriptor_find(&heap,&cold) && heap.bytes==bytes);
    heap.limit=0; heap.exhausted=0;
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&cold,0);
    uint64_t key=1, value=7, output=0;
    assert(dict && myl_rc_descriptor_repeat(&heap,&cold));
    assert(myl_native_dictionary_write(&heap,dict,&key,&value));
    value=13;
    assert(myl_native_dictionary_write(&heap,dict,&key,&value));
    assert(myl_native_dictionary_read(dict,&key,&output) && output==13);
    myl_native_list *list=myl_native_list_new(&heap,&floating,4);
    assert(list);
    for (value=14;value<18;value++) {
        assert(same_plain_ready(&heap,list));
        assert(myl_native_dictionary_write(&heap,dict,&key,&value));
        assert(same_plain_ready(&heap,list));
        assert(myl_native_dictionary_read(dict,&key,&output) && output==value);
    }
    myl_rc_owner_release(&heap,list);
    myl_rc_owner_release(&heap,dict);
    finish(&heap);
}

int myl_rc_collections_verify(void) {
    storage_reuse_and_holds();
    storage_boundaries();
    native_allocation_cache();
    native_allocation_budget();
    native_allocation_regions_and_counts();
    native_allocation_custom_hooks();
    list_edges_and_retired_backing();
    construction_refusal();
    dictionary_dead_edges();
    views_and_snapshots();
    pinned_pop_and_count_refusal();
    dictionary_probe_reuse();
    production_deep_and_wide();
    transforms_release_temporaries();
    sorting_and_partial_clone();
    dictionary_method_results();
    arena_construction_abort();
    deep_pinned_snapshot();
    pinned_sparse_dictionary();
    arena_snapshot_rollback();
    publication_refusal_output();
    arena_append_refusal();
    dictionary_publication_rollback();
    arena_edit_abort();
    pinned_dictionary_readers();
    arena_text_split_rollback();
    native_pointer_transactions();
    flat_array_transactions();
    flat_record_admission();
    flat_drop_order();
    flat_body_order();
    flat_single_body_order();
    plain_retain_replace();
    plain_replace_pending_death();
    plain_replace_excludes_ownership();
    plain_retain_regions();
    plain_retain_empty_and_alias();
    plain_retain_pending_death();
    plain_retain_excludes_tokens();
    plain_append_admission();
    plain_append_pending_death();
    plain_append_fallback();
    dictionary_word_overlap();
    dictionary_word_regions();
    dictionary_word_queue();
    dictionary_word_fallback();
    dictionary_word_registration();
    return 47;
}
#ifndef MYL_RC_COLLECTIONS_LIBRARY
int main(void) {
    assert(myl_rc_collections_verify()==47);
    puts("native RC collections: 47 passed");
    return 0;
}
#endif
