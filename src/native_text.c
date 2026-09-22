/* `memmem` is a GNU extension, so the feature macro has to precede <string.h>. */
#define _GNU_SOURCE
#include "native_text.h"
#include <stdlib.h>
#include <string.h>
/* A text object's payload is UTF-8 octets, so the collector has nothing to walk;
 * the element descriptor names a plain byte and switches tracing off. */
const myl_native_type myl_native_text_leaf = { .size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN,.trace_mode=MYL_NATIVE_TRACE_NONE };
static const myl_native_type pointer_type = { .size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER };
/* Decode one scalar from `bytes` at `*offset`, advancing it. Answers 1 for a
 * scalar, 0 at the end of the input and -1 for a malformed or non-shortest
 * encoding, an out-of-range scalar or a surrogate. */
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
const unsigned char *myl_native_text_payload(const myl_native_text *text) {
    return myl_native_text_storage(text);
}
/* Nonzero when `bytes` holds no octet at or above 0x80, a word at a time: the
 * scan that decides whether a text is ASCII is the only part of a conversion
 * that touches every input octet, so it cannot be a per-octet loop. */
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
/* Text is immutable and keeps its UTF-8 payload in the same allocation as its
 * header: 24 bytes of header plus one octet per scalar of source text, one
 * allocator round trip, and the collector never walks the payload because it
 * holds no pointer. `length` stays the scalar count so `len(text)` and scalar
 * indexing keep Python's meaning, and `bytes` lets every UTF-8 boundary copy
 * octets instead of re-encoding them. */
myl_native_text *myl_native_text_build(myl_native_heap *heap, size_t bytes) {
    if (bytes > (SIZE_MAX-sizeof(myl_native_text))) return NULL;
    myl_native_text *text=myl_native_heap_alloc_block(heap,sizeof(myl_native_text),bytes);
    if (!text) return NULL;
    text->length=0;
    text->bytes=bytes;
    text->flags=0;
    text->hash=0;
    return text;
}
void myl_native_text_publish(myl_native_text *text, size_t scalars, int plain) {
    text->length=scalars;
    /* Publishing replaces the flag word, so a hash cached before the payload was
     * written can never survive into the published value. */
    text->flags=plain ? MYL_TEXT_ASCII : 0;
}
/* The high and low halves of one full 64×64-bit product folded together, so
 * every output bit depends on every input bit of both factors. */
static inline uint64_t fold_multiply(uint64_t a, uint64_t b) {
    unsigned __int128 product=(unsigned __int128)a*b;
    return (uint64_t)product^(uint64_t)(product>>64);
}
#define TEXT_HASH_WORD 0xa0761d6478bd642fULL
#define TEXT_HASH_STATE 0xe7037ed1a0b428dbULL
/* The payload read eight octets at a time: each word is folded into a running
 * state by one multiply, a payload of at most eight octets is read as two
 * overlapping halves and folded once, and a longer one ends on the word that
 * finishes exactly at its last octet, so no read passes the payload and every
 * octet reaches the answer. The length seeds the state, so payloads of
 * different lengths start apart. Fixed constants, no seed: the runtime has no
 * sanctioned randomness and a dictionary must behave identically on every run.
 * The answer is cached in the header, because a dictionary hashes the same key
 * text once per lookup and a text can never change under it. */
