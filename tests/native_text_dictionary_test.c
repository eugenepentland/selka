#include "native_dictionary.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static myl_native_text *text(myl_native_heap *heap,const char *bytes) { return myl_native_text_from_utf8(heap,(const unsigned char *)bytes,strlen(bytes)); }
static void equals(myl_native_text *value,const char *bytes) {
    unsigned char buffer[128];
    size_t length=myl_native_text_utf8(value,buffer,sizeof(buffer));
    assert(length==strlen(bytes) && !memcmp(buffer,bytes,length));
}
/* A 16-byte key with interior padding, the shape a record key would have. */
typedef struct { int32_t tag; int64_t serial; } Wide;
static const myl_native_type wide={.size=sizeof(Wide),.alignment=_Alignof(Wide),.kind=MYL_NATIVE_PLAIN};
/* Every live slot names an entry that exists, no entry is named twice, none is
   left unnamed, every slot is reachable by linear probing from the home its
   stored hash names, and the load factor the writer promised still holds. */
static void index_sound(const myl_native_dictionary *dict) {
    if (!dict->index.capacity) return;
    assert(!(dict->index.capacity&(dict->index.capacity-1)));
    assert(dict->entries->length*8<=dict->index.capacity*5);
    size_t named=0, mask=dict->index.capacity-1;
    for (size_t at=0;at<dict->index.capacity;++at) {
        size_t entry=MYL_NATIVE_DICTIONARY_SLOT_ENTRY(dict->index.slots[at]);
        if (!entry) continue;
        assert(entry-1<dict->entries->length);
        named++;
        for (size_t other=at+1;other<dict->index.capacity;++other)
            assert(MYL_NATIVE_DICTIONARY_SLOT_ENTRY(dict->index.slots[other])!=entry);
        for (size_t walk=(size_t)(dict->index.slots[at]>>32)&mask;walk!=at;walk=(walk+1)&mask)
            assert(dict->index.slots[walk]);
    }
    assert(named==dict->entries->length);
}
/* The slot a lone key lands in, read back from the table the writer filled. */
static size_t home(myl_native_heap *heap,myl_native_dictionary *dict,int64_t key) {
    int64_t value=key;
    myl_native_dictionary_clear(dict);
    assert(myl_native_dictionary_write(heap,dict,&key,&value));
    for (size_t at=0;at<dict->index.capacity;++at) if (dict->index.slots[at]) return at;
    assert(0);
    return 0;
}
/* spec-case: PY-DICT-2 -- growth, the rebuild after pop, and two keys built to
   share one home slot, which linear probing must keep telling apart. */
