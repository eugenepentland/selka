/* `memmem` is a GNU extension, so the feature macro has to precede <string.h>. */
#define _GNU_SOURCE
#include "native_text.h"
#include "native_rc_collections.h"
#include <stdlib.h>
#include <string.h>
/* A text object's payload is UTF-8 octets, so the collector has nothing to walk;
 * the element descriptor names a plain byte and switches tracing off. */
const myl_native_type myl_native_text_leaf = { .size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN,.trace_mode=MYL_NATIVE_TRACE_NONE };
static const myl_native_type pointer_type = { .size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER };
#ifdef MYL_TEXT_STEPS
size_t myl_native_text_steps;
#define STEPS(count) (myl_native_text_steps+=(count))
#else
#define STEPS(count) ((void)(count))
#endif
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
/* The position index behind an indexed text's payload (TEXT-INDEX-1): the last
 * scalar a lookup found and the octet where it begins, then the sample table,
 * whose entry `k-1` is the octet where scalar `k * MYL_TEXT_SAMPLE_STRIDE`
 * begins. The table is filled by the first lookup that no end and no earlier
 * lookup is near, so a text that is only ever scanned in order never pays for
 * it. Both parts are functions of the immutable payload, so filling or moving
 * them is invisible to every reader and to every alias of the text. */
typedef struct {
    uint64_t scalar, octet;
    uint32_t sample[];
} text_index;
/* Sample entries an indexed text of `scalars` scalars holds: one for every
 * multiple of the stride below its length. */
static size_t samples_in(size_t scalars) {
    return scalars ? (scalars-1)/MYL_TEXT_SAMPLE_STRIDE : 0;
}
/* Octets the index takes behind a payload, a multiple of eight. */
static size_t index_octets(size_t scalars) {
    return (sizeof(text_index)+samples_in(scalars)*sizeof(uint32_t)+7)&~(size_t)7;
}
/* Whether a text of `bytes` octets holding `scalars` scalars is given an index:
 * it is not ASCII, it is long enough to repay one, and its octet offsets fit
 * the table's 32-bit entries. */
static int indexable(size_t bytes, size_t scalars) {
    return scalars!=bytes && bytes>=MYL_TEXT_INDEX_MIN && bytes<=UINT32_MAX;
}
/* The index of an indexed text: the block's tail, eight-aligned behind the
 * payload. */
static text_index *index_of(const myl_native_text *text) {
    return (text_index *)((unsigned char *)(text+1)+((text->bytes+7)&~(size_t)7));
}
myl_native_text *myl_native_text_build_scalars(myl_native_heap *heap, size_t bytes, size_t scalars) {
    if (!indexable(bytes,scalars)) return myl_native_text_build(heap,bytes);
    myl_native_text *text=myl_native_heap_alloc_block(heap,sizeof(myl_native_text),((bytes+7)&~(size_t)7)+index_octets(scalars));
    if (!text) return NULL;
    /* The promised scalar count waits in `length` for the publish to confirm. */
    text->length=scalars;
    text->bytes=bytes;
    text->flags=MYL_TEXT_INDEXED;
    text->hash=0;
    return text;
}
/* Publish a text that is not ASCII: a block built with an index keeps it only
 * when it is published as the non-ASCII text it was sized for. */
