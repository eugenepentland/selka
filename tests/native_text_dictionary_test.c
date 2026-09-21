#include "native_dictionary.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static myl_native_text *text(myl_native_heap *heap,const char *bytes) { return myl_native_text_from_utf8(heap,(const unsigned char *)bytes,strlen(bytes)); }
static void equals(myl_native_text *value,const char *bytes) {
    unsigned char buffer[128];
    size_t length=myl_native_text_utf8(value,buffer,sizeof(buffer));
    assert(length==strlen(bytes) && !memcmp(buffer,bytes,length));
}
/* A 16-byte key with interior padding, the shape a record key would have. */
typedef struct { int32_t tag; int64_t serial; } Wide;
static const myl_native_type wide={.size=sizeof(Wide),.alignment=_Alignof(Wide),.kind=MYL_NATIVE_PLAIN};
/* Every live slot names an entry that exists, no entry is named twice, none is
   left unnamed, and the load factor the writer promised still holds. */
static void index_sound(const myl_native_dictionary *dict) {
    if (!dict->index.capacity) return;
    assert(!(dict->index.capacity&(dict->index.capacity-1)));
    assert(dict->entries->length*8<=dict->index.capacity*5);
    size_t named=0;
    for (size_t at=0;at<dict->index.capacity;++at) {
        if (!dict->index.slots[at]) continue;
        assert(dict->index.slots[at]-1<dict->entries->length);
        named++;
        for (size_t other=at+1;other<dict->index.capacity;++other)
            assert(dict->index.slots[other]!=dict->index.slots[at]);
    }
    assert(named==dict->entries->length);
}
/* The slot a lone key lands in, read back from the table the writer filled. */
static size_t home(myl_native_heap *heap,myl_native_dictionary *dict,int64_t key) {
    int64_t value=key;
    myl_native_dictionary_clear(dict);
    assert(myl_native_dictionary_write(heap,dict,&key,&value));
    for (size_t at=0;at<dict->index.capacity;++at) if (dict->index.slots[at]) return at;
    assert(0);
    return 0;
}
/* spec-case: PY-DICT-2 -- growth, the rebuild after pop, and two keys built to
   share one home slot, which linear probing must keep telling apart. */