static void index_cases(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<26);
    myl_native_root root;
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&number,0); assert(dict);
    myl_native_root_push(&heap,&root,&dict,&pointer);
    int64_t out=0;
    for (int64_t i=0;i<4096;++i) {
        int64_t key=i*7919-1000,value=i;
        assert(myl_native_dictionary_write(&heap,dict,&key,&value));
    }
    index_sound(dict);
    assert(myl_native_dictionary_length(dict)==4096);
    for (int64_t i=0;i<4096;++i) {
        int64_t key=i*7919-1000;
        assert(myl_native_dictionary_read(dict,&key,&out) && out==i);
    }
    int64_t absent=5;
    assert(!myl_native_dictionary_contains(dict,&absent));
    /* Popping the first entry shifts every later one down a slot. */
    int64_t first=-1000;
    assert(myl_native_dictionary_pop(dict,&first,&out) && out==0);
    index_sound(dict);
    for (int64_t i=1;i<4096;++i) {
        int64_t key=i*7919-1000;
        assert(myl_native_dictionary_read(dict,&key,&out) && out==i);
    }
    assert(!myl_native_dictionary_contains(dict,&first));
    assert(myl_native_root_pop(&heap,&root));
    /* Two distinct keys built to share a home slot in a table left small on
       purpose: the second must probe past the first, both must read back, and
       removing one must leave the other reachable. */
    myl_native_dictionary *small=myl_native_dictionary_new(&heap,&number,&number,0); assert(small);
    myl_native_root_push(&heap,&root,&small,&pointer);
    size_t target=home(&heap,small,0),collider=0;
    for (int64_t candidate=1;candidate<4096 && !collider;++candidate)
        if (home(&heap,small,candidate)==target) collider=(size_t)candidate;
    assert(collider && small->index.capacity==8);
    int64_t zero=0,other=(int64_t)collider,one=1,two=2;
    myl_native_dictionary_clear(small);
    assert(myl_native_dictionary_write(&heap,small,&zero,&one));
    assert(myl_native_dictionary_write(&heap,small,&other,&two));
    index_sound(small);
    assert(myl_native_dictionary_length(small)==2);
    assert(small->index.slots[target] && small->index.slots[(target+1)&(small->index.capacity-1)]);
    assert(myl_native_dictionary_read(small,&zero,&out) && out==1);
    assert(myl_native_dictionary_read(small,&other,&out) && out==2);
    assert(myl_native_dictionary_pop(small,&zero,&out) && out==1);
    index_sound(small);
    assert(!myl_native_dictionary_contains(small,&zero));
    assert(myl_native_dictionary_read(small,&other,&out) && out==2);
    assert(myl_native_root_pop(&heap,&root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: PY-DICT-2 -- a padded key hashes the same bytes equality compares,
   and a dictionary whose index allocation is refused keeps every earlier answer. */
static void index_limits(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<26);
    myl_native_root root;
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&wide,&number,0); assert(dict);
    myl_native_root_push(&heap,&root,&dict,&pointer);
    int64_t out=0;
    for (int64_t i=0;i<2000;++i) {
        Wide key; memset(&key,0,sizeof key);
        key.tag=(int32_t)(i%7); key.serial=i;
        assert(myl_native_dictionary_write(&heap,dict,&key,&i));
    }
    index_sound(dict);
    assert(myl_native_dictionary_length(dict)==2000);
    for (int64_t i=0;i<2000;++i) {
        Wide key; memset(&key,0,sizeof key);
        key.tag=(int32_t)(i%7); key.serial=i;
        assert(myl_native_dictionary_read(dict,&key,&out) && out==i);
    }
    Wide missing; memset(&missing,0,sizeof missing);
    missing.tag=1; missing.serial=-1;
    assert(!myl_native_dictionary_contains(dict,&missing));
    assert(myl_native_root_pop(&heap,&root));
    myl_native_heap_destroy(&heap);
    /* A budget too small to keep growing: writes start failing, and everything
       the dictionary did accept still reads back, indexed or scanning. */
    myl_native_heap_init(&heap,1<<15);
    dict=myl_native_dictionary_new(&heap,&number,&number,0); assert(dict);
    myl_native_root_push(&heap,&root,&dict,&pointer);
    int64_t accepted=0;
    while (accepted<4096 && myl_native_dictionary_write(&heap,dict,&accepted,&accepted)) accepted++;
    assert(accepted && accepted<4096);
    index_sound(dict);
    assert(myl_native_dictionary_length(dict)==(size_t)accepted);
    for (int64_t i=0;i<accepted;++i)
        assert(myl_native_dictionary_read(dict,&i,&out) && out==i);
    assert(!myl_native_dictionary_contains(dict,&accepted));
    assert(myl_native_root_pop(&heap,&root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: DICT-GETORPUT-1. A read-modify-write probes one key object twice in
   a row, and the remembered entry the second probe answers with is only a hint:
   it must name the entry the first probe found even after an insertion, a `pop`
   that shifts every later entry down, a `clear`, and a lookup of a *different*
   text object holding the same content. */
static void repeated_probes_survive_a_shift(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20);
    myl_native_text *key=myl_native_text_from_utf8(&heap,(const unsigned char *)"k7",2);
    assert(key);
    myl_native_root key_root;
    myl_native_root_push(&heap,&key_root,&key,&pointer);
    /* The shape `dict[str, i64]` has: a traced text pointer per key, one word of
       value. */
    static const myl_native_type text_key={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
    myl_native_dictionary *counts=myl_native_dictionary_new(&heap,&text_key,&number,1);
    assert(counts);
    myl_native_root dict_root;
    myl_native_root_push(&heap,&dict_root,&counts,&pointer);
    for (int i=0;i<40;++i) {
        char spelling[8];
        int width=snprintf(spelling,sizeof spelling,"k%d",i);
        myl_native_text *name=myl_native_text_from_utf8(&heap,(const unsigned char *)spelling,(size_t)width);
        assert(name);
        myl_native_root name_root;
        myl_native_root_push(&heap,&name_root,&name,&pointer);
        int64_t value=i;
        assert(myl_native_dictionary_write(&heap,counts,&name,&value));
        myl_native_root_pop(&heap,&name_root);
    }
    myl_native_text *last=text(&heap,"k39");
    assert(last);
    myl_native_root last_root;
    myl_native_root_push(&heap,&last_root,&last,&pointer);
    int64_t seen=0;
    assert(myl_native_dictionary_read(counts,&key,&seen) && seen==7);
    /* An insertion, then a removal that shifts every later entry down, both
       between the read and the write of one read-modify-write. */
    assert(myl_native_dictionary_write(&heap,counts,&last,&seen));
    char removed[8];
    int removed_width=snprintf(removed,sizeof removed,"k1");
    myl_native_text *dropped=myl_native_text_from_utf8(&heap,(const unsigned char *)removed,(size_t)removed_width);
    assert(dropped);
    myl_native_root dropped_root;
    myl_native_root_push(&heap,&dropped_root,&dropped,&pointer);
    int64_t popped=0;
    assert(myl_native_dictionary_pop(counts,&dropped,&popped) && popped==1);
    myl_native_root_pop(&heap,&dropped_root);
    int64_t bumped=seen+1;
    assert(myl_native_dictionary_write(&heap,counts,&key,&bumped));
    assert(myl_native_dictionary_length(counts)==39);
    assert(myl_native_dictionary_read(counts,&key,&seen) && seen==8);
    /* A different text object with the same content is not the remembered one:
       the full probe finds the same entry and the write lands there. */
    myl_native_text *rebuilt=myl_native_text_from_utf8(&heap,(const unsigned char *)"k7",2);
    assert(rebuilt && rebuilt!=key);
    myl_native_root rebuilt_root;
    myl_native_root_push(&heap,&rebuilt_root,&rebuilt,&pointer);
    assert(myl_native_dictionary_read(counts,&rebuilt,&seen) && seen==8);
    int64_t again=seen+1;
    assert(myl_native_dictionary_write(&heap,counts,&rebuilt,&again));
    assert(myl_native_dictionary_length(counts)==39);
    assert(myl_native_dictionary_read(counts,&key,&seen) && seen==9);
    myl_native_root_pop(&heap,&last_root);
    /* A clear leaves the remembered entry beyond the live range, so the next
       read-modify-write inserts again. */
    myl_native_dictionary_clear(counts);
    int64_t fresh=0;
    assert(!myl_native_dictionary_read(counts,&key,&fresh));
    int64_t first=fresh+5;
    assert(myl_native_dictionary_write(&heap,counts,&key,&first));
    assert(myl_native_dictionary_length(counts)==1);
    assert(myl_native_dictionary_read(counts,&key,&seen) && seen==5);
    myl_native_root_pop(&heap,&rebuilt_root);
    myl_native_root_pop(&heap,&dict_root);
    myl_native_root_pop(&heap,&key_root);
    myl_native_heap_destroy(&heap);
}

/* spec-case: PY-DICT-4 -- a scalar key's recorded absence names the empty slot a
   write would fill, so every change that could fill that slot or move the table
   must drop it: an insertion of another key (which may take that very slot), a
   growth, a pop and a clear, each between the missed read and the write. */
static void absent_records_are_dropped_by_every_change(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<22);
    myl_native_root root;
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&number,0); assert(dict);
    myl_native_root_push(&heap,&root,&dict,&pointer);
    int64_t out=-1,one=1,two=2;
    for (int64_t other=1;other<64;++other) {
        int64_t key=0;
        out=-1;
        myl_native_dictionary_clear(dict);
        assert(!myl_native_dictionary_read(dict,&key,&out) && out==-1);
        assert(!myl_native_dictionary_contains(dict,&key));
        assert(myl_native_dictionary_write(&heap,dict,&other,&two));
        assert(myl_native_dictionary_write(&heap,dict,&key,&one));
        index_sound(dict);
        assert(myl_native_dictionary_length(dict)==2);
        assert(myl_native_dictionary_read(dict,&other,&out) && out==2);
        assert(myl_native_dictionary_read(dict,&key,&out) && out==1);
    }
    /* A miss, then enough insertions to grow the table several times. */
    int64_t late=-5;
    myl_native_dictionary_clear(dict);
    assert(!myl_native_dictionary_contains(dict,&late));
    for (int64_t i=0;i<200;++i) assert(myl_native_dictionary_write(&heap,dict,&i,&i));
    assert(myl_native_dictionary_write(&heap,dict,&late,&one));
    index_sound(dict);
    assert(myl_native_dictionary_length(dict)==201);
    /* A miss, then a pop that shifts entries and slots, then the write. */
    int64_t fresh=1000,victim=3;
    assert(!myl_native_dictionary_read(dict,&fresh,&out));
    assert(myl_native_dictionary_pop(dict,&victim,&out) && out==3);
    assert(myl_native_dictionary_write(&heap,dict,&fresh,&two));
    index_sound(dict);
    for (int64_t i=0;i<200;++i) assert(i==3 || (myl_native_dictionary_read(dict,&i,&out) && out==i));
    assert(myl_native_dictionary_read(dict,&fresh,&out) && out==2);
    /* A miss, then a clear, then the write: one entry. */
    assert(!myl_native_dictionary_contains(dict,&victim));
    myl_native_dictionary_clear(dict);
    assert(myl_native_dictionary_write(&heap,dict,&victim,&one));
    index_sound(dict);
    assert(myl_native_dictionary_length(dict)==1);
    /* setdefault of a missing key inserts once and answers the fallback. */
    int64_t fallback=9;
    assert(myl_native_dictionary_setdefault(&heap,dict,&fresh,&fallback,&out) && out==9);
    assert(myl_native_dictionary_setdefault(&heap,dict,&fresh,&one,&out) && out==9);
    assert(myl_native_dictionary_length(dict)==2);
    /* spec-case: DICT-OVERWRITE-1 -- an overwrite that misses records the
       absence and inserts nothing; the write after it inserts at that slot. */
    int64_t newcomer=77;
    assert(!myl_native_dictionary_overwrite(dict,&newcomer,&two) && myl_native_dictionary_length(dict)==2);
    assert(myl_native_dictionary_write(&heap,dict,&newcomer,&two));
    index_sound(dict);
    assert(myl_native_dictionary_overwrite(dict,&newcomer,&one) && myl_native_dictionary_read(dict,&newcomer,&out) && out==1);
    assert(myl_native_dictionary_length(dict)==3);
    assert(myl_native_root_pop(&heap,&root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: PY-DICT-5 -- popping keys out of the middle of long collision runs
   and across the table's wraparound closes every gap: after each pop the table
   is sound, every remaining key reads back, and every popped key misses. */
static void pops_close_collision_runs(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<22);
    myl_native_root root;
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&number,&number,0); assert(dict);
    myl_native_root_push(&heap,&root,&dict,&pointer);
    enum { COUNT=300 };
    int64_t out=0;
    for (int64_t i=0;i<COUNT;++i) {
        int64_t key=i<<40;
        assert(myl_native_dictionary_write(&heap,dict,&key,&i));
    }
    for (int64_t step=0;step<COUNT;step+=7) {
        int64_t key=step<<40;
        assert(myl_native_dictionary_pop(dict,&key,&out) && out==step);
        index_sound(dict);
    }
    for (int64_t i=0;i<COUNT;++i) {
        int64_t key=i<<40;
        if (i%7) assert(myl_native_dictionary_read(dict,&key,&out) && out==i);
        else assert(!myl_native_dictionary_contains(dict,&key));
    }
    /* Reinserting the popped keys appends them after every survivor. */
    for (int64_t step=0;step<COUNT;step+=7) {
        int64_t key=step<<40;
        assert(myl_native_dictionary_write(&heap,dict,&key,&step));
    }
    index_sound(dict);
    assert(myl_native_dictionary_length(dict)==COUNT);
    int64_t last=0;
    assert(myl_native_dictionary_key_at(dict,COUNT-1,&last) && last==((int64_t)(COUNT-1)/7*7)<<40);
    assert(myl_native_root_pop(&heap,&root));
    myl_native_heap_destroy(&heap);
}

/* spec-case: DICT-RANGE-KEY-1 -- a described slice is the built slice: the same
   octets under the same clamping, the same hash, and a dictionary keyed by it
   stores, finds and orders exactly what writes of the built slices would. The
   heap collects at every allocation, so each inserted key is read back after
   the text it was cut from went through many collections. */
static void span_keys_answer_as_built_slices(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<22); heap.stress=1;
    myl_native_root roots[4];
    myl_native_text *source=text(&heap,"héllo wörld €uro héllo"); assert(source);
    myl_native_root_push(&heap,&roots[0],&source,&pointer);
    myl_native_dictionary *spans=myl_native_dictionary_new(&heap,&pointer,&number,1); assert(spans);
    myl_native_root_push(&heap,&roots[1],&spans,&pointer);
    myl_native_dictionary *built=myl_native_dictionary_new(&heap,&pointer,&number,1); assert(built);
    myl_native_root_push(&heap,&roots[2],&built,&pointer);
    myl_native_text *piece=NULL;
    myl_native_root_push(&heap,&roots[3],&piece,&pointer);
    const int64_t ends[]={INT64_MIN,-30,-6,-1,0,1,2,5,6,11,17,22,23,40,INT64_MAX};
    const size_t count=sizeof ends/sizeof ends[0];
    for (size_t i=0;i<count;++i) for (size_t j=0;j<count;++j) {
        myl_native_text_span span;
        myl_native_text_range(source,ends[i],ends[j],&span);
        piece=myl_native_text_slice(&heap,source,ends[i],ends[j]); assert(piece);
        assert(span.bytes==piece->bytes && span.offset+span.bytes<=source->bytes);
        assert(!memcmp(myl_native_text_storage(source)+span.offset,myl_native_text_storage(piece),span.bytes));
        assert(myl_native_octets_hash(myl_native_text_storage(source)+span.offset,span.bytes)==myl_native_text_hash(piece));
        int64_t seen=0, again=0;
        int present=myl_native_dictionary_read(built,&piece,&seen);
        assert(present==myl_native_dictionary_contains_range(&heap,spans,source,&span));
        assert(present==myl_native_dictionary_read_range(&heap,spans,source,&span,&again) && seen==again);
        seen++;
        assert(myl_native_dictionary_write(&heap,built,&piece,&seen));
        assert(myl_native_dictionary_write_range(&heap,spans,source,&span,&seen));
        index_sound(spans);
    }
    assert(myl_native_dictionary_length(spans)==myl_native_dictionary_length(built));
    myl_native_heap_collect(&heap);
    for (size_t at=0;at<myl_native_dictionary_length(spans);++at) {
        myl_native_text *mine, *theirs;
        int64_t left, right;
        assert(myl_native_dictionary_key_at(spans,at,&mine) && myl_native_dictionary_key_at(built,at,&theirs));
        assert(myl_native_text_equal(mine,theirs) && mine->length==theirs->length);
        assert(!(mine->flags&MYL_TEXT_VIEW) && (mine->flags&MYL_TEXT_ASCII)==(theirs->flags&MYL_TEXT_ASCII));
        assert(!(mine->flags&MYL_TEXT_HASHED) || mine->hash==myl_native_text_hash(theirs));
        assert(myl_native_dictionary_value_at(spans,at,&left) && myl_native_dictionary_value_at(built,at,&right) && left==right);
    }
    for (int i=3;i>=0;--i) assert(myl_native_root_pop(&heap,&roots[i]));
    myl_native_heap_destroy(&heap);
}
/* spec-case: DICT-RANGE-KEY-2 -- a slice's recorded absence answers only the
   same span of the same text while no collection has run, never a lookup of the
   whole text it was cut from, and never after an insertion. */
static void span_absences_are_dated_and_kept_apart(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<22);
    myl_native_root roots[3];
    myl_native_text *source=text(&heap,"abcabc"); assert(source);
    myl_native_root_push(&heap,&roots[0],&source,&pointer);
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&pointer,&number,1); assert(dict);
    myl_native_root_push(&heap,&roots[1],&dict,&pointer);
    myl_native_text *other=text(&heap,"ab"); assert(other);
    myl_native_root_push(&heap,&roots[2],&other,&pointer);
    int64_t one=1,two=2,out=-1;
    assert(myl_native_dictionary_write(&heap,dict,&source,&one));
    myl_native_text_span front={.offset=0,.bytes=2};
    /* A miss records the span's absence; the whole text is still found. */
    assert(!myl_native_dictionary_read_range(&heap,dict,source,&front,&out) && out==-1);
    assert(dict->last.state==4 && dict->last.key==(uint64_t)(uintptr_t)source && dict->last.offset==0 && dict->last.epoch==heap.collections);
    assert(myl_native_dictionary_contains(dict,&source));
    assert(myl_native_dictionary_read(dict,&source,&out) && out==1);
    /* A miss, then an insertion of the same octets by another text, then the
       span's write: the insertion dropped the record, so the write finds it. */
    assert(!myl_native_dictionary_contains_range(&heap,dict,source,&front));
    assert(myl_native_dictionary_write(&heap,dict,&other,&one));
    assert(myl_native_dictionary_write_range(&heap,dict,source,&front,&two));
    assert(myl_native_dictionary_length(dict)==2 && myl_native_dictionary_read(dict,&other,&out) && out==2);
    /* A miss, a collection, then the write: the record is no longer believed. */
    myl_native_text_span back={.offset=1,.bytes=2};
    assert(!myl_native_dictionary_read_range(&heap,dict,source,&back,&out));
    size_t epoch=dict->last.epoch;
    myl_native_heap_collect(&heap);
    assert(heap.collections!=epoch);
    assert(!myl_native_dictionary_contains_range(&heap,dict,source,&back));
    assert(dict->last.epoch==heap.collections);
    assert(myl_native_dictionary_write_range(&heap,dict,source,&back,&two));
    index_sound(dict);
    assert(myl_native_dictionary_length(dict)==3 && myl_native_dictionary_read_range(&heap,dict,source,&back,&out) && out==2);
    /* A found record answers a different span only when its octets match. */
    myl_native_text_span later={.offset=3,.bytes=2}, shifted={.offset=4,.bytes=2};
    assert(myl_native_dictionary_read_range(&heap,dict,source,&later,&out) && out==2);
    assert(myl_native_dictionary_read_range(&heap,dict,source,&shifted,&out) && out==2);
    assert(!myl_native_dictionary_contains_range(&heap,dict,source,&(myl_native_text_span){.offset=2,.bytes=2}));
    /* The allocation-free halves of the writes replace present values only. */
    int64_t nine=9;
    myl_native_text_span middle={.offset=2,.bytes=2};
    assert(!myl_native_dictionary_overwrite_range(&heap,dict,source,&middle,&nine));
    assert(myl_native_dictionary_length(dict)==3);
    assert(myl_native_dictionary_overwrite_range(&heap,dict,source,&later,&nine));
    assert(myl_native_dictionary_read(dict,&other,&out) && out==9);
    int64_t ten=10;
    assert(myl_native_dictionary_overwrite(dict,&source,&ten) && myl_native_dictionary_read(dict,&source,&out) && out==10);
    myl_native_text *fresh=text(&heap,"zz"); assert(fresh);
    assert(!myl_native_dictionary_overwrite(dict,&fresh,&ten) && myl_native_dictionary_length(dict)==3);
    for (int i=2;i>=0;--i) assert(myl_native_root_pop(&heap,&roots[i]));
    myl_native_heap_destroy(&heap);
}
int main(void) {
    span_keys_answer_as_built_slices();
    span_absences_are_dated_and_kept_apart();
    repeated_probes_survive_a_shift();
    absent_records_are_dropped_by_every_change();
    pops_close_collision_runs();
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<20); heap.stress=1;
    myl_native_root roots[8];
    myl_native_text *input=text(&heap,"é🙂|x|"); assert(input && input->length==5);
    myl_native_root_push(&heap,&roots[0],&input,&pointer);
    myl_native_text *separator=text(&heap,"|"); assert(separator);
    myl_native_root_push(&heap,&roots[1],&separator,&pointer);
    myl_native_list *parts=myl_native_text_split(&heap,input,separator); assert(parts && parts->length==3);
    myl_native_root_push(&heap,&roots[2],&parts,&pointer);
    myl_native_text *joined=myl_native_text_join(&heap,separator,parts); assert(joined);
    myl_native_root_push(&heap,&roots[3],&joined,&pointer);
    assert(myl_native_text_equal(input,joined));
    equals(myl_native_text_at(&heap,input,-4),"🙂");
    equals(myl_native_text_slice(&heap,input,-99,2),"é🙂");
    assert(!myl_native_text_at(&heap,input,INT64_MIN));
    assert(!myl_native_text_from_utf8(&heap,(const unsigned char *)"\xc0\x80",2));
    assert(!myl_native_text_from_utf8(&heap,(const unsigned char *)"\xed\xa0\x80",3));
    myl_native_dictionary *dict=myl_native_dictionary_new(&heap,&pointer,&number,1); assert(dict);
    myl_native_root_push(&heap,&roots[4],&dict,&pointer);
    int64_t one=1,two=2,three=3,out;
    assert(myl_native_dictionary_write(&heap,dict,&input,&one));
    assert(myl_native_dictionary_write(&heap,dict,&separator,&two));
    assert(myl_native_dictionary_write(&heap,dict,&joined,&three));
    assert(myl_native_dictionary_length(dict)==2);
    assert(myl_native_dictionary_read(dict,&input,&out) && out==3);
    myl_native_text *first;
    assert(myl_native_dictionary_key_at(dict,0,&first) && first==input);
    out=-1;
    assert(myl_native_dictionary_value_at(dict,0,&out) && out==3);
    out=-1;
    assert(!myl_native_dictionary_value_at(dict,2,&out) && out==-1);
    myl_native_list *snapshot=myl_native_dictionary_snapshot(&heap,dict,0); assert(snapshot);
    myl_native_root_push(&heap,&roots[5],&snapshot,&pointer);
    assert(myl_native_dictionary_write(&heap,dict,&input,&one));
    assert(myl_native_list_get(snapshot,0,&out) && out==3);
    myl_native_heap_collect(&heap);
    equals(first,"é🙂|x|");
    for (int i=5;i>=0;--i) assert(myl_native_root_pop(&heap,&roots[i]));
    myl_native_heap_collect(&heap); assert(heap.objects_live==0);
    myl_native_heap_destroy(&heap);
    /* Snapshot descriptors reference canonical key/value types, not the dead
       dictionary's embedded entry descriptor. */
    myl_native_heap_init(&heap,1<<20); heap.stress=1;
    dict=myl_native_dictionary_new(&heap,&number,&number,0); assert(dict);
    myl_native_root_push(&heap,&roots[0],&dict,&pointer);
    assert(myl_native_dictionary_write(&heap,dict,&one,&three));
    snapshot=myl_native_dictionary_snapshot(&heap,dict,0); assert(snapshot);
    myl_native_root_pop(&heap,&roots[0]);
    myl_native_root_push(&heap,&roots[0],&snapshot,&pointer);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==2);
    assert(myl_native_list_get(snapshot,0,&out) && out==3);
    myl_native_heap_collect(&heap);
    assert(myl_native_list_get(snapshot,0,&out) && out==3);
    myl_native_heap_destroy(&heap);
    myl_native_heap_init(&heap,1<<20); heap.stress=1;
    dict=myl_native_dictionary_new(&heap,&pointer,&number,1); assert(dict);
    myl_native_root_push(&heap,&roots[0],&dict,&pointer);
    input=text(&heap,"retained key"); assert(input);
    assert(myl_native_dictionary_write(&heap,dict,&input,&three));
    snapshot=myl_native_dictionary_snapshot(&heap,dict,1); assert(snapshot);
    myl_native_root_pop(&heap,&roots[0]);
    myl_native_root_push(&heap,&roots[0],&snapshot,&pointer);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==3);
    assert(myl_native_list_get(snapshot,0,&first)); equals(first,"retained key");
    myl_native_heap_collect(&heap);
    assert(myl_native_list_get(snapshot,0,&first)); equals(first,"retained key");
    myl_native_heap_destroy(&heap);
    index_cases();
    index_limits();
    puts("native text and dictionary tests passed");
}