uint32_t myl_native_text_hash(const myl_native_text *input) {
    myl_native_text *text=(myl_native_text *)input;
    if (text->flags&MYL_TEXT_HASHED) return text->hash;
    const unsigned char *bytes=myl_native_text_storage(text);
    size_t length=text->bytes;
    uint64_t state=0x243f6a8885a308d3ULL^length, hash;
    if (length<=8) {
        uint64_t low=0, high=0;
        if (length>=4) {
            uint32_t first, last;
            memcpy(&first,bytes,4); memcpy(&last,bytes+length-4,4);
            low=first; high=last;
        } else if (length) {
            low=(uint64_t)bytes[0]<<16|(uint64_t)bytes[length>>1]<<8|bytes[length-1];
        }
        hash=fold_multiply(low^TEXT_HASH_WORD,high^state^TEXT_HASH_STATE);
    } else {
        uint64_t word;
        for (size_t at=0;at+8<length;at+=8) {
            memcpy(&word,bytes+at,8);
            state=fold_multiply(word^TEXT_HASH_WORD,state^TEXT_HASH_STATE);
        }
        memcpy(&word,bytes+length-8,8);
        hash=fold_multiply(word^TEXT_HASH_WORD,state^TEXT_HASH_STATE);
    }
    text->hash=(uint32_t)(hash^(hash>>32));
    text->flags|=MYL_TEXT_HASHED;
    return text->hash;
}
/* Scalars in `bytes` and whether all of them are below 0x80, or -1 for a
 * malformed payload. Octets of a continuation byte never begin a scalar, so the
 * count is one per octet that is not `10xxxxxx`. */
static int measure(const unsigned char *bytes, size_t length, size_t *scalars, int *plain) {
    if (ascii(bytes,length)) { *scalars=length; *plain=1; return 1; }
    size_t offset=0, count=0;
    uint32_t point;
    int status;
    while ((status=decode(bytes,length,&offset,&point))>0) count++;
    if (status<0) return -1;
    *scalars=count; *plain=0;
    return 1;
}
/* Fresh text holding the `count` octets at `bytes`, already known to be valid
 * UTF-8 with `scalars` scalar values and `plain` naming the ASCII case. */
static myl_native_text *build(myl_native_heap *heap, const unsigned char *bytes, size_t length, size_t scalars, int plain) {
    myl_native_text *text=myl_native_text_build(heap,length);
    if (!text) return NULL;
    if (length) memcpy((unsigned char *)myl_native_text_storage(text),bytes,length);
    myl_native_text_publish(text,scalars,plain);
    return text;
}
myl_native_text *myl_native_text_from_utf8_checked(myl_native_heap *heap, const unsigned char *bytes, size_t length, int *invalid) {
    size_t scalars=0;
    int plain=0;
    *invalid=0;
    if (measure(bytes,length,&scalars,&plain)<0) { *invalid=1; return NULL; }
    return build(heap,bytes,length,scalars,plain);
}
myl_native_text *myl_native_text_from_utf8(myl_native_heap *heap, const unsigned char *bytes, size_t length) {
    int invalid=0;
    return myl_native_text_from_utf8_checked(heap,bytes,length,&invalid);
}
myl_native_text *myl_native_text_from_scalars(myl_native_heap *heap, const uint32_t *points, size_t count) {
    size_t length=0;
    for (size_t i=0;i<count;i++) {
        uint32_t point=points[i];
        size_t width;
        if (point<0x80) width=1;
        else if (point<0x800) width=2;
        else if (point<0x10000) { if (point>=0xd800 && point<=0xdfff) return NULL; width=3; }
        else if (point<=0x10ffff) width=4;
        else return NULL;
        if (width>SIZE_MAX-length) return NULL;
        length+=width;
    }
    myl_native_text *text=myl_native_text_build(heap,length);
    if (!text) return NULL;
    unsigned char *output=(unsigned char *)myl_native_text_storage(text);
    size_t at=0;
    for (size_t i=0;i<count;i++) {
        uint32_t point=points[i];
        if (point<0x80) output[at++]=(unsigned char)point;
        else if (point<0x800) { output[at++]=(unsigned char)(0xc0|(point>>6)); output[at++]=(unsigned char)(0x80|(point&63)); }
        else if (point<0x10000) { output[at++]=(unsigned char)(0xe0|(point>>12)); output[at++]=(unsigned char)(0x80|((point>>6)&63)); output[at++]=(unsigned char)(0x80|(point&63)); }
        else { output[at++]=(unsigned char)(0xf0|(point>>18)); output[at++]=(unsigned char)(0x80|((point>>12)&63)); output[at++]=(unsigned char)(0x80|((point>>6)&63)); output[at++]=(unsigned char)(0x80|(point&63)); }
    }
    myl_native_text_publish(text,count,ascii(output,length));
    return text;
}
myl_native_text *myl_native_text_from_points(myl_native_heap *heap, const myl_native_list *points) {
    const myl_native_list *list=points;
    myl_native_root root;
    myl_native_root_push(heap,&root,&list,&pointer_type);
    myl_native_text *text=myl_native_text_from_scalars(heap,list->storage,list->length);
    myl_native_root_pop(heap,&root);
    return text;
}
size_t myl_native_text_offset(const myl_native_text *text, size_t index) {
    if (text->flags&MYL_TEXT_ASCII) return index;
    const unsigned char *bytes=myl_native_text_storage(text);
    size_t at=0;
    while (index--) {
        at++;
        while (at<text->bytes && (bytes[at]&0xc0u)==0x80u) at++;
    }
    return at;
}
size_t myl_native_text_index(const myl_native_text *text, size_t at) {
    if (text->flags&MYL_TEXT_ASCII) return at;
    const unsigned char *bytes=myl_native_text_storage(text);
    size_t scalars=0;
    for (size_t i=0;i<at;i++) if ((bytes[i]&0xc0u)!=0x80u) scalars++;
    return scalars;
}
/* Scalars that begin in `count` octets of valid UTF-8: one per octet that is not
 * a continuation octet `10xxxxxx`. */
