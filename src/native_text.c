/* `memmem` is a GNU extension, so the feature macro has to precede <string.h>. */
#define _GNU_SOURCE
#include "native_text.h"
#include "native_rc_collections.h"
#include <stdlib.h>
#include <string.h>
/* A text object's payload is UTF-8 octets, so the collector has nothing to walk;
 * the element descriptor names a plain byte and switches tracing off. */
const myl_native_type myl_native_text_leaf = { .size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN,.trace_mode=MYL_NATIVE_TRACE_NONE };
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
/* A text's hash is cached in its header, because a dictionary hashes the same
 * key text once per lookup and a text can never change under it. */
uint32_t myl_native_text_hash(const myl_native_text *input) {
    myl_native_text *text=(myl_native_text *)input;
    if (text->flags&MYL_TEXT_HASHED) return text->hash;
    uint32_t folded=myl_native_octets_hash(myl_native_text_storage(text),text->bytes);
    /* A view's hash word is its offset, so its hash is recomputed per request. */
    if (text->flags&MYL_TEXT_VIEW) return folded;
    text->hash=folded;
    text->flags|=MYL_TEXT_HASHED;
    return folded;
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
    /* A text being built is owned, so its payload is the header's tail. */
    if (length) memcpy((unsigned char *)(text+1),bytes,length);
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
    myl_native_root_push(heap,&root,&list,&myl_rc_pointer_leaf);
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
/* The element descriptor a view is allocated with: a 32-byte record whose one
 * traced field is its owner, so the collector, the arena scan and the budget
 * see an ordinary one-pointer record and nothing else in the runtime has to know
 * a view exists. */
static const myl_native_field view_fields[]={
    { .offset=offsetof(myl_native_text_view,owner), .type=&myl_rc_pointer_leaf }
};
static const myl_native_scan_entry view_scan[]={
    { .offset=offsetof(myl_native_text_view,owner), .tag_offset=MYL_NATIVE_SCAN_ALWAYS }
};
const myl_native_type myl_native_text_view_type={
    .size=sizeof(myl_native_text_view), .alignment=_Alignof(myl_native_text_view),
    .kind=MYL_NATIVE_RECORD, .fields=view_fields, .field_count=1,
    .trace_fields=view_fields, .trace_field_count=1, .trace_mode=MYL_NATIVE_TRACE_FIELDS,
    .scan=view_scan, .scan_count=1, .rc_id=MYL_RC_ID_TEXT_VIEW
};
_Static_assert(sizeof(myl_native_text_view)==32, "a text view is four words");
static void rc_text_view_edges(myl_native_heap *heap, void *payload, size_t count) {
    (void)count;
    myl_rc_edge_release(heap,(void *)((myl_native_text_view *)payload)->owner);
}
static const myl_rc_shape rc_text_view_shape={.size=sizeof(myl_native_text_view),.kind=MYL_RC_SHAPE_NONE};
static myl_rc_status rc_text_clone_adapter(myl_native_heap *heap, const void *payload, unsigned region, void **out) {
    *out=myl_native_text_own_at(heap,(myl_native_text *)payload,region);
    return myl_rc_native_result(heap,*out);
}
static const myl_rc_descriptor rc_text_view_descriptor={.type=&myl_native_text_view_type,.shape=&rc_text_view_shape,.edges=rc_text_view_edges,.clone=rc_text_clone_adapter,.shell=rc_text_clone_adapter};
static const myl_rc_module rc_text_view_module={.abi=MYL_RC_ABI_VERSION,.descriptors=&rc_text_view_descriptor,.descriptor_count=1};
static myl_native_text *rc_text_result(myl_native_heap *heap, myl_native_text *text) {
    if (myl_rc_enabled(heap)) {
        myl_rc_status status=myl_rc_owner_acquire(heap,text);
        if (status!=MYL_RC_OK) { myl_rc_record_failure(heap,status); return NULL; }
    }
    return text;
}
/* Whether a piece of `count` octets at octet `offset` of `owner` is shared as a
 * view rather than copied; see MYL_TEXT_VIEW_MIN and MYL_TEXT_VIEW_RATIO. A
 * view's offset lives in the header's 32-bit hash word, so a piece that starts
 * beyond 4 GiB is copied, and a view never lives in a shallower arena than its
 * owner: the store barrier reads only one hop, so an owner younger than the
 * view would be released under it. The allocation depth is the innermost open
 * arena, which no live owner is younger than, so that test only guards the
 * invariant. */
static int shares(const myl_native_heap *heap, const myl_native_text *owner, size_t offset, size_t count) {
    if (count<MYL_TEXT_VIEW_MIN || offset>UINT32_MAX) return 0;
    if (count<owner->bytes/MYL_TEXT_VIEW_RATIO) return 0;
    return myl_native_header_region(owner)<=heap->region_depth;
}
/* One view of `count` octets of `input`'s owner from octet `offset` on. `input`
 * is rooted across the allocation because it is what keeps the owner alive
 * until the view records it. */
static myl_native_text *view(myl_native_heap *heap, myl_native_text *input, size_t offset, size_t count, size_t scalars, int plain) {
    if (myl_rc_enabled(heap)) {
        myl_rc_status status=myl_rc_module_register(heap,&rc_text_view_module);
        if (status!=MYL_RC_OK) { myl_rc_record_failure(heap,status); return NULL; }
    }
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&myl_rc_pointer_leaf);
    myl_native_text_view *result=myl_native_heap_alloc(heap,&myl_native_text_view_type,1);
    myl_native_root_pop(heap,&root);
    if (!result) return NULL;
    result->text.length=scalars;
    result->text.bytes=count;
    result->text.flags=MYL_TEXT_VIEW|(plain ? MYL_TEXT_ASCII : 0);
    result->text.hash=(uint32_t)offset;
    myl_native_text *owner=(myl_native_text *)myl_native_text_owner(input);
    if (myl_rc_enabled(heap) && !rc_text_result(heap,owner)) { myl_rc_owner_release(heap,result); return NULL; }
    result->owner=owner;
    return &result->text;
}
/* A copied piece: the `count` octets at `bytes`, which lie inside a receiver
 * whose ASCII flag is `ascii`. An ASCII receiver's piece is its own octet count
 * of scalars; any other piece counts the scalars of its own octets, and is
 * ASCII when every octet begins one. */
