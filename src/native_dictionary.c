#include "native_dictionary.h"
#include <stdlib.h>
#include <string.h>
static const myl_native_type pointer_type={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
/* Slot numbers are plain integers, so the collector keeps the block alive through
 * the traced field below and never walks what it holds. */
static const myl_native_type slot_type={.size=sizeof(size_t),.alignment=_Alignof(size_t),.kind=MYL_NATIVE_PLAIN};
static const myl_native_field dict_fields[]={
    {.offset=offsetof(myl_native_dictionary,entries),.type=&pointer_type},
    {.offset=offsetof(myl_native_dictionary,index)+offsetof(myl_native_dictionary_index,slots),.type=&pointer_type}};
static const myl_native_type dict_type={.size=sizeof(myl_native_dictionary),.alignment=_Alignof(myl_native_dictionary),.kind=MYL_NATIVE_RECORD,.fields=dict_fields,.field_count=2};
myl_native_dictionary *myl_native_dictionary_new(myl_native_heap *heap, const myl_native_type *key, const myl_native_type *value, int string_keys) {
    if (!key || !value || !key->alignment || !value->alignment) return NULL;
    size_t alignment=key->alignment>value->alignment?key->alignment:value->alignment;
    if (key->size>SIZE_MAX-(value->alignment-1)) return NULL;
    size_t offset=(key->size+value->alignment-1)&~(value->alignment-1);
    if (offset>SIZE_MAX-value->size || offset+value->size>SIZE_MAX-(alignment-1)) return NULL;
    size_t size=(offset+value->size+alignment-1)&~(alignment-1);
    myl_native_dictionary *dict=myl_native_heap_alloc(heap,&dict_type,1);
    if (!dict) return NULL;
    dict->key=key; dict->value=value; dict->value_offset=offset; dict->string_keys=string_keys;
    dict->entry_fields[0]=(myl_native_field){.offset=0,.type=key};
    dict->entry_fields[1]=(myl_native_field){.offset=offset,.type=value};
    dict->entry_type=(myl_native_type){.size=size,.alignment=alignment,.kind=MYL_NATIVE_RECORD,.fields=dict->entry_fields,.field_count=2};
    /* An empty dictionary carries no table: the first write sizes one. */
    dict->index=(myl_native_dictionary_index){.slots=NULL,.capacity=0};
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    dict->entries=myl_native_list_new(heap,&dict->entry_type,0);
    myl_native_root_pop(heap,&root);
    return dict->entries ? dict : NULL;
}
static const unsigned char *entry_at(const myl_native_dictionary *dict, size_t index) {
    return (const unsigned char *)dict->entries->storage+index*dict->entry_type.size;
}
/* Exactly the comparison `find` used before the index existed: text content for
 * `str` keys, and the raw key bytes for every other key type. */
static int same_key(const myl_native_dictionary *dict, const void *entry, const void *key) {
    if (!dict->string_keys) return !memcmp(entry,key,dict->key->size);
    myl_native_text *a,*b;
    memcpy(&a,entry,sizeof(a)); memcpy(&b,key,sizeof(b));
    return myl_native_text_equal(a,b);
}
/* FNV-1a over precisely the units `same_key` compares, then one avalanche so the
 * low bits the table masks depend on the whole key. Fixed constants, no seed: the
 * runtime has no sanctioned randomness and a dictionary must behave identically
 * on every run. */
static uint64_t hash_key(const myl_native_dictionary *dict, const void *key) {
    uint64_t hash=0xcbf29ce484222325ULL;
    if (dict->string_keys) {
        myl_native_text *text;
        memcpy(&text,key,sizeof(text));
        size_t count=text?text->length:0;
        const uint32_t *scalars=text?text->storage:NULL;
        for (size_t i=0;i<count;i++) { hash^=scalars[i]; hash*=0x100000001b3ULL; }
        hash^=count;
    } else {
        const unsigned char *bytes=key;
        for (size_t i=0;i<dict->key->size;i++) { hash^=bytes[i]; hash*=0x100000001b3ULL; }
    }
    hash^=hash>>33; hash*=0xff51afd7ed558ccdULL;
    hash^=hash>>33; hash*=0xc4ceb9fe1a85ec53ULL;
    return hash^(hash>>33);
}
/* Linear probing from the masked hash. The caller guarantees a free slot, which
 * the load factor below always leaves. */
static void index_place(const myl_native_dictionary_index *index, uint64_t hash, size_t entry) {
    size_t mask=index->capacity-1, at=(size_t)hash&mask;
    while (index->slots[at]) at=(at+1)&mask;
    index->slots[at]=entry+1;
}
static void index_rebuild(myl_native_dictionary *dict) {
    if (!dict->index.capacity) return;
    memset(dict->index.slots,0,dict->index.capacity*sizeof(size_t));
    for (size_t i=0;i<dict->entries->length;i++)
        index_place(&dict->index,hash_key(dict,entry_at(dict,i)),i);
}
/* Size the table for `needed` entries at a load factor of at most 5/8 and refill
 * it. A refused allocation drops the index rather than failing the write: lookups
 * fall back to scanning, which is slower and exactly as correct, and the caller's
 * budget flag is left as it was so a later trap still names the real cause. */
static void index_reserve(myl_native_heap *heap, myl_native_dictionary *dict, size_t needed) {
    if (dict->index.capacity && needed*8<=dict->index.capacity*5) return;
    size_t capacity=dict->index.capacity?dict->index.capacity:8;
    while (needed>SIZE_MAX/8 || needed*8>capacity*5) {
        if (capacity>SIZE_MAX/16) { dict->index.slots=NULL; dict->index.capacity=0; return; }
        capacity*=2;
    }
    int exhausted=heap->exhausted;
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    size_t *slots=myl_native_heap_alloc_at(heap,&slot_type,capacity,myl_native_object_region(heap,dict));
    myl_native_root_pop(heap,&root);
    if (!slots) {
        heap->exhausted=exhausted;
        dict->index.slots=NULL; dict->index.capacity=0;
        return;
    }
    dict->index.slots=slots; dict->index.capacity=capacity;
    index_rebuild(dict);
}
static size_t find(const myl_native_dictionary *dict, const void *key) {
    if (!dict->index.capacity) {
        for (size_t i=0;i<dict->entries->length;i++)
            if (same_key(dict,entry_at(dict,i),key)) return i;
        return SIZE_MAX;
    }
    size_t mask=dict->index.capacity-1, at=(size_t)hash_key(dict,key)&mask;
    while (dict->index.slots[at]) {
        size_t entry=dict->index.slots[at]-1;
        if (same_key(dict,entry_at(dict,entry),key)) return entry;
        at=(at+1)&mask;
    }
    return SIZE_MAX;
}
size_t myl_native_dictionary_length(const myl_native_dictionary *dict) { return dict->entries->length; }
int myl_native_dictionary_contains(const myl_native_dictionary *dict, const void *key) { return find(dict,key)!=SIZE_MAX; }
int myl_native_dictionary_read(const myl_native_dictionary *dict, const void *key, void *output) {
    size_t index=find(dict,key);
    if (index==SIZE_MAX) return 0;
    memmove(output,entry_at(dict,index)+dict->value_offset,dict->value->size);
    return 1;
}
int myl_native_dictionary_write(myl_native_heap *heap, myl_native_dictionary *dict, const void *key, const void *value) {
    size_t index=find(dict,key);
    if (index!=SIZE_MAX) {
        memmove((unsigned char *)dict->entries->storage+index*dict->entry_type.size+dict->value_offset,value,dict->value->size);
        return 1;
    }
    /* Most entries are a pointer or two, so the staged entry lives on the stack;
     * only an outsized key or value reaches the host allocator. */
    unsigned char inline_entry[96];
    size_t width=dict->entry_type.size?dict->entry_type.size:1;
    unsigned char *entry=width<=sizeof inline_entry?inline_entry:calloc(1,width);
    if (!entry) return 0;
    memset(entry,0,width);
    memcpy(entry,key,dict->key->size);
    memcpy(entry+dict->value_offset,value,dict->value->size);
    /* The staged entry is rooted before anything can allocate, so the key it
     * holds survives a collection even when the caller passed the only reference. */
    myl_native_root owner_root, entry_root;
    myl_native_root_push(heap,&owner_root,&dict,&pointer_type);
    myl_native_root_push(heap,&entry_root,entry,&dict->entry_type);
    index_reserve(heap,dict,dict->entries->length+1);
    uint64_t hash=dict->index.capacity?hash_key(dict,entry):0;
    int ok=myl_native_list_append(heap,dict->entries,entry);
    myl_native_root_pop(heap,&entry_root);
    myl_native_root_pop(heap,&owner_root);
    if (entry!=inline_entry) free(entry);
    if (ok && dict->index.capacity) index_place(&dict->index,hash,dict->entries->length-1);
    return ok;
}
myl_native_list *myl_native_dictionary_snapshot(myl_native_heap *heap, myl_native_dictionary *dict, int keys) {
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    const myl_native_type *element=keys?dict->key:dict->value;
    myl_native_list *result=myl_native_list_new(heap,element,dict->entries->length);
    if (result) {
        for (size_t i=0;i<dict->entries->length;i++) {
            const unsigned char *entry=entry_at(dict,i);
            memcpy((unsigned char *)result->storage+i*element->size,entry+(keys?0:dict->value_offset),element->size);
        }
        result->length=dict->entries->length;
    }
    myl_native_root_pop(heap,&root);
    return result;
}
int myl_native_dictionary_key_at(const myl_native_dictionary *dict, size_t index, void *output) {
    if (index>=dict->entries->length) return 0;
    memmove(output,entry_at(dict,index),dict->key->size);
    return 1;
}
int myl_native_dictionary_value_at(const myl_native_dictionary *dict, size_t index, void *output) {
    if (index>=dict->entries->length) return 0;
    memmove(output,entry_at(dict,index)+dict->value_offset,dict->value->size);
    return 1;
}
int myl_native_dictionary_pop(myl_native_dictionary *dict, const void *key, void *output) {
    size_t index=find(dict,key);
    if (index==SIZE_MAX) return 0;
    unsigned char *entries=dict->entries->storage;
    size_t size=dict->entry_type.size;
    memcpy(output,entries+index*size+dict->value_offset,dict->value->size);
    size_t moved=dict->entries->length-index-1;
    if (moved) memmove(entries+index*size,entries+(index+1)*size,moved*size);
    dict->entries->length--;
    memset(entries+dict->entries->length*size,0,size);
    dict->entries->generation++;
    /* Every entry after the removed one moved down, so its recorded slot is now
     * wrong. Refilling the existing table needs no allocation, which is what lets
     * `pop` keep its heap-free signature; it also makes `pop` the one linear
     * operation left. */
    index_rebuild(dict);
    return 1;
}
int myl_native_dictionary_update(myl_native_heap *heap, myl_native_dictionary *dict, const myl_native_dictionary *source) {
    for (size_t i=0;i<source->entries->length;i++) {
        const unsigned char *entry=(const unsigned char *)source->entries->storage+i*source->entry_type.size;
        if (!myl_native_dictionary_write(heap,dict,entry,entry+source->value_offset)) return 0;
    }
    return 1;
}
int myl_native_dictionary_setdefault(myl_native_heap *heap, myl_native_dictionary *dict, const void *key, const void *fallback, void *output) {
    if (myl_native_dictionary_read(dict,key,output)) return 1;
    if (!myl_native_dictionary_write(heap,dict,key,fallback)) return 0;
    memcpy(output,fallback,dict->value->size);
    return 1;
}
void myl_native_dictionary_clear(myl_native_dictionary *dict) {
    if (dict->entries->length) {
        memset(dict->entries->storage,0,dict->entries->length*dict->entry_type.size);
        dict->entries->length=0;
        dict->entries->generation++;
        if (dict->index.capacity) memset(dict->index.slots,0,dict->index.capacity*sizeof(size_t));
    }
}
void myl_native_dictionary_reindex(myl_native_heap *heap, myl_native_dictionary *dict) {
    index_reserve(heap,dict,dict->entries->length);
    index_rebuild(dict);
}
myl_native_dictionary *myl_native_dictionary_copy(myl_native_heap *heap, const myl_native_dictionary *input) {
    const myl_native_dictionary *rooted=input;
    myl_native_root root;
    myl_native_root_push(heap,&root,&rooted,&pointer_type);
    myl_native_dictionary *result=myl_native_dictionary_new(heap,input->key,input->value,input->string_keys);
    if (result && !myl_native_dictionary_update(heap,result,input)) result=NULL;
    myl_native_root_pop(heap,&root);
    return result;
}
