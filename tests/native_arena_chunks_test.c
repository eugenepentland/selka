#include "native_heap.h"
#include "native_bytes.h"
#include "native_regions.h"
#include <assert.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>

static const myl_native_type octet={.size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN,.trace_mode=MYL_NATIVE_TRACE_NONE};
static const myl_native_type wide={.size=sizeof(max_align_t),.alignment=_Alignof(max_align_t),.kind=MYL_NATIVE_PLAIN,.trace_mode=MYL_NATIVE_TRACE_NONE};
typedef struct {
    myl_native_object header;
    myl_native_list value;
    myl_native_object storage_header;
    unsigned char storage[4];
} frozen_block;
static frozen_block frozen={
    .header={.mark=MYL_NATIVE_OBJECT_LITERAL_MARK},
    .value={.length=4,.capacity=4,.element=&octet,.storage=frozen.storage},
    .storage_header={.mark=MYL_NATIVE_OBJECT_LITERAL_MARK},
    .storage={'f','r','o','z'},
};
static void chunked_objects(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    assert(myl_native_region_begin(&heap));
    enum { count=1024 };
    void *items[count];
    size_t allocations=heap.allocations;
    for (size_t i=0;i<count;i++) {
        items[i]=myl_native_heap_alloc(&heap,&wide,1);
        assert(items[i] && (uintptr_t)items[i]%_Alignof(max_align_t)==0);
        assert(myl_native_object_region(&heap,items[i])==1);
        assert(myl_native_object_element(&heap,items[i])==&wide);
        assert(!myl_native_object_immortal(&heap,items[i]));
        for (size_t j=0;j<sizeof(max_align_t);j++) assert(((unsigned char *)items[i])[j]==0);
    }
    assert(heap.allocations-allocations==count);
    assert(heap.arena.allocations>=count);
    assert(heap.arena.chunks>0 && heap.arena.chunks<count);
    assert(heap.arena.chunks_live>0 && heap.arena.reserved_bytes>0);
    assert(heap.arena.peak_reserved_bytes>=heap.arena.reserved_bytes);
    size_t live=heap.objects_live,bytes=heap.bytes,chunks=heap.arena.chunks_live;
    myl_native_heap_release(&heap,items[0]);
    assert(heap.objects_live==live && heap.bytes==bytes && heap.arena.chunks_live==chunks);
    memset(items[0],0xa5,sizeof(max_align_t));
    myl_native_region_end(&heap);
    assert(!heap.region_depth && heap.objects_live==0 && heap.bytes==0);
    assert(!heap.arena.chunks_live && !heap.arena.reserved_bytes);
    myl_native_heap_destroy(&heap);
}
static void zero_and_validation(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,4096);
    assert(myl_native_region_begin(&heap));
    unsigned char *first=myl_native_heap_alloc(&heap,&octet,0);
    unsigned char *second=myl_native_heap_alloc(&heap,&octet,0);
    assert(first && second && first!=second && *first==0 && *second==0);
    myl_native_type invalid=octet;
    invalid.alignment=3;
    size_t allocations=heap.allocations;
    assert(!myl_native_heap_alloc(&heap,&invalid,1));
    invalid=octet; invalid.alignment=_Alignof(max_align_t)*2;
    assert(!myl_native_heap_alloc(&heap,&invalid,1));
    assert(!myl_native_heap_alloc(&heap,&wide,SIZE_MAX));
    assert(!myl_native_heap_alloc_at(&heap,&wide,1,heap.region_depth+1));
    assert(heap.allocations==allocations && heap.bytes<=heap.limit);
    while (myl_native_heap_alloc(&heap,&wide,1)) {}
    assert(heap.exhausted && heap.bytes<=heap.limit && heap.arena.chunks_live>0);
    myl_native_region_end(&heap);
    assert(heap.bytes==0 && heap.objects_live==0 && !heap.arena.chunks_live);
    heap.region_depth=UINT_MAX;
    assert(!myl_native_region_begin(&heap) && heap.region_depth==UINT_MAX);
    heap.region_depth=0;
    myl_native_heap_destroy(&heap);
}
static void nested_chunks(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    assert(myl_native_region_begin(&heap));
    uint64_t *outer=myl_native_heap_alloc(&heap,&(myl_native_type){.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN,.trace_mode=MYL_NATIVE_TRACE_NONE},1);
    assert(outer); *outer=91;
    myl_native_list *owner=myl_native_list_new(&heap,&octet,0);
    assert(owner && myl_native_object_region(&heap,owner)==1);
    size_t outer_live=heap.objects_live;
    assert(myl_native_region_begin(&heap));
    void *inner=myl_native_heap_alloc(&heap,&wide,1);
    assert(inner && myl_native_object_region(&heap,inner)==2);
    for (uint8_t i=0;i<64;i++) assert(myl_native_list_append(&heap,owner,&i));
    assert(myl_native_object_region(&heap,owner->storage)==1);
    myl_native_region_end(&heap);
    uint8_t last=0;
    assert(heap.region_depth==1 && heap.objects_live>outer_live && *outer==91);
    assert(myl_native_list_get(owner,63,&last) && last==63);
    myl_native_region_end(&heap);
    assert(!heap.region_depth && !heap.objects_live && !heap.bytes);
    myl_native_heap_destroy(&heap);
}
static void arena_byte_buffer(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    assert(myl_native_region_begin(&heap));
    myl_native_bytes *bytes=myl_native_bytes_new(&heap,(const unsigned char *)"ab",2);
    assert(bytes && myl_native_object_region(&heap,bytes)==1);
    assert(myl_native_bytes_buffer_append_byte(&heap,bytes,'c')==MYL_BYTES_WROTE);
    assert(bytes->length==3 && !memcmp(bytes->storage,"abc",3));
    myl_native_bytes *view=myl_native_bytes_view(&heap,bytes,1,3);
    assert(view && view->length==2 && !memcmp(view->storage,"bc",2));
    myl_native_region_end(&heap);
    assert(!heap.objects_live && !heap.bytes);
    myl_native_heap_destroy(&heap);
}
static void frozen_arena_views(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    assert(myl_native_object_immortal(&heap,&frozen.value));
    assert(myl_native_region_begin(&heap));
    assert(myl_native_bytes_buffer_append_byte(&heap,&frozen.value,'!')==MYL_BYTES_REFUSED);
    myl_native_bytes *view=myl_native_bytes_view(&heap,&frozen.value,1,4);
    myl_native_bytes *inner=myl_native_bytes_view(&heap,view,1,2);
    assert(view && inner && myl_native_object_region(&heap,view)==1);
    assert(view->length==3 && !memcmp(view->storage,"roz",3));
    assert(inner->length==1 && !memcmp(inner->storage,"o",1));
    heap.stress=1;
    myl_native_heap_collect(&heap);
    assert(inner->length==1 && !memcmp(inner->storage,"o",1));
    myl_native_region_end(&heap);
    assert(!heap.objects_live && !heap.bytes);
    myl_native_heap_destroy(&heap);
}
static void arena_views_retain_old_backing(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    myl_native_bytes *source=myl_native_bytes_new(&heap,(const unsigned char *)"older",5);
    assert(source);
    assert(myl_native_region_begin(&heap));
    myl_native_bytes *view=myl_native_bytes_view(&heap,source,1,5);
    myl_native_bytes *inner=myl_native_bytes_view(&heap,view,1,3);
    assert(view && inner);
    source=NULL; view=NULL;
    heap.stress=1;
    myl_native_heap_collect(&heap);
    assert(inner->length==2 && !memcmp(inner->storage,"de",2));
    myl_native_region_end(&heap);
    myl_native_heap_collect(&heap);
    assert(!heap.objects_live && !heap.bytes);
    myl_native_heap_destroy(&heap);
}
static void oversized_chunk(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,8u<<20);
    assert(myl_native_region_begin(&heap));
    unsigned char *large=myl_native_heap_alloc(&heap,&octet,2u<<20);
    assert(large && !large[0] && !large[(2u<<20)-1]);
    size_t reserved=heap.arena.reserved_bytes;
    assert(myl_native_heap_alloc(&heap,&wide,1));
    assert(heap.arena.reserved_bytes-reserved<=(1u<<20));
    myl_native_region_end(&heap);
    assert(!heap.bytes && !heap.objects_live);
    myl_native_heap_destroy(&heap);
}
/* spec-case: ARENA-MANAGED-10. The second scope serves its first allocation
   from the chunk the first scope released: same address, no new host
   reservation, and every byte the previous scope wrote reads back as zero. */
