#include "native_bytes.h"
#include <stdlib.h>
#include <string.h>
static const myl_native_type byte_type = { .size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN };
static const myl_native_type integer_type = { .size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN };
static const myl_native_type pointer_type = { .size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER };
/* Python endpoints clamp instead of trapping, matching managed list slices. */
static size_t endpoint(size_t length, int64_t value) {
    if (value>=0) return (uint64_t)value>length ? length : (size_t)value;
    uint64_t distance=(uint64_t)(-(value+1))+1;
    return distance>length ? 0 : length-(size_t)distance;
}
static myl_native_bytes *copy_range(myl_native_heap *heap, myl_native_bytes *input, size_t start, size_t count) {
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_bytes *result=myl_native_list_new(heap,&byte_type,count);
    if (result) {
        if (count) memcpy(result->storage,(const unsigned char *)input->storage+start,count);
        result->length=count;
    }
    myl_native_root_pop(heap,&root);
    return result;
}
myl_native_bytes *myl_native_bytes_new(myl_native_heap *heap, const unsigned char *raw, size_t length) {
    myl_native_bytes *result=myl_native_list_new(heap,&byte_type,length);
    if (!result) return NULL;
    if (length) memcpy(result->storage,raw,length);
    result->length=length;
    return result;
}
myl_native_bytes *myl_native_bytes_concat(myl_native_heap *heap, myl_native_bytes *left, myl_native_bytes *right) {
    if (left->length>SIZE_MAX-right->length) return NULL;
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&left,&pointer_type);
    myl_native_root_push(heap,&b,&right,&pointer_type);
    myl_native_bytes *result=myl_native_list_new(heap,&byte_type,left->length+right->length);
    if (result) {
        if (left->length) memcpy(result->storage,left->storage,left->length);
        if (right->length) memcpy((unsigned char *)result->storage+left->length,right->storage,right->length);
        result->length=left->length+right->length;
    }
    myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
