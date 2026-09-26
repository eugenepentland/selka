#include "native_dictionary.h"
#include "native_equal.h"
#include "native_rc_dictionary.h"
#include "native_rc_internal.h"
#include "native_rc_collections.h"
#include <stdlib.h>
#include <string.h>
static const myl_native_type pointer_type={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
/* Slots are plain integers, so the collector keeps the block alive through the
 * traced field below and never walks what it holds. */
static const myl_native_type slot_type={.size=sizeof(uint64_t),.alignment=_Alignof(uint64_t),.kind=MYL_NATIVE_PLAIN};
static const myl_native_field dict_fields[]={
    {.offset=offsetof(myl_native_dictionary,entries),.type=&pointer_type},
    {.offset=offsetof(myl_native_dictionary,index)+offsetof(myl_native_dictionary_index,slots),.type=&pointer_type}};
/* The two references of `dict_fields`, as the collector's flat plan (GC-SCAN-PLAN-2). */
static const myl_native_scan_entry dict_scan[]={
    {.offset=offsetof(myl_native_dictionary,entries),.tag_offset=MYL_NATIVE_SCAN_ALWAYS},
    {.offset=offsetof(myl_native_dictionary,index)+offsetof(myl_native_dictionary_index,slots),.tag_offset=MYL_NATIVE_SCAN_ALWAYS}};
static const myl_native_type dict_type={.size=sizeof(myl_native_dictionary),.alignment=_Alignof(myl_native_dictionary),.kind=MYL_NATIVE_RECORD,.fields=dict_fields,.field_count=2,.scan=dict_scan,.scan_count=2};
static const myl_native_type rc_dict_type={.size=sizeof(myl_native_dictionary),.alignment=_Alignof(myl_native_dictionary),.kind=MYL_NATIVE_PLAIN};
static int rc_dict_prepare(myl_native_heap *, const myl_native_type *, const myl_native_type *);
static myl_native_dictionary *rc_dict_clone(myl_native_heap *, const myl_native_dictionary *, unsigned);
static myl_rc_status rc_dict_shell(myl_native_heap *, const void *, unsigned, void **);
static int rc_dict_next(myl_native_heap *, const void *, void *, size_t *, myl_rc_slot *, myl_rc_slot *);
static int rc_insert(myl_native_heap *, myl_native_dictionary *, const void *, const void *);
static int rc_insert_result(myl_native_heap *, myl_native_dictionary *, const void *, const void *, void *);
static int rc_dictionary(const myl_native_dictionary *dict) {
    return ((const myl_native_object *)dict-1)->element==&rc_dict_type;
}
/* A dictionary's header and payload fill one slot of the 320-byte size class. */
_Static_assert(sizeof(myl_native_dictionary)<=320-sizeof(myl_native_object),"a dictionary stays in its size class");
/* How a dictionary's keys hash and compare: a `str` key by its text's octets, an
 * eight-byte integer as one word, a narrower integer as its zero-extended bytes,
 * a plain key wider than a word as a byte string, and any other key — a record,
 * tuple, union, domain, fixed array, `bytes`, or a value holding a `str` — by
 * walking its descriptor (HASH-KEYS-1). */
enum { KEY_TEXT, KEY_WORD, KEY_NARROW, KEY_WIDE, KEY_STRUCT };
/* What the last probe learned: nothing, the key's entry, the key's absence, or
 * the absence of a described slice (DICT-RANGE-KEY-1). The two absences are
 * kept apart because a slice's record names the text it ranges over, which a
 * lookup of that whole text must never mistake for its own. */
enum { PROBE_NONE, PROBE_FOUND, PROBE_ABSENT, PROBE_FOUND_SPAN, PROBE_ABSENT_SPAN };
/* The largest table: slot numbers stay below 2^31, so a slot position fits the
 * record's 32 bits with NO_SLOT to spare, and an entry index fits the low half
 * of a slot. A longer entry list drops the index and scans. */
#define MAX_CAPACITY ((size_t)1<<31)
#define NO_ENTRY SIZE_MAX
#define NO_SLOT UINT32_MAX
myl_native_dictionary *myl_native_dictionary_new(myl_native_heap *heap, const myl_native_type *key, const myl_native_type *value, int string_keys) {
    if (!key || !value || !key->alignment || !value->alignment) return NULL;
    size_t alignment=key->alignment>value->alignment?key->alignment:value->alignment;
    if (key->size>SIZE_MAX-(value->alignment-1)) return NULL;
    size_t offset=(key->size+value->alignment-1)&~(value->alignment-1);
    if (offset>SIZE_MAX-value->size || offset+value->size>SIZE_MAX-(alignment-1)) return NULL;
    size_t size=(offset+value->size+alignment-1)&~(alignment-1);
    if (myl_rc_enabled(heap)) {
        if (size>SIZE_MAX-8-(alignment-1) || !rc_dict_prepare(heap,key,value)) return NULL;
        size=(size+8+alignment-1)&~(alignment-1);
    }
    myl_native_dictionary *dict=myl_native_heap_alloc(heap,myl_rc_enabled(heap)?&rc_dict_type:&dict_type,1);
    if (!dict) return NULL;
    dict->key=key; dict->value=value; dict->value_offset=offset; dict->string_keys=string_keys;
    dict->key_kind=string_keys?KEY_TEXT:key->kind!=MYL_NATIVE_PLAIN?KEY_STRUCT:key->size==8?KEY_WORD:key->size<8?KEY_NARROW:KEY_WIDE;
    dict->dead=0;
    dict->entry_fields[0]=(myl_native_field){.offset=0,.type=key};
    dict->entry_fields[1]=(myl_native_field){.offset=offset,.type=value};
    dict->entry_type=(myl_native_type){.size=size,.alignment=alignment,.kind=MYL_NATIVE_RECORD,.fields=dict->entry_fields,.field_count=2};
    size_t slots;
    if (!myl_rc_enabled(heap) && myl_native_scan_flatten(&dict->entry_type,dict->entry_scan,sizeof dict->entry_scan/sizeof dict->entry_scan[0],&slots)) {
        dict->entry_type.scan=dict->entry_scan;
        dict->entry_type.scan_count=slots;
    }
    /* An empty dictionary carries no table: the first write sizes one. */
    dict->index=(myl_native_dictionary_index){.slots=NULL,.capacity=0};
    dict->last=(myl_native_dictionary_probe){.state=PROBE_NONE};
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    dict->entries=myl_rc_enabled(heap)?myl_rc_list_storage_new(heap,&dict->entry_type,0,heap->region_depth):myl_native_list_new(heap,&dict->entry_type,0);
    myl_native_root_pop(heap,&root);
    if (!dict->entries && myl_rc_enabled(heap)) { myl_rc_native_abort(heap,dict); return NULL; }
    return dict->entries ? dict : NULL;
}
static inline unsigned char *entry_at(const myl_native_dictionary *dict, size_t index) {
    return (unsigned char *)dict->entries->storage+index*dict->entry_type.size;
}
/* Copy one value. Almost every value is a word, so that width is a register
 * move rather than a call into the C library. */
static inline void copy_value(const myl_native_dictionary *dict, void *target, const void *source) {
    size_t size=dict->value->size;
    if (size==8) { uint64_t word; memcpy(&word,source,8); memcpy(target,&word,8); }
    else memmove(target,source,size);
}
/* A scalar key's bytes zero-extended into one word: the record's key and the
 * whole input to its hash for every key up to eight bytes wide. */
static inline uint64_t scalar_bits(const void *key, size_t size) {
    uint64_t bits=0;
    if (size==8) memcpy(&bits,key,8);
    else if (size==4) { uint32_t word; memcpy(&word,key,4); bits=word; }
    else if (size==2) { uint16_t word; memcpy(&word,key,2); bits=word; }
    else if (size==1) bits=*(const unsigned char *)key;
    else memcpy(&bits,key,size<8?size:8);
    return bits;
}
static inline const myl_native_text *text_of(const void *key) {
    const myl_native_text *text;
    memcpy(&text,key,sizeof text);
    return text;
}
/* Octet equality for two payloads of one length, a word at a time and inline:
 * a key comparison that follows a matching stored hash is nearly always a
 * match, so it is worth neither a call nor a byte loop. */
static inline int same_octets(const unsigned char *a, const unsigned char *b, size_t size) {
    if (size>=8) {
        uint64_t x,y;
        for (size_t at=0;at+8<size;at+=8) {
            memcpy(&x,a+at,8); memcpy(&y,b+at,8);
            if (x!=y) return 0;
        }
        memcpy(&x,a+size-8,8); memcpy(&y,b+size-8,8);
        return x==y;
    }
    if (size>=4) {
        uint32_t x,y,u,v;
        memcpy(&x,a,4); memcpy(&y,b,4); memcpy(&u,a+size-4,4); memcpy(&v,b+size-4,4);
        return x==y && u==v;
    }
    for (size_t at=0;at<size;at++) if (a[at]!=b[at]) return 0;
    return 1;
}
/* Exactly the comparison `find` used before the index existed: text content for
 * `str` keys and the raw key bytes for every other key type. One text object is
 * always equal to itself, which settles most matches without a payload read.
 * `stored` is an entry's key, which `insert` keeps owned, so its octets are its
 * header's tail; `octets` are the queried text's, resolved once per lookup
 * because the queried text may be a view. */
static inline int same_text(const myl_native_text *stored, const myl_native_text *query, const unsigned char *octets) {
    return stored==query || (stored->bytes==query->bytes && same_octets((const unsigned char *)(stored+1),octets,stored->bytes));
}
/* Structural equality of two hashable values of one descriptor, exactly the
 * answer `==` gives them: integers and enums by their bytes, a `str` by its
 * octets, `bytes` by its octets, records, tuples and domains field by field,
 * a union or Option by its case and that case's payload, and a fixed array
 * element by element. A hashable key holds no cycle, so the walk recurses on
 * the descriptor's depth and allocates nothing. */
static int same_value(const myl_native_type *type, const unsigned char *a, const unsigned char *b) {
    switch (type->kind) {
    case MYL_NATIVE_POINTER: {
        const void *left, *right;
        memcpy(&left,a,sizeof left); memcpy(&right,b,sizeof right);
        if (left==right) return 1;
        if (!left || !right) return 0;
        if (type->collection_kind==2) return myl_native_text_equal(left,right);
        /* A box holds a recursive value of any depth (RECURSIVE-VALUES-3), so it
         * is compared by the equality runtime's heap work list instead of this
         * walk's host recursion. A hashable value holds no float, so one box is
         * always equal to itself, which the check above already answered; only
         * if the work list cannot be allocated is the value walked here. */
        if (type->collection_kind==5) {
            int equal=myl_native_equal(type,a,b);
            return equal<0?same_value(type->element,left,right):equal;
        }
        if (type->collection_kind==4) {
            const myl_native_list *x=left, *y=right;
            return x->length==y->length && (!x->length || !memcmp(x->storage,y->storage,x->length));
        }
        return 0;
    }
    case MYL_NATIVE_RECORD:
        for (size_t i=0;i<type->field_count;i++)
            if (!same_value(type->fields[i].type,a+type->fields[i].offset,b+type->fields[i].offset)) return 0;
        return 1;
    case MYL_NATIVE_VARIANT: {
        uint32_t tag, other;
        memcpy(&tag,a,4); memcpy(&other,b,4);
        if (tag!=other) return 0;
        for (size_t i=0;i<type->field_count;i++)
            if (type->fields[i].tag==tag && !same_value(type->fields[i].type,a+type->fields[i].offset,b+type->fields[i].offset)) return 0;
        return 1;
    }
    case MYL_NATIVE_ARRAY:
        for (size_t i=0;i<type->count;i++)
            if (!same_value(type->fields[0].type,a+i*type->stride,b+i*type->stride)) return 0;
        return 1;
    default: return !memcmp(a,b,type->size);
    }
}
/* A stored `str` key against a queried one. */
static inline int same_text_key(const void *entry, const void *key) {
    const myl_native_text *stored=text_of(entry), *query=text_of(key);
    return stored==query || same_text(stored,query,myl_native_text_storage(query));
}
/* Equality of a key that is not walked through its descriptor (HASH-KEYS-2): a
 * `str`, a plain scalar or plain bytes wider than a word. It reads only the two
 * keys and calls nothing, so a lookup that compares one keeps what it loaded
 * from the dictionary in registers across the comparison instead of reloading
 * it after a call that might have written memory; only a structural key pays
 * for the descriptor walk. */
static inline int same_flat_key(const myl_native_dictionary *dict, const void *entry, const void *key) {
    switch (dict->key_kind) {
    case KEY_TEXT: return same_text_key(entry,key);
    case KEY_WIDE: return same_octets(entry,key,dict->key->size);
    default: return scalar_bits(entry,dict->key->size)==scalar_bits(key,dict->key->size);
    }
}
static inline int same_key(const myl_native_dictionary *dict, const void *entry, const void *key) {
    return dict->key_kind==KEY_STRUCT?same_value(dict->key,entry,key):same_flat_key(dict,entry,key);
}
/* The high and low halves of one full 64×64-bit product folded together, so
 * every output bit depends on every input bit of both factors. */
static inline uint64_t fold_multiply(uint64_t a, uint64_t b) {
    unsigned __int128 product=(unsigned __int128)a*b;
    return (uint64_t)product^(uint64_t)(product>>64);
}
/* Fixed odd constants and no seed: the runtime has no sanctioned randomness and a
 * dictionary must behave identically on every run. */
#define KEY_MIX 0x9e3779b97f4a7c15ULL
#define KEY_SPREAD 0xbf58476d1ce4e5b9ULL
/* A scalar key's hash: one multiply of its zero-extended bits, folded to 32 bits
 * so the low bits the table masks and the high bits a slot stores both depend
 * on the whole key. */
static inline uint32_t scalar_hash(uint64_t bits) {
    uint64_t hash=fold_multiply(bits^KEY_MIX,KEY_SPREAD);
    return (uint32_t)(hash^(hash>>32));
}
/* A text asks for its own payload hash, which it computes a word at a time and
 * caches in its header, so a text probed twice — every read-modify-write — is
 * hashed once. */
static inline uint32_t text_hash(const myl_native_text *text) {
    return text->flags&MYL_TEXT_HASHED?text->hash:myl_native_text_hash(text);
}
/* Fold one word into a running structural hash with the same multiply. */
static inline uint64_t mix_word(uint64_t state, uint64_t word) {
    return fold_multiply(state^word^KEY_MIX,KEY_SPREAD);
}
/* The structural hash of one hashable value, reading exactly what `same_value`
 * compares: a scalar's bytes a word at a time, a `str` through its cached text
 * hash, `bytes` through the octet hash a text of the same octets gets, each
 * field of a record in declaration order, a union's case tag and then only
 * that case's payload, and each element of a fixed array. Padding and an
 * inactive case's bytes are never read, so equal values hash equally however
 * they were built, and no seed is involved. */
typedef struct box_memo box_memo;
static uint64_t box_hash(const myl_native_type *body, const void *box, box_memo *memo);
static uint64_t hash_walk(const myl_native_type *type, const unsigned char *value, uint64_t state, box_memo *memo) {
    switch (type->kind) {
    case MYL_NATIVE_POINTER: {
        const void *pointer;
        memcpy(&pointer,value,sizeof pointer);
        if (!pointer) return mix_word(state,0);
        if (type->collection_kind==2) return mix_word(state,(uint64_t)text_hash(pointer)+1);
        /* A box mixes in the hash of the value it holds (RECURSIVE-VALUES-3). */
        if (type->collection_kind==5) return mix_word(state,box_hash(type->element,pointer,memo));
        if (type->collection_kind==4) {
            const myl_native_list *octets=pointer;
            return mix_word(state,(uint64_t)myl_native_octets_hash(octets->storage,octets->length)+1);
        }
        return mix_word(state,(uint64_t)(uintptr_t)pointer);
    }
    case MYL_NATIVE_RECORD:
        for (size_t i=0;i<type->field_count;i++) state=hash_walk(type->fields[i].type,value+type->fields[i].offset,state,memo);
        return state;
    case MYL_NATIVE_VARIANT: {
        uint32_t tag;
        memcpy(&tag,value,4);
        state=mix_word(state,tag);
        for (size_t i=0;i<type->field_count;i++)
            if (type->fields[i].tag==tag) state=hash_walk(type->fields[i].type,value+type->fields[i].offset,state,memo);
        return state;
    }
    case MYL_NATIVE_ARRAY:
        for (size_t i=0;i<type->count;i++) state=hash_walk(type->fields[0].type,value+i*type->stride,state,memo);
        return state;
    default:
        for (size_t at=0;at<type->size;at+=8) {
            uint64_t word=0;
            memcpy(&word,value+at,type->size-at<8?type->size-at:8);
            state=mix_word(state,word);
        }
        return state;
    }
}
static uint64_t hash_value(const myl_native_type *type, const unsigned char *value, uint64_t state) {
    return hash_walk(type,value,state,NULL);
}
/* The hashes of the boxes one key hash has already met, by box address, so a
 * value whose subtrees share boxes hashes each box once. */
struct box_memo { const void **boxes; uint64_t *hashes; size_t capacity, count; };
static size_t box_slot(const box_memo *memo, const void *box) {
    size_t at=(size_t)(scalar_hash((uint64_t)(uintptr_t)box))&(memo->capacity-1);
    while (memo->boxes[at] && memo->boxes[at]!=box) at=(at+1)&(memo->capacity-1);
    return at;
}
static int box_known(const box_memo *memo, const void *box) {
    return memo->capacity && memo->boxes[box_slot(memo,box)]==box;
}
static int box_remember(box_memo *memo, const void *box, uint64_t hash) {
    if (memo->count*2>=memo->capacity) {
        size_t capacity=memo->capacity?memo->capacity*2:64;
        const void **boxes=calloc(capacity,sizeof *boxes);
        uint64_t *hashes=malloc(capacity*sizeof *hashes);
        if (!boxes || !hashes) { free(boxes); free(hashes); return 0; }
        box_memo grown={boxes,hashes,capacity,memo->count};
        for (size_t i=0;i<memo->capacity;i++) if (memo->boxes[i]) {
            size_t at=box_slot(&grown,memo->boxes[i]);
            grown.boxes[at]=memo->boxes[i]; grown.hashes[at]=memo->hashes[i];
        }
        free(memo->boxes); free(memo->hashes);
        *memo=grown;
    }
    size_t at=box_slot(memo,box);
    memo->boxes[at]=box; memo->hashes[at]=hash; memo->count++;
    return 1;
}
/* One box still to hash: its body descriptor, its address, and whether the
 * boxes it holds have been queued ahead of it. */
typedef struct { const myl_native_type *body; const void *box; int expanded; } box_visit;
typedef struct { box_visit *items; size_t length, capacity; } box_stack;
static int box_push(box_stack *stack, const myl_native_type *body, const void *box) {
    if (stack->length==stack->capacity) {
        size_t capacity=stack->capacity?stack->capacity*2:32;
        box_visit *items=realloc(stack->items,capacity*sizeof *items);
        if (!items) return 0;
        stack->items=items; stack->capacity=capacity;
    }
    stack->items[stack->length++]=(box_visit){body,box,0};
    return 1;
}
/* Queue every box directly inside one box's value that is not hashed yet. The
 * walk follows only the value's inline shape, which its declarations bound. */
static int box_children(box_stack *stack, const box_memo *memo, const myl_native_type *type, const unsigned char *value) {
    switch (type->kind) {
    case MYL_NATIVE_POINTER: {
        const void *pointer;
        memcpy(&pointer,value,sizeof pointer);
        if (type->collection_kind!=5 || !pointer || box_known(memo,pointer)) return 1;
        return box_push(stack,type->element,pointer);
    }
    case MYL_NATIVE_RECORD:
        for (size_t i=0;i<type->field_count;i++) if (!box_children(stack,memo,type->fields[i].type,value+type->fields[i].offset)) return 0;
        return 1;
    case MYL_NATIVE_VARIANT: {
        uint32_t tag;
        memcpy(&tag,value,4);
        for (size_t i=0;i<type->field_count;i++)
            if (type->fields[i].tag==tag && !box_children(stack,memo,type->fields[i].type,value+type->fields[i].offset)) return 0;
        return 1;
    }
    case MYL_NATIVE_ARRAY:
        for (size_t i=0;i<type->count;i++) if (!box_children(stack,memo,type->fields[0].type,value+i*type->stride)) return 0;
        return 1;
    default: return 1;
    }
}
/* The hash of the value inside one box (RECURSIVE-VALUES-3): its own fold from
 * a fixed start, so it depends on that value alone. The boxes below it are
 * hashed first, children before parents, off a heap stack, so a recursive key
 * of any depth hashes without host recursion. If that bookkeeping cannot be
 * allocated, the value is hashed by plain recursion instead. */
static uint64_t box_hash(const myl_native_type *body, const void *box, box_memo *memo) {
    if (memo && box_known(memo,box)) return memo->hashes[box_slot(memo,box)];
    box_memo local={0};
    box_memo *known=memo?memo:&local;
    box_stack stack={0};
    int ok=box_push(&stack,body,box);
    while (ok && stack.length) {
        box_visit *top=&stack.items[stack.length-1];
        if (box_known(known,top->box)) { stack.length--; continue; }
        if (!top->expanded) {
            top->expanded=1;
            ok=box_children(&stack,known,top->body,top->box);
            continue;
        }
        const box_visit item=*top;
        ok=box_remember(known,item.box,hash_walk(item.body,item.box,KEY_MIX,known));
        stack.length--;
    }
    uint64_t hash=ok?known->hashes[box_slot(known,box)]:hash_walk(body,box,KEY_MIX,NULL);
    free(stack.items);
    if (!memo) { free(local.boxes); free(local.hashes); }
    return hash;
}
/* The table hash of one key. Equal keys have equal bytes and so equal hashes. */
static uint32_t hash_key(const myl_native_dictionary *dict, const void *key) {
    switch (dict->key_kind) {
    case KEY_TEXT: return text_hash(text_of(key));
    case KEY_STRUCT: {
        uint64_t hash=hash_value(dict->key,key,dict->key->size);
        return (uint32_t)(hash^(hash>>32));
    }
    case KEY_WIDE: {
        /* The same multiply chained over the key's words. */
        const unsigned char *bytes=key;
        size_t size=dict->key->size;
        uint64_t hash=size;
        for (size_t at=0;at<size;at+=8) {
            uint64_t word=0;
            memcpy(&word,bytes+at,size-at<8?size-at:8);
            hash=fold_multiply(word^KEY_MIX,hash^KEY_SPREAD);
        }
        return (uint32_t)(hash^(hash>>32));
    }
    default: return scalar_hash(scalar_bits(key,dict->key->size));
    }
}
static inline uint64_t pack_slot(uint32_t hash, size_t entry) {
    return (uint64_t)hash<<32|(uint64_t)(entry+1);
}
/* Linear probing from the masked hash to the first empty slot. The caller
 * guarantees one, which the load factor below always leaves. */
static void index_place(const myl_native_dictionary_index *index, uint64_t slot) {
    size_t mask=index->capacity-1, at=(size_t)(slot>>32)&mask;
    while (index->slots[at]) at=(at+1)&mask;
    index->slots[at]=slot;
}
/* Fill an empty table from the entry list, hashing every key: the first table a
 * dictionary gets, and the arena escape's rebuild once its keys are filled. */
static void index_fill(myl_native_dictionary *dict) {
    for (size_t i=0;i<dict->entries->length;i++)
        index_place(&dict->index,pack_slot(hash_key(dict,entry_at(dict,i)),i));
}
/* Whether the table already holds `needed` entries at a load factor of at most 5/8. */
static inline int table_fits(const myl_native_dictionary *dict, size_t needed) {
    return dict->index.capacity && needed<=MAX_CAPACITY/8*5 && needed*8<=dict->index.capacity*5;
}
/* The slot that names entry `index`, or SIZE_MAX when none does: the entry was
 * removed and its bytes wait in the entry list for `settle` (DICT-REMOVE-1).
 * The entry's own key is hashed once, and a slot is matched by the stored hash
 * and the entry number it carries, so no key is compared. */
static size_t slot_of(const myl_native_dictionary *dict, size_t index) {
    uint32_t hash;
    if (rc_dictionary(dict)) {
        uint64_t marker;
        memcpy(&marker,entry_at(dict,index)+dict->entry_type.size-8,8);
        if (!(uint32_t)marker) return SIZE_MAX;
        hash=(uint32_t)(marker>>32);
    } else hash=hash_key(dict,entry_at(dict,index));
    size_t mask=dict->index.capacity-1;
    for (size_t at=hash&mask;dict->index.slots[at];at=(at+1)&mask) {
        uint64_t slot=dict->index.slots[at];
        if ((uint32_t)(slot>>32)==hash && MYL_NATIVE_DICTIONARY_SLOT_ENTRY(slot)==index+1) return at;
    }
    return SIZE_MAX;
}
void myl_native_dictionary_settle(const myl_native_dictionary *input) {
    myl_native_dictionary *dict=(myl_native_dictionary *)input;
    if (!dict->dead) return;
    unsigned char *storage=dict->entries->storage;
    size_t size=dict->entry_type.size, kept=0;
    /* Every entry before `kept` is settled and every slot naming one was
     * renumbered to at most `kept`, so a slot still carrying `i + 1` can only
     * name entry `i` itself: the walk never mistakes a moved entry for a live
     * one it has not reached. */
    for (size_t i=0;i<dict->entries->length;i++) {
        size_t at=slot_of(dict,i);
        if (at==SIZE_MAX) continue;
        if (kept!=i) {
            memmove(storage+kept*size,storage+i*size,size);
            dict->index.slots[at]=pack_slot((uint32_t)(dict->index.slots[at]>>32),kept);
        }
        kept++;
    }
    memset(storage+kept*size,0,(dict->entries->length-kept)*size);
    dict->entries->length=kept;
    dict->entries->generation++;
    dict->dead=0;
    dict->last.state=PROBE_NONE;
}
/* Size the table for `needed` entries at a load factor of at most 5/8. A grown
 * table is refilled from the old one's stored hashes, so growth reads no key.
 * A refused allocation drops the index rather than failing the write: lookups
 * fall back to scanning, which is slower and exactly as correct, and the
 * caller's budget flag is left as it was so a later trap still names the real
 * cause. Any change to the table forgets the last probe. */
static void index_reserve(myl_native_heap *heap, myl_native_dictionary *dict, size_t needed) {
    if (table_fits(dict,needed)) return;
    /* Removed entries are squeezed out before the table grows or is dropped:
     * they may be all the growth needed, and only a table can tell them apart. */
    if (dict->dead) {
        size_t before=dict->entries->length;
        myl_native_dictionary_settle(dict);
        needed-=before-dict->entries->length;
        if (table_fits(dict,needed)) return;
    }
    dict->last.state=PROBE_NONE;
    size_t capacity=dict->index.capacity?dict->index.capacity:8;
    if (needed>MAX_CAPACITY/8*5) {
        void *old=dict->index.slots;
        dict->index.slots=NULL; dict->index.capacity=0;
        if (myl_rc_enabled(heap)) myl_rc_owner_release(heap,old);
        return;
    }
    while (needed*8>capacity*5) capacity*=2;
    int exhausted=heap->exhausted;
    myl_rc_status previous=MYL_RC_OK;
    if (myl_rc_enabled(heap)) previous=myl_rc_take_failure(heap);
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    uint64_t *slots=myl_native_heap_alloc_at(heap,&slot_type,capacity,myl_native_object_region(heap,dict));
    myl_native_root_pop(heap,&root);
    if (myl_rc_enabled(heap)) {
        (void)myl_rc_take_failure(heap);
        myl_rc_record_failure(heap,previous);
    }
    if (!slots) {
        heap->exhausted=exhausted;
        void *old=dict->index.slots;
        dict->index.slots=NULL; dict->index.capacity=0;
        if (myl_rc_enabled(heap)) myl_rc_owner_release(heap,old);
        return;
    }
    myl_native_dictionary_index old=dict->index;
    dict->index.slots=slots; dict->index.capacity=capacity;
    if (!old.capacity) { index_fill(dict); return; }
    for (size_t at=0;at<old.capacity;at++)
        if (old.slots[at]) index_place(&dict->index,old.slots[at]);
    if (myl_rc_enabled(heap)) myl_rc_owner_release(heap,old.slots);
}
/* One lookup's answer, small enough to come back in two registers: the entry
 * that holds the key or NO_ENTRY, and — when a table walk produced them — the
 * slot that names it or the empty slot a write of the key would fill, with the
 * key's hash. A scan, or an answer from the record of a found entry, leaves
 * NO_SLOT. */
typedef struct { size_t entry; uint32_t slot, hash; } located;
/* The table walk for a text key. A slot whose stored hash differs cannot hold
 * the key, so its entry is never loaded. */
static located probe_text(const myl_native_dictionary *dict, const myl_native_text *text) {
    uint32_t hash=text_hash(text);
    const unsigned char *octets=myl_native_text_storage(text);
    const uint64_t *slots=dict->index.slots;
    const unsigned char *storage=dict->entries->storage;
    size_t mask=dict->index.capacity-1, at=hash&mask, stride=dict->entry_type.size;
    for (uint64_t slot;(slot=slots[at]);at=(at+1)&mask) {
        if ((uint32_t)(slot>>32)!=hash) continue;
        size_t entry=MYL_NATIVE_DICTIONARY_SLOT_ENTRY(slot)-1;
        if (same_text(text_of(storage+entry*stride),text,octets)) return (located){entry,(uint32_t)at,hash};
    }
    return (located){NO_ENTRY,(uint32_t)at,hash};
}
/* The table walk for an eight-byte integer key — `int`, the common case —
 * compared as one word. */
static located probe_word(const myl_native_dictionary *dict, uint64_t bits) {
    uint32_t hash=scalar_hash(bits);
    const uint64_t *slots=dict->index.slots;
    const unsigned char *storage=dict->entries->storage;
    size_t mask=dict->index.capacity-1, at=hash&mask, stride=dict->entry_type.size;
    for (uint64_t slot;(slot=slots[at]);at=(at+1)&mask) {
        if ((uint32_t)(slot>>32)!=hash) continue;
        size_t entry=MYL_NATIVE_DICTIONARY_SLOT_ENTRY(slot)-1;
        uint64_t held;
        memcpy(&held,storage+entry*stride,8);
        if (held==bits) return (located){entry,(uint32_t)at,hash};
    }
    return (located){NO_ENTRY,(uint32_t)at,hash};
}
/* The table walk for a narrower integer key, compared as its bits. */
static located probe_scalar(const myl_native_dictionary *dict, uint64_t bits) {
    uint32_t hash=scalar_hash(bits);
    const uint64_t *slots=dict->index.slots;
    const unsigned char *storage=dict->entries->storage;
    size_t mask=dict->index.capacity-1, at=hash&mask, stride=dict->entry_type.size, size=dict->key->size;
    for (uint64_t slot;(slot=slots[at]);at=(at+1)&mask) {
        if ((uint32_t)(slot>>32)!=hash) continue;
        size_t entry=MYL_NATIVE_DICTIONARY_SLOT_ENTRY(slot)-1;
        if (scalar_bits(storage+entry*stride,size)==bits) return (located){entry,(uint32_t)at,hash};
    }
    return (located){NO_ENTRY,(uint32_t)at,hash};
}
/* The walk for any other key, and the scan a dictionary without a table falls
 * back to. */
static located probe_any(const myl_native_dictionary *dict, const void *key) {
    if (!dict->index.capacity) {
        for (size_t i=0;i<dict->entries->length;i++)
            if (same_key(dict,entry_at(dict,i),key)) return (located){i,NO_SLOT,0};
        return (located){NO_ENTRY,NO_SLOT,0};
    }
    uint32_t hash=hash_key(dict,key);
    size_t mask=dict->index.capacity-1, at=hash&mask;
    for (uint64_t slot;(slot=dict->index.slots[at]);at=(at+1)&mask) {
        if ((uint32_t)(slot>>32)!=hash) continue;
        size_t entry=MYL_NATIVE_DICTIONARY_SLOT_ENTRY(slot)-1;
        if (same_key(dict,entry_at(dict,entry),key)) return (located){entry,(uint32_t)at,hash};
    }
    return (located){NO_ENTRY,(uint32_t)at,hash};
}
/* The record's key for one queried key: a text key's object pointer, a scalar
 * key's bytes. A key wider than a word has no one-word identity and is never
 * recorded. */
static inline int record_key(const myl_native_dictionary *dict, const void *key, uint64_t *bits) {
    switch (dict->key_kind) {
    case KEY_TEXT: *bits=(uint64_t)(uintptr_t)text_of(key); return 1;
    case KEY_WORD: memcpy(bits,key,8); return 1;
    case KEY_NARROW: *bits=scalar_bits(key,dict->key->size); return 1;
    default: return 0;
    }
}
/* The entry the last probe found for this key, when it still holds; NO_ENTRY
 * otherwise. The record only nominates an entry — the same text object, or
 * the same scalar bytes, as the key it was made for — and the nomination is
 * proven, not trusted: the entry at the recorded position must still hold a key
 * equal to the queried one, which no insertion, removal or rebuild can fake.
 * A text is compared by content there, because the entry keeps the text first
 * inserted while a read-modify-write of a fresh slice queries another object
 * with the same content; that comparison reads one payload already in cache,
 * not a hash, a table walk and a payload. Two equal texts that are not the same
 * object are never nominated by each other's record; they get the full probe. */
static inline __attribute__((always_inline)) size_t recall(const myl_native_dictionary *dict, const void *key) {
    const myl_native_dictionary_probe *last=&dict->last;
    uint64_t bits, held;
    if (last->state!=PROBE_FOUND || !record_key(dict,key,&bits) || bits!=last->key) return NO_ENTRY;
    if (last->entry>=dict->entries->length) return NO_ENTRY;
    const unsigned char *entry=entry_at(dict,last->entry);
    if (dict->key_kind==KEY_TEXT) return same_text_key(entry,key)?last->entry:NO_ENTRY;
    record_key(dict,entry,&held);
    return held==bits?last->entry:NO_ENTRY;
}
/* Locate one key once no recorded entry applies. A scalar key's recorded
 * absence answers without a walk: it is kept only while nothing has been
 * inserted, moved or removed since, because every such change drops it first.
 * A text's absence is never recorded — its object could be collected and its
 * address reused by an equal text that is present. Whatever the walk learns is
 * recorded for the next lookup. */
static inline __attribute__((always_inline)) located locate(const myl_native_dictionary *dict, const void *key) {
    myl_native_dictionary_probe *last=(myl_native_dictionary_probe *)&dict->last;
    uint64_t bits=0;
    int recorded=record_key(dict,key,&bits);
    if (last->state==PROBE_ABSENT && recorded && bits==last->key) return (located){NO_ENTRY,last->slot,last->hash};
    located found;
    if (!dict->index.capacity || dict->key_kind>=KEY_WIDE) found=probe_any(dict,key);
    else if (dict->key_kind==KEY_TEXT) found=probe_text(dict,text_of(key));
    else if (dict->key_kind==KEY_WORD) found=probe_word(dict,bits);
    else found=probe_scalar(dict,bits);
    if (!recorded) last->state=PROBE_NONE;
    else if (found.entry!=NO_ENTRY) *last=(myl_native_dictionary_probe){.key=bits,.entry=found.entry,.state=PROBE_FOUND};
    else if (dict->key_kind!=KEY_TEXT && found.slot!=NO_SLOT) *last=(myl_native_dictionary_probe){.key=bits,.slot=found.slot,.hash=found.hash,.state=PROBE_ABSENT};
    else last->state=PROBE_NONE;
    return found;
}
/* Locate one key, answering from the last probe when it still applies. */
static inline __attribute__((always_inline)) located find(const myl_native_dictionary *dict, const void *key) {
    size_t entry=recall(dict,key);
    if (entry!=NO_ENTRY) return (located){entry,NO_SLOT,0};
    return locate(dict,key);
}
/* The out-of-line halves of `contains` and `read`: the table walk and what
 * follows it. Each public call is the record check inline plus at most one call
 * into one of these, so a generated read-modify-write pays no call when the
 * record answers and one when it does not. */
static __attribute__((noinline)) int contains_walk(const myl_native_dictionary *dict, const void *key) {
    return locate(dict,key).entry!=NO_ENTRY;
}
static __attribute__((noinline)) int read_walk(const myl_native_dictionary *dict, const void *key, void *output) {
    size_t index=locate(dict,key).entry;
    if (index==NO_ENTRY) return 0;
    copy_value(dict,output,entry_at(dict,index)+dict->value_offset);
    return 1;
}
size_t myl_native_dictionary_length(const myl_native_dictionary *dict) { return dict->entries->length-dict->dead; }
int myl_native_dictionary_contains(const myl_native_dictionary *dict, const void *key) {
    return recall(dict,key)!=NO_ENTRY || contains_walk(dict,key);
}
int myl_native_dictionary_read(const myl_native_dictionary *dict, const void *key, void *output) {
    size_t index=recall(dict,key);
    if (index==NO_ENTRY) return read_walk(dict,key,output);
    copy_value(dict,output,entry_at(dict,index)+dict->value_offset);
    return 1;
}
/* Append one new key the caller's lookup found absent, and name it in the table
 * at the empty slot that lookup ended on when the table did not change in
 * between — so a write after a missed read walks the table at most once more. */
static __attribute__((noinline)) int insert(myl_native_heap *heap, myl_native_dictionary *dict, const void *key, const void *value, located at) {
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
    /* A text key that is a view is stored as an owned copy of its octets, in the
     * dictionary's own region: every stored key then reads its octets from its
     * header's tail (`same_text`), and a key never keeps a larger text alive. */
    if (dict->key_kind==KEY_TEXT && (text_of(entry)->flags&MYL_TEXT_VIEW)) {
        myl_native_text *owned=myl_native_text_own_at(heap,(myl_native_text *)text_of(entry),myl_native_object_region(heap,dict));
        if (!owned) {
            myl_native_root_pop(heap,&entry_root);
            myl_native_root_pop(heap,&owner_root);
            if (entry!=inline_entry) free(entry);
            return 0;
        }
        memcpy(entry,&owned,sizeof owned);
    }
    /* Removed entries never outnumber live ones for long: once they do, the
     * entry list is squeezed before it grows again (DICT-REMOVE-1). */
    if (dict->dead && dict->dead*2>=dict->entries->length) myl_native_dictionary_settle(dict);
    const uint64_t *slots=dict->index.slots;
    index_reserve(heap,dict,dict->entries->length+1);
    int unchanged=dict->index.slots==slots && at.slot!=NO_SLOT;
    uint32_t hash=at.slot!=NO_SLOT?at.hash:dict->index.capacity?hash_key(dict,entry):0;
    int ok=myl_native_list_append(heap,dict->entries,entry);
    myl_native_root_pop(heap,&entry_root);
    myl_native_root_pop(heap,&owner_root);
    size_t added=dict->entries->length-1;
    uint64_t bits;
    dict->last.state=PROBE_NONE;
    if (ok && dict->index.capacity) {
        if (unchanged) dict->index.slots[at.slot]=pack_slot(hash,added);
        else index_place(&dict->index,pack_slot(hash,added));
    }
    if (ok && record_key(dict,entry,&bits))
        dict->last=(myl_native_dictionary_probe){.key=bits,.entry=added,.state=PROBE_FOUND};
    if (entry!=inline_entry) free(entry);
    return ok;
}
/* The out-of-line half of `write`: the table walk, then an overwrite or an
 * insertion at the slot the walk ended on. */
static __attribute__((noinline)) int write_walk(myl_native_heap *heap, myl_native_dictionary *dict, const void *key, const void *value) {
    located at=locate(dict,key);
    if (at.entry==NO_ENTRY) return insert(heap,dict,key,value,at);
    copy_value(dict,entry_at(dict,at.entry)+dict->value_offset,value);
    return 1;
}
int myl_native_dictionary_write(myl_native_heap *heap, myl_native_dictionary *dict, const void *key, const void *value) {
    if (myl_rc_enabled(heap)) {
        size_t at=find(dict,key).entry;
        if (at==NO_ENTRY) return rc_insert(heap,dict,key,value);
        return myl_rc_native_retain_replace(heap,dict->value,entry_at(dict,at)+dict->value_offset,value,myl_native_header_region(dict));
    }
    size_t index=recall(dict,key);
    if (index==NO_ENTRY) return write_walk(heap,dict,key,value);
    copy_value(dict,entry_at(dict,index)+dict->value_offset,value);
    return 1;
}
static __attribute__((noinline)) int overwrite_walk(myl_native_dictionary *dict, const void *key, const void *value) {
    size_t index=locate(dict,key).entry;
    if (index==NO_ENTRY) return 0;
    copy_value(dict,entry_at(dict,index)+dict->value_offset,value);
    return 1;
}
int myl_native_dictionary_overwrite(myl_native_dictionary *dict, const void *key, const void *value) {
    size_t index=recall(dict,key);
    if (index==NO_ENTRY) return overwrite_walk(dict,key,value);
    copy_value(dict,entry_at(dict,index)+dict->value_offset,value);
    return 1;
}
/* A described slice as a lookup key (DICT-RANGE-KEY-1): the octets it names, in
 * place inside the text it ranges over, and that text with the span for the
 * record of an absence. */
typedef struct {
    const myl_native_text *text;
    const myl_native_text_span *span;
    const unsigned char *octets;
} span_key;
static inline span_key span_of(const myl_native_text *text, const myl_native_text_span *span) {
    return (span_key){text,span,myl_native_text_storage(text)+span->offset};
}
/* Whether a stored key holds exactly the slice's octets. Stored keys are owned,
 * so their octets are the header's tail (`insert`). */
static inline int same_span(const unsigned char *entry, span_key key) {
    const myl_native_text *stored=text_of(entry);
    return stored->bytes==key.span->bytes && same_octets((const unsigned char *)(stored+1),key.octets,key.span->bytes);
}
/* Whether the record was made for this very span of this very text. */
static inline int same_query(const myl_native_dictionary_probe *last, span_key key) {
    return last->key==(uint64_t)(uintptr_t)key.text && last->offset==key.span->offset && last->bytes==key.span->bytes;
}
/* The entry the last probe found for this span of this text, when it still
 * holds the slice's octets. The record nominates only the query it was made for
 * — the same text, offset and length, which is what the write of a
 * read-modify-write asks — so a lookup of any other span fails the nomination on
 * a register compare instead of on a coin-flip octet comparison; the nomination
 * is then proven by comparing the entry's octets, as a text's recall is. */
static inline size_t recall_span(const myl_native_dictionary *dict, span_key key) {
    const myl_native_dictionary_probe *last=&dict->last;
    if (last->state!=PROBE_FOUND_SPAN || !same_query(last,key) || last->entry>=dict->entries->length) return NO_ENTRY;
    return same_span(entry_at(dict,last->entry),key)?last->entry:NO_ENTRY;
}
/* The heap's collection count while no arena is open, which is when a recorded
 * slice's absence may be written or believed. The record names the ranged text
 * by address; that text was live when it was recorded, and a tracing-heap
 * object is reclaimed only by a collection, so an unchanged count proves the
 * address still names the same immutable text. An arena frees without
 * collecting, so no absence is dated while one is open. */
static inline int span_epoch(const myl_native_heap *heap, size_t *epoch) {
    if (heap->region_depth || heap->collections==SIZE_MAX) return 0;
    *epoch=heap->collections;
    return 1;
}
/* The walk for a described slice, answering from a recorded absence of the same
 * span of the same text when nothing since can have inserted a key (every
 * insertion drops the record) or reclaimed that text (`span_epoch`). Whatever the
 * walk learns is recorded, as `locate` records it. */
static inline __attribute__((always_inline)) located locate_span(const myl_native_heap *heap, const myl_native_dictionary *dict, span_key key) {
    myl_native_dictionary_probe *last=(myl_native_dictionary_probe *)&dict->last;
    size_t epoch=0;
    int dated=span_epoch(heap,&epoch);
    if (dated && last->state==PROBE_ABSENT_SPAN && same_query(last,key) && last->epoch==epoch)
        return (located){NO_ENTRY,last->slot,last->hash};
    located found={NO_ENTRY,NO_SLOT,0};
    if (!dict->index.capacity) {
        for (size_t i=0;i<dict->entries->length;i++)
            if (same_span(entry_at(dict,i),key)) { found.entry=i; break; }
    } else {
        uint32_t hash=myl_native_octets_hash(key.octets,key.span->bytes);
        const uint64_t *slots=dict->index.slots;
        size_t mask=dict->index.capacity-1, at=hash&mask;
        found=(located){NO_ENTRY,NO_SLOT,hash};
        for (uint64_t slot;(slot=slots[at]);at=(at+1)&mask) {
            if ((uint32_t)(slot>>32)!=hash) continue;
            size_t entry=MYL_NATIVE_DICTIONARY_SLOT_ENTRY(slot)-1;
            if (same_span(entry_at(dict,entry),key)) { found.entry=entry; break; }
        }
        found.slot=(uint32_t)at;
    }
    uint64_t text=(uint64_t)(uintptr_t)key.text;
    if (found.entry!=NO_ENTRY) *last=(myl_native_dictionary_probe){.key=text,.entry=found.entry,.state=PROBE_FOUND_SPAN,.offset=key.span->offset,.bytes=key.span->bytes};
    else if (dated && found.slot!=NO_SLOT) *last=(myl_native_dictionary_probe){.key=text,.slot=found.slot,.hash=found.hash,.state=PROBE_ABSENT_SPAN,.offset=key.span->offset,.bytes=key.span->bytes,.epoch=epoch};
    else last->state=PROBE_NONE;
    return found;
}
/* The entry holding a described slice, from the record or one walk. */
static inline __attribute__((always_inline)) located find_span(const myl_native_heap *heap, const myl_native_dictionary *dict, span_key key) {
    size_t entry=recall_span(dict,key);
    if (entry!=NO_ENTRY) return (located){entry,NO_SLOT,0};
    return locate_span(heap,dict,key);
}
int myl_native_dictionary_read_range(const myl_native_heap *heap, const myl_native_dictionary *dict, const myl_native_text *text, const myl_native_text_span *span, void *output) {
    size_t index=find_span(heap,dict,span_of(text,span)).entry;
    if (index==NO_ENTRY) return 0;
    copy_value(dict,output,entry_at(dict,index)+dict->value_offset);
    return 1;
}
const void *myl_native_dictionary_find_range(const myl_native_heap *heap, const myl_native_dictionary *dict, const myl_native_text *text, const myl_native_text_span *span) {
    size_t index=find_span(heap,dict,span_of(text,span)).entry;
    return index==NO_ENTRY?NULL:entry_at(dict,index)+dict->value_offset;
}
int myl_native_dictionary_contains_range(const myl_native_heap *heap, const myl_native_dictionary *dict, const myl_native_text *text, const myl_native_text_span *span) {
    return find_span(heap,dict,span_of(text,span)).entry!=NO_ENTRY;
}
int myl_native_dictionary_overwrite_range(const myl_native_heap *heap, myl_native_dictionary *dict, const myl_native_text *text, const myl_native_text_span *span, const void *value) {
    size_t index=find_span(heap,dict,span_of(text,span)).entry;
    if (index==NO_ENTRY) return 0;
    if (myl_rc_enabled(heap)) return myl_rc_native_retain_replace((myl_native_heap *)heap,dict->value,entry_at(dict,index)+dict->value_offset,value,myl_native_header_region(dict));
    copy_value(dict,entry_at(dict,index)+dict->value_offset,value);
    return 1;
}
/* A new key from a described slice: its owned text is built in the dictionary's
 * own region, where `insert` would have put an owned copy of a view, and carries
 * the hash the walk already computed, so the insertion hashes nothing. */
static __attribute__((noinline)) int insert_span(myl_native_heap *heap, myl_native_dictionary *dict, myl_native_text *text, const myl_native_text_span *span, const void *value, located at) {
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    myl_native_text *owned=myl_native_text_piece_at(heap,text,span,myl_native_object_region(heap,dict));
    myl_native_root_pop(heap,&root);
    if (!owned) return 0;
    if (at.slot!=NO_SLOT) {
        owned->hash=at.hash;
        owned->flags|=MYL_TEXT_HASHED;
    }
    int ok=insert(heap,dict,&owned,value,at);
    /* The text is live — the generated frame still holds it — so the new entry
     * is recorded for this same span, as a found probe of it would be. */
    if (ok) dict->last=(myl_native_dictionary_probe){.key=(uint64_t)(uintptr_t)text,.entry=dict->entries->length-1,.state=PROBE_FOUND_SPAN,.offset=span->offset,.bytes=span->bytes};
    return ok;
}
int myl_native_dictionary_write_range(myl_native_heap *heap, myl_native_dictionary *dict, myl_native_text *text, const myl_native_text_span *span, const void *value) {
    located at=find_span(heap,dict,span_of(text,span));
    if (myl_rc_enabled(heap)) {
        if (at.entry!=NO_ENTRY) return myl_rc_native_retain_replace(heap,dict->value,entry_at(dict,at.entry)+dict->value_offset,value,myl_native_header_region(dict));
        myl_native_text *owned=myl_native_text_piece_at(heap,text,span,myl_native_header_region(dict));
        if (!owned) return 0;
        int ok=rc_insert(heap,dict,&owned,value);
        myl_rc_owner_release(heap,owned);
        return ok;
    }
    if (at.entry==NO_ENTRY) return insert_span(heap,dict,text,span,value,at);
    copy_value(dict,entry_at(dict,at.entry)+dict->value_offset,value);
    return 1;
}
/* Cursor reads keep pinned entry addresses stable and visit a sparse source
 * in linear time. GC readers retain their historical initial compaction. */
int myl_native_dictionary_next(const myl_native_dictionary *dict, size_t *cursor, const void **key, const void **value) {
    if (!*cursor && !rc_dictionary(dict)) myl_native_dictionary_settle(dict);
    while (*cursor<dict->entries->length) {
        const unsigned char *entry=entry_at(dict,(*cursor)++);
        if (rc_dictionary(dict)) {
            uint64_t marker;
            memcpy(&marker,entry+dict->entry_type.size-8,8);
            if (!(uint32_t)marker) continue;
        }
        *key=entry;
        *value=entry+dict->value_offset;
        return 1;
    }
    return 0;
}
myl_native_list *myl_native_dictionary_snapshot(myl_native_heap *heap, myl_native_dictionary *dict, int keys) {
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    const myl_native_type *element=keys?dict->key:dict->value;
    myl_native_list *result=myl_native_list_new(heap,element,myl_native_dictionary_length(dict));
    if (result) {
        size_t cursor=0;
        const void *key, *value;
        while (myl_native_dictionary_next(dict,&cursor,&key,&value)) {
            const void *item=keys?key:value;
            if (myl_rc_enabled(heap)) {
                if (!myl_rc_list_append(heap,result,item)) {
                    myl_rc_native_abort(heap,result); result=NULL; break;
                }
            } else {
                memcpy((unsigned char *)result->storage+result->length*element->size,item,element->size);
                result->length++;
            }
        }
    }
    myl_native_root_pop(heap,&root);
    return result;
}
static const unsigned char *ordinal_entry(const myl_native_dictionary *dict, size_t index) {
    if (rc_dictionary(dict) && dict->dead && (((const myl_native_object *)dict-1)->mark&MYL_NATIVE_OBJECT_PINNED)) {
        size_t cursor=0;
        const void *key, *value;
        while (myl_native_dictionary_next(dict,&cursor,&key,&value))
            if (!index--) return key;
        return NULL;
    }
    myl_native_dictionary_settle(dict);
    return index<dict->entries->length?entry_at(dict,index):NULL;
}
int myl_native_dictionary_key_at(const myl_native_dictionary *dict, size_t index, void *output) {
    const unsigned char *entry=ordinal_entry(dict,index);
    if (!entry) return 0;
    memmove(output,entry,dict->key->size);
    return 1;
}
int myl_native_dictionary_value_at(const myl_native_dictionary *dict, size_t index, void *output) {
    const unsigned char *entry=ordinal_entry(dict,index);
    if (!entry) return 0;
    memmove(output,entry+dict->value_offset,dict->value->size);
    return 1;
}
/* Empty the slot at `hole` and close the gap linear probing needs closed: every
 * later slot of the same run whose home does not lie cyclically in (hole, at]
 * moves back into the hole, so every key stays reachable from its home. */
static void index_remove(const myl_native_dictionary_index *index, size_t hole) {
    size_t mask=index->capacity-1;
    for (size_t at=(hole+1)&mask;index->slots[at];at=(at+1)&mask) {
        size_t home=(size_t)(index->slots[at]>>32)&mask;
        int stays=hole<=at ? hole<home && home<=at : hole<home || home<=at;
        if (stays) continue;
        index->slots[hole]=index->slots[at];
        hole=at;
    }
    index->slots[hole]=0;
}
/* Forget entry `index`, whose slot is already out of the table. An entry in the
 * middle of the list is only counted dead: its bytes stay, still traced, until
 * `settle` squeezes them out, so the removal moves nothing (DICT-REMOVE-1). The
 * last entry is cut off instead, together with every dead entry before it, so
 * the last entry of the list is always a live one. */
static void drop_entry(myl_native_dictionary *dict, size_t index) {
    unsigned char *storage=dict->entries->storage;
    size_t size=dict->entry_type.size;
    dict->entries->generation++;
    if (index+1<dict->entries->length) { dict->dead++; return; }
    dict->entries->length--;
    memset(storage+dict->entries->length*size,0,size);
    while (dict->dead && dict->entries->length && slot_of(dict,dict->entries->length-1)==SIZE_MAX) {
        dict->entries->length--;
        memset(storage+dict->entries->length*size,0,size);
        dict->dead--;
    }
}
/* Remove entry `index` of a dictionary without a table: every later entry moves
 * down one place, as the scan that answers its lookups expects. */
static void shift_out(myl_native_dictionary *dict, size_t index) {
    unsigned char *entries=dict->entries->storage;
    size_t size=dict->entry_type.size;
    size_t moved=dict->entries->length-index-1;
    if (moved) memmove(entries+index*size,entries+(index+1)*size,moved*size);
    dict->entries->length--;
    memset(entries+dict->entries->length*size,0,size);
    dict->entries->generation++;
}
int myl_native_dictionary_pop(myl_native_dictionary *dict, const void *key, void *output) {
    located at=find(dict,key);
    if (at.entry==NO_ENTRY) return 0;
    size_t index=at.entry;
    memcpy(output,entry_at(dict,index)+dict->value_offset,dict->value->size);
    dict->last.state=PROBE_NONE;
    if (!dict->index.capacity) { shift_out(dict,index); return 1; }
    /* One slot leaves the table, closing its collision run behind it, and no
     * other entry moves: removal is expected constant time and allocates
     * nothing. */
    index_remove(&dict->index,at.slot!=NO_SLOT?at.slot:slot_of(dict,index));
    drop_entry(dict,index);
    return 1;
}
int myl_native_dictionary_pop_last(myl_native_dictionary *dict, void *output) {
    if (!dict->entries->length) return 0;
    size_t index=dict->entries->length-1;
    memcpy(output,entry_at(dict,index),dict->key->size);
    dict->last.state=PROBE_NONE;
    if (!dict->index.capacity) { shift_out(dict,index); return 1; }
    size_t at=slot_of(dict,index);
    if (at!=SIZE_MAX) index_remove(&dict->index,at);
    drop_entry(dict,index);
    return 1;
}
const void *myl_native_dictionary_find(const myl_native_dictionary *dict, const void *key) {
    size_t index=find(dict,key).entry;
    return index==NO_ENTRY?NULL:entry_at(dict,index)+dict->value_offset;
}
int myl_native_dictionary_update(myl_native_heap *heap, myl_native_dictionary *dict, const myl_native_dictionary *source) {
    size_t cursor=0;
    const void *key, *value;
    while (myl_native_dictionary_next(source,&cursor,&key,&value))
        if (!myl_native_dictionary_write(heap,dict,key,value)) return 0;
    return 1;
}
static int rc_existing_result(myl_native_heap *heap, const myl_native_type *type, void *output, const void *value) {
    unsigned char local[128];
    void *staged=type->size<=sizeof local?local:myl_rc_storage_bytes(heap,type->size,0);
    if (!staged) return 0;
    int ok=myl_rc_native_retain(heap,type,staged,value,heap->region_depth);
    if (ok) memcpy(output,staged,type->size);
    if (staged!=local) myl_rc_owner_release(heap,staged);
    return ok;
}
int myl_native_dictionary_setdefault(myl_native_heap *heap, myl_native_dictionary *dict, const void *key, const void *fallback, void *output) {
    located at=find(dict,key);
    if (myl_rc_enabled(heap)) {
        if (at.entry==NO_ENTRY) return rc_insert_result(heap,dict,key,fallback,output);
        const void *value=entry_at(dict,at.entry)+dict->value_offset;
        return rc_existing_result(heap,dict->value,output,value);
    }
    if (at.entry!=NO_ENTRY) {
        copy_value(dict,output,entry_at(dict,at.entry)+dict->value_offset);
        return 1;
    }
    if (!insert(heap,dict,key,fallback,at)) return 0;
    memcpy(output,fallback,dict->value->size);
    return 1;
}
void myl_native_dictionary_clear(myl_native_dictionary *dict) {
    dict->last.state=PROBE_NONE;
    dict->dead=0;
    if (dict->entries->length) {
        memset(dict->entries->storage,0,dict->entries->length*dict->entry_type.size);
        dict->entries->length=0;
        dict->entries->generation++;
        if (dict->index.capacity) memset(dict->index.slots,0,dict->index.capacity*sizeof(uint64_t));
    }
}
void myl_native_dictionary_reindex(myl_native_heap *heap, myl_native_dictionary *dict) {
    /* Whatever table the dictionary carried described keys that were not yet
     * filled, so it is dropped and a fresh one hashes every key. */
    dict->last.state=PROBE_NONE;
    dict->dead=0;
    void *old=dict->index.slots;
    dict->index=(myl_native_dictionary_index){.slots=NULL,.capacity=0};
    if (myl_rc_enabled(heap)) myl_rc_owner_release(heap,old);
    index_reserve(heap,dict,dict->entries->length);
}
int myl_native_dictionary_header(const void *payload) {
    return payload && (((const myl_native_object *)payload-1)->element==&dict_type || rc_dictionary(payload));
}
/* Give `dict` its own entry descriptor, shaped like `from`'s: the field table
 * and scan plan it names live inside `dict`, so they die with it. */
static void entry_shape(myl_native_dictionary *dict, const myl_native_dictionary *from) {
    memcpy(dict->entry_fields,from->entry_fields,sizeof dict->entry_fields);
    memcpy(dict->entry_scan,from->entry_scan,sizeof dict->entry_scan);
    dict->entry_type=from->entry_type;
    dict->entry_type.fields=dict->entry_fields;
    if (from->entry_type.scan) dict->entry_type.scan=dict->entry_scan;
}
myl_native_dictionary *myl_native_dictionary_clone_at(myl_native_heap *heap, const myl_native_dictionary *input, unsigned region) {
    if (myl_rc_enabled(heap)) return rc_dict_clone(heap,input,region);
    myl_native_dictionary_settle(input);
    const myl_native_dictionary *rooted=input;
    myl_native_root source_root,clone_root;
    myl_native_root_push(heap,&source_root,&rooted,&pointer_type);
    myl_native_dictionary *dict=myl_native_heap_alloc_at(heap,&dict_type,1,region);
    if (dict) {
        myl_native_root_push(heap,&clone_root,&dict,&pointer_type);
        dict->key=rooted->key; dict->value=rooted->value; dict->value_offset=rooted->value_offset;
        dict->string_keys=rooted->string_keys; dict->key_kind=rooted->key_kind; dict->dead=0;
        entry_shape(dict,rooted);
        dict->index=(myl_native_dictionary_index){.slots=NULL,.capacity=0};
        dict->last=(myl_native_dictionary_probe){.state=PROBE_NONE};
        dict->entries=myl_native_list_clone_at(heap,rooted->entries,&dict->entry_type,region);
        size_t capacity=rooted->index.capacity;
        if (dict->entries && capacity) {
            int exhausted=heap->exhausted;
            uint64_t *slots=myl_native_heap_alloc_at(heap,&slot_type,capacity,region);
            if (slots) {
                memcpy(slots,rooted->index.slots,capacity*sizeof(uint64_t));
                dict->index=(myl_native_dictionary_index){.slots=slots,.capacity=capacity};
            } else heap->exhausted=exhausted;
        }
        myl_native_root_pop(heap,&clone_root);
        if (!dict->entries) dict=NULL;
    }
    myl_native_root_pop(heap,&source_root);
    return dict;
}
myl_native_dictionary *myl_native_dictionary_copy(myl_native_heap *heap, const myl_native_dictionary *input) {
    const myl_native_dictionary *rooted=input;
    myl_native_root root;
    myl_native_root_push(heap,&root,&rooted,&pointer_type);
    myl_native_dictionary *result=myl_native_dictionary_new(heap,input->key,input->value,input->string_keys);
    if (result && !myl_native_dictionary_update(heap,result,input)) {
        if (myl_rc_enabled(heap)) myl_rc_native_abort(heap,result);
        result=NULL;
    }
    myl_native_root_pop(heap,&root);
    return result;
}
static void rc_entry_release(myl_native_heap *heap, myl_native_dictionary *dict, size_t index) {
    unsigned char *entry=entry_at(dict,index);
    const myl_rc_descriptor *key=myl_rc_descriptor_find(heap,dict->key);
    const myl_rc_descriptor *value=myl_rc_descriptor_find(heap,dict->value);
    if (!key || !value) abort();
    myl_rc_edges_release(heap,key->shape,entry,1);
    myl_rc_edges_release(heap,value->shape,entry+dict->value_offset,1);
}
/* The index already identifies every live entry exactly once. Destruction
 * neither hashes dead keys nor consults dictionary-owned entry descriptors. */
static void rc_dictionary_edges(myl_native_heap *heap, void *payload, size_t count) {
    (void)count;
    myl_native_dictionary *dict=payload;
    if (dict->entries) {
        if (dict->index.capacity) {
            for (size_t i=0;i<dict->index.capacity;i++)
                if (dict->index.slots[i]) rc_entry_release(heap,dict,MYL_NATIVE_DICTIONARY_SLOT_ENTRY(dict->index.slots[i])-1);
        } else {
            if (dict->dead) abort();
            for (size_t i=0;i<dict->entries->length;i++) rc_entry_release(heap,dict,i);
        }
    }
    myl_rc_edge_release(heap,dict->entries);
    myl_rc_edge_release(heap,dict->index.slots);
}
static const myl_rc_shape rc_dict_shape={.size=sizeof(myl_native_dictionary),.kind=MYL_RC_SHAPE_NONE};
static myl_rc_status rc_dict_clone_adapter(myl_native_heap *heap, const void *payload, unsigned region, void **out) {
    *out=rc_dict_clone(heap,payload,region);
    return myl_rc_native_result(heap,*out);
}
static const myl_rc_descriptor rc_dict_descriptor={.type=&rc_dict_type,.shape=&rc_dict_shape,.edges=rc_dictionary_edges,.clone=rc_dict_clone_adapter,.shell=rc_dict_shell,.next=rc_dict_next};
static const myl_rc_module rc_dict_module={.abi=MYL_RC_ABI_VERSION,.descriptors=&rc_dict_descriptor,.descriptor_count=1};
static int rc_dict_prepare(myl_native_heap *heap, const myl_native_type *key, const myl_native_type *value) {
    if (!myl_rc_native_shape(heap,key) || !myl_rc_native_shape(heap,value)) return 0;
    myl_rc_status status=myl_rc_module_register(heap,&rc_dict_module);
    if (status!=MYL_RC_OK) myl_rc_record_failure(heap,status);
    return status==MYL_RC_OK;
}
static int rc_insert_result(myl_native_heap *heap, myl_native_dictionary *dict, const void *key, const void *value, void *output) {
    size_t width=dict->entry_type.size, extra=output?dict->value->size:0;
    if (width>(SIZE_MAX-extra)/2) return 0;
    size_t bytes=width*2+extra;
    unsigned char local[384];
    unsigned char *scratch=bytes<=sizeof local?local:myl_rc_storage_bytes(heap,bytes,0);
    if (!scratch) return 0;
    unsigned char *entry=scratch+width, *result=entry+width;
    /* Inputs may point into this dictionary. Save borrowed bytes before any
     * capacity growth or compaction moves their source slots. */
    memset(scratch,0,bytes);
    memcpy(scratch,key,dict->key->size);
    memcpy(scratch+dict->value_offset,value,dict->value->size);
    unsigned region=myl_native_header_region(dict);
    myl_native_text *owned=NULL;
    int ok=0;
    if (dict->dead && dict->dead*2>=dict->entries->length) myl_native_dictionary_settle(dict);
    if (dict->entries->length==SIZE_MAX || dict->entries->generation==UINT64_MAX) goto done;
    if (!myl_rc_list_storage_reserve(heap,dict->entries,dict->entries->length+1)) goto done;
    index_reserve(heap,dict,dict->entries->length+1);
    if (dict->key_kind==KEY_TEXT && (text_of(scratch)->flags&MYL_TEXT_VIEW)) {
        owned=myl_native_text_own_at(heap,(myl_native_text *)text_of(scratch),region);
        if (!owned) goto done;
        memcpy(scratch,&owned,sizeof owned);
    }
    const myl_rc_descriptor *key_shape=myl_rc_descriptor_find(heap,dict->key);
    const myl_rc_descriptor *value_shape=myl_rc_descriptor_find(heap,dict->value);
    if (!key_shape || !value_shape) abort();
    myl_rc_slot targets[]={
        {.shape=key_shape->shape,.address=entry,.region=region},
        {.shape=value_shape->shape,.address=entry+dict->value_offset,.region=region},
        {.shape=value_shape->shape,.address=result,.region=heap->region_depth}
    };
    myl_rc_slot sources[]={
        {.shape=key_shape->shape,.address=scratch},
        {.shape=value_shape->shape,.address=scratch+dict->value_offset},
        {.shape=value_shape->shape,.address=scratch+dict->value_offset}
    };
    myl_rc_status status=myl_rc_value_retain_many(heap,targets,sources,output?3:2);
    if (status!=MYL_RC_OK) { myl_rc_record_failure(heap,status); goto done; }
    uint32_t hash=hash_key(dict,entry);
    uint64_t marker=((uint64_t)hash<<32)|1;
    memcpy(entry+width-8,&marker,8);
    size_t added=dict->entries->length;
    memcpy(entry_at(dict,added),entry,width);
    dict->entries->length++;
    dict->entries->generation++;
    if (dict->index.capacity) index_place(&dict->index,pack_slot(hash,added));
    dict->last.state=PROBE_NONE;
    if (output) memcpy(output,result,dict->value->size);
    ok=1;
done:
    if (owned) myl_rc_owner_release(heap,owned);
    if (scratch!=local) myl_rc_owner_release(heap,scratch);
    return ok;
}
static int rc_insert(myl_native_heap *heap, myl_native_dictionary *dict, const void *key, const void *value) {
    return rc_insert_result(heap,dict,key,value,NULL);
}
int myl_rc_dictionary_overwrite(myl_native_heap *heap, myl_native_dictionary *dict, const void *key, const void *value) {
    size_t at=find(dict,key).entry;
    if (at==NO_ENTRY) return 0;
    return myl_rc_native_retain_replace(heap,dict->value,entry_at(dict,at)+dict->value_offset,value,myl_native_header_region(dict));
}
static int rc_pop_entry(myl_native_heap *heap, myl_native_dictionary *dict, located at, void *output, int key_result) {
    if (dict->entries->generation==UINT64_MAX) return -1;
    unsigned char *entry=entry_at(dict,at.entry);
    const myl_native_type *result=key_result?dict->key:dict->value;
    void *source=entry+(key_result?0:dict->value_offset);
    if (!myl_rc_native_take(heap,result,output,source,heap->region_depth)) return -1;
    if (dict->index.capacity) index_remove(&dict->index,at.slot!=NO_SLOT?at.slot:slot_of(dict,at.entry));
    const myl_rc_descriptor *discard=myl_rc_descriptor_find(heap,key_result?dict->value:dict->key);
    if (!discard) abort();
    myl_rc_edges_release(heap,discard->shape,entry+(key_result?dict->value_offset:0),1);
    memset(entry,0,dict->entry_type.size);
    dict->last.state=PROBE_NONE;
    if (dict->index.capacity) drop_entry(dict,at.entry);
    else shift_out(dict,at.entry);
    myl_rc_drain(heap);
    return 1;
}
int myl_rc_dictionary_pop(myl_native_heap *heap, myl_native_dictionary *dict, const void *key, void *output) {
    located at=find(dict,key);
    return at.entry==NO_ENTRY?0:rc_pop_entry(heap,dict,at,output,0);
}
int myl_rc_dictionary_pop_last(myl_native_heap *heap, myl_native_dictionary *dict, void *output) {
    if (!dict->entries->length) return 0;
    located at={.entry=dict->entries->length-1,.slot=NO_SLOT};
    return rc_pop_entry(heap,dict,at,output,1);
}
void myl_rc_dictionary_clear(myl_native_heap *heap, myl_native_dictionary *dict) {
    if (dict->index.capacity) {
        for (size_t i=0;i<dict->index.capacity;i++)
            if (dict->index.slots[i]) rc_entry_release(heap,dict,MYL_NATIVE_DICTIONARY_SLOT_ENTRY(dict->index.slots[i])-1);
    } else for (size_t i=0;i<dict->entries->length;i++) rc_entry_release(heap,dict,i);
    myl_native_dictionary_clear(dict);
    myl_rc_drain(heap);
}
static myl_native_dictionary *rc_dict_clone(myl_native_heap *heap, const myl_native_dictionary *input, unsigned region) {
    unsigned saved=heap->region_depth;
    heap->region_depth=region;
    myl_native_dictionary *clone=myl_native_dictionary_new(heap,input->key,input->value,input->string_keys);
    heap->region_depth=saved;
    if (!clone) return NULL;
    for (size_t i=0;i<input->entries->length;i++) {
        const unsigned char *entry=entry_at(input,i);
        uint64_t marker;
        memcpy(&marker,entry+input->entry_type.size-8,8);
        if (!(uint32_t)marker) continue;
        if (!rc_insert(heap,clone,entry,entry+input->value_offset)) {
            myl_rc_native_abort(heap,clone); return NULL;
        }
    }
    return clone;
}
/* Preserve sparse positions and stored hashes without settling a receiver
 * whose backing may be captured. Every target key/value starts with zero
 * owning pointers, so the iterative operation can abort at any child edge. */
static myl_rc_status rc_dict_shell(myl_native_heap *heap, const void *payload, unsigned region, void **out) {
    const myl_native_dictionary *source=payload;
    unsigned saved=heap->region_depth;
    heap->region_depth=region;
    myl_native_dictionary *copy=myl_native_dictionary_new(heap,source->key,source->value,source->string_keys);
    heap->region_depth=saved;
    *out=NULL;
    if (!copy) return myl_rc_native_result(heap,NULL);
    if (!myl_rc_list_storage_reserve(heap,copy->entries,source->entries->length)) goto failed;
    uint64_t *slots=NULL;
    if (source->index.capacity) {
        slots=myl_native_heap_alloc_at(heap,&slot_type,source->index.capacity,region);
        if (!slots) goto failed;
    }
    const myl_rc_descriptor *key=myl_rc_descriptor_find(heap,source->key);
    const myl_rc_descriptor *value=myl_rc_descriptor_find(heap,source->value);
    if (!key || !value) abort();
    for (size_t i=0;i<source->entries->length;i++) {
        const unsigned char *entry=entry_at(source,i);
        unsigned char *target=entry_at(copy,i);
        uint64_t marker;
        memcpy(&marker,entry+source->entry_type.size-8,8);
        if (!(uint32_t)marker) continue;
        memcpy(target,entry,source->entry_type.size);
        myl_rc_value_seed(heap,key->shape,target,entry,1);
        myl_rc_value_seed(heap,value->shape,target+copy->value_offset,entry+source->value_offset,1);
    }
    copy->entries->length=source->entries->length;
    copy->dead=source->dead;
    if (slots) {
        memcpy(slots,source->index.slots,source->index.capacity*sizeof *slots);
        copy->index=(myl_native_dictionary_index){.slots=slots,.capacity=source->index.capacity};
    }
    *out=copy;
    return MYL_RC_OK;
failed:
    myl_rc_native_abort(heap,copy);
    return myl_rc_native_result(heap,NULL);
}
static int rc_dict_next(myl_native_heap *heap, const void *payload, void *target, size_t *cursor, myl_rc_slot *to, myl_rc_slot *from) {
    const myl_native_dictionary *source=payload;
    myl_native_dictionary *copy=target;
    while (*cursor/2<source->entries->length) {
        size_t index=*cursor/2;
        unsigned is_value=(unsigned)((*cursor)++&1);
        const unsigned char *entry=entry_at(source,index);
        uint64_t marker;
        memcpy(&marker,entry+source->entry_type.size-8,8);
        if (!(uint32_t)marker) continue;
        const myl_rc_descriptor *descriptor=myl_rc_descriptor_find(heap,is_value?source->value:source->key);
        if (!descriptor) abort();
        if (descriptor->shape->kind==MYL_RC_SHAPE_NONE) continue;
        size_t offset=is_value?source->value_offset:0;
        *to=(myl_rc_slot){.shape=descriptor->shape,.address=entry_at(copy,index)+offset,.container=copy,.region=myl_native_header_region(copy)};
        *from=(myl_rc_slot){.shape=descriptor->shape,.address=(void *)(entry+offset),.container=(void *)source,.region=myl_native_header_region(source)};
        return 1;
    }
    return 0;
}