static void chunk_reuse_across_scopes(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    assert(myl_native_region_begin(&heap));
    unsigned char *first=myl_native_heap_alloc(&heap,&octet,64);
    assert(first && !heap.arena.reused);
    memset(first,0xa5,64);
    assert(myl_native_heap_alloc(&heap,&wide,1));
    uint64_t chunks=heap.arena.chunks;
    size_t reserved=heap.arena.reserved_bytes;
    myl_native_region_end(&heap);
    assert(heap.arena.cached==1 && heap.arena.cached_bytes==reserved);
    assert(!heap.bytes && !heap.arena.reserved_bytes && !heap.arena.chunks_live);
    assert(myl_native_region_begin(&heap));
    unsigned char *again=myl_native_heap_alloc(&heap,&octet,64);
    assert(again==first && heap.arena.chunks==chunks && heap.arena.reused==1);
    assert(!heap.arena.cached && !heap.arena.cached_bytes);
    for (size_t i=0;i<64;i++) assert(again[i]==0);
    assert(heap.bytes==reserved && heap.arena.reserved_bytes==reserved);
    assert(heap.arena.peak_reserved_bytes==reserved);
    myl_native_region_end(&heap);
    assert(heap.arena_cache);
    myl_native_heap_destroy(&heap);
}
/* spec-case: ARENA-MANAGED-10. Retention is bounded: six nested scopes release
   six chunks and the cache keeps at most four of them, under its byte bound. */