static size_t scalars_in(const unsigned char *bytes, size_t count) {
    size_t scalars=0;
    for (size_t i=0;i<count;i++) scalars+=(bytes[i]&0xc0u)!=0x80u;
    return scalars;
}
/* A piece of non-ASCII text counts only its own octets: counting from the start
 * of the receiver at both ends made every split, splitlines and word split of a
 * non-ASCII text quadratic in its length. A piece whose every octet begins a
 * scalar is ASCII, and says so, so later operations on it index by octet. */
myl_native_text *myl_native_text_substring(myl_native_heap *heap, myl_native_text *input, size_t from, size_t to) {
    const unsigned char *bytes=myl_native_text_storage(input);
    int plain=input->flags&MYL_TEXT_ASCII;
    size_t scalars=plain ? to-from : scalars_in(bytes+from,to-from);
    return build(heap,bytes+from,to-from,scalars,plain || scalars==to-from);
}
uint32_t myl_native_text_point_at(const myl_native_text *text, size_t index) {
    size_t at=myl_native_text_offset(text,index);
    uint32_t point=0;
    (void)decode(myl_native_text_storage(text),text->bytes,&at,&point);
    return point;
}
myl_native_text *myl_native_text_copy(myl_native_heap *heap, myl_native_text *input, size_t start, size_t count) {
    size_t from=myl_native_text_offset(input,start), to=myl_native_text_offset(input,start+count);
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *result=myl_native_text_substring(heap,input,from,to);
    myl_native_root_pop(heap,&root);
    return result;
}
myl_native_text *myl_native_text_clone(myl_native_heap *heap, const myl_native_text *input) {
    return build(heap,myl_native_text_storage(input),input->bytes,input->length,input->flags&MYL_TEXT_ASCII);
}
/* Gather `count` scalars of a non-ASCII text, `step` apart from `first`, into one
 * fresh text. One forward walk records where each selected scalar starts, so the
 * gather costs a pass over the payload rather than a walk per scalar. */
