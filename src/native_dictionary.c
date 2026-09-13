#include "native_dictionary.h"
#include <stdlib.h>
#include <string.h>
static const myl_native_type pointer_type={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_field dict_fields[]={{.offset=offsetof(myl_native_dictionary,entries),.type=&pointer_type}};
static const myl_native_type dict_type={.size=sizeof(myl_native_dictionary),.alignment=_Alignof(myl_native_dictionary),.kind=MYL_NATIVE_RECORD,.fields=dict_fields,.field_count=1};
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
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    dict->entries=myl_native_list_new(heap,&dict->entry_type,0);
    myl_native_root_pop(heap,&root);
    return dict->entries ? dict : NULL;
}
static size_t find(const myl_native_dictionary *dict, const void *key) {
    const unsigned char *entries=dict->entries->storage;
    for (size_t i=0;i<dict->entries->length;i++) {
        const void *candidate=entries+i*dict->entry_type.size;
        if (dict->string_keys) {
            myl_native_text *a,*b;
            memcpy(&a,candidate,sizeof(a)); memcpy(&b,key,sizeof(b));
            if (myl_native_text_equal(a,b)) return i;
        } else if (!memcmp(candidate,key,dict->key->size)) return i;
    }
    return SIZE_MAX;
}
size_t myl_native_dictionary_length(const myl_native_dictionary *dict) { return dict->entries->length; }
int myl_native_dictionary_contains(const myl_native_dictionary *dict, const void *key) { return find(dict,key)!=SIZE_MAX; }
int myl_native_dictionary_read(const myl_native_dictionary *dict, const void *key, void *output) {
    size_t index=find(dict,key);
    if (index==SIZE_MAX) return 0;
    memmove(output,(const unsigned char *)dict->entries->storage+index*dict->entry_type.size+dict->value_offset,dict->value->size);
    return 1;
}
int myl_native_dictionary_write(myl_native_heap *heap, myl_native_dictionary *dict, const void *key, const void *value) {
    size_t index=find(dict,key);
    if (index!=SIZE_MAX) {
        memmove((unsigned char *)dict->entries->storage+index*dict->entry_type.size+dict->value_offset,value,dict->value->size);
        return 1;
    }
    unsigned char *entry=calloc(1,dict->entry_type.size ? dict->entry_type.size : 1);
    if (!entry) return 0;
    memcpy(entry,key,dict->key->size);
    memcpy(entry+dict->value_offset,value,dict->value->size);
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    int ok=myl_native_list_append(heap,dict->entries,entry);
    myl_native_root_pop(heap,&root);
    free(entry);
    return ok;
}
myl_native_list *myl_native_dictionary_snapshot(myl_native_heap *heap, myl_native_dictionary *dict, int keys) {
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    const myl_native_type *element=keys?dict->key:dict->value;
    myl_native_list *result=myl_native_list_new(heap,element,dict->entries->length);
    if (result) {
        for (size_t i=0;i<dict->entries->length;i++) {
            const unsigned char *entry=(const unsigned char *)dict->entries->storage+i*dict->entry_type.size;
            memcpy((unsigned char *)result->storage+i*element->size,entry+(keys?0:dict->value_offset),element->size);
        }
        result->length=dict->entries->length;
    }
    myl_native_root_pop(heap,&root);
    return result;
}
int myl_native_dictionary_key_at(const myl_native_dictionary *dict, size_t index, void *output) {
    if (index>=dict->entries->length) return 0;
    memmove(output,(const unsigned char *)dict->entries->storage+index*dict->entry_type.size,dict->key->size);
    return 1;
}
