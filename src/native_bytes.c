/* `memmem` is a GNU extension, so the feature macro has to precede <string.h>. */
#define _GNU_SOURCE
#include "native_bytes.h"
#include <stdlib.h>
#include <string.h>
static const myl_native_type byte_type = { .size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN };
static const myl_native_type integer_type = { .size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN };
static const myl_native_type pointer_type = { .size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER };
/* Splits on maximal runs of ASCII whitespace, dropping every empty piece. It is
   declared here rather than in the companion header so this file stays the only
   one the whitespace-split addition touches on the byte runtime side; the QBE
   emitter reaches it by symbol name. */
myl_native_list *myl_native_bytes_split_whitespace(myl_native_heap *, myl_native_bytes *);
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
myl_native_bytes *myl_native_bytes_copy(myl_native_heap *heap, myl_native_bytes *input) {
    return copy_range(heap,input,0,input->length);
}
/* A view is a byte string that reads another byte string's octets: `storage`
   points into the source's backing at the range start and `length` is the range
   length, so every read path — indexing, iteration, equality, search, slicing,
   decode, parsing — works on a view unchanged. The one thing a view adds is
   retention: its header carries the descriptor below, whose single traced field
   is the backing block, so the octets outlive the byte string that first owned
   them. The field lives in the list header's unused drop link, and the recorded
   pointer is the *storage block* rather than its owner: a block's own header
   sits immediately before it, which a mid-block content pointer would not have,
   and a frozen literal's block is immortal, so the collector never queues it. */
static const myl_native_field view_fields[] = {
    { .offset=offsetof(myl_native_list,work)+offsetof(myl_native_drop_link,owner), .type=&pointer_type }
};
static const myl_native_type view_header_type = {
    .size=sizeof(myl_native_list), .alignment=_Alignof(myl_native_list),
    .kind=MYL_NATIVE_RECORD, .fields=view_fields, .field_count=1,
    .trace_fields=view_fields, .trace_field_count=1, .trace_mode=MYL_NATIVE_TRACE_FIELDS
};
/* The backing block a view of `source` must keep alive. A byte string owns the
   block its `storage` points into; a view already points into a block an
   earlier view recorded, so it hands that record on instead of deriving a
   header from a mid-block address. */
static void *view_backing(const myl_native_heap *heap, const myl_native_bytes *source) {
    if (myl_native_object_element(heap, source)==&view_header_type) return source->work.owner;
    return source->storage;
}
myl_native_bytes *myl_native_bytes_view(myl_native_heap *heap, myl_native_bytes *source, int64_t start, int64_t end) {
    size_t first=endpoint(source->length,start), last=endpoint(source->length,end);
    size_t count=last>first ? last-first : 0;
    myl_native_root root;
    myl_native_root_push(heap,&root,&source,&pointer_type);
    myl_native_bytes *view=myl_native_heap_alloc(heap,&view_header_type,1);
    if (view) {
        view->element=&byte_type;
        view->length=count;
        view->capacity=count;
        view->storage=count ? (unsigned char *)source->storage+first : source->storage;
        view->work.owner=view_backing(heap,source);
    }
    myl_native_root_pop(heap,&root);
    return view;
}
/* Count the Unicode scalars of a byte string's octets in one validating pass, so
   measuring a range never decodes it. A word at a time is ASCII — one scalar per
   octet — and every other scalar is decoded with exactly the acceptance rules of
   `myl_native_text_valid_utf8`: a lead byte of 0xC2..0xF4 with that many
   continuation bytes, above the length's minimum and inside the scalar range. A
   malformed sequence reports MYL_BYTES_INVALID and no count. */