static myl_native_text *gather(myl_native_heap *heap, const myl_native_text *input, int64_t first, uint64_t count, int64_t step) {
    const unsigned char *bytes=myl_native_text_storage(input);
    size_t *offsets=malloc((size_t)count*sizeof(size_t));
    if (!offsets) return NULL;
    /* The selected scalars are `lowest`, `lowest+magnitude`, ... in payload
       order, so one countdown visits each of them in the walk below and records
       it under its own place in the answer: a negative step answers its
       selection reversed, so the walk fills the record back to front. */
    const int64_t magnitude=step>0?step:-step;
    int64_t next=step>0?first:first-(int64_t)(count-1)*magnitude;
    int64_t place=step>0?0:(int64_t)count-1;
    size_t octets=0, at=0;
    int plain=1;
    uint64_t found=0;
    int64_t index=0;
    while (found<count) {
        size_t width=1;
        while (at+width<input->bytes && (bytes[at+width]&0xc0u)==0x80u) width++;
        if (index==next) {
            offsets[place]=at;
            octets+=width;
            if (width>1) plain=0;
            next+=magnitude;
            place+=step>0?1:-1;
            found++;
        }
        at+=width; index++;
    }
    myl_native_text *result=myl_native_text_build(heap,octets);
    if (result) {
        unsigned char *output=(unsigned char *)myl_native_text_storage(result);
        size_t written=0;
        for (uint64_t i=0;i<count;i++) {
            size_t from=offsets[i], width=1;
            while (from+width<input->bytes && (bytes[from+width]&0xc0u)==0x80u) width++;
            memcpy(output+written,bytes+from,width);
            written+=width;
        }
        myl_native_text_publish(result,(size_t)count,plain);
    }
    free(offsets);
    return result;
}
myl_native_text *myl_native_text_slice_step(myl_native_heap *heap, myl_native_text *input, int64_t start, int64_t stop, int64_t step) {
    if (!step) return NULL;
    const int64_t length=(int64_t)input->length;
    int64_t first=myl_native_slice_start(length,start,step);
    const int64_t last=myl_native_slice_stop(length,stop,step);
    uint64_t count=myl_native_slice_count(first,last,step);
    /* An adjusted start outside the receiver selects nothing, which is also what
       the arithmetic above answers for every other endpoint combination. */
    if (first<0 || first>=length) count=0;
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *result=NULL;
    if (!count) result=myl_native_text_substring(heap,input,0,0);
    else if (input->flags&MYL_TEXT_ASCII) {
        /* A scalar offset is a byte offset, so the gather needs no walk. */
        result=myl_native_text_build(heap,(size_t)count);
        if (result) {
            unsigned char *output=(unsigned char *)myl_native_text_storage(result);
            const unsigned char *bytes=myl_native_text_storage(input);
            for (uint64_t i=0;i<count;i++) output[i]=bytes[first+(int64_t)i*step];
            myl_native_text_publish(result,(size_t)count,1);
        }
    } else result=gather(heap,input,first,count,step);
    myl_native_root_pop(heap,&root);
    return result;
}
myl_native_text *myl_native_text_concat(myl_native_heap *heap, myl_native_text *left, myl_native_text *right) {
    if (left->bytes>SIZE_MAX-right->bytes) return NULL;
    size_t bytes=left->bytes+right->bytes;
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&left,&pointer_type);
    myl_native_root_push(heap,&b,&right,&pointer_type);
    myl_native_text *result=myl_native_text_build(heap,bytes);
    if (result) {
        unsigned char *output=(unsigned char *)myl_native_text_storage(result);
        if (left->bytes) memcpy(output,myl_native_text_storage(left),left->bytes);
        if (right->bytes) memcpy(output+left->bytes,myl_native_text_storage(right),right->bytes);
        myl_native_text_publish(result,left->length+right->length,left->flags&right->flags&MYL_TEXT_ASCII);
    }
    myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