myl_native_bytes *myl_native_bytes_slice(myl_native_heap *heap, myl_native_bytes *input, int64_t start, int64_t end) {
    size_t first=endpoint(input->length,start), last=endpoint(input->length,end);
    return copy_range(heap,input,first,last>first ? last-first : 0);
}
static int matches(const myl_native_bytes *input, size_t at, const myl_native_bytes *needle) {
    if (needle->length>input->length-at) return 0;
    return !needle->length || !memcmp((const unsigned char *)input->storage+at,needle->storage,needle->length);
}
int64_t myl_native_bytes_find(const myl_native_bytes *input, const myl_native_bytes *needle) {
    if (needle->length>input->length) return -1;
    for (size_t i=0;i<=input->length-needle->length;i++) if (matches(input,i,needle)) return (int64_t)i;
    return -1;
}
int myl_native_bytes_starts_with(const myl_native_bytes *input, const myl_native_bytes *prefix) {
    return prefix->length<=input->length && matches(input,0,prefix);
}
int myl_native_bytes_ends_with(const myl_native_bytes *input, const myl_native_bytes *suffix) {
    return suffix->length<=input->length && matches(input,input->length-suffix->length,suffix);
}
int myl_native_bytes_has_byte(const myl_native_bytes *input, int64_t value) {
    if (value<0 || value>255) return 0;
    const unsigned char *bytes=input->storage;
    for (size_t i=0;i<input->length;i++) if (bytes[i]==(unsigned char)value) return 1;
    return 0;
}
myl_native_list *myl_native_bytes_split(myl_native_heap *heap, myl_native_bytes *input, myl_native_bytes *separator) {
    if (!separator->length) return NULL;
    myl_native_root a,b,c;
    myl_native_root_push(heap,&a,&input,&pointer_type);
    myl_native_root_push(heap,&b,&separator,&pointer_type);
    myl_native_list *result=myl_native_list_new(heap,&pointer_type,0);
    myl_native_root_push(heap,&c,&result,&pointer_type);
    if (result) {
        size_t start=0,cursor=0;
        while (cursor<=input->length) {
            if (cursor==input->length || matches(input,cursor,separator)) {
                myl_native_bytes *piece=copy_range(heap,input,start,cursor-start);
                if (!piece || !myl_native_list_append(heap,result,&piece)) { result=NULL; break; }
                if (cursor==input->length) break;
                cursor+=separator->length; start=cursor;
            } else cursor++;
        }
    }
    myl_native_root_pop(heap,&c); myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
myl_native_bytes *myl_native_bytes_join(myl_native_heap *heap, myl_native_bytes *separator, myl_native_list *list) {
    size_t count=0;
    myl_native_bytes **items=list->storage;
    for (size_t i=0;i<list->length;i++) {
        if (items[i]->length>SIZE_MAX-count) return NULL;
        count+=items[i]->length;
        if (i) { if (separator->length>SIZE_MAX-count) return NULL; count+=separator->length; }
    }
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&separator,&pointer_type); myl_native_root_push(heap,&b,&list,&pointer_type);
    myl_native_bytes *result=myl_native_list_new(heap,&byte_type,count);
    if (result) {
        unsigned char *output=result->storage;
        size_t at=0;
        items=list->storage;
        for (size_t i=0;i<list->length;i++) {
            if (i && separator->length) { memcpy(output+at,separator->storage,separator->length); at+=separator->length; }
            if (items[i]->length) memcpy(output+at,items[i]->storage,items[i]->length);
            at+=items[i]->length;
        }
        result->length=count;
    }
    myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
myl_native_list *myl_native_bytes_to_list(myl_native_heap *heap, myl_native_bytes *input) {
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_list *result=myl_native_list_new(heap,&integer_type,input->length);
    if (result) {
        const unsigned char *bytes=input->storage;
        int64_t *output=result->storage;
        for (size_t i=0;i<input->length;i++) output[i]=(int64_t)bytes[i];
        result->length=input->length;
    }
    myl_native_root_pop(heap,&root);
    return result;
}
myl_native_bytes *myl_native_bytes_from_list(myl_native_heap *heap, myl_native_list *list, int *status) {
    const int64_t *values=list->storage;
    *status=MYL_BYTES_OK;
    for (size_t i=0;i<list->length;i++) if (values[i]<0 || values[i]>255) { *status=MYL_BYTES_RANGE;return NULL; }
    myl_native_root root;
    myl_native_root_push(heap,&root,&list,&pointer_type);
    myl_native_bytes *result=myl_native_list_new(heap,&byte_type,list->length);
    if (result) {
        values=list->storage;
        unsigned char *output=result->storage;
        for (size_t i=0;i<list->length;i++) output[i]=(unsigned char)values[i];
        result->length=list->length;
    } else *status=MYL_BYTES_MEMORY;
    myl_native_root_pop(heap,&root);
    return result;
}
myl_native_text *myl_native_bytes_hex(myl_native_heap *heap, myl_native_bytes *input) {
    static const char digits[]="0123456789abcdef";
    if (input->length>SIZE_MAX/2) return NULL;
    unsigned char *text=malloc(input->length ? input->length*2 : 1);
    if (!text) return NULL;
    const unsigned char *bytes=input->storage;
    for (size_t i=0;i<input->length;i++) {
        text[i*2]=(unsigned char)digits[bytes[i]>>4];
        text[i*2+1]=(unsigned char)digits[bytes[i]&15];
    }
    myl_native_text *result=myl_native_text_from_utf8(heap,text,input->length*2);
    free(text);
    return result;
}
/* Hexadecimal parsing reads the UTF-8 encoding so a non-ASCII digit is rejected
   exactly where the VM rejects it. */
static int hex_digit(unsigned char value) {
    if (value>='0' && value<='9') return value-'0';
    if (value>='a' && value<='f') return value-'a'+10;
    if (value>='A' && value<='F') return value-'A'+10;
    return -1;
}
myl_native_bytes *myl_native_bytes_from_hex(myl_native_heap *heap, myl_native_text *input, int *status) {
    *status=MYL_BYTES_MEMORY;
    size_t required=myl_native_text_utf8(input,NULL,0);
    if (required==SIZE_MAX) return NULL;
    unsigned char *raw=malloc(required?required:1);
    if (!raw) return NULL;
    myl_native_text_utf8(input,raw,required);
    if (required%2) { free(raw);*status=MYL_BYTES_INVALID;return NULL; }
    for (size_t i=0;i<required;i++) if (hex_digit(raw[i])<0) { free(raw);*status=MYL_BYTES_INVALID;return NULL; }
    for (size_t i=0;i<required;i+=2) raw[i/2]=(unsigned char)(hex_digit(raw[i])*16+hex_digit(raw[i+1]));
    myl_native_bytes *result=myl_native_bytes_new(heap,raw,required/2);
    free(raw);
    if (result) *status=MYL_BYTES_OK;
    return result;
}
myl_native_bytes *myl_native_bytes_encode(myl_native_heap *heap, myl_native_text *input) {
    size_t required=myl_native_text_utf8(input,NULL,0);
    if (required==SIZE_MAX) return NULL;
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_bytes *result=myl_native_list_new(heap,&byte_type,required);
    if (result) {
        myl_native_text_utf8(input,result->storage,required);
        result->length=required;
    }
    myl_native_root_pop(heap,&root);
    return result;
}
myl_native_text *myl_native_bytes_decode(myl_native_heap *heap, myl_native_bytes *input, int *status) {
    int invalid=0;
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *result=myl_native_text_from_utf8_checked(heap,input->storage,input->length,&invalid);
    myl_native_root_pop(heap,&root);
    *status=result ? MYL_BYTES_OK:(invalid ? MYL_BYTES_INVALID:MYL_BYTES_MEMORY);
    return result;
}
myl_native_text *myl_native_bytes_decode_range(myl_native_heap *heap, myl_native_bytes *input, int64_t start, int64_t end, int *status) {
    int invalid=0;
    size_t first=endpoint(input->length,start), last=endpoint(input->length,end);
    size_t count=last>first ? last-first : 0;
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *result=myl_native_text_from_utf8_checked(heap,(const unsigned char *)input->storage+first,count,&invalid);
    myl_native_root_pop(heap,&root);
    *status=result ? MYL_BYTES_OK:(invalid ? MYL_BYTES_INVALID:MYL_BYTES_MEMORY);
    return result;
}
