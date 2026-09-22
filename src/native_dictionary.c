#include "native_dictionary.h"
#include <stdlib.h>
#include <string.h>
static const myl_native_type pointer_type={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
/* Slots are plain integers, so the collector keeps the block alive through the
 * traced field below and never walks what it holds. */
static const myl_native_type slot_type={.size=sizeof(uint64_t),.alignment=_Alignof(uint64_t),.kind=MYL_NATIVE_PLAIN};
static const myl_native_field dict_fields[]={
    {.offset=offsetof(myl_native_dictionary,entries),.type=&pointer_type},
    {.offset=offsetof(myl_native_dictionary,index)+offsetof(myl_native_dictionary_index,slots),.type=&pointer_type}};
static const myl_native_type dict_type={.size=sizeof(myl_native_dictionary),.alignment=_Alignof(myl_native_dictionary),.kind=MYL_NATIVE_RECORD,.fields=dict_fields,.field_count=2};
/* How a dictionary's keys hash and compare: a `str` key by its text's octets, an
 * eight-byte integer as one word, a narrower integer as its zero-extended bytes,
 * and a key wider than a word (only reachable from C) as a byte string. */
enum { KEY_TEXT, KEY_WORD, KEY_NARROW, KEY_WIDE };
/* What the last probe learned: nothing, the key's entry, or the key's absence. */
enum { PROBE_NONE, PROBE_FOUND, PROBE_ABSENT };
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
    myl_native_dictionary *dict=myl_native_heap_alloc(heap,&dict_type,1);
    if (!dict) return NULL;
    dict->key=key; dict->value=value; dict->value_offset=offset; dict->string_keys=string_keys;
    dict->key_kind=string_keys?KEY_TEXT:key->size==8?KEY_WORD:key->size<8?KEY_NARROW:KEY_WIDE;
    dict->entry_fields[0]=(myl_native_field){.offset=0,.type=key};
    dict->entry_fields[1]=(myl_native_field){.offset=offset,.type=value};
    dict->entry_type=(myl_native_type){.size=size,.alignment=alignment,.kind=MYL_NATIVE_RECORD,.fields=dict->entry_fields,.field_count=2};
    /* An empty dictionary carries no table: the first write sizes one. */
    dict->index=(myl_native_dictionary_index){.slots=NULL,.capacity=0};
    dict->last=(myl_native_dictionary_probe){.state=PROBE_NONE};
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    dict->entries=myl_native_list_new(heap,&dict->entry_type,0);
    myl_native_root_pop(heap,&root);
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
 * always equal to itself, which settles most matches without a payload read. */
static inline int same_text(const myl_native_text *a, const myl_native_text *b) {
    return a==b || (a->bytes==b->bytes && same_octets(myl_native_text_storage(a),myl_native_text_storage(b),a->bytes));
}
static inline int same_key(const myl_native_dictionary *dict, const void *entry, const void *key) {
    switch (dict->key_kind) {
    case KEY_TEXT: return same_text(text_of(entry),text_of(key));
    case KEY_WIDE: return same_octets(entry,key,dict->key->size);
    default: return scalar_bits(entry,dict->key->size)==scalar_bits(key,dict->key->size);
    }
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
/* The table hash of one key. Equal keys have equal bytes and so equal hashes. */
static uint32_t hash_key(const myl_native_dictionary *dict, const void *key) {
    switch (dict->key_kind) {
    case KEY_TEXT: return text_hash(text_of(key));
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
/* Size the table for `needed` entries at a load factor of at most 5/8. A grown
 * table is refilled from the old one's stored hashes, so growth reads no key.
 * A refused allocation drops the index rather than failing the write: lookups
 * fall back to scanning, which is slower and exactly as correct, and the
 * caller's budget flag is left as it was so a later trap still names the real
 * cause. Any change to the table forgets the last probe. */
static void index_reserve(myl_native_heap *heap, myl_native_dictionary *dict, size_t needed) {
    if (dict->index.capacity && needed<=MAX_CAPACITY/8*5 && needed*8<=dict->index.capacity*5) return;
    dict->last.state=PROBE_NONE;
    size_t capacity=dict->index.capacity?dict->index.capacity:8;
    if (needed>MAX_CAPACITY/8*5) { dict->index.slots=NULL; dict->index.capacity=0; return; }
    while (needed*8>capacity*5) capacity*=2;
    int exhausted=heap->exhausted;
    myl_native_root root;
    myl_native_root_push(heap,&root,&dict,&pointer_type);
    uint64_t *slots=myl_native_heap_alloc_at(heap,&slot_type,capacity,myl_native_object_region(heap,dict));
    myl_native_root_pop(heap,&root);
    if (!slots) {
        heap->exhausted=exhausted;
        dict->index.slots=NULL; dict->index.capacity=0;
        return;
    }
    myl_native_dictionary_index old=dict->index;
    dict->index.slots=slots; dict->index.capacity=capacity;
    if (!old.capacity) { index_fill(dict); return; }
    for (size_t at=0;at<old.capacity;at++)
        if (old.slots[at]) index_place(&dict->index,old.slots[at]);
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
    const uint64_t *slots=dict->index.slots;
    const unsigned char *storage=dict->entries->storage;
    size_t mask=dict->index.capacity-1, at=hash&mask, stride=dict->entry_type.size;
    for (uint64_t slot;(slot=slots[at]);at=(at+1)&mask) {
        if ((uint32_t)(slot>>32)!=hash) continue;
        size_t entry=MYL_NATIVE_DICTIONARY_SLOT_ENTRY(slot)-1;
        if (same_text(text_of(storage+entry*stride),text)) return (located){entry,(uint32_t)at,hash};
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
    if (dict->key_kind==KEY_TEXT) return same_text(text_of(entry),text_of(key))?last->entry:NO_ENTRY;
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
    if (!dict->index.capacity || dict->key_kind==KEY_WIDE) found=probe_any(dict,key);
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
size_t myl_native_dictionary_length(const myl_native_dictionary *dict) { return dict->entries->length; }
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
    size_t index=recall(dict,key);
    if (index==NO_ENTRY) return write_walk(heap,dict,key,value);
    copy_value(dict,entry_at(dict,index)+dict->value_offset,value);
    return 1;
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
int myl_native_dictionary_pop(myl_native_dictionary *dict, const void *key, void *output) {
    located at=find(dict,key);
    if (at.entry==NO_ENTRY) return 0;
    size_t index=at.entry;
    unsigned char *entries=dict->entries->storage;
    size_t size=dict->entry_type.size;
    memcpy(output,entries+index*size+dict->value_offset,dict->value->size);
    dict->last.state=PROBE_NONE;
    /* Every entry after the removed one moves down, so every slot that names one
     * is renumbered in place: no key is rehashed and nothing is allocated, which
     * is what lets `pop` keep its heap-free signature, and the walk over the
     * table keeps `pop` linear. */
    if (dict->index.capacity) {
        size_t slot=at.slot;
        if (slot==NO_SLOT) {
            size_t mask=dict->index.capacity-1;
            for (slot=hash_key(dict,key)&mask;MYL_NATIVE_DICTIONARY_SLOT_ENTRY(dict->index.slots[slot])!=index+1;slot=(slot+1)&mask) {}
        }
        index_remove(&dict->index,slot);
        for (size_t i=0;i<dict->index.capacity;i++)
            if (MYL_NATIVE_DICTIONARY_SLOT_ENTRY(dict->index.slots[i])>index+1) dict->index.slots[i]--;
    }
    size_t moved=dict->entries->length-index-1;
    if (moved) memmove(entries+index*size,entries+(index+1)*size,moved*size);
    dict->entries->length--;
    memset(entries+dict->entries->length*size,0,size);
    dict->entries->generation++;
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
    located at=find(dict,key);
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
    dict->index=(myl_native_dictionary_index){.slots=NULL,.capacity=0};
    index_reserve(heap,dict,dict->entries->length);
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