static size_t endpoint(size_t length, int64_t value) {
    if (value>=0) return (uint64_t)value>length ? length : (size_t)value;
    uint64_t distance=(uint64_t)(-(value+1))+1;
    return distance>length ? 0 : length-(size_t)distance;
}
/* Return the shared immortal one-octet text for an ASCII code point, building
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
            unsigned char octet=(unsigned char)code;
            myl_native_text *text=myl_native_text_from_utf8(heap,&octet,1);
            if (!text) { heap->region_depth=depth; return NULL; }
            heap->text_scalars[code]=text;
        }
        heap->region_depth=depth;
    }
    return heap->text_scalars[point];
}
myl_native_text *myl_native_text_at(myl_native_heap *heap, myl_native_text *input, int64_t index) {
    if (index<0 && (uint64_t)(-(index+1))+1>input->length) return NULL;
    if (index>=0 && (uint64_t)index>=input->length) return NULL;
    size_t at=myl_native_text_offset(input,endpoint(input->length,index));
    uint32_t point=0;
    size_t cursor=at;
    (void)decode(myl_native_text_storage(input),input->bytes,&cursor,&point);
    if (point<128) {
        myl_native_text *scalar=ascii_scalar(heap,point);
        if (scalar) return scalar;
    }
    return myl_native_text_substring(heap,input,at,cursor);
}
myl_native_text *myl_native_text_slice(myl_native_heap *heap, myl_native_text *input, int64_t start, int64_t end) {
    size_t first=endpoint(input->length,start), last=endpoint(input->length,end);
    return myl_native_text_copy(heap,input,first,last>first ? last-first : 0);
}
int myl_native_text_equal(const myl_native_text *a, const myl_native_text *b) {
    return a->bytes==b->bytes && (!a->bytes || !memcmp(myl_native_text_storage(a),myl_native_text_storage(b),a->bytes));
}
int myl_native_text_compare(const myl_native_text *a, const myl_native_text *b) {
    size_t count=a->bytes<b->bytes?a->bytes:b->bytes;
    int order=count?memcmp(myl_native_text_storage(a),myl_native_text_storage(b),count):0;
    if (order) return order<0?-1:1;
    return a->bytes<b->bytes?-1:a->bytes>b->bytes?1:0;
}
/* Whether `count` octets agree. The rest of a needle whose first octet already
 * matched is short in every search this runtime makes, so a loop that stops at
 * the first difference costs less than a `memcmp` call per candidate. */
static int same_octets(const unsigned char *left, const unsigned char *right, size_t count) {
    for (size_t i=0;i<count;i++) if (left[i]!=right[i]) return 0;
    return 1;
}
/* Candidates one search confirms in place before it hands the rest of the
 * haystack to `memmem`. A first octet that keeps recurring without a match (a
 * needle `ab` in a run of `a`) would otherwise cost one `memchr` call per octet;
 * `memmem`'s own scan stays linear however the octets repeat, and a search that
 * finds its match within this many candidates never pays `memmem`'s setup. */
enum { SCAN_CANDIDATES = 8 };
size_t myl_native_octets_find(const unsigned char *haystack, size_t length, const unsigned char *needle, size_t count) {
    if (!count) return 0;
    if (count>length) return SIZE_MAX;
    if (count==1) {
        const unsigned char *found=memchr(haystack,needle[0],length);
        return found ? (size_t)(found-haystack) : SIZE_MAX;
    }
    /* A match can begin no later than `last`, so every candidate the loop
       confirms has `count` octets behind it. */
    const unsigned char *at=haystack, *last=haystack+(length-count);
    for (int tried=0; tried<SCAN_CANDIDATES; tried++) {
        const unsigned char *candidate=memchr(at,needle[0],(size_t)(last-at)+1);
        if (!candidate) return SIZE_MAX;
        if (same_octets(candidate+1,needle+1,count-1)) return (size_t)(candidate-haystack);
        if (candidate==last) return SIZE_MAX;
        at=candidate+1;
    }
    const unsigned char *found=memmem(at,(size_t)(haystack+length-at),needle,count);
    return found ? (size_t)(found-haystack) : SIZE_MAX;
}
size_t myl_native_octets_count(const unsigned char *haystack, size_t length, const unsigned char *needle, size_t count) {
    if (!count || count>length) return 0;
    size_t found=0;
    if (count==1) {
        /* One octet cannot overlap itself, so its count is a plain tally, which
           the compiler vectorizes; a 32-bit block sum keeps the lanes wide. */
        const unsigned char octet=needle[0];
        for (size_t at=0; at<length;) {
            size_t block=length-at<65536 ? length-at : 65536;
            uint32_t tally=0;
            for (size_t i=0;i<block;i++) tally+=haystack[at+i]==octet;
            found+=tally;
            at+=block;
        }
        return found;
    }
    for (size_t at=0;;) {
        size_t hit=myl_native_octets_find(haystack+at,length-at,needle,count);
        if (hit==SIZE_MAX) return found;
        found++;
        at+=hit+count;
    }
}
size_t myl_native_text_find_bytes(const myl_native_text *input, const myl_native_text *needle) {
    return myl_native_octets_find(myl_native_text_storage(input),input->bytes,myl_native_text_storage(needle),needle->bytes);
}
int myl_native_text_contains(const myl_native_text *input, const myl_native_text *needle) {
    return myl_native_text_find_bytes(input,needle)!=SIZE_MAX;
}
/* The separator is found by the bulk search, never by a comparison at every
 * octet, and the cuts are counted first so the result list is allocated once at
 * its final length: filling it never grows it, so no piece needs a root of its
 * own between its allocation and its store. */
