#include "native_text.h"
#include <string.h>
static const myl_native_type point_type = { .size=4,.alignment=4,.kind=MYL_NATIVE_PLAIN };
static const myl_native_type pointer_type = { .size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER };
static int decode(const unsigned char *bytes, size_t length, size_t *offset, uint32_t *point) {
    if (*offset == length) return 0;
    unsigned char first = bytes[(*offset)++];
    unsigned remaining;
    uint32_t minimum;
    if (first < 128) { *point=first; return 1; }
    if (first >= 0xc2 && first <= 0xdf) { remaining=1; minimum=0x80; *point=first&31; }
    else if (first >= 0xe0 && first <= 0xef) { remaining=2; minimum=0x800; *point=first&15; }
    else if (first >= 0xf0 && first <= 0xf4) { remaining=3; minimum=0x10000; *point=first&7; }
    else return -1;
    if (remaining > length-*offset) return -1;
    while (remaining--) {
        unsigned char next=bytes[(*offset)++];
        if ((next&0xc0)!=0x80) return -1;
        *point=(*point<<6)|(next&63);
    }
    return *point>=minimum && *point<=0x10ffff && !(*point>=0xd800 && *point<=0xdfff) ? 1 : -1;
}
myl_native_text *myl_native_text_from_utf8(myl_native_heap *heap, const unsigned char *bytes, size_t length) {
    size_t count=0, offset=0;
    uint32_t point;
    int status;
    while ((status=decode(bytes,length,&offset,&point))>0) count++;
    if (status<0) return NULL;
    myl_native_text *result=myl_native_list_new(heap,&point_type,count);
    if (!result) return NULL;
    offset=0;
    for (size_t i=0; i<count; ++i) { decode(bytes,length,&offset,&point); ((uint32_t *)result->storage)[i]=point; }
    result->length=count;
    return result;
}
static myl_native_text *copy_points(myl_native_heap *heap, myl_native_text *input, size_t start, size_t count) {
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *result=myl_native_list_new(heap,&point_type,count);
    if (result) {
        if (count) memcpy(result->storage,(uint32_t *)input->storage+start,count*4);
        result->length=count;
    }
    myl_native_root_pop(heap,&root);
    return result;
}
myl_native_text *myl_native_text_concat(myl_native_heap *heap, myl_native_text *left, myl_native_text *right) {
    if (left->length>SIZE_MAX-right->length) return NULL;
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&left,&pointer_type);
    myl_native_root_push(heap,&b,&right,&pointer_type);
    myl_native_text *result=myl_native_list_new(heap,&point_type,left->length+right->length);
    if (result) {
        if (left->length) memcpy(result->storage,left->storage,left->length*4);
        if (right->length) memcpy((uint32_t *)result->storage+left->length,right->storage,right->length*4);
        result->length=left->length+right->length;
    }
    myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
static size_t endpoint(size_t length, int64_t value) {
    if (value>=0) return (uint64_t)value>length ? length : (size_t)value;
    uint64_t distance=(uint64_t)(-(value+1))+1;
    return distance>length ? 0 : length-(size_t)distance;
}
myl_native_text *myl_native_text_at(myl_native_heap *heap, myl_native_text *input, int64_t index) {
    if (index<0 && (uint64_t)(-(index+1))+1>input->length) return NULL;
    if (index>=0 && (uint64_t)index>=input->length) return NULL;
    return copy_points(heap,input,endpoint(input->length,index),1);
}
myl_native_text *myl_native_text_slice(myl_native_heap *heap, myl_native_text *input, int64_t start, int64_t end) {
    size_t first=endpoint(input->length,start), last=endpoint(input->length,end);
    return copy_points(heap,input,first,last>first ? last-first : 0);
}
int myl_native_text_equal(const myl_native_text *a, const myl_native_text *b) {
    return a->length==b->length && (!a->length || !memcmp(a->storage,b->storage,a->length*4));
}
int myl_native_text_contains(const myl_native_text *input, const myl_native_text *needle) {
    if (!needle->length) return 1;
    if (needle->length>input->length) return 0;
    for (size_t i=0;i<=input->length-needle->length;i++)
        if (!memcmp((const uint32_t *)input->storage+i,needle->storage,needle->length*4)) return 1;
    return 0;
}
myl_native_list *myl_native_text_split(myl_native_heap *heap, myl_native_text *input, myl_native_text *separator) {
    if (!separator->length) return NULL;
    myl_native_root a,b,c;
    myl_native_root_push(heap,&a,&input,&pointer_type);
    myl_native_root_push(heap,&b,&separator,&pointer_type);
    myl_native_list *result=myl_native_list_new(heap,&pointer_type,0);
    myl_native_root_push(heap,&c,&result,&pointer_type);
    if (result) {
        size_t start=0,cursor=0;
        while (cursor<=input->length) {
            if (cursor==input->length || (separator->length<=input->length-cursor && !memcmp((uint32_t *)input->storage+cursor,separator->storage,separator->length*4))) {
                myl_native_text *piece=copy_points(heap,input,start,cursor-start);
                if (!piece || !myl_native_list_append(heap,result,&piece)) { result=NULL; break; }
                if (cursor==input->length) break;
                cursor+=separator->length; start=cursor;
            } else cursor++;
        }
    }
    myl_native_root_pop(heap,&c); myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
myl_native_text *myl_native_text_join(myl_native_heap *heap, myl_native_text *separator, myl_native_list *list) {
    size_t count=0;
    myl_native_text **items=list->storage;
    for (size_t i=0;i<list->length;i++) {
        if (items[i]->length>SIZE_MAX-count) return NULL;
        count+=items[i]->length;
        if (i) { if (separator->length>SIZE_MAX-count) return NULL; count+=separator->length; }
    }
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&separator,&pointer_type); myl_native_root_push(heap,&b,&list,&pointer_type);
    myl_native_text *result=myl_native_list_new(heap,&point_type,count);
    if (result) {
        size_t at=0;
        for (size_t i=0;i<list->length;i++) {
            if (i && separator->length) { memcpy((uint32_t *)result->storage+at,separator->storage,separator->length*4); at+=separator->length; }
            if (items[i]->length) memcpy((uint32_t *)result->storage+at,items[i]->storage,items[i]->length*4);
            at+=items[i]->length;
        }
        result->length=count;
    }
    myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
size_t myl_native_text_utf8(const myl_native_text *text, unsigned char *output, size_t capacity) {
    const uint32_t *points=text->storage;
    size_t required=0;
    for (size_t i=0;i<text->length;i++) {
        size_t width=points[i]<0x80?1:points[i]<0x800?2:points[i]<0x10000?3:4;
        if (width>SIZE_MAX-required) return SIZE_MAX;
        required+=width;
    }
    if (!output || capacity<required) return required;
    size_t at=0;
    for (size_t i=0;i<text->length;i++) {
        uint32_t p=points[i];
        if (p<0x80) output[at++]=(unsigned char)p;
        else if (p<0x800) { output[at++]=(unsigned char)(0xc0|(p>>6)); output[at++]=(unsigned char)(0x80|(p&63)); }
        else if (p<0x10000) { output[at++]=(unsigned char)(0xe0|(p>>12)); output[at++]=(unsigned char)(0x80|((p>>6)&63)); output[at++]=(unsigned char)(0x80|(p&63)); }
        else { output[at++]=(unsigned char)(0xf0|(p>>18)); output[at++]=(unsigned char)(0x80|((p>>12)&63)); output[at++]=(unsigned char)(0x80|((p>>6)&63)); output[at++]=(unsigned char)(0x80|(p&63)); }
    }
    return required;
}
