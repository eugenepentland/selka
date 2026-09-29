#include "native_text_methods.h"
#include "native_regions.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* spec-case: TEXT-VIEW-1, TEXT-VIEW-2, TEXT-VIEW-3. Text views over the real
   runtime, under collection stress: which pieces share their receiver's octets,
   that a view reads exactly the octets a copy would, that the collector keeps a
   view's owner alive through the view alone, that a view's hash equals an owned
   text's and is never cached in its offset word, that a dictionary stores a
   view key as an owned copy, and that an arena view escapes
   as an owned copy. */
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
/* A `str` slot as generated descriptors describe it to the escape copier. */
static const myl_native_type text_slot={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=2};
void myl_qbe_fail(void *context,const char *code) {
    (void)context; (void)code;
    assert(0 && "unexpected text trap");
}
static myl_native_text *raw(myl_native_heap *heap,const char *text) {
    myl_native_text *value=myl_native_text_from_utf8(heap,(const unsigned char *)text,strlen(text));
    assert(value);
    return value;
}
static int reads(const myl_native_text *value,const char *text,size_t count) {
    return value && value->bytes==count && !memcmp(myl_native_text_storage(value),text,count);
}
static int is_view(const myl_native_text *value) { return (value->flags&MYL_TEXT_VIEW)!=0; }
/* A 100-octet ASCII receiver: which pieces are views, and that each reads the
   same octets, scalar count and ASCII flag a copy carries. */
static void policy(myl_native_heap *heap) {
    char octets[101];
    for (int i=0;i<100;i++) octets[i]=(char)('a'+i%26);
    octets[100]=0;
    myl_native_text *owner=raw(heap,octets);
    myl_native_root root;
    myl_native_root_push(heap,&root,&owner,&pointer);
    myl_native_text *whole=myl_native_text_substring(heap,owner,0,100);
    assert(whole==owner);
    myl_native_text *quarter=myl_native_text_substring(heap,owner,10,35);
    assert(is_view(quarter) && reads(quarter,octets+10,25) && quarter->length==25 && (quarter->flags&MYL_TEXT_ASCII));
    assert(((const myl_native_text_view *)quarter)->owner==owner && myl_native_text_storage(quarter)==myl_native_text_storage(owner)+10);
    assert(!is_view(myl_native_text_substring(heap,owner,10,34)));
    assert(!is_view(myl_native_text_substring(heap,owner,0,8)));
    assert(reads(myl_native_text_substring(heap,owner,3,11),octets+3,8));
    myl_native_text *empty=myl_native_text_substring(heap,owner,50,50);
    assert(!is_view(empty) && reads(empty,"",0));
    /* A view of a view records the first view's owner and the summed offset. */
    myl_native_text *outer=myl_native_text_substring(heap,owner,5,95);
    myl_native_root second;
    myl_native_root_push(heap,&second,&outer,&pointer);
    myl_native_text *inner=myl_native_text_slice(heap,outer,7,60);
    assert(is_view(outer) && is_view(inner) && ((const myl_native_text_view *)inner)->owner==owner);
    assert(reads(inner,octets+12,53) && inner->hash==12);
    /* Its whole range answers the view itself. */
    assert(myl_native_text_substring(heap,outer,0,90)==outer);
    myl_native_root_pop(heap,&second);
    myl_native_root_pop(heap,&root);
}
/* Only the view is rooted: collection keeps its owner, and a flood of fresh
   texts of the owner's size class never reuses the owner's slot. */