static __attribute__((noinline)) void publish_wide(myl_native_text *text, size_t scalars) {
    const int indexed=(text->flags&MYL_TEXT_INDEXED) && text->length==scalars;
    text->length=scalars;
    text->flags=indexed ? MYL_TEXT_INDEXED : 0;
    if (indexed) {
        text_index *index=index_of(text);
        index->scalar=0;
        index->octet=0;
    }
}
void myl_native_text_publish(myl_native_text *text, size_t scalars, int plain) {
    /* Publishing replaces the flag word, so a hash cached before the payload was
     * written can never survive into the published value. A text whose scalar
     * count is its octet count is ASCII, whoever built it. */
    if (plain || scalars==text->bytes) {
        text->length=scalars;
        text->flags=MYL_TEXT_ASCII;
        return;
    }
    publish_wide(text,scalars);
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
    /* A text with a few non-ASCII scalars is mostly ASCII: whole words of it are
     * counted without decoding, and only the words a multi-octet scalar touches
     * are decoded one scalar at a time. */
    for (;;) {
        for (; offset+sizeof(uint64_t)<=length; offset+=sizeof(uint64_t), count+=sizeof(uint64_t)) {
            uint64_t word;
            memcpy(&word,bytes+offset,sizeof word);
            if (word&UINT64_C(0x8080808080808080)) break;
        }
        status=decode(bytes,length,&offset,&point);
        if (status<=0) break;
        count++;
    }
    if (status<0) return -1;
    *scalars=count; *plain=0;
    return 1;
}
/* Fresh text holding the `length` octets at `bytes`, already known to be valid
 * UTF-8 with `scalars` scalar values, that is not ASCII: given the position
 * index its shape carries. Out of line, so the ASCII path of `build` below stays
 * exactly the small body its callers inline. */
static __attribute__((noinline)) myl_native_text *build_wide(myl_native_heap *heap, const unsigned char *bytes, size_t length, size_t scalars) {
    myl_native_text *text=myl_native_text_build_scalars(heap,length,scalars);
    if (!text) return NULL;
    /* A text being built is owned, so its payload is the header's tail. */
    if (length) memcpy((unsigned char *)(text+1),bytes,length);
    myl_native_text_publish(text,scalars,0);
    return text;
}
/* Fresh text holding the `count` octets at `bytes`, already known to be valid
 * UTF-8 with `scalars` scalar values and `plain` naming the ASCII case. */