static inline myl_native_text *copy_piece(myl_native_heap *heap, const unsigned char *bytes, size_t count, int ascii) {
    size_t scalars=ascii ? count : scalars_in(bytes,count);
    return build(heap,bytes,count,scalars,ascii || scalars==count);
}
/* The shortest piece of `input` the policy could share: a piece below it is a
 * copy without further tests. Computed once per receiver by the loops that cut
 * one text into many pieces. */
static inline size_t share_threshold(const myl_native_text *input) {
    size_t quarter=myl_native_text_owner(input)->bytes/MYL_TEXT_VIEW_RATIO;
    return quarter>MYL_TEXT_VIEW_MIN ? quarter : MYL_TEXT_VIEW_MIN;
}
/* A piece long enough, against its owner, for the policy to share: the
 * receiver itself when it is the whole of it and already lives in the innermost
 * open arena, else a view of the receiver's owner or a copy, as `shares`
 * decides. Kept out of line so the copy path of `myl_native_text_substring`
 * stays small enough to inline into the loops that cut a text into many short
 * pieces. */
static __attribute__((noinline)) myl_native_text *long_piece(myl_native_heap *heap, myl_native_text *input, size_t from, size_t count) {
    if (count==input->bytes && myl_native_header_region(input)==heap->region_depth) return rc_text_result(heap,input);
    const myl_native_text *owner=myl_native_text_owner(input);
    const unsigned char *bytes=myl_native_text_storage(input);
    size_t offset=(size_t)(bytes+from-(const unsigned char *)(owner+1));
    int ascii=(int)(input->flags&MYL_TEXT_ASCII);
    if (!shares(heap,owner,offset,count)) return copy_piece(heap,bytes+from,count,ascii);
    size_t scalars=ascii ? count : scalars_in(bytes+from,count);
    return view(heap,input,offset,count,scalars,ascii || scalars==count);
}
/* A piece of non-ASCII text counts only its own octets: counting from the start
 * of the receiver at both ends made every split, splitlines and word split of a
 * non-ASCII text quadratic in its length. A piece whose every octet begins a
 * scalar is ASCII, and says so, so later operations on it index by octet. A
 * piece shorter than MYL_TEXT_VIEW_MIN octets is always a copy; a longer one may
 * be the receiver itself or a view (`long_piece`), and every form reads the same
 * octets. Every piece belongs to the innermost open arena, as a copy always did,
 * so the store barrier traps exactly where it did. The body is forced inline
 * into this file's slicing and splitting loops, where a copied piece used to be
 * inlined whole. */
static inline __attribute__((always_inline)) myl_native_text *cut(myl_native_heap *heap, myl_native_text *input, size_t from, size_t to) {
    const size_t count=to-from;
    /* Only a piece the policy could share leaves the inline copy path: a short
       field of a long line never pays for the call, and a piece shorter than the
       minimum never reads the receiver's header for it. */
    if (count>=MYL_TEXT_VIEW_MIN && count>=share_threshold(input)) return long_piece(heap,input,from,count);
    return copy_piece(heap,myl_native_text_storage(input)+from,count,(int)(input->flags&MYL_TEXT_ASCII));
}
myl_native_text *myl_native_text_substring(myl_native_heap *heap, myl_native_text *input, size_t from, size_t to) {
    return cut(heap,input,from,to);
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
    myl_native_root_push(heap,&root,&input,&myl_rc_pointer_leaf);
    myl_native_text *result=cut(heap,input,from,to);
    myl_native_root_pop(heap,&root);
    return result;
}
/* A text block's payload is raw octets: the same one-octet plain element the
 * heap's own block allocation uses, so an owned copy placed at an explicit depth
 * is charged and traced exactly as one built at the current depth. */
