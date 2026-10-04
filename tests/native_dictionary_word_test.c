#include "native_dictionary.h"
#include "native_rc_dictionary.h"
#include "native_rc_internal.h"
#include "native_rc_stats.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const myl_native_type word={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type narrow={.size=4,.alignment=4,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type wide={.size=16,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_type text_pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=2};
enum { NONE, FOUND, ABSENT, FOUND_SPAN, ABSENT_SPAN };
static void init(myl_native_heap *heap,int rc) {
    myl_native_heap_init(heap,64u<<20);
    if (rc) assert(myl_rc_storage_init(heap)==MYL_RC_OK);
}
static void release(myl_native_heap *heap,void *object) {
    if (myl_rc_enabled(heap)) myl_rc_owner_release(heap,object);
}
static void finish(myl_native_heap *heap) {
    if (myl_rc_enabled(heap)) assert(!heap->objects_live);
    myl_native_heap_destroy(heap); assert(!heap->bytes);
}
static void same_probe(const myl_native_dictionary_probe *a,const myl_native_dictionary_probe *b) {
    assert(a->key==b->key && a->entry==b->entry && a->state==b->state);
    assert(a->slot==b->slot && a->hash==b->hash);
    assert(a->offset==b->offset && a->bytes==b->bytes && a->epoch==b->epoch);
}
/* The full ordinary API is the reference, from exactly the same initial probe.
 * Compare all output bytes (including the untouched suffix), every probe field
 * and allocation/collection effects, without normalizing either result. */
static void pair(myl_native_heap *heap,myl_native_dictionary *dict,const void *key,int found,const void *expected) {
    unsigned char ordinary[64],fast[64]; memset(ordinary,0xa5,sizeof ordinary); memset(fast,0xa5,sizeof fast);
    assert(dict->value->size<=sizeof ordinary);
    myl_native_dictionary_probe before=dict->last;
    size_t bytes=heap->bytes,allocations=heap->allocations,collections=heap->collections;
    myl_rc_counters counts_before={0},counts_after={0};
    int counted=myl_rc_stats_snapshot(heap,&counts_before);
    int status=myl_native_dictionary_read(dict,key,ordinary);
    myl_native_dictionary_probe after=dict->last; dict->last=before;
    assert(myl_native_dictionary_read_word(dict,key,fast)==status && status==found);
    assert(!memcmp(ordinary,fast,sizeof fast)); same_probe(&after,&dict->last);
    if (found) assert(!memcmp(fast,expected,dict->value->size));
    else { unsigned char untouched[64]; memset(untouched,0xa5,sizeof untouched); assert(!memcmp(fast,untouched,sizeof fast)); }
    assert(heap->bytes==bytes && heap->allocations==allocations && heap->collections==collections);
    assert(myl_rc_stats_snapshot(heap,&counts_after)==counted);
    assert(!memcmp(counts_before.events,counts_after.events,sizeof counts_before.events));
    assert(counts_before.saturated==counts_after.saturated);
}
/* spec-case: PY-DICT-4. Signed extremes are just key/value bits; found hints
 * must revalidate stored keys and bounds. Misses cannot change output. */