static inline myl_native_text *build(myl_native_heap *heap, const unsigned char *bytes, size_t length, size_t scalars, int plain) {
    if (!plain) return build_wide(heap,bytes,length,scalars);
    myl_native_text *text=myl_native_text_build(heap,length);
    if (!text) return NULL;
    if (length) memcpy((unsigned char *)(text+1),bytes,length);
    text->length=scalars;
    text->flags=MYL_TEXT_ASCII;
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
    myl_native_text *text=myl_native_text_build_scalars(heap,length,count);
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
/* Scalars that begin in the eight octets at `at`: one per octet that is not a
 * continuation octet `10xxxxxx`. A continuation octet has bit 7 set and bit 6
 * clear, so one mask finds them all and one multiply adds the eight flags. */
static inline size_t word_starts(const unsigned char *at) {
    uint64_t word;
    memcpy(&word,at,sizeof word);
    const uint64_t continuation=word&~(word<<1)&UINT64_C(0x8080808080808080);
    return 8-(size_t)(((continuation>>7)*UINT64_C(0x0101010101010101))>>56);
}
/* Scalars that begin in octets `[from, to)` of valid UTF-8, a word at a time. */
static size_t starts_in(const unsigned char *bytes, size_t from, size_t to) {
    size_t scalars=0, at=from;
    STEPS(to-from);
    for (; at+8<=to; at+=8) scalars+=word_starts(bytes+at);
    for (; at<to; at++) scalars+=(bytes[at]&0xc0u)!=0x80u;
    return scalars;
}
/* The octet where the scalar `count` scalars after the one beginning at octet
 * `at` begins, or `length` when the payload ends first. Whole words are skipped
 * while the target lies beyond them, so a long walk costs an eighth of its
 * octets in steps. */
static size_t advance(const unsigned char *bytes, size_t length, size_t at, size_t count) {
    size_t position=at+1;
    if (!count) return at;
    while (count>=8 && position+8<=length) {
        const size_t starts=word_starts(bytes+position);
        if (starts>=count) break;
        count-=starts;
        position+=8;
    }
    for (; position<length; position++) {
        if ((bytes[position]&0xc0u)!=0x80u && !--count) { STEPS(position-at); return position; }
    }
    STEPS(position-at);
    return length;
}
/* The octet where the scalar `count` scalars before the one beginning at octet
 * `at` (or before the payload's end, when `at` is its length) begins. */
static size_t retreat(const unsigned char *bytes, size_t at, size_t count) {
    const size_t origin=at;
    while (count--) {
        do at--; while ((bytes[at]&0xc0u)==0x80u);
    }
    STEPS(origin-at);
    return at;
}
/* A scalar index and the octet where that scalar begins: a place a walk starts
 * from. */
typedef struct {
    size_t scalar, octet;
} anchor;
/* `best` becomes `candidate` when it lies closer to scalar `index` than every
 * anchor considered so far, `gap` scalars away. */
static void nearer(anchor *best, size_t *gap, size_t index, anchor candidate) {
    const size_t distance=candidate.scalar>index ? candidate.scalar-index : index-candidate.scalar;
    if (distance>=*gap) return;
    *best=candidate;
    *gap=distance;
}
/* How far, in scalars, the nearest anchor of an unsampled text may be before a
 * lookup fills the sample table instead of walking there, and how far, in
 * octets, a byte offset may be from either end before it is converted through
 * the table. A text that is scanned in order, or only ever probed near its
 * ends or its last probe, never reaches them. */
#define LAZY_SCALARS (8*MYL_TEXT_SAMPLE_STRIDE)
#define LAZY_OCTETS ((size_t)1024)
/* Fill the sample table of an indexed text: one pass over its payload. */
static __attribute__((noinline)) void fill_samples(myl_native_text *text) {
    text_index *index=index_of(text);
    const unsigned char *bytes=myl_native_text_storage(text);
    const size_t count=samples_in(text->length);
    size_t at=0;
    for (size_t entry=0; entry<count; entry++) {
        at=advance(bytes,text->bytes,at,MYL_TEXT_SAMPLE_STRIDE);
        index->sample[entry]=(uint32_t)at;
    }
    text->flags|=MYL_TEXT_SAMPLED;
}
/* The octet where scalar `index`, which is below the length of an owned
 * non-ASCII text, begins: a walk from the nearest of the payload's two ends,
 * the last scalar an earlier lookup found, and the sample table entry nearest
 * the scalar. Only a lookup far from every one of them but the table fills it,
 * and every lookup of an indexed text records where it ended. */
static __attribute__((noinline)) size_t locate(myl_native_text *text, size_t index) {
    const unsigned char *bytes=myl_native_text_storage(text);
    anchor best={0,0};
    size_t gap=index;
    nearer(&best,&gap,index,(anchor){text->length,text->bytes});
    text_index *cache=NULL;
    if (text->flags&MYL_TEXT_INDEXED) {
        cache=index_of(text);
        nearer(&best,&gap,index,(anchor){(size_t)cache->scalar,(size_t)cache->octet});
        if (gap>LAZY_SCALARS && !(text->flags&MYL_TEXT_SAMPLED)) fill_samples(text);
        if (text->flags&MYL_TEXT_SAMPLED) {
            size_t entry=(index+MYL_TEXT_SAMPLE_STRIDE/2)/MYL_TEXT_SAMPLE_STRIDE;
            if (entry>samples_in(text->length)) entry=samples_in(text->length);
            if (entry) nearer(&best,&gap,index,(anchor){entry*MYL_TEXT_SAMPLE_STRIDE,cache->sample[entry-1]});
        }
    }
    const size_t at=best.scalar<=index ? advance(bytes,text->bytes,best.octet,index-best.scalar)
                                       : retreat(bytes,best.octet,best.scalar-index);
    if (cache) { cache->scalar=index; cache->octet=at; }
    return at;
}
/* The scalar that begins at octet `at`, a scalar boundary of an indexed text:
 * the sample table's last entry at or before it, then the scalars between. */
static __attribute__((noinline)) size_t index_at(myl_native_text *text, size_t at) {
    if (!(text->flags&MYL_TEXT_SAMPLED)) fill_samples(text);
    const text_index *index=index_of(text);
    size_t low=0, high=samples_in(text->length);
    while (low<high) {
        const size_t middle=(low+high+1)/2;
        if (index->sample[middle-1]<=at) low=middle; else high=middle-1;
    }
    const size_t base=low ? index->sample[low-1] : 0;
    return low*MYL_TEXT_SAMPLE_STRIDE+starts_in(myl_native_text_storage(text),base,at);
}
/* A view is located from its own ends while they are near, and otherwise by its
 * place in its owner: the scalar where the view begins is found once through the
 * owner's sample table, and the owner locates the scalar that many places on. A
 * view of an owner with no index walks from its nearer end. */
static __attribute__((noinline)) size_t locate_view(const myl_native_text *view, size_t index) {
    const myl_native_text *owner=((const myl_native_text_view *)view)->owner;
    const size_t base=view->hash, gap=index<view->length-index ? index : view->length-index;
    if (gap>MYL_TEXT_SAMPLE_STRIDE && (owner->flags&MYL_TEXT_INDEXED)) {
        myl_native_text *shared=(myl_native_text *)owner;
        return locate(shared,index_at(shared,base)+index)-base;
    }
    const unsigned char *bytes=myl_native_text_storage(view);
    return index<=view->length-index ? advance(bytes,view->bytes,0,index) : retreat(bytes,view->bytes,view->length-index);
}
/* The offset of scalar `index` of a text that is not ASCII. */
static __attribute__((noinline)) size_t offset_walk(const myl_native_text *text, size_t index) {
    if (index>=text->length) return text->bytes;
    if (text->flags&MYL_TEXT_VIEW) return locate_view(text,index);
    return locate((myl_native_text *)text,index);
}
/* `myl_native_text_offset` with the ASCII test inlined into its callers in this
 * file, so an ASCII slice or index pays one branch and no call. */
static inline size_t offset_of(const myl_native_text *text, size_t index) {
    if (text->flags&MYL_TEXT_ASCII) return index;
    return offset_walk(text,index);
}
size_t myl_native_text_offset(const myl_native_text *text, size_t index) {
    return offset_of(text,index);
}
/* The scalar index of octet `at` of a text that is not ASCII. */
static __attribute__((noinline)) size_t index_walk(const myl_native_text *text, size_t at) {
    if (at>=text->bytes) return text->length;
    const unsigned char *bytes=myl_native_text_storage(text);
    const size_t behind=text->bytes-at;
    if ((at<behind ? at : behind)>LAZY_OCTETS) {
        if (text->flags&MYL_TEXT_INDEXED) return index_at((myl_native_text *)text,at);
        const myl_native_text *owner=(text->flags&MYL_TEXT_VIEW) ? ((const myl_native_text_view *)text)->owner : NULL;
        if (owner && (owner->flags&MYL_TEXT_INDEXED)) {
            myl_native_text *shared=(myl_native_text *)owner;
            return index_at(shared,text->hash+at)-index_at(shared,text->hash);
        }
    }
    return at<=behind ? starts_in(bytes,0,at) : text->length-starts_in(bytes,at,text->bytes);
}
size_t myl_native_text_index(const myl_native_text *text, size_t at) {
    if (text->flags&MYL_TEXT_ASCII) return at;
    return index_walk(text,at);
}
/* The element descriptor a view is allocated with: a 32-byte record whose one
 * traced field is its owner, so the collector, the arena scan and the budget
 * see an ordinary one-pointer record and nothing else in the runtime has to know
 * a view exists. */
static const myl_native_field view_fields[]={
    { .offset=offsetof(myl_native_text_view,owner), .type=&pointer_type }
};
static const myl_native_scan_entry view_scan[]={
    { .offset=offsetof(myl_native_text_view,owner), .tag_offset=MYL_NATIVE_SCAN_ALWAYS }
};
const myl_native_type myl_native_text_view_type={
    .size=sizeof(myl_native_text_view), .alignment=_Alignof(myl_native_text_view),
    .kind=MYL_NATIVE_RECORD, .fields=view_fields, .field_count=1,
    .trace_fields=view_fields, .trace_field_count=1, .trace_mode=MYL_NATIVE_TRACE_FIELDS,
    .scan=view_scan, .scan_count=1
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
    myl_native_root_push(heap,&root,&input,&pointer_type);
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
    size_t scalars=ascii ? count : starts_in(bytes,0,count);
    return build(heap,bytes,count,scalars,ascii || scalars==count);
}
/* The shortest piece of `input` the policy could share: a piece below it is a
 * copy without further tests. Computed once per receiver by the loops that cut
 * one text into many pieces. */
static inline size_t share_threshold(const myl_native_text *input) {
    size_t quarter=myl_native_text_owner(input)->bytes/MYL_TEXT_VIEW_RATIO;
    return quarter>MYL_TEXT_VIEW_MIN ? quarter : MYL_TEXT_VIEW_MIN;
}
/* A scalar count a caller of `cut` or `long_piece` does not know: the piece's
 * own octets are counted instead. A caller that does know it (a slice by scalar
 * index) passes it, so a large piece of a non-ASCII text is described in
 * constant time rather than counted (TEXT-INDEX-2). */
#define SCALARS_UNKNOWN SIZE_MAX
/* A piece long enough, against its owner, for the policy to share: the
 * receiver itself when it is the whole of it and already lives in the innermost
 * open arena, else a view of the receiver's owner or a copy, as `shares`
 * decides. Kept out of line so the copy path of `myl_native_text_substring`
 * stays small enough to inline into the loops that cut a text into many short
 * pieces. */
static __attribute__((noinline)) myl_native_text *long_piece(myl_native_heap *heap, myl_native_text *input, size_t from, size_t count, size_t scalars) {
    if (count==input->bytes && myl_native_header_region(input)==heap->region_depth) return rc_text_result(heap,input);
    const myl_native_text *owner=myl_native_text_owner(input);
    const unsigned char *bytes=myl_native_text_storage(input);
    size_t offset=(size_t)(bytes+from-(const unsigned char *)(owner+1));
    int ascii=(int)(input->flags&MYL_TEXT_ASCII);
    if (ascii) scalars=count;
    else if (scalars==SCALARS_UNKNOWN) scalars=starts_in(bytes+from,0,count);
    if (!shares(heap,owner,offset,count)) return build(heap,bytes+from,count,scalars,ascii || scalars==count);
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
static inline __attribute__((always_inline)) myl_native_text *cut(myl_native_heap *heap, myl_native_text *input, size_t from, size_t to, size_t scalars) {
    const size_t count=to-from;
    /* Only a piece the policy could share leaves the inline copy path: a short
       field of a long line never pays for the call, and a piece shorter than the
       minimum never reads the receiver's header for it. */
    if (count>=MYL_TEXT_VIEW_MIN && count>=share_threshold(input)) return long_piece(heap,input,from,count,scalars);
    if (scalars!=SCALARS_UNKNOWN && !(input->flags&MYL_TEXT_ASCII)) return build(heap,myl_native_text_storage(input)+from,count,scalars,scalars==count);
    return copy_piece(heap,myl_native_text_storage(input)+from,count,(int)(input->flags&MYL_TEXT_ASCII));
}
myl_native_text *myl_native_text_substring(myl_native_heap *heap, myl_native_text *input, size_t from, size_t to) {
    return cut(heap,input,from,to,SCALARS_UNKNOWN);
}
uint32_t myl_native_text_point_at(const myl_native_text *text, size_t index) {
    size_t at=offset_of(text,index);
    uint32_t point=0;
    (void)decode(myl_native_text_storage(text),text->bytes,&at,&point);
    return point;
}
myl_native_text *myl_native_text_copy(myl_native_heap *heap, myl_native_text *input, size_t start, size_t count) {
    size_t from=offset_of(input,start), to=offset_of(input,start+count);
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *result=cut(heap,input,from,to,count);
    myl_native_root_pop(heap,&root);
    return result;
}
/* A text block's payload is raw octets: the same one-octet plain element the
 * heap's own block allocation uses, so an owned copy placed at an explicit depth
 * is charged and traced exactly as one built at the current depth. */
static const myl_native_type octet_type = { .size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN };
/* A text of `bytes` octets holding `scalars` scalars at arena depth `region`,
 * given the position index a text of that shape carries (`build_scalars`), for
 * its constructor to fill and publish. */
static myl_native_text *build_at(myl_native_heap *heap, size_t bytes, size_t scalars, unsigned region) {
    const int indexed=indexable(bytes,scalars);
    myl_native_text *text=myl_native_heap_alloc_at(heap,&octet_type,sizeof(myl_native_text)+(indexed ? ((bytes+7)&~(size_t)7)+index_octets(scalars) : bytes),region);
    if (!text) return NULL;
    text->length=scalars;
    text->bytes=bytes;
    text->flags=indexed ? MYL_TEXT_INDEXED : 0;
    text->hash=0;
    return text;
}
myl_native_text *myl_native_text_own_at(myl_native_heap *heap, myl_native_text *input, unsigned region) {
    if (!(input->flags&MYL_TEXT_VIEW)) return rc_text_result(heap,input);
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *text=build_at(heap,input->bytes,input->length,region);
    myl_native_root_pop(heap,&root);
    if (!text) return NULL;
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
    myl_native_text *result=myl_native_text_build_scalars(heap,octets,(size_t)count);
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
    myl_native_text *result=myl_native_text_build_scalars(heap,bytes,left->length+right->length);
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
    size_t at=offset_of(input,endpoint(input->length,index));
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
    size_t from=offset_of(input,first);
    span->offset=from;
    span->bytes=offset_of(input,first+count)-from;
}
myl_native_text *myl_native_text_piece_at(myl_native_heap *heap, myl_native_text *input, const myl_native_text_span *span, unsigned region) {
    const unsigned char *bytes=myl_native_text_storage(input)+span->offset;
    const int plain=(int)(input->flags&MYL_TEXT_ASCII);
    const size_t scalars=plain ? span->bytes : starts_in(bytes,0,span->bytes);
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *text=build_at(heap,span->bytes,scalars,region);
    myl_native_root_pop(heap,&root);
    if (!text) return NULL;
    /* The allocation may have collected, but a text never moves, so `bytes` still
     * points into the rooted receiver's payload. */
    if (span->bytes) memcpy((unsigned char *)(text+1),bytes,span->bytes);
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
    myl_native_root_push(heap,&a,&input,&pointer_type);
    myl_native_root_push(heap,&b,&separator,&pointer_type);
    myl_native_list *result=myl_native_list_new(heap,&pointer_type,pieces);
    myl_native_root_push(heap,&c,&result,&pointer_type);
    if (result) {
        const unsigned char *haystack=myl_native_text_storage(input);
        const unsigned char *needle=myl_native_text_storage(separator);
        const size_t threshold=share_threshold(input);
        const int ascii=(int)(input->flags&MYL_TEXT_ASCII);
        size_t start=0;
        for (size_t left=pieces; left; left--) {
            size_t hit=left>1 ? myl_native_octets_find(haystack+start,input->bytes-start,needle,width) : SIZE_MAX;
            size_t end=hit==SIZE_MAX ? input->bytes : start+hit;
            myl_native_text *piece=end-start>=threshold ? long_piece(heap,input,start,end-start,SCALARS_UNKNOWN)
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
    size_t count=0, joined=0;
    myl_native_text **items=list->storage;
    for (size_t i=0;i<list->length;i++) {
        if (items[i]->bytes>SIZE_MAX-count) return NULL;
        count+=items[i]->bytes;
        joined+=items[i]->length;
        if (i) { if (separator->bytes>SIZE_MAX-count) return NULL; count+=separator->bytes; joined+=separator->length; }
    }
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&separator,&pointer_type); myl_native_root_push(heap,&b,&list,&pointer_type);
    myl_native_text *result=myl_native_text_build_scalars(heap,count,joined);
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
