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
/* spec-case: ARENA-MANAGED-11. An arena payload's depth and element come from
   the header in front of it. With the chunk list detached every lookup still
   answers, so no lookup walks the chunks however many the arena holds. */
static void header_regions(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,8u<<20);
    void *collected=myl_native_heap_alloc(&heap,&wide,1);
    assert(collected);
    assert(myl_native_region_begin(&heap));
    enum { count=4096 };
    static void *outer[count];
    for (size_t i=0;i<count;i++) {
        outer[i]=myl_native_heap_alloc(&heap,&wide,1);
        assert(outer[i]);
    }
    assert(myl_native_region_begin(&heap));
    void *inner=myl_native_heap_alloc(&heap,&octet,3);
    assert(inner && heap.arena.chunks_live>=3);
    myl_native_arena_chunk *chunks=heap.arena_chunks;
    heap.arena_chunks=NULL;
    for (size_t i=0;i<count;i++) {
        assert(myl_native_object_region(&heap,outer[i])==1);
        assert(myl_native_object_element(&heap,outer[i])==&wide);
        assert(!myl_native_object_immortal(&heap,outer[i]));
    }
    assert(myl_native_object_region(&heap,inner)==2 && myl_native_object_element(&heap,inner)==&octet);
    assert(myl_native_object_region(&heap,collected)==0 && myl_native_object_element(&heap,collected)==&wide);
    assert(myl_native_object_region(&heap,&frozen.value)==0 && myl_native_object_immortal(&heap,&frozen.value));
    assert(!myl_native_object_region(&heap,NULL) && !myl_native_object_element(&heap,NULL));
    heap.arena_chunks=chunks;
    myl_native_region_end(&heap);
    myl_native_region_end(&heap);
    assert(!heap.region_depth && heap.objects_live==1);
    myl_native_heap_destroy(&heap);
}
/* spec-case: ARENA-MANAGED-11. A container in the innermost arena accepts any
   value without walking it; an older container still refuses a younger value
   and accepts its own region's and older ones. */
static void barrier_by_header(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    myl_native_list *collected=myl_native_list_new(&heap,&number,0);
    assert(myl_native_region_begin(&heap));
    myl_native_list *older=myl_native_list_new(&heap,&number,0);
    assert(myl_native_region_begin(&heap));
    myl_native_list *younger=myl_native_list_new(&heap,&number,0);
    assert(collected && older && younger);
    assert(myl_native_region_check(&heap,younger,&integers,&younger));
    assert(myl_native_region_check(&heap,younger,&integers,&older));
    assert(myl_native_region_check(&heap,younger,&integers,&collected));
    assert(!myl_native_region_check(&heap,older,&integers,&younger));
    assert(myl_native_region_check(&heap,older,&integers,&older));
    assert(myl_native_region_check(&heap,older,&integers,&collected));
    assert(!myl_native_region_check(&heap,collected,&integers,&younger));
    assert(!myl_native_region_check(&heap,collected,&integers,&older));
    assert(myl_native_region_check(&heap,collected,&integers,&collected));
    myl_native_region_end(&heap);
    myl_native_region_end(&heap);
    myl_native_heap_destroy(&heap);
}
/* spec-case: ARENA-MANAGED-11. Collection scans every arena allocation through
   its header, so a collected object referenced only from the first and the last
   of thousands of arena slots — in different chunks — stays live. */
static void scan_across_chunks(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,8u<<20);
    assert(myl_native_region_begin(&heap));
    enum { count=3000 };
    static void **slots[count];
    for (size_t i=0;i<count;i++) {
        slots[i]=myl_native_heap_alloc(&heap,&pointer,1);
        assert(slots[i]);
    }
    assert(heap.arena.chunks_live>=2);
    int64_t *first=myl_native_heap_alloc_at(&heap,&number,1,0);
    int64_t *last=myl_native_heap_alloc_at(&heap,&number,1,0);
    assert(first && last && !myl_native_object_region(&heap,first));
    *first=11; *last=22;
    *slots[0]=first; *slots[count-1]=last;
    assert(myl_native_heap_alloc_at(&heap,&number,1,0));
    size_t live=heap.objects_live;
    heap.stress=1;
    myl_native_heap_collect(&heap);
    heap.stress=0;
    assert(heap.objects_live==live-1 && *first==11 && *last==22);
    myl_native_region_end(&heap);
    myl_native_heap_collect(&heap);
    assert(!heap.objects_live && !heap.bytes);
    myl_native_heap_destroy(&heap);
}
/* spec-case: ARENA-MANAGED-11. The header bounds an arena allocation's count
   and the nesting depth, and a tracing-heap count stays below the arena flag;
   past a bound the allocation or scope is refused, never truncated. */