static void owner_survives(myl_native_heap *heap) {
    char octets[201];
    for (int i=0;i<200;i++) octets[i]=(char)('A'+i%23);
    octets[200]=0;
    myl_native_text *piece=myl_native_text_substring(heap,raw(heap,octets),20,180);
    assert(is_view(piece));
    myl_native_root root;
    myl_native_root_push(heap,&root,&piece,&pointer);
    size_t collections=heap->collections;
    unsigned char flood[200];
    memset(flood,'Z',sizeof flood);
    for (int i=0;i<200;i++) assert(myl_native_text_from_utf8(heap,flood,sizeof flood));
    assert(heap->collections>collections);
    assert(reads(piece,octets+20,160));
    myl_native_root_pop(heap,&root);
}
/* Non-ASCII: a view counts its own scalars and indexes them by scalar. */
static void scalars(myl_native_heap *heap) {
    const char *octets="a\xc3\xa9\xf0\x9f\x99\x82z\xe2\x80\x94" "a\xc3\xa9\xf0\x9f\x99\x82z\xe2\x80\x94";
    myl_native_text *owner=raw(heap,octets);
    myl_native_root root;
    myl_native_root_push(heap,&root,&owner,&pointer);
    myl_native_text *piece=myl_native_text_slice(heap,owner,2,9);
    assert(is_view(piece) && piece->length==7 && !(piece->flags&MYL_TEXT_ASCII));
    assert(reads(piece,octets+3,16) && myl_native_text_point_at(piece,0)==0x1F642 && myl_native_text_point_at(piece,5)==0x1F642 && myl_native_text_point_at(piece,6)==(uint32_t)'z');
    myl_native_root_pop(heap,&root);
}
/* Hashing a view answers an owned text's hash and never writes the view's
   offset word; a dictionary keyed by views finds owned keys and back. */
static void hashing(myl_native_heap *heap) {
    const char *octets="0123456789abcdefghijklmnopqrstuv";
    myl_native_text *owner=raw(heap,octets);
    myl_native_root root;
    myl_native_root_push(heap,&root,&owner,&pointer);
    myl_native_text *piece=myl_native_text_substring(heap,owner,4,20);
    myl_native_root second;
    myl_native_root_push(heap,&second,&piece,&pointer);
    myl_native_text *copy=raw(heap,"456789abcdefghij");
    assert(is_view(piece) && myl_native_text_equal(piece,copy) && !myl_native_text_compare(piece,copy));
    assert(myl_native_text_hash(piece)==myl_native_text_hash(copy));
    assert(piece->hash==4 && !(piece->flags&MYL_TEXT_HASHED) && (copy->flags&MYL_TEXT_HASHED));
    assert(myl_native_text_hash(piece)==myl_native_text_hash(copy) && piece->hash==4);
    myl_native_root_pop(heap,&second);
    myl_native_root_pop(heap,&root);
}
/* A dictionary stores a view key as an owned copy of its octets in the
   dictionary's own region, and answers lookups by views and by owned text. */
