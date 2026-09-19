#include "native_text.h"
#include <string.h>
const myl_native_type myl_native_text_point = { .size=4,.alignment=4,.kind=MYL_NATIVE_PLAIN };
static const myl_native_type pointer_type = { .size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER };
/* Text is immutable in practice but keeps the list header, so the scalars live
   in the same allocation as that header rather than in a second one with a
   header of its own: 96 bytes and one allocator round trip less per text, at
   the cost of a `storage` pointer that is not a payload. The object descriptor
   handed to the allocator therefore has no traced field — the scalars are
   plain u32, so there is nothing to trace — and `storage` is set to the block's
   tail only when there is at least one scalar to hold. Appending to such a text
   still grows an ordinary backing array, because `length == capacity`. */
myl_native_text *myl_native_text_new(myl_native_heap *heap, size_t count) {
    if (count > (SIZE_MAX-sizeof(myl_native_list))/sizeof(uint32_t)) return NULL;
    myl_native_text *text=myl_native_heap_alloc_block(heap,sizeof(myl_native_list),count*sizeof(uint32_t));
    if (!text) return NULL;
    text->element=&myl_native_text_point;
    text->capacity=count;
    if (count) text->storage=(unsigned char *)text+sizeof(myl_native_list);
    return text;
}
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
int myl_native_text_valid_utf8(const unsigned char *bytes, size_t length) {
    size_t offset=0;
    uint32_t point;
    int status;
    while ((status=decode(bytes,length,&offset,&point))>0) {}
    return status==0;
}
/* One scalar per byte for the ASCII range, which is the whole of most source
   text: check for a high bit and widen in two flat passes instead of running
   the branchy UTF-8 decoder twice (once to count, once to fill). The high-bit
   scan goes a word at a time — it is the only part of an ASCII conversion that
   touches every input byte, and the byte loop it replaces measured as the bulk
   of `myl_native_text_from_utf8_checked` on the census. */
static int ascii(const unsigned char *bytes, size_t length) {
    size_t i=0;
    for (; i+sizeof(uint64_t)<=length; i+=sizeof(uint64_t)) {
        uint64_t word;
        memcpy(&word,bytes+i,sizeof word);
        if (word&UINT64_C(0x8080808080808080)) return 0;
    }
    for (; i<length; ++i) if (bytes[i]&0x80u) return 0;
    return 1;
}
/* End of the ASCII run starting at `offset`: whole words first, then the bytes
   of the word that held the high bit and any trailing bytes too short for one.
   The fallback below runs this over input that is ASCII except for a few bytes,
   which is what source text with a stray non-ASCII character looks like. */
static size_t ascii_run(const unsigned char *bytes, size_t length, size_t offset) {
    size_t i=offset;
    for (; i+sizeof(uint64_t)<=length; i+=sizeof(uint64_t)) {
        uint64_t word;
        memcpy(&word,bytes+i,sizeof word);
        if (word&UINT64_C(0x8080808080808080)) break;
    }
    while (i<length && bytes[i]<0x80u) i++;
    return i;
}
/* One validating pass that both checks and fills. ASCII (the whole of most
   source text) is a high-bit scan plus a widening pass; every other input runs
   the branchy decoder once to validate and count and once more to fill, so no
   caller needs a separate prior validation pass. `*invalid` names the failure:
   1 for malformed input, 0 for a refused allocation. Inside the fallback the
   ASCII runs are still skipped a word at a time, so text that is ASCII but for
   one multi-byte character does not pay the per-byte decoder for all of it. */
myl_native_text *myl_native_text_from_utf8_checked(myl_native_heap *heap, const unsigned char *bytes, size_t length, int *invalid) {
    *invalid=0;
    size_t count=0, offset=0, run=0;
    uint32_t point;
    if (ascii(bytes,length)) {
        myl_native_text *result=myl_native_text_new(heap,length);
        if (!result) return NULL;
        uint32_t *points=(uint32_t *)result->storage;
        for (size_t i=0; i<length; ++i) points[i]=bytes[i];
        result->length=length;
        return result;
    }
    for (;;) {
        run=ascii_run(bytes,length,offset);
        count+=run-offset;
        offset=run;
        if (offset==length) break;
        if (decode(bytes,length,&offset,&point)<0) { *invalid=1; return NULL; }
        count++;
    }
    myl_native_text *result=myl_native_text_new(heap,count);
    if (!result) return NULL;
    uint32_t *points=(uint32_t *)result->storage;
    offset=0;
    size_t written=0;
    for (;;) {
        run=ascii_run(bytes,length,offset);
        const size_t ascii=run-offset;
        for (size_t i=0; i<ascii; ++i) points[written+i]=bytes[offset+i];
        written+=ascii;
        offset=run;
        if (offset==length) break;
        decode(bytes,length,&offset,&point);
        points[written++]=point;
    }
    result->length=count;
    return result;
}
myl_native_text *myl_native_text_from_utf8(myl_native_heap *heap, const unsigned char *bytes, size_t length) {
    int invalid=0;
    return myl_native_text_from_utf8_checked(heap,bytes,length,&invalid);
}
myl_native_text *myl_native_text_copy(myl_native_heap *heap, myl_native_text *input, size_t start, size_t count) {
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *result=myl_native_text_new(heap,count);
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
    myl_native_text *result=myl_native_text_new(heap,left->length+right->length);
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
/* Return the shared immortal one-scalar text for an ASCII code point, building
 * the table on first use. NULL means the slot could not be allocated and the
 * caller must fall back to a fresh copy. */
static myl_native_text *ascii_scalar(myl_native_heap *heap, unsigned point) {
    if (!heap->text_scalars_ready) {
        /* Mark the table ready first: a refused allocation leaves the remaining
         * slots NULL, so a later call retries only those and never rebuilds the
         * ones already stored here. The collector marks the table itself, so no
         * root-stack entry is involved and a frame restore cannot drop it. */
        heap->text_scalars_ready=1;
        /* The table outlives every arena, so build it at the ordinary tracing
         * depth: an index performed inside `with arena()` must not leave the table
         * pointing at objects the block's bulk release will free. */
        unsigned depth=heap->region_depth;
        heap->region_depth=0;
        for (unsigned code=0; code<128; code++) {
            myl_native_text *text=myl_native_text_new(heap,1);
            if (!text) { heap->region_depth=depth; return NULL; }
            ((uint32_t *)text->storage)[0]=code;
            text->length=1;
            heap->text_scalars[code]=text;
        }
        heap->region_depth=depth;
    }
    return heap->text_scalars[point];
}
myl_native_text *myl_native_text_at(myl_native_heap *heap, myl_native_text *input, int64_t index) {
    if (index<0 && (uint64_t)(-(index+1))+1>input->length) return NULL;
    if (index>=0 && (uint64_t)index>=input->length) return NULL;
    size_t at=endpoint(input->length,index);
    uint32_t point=((const uint32_t *)input->storage)[at];
    if (point<128) {
        myl_native_text *scalar=ascii_scalar(heap,point);
        if (scalar) return scalar;
    }
    return myl_native_text_copy(heap,input,at,1);
}
myl_native_text *myl_native_text_slice(myl_native_heap *heap, myl_native_text *input, int64_t start, int64_t end) {
    size_t first=endpoint(input->length,start), last=endpoint(input->length,end);
    return myl_native_text_copy(heap,input,first,last>first ? last-first : 0);
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
                myl_native_text *piece=myl_native_text_copy(heap,input,start,cursor-start);
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
    myl_native_text *result=myl_native_text_new(heap,count);
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