static void word_states(int rc) {
    myl_native_heap heap; init(&heap,rc);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&word,&word,0); assert(dict);
    myl_native_root root; myl_native_root_push(&heap,&root,&dict,&pointer);
    uint64_t keys[]={0,UINT64_MAX,UINT64_C(1)<<63,1},values[]={UINT64_MAX,0,17,UINT64_C(1)<<63},missing=3;
    pair(&heap,dict,&missing,0,NULL); assert(!dict->index.capacity);
    for (size_t i=0;i<4;i++) assert(myl_native_dictionary_write(&heap,dict,&keys[i],&values[i]));
    for (size_t i=0;i<4;i++) { pair(&heap,dict,&keys[i],1,&values[i]); pair(&heap,dict,&keys[i],1,&values[i]); }
    dict->last.entry=SIZE_MAX; pair(&heap,dict,&keys[3],1,&values[3]);
    dict->last.entry=0; pair(&heap,dict,&keys[3],1,&values[3]);
    pair(&heap,dict,&missing,0,NULL); assert(dict->last.state==ABSENT); pair(&heap,dict,&missing,0,NULL);
    for (unsigned state=NONE;state<=ABSENT_SPAN;state++) {
        dict->last=(myl_native_dictionary_probe){.state=state,.key=keys[0],.entry=0,.slot=0,.hash=0,.offset=SIZE_MAX,.bytes=9,.epoch=7};
        pair(&heap,dict,&keys[1],1,&values[1]);
    }
    uint64_t key=keys[2]; myl_native_dictionary_probe before=dict->last;
    assert(myl_native_dictionary_read(dict,&key,&key) && key==values[2]);
    myl_native_dictionary_probe after=dict->last; dict->last=before; key=keys[2];
    assert(myl_native_dictionary_read_word(dict,&key,&key) && key==values[2]); same_probe(&after,&dict->last);
    assert(myl_native_root_pop(&heap,&root)); release(&heap,dict); finish(&heap);
}
static void clear(myl_native_heap *heap,myl_native_dictionary *dict) {
    if (myl_rc_enabled(heap)) myl_rc_dictionary_clear(heap,dict); else myl_native_dictionary_clear(dict);
}
static size_t home(myl_native_heap *heap,myl_native_dictionary *dict,uint64_t key) {
    clear(heap,dict); assert(myl_native_dictionary_write(heap,dict,&key,&key));
    for (size_t i=0;i<dict->index.capacity;i++) if (dict->index.slots[i]) return i;
    assert(0); return 0;
}
/* spec-case: PY-DICT-4. Collision walks, borrowed aliases and detached clones
 * preserve values through overwrite, deletion, compaction and rebuilding. */
static void shared_collision(int rc) {
    myl_native_heap heap; init(&heap,rc);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&word,&word,0); assert(dict);
    myl_native_root roots[2]; myl_native_root_push(&heap,&roots[0],&dict,&pointer);
    size_t at=home(&heap,dict,0); uint64_t collider=0;
    for (uint64_t k=1;k<4096 && !collider;k++) if (home(&heap,dict,k)==at) collider=k;
    assert(collider); clear(&heap,dict);
    uint64_t zero=0,one=11,two=22,three=33,out=0;
    assert(myl_native_dictionary_write(&heap,dict,&zero,&one));
    assert(myl_native_dictionary_write(&heap,dict,&collider,&two));
    assert(dict->index.slots[at] && dict->index.slots[(at+1)&7]);
    pair(&heap,dict,&zero,1,&one); pair(&heap,dict,&collider,1,&two);
    myl_native_dictionary *copy=myl_native_dictionary_clone_at(&heap,dict,0); assert(copy);
    myl_native_root_push(&heap,&roots[1],&copy,&pointer); myl_native_dictionary *alias=dict;
    assert(myl_native_dictionary_overwrite(alias,&collider,&three));
    pair(&heap,dict,&collider,1,&three); pair(&heap,copy,&collider,1,&two);
    assert((rc?myl_rc_dictionary_pop(&heap,dict,&zero,&out):myl_native_dictionary_pop(dict,&zero,&out)) && out==one);
    myl_native_dictionary_settle(dict); pair(&heap,dict,&zero,0,NULL); pair(&heap,dict,&collider,1,&three);
    pair(&heap,copy,&zero,1,&one); myl_native_dictionary_reindex(&heap,dict); pair(&heap,dict,&collider,1,&three);
    assert(myl_native_dictionary_write(&heap,dict,&zero,&one)); pair(&heap,dict,&zero,1,&one);
    assert(myl_native_root_pop(&heap,&roots[1])); release(&heap,copy);
    assert(myl_native_root_pop(&heap,&roots[0])); release(&heap,dict); finish(&heap);
}
static void shape(myl_native_heap *heap,const myl_native_type *key_type,const myl_native_type *value_type,const void *key,const void *value,int text) {
    myl_native_dictionary *dict=myl_native_dictionary_new(heap,key_type,value_type,text); assert(dict);
    myl_native_root root; myl_native_root_push(heap,&root,&dict,&pointer);
    assert(myl_native_dictionary_write(heap,dict,key,value)); pair(heap,dict,key,1,value); pair(heap,dict,key,1,value);
    assert(myl_native_root_pop(heap,&root)); release(heap,dict);
}
/* spec-case: PY-DICT-4. Every unsupported key or value shape uses the ordinary
 * read, including structural words, managed references, spans and GC epochs. */