static int64_t scalar_count(const unsigned char *, size_t, int *);
int64_t myl_native_bytes_scalar_count(const myl_native_bytes *input, int *status) {
    return scalar_count(input->storage,input->length,status);
}
static int64_t scalar_count(const unsigned char *bytes, size_t length, int *status) {
    size_t at=0;
    int64_t count=0;
    while (at<length) {
        while (at+sizeof(uint64_t)<=length) {
            uint64_t word;
            memcpy(&word,bytes+at,sizeof word);
            if (word&UINT64_C(0x8080808080808080)) break;
            at+=sizeof(uint64_t);
            count+=8;
        }
        if (at<length && bytes[at]<0x80) { at+=1; count+=1; continue; }
        if (at==length) break;
        unsigned char first=bytes[at];
        unsigned remaining;
        uint32_t minimum;
        if (first>=0xc2 && first<=0xdf) { remaining=1; minimum=0x80; }
        else if (first>=0xe0 && first<=0xef) { remaining=2; minimum=0x800; }
        else if (first>=0xf0 && first<=0xf4) { remaining=3; minimum=0x10000; }
        else { *status=MYL_BYTES_INVALID; return 0; }
        if (remaining>length-at-1) { *status=MYL_BYTES_INVALID; return 0; }
        uint32_t point=first&((1u<<(6-remaining))-1u);
        for (unsigned index=0;index<remaining;++index) {
            unsigned char next=bytes[at+1+index];
            if ((next&0xc0)!=0x80) { *status=MYL_BYTES_INVALID; return 0; }
            point=(point<<6)|(next&63u);
        }
        if (point<minimum || point>0x10ffff || (point>=0xd800 && point<=0xdfff)) { *status=MYL_BYTES_INVALID; return 0; }
        at+=remaining+1;
        count+=1;
    }
    *status=MYL_BYTES_OK;
    return count;
}
int64_t myl_native_bytes_scalar_count_range(const myl_native_bytes *input, int64_t start, int64_t end, int *status) {
    size_t first=endpoint(input->length,start), last=endpoint(input->length,end);
    size_t count=last>first ? last-first : 0;
    return scalar_count((const unsigned char *)input->storage+first,count,status);
}
const unsigned char *myl_native_bytes_range(const myl_native_bytes *input, int64_t start, int64_t end, size_t *length) {
    size_t first=endpoint(input->length,start), last=endpoint(input->length,end);
    *length=last>first ? last-first : 0;
    return input->storage ? (const unsigned char *)input->storage+first : NULL;
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
/* The first index of a contiguous subsequence, or -1 when it is absent. An empty
   needle matches at index zero. The one-octet and longer cases hand the scan to
   the libc bulk primitives, so a candidate position costs one comparison inside
   `memchr`/`memmem` rather than a `memcmp` call from this loop. */
int64_t myl_native_bytes_find(const myl_native_bytes *input, const myl_native_bytes *needle) {
    if (needle->length>input->length) return -1;
    const unsigned char *bytes=input->storage;
    if (!needle->length) return 0;
    const unsigned char *found;
    if (needle->length==1) found=memchr(bytes,((const unsigned char *)needle->storage)[0],input->length);
    else found=memmem(bytes,input->length,needle->storage,needle->length);
    return found ? (int64_t)(found-bytes) : -1;
}
/* The first index at or after `start` of any octet in the set `values`, or -1.
   `values` is a set, not a sequence: an empty one finds nothing and a repeated
   octet costs one bit. A one-octet set is exactly `memchr`; a wider set builds a
   256-bit membership table on the stack and scans the remaining octets with it,
   so the search itself is a load, a shift and a test per octet. `start` clamps
   negative to zero and a start at or past the end finds nothing, so this is a
   search and never traps where an indexed read would. */
int64_t myl_native_bytes_find_any(const myl_native_bytes *input, const myl_native_bytes *values, int64_t start) {
    size_t length=input->length;
    size_t at = start<0 ? 0 : ((uint64_t)start>length ? length : (size_t)start);
    if (at>=length || !values->length) return -1;
    const unsigned char *bytes=input->storage;
    const unsigned char *set=values->storage;
    if (values->length==1) {
        const unsigned char *found=memchr(bytes+at,set[0],length-at);
        return found ? (int64_t)(found-bytes) : -1;
    }
    uint64_t members[4]={0,0,0,0};
    for (size_t i=0;i<values->length;i++) members[set[i]>>6]|=(uint64_t)1<<(set[i]&63);
    for (size_t i=at;i<length;i++) if (members[bytes[i]>>6]>>(bytes[i]&63)&1) return (int64_t)i;
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
/* The six octets Python's `bytes.split()` treats as whitespace: space, tab,
   line feed, carriage return, vertical tab and form feed. */
static int byte_space(unsigned char value) {
    return value==' ' || value=='\t' || value=='\n' || value=='\r' || value==0x0b || value==0x0c;
}
/* Python's no-argument byte split: break the receiver on maximal runs of ASCII
   whitespace and keep only the nonempty pieces, so leading, trailing and
   doubled whitespace produce no empty byte string. */
myl_native_list *myl_native_bytes_split_whitespace(myl_native_heap *heap, myl_native_bytes *input) {
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&input,&pointer_type);
    myl_native_list *result=myl_native_list_new(heap,&pointer_type,0);
    myl_native_root_push(heap,&b,&result,&pointer_type);
    if (result) {
        const unsigned char *octets=input->storage;
        size_t cursor=0;
        while (cursor<input->length) {
            while (cursor<input->length && byte_space(octets[cursor])) cursor++;
            size_t start=cursor;
            while (cursor<input->length && !byte_space(octets[cursor])) cursor++;
            if (start==cursor) break;
            myl_native_bytes *piece=copy_range(heap,input,start,cursor-start);
            if (!piece || !myl_native_list_append(heap,result,&piece)) { result=NULL; break; }
        }
    }
    myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
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
/* One managed byte string can hold spare capacity beyond its length: `length` is
   what every reader sees and `capacity` is what its backing can hold. These
   entry points append into that spare capacity and double it when it runs out,
   so appending N octets performs O(log N) growth allocations and no allocation
   per appended fragment. Byte-string identity is stable across growth, which is
   what lets one managed object be mutated through the ordinary byte surface. A
   frozen literal's storage belongs to the whole image, so a mutating entry point
   refuses an immortal receiver instead of writing storage the image owns. */
/* Whether this payload is shared frozen storage rather than one heap object. */
static int buffer_frozen(const myl_native_heap *heap, const myl_native_bytes *buffer) {
    return myl_native_object_immortal(heap,buffer);
}
/* Grow the backing to hold `needed` octets. The first block is one cache line
   and later blocks double, so the count of growth allocations stays logarithmic.
   The grown block joins the buffer's own arena, so an append performed inside a
   younger arena never leaves an older buffer owning storage about to be
   bulk released. */
static int buffer_grow(myl_native_heap *heap, myl_native_bytes *buffer, size_t needed) {
    if (needed<=buffer->capacity) return 1;
    size_t capacity=buffer->capacity<64 ? 64 : buffer->capacity;
    while (capacity<needed) {
        if (capacity>SIZE_MAX/2) return 0;
        capacity*=2;
    }
    void *storage=myl_native_heap_alloc_at(heap,buffer->element,capacity,myl_native_object_region(heap,buffer));
    if (!storage) return 0;
    if (buffer->length) memcpy(storage,buffer->storage,buffer->length);
    buffer->storage=storage;
    buffer->capacity=capacity;
    return 1;
}
/* Grow the buffer while it and one companion value stay reachable, because the
   growth allocation may collect before this call stores the new storage. Room
   that is already reserved allocates nothing, so it collects nothing and needs
   no roots: a capacity-sufficient append costs one test here instead of two
   root records on every call. */
static int buffer_grow_rooted(myl_native_heap *heap, myl_native_bytes *buffer, void *companion, size_t needed) {
    if (needed<=buffer->capacity) return 1;
    myl_native_root buffer_root, companion_root;
    myl_native_root_push(heap,&buffer_root,&buffer,&pointer_type);
    if (companion) myl_native_root_push(heap,&companion_root,companion,&pointer_type);
    int grown=buffer_grow(heap,buffer,needed);
    if (companion) myl_native_root_pop(heap,&companion_root);
    myl_native_root_pop(heap,&buffer_root);
    return grown;
}
int myl_native_bytes_buffer_reserve(myl_native_heap *heap, myl_native_bytes *buffer, int64_t extra) {
    if (extra<0) return MYL_BYTES_REFUSED;
    if (buffer_frozen(heap,buffer)) return extra==0 ? MYL_BYTES_WROTE : MYL_BYTES_REFUSED;
    if ((uint64_t)extra>SIZE_MAX-buffer->length) return MYL_BYTES_FAILED;
    if (!buffer_grow_rooted(heap,buffer,NULL,buffer->length+(size_t)extra)) return MYL_BYTES_FAILED;
    return MYL_BYTES_WROTE;
}
int myl_native_bytes_buffer_append_byte(myl_native_heap *heap, myl_native_bytes *buffer, int64_t value) {
    if (value<0 || value>255) return MYL_BYTES_REFUSED;
    if (buffer_frozen(heap,buffer)) return MYL_BYTES_REFUSED;
    if (buffer->length==SIZE_MAX) return MYL_BYTES_FAILED;
    if (!buffer_grow_rooted(heap,buffer,NULL,buffer->length+1)) return MYL_BYTES_FAILED;
    ((unsigned char *)buffer->storage)[buffer->length++]=(unsigned char)value;
    return MYL_BYTES_WROTE;
}
int myl_native_bytes_buffer_append_range(myl_native_heap *heap, myl_native_bytes *buffer, myl_native_bytes *data, int64_t start, int64_t end) {
    if (start<0 || end<start || (uint64_t)end>data->length) return MYL_BYTES_REFUSED;
    if (buffer_frozen(heap,buffer)) return MYL_BYTES_REFUSED;
    size_t count=(size_t)(end-start);
    if (!count) return MYL_BYTES_WROTE;
    if (count>SIZE_MAX-buffer->length) return MYL_BYTES_FAILED;
    if (!buffer_grow_rooted(heap,buffer,&data,buffer->length+count)) return MYL_BYTES_FAILED;
    /* `data` may be the buffer itself. Growth reallocates the buffer's backing,
       so the source is read back through the rooted pointer afterwards; the
       destination is always the end, past every copied octet, so the two ranges
       never overlap even then. */
    memcpy((unsigned char *)buffer->storage+buffer->length,(const unsigned char *)data->storage+(size_t)start,count);
    buffer->length+=count;
    return MYL_BYTES_WROTE;
}
int myl_native_bytes_buffer_append_utf8(myl_native_heap *heap, myl_native_bytes *buffer, myl_native_text *text) {
    if (buffer_frozen(heap,buffer)) return MYL_BYTES_REFUSED;
    size_t required=myl_native_text_utf8(text,NULL,0);
    if (required==SIZE_MAX || required>SIZE_MAX-buffer->length) return MYL_BYTES_FAILED;
    if (!required) return MYL_BYTES_WROTE;
    if (!buffer_grow_rooted(heap,buffer,&text,buffer->length+required)) return MYL_BYTES_FAILED;
    myl_native_text_utf8(text,(unsigned char *)buffer->storage+buffer->length,buffer->capacity-buffer->length);
    buffer->length+=required;
    return MYL_BYTES_WROTE;
}
/* Decimal spelling of one signed integer, written least significant digit first
   and reversed in place. `-(value+1)+1` is the magnitude in unsigned
   arithmetic, so the minimum signed value formats without overflowing. */
static size_t decimal_digits(unsigned char *digits, int64_t value) {
    unsigned char *at=digits;
    uint64_t magnitude=value<0 ? (uint64_t)(-(value+1))+1 : (uint64_t)value;
    do { *at++=(unsigned char)('0'+magnitude%10); magnitude/=10; } while (magnitude);
    if (value<0) *at++='-';
    for (unsigned char *left=digits,*right=at-1;left<right;left++,right--) {
        unsigned char held=*left; *left=*right; *right=held;
    }
    return (size_t)(at-digits);
}
int myl_native_bytes_buffer_append_raw(myl_native_heap *heap, myl_native_bytes *buffer, const unsigned char *data, size_t count) {
    if (buffer_frozen(heap,buffer)) return MYL_BYTES_REFUSED;
    if (!count) return MYL_BYTES_WROTE;
    if (count>SIZE_MAX-buffer->length) return MYL_BYTES_FAILED;
    if (!buffer_grow_rooted(heap,buffer,NULL,buffer->length+count)) return MYL_BYTES_FAILED;
    memcpy((unsigned char *)buffer->storage+buffer->length,data,count);
    buffer->length+=count;
    return MYL_BYTES_WROTE;
}
int myl_native_bytes_buffer_append_int(myl_native_heap *heap, myl_native_bytes *buffer, int64_t value) {
    if (buffer_frozen(heap,buffer)) return MYL_BYTES_REFUSED;
    unsigned char digits[20];
    size_t width=decimal_digits(digits,value);
    if (width>SIZE_MAX-buffer->length) return MYL_BYTES_FAILED;
    if (!buffer_grow_rooted(heap,buffer,NULL,buffer->length+width)) return MYL_BYTES_FAILED;
    memcpy((unsigned char *)buffer->storage+buffer->length,digits,width);
    buffer->length+=width;
    return MYL_BYTES_WROTE;
}