static void index_cases(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<26);
    myl_native_root root;
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&number,0); assert(dict);
    myl_native_root_push(&heap,&root,&dict,&pointer);
    int64_t out=0;
    for (int64_t i=0;i<4096;++i) {
        int64_t key=i*7919-1000,value=i;
        assert(myl_native_dictionary_write(&heap,dict,&key,&value));
    }
    index_sound(dict);
    assert(myl_native_dictionary_length(dict)==4096);
    for (int64_t i=0;i<4096;++i) {
        int64_t key=i*7919-1000;
        assert(myl_native_dictionary_read(dict,&key,&out) && out==i);
    }
    int64_t absent=5;
    assert(!myl_native_dictionary_contains(dict,&absent));
    /* Popping the first entry shifts every later one down a slot. */
    int64_t first=-1000;
    assert(myl_native_dictionary_pop(dict,&first,&out) && out==0);
    index_sound(dict);
    for (int64_t i=1;i<4096;++i) {
        int64_t key=i*7919-1000;
        assert(myl_native_dictionary_read(dict,&key,&out) && out==i);
    }
    assert(!myl_native_dictionary_contains(dict,&first));
    assert(myl_native_root_pop(&heap,&root));
    /* Two distinct keys built to share a home slot in a table left small on
       purpose: the second must probe past the first, both must read back, and
       removing one must leave the other reachable. */
    myl_native_dictionary *small=myl_native_dictionary_new(&heap,&number,&number,0); assert(small);
    myl_native_root_push(&heap,&root,&small,&pointer);
    size_t target=home(&heap,small,0),collider=0;
    for (int64_t candidate=1;candidate<4096 && !collider;++candidate)
        if (home(&heap,small,candidate)==target) collider=(size_t)candidate;
    assert(collider && small->index.capacity==8);
    int64_t zero=0,other=(int64_t)collider,one=1,two=2;
    myl_native_dictionary_clear(small);
    assert(myl_native_dictionary_write(&heap,small,&zero,&one));
    assert(myl_native_dictionary_write(&heap,small,&other,&two));
    index_sound(small);
    assert(myl_native_dictionary_length(small)==2);
    assert(small->index.slots[target] && small->index.slots[(target+1)&(small->index.capacity-1)]);
    assert(myl_native_dictionary_read(small,&zero,&out) && out==1);
    assert(myl_native_dictionary_read(small,&other,&out) && out==2);
    assert(myl_native_dictionary_pop(small,&zero,&out) && out==1);
    index_sound(small);
    assert(!myl_native_dictionary_contains(small,&zero));
    assert(myl_native_dictionary_read(small,&other,&out) && out==2);
    assert(myl_native_root_pop(&heap,&root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: PY-DICT-2 -- a padded key hashes the same bytes equality compares,
   and a dictionary whose index allocation is refused keeps every earlier answer. */
static void index_limits(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<26);
    myl_native_root root;
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&wide,&number,0); assert(dict);
    myl_native_root_push(&heap,&root,&dict,&pointer);
    int64_t out=0;
    for (int64_t i=0;i<2000;++i) {
        Wide key; memset(&key,0,sizeof key);
        key.tag=(int32_t)(i%7); key.serial=i;
        assert(myl_native_dictionary_write(&heap,dict,&key,&i));
    }
    index_sound(dict);
    assert(myl_native_dictionary_length(dict)==2000);
    for (int64_t i=0;i<2000;++i) {
        Wide key; memset(&key,0,sizeof key);
        key.tag=(int32_t)(i%7); key.serial=i;
        assert(myl_native_dictionary_read(dict,&key,&out) && out==i);
    }
    Wide missing; memset(&missing,0,sizeof missing);
    missing.tag=1; missing.serial=-1;
    assert(!myl_native_dictionary_contains(dict,&missing));
    assert(myl_native_root_pop(&heap,&root));
    myl_native_heap_destroy(&heap);
    /* A budget too small to keep growing: writes start failing, and everything
       the dictionary did accept still reads back, indexed or scanning. */
    myl_native_heap_init(&heap,1<<15);
    dict=myl_native_dictionary_new(&heap,&number,&number,0); assert(dict);
    myl_native_root_push(&heap,&root,&dict,&pointer);
    int64_t accepted=0;
    while (accepted<4096 && myl_native_dictionary_write(&heap,dict,&accepted,&accepted)) accepted++;
    assert(accepted && accepted<4096);
    index_sound(dict);
    assert(myl_native_dictionary_length(dict)==(size_t)accepted);
    for (int64_t i=0;i<accepted;++i)
        assert(myl_native_dictionary_read(dict,&i,&out) && out==i);
    assert(!myl_native_dictionary_contains(dict,&accepted));
    assert(myl_native_root_pop(&heap,&root));
    myl_native_heap_destroy(&heap);
}
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20); heap.stress=1;
    myl_native_root roots[8];
    myl_native_text *input=text(&heap,"é🙂|x|"); assert(input && input->length==5);
    myl_native_root_push(&heap,&roots[0],&input,&pointer);
    myl_native_text *separator=text(&heap,"|"); assert(separator);
    myl_native_root_push(&heap,&roots[1],&separator,&pointer);
    myl_native_list *parts=myl_native_text_split(&heap,input,separator); assert(parts && parts->length==3);
    myl_native_root_push(&heap,&roots[2],&parts,&pointer);
    myl_native_text *joined=myl_native_text_join(&heap,separator,parts); assert(joined);
    myl_native_root_push(&heap,&roots[3],&joined,&pointer);
    assert(myl_native_text_equal(input,joined));
    equals(myl_native_text_at(&heap,input,-4),"🙂");
    equals(myl_native_text_slice(&heap,input,-99,2),"é🙂");
    assert(!myl_native_text_at(&heap,input,INT64_MIN));
    assert(!myl_native_text_from_utf8(&heap,(const unsigned char *)"\xc0\x80",2));
    assert(!myl_native_text_from_utf8(&heap,(const unsigned char *)"\xed\xa0\x80",3));
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&pointer,&number,1); assert(dict);
    myl_native_root_push(&heap,&roots[4],&dict,&pointer);
    int64_t one=1,two=2,three=3,out;
    assert(myl_native_dictionary_write(&heap,dict,&input,&one));
    assert(myl_native_dictionary_write(&heap,dict,&separator,&two));
    assert(myl_native_dictionary_write(&heap,dict,&joined,&three));
    assert(myl_native_dictionary_length(dict)==2);
    assert(myl_native_dictionary_read(dict,&input,&out) && out==3);
    myl_native_text *first;
    assert(myl_native_dictionary_key_at(dict,0,&first) && first==input);
    out=-1;
    assert(myl_native_dictionary_value_at(dict,0,&out) && out==3);
    out=-1;
    assert(!myl_native_dictionary_value_at(dict,2,&out) && out==-1);
    myl_native_list *snapshot=myl_native_dictionary_snapshot(&heap,dict,0); assert(snapshot);
    myl_native_root_push(&heap,&roots[5],&snapshot,&pointer);
    assert(myl_native_dictionary_write(&heap,dict,&input,&one));
    assert(myl_native_list_get(snapshot,0,&out) && out==3);
    myl_native_heap_collect(&heap);
    equals(first,"é🙂|x|");
    for (int i=5;i>=0;--i) assert(myl_native_root_pop(&heap,&roots[i]));
    myl_native_heap_collect(&heap); assert(heap.objects_live==0);
    myl_native_heap_destroy(&heap);
    /* Snapshot descriptors reference canonical key/value types, not the dead
       dictionary's embedded entry descriptor. */
    myl_native_heap_init(&heap,1<<20); heap.stress=1;
    dict=myl_native_dictionary_new(&heap,&number,&number,0); assert(dict);
    myl_native_root_push(&heap,&roots[0],&dict,&pointer);
    assert(myl_native_dictionary_write(&heap,dict,&one,&three));
    snapshot=myl_native_dictionary_snapshot(&heap,dict,0); assert(snapshot);
    myl_native_root_pop(&heap,&roots[0]);
    myl_native_root_push(&heap,&roots[0],&snapshot,&pointer);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==2);
    assert(myl_native_list_get(snapshot,0,&out) && out==3);
    myl_native_heap_collect(&heap);
    assert(myl_native_list_get(snapshot,0,&out) && out==3);
    myl_native_heap_destroy(&heap);
    myl_native_heap_init(&heap,1<<20); heap.stress=1;
    dict=myl_native_dictionary_new(&heap,&pointer,&number,1); assert(dict);
    myl_native_root_push(&heap,&roots[0],&dict,&pointer);
    input=text(&heap,"retained key"); assert(input);
    assert(myl_native_dictionary_write(&heap,dict,&input,&three));
    snapshot=myl_native_dictionary_snapshot(&heap,dict,1); assert(snapshot);
    myl_native_root_pop(&heap,&roots[0]);
    myl_native_root_push(&heap,&roots[0],&snapshot,&pointer);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==3);
    assert(myl_native_list_get(snapshot,0,&first)); equals(first,"retained key");
    myl_native_heap_collect(&heap);
    assert(myl_native_list_get(snapshot,0,&first)); equals(first,"retained key");
    myl_native_heap_destroy(&heap);
    index_cases();
    index_limits();
    puts("native text and dictionary tests passed");
}