myl_native_text *myl_native_text_own_at(myl_native_heap *heap, myl_native_text *input, unsigned region) {
    if (!(input->flags&MYL_TEXT_VIEW)) return rc_text_result(heap,input);
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&myl_rc_pointer_leaf);
    myl_native_text *text=myl_native_heap_alloc_at(heap,&myl_rc_octet_leaf,sizeof(myl_native_text)+input->bytes,region);
    myl_native_root_pop(heap,&root);
    if (!text) return NULL;
    text->bytes=input->bytes;
    text->hash=0;
    if (input->bytes) memcpy((unsigned char *)(text+1),myl_native_text_storage(input),input->bytes);
    myl_native_text_publish(text,input->length,input->flags&MYL_TEXT_ASCII);
    return text;
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
    myl_native_root_push(heap,&root,&input,&myl_rc_pointer_leaf);
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
    myl_native_root_push(heap,&a,&left,&myl_rc_pointer_leaf);
    myl_native_root_push(heap,&b,&right,&myl_rc_pointer_leaf);
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
        if (scalar) return rc_text_result(heap,scalar);
    }
    return myl_native_text_substring(heap,input,at,cursor);
}
myl_native_text *myl_native_text_slice(myl_native_heap *heap, myl_native_text *input, int64_t start, int64_t end) {
    size_t first=endpoint(input->length,start), last=endpoint(input->length,end);
    return myl_native_text_copy(heap,input,first,last>first ? last-first : 0);
}
void myl_native_text_range(const myl_native_text *input, int64_t start, int64_t end, myl_native_text_span *span) {
    size_t first=endpoint(input->length,start), last=endpoint(input->length,end);
    size_t count=last>first ? last-first : 0;
    if (input->flags&MYL_TEXT_ASCII) { span->offset=first; span->bytes=count; return; }
    size_t from=myl_native_text_offset(input,first);
    span->offset=from;
    span->bytes=myl_native_text_offset(input,first+count)-from;
}
myl_native_text *myl_native_text_piece_at(myl_native_heap *heap, myl_native_text *input, const myl_native_text_span *span, unsigned region) {
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&myl_rc_pointer_leaf);
    myl_native_text *text=myl_native_heap_alloc_at(heap,&myl_rc_octet_leaf,sizeof(myl_native_text)+span->bytes,region);
    myl_native_root_pop(heap,&root);
    if (!text) return NULL;
    const unsigned char *bytes=myl_native_text_storage(input)+span->offset;
    text->bytes=span->bytes;
    text->hash=0;
    if (span->bytes) memcpy((unsigned char *)(text+1),bytes,span->bytes);
    int plain=(int)(input->flags&MYL_TEXT_ASCII);
    size_t scalars=plain ? span->bytes : scalars_in(bytes,span->bytes);
    myl_native_text_publish(text,scalars,plain || scalars==span->bytes);
    return text;
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
    myl_native_root_push(heap,&a,&input,&myl_rc_pointer_leaf);
    myl_native_root_push(heap,&b,&separator,&myl_rc_pointer_leaf);
    myl_native_list *result=myl_native_list_new(heap,&myl_rc_pointer_leaf,pieces);
    myl_native_root_push(heap,&c,&result,&myl_rc_pointer_leaf);
    if (result) {
        const unsigned char *haystack=myl_native_text_storage(input);
        const unsigned char *needle=myl_native_text_storage(separator);
        const size_t threshold=share_threshold(input);
        const int ascii=(int)(input->flags&MYL_TEXT_ASCII);
        size_t start=0;
        for (size_t left=pieces; left; left--) {
            size_t hit=left>1 ? myl_native_octets_find(haystack+start,input->bytes-start,needle,width) : SIZE_MAX;
            size_t end=hit==SIZE_MAX ? input->bytes : start+hit;
            myl_native_text *piece=end-start>=threshold ? long_piece(heap,input,start,end-start)
                                                         : copy_piece(heap,haystack+start,end-start,ascii);
            if (!piece) { if (myl_rc_enabled(heap)) myl_rc_list_abort_parts(heap,result,input); result=NULL; break; }
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
    myl_native_root_push(heap,&a,&separator,&myl_rc_pointer_leaf); myl_native_root_push(heap,&b,&list,&myl_rc_pointer_leaf);
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