static void header_bounds(void) {
    static const myl_native_type empty={.size=0,.alignment=1,.kind=MYL_NATIVE_PLAIN,.trace_mode=MYL_NATIVE_TRACE_NONE};
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    void *most=myl_native_heap_alloc(&heap,&empty,MYL_NATIVE_OBJECT_COUNT_MAX);
    assert(most && !myl_native_object_region(&heap,most) && myl_native_object_element(&heap,most)==&empty);
    assert(!myl_native_heap_alloc(&heap,&empty,MYL_NATIVE_OBJECT_COUNT_MAX+1));
    assert(myl_native_region_begin(&heap));
    void *widest=myl_native_heap_alloc(&heap,&empty,MYL_NATIVE_ARENA_COUNT_MAX);
    assert(widest && myl_native_object_region(&heap,widest)==1 && myl_native_object_element(&heap,widest)==&empty);
    assert(!myl_native_heap_alloc(&heap,&empty,MYL_NATIVE_ARENA_COUNT_MAX+1));
    assert(myl_native_heap_alloc(&heap,&wide,1));
    heap.stress=1;
    myl_native_heap_collect(&heap);
    heap.stress=0;
    myl_native_region_end(&heap);
    heap.region_depth=MYL_NATIVE_ARENA_REGION_MAX-1;
    assert(myl_native_region_begin(&heap) && heap.region_depth==MYL_NATIVE_ARENA_REGION_MAX);
    void *deepest=myl_native_heap_alloc(&heap,&wide,1);
    assert(deepest && myl_native_object_region(&heap,deepest)==MYL_NATIVE_ARENA_REGION_MAX);
    assert(!myl_native_region_begin(&heap) && heap.region_depth==MYL_NATIVE_ARENA_REGION_MAX);
    myl_native_region_end(&heap);
    heap.region_depth=0;
    myl_native_heap_destroy(&heap);
}
/* spec-case: QBE-INLINE-ALLOC-1. After a runtime allocation at the innermost
   depth the arena window is open on the chunk's free tail; an object bumped out
   of it the way generated code does is found by the collector's arena scan,
   carries its depth in its header, is released with the scope, and its bytes
   are zeroed before the chunk is reused. Opening a nested scope closes it. */
static void inline_arena_window(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,8u<<20);
    assert(myl_native_region_begin(&heap));
    assert(myl_native_heap_alloc(&heap,&pointer,1));
    assert(heap.arena_window.cursor && heap.arena_window.cursor<heap.arena_window.limit);
    assert(heap.arena_mark==(MYL_NATIVE_OBJECT_ARENA|((uintptr_t)1<<MYL_NATIVE_ARENA_REGION_SHIFT)|4));
    myl_native_object *bumped=(myl_native_object *)heap.arena_window.cursor;
    heap.arena_window.cursor+=32;
    bumped->mark=heap.arena_mark;
    bumped->element=&pointer;
    int64_t *kept=myl_native_heap_alloc_at(&heap,&number,1,0);
    assert(kept);
    *kept=5;
    *(int64_t **)(bumped+1)=kept;
    assert(myl_native_header_region(bumped+1)==1);
    myl_native_heap_collect(&heap);
    assert(!heap.arena_window.cursor && *kept==5 && !myl_native_object_region(&heap,kept));
    assert(myl_native_heap_alloc(&heap,&pointer,1) && heap.arena_window.cursor);
    assert(myl_native_region_begin(&heap));
    assert(!heap.arena_window.cursor);
    myl_native_region_end(&heap);
    myl_native_region_end(&heap);
    assert(!heap.arena_window.cursor);
    /* The released chunk comes back zeroed over what the window handed out. */
    assert(myl_native_region_begin(&heap));
    void **again=myl_native_heap_alloc(&heap,&pointer,1);
    assert(again && !*again && heap.arena.reused);
    assert(!((void **)heap.arena_window.cursor)[2]);
    myl_native_region_end(&heap);
    myl_native_heap_collect(&heap);
    assert(!heap.bytes);
    myl_native_heap_destroy(&heap);
}
int main(void) {
    inline_arena_window();
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
    header_regions();
    barrier_by_header();
    scan_across_chunks();
    header_bounds();
    return 0;
}
