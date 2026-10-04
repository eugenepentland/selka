#include "native_dictionary.h"
#include "native_rc_dictionary.h"
#include "native_rc_internal.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_type text_pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=2};
/* Internal probe states, whose consumers must check state before other fields. */
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
    myl_native_heap_destroy(heap);
    assert(!heap->bytes);
}
static void clear(myl_native_heap *heap,myl_native_dictionary *dict) {
    if (myl_rc_enabled(heap)) myl_rc_dictionary_clear(heap,dict);
    else myl_native_dictionary_clear(dict);
}
static int pop(myl_native_heap *heap,myl_native_dictionary *dict,const void *key,void *out) {
    return myl_rc_enabled(heap)?myl_rc_dictionary_pop(heap,dict,key,out):myl_native_dictionary_pop(dict,key,out);
}
static void ignored(myl_native_dictionary_probe *probe) {
    probe->slot=0xdeadbeefu; probe->hash=0x13579bdfu;
    probe->offset=SIZE_MAX; probe->bytes=SIZE_MAX-1; probe->epoch=SIZE_MAX-2;
}
static void same_ignored(const myl_native_dictionary_probe *a,const myl_native_dictionary_probe *b) {
    assert(a->slot==b->slot && a->hash==b->hash);
    assert(a->offset==b->offset && a->bytes==b->bytes && a->epoch==b->epoch);
}
/* spec-case: PY-DICT-4. Stale absence fields cannot nominate an
 * insertion after an ordinary hit. Cached reads, aliases and independent clones
 * retain values through overwrite, deletion and physical entry compaction. */
static void scalar_states(int rc) {
    myl_native_heap heap; init(&heap,rc);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&number,0);
    assert(dict);
    myl_native_root roots[2]; myl_native_root_push(&heap,&roots[0],&dict,&pointer);
    int64_t key=INT64_MIN,missing=INT64_MAX,one=11,two=22,out=-1;
    assert(myl_native_dictionary_write(&heap,dict,&key,&one));
    ignored(&dict->last); dict->last.state=NONE;
    myl_native_dictionary_probe previous=dict->last;
    assert(myl_native_dictionary_read(dict,&key,&out) && out==one);
    assert(dict->last.state==FOUND && dict->last.key==(uint64_t)key);
    same_ignored(&previous,&dict->last);
    myl_native_dictionary *alias=dict;
    assert(myl_native_dictionary_read(alias,&key,&out) && out==one);
    assert(!myl_native_dictionary_read(dict,&missing,&out) && out==one);
    assert(dict->last.state==ABSENT);
    previous=dict->last;
    assert(myl_native_dictionary_read(dict,&key,&out) && out==one);
    same_ignored(&previous,&dict->last);
    assert(myl_native_dictionary_write(&heap,alias,&missing,&two));
    assert(myl_native_dictionary_read(dict,&missing,&out) && out==two);
    assert(myl_native_dictionary_length(dict)==2);
    myl_native_dictionary *copy=myl_native_dictionary_clone_at(&heap,dict,0);
    assert(copy); myl_native_root_push(&heap,&roots[1],&copy,&pointer);
    int64_t changed=99;
    assert(myl_native_dictionary_write(&heap,copy,&missing,&changed));
    assert(myl_native_dictionary_read(dict,&missing,&out) && out==two);
    assert(myl_native_dictionary_read(copy,&missing,&out) && out==changed);
    assert(pop(&heap,alias,&key,&out)==1 && out==one);
    myl_native_dictionary_settle(dict);
    assert(!myl_native_dictionary_contains(dict,&key));
    assert(myl_native_dictionary_read(dict,&missing,&out) && out==two);
    assert(myl_native_dictionary_read(copy,&key,&out) && out==one);
    assert(myl_native_root_pop(&heap,&roots[1])); release(&heap,copy);
    assert(myl_native_root_pop(&heap,&roots[0])); release(&heap,dict); finish(&heap);
}
static myl_native_text *text(myl_native_heap *heap,const char *value) {
    return myl_native_text_from_utf8(heap,(const unsigned char *)value,strlen(value));
}
/* spec-case: PY-DICT-4. A prior span's fields remain present after an
 * ordinary found publication but cannot answer a different query. Span absence
 * epochs and equal distinct text keys retain their existing meaning. */