myl_native_list *myl_native_text_split(myl_native_heap *heap, myl_native_text *input, myl_native_text *separator) {
    if (!separator->length) return NULL;
    const size_t width=separator->bytes;
    size_t pieces=myl_native_octets_count(myl_native_text_storage(input),input->bytes,myl_native_text_storage(separator),width)+1;
    myl_native_root a,b,c;
    myl_native_root_push(heap,&a,&input,&pointer_type);
    myl_native_root_push(heap,&b,&separator,&pointer_type);
    myl_native_list *result=myl_native_list_new(heap,&pointer_type,pieces);
    myl_native_root_push(heap,&c,&result,&pointer_type);
    if (result) {
        const unsigned char *haystack=myl_native_text_storage(input);
        const unsigned char *needle=myl_native_text_storage(separator);
        size_t start=0;
        for (size_t left=pieces; left; left--) {
            size_t hit=left>1 ? myl_native_octets_find(haystack+start,input->bytes-start,needle,width) : SIZE_MAX;
            size_t end=hit==SIZE_MAX ? input->bytes : start+hit;
            myl_native_text *piece=myl_native_text_substring(heap,input,start,end);
            if (!piece) { result=NULL; break; }
            /* The reserved slot is written in place, exactly as an append that
               finds room writes it: the collector traces the whole reservation,
               so the piece is reachable from here on. */
            ((myl_native_text **)result->storage)[result->length++]=piece;
            result->generation++;
            if (end==input->bytes) break;
            start=end+width;
        }
    }
    myl_native_root_pop(heap,&c); myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
myl_native_text *myl_native_text_join(myl_native_heap *heap, myl_native_text *separator, myl_native_list *list) {
    size_t count=0;
    myl_native_text **items=list->storage;
    for (size_t i=0;i<list->length;i++) {
        if (items[i]->bytes>SIZE_MAX-count) return NULL;
        count+=items[i]->bytes;
        if (i) { if (separator->bytes>SIZE_MAX-count) return NULL; count+=separator->bytes; }
    }
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&separator,&pointer_type); myl_native_root_push(heap,&b,&list,&pointer_type);
    myl_native_text *result=myl_native_text_build(heap,count);
    if (result) {
        unsigned char *output=(unsigned char *)myl_native_text_storage(result);
        int plain=separator->flags&MYL_TEXT_ASCII;
        size_t at=0, scalars=0;
        for (size_t i=0;i<list->length;i++) {
            if (i && separator->bytes) { memcpy(output+at,myl_native_text_storage(separator),separator->bytes); at+=separator->bytes; scalars+=separator->length; }
            if (items[i]->bytes) memcpy(output+at,myl_native_text_storage(items[i]),items[i]->bytes);
            at+=items[i]->bytes;
            scalars+=items[i]->length;
            plain&=items[i]->flags&MYL_TEXT_ASCII;
        }
        myl_native_text_publish(result,scalars,plain);
    }
    myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
size_t myl_native_text_utf8(const myl_native_text *text, unsigned char *output, size_t capacity) {
    if (!output || capacity<text->bytes) return text->bytes;
    if (text->bytes) memcpy(output,myl_native_text_storage(text),text->bytes);
    return text->bytes;
}