static void fallback_shapes(int rc) {
    myl_native_heap heap; init(&heap,rc); uint64_t key[2]={UINT64_MAX,3},value[2]={71,72};
    shape(&heap,&narrow,&word,key,value,0); shape(&heap,&wide,&word,key,value,0);
    shape(&heap,&word,&narrow,key,value,0); shape(&heap,&word,&wide,key,value,0);
    const myl_native_field field={.offset=0,.type=&word};
    const myl_native_type record={.size=8,.alignment=8,.kind=MYL_NATIVE_RECORD,.fields=&field,.field_count=1};
    if (rc) {
        const myl_rc_shape plain={.size=8,.kind=MYL_RC_SHAPE_NONE};
        const myl_rc_descriptor descriptor={.type=&record,.shape=&plain};
        assert(myl_rc_descriptor_import(&heap,&descriptor)==MYL_RC_OK);
    }
    shape(&heap,&record,&word,key,value,0); shape(&heap,&word,&record,key,value,0);
    myl_native_text *text=myl_native_text_from_utf8(&heap,(const unsigned char *)"abc",3); assert(text);
    myl_native_root root; myl_native_root_push(&heap,&root,&text,&pointer);
    shape(&heap,&word,&text_pointer,key,&text,0); shape(&heap,&text_pointer,&word,&text,value,1);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&text_pointer,&word,1); assert(dict);
    myl_native_root dict_root; myl_native_root_push(&heap,&dict_root,&dict,&pointer);
    assert(myl_native_dictionary_write(&heap,dict,&text,value));
    myl_native_text_span all={.offset=0,.bytes=3},absent={.offset=0,.bytes=2}; uint64_t out=0;
    assert(!myl_native_dictionary_read_range(&heap,dict,text,&absent,&out)); assert(dict->last.state==ABSENT_SPAN);
    pair(&heap,dict,&text,1,value); assert(myl_native_dictionary_read_range(&heap,dict,text,&all,&out) && out==value[0]);
    myl_native_heap_collect(&heap); pair(&heap,dict,&text,1,value);
    assert(myl_native_root_pop(&heap,&dict_root)); release(&heap,dict);
    assert(myl_native_root_pop(&heap,&root)); release(&heap,text); finish(&heap);
}
/* spec-case: PY-DICT-4. A real refused reindex leaves nonempty scan storage.
 * The word API must retain that fallback and allocate nothing at the ceiling. */
static void refused_scan(void) {
    myl_native_heap heap; init(&heap,0);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&word,&word,0); assert(dict);
    myl_native_root root; myl_native_root_push(&heap,&root,&dict,&pointer);
    uint64_t key=7,value=8,missing=9; assert(myl_native_dictionary_write(&heap,dict,&key,&value));
    heap.limit=1; myl_native_dictionary_reindex(&heap,dict); assert(!dict->index.capacity && dict->entries->length==1);
    pair(&heap,dict,&key,1,&value); pair(&heap,dict,&key,1,&value); pair(&heap,dict,&missing,0,NULL);
    assert(myl_native_root_pop(&heap,&root)); finish(&heap);
}
int main(void) {
    for (int rc=0;rc<2;rc++) { word_states(rc); shared_collision(rc); fallback_shapes(rc); }
    refused_scan(); puts("native dictionary word differential tests passed"); return 0;
}