static void span_states(int rc) {
    myl_native_heap heap; init(&heap,rc);
    myl_native_root roots[4];
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&text_pointer,&number,1);
    assert(dict); myl_native_root_push(&heap,&roots[0],&dict,&pointer);
    myl_native_text *whole=text(&heap,"whole abc"); assert(whole);
    myl_native_root_push(&heap,&roots[1],&whole,&pointer);
    myl_native_text *piece=text(&heap,"abc"); assert(piece);
    myl_native_root_push(&heap,&roots[2],&piece,&pointer);
    int64_t first=71,second=72,out=-1;
    assert(myl_native_dictionary_write(&heap,dict,&whole,&first));
    assert(myl_native_dictionary_write(&heap,dict,&piece,&second));
    myl_native_text_span suffix={.offset=6,.bytes=3},absent={.offset=0,.bytes=3};
    assert(myl_native_dictionary_read_range(&heap,dict,whole,&suffix,&out) && out==second);
    assert(dict->last.state==FOUND_SPAN);
    myl_native_dictionary_probe previous=dict->last;
    assert(myl_native_dictionary_read(dict,&whole,&out) && out==first);
    assert(dict->last.state==FOUND); same_ignored(&previous,&dict->last);
    assert(!myl_native_dictionary_read_range(&heap,dict,whole,&absent,&out) && out==first);
    assert(dict->last.state==ABSENT_SPAN && dict->last.epoch==heap.collections);
    previous=dict->last;
    assert(myl_native_dictionary_read(dict,&whole,&out) && out==first);
    same_ignored(&previous,&dict->last);
    assert(!myl_native_dictionary_contains_range(&heap,dict,whole,&absent));
    assert(myl_native_dictionary_read_range(&heap,dict,whole,&suffix,&out) && out==second);
    if (!rc) heap.stress=1;
    myl_native_text *equal=text(&heap,"abc"); assert(equal && equal!=piece);
    myl_native_root_push(&heap,&roots[3],&equal,&pointer);
    assert(myl_native_dictionary_read(dict,&equal,&out) && out==second);
    assert(myl_native_dictionary_overwrite_range(&heap,dict,whole,&absent,&first)==0);
    assert(myl_native_dictionary_read(dict,&whole,&out) && out==first);
    myl_native_heap_collect(&heap);
    assert(!myl_native_dictionary_read_range(&heap,dict,whole,&absent,&out));
    assert(myl_native_dictionary_read(dict,&piece,&out) && out==second);
    assert(myl_native_root_pop(&heap,&roots[3])); release(&heap,equal);
    assert(myl_native_root_pop(&heap,&roots[2])); release(&heap,piece);
    assert(myl_native_root_pop(&heap,&roots[1])); release(&heap,whole);
    assert(myl_native_root_pop(&heap,&roots[0])); release(&heap,dict); finish(&heap);
}
static size_t home(myl_native_heap *heap,myl_native_dictionary *dict,int64_t key) {
    clear(heap,dict);
    assert(myl_native_dictionary_write(heap,dict,&key,&key));
    for (size_t at=0;at<dict->index.capacity;at++) if (dict->index.slots[at]) return at;
    assert(0); return 0;
}
/* spec-case: PY-DICT-4. Two keys with the same table home cannot be
 * confused by a stale found nomination or an absent probe after deletion. */
static void collision_states(int rc) {
    myl_native_heap heap; init(&heap,rc);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&number,0); assert(dict);
    myl_native_root root; myl_native_root_push(&heap,&root,&dict,&pointer);
    size_t target=home(&heap,dict,0);
    int64_t collider=0;
    for (int64_t key=1;key<4096 && !collider;key++) if (home(&heap,dict,key)==target) collider=key;
    assert(collider && dict->index.capacity==8);
    clear(&heap,dict);
    int64_t zero=0,one=1,two=2,out=-1;
    assert(myl_native_dictionary_write(&heap,dict,&zero,&one));
    assert(myl_native_dictionary_write(&heap,dict,&collider,&two));
    assert(dict->index.slots[target] && dict->index.slots[(target+1)&7]);
    ignored(&dict->last); dict->last.state=NONE;
    myl_native_dictionary_probe previous=dict->last;
    assert(myl_native_dictionary_read(dict,&zero,&out) && out==one);
    same_ignored(&previous,&dict->last);
    assert(myl_native_dictionary_read(dict,&collider,&out) && out==two);
    assert(pop(&heap,dict,&zero,&out)==1 && out==one);
    assert(!myl_native_dictionary_contains(dict,&zero));
    assert(myl_native_dictionary_read(dict,&collider,&out) && out==two);
    assert(myl_native_dictionary_write(&heap,dict,&zero,&one));
    assert(myl_native_dictionary_read(dict,&zero,&out) && out==one);
    assert(myl_native_root_pop(&heap,&root)); release(&heap,dict); finish(&heap);
}
/* spec-case: PY-DICT-4. Real mandatory growth refusal preserves all
 * accepted entries and absent-output semantics, even when the index drops and
 * probes scan. Publishing found state allocates nothing at the memory ceiling. */
static void refusal_states(int rc) {
    myl_native_heap heap; init(&heap,rc);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&number,0); assert(dict);
    myl_native_root root; myl_native_root_push(&heap,&root,&dict,&pointer);
    int64_t key=0,value=10,out=-1;
    assert(myl_native_dictionary_write(&heap,dict,&key,&value));
    heap.limit=heap.bytes;
    int64_t accepted=1;
    while (accepted<16384) {
        value=accepted+10;
        if (!myl_native_dictionary_write(&heap,dict,&accepted,&value)) break;
        accepted++;
    }
    assert(accepted<16384 && myl_native_dictionary_length(dict)==(size_t)accepted);
    size_t bytes=heap.bytes,allocations=heap.allocations;
    for (key=0;key<accepted;key++) assert(myl_native_dictionary_read(dict,&key,&out) && out==key+10);
    assert(!myl_native_dictionary_read(dict,&accepted,&out) && out==accepted+9);
    key=0; assert(myl_native_dictionary_read(dict,&key,&out) && out==10);
    assert(heap.bytes==bytes && heap.allocations==allocations);
    assert(myl_native_root_pop(&heap,&root)); release(&heap,dict); finish(&heap);
}
int main(void) {
    for (int rc=0;rc<2;rc++) {
        scalar_states(rc); span_states(rc); collision_states(rc); refusal_states(rc);
    }
    puts("native dictionary probe state tests passed");
    return 0;
}