static void retention_bound(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,8u<<20);
    enum { depth=6 };
    for (unsigned i=0;i<depth;i++) {
        assert(myl_native_region_begin(&heap));
        assert(myl_native_heap_alloc(&heap,&wide,1));
    }
    assert(heap.arena.chunks_live==depth && !heap.arena.cached);
    for (unsigned i=0;i<depth;i++) myl_native_region_end(&heap);
    assert(heap.arena.cached==4 && heap.arena.cached_bytes<=(2u<<20));
    assert(!heap.bytes && !heap.arena.chunks_live && !heap.arena.reserved_bytes);
    myl_native_heap_destroy(&heap);
}
/* spec-case: ARENA-MANAGED-10. A reused chunk is charged to the budget exactly
   as a fresh reservation is, so a tiny budget still shrinks its chunk and still
   reports exhaustion rather than spending retained bytes. */
static void reuse_respects_budget(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,4096);
    assert(myl_native_region_begin(&heap));
    assert(myl_native_heap_alloc(&heap,&wide,1));
    size_t reserved=heap.arena.reserved_bytes;
    assert(reserved && reserved<=4096 && heap.bytes==reserved);
    myl_native_region_end(&heap);
    assert(heap.arena.cached==1 && heap.arena.cached_bytes==reserved && !heap.bytes);
    assert(myl_native_region_begin(&heap));
    assert(myl_native_heap_alloc(&heap,&wide,1));
    assert(heap.arena.reused==1 && !heap.arena.cached && !heap.arena.cached_bytes);
    assert(heap.bytes==reserved && heap.arena.reserved_bytes==reserved);
    while (myl_native_heap_alloc(&heap,&wide,1)) {}
    assert(heap.exhausted && heap.bytes<=heap.limit);
    myl_native_region_end(&heap);
    assert(!heap.bytes && !heap.objects_live);
    myl_native_heap_destroy(&heap);
}
/* spec-case: ARENA-MANAGED-10. A chunk released by an inner scope serves the
   next inner scope while the outer scope keeps its own chunk and its values. */
static void nested_scope_reuse(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    assert(myl_native_region_begin(&heap));
    uint64_t *outer=myl_native_heap_alloc(&heap,&(myl_native_type){.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN,.trace_mode=MYL_NATIVE_TRACE_NONE},1);
    assert(outer); *outer=55;
    assert(myl_native_region_begin(&heap));
    void *inner=myl_native_heap_alloc(&heap,&wide,1);
    assert(inner && myl_native_object_region(&heap,inner)==2);
    myl_native_region_end(&heap);
    assert(heap.arena.cached==1 && heap.arena.chunks_live==1);
    assert(myl_native_region_begin(&heap));
    void *again=myl_native_heap_alloc(&heap,&wide,1);
    assert(again==inner && heap.arena.reused==1 && myl_native_object_region(&heap,again)==2);
    assert(myl_native_object_region(&heap,outer)==1 && *outer==55);
    myl_native_region_end(&heap);
    myl_native_region_end(&heap);
    assert(!heap.region_depth && !heap.bytes && !heap.objects_live);
    myl_native_heap_destroy(&heap);
}
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type integers={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=1,.element=&number};
/* spec-case: ARENA-MANAGED-10. An escape copy lands in the enclosing region and
   survives the scope that produced it, and the released chunk is then reused. */
static void reuse_after_escape(void) {
    myl_native_heap heap;
    myl_native_root root;
    myl_native_heap_init(&heap,1<<20);
    assert(myl_native_region_begin(&heap));
    myl_native_list *source=myl_native_list_new(&heap,&number,0);
    assert(source);
    int64_t value=91;
    assert(myl_native_list_append(&heap,source,&value));
    myl_native_list *escaped=NULL;
    assert(myl_native_region_escape(&heap,&integers,&source,&escaped));
    myl_native_root_push(&heap,&root,&escaped,&pointer);
    assert(escaped && escaped!=source && !myl_native_object_region(&heap,escaped));
    void *chunk_head=source;
    myl_native_region_end(&heap);
    assert(heap.arena.cached==1);
    heap.stress=1;
    myl_native_heap_collect(&heap);
    int64_t read=0;
    assert(myl_native_list_get(escaped,0,&read) && read==91);
    heap.stress=0;
    assert(myl_native_region_begin(&heap));
    void *again=myl_native_heap_alloc(&heap,&octet,1);
    assert(again==chunk_head && heap.arena.reused==1 && !((unsigned char *)again)[0]);
    myl_native_region_end(&heap);
    assert(myl_native_root_pop(&heap,&root));
    myl_native_heap_destroy(&heap);
}
int main(void) {
    chunked_objects();
    zero_and_validation();
    nested_chunks();
    arena_byte_buffer();
    frozen_arena_views();
    oversized_chunk();
    arena_views_retain_old_backing();
    chunk_reuse_across_scopes();
    retention_bound();
    reuse_respects_budget();
    nested_scope_reuse();
    reuse_after_escape();
    return 0;
}