static void dictionary_keys(myl_native_heap *heap) {
    static const myl_native_type text_key={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
    static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
    myl_native_text *owner=raw(heap,"GATTACA-CATTAGA-GATTACA-CATTAGA-");
    myl_native_root root;
    myl_native_root_push(heap,&root,&owner,&pointer);
    myl_native_dictionary *counts=myl_native_dictionary_new(heap,&text_key,&number,1);
    myl_native_root second;
    myl_native_root_push(heap,&second,&counts,&pointer);
    assert(myl_native_region_begin(heap));
    myl_native_text *key=myl_native_text_substring(heap,owner,0,15);
    myl_native_root third;
    myl_native_root_push(heap,&third,&key,&pointer);
    int64_t value=1, read=0;
    assert(is_view(key) && myl_native_header_region(key)==1);
    assert(myl_native_dictionary_write(heap,counts,&key,&value));
    myl_native_text *stored=NULL;
    assert(myl_native_dictionary_key_at(counts,0,&stored));
    assert(stored!=key && !is_view(stored) && myl_native_header_region(stored)==0 && reads(stored,"GATTACA-CATTAGA",15));
    myl_native_text *other=myl_native_text_substring(heap,owner,16,31);
    assert(is_view(other) && myl_native_dictionary_read(counts,&other,&read) && read==1);
    value=2;
    assert(myl_native_dictionary_write(heap,counts,&other,&value) && myl_native_dictionary_length(counts)==1);
    myl_native_root_pop(heap,&third);
    myl_native_region_end(heap);
    myl_native_heap_collect(heap);
    myl_native_text *copy=raw(heap,"GATTACA-CATTAGA");
    assert(myl_native_dictionary_read(counts,&copy,&read) && read==2);
    myl_native_root_pop(heap,&second);
    myl_native_root_pop(heap,&root);
}
/* Arenas: a view allocated inside an arena lives at the arena's depth whether
   its owner is outer or arena text, keeps an outer owner alive through the
   arena scan, and escapes as an owned copy of its own octets. */
static void arenas(myl_native_heap *heap) {
    const char *octets="outer text that an arena slices into pieces";
    size_t count=strlen(octets);
    myl_native_text *owner=raw(heap,octets);
    myl_native_root root;
    myl_native_root_push(heap,&root,&owner,&pointer);
    /* An outer text nothing but an arena view refers to survives collection:
       the arena scan traces the view's owner field. */
    myl_native_text *unrooted=raw(heap,"an outer text only an arena view refers to");
    assert(myl_native_region_begin(heap));
    myl_native_text *lonely=myl_native_text_substring(heap,unrooted,3,40);
    assert(is_view(lonely) && myl_native_header_region(lonely)==1);
    size_t live=heap->objects_live;
    myl_native_heap_collect(heap);
    /* Nothing on the tracing heap is garbage here, so a collection that kept
       `unrooted` alive through the arena view's owner frees nothing. */
    assert(heap->objects_live==live);
    assert(reads(lonely,"outer text only an arena view refers ",37));
    myl_native_text *piece=myl_native_text_substring(heap,owner,6,count);
    assert(is_view(piece) && myl_native_header_region(piece)==1 && myl_native_header_region(owner)==0);
    /* The whole outer text is not reused inside the arena: its piece belongs
       to the arena, exactly as a copy did. */
    myl_native_text *whole=myl_native_text_substring(heap,owner,0,count);
    assert(whole!=owner && myl_native_header_region(whole)==1 && reads(whole,octets,count));
    myl_native_text *local=myl_native_text_concat(heap,piece,piece);
    myl_native_text *inner=myl_native_text_substring(heap,local,3,40);
    assert(is_view(inner) && ((const myl_native_text_view *)inner)->owner==local);
    myl_native_heap_collect(heap);
    assert(reads(piece,octets+6,count-6));
    myl_native_text *escaped=NULL;
    assert(myl_native_region_escape(heap,&text_slot,&inner,&escaped));
    assert(escaped && !is_view(escaped) && myl_native_header_region(escaped)==0);
    assert(reads(escaped,"t that an arena slices into piecestex",37) && escaped->length==37);
    myl_native_root kept;
    myl_native_root_push(heap,&kept,&escaped,&pointer);
    myl_native_region_end(heap);
    myl_native_heap_collect(heap);
    assert(reads(escaped,"t that an arena slices into piecestex",37));
    myl_native_root_pop(heap,&kept);
    myl_native_root_pop(heap,&root);
}
/* Split pieces follow the same policy: a long field is a view, a short one is
   a copy, and both read their own octets after the receiver is gone. */
static void split_pieces(myl_native_heap *heap) {
    const char *octets="a much longer first field,short,x";
    myl_native_text *input=raw(heap,octets);
    myl_native_root receiver;
    myl_native_root_push(heap,&receiver,&input,&pointer);
    myl_native_list *parts=myl_native_text_split(heap,input,raw(heap,","));
    assert(parts && parts->length==3);
    myl_native_root root;
    myl_native_root_push(heap,&root,&parts,&pointer);
    input=NULL;
    myl_native_heap_collect(heap);
    myl_native_text **items=parts->storage;
    assert(is_view(items[0]) && !is_view(items[1]) && !is_view(items[2]));
    assert(reads(items[0],octets,25) && reads(items[1],"short",5) && reads(items[2],"x",1));
    myl_native_root_pop(heap,&root);
    myl_native_root_pop(heap,&receiver);
}
/* spec: TEXT-VIEW-5. Tails below a quarter share one owner down to nine
 * octets; bounded slices and split's final field retain the quarter policy. */
static void streaming_tails(myl_native_heap *heap) {
    char octets[101]; memset(octets,'a',100); octets[90]=','; octets[100]=0;
    myl_native_text *owner=raw(heap,octets);
    myl_native_root root, kept;
    myl_native_root_push(heap,&root,&owner,&pointer);
    myl_native_text *rest=myl_native_text_tail(heap,owner,80,100);
    myl_native_root_push(heap,&kept,&rest,&pointer);
    assert(is_view(rest) && ((myl_native_text_view *)rest)->owner==owner);
    for (int i=81;i<=91;i++) {
        rest=myl_native_text_tail(heap,rest,1,(int64_t)rest->length);
        assert(is_view(rest) && ((myl_native_text_view *)rest)->owner==owner);
        assert(rest->hash==(uint32_t)i && reads(rest,octets+i,100-(size_t)i));
    }
    assert(!is_view(myl_native_text_tail(heap,owner,92,100)));
    assert(!is_view(myl_native_text_slice(heap,owner,91,100)));
    assert(!is_view(myl_native_text_tail(heap,owner,91,99)));
    assert(reads(myl_native_text_tail(heap,owner,200,100),"",0));
    assert(myl_native_text_tail(heap,owner,-200,100)==owner);
    myl_native_list *parts=myl_native_text_split(heap,owner,raw(heap,","));
    assert(parts && parts->length==2 && !is_view(((myl_native_text **)parts->storage)[1]));
    myl_native_root_pop(heap,&kept);
    myl_native_root_pop(heap,&root);
}
/* spec-case: TEXT-VIEW-5. Scalar endpoints include astral UTF-8 widths, and
 * escaping an arena tail copies only the tail and survives the arena. */
static void tail_arenas(myl_native_heap *heap) {
    myl_native_text *escaped=NULL;
    assert(myl_native_region_begin(heap));
    myl_native_text *owner=raw(heap,"abcdefghijklmnopqrstuvwxyz\xf0\x9f\x99\x82\xc3\xa9" "abcdefghi");
    myl_native_text *tail=myl_native_text_tail(heap,owner,26,owner->length);
    assert(is_view(tail) && tail->length==11 && tail->bytes==15 && tail->hash==26);
    tail=myl_native_text_tail(heap,tail,1,tail->length);
    assert(is_view(tail) && tail->hash==30 && ((myl_native_text_view *)tail)->owner==owner);
    assert(myl_native_text_point_at(tail,0)==0xe9 && myl_native_text_point_at(tail,9)=='i');
    assert(myl_native_region_escape(heap,&text_slot,&tail,&escaped));
    assert(escaped && !is_view(escaped) && myl_native_header_region(escaped)==0);
    myl_native_root kept;
    myl_native_root_push(heap,&kept,&escaped,&pointer);
    myl_native_region_end(heap);
    myl_native_heap_collect(heap);
    assert(reads(escaped,"\xc3\xa9" "abcdefghi",11));
    myl_native_root_pop(heap,&kept);
}
/* spec-case: TEXT-VIEW-5. Scanning the original owner's final quarter copies
 * only the final eight short tails, independently of the owner's length. */
static void tail_copy_bound(myl_native_heap *heap, size_t count) {
    unsigned char *octets=malloc(count); assert(octets); memset(octets,'x',count);
    myl_native_text *owner=myl_native_text_from_utf8(heap,octets,count); assert(owner);
    myl_native_root root;
    myl_native_root_push(heap,&root,&owner,&pointer);
    size_t copied=0, views=0;
    for (size_t start=3*count/4;start<=count;start++) {
        myl_native_text *tail=myl_native_text_tail(heap,owner,(int64_t)start,(int64_t)count);
        assert(tail && tail->length==count-start);
        if (is_view(tail)) { views++; assert(((myl_native_text_view *)tail)->owner==owner); }
        else copied+=tail->bytes;
    }
    assert(copied==36 && views==count/4-8);
    printf("streaming tails: owner=%zu views=%zu copied=%zu\n",count,views,copied);
    myl_native_root_pop(heap,&root);
    free(octets);
}
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<22); heap.stress=1;
    policy(&heap);
    owner_survives(&heap);
    scalars(&heap);
    hashing(&heap);
    dictionary_keys(&heap);
    arenas(&heap);
    split_pieces(&heap);
    streaming_tails(&heap);
    tail_arenas(&heap);
    heap.stress=0;
    tail_copy_bound(&heap,4096);
    tail_copy_bound(&heap,32768);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live==0);
    myl_native_heap_destroy(&heap);
    puts("native text view tests passed");
    return 0;
}
