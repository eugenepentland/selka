#define _GNU_SOURCE
#include "native_text_methods.h"
#include "native_regions.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
/* spec-case: TEXT-INDEX-1, TEXT-INDEX-2, TEXT-INDEX-3. The position index of a
   long non-ASCII text over the real runtime, under collection stress. Every
   lookup is checked against the scalar array the text was built from, in every
   access order a program can take (in order, reversed, strided, random, from
   both ends at once), for owned texts, views of them and pieces cut from
   them; and the work the runtime reports (`myl_native_text_steps`, octets
   examined, compiled in by this suite alone) is checked against a linear
   bound, so a lookup that walks from the start of the payload again fails here
   without a clock. */
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
void myl_qbe_fail(void *context,const char *code) {
    (void)context; (void)code;
    assert(0 && "unexpected text trap");
}
/* A `str` slot as generated descriptors describe it to the escape copier. */
static const myl_native_type text_slot={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=2};
static uint64_t seed=0x9e3779b97f4a7c15ULL;
static uint32_t next_random(void) {
    seed=seed*6364136223846793005ULL+1442695040888963407ULL;
    return (uint32_t)(seed>>33);
}
/* Scalars of every width, weighted toward ASCII the way real text is. */
static uint32_t scalar_of(unsigned kind) {
    switch (kind) {
    case 0: return 0xe9;
    case 1: return 0x4e2d;
    case 2: return 0x1f600;
    case 3: return 0x7ff;
    case 4: return 0x10ffff;
    default: return 0x20+next_random()%0x5f;
    }
}
/* `count` scalars: one non-ASCII scalar in every `period`, and none when `period` is 0. */
static uint32_t *points_of(size_t count, unsigned period) {
    uint32_t *points=malloc((count?count:1)*sizeof *points);
    assert(points);
    for (size_t i=0;i<count;i++) points[i]=period && next_random()%period==0 ? scalar_of(next_random()%5) : scalar_of(5);
    return points;
}
static myl_native_text *build(myl_native_heap *heap, const uint32_t *points, size_t count) {
    myl_native_text *text=myl_native_text_from_scalars(heap,points,count);
    assert(text && text->length==count);
    return text;
}
static size_t width_of(uint32_t point) { return point<0x80 ? 1 : point<0x800 ? 2 : point<0x10000 ? 3 : 4; }
/* The offset of every scalar and the payload size, by summing widths. */
static size_t *offsets_of(const uint32_t *points, size_t count) {
    size_t *offsets=malloc((count+1)*sizeof *offsets);
    assert(offsets);
    size_t at=0;
    for (size_t i=0;i<count;i++) { offsets[i]=at; at+=width_of(points[i]); }
    offsets[count]=at;
    return offsets;
}
static void check_at(const myl_native_text *text, const uint32_t *points, const size_t *offsets, size_t index) {
    assert(myl_native_text_offset(text,index)==offsets[index]);
    assert(myl_native_text_point_at(text,index)==points[index]);
}
/* Every access order over one text, each answer checked. */
static void orders(const myl_native_text *text, const uint32_t *points, size_t count) {
    size_t *offsets=offsets_of(points,count);
    assert(text->bytes==offsets[count]);
    for (size_t i=0;i<count;i++) check_at(text,points,offsets,i);
    for (size_t i=count;i--;) check_at(text,points,offsets,i);
    for (size_t stride=2;stride<=1500;stride=stride*3+1)
        for (size_t i=0;i<count;i+=stride) check_at(text,points,offsets,i);
    for (size_t i=0;i<count;i++) check_at(text,points,offsets,next_random()%count);
    for (size_t low=0,high=count-1;low<high;low++,high--) { check_at(text,points,offsets,low); check_at(text,points,offsets,high); }
    /* The end, and past it. */
    assert(myl_native_text_offset(text,count)==offsets[count]);
    if (!(text->flags&MYL_TEXT_ASCII)) assert(myl_native_text_offset(text,count+5)==offsets[count]);
    /* Scalar index of every scalar boundary, and of the payload end. */
    for (size_t i=0;i<count;i+=1+next_random()%40) assert(myl_native_text_index(text,offsets[i])==i);
    for (size_t i=count;i>0;) {
        i--;
        assert(myl_native_text_index(text,offsets[i])==i);
        i-=i>40 ? next_random()%40 : 0;
    }
    assert(myl_native_text_index(text,offsets[count])==count);
    free(offsets);
}
/* Shapes on both sides of every threshold: below and above the smallest
   indexed payload, and around the sample stride. */
static void shapes(myl_native_heap *heap) {
    const size_t counts[]={1,2,63,64,65,127,128,129,130,200,255,256,257,300,600,1023,1024,1025,1100,2048,2049,4000,9000,40000};
    const unsigned periods[]={0,1,3,50,1000};
    for (size_t c=0;c<sizeof counts/sizeof *counts;c++)
        for (size_t p=0;p<sizeof periods/sizeof *periods;p++) {
            uint32_t *points=points_of(counts[c],periods[p]);
            myl_native_text *text=build(heap,points,counts[c]);
            myl_native_root root;
            myl_native_root_push(heap,&root,&text,&pointer);
            orders(text,points,counts[c]);
            myl_native_root_pop(heap,&root);
            free(points);
        }
}
/* A non-ASCII text carries the index exactly when it is at least 256 octets,
   and an ASCII text never does. */
static void which_carry_an_index(myl_native_heap *heap) {
    uint32_t *points=points_of(300,0);
    myl_native_text *ascii=build(heap,points,300);
    assert((ascii->flags&MYL_TEXT_ASCII) && !(ascii->flags&MYL_TEXT_INDEXED));
    /* 253 ASCII scalars and one two-octet scalar are 255 octets; one more is 256. */
    points[253]=0xe9;
    myl_native_text *shorter=build(heap,points,254);
    assert(shorter->bytes==255 && !(shorter->flags&MYL_TEXT_ASCII) && !(shorter->flags&MYL_TEXT_INDEXED));
    orders(shorter,points,254);
    points[254]=0x20;
    myl_native_text *exact=build(heap,points,255);
    assert(exact->bytes==256 && !(exact->flags&MYL_TEXT_ASCII) && (exact->flags&MYL_TEXT_INDEXED) && !(exact->flags&MYL_TEXT_SAMPLED));
    orders(exact,points,255);
    free(points);
    /* A short non-ASCII text is never indexed. */
    points=points_of(120,0);
    points[60]=0x4e2d;
    shorter=build(heap,points,120);
    assert(!(shorter->flags&MYL_TEXT_ASCII) && !(shorter->flags&MYL_TEXT_INDEXED));
    orders(shorter,points,120);
    free(points);
}
/* `myl_native_text_at` answers one-scalar texts, from the front and the back. */
static void single_scalars(myl_native_heap *heap) {
    const size_t count=5000;
    uint32_t *points=points_of(count,7);
    myl_native_text *text=build(heap,points,count);
    myl_native_root root, second;
    myl_native_root_push(heap,&root,&text,&pointer);
    for (size_t round=0;round<400;round++) {
        size_t i=next_random()%count;
        myl_native_text *one=myl_native_text_at(heap,text,(int64_t)i);
        assert(one && one->length==1);
        myl_native_root_push(heap,&second,&one,&pointer);
        assert(myl_native_text_point_at(one,0)==points[i]);
        myl_native_text *back=myl_native_text_at(heap,text,-(int64_t)(count-i));
        assert(back && myl_native_text_point_at(back,0)==points[i]);
        myl_native_root_pop(heap,&second);
    }
    assert(!myl_native_text_at(heap,text,(int64_t)count));
    assert(!myl_native_text_at(heap,text,-(int64_t)count-1));
    myl_native_root_pop(heap,&root);
    free(points);
}
/* Pieces of an indexed text: slices, views of views and the constructors that
   build a fresh text all read exactly the scalars a copy would. */
static void pieces(myl_native_heap *heap) {
    const size_t count=6000;
    uint32_t *points=points_of(count,20);
    myl_native_text *text=build(heap,points,count);
    myl_native_root root, second;
    myl_native_root_push(heap,&root,&text,&pointer);
    size_t *offsets=offsets_of(points,count);
    for (int round=0;round<300;round++) {
        size_t start=next_random()%count, length=next_random()%(count-start+1);
        myl_native_text *piece=myl_native_text_slice(heap,text,(int64_t)start,(int64_t)(start+length));
        assert(piece && piece->length==length);
        myl_native_root_push(heap,&second,&piece,&pointer);
        assert(piece->bytes==offsets[start+length]-offsets[start]);
        assert(!memcmp(myl_native_text_storage(piece),myl_native_text_storage(text)+offsets[start],piece->bytes));
        if (length) orders(piece,points+start,length);
        /* A piece of a piece reads through the first. */
        if (length>10) {
            size_t inner=next_random()%(length/2), span=next_random()%(length-inner+1);
            myl_native_text *nested=myl_native_text_slice(heap,piece,(int64_t)inner,(int64_t)(inner+span));
            assert(nested && nested->length==span);
            assert(nested->bytes==offsets[start+inner+span]-offsets[start+inner]);
            assert(!memcmp(myl_native_text_storage(nested),myl_native_text_storage(text)+offsets[start+inner],nested->bytes));
        }
        myl_native_root_pop(heap,&second);
    }
    /* Negative endpoints through the slice entry point. */
    myl_native_text *tail=myl_native_text_slice(heap,text,-100,(int64_t)count);
    assert(tail->length==100 && tail->bytes==offsets[count]-offsets[count-100]);
    myl_native_text *head=myl_native_text_slice(heap,text,0,-(int64_t)(count-100));
    assert(head->length==100 && head->bytes==offsets[100]);
    /* Concatenation, joining, case mapping and replacement keep the index sound. */
    myl_native_text *both=myl_native_text_concat(heap,text,text);
    myl_native_root_push(heap,&second,&both,&pointer);
    uint32_t *twice=malloc(2*count*sizeof *twice);
    memcpy(twice,points,count*sizeof *twice);
    memcpy(twice+count,points,count*sizeof *twice);
    orders(both,twice,2*count);
    free(twice);
    myl_native_root_pop(heap,&second);
    myl_native_text *upper=myl_native_text_case(heap,text,1);
    myl_native_root_push(heap,&second,&upper,&pointer);
    assert(upper->length==count && upper->bytes==text->bytes);
    for (size_t i=0;i<count;i+=7) {
        uint32_t point=points[i];
        assert(myl_native_text_point_at(upper,i)==(point>='a'&&point<='z' ? point-32 : point));
    }
    myl_native_root_pop(heap,&second);
    free(offsets);
    free(points);
    myl_native_root_pop(heap,&root);
}
/* A text and a view of it made inside an arena, and the owned copy of that view
   `escape` makes, carry their own index: the copy reads every scalar after the
   arena is gone and its source is collected. */
static void arenas(myl_native_heap *heap) {
    const size_t count=3000;
    uint32_t *points=points_of(count,12);
    myl_native_root root;
    myl_native_text *escaped=NULL;
    assert(myl_native_region_begin(heap));
    myl_native_text *text=build(heap,points,count);
    assert(text->flags&MYL_TEXT_INDEXED);
    myl_native_text *view=myl_native_text_slice(heap,text,200,2900);
    assert(view && (view->flags&MYL_TEXT_VIEW));
    orders(view,points+200,2700);
    orders(text,points,count);
    assert(myl_native_region_escape(heap,&text_slot,&view,&escaped));
    assert(escaped && !(escaped->flags&MYL_TEXT_VIEW) && (escaped->flags&MYL_TEXT_INDEXED) && escaped->length==2700);
    myl_native_root_push(heap,&root,&escaped,&pointer);
    myl_native_region_end(heap);
    myl_native_heap_collect(heap);
    orders(escaped,points+200,2700);
    myl_native_root_pop(heap,&root);
    free(points);
}
/* A text that is scanned in order fills no table; one probed far from every
   anchor fills it once, and the answers agree either way. */
static void lazy_table(myl_native_heap *heap) {
    uint32_t *points=points_of(20000,100);
    myl_native_text *text=build(heap,points,20000);
    myl_native_root root;
    myl_native_root_push(heap,&root,&text,&pointer);
    size_t *offsets=offsets_of(points,20000);
    for (size_t i=0;i<20000;i++) assert(myl_native_text_offset(text,i)==offsets[i]);
    assert(!(text->flags&MYL_TEXT_SAMPLED));
    assert(myl_native_text_offset(text,10000)==offsets[10000]);
    assert(text->flags&MYL_TEXT_SAMPLED);
    for (size_t i=0;i<20000;i+=13) assert(myl_native_text_offset(text,i)==offsets[i]);
    free(offsets);
    free(points);
    myl_native_root_pop(heap,&root);
}
/* Search results convert a byte offset back to a scalar index. */
static void searching(myl_native_heap *heap) {
    const size_t count=30000;
    uint32_t *points=points_of(count,30);
    points[count-2]='q'; points[count-1]='z';
    myl_native_text *text=build(heap,points,count);
    myl_native_root root, second;
    myl_native_root_push(heap,&root,&text,&pointer);
    myl_native_text *needle=myl_native_text_from_utf8(heap,(const unsigned char *)"qz",2);
    myl_native_root_push(heap,&second,&needle,&pointer);
    assert(myl_native_text_find(text,needle)>=0);
    size_t first=0;
    while (first<count-1 && !(points[first]=='q' && points[first+1]=='z')) first++;
    assert(first>=3);
    assert(myl_native_text_find(text,needle)==(int64_t)first);
    myl_native_text *rest=myl_native_text_slice(heap,text,(int64_t)(first-3),(int64_t)count);
    assert(myl_native_text_find(rest,needle)==3);
    myl_native_root_pop(heap,&second);
    myl_native_root_pop(heap,&root);
    free(points);
}
#ifdef MYL_TEXT_STEPS
/* Octets the position machinery examines while `work` runs. */
static size_t steps_of(void (*work)(myl_native_heap *, myl_native_text *, size_t), myl_native_heap *heap, myl_native_text *text, size_t count) {
    size_t before=myl_native_text_steps;
    work(heap,text,count);
    return myl_native_text_steps-before;
}
static void scan_in_order(myl_native_heap *heap, myl_native_text *text, size_t count) {
    (void)heap;
    for (size_t i=0;i<count;i++) (void)myl_native_text_offset(text,i);
}
static void scan_reversed(myl_native_heap *heap, myl_native_text *text, size_t count) {
    (void)heap;
    for (size_t i=count;i--;) (void)myl_native_text_offset(text,i);
}
static void scan_at_random(myl_native_heap *heap, myl_native_text *text, size_t count) {
    (void)heap;
    for (size_t i=0;i<count;i++) (void)myl_native_text_offset(text,next_random()%count);
}
static void slice_in_order(myl_native_heap *heap, myl_native_text *text, size_t count) {
    for (size_t i=0;i+8<=count;i+=8) assert(myl_native_text_slice(heap,text,(int64_t)i,(int64_t)i+8));
}
/* Ever-shorter tails, the way a parser that keeps the rest of its input does. */
static void tails(myl_native_heap *heap, myl_native_text *text, size_t count) {
    for (size_t i=0;i<count;i+=61) {
        myl_native_text *rest=myl_native_text_slice(heap,text,(int64_t)i,(int64_t)count);
        assert(rest && rest->length==count-i);
    }
}
static void views_in_order(myl_native_heap *heap, myl_native_text *text, size_t count) {
    myl_native_text *view=myl_native_text_slice(heap,text,(int64_t)(count/8),(int64_t)count);
    assert(view && (view->flags&MYL_TEXT_VIEW));
    myl_native_root root;
    myl_native_root_push(heap,&root,&view,&pointer);
    for (size_t i=0;i<view->length;i++) (void)myl_native_text_offset(view,i);
    myl_native_root_pop(heap,&root);
}
static void views_at_random(myl_native_heap *heap, myl_native_text *text, size_t count) {
    myl_native_text *view=myl_native_text_slice(heap,text,(int64_t)(count/8),(int64_t)count);
    assert(view && (view->flags&MYL_TEXT_VIEW));
    myl_native_root root;
    myl_native_root_push(heap,&root,&view,&pointer);
    for (size_t i=0;i<view->length;i++) (void)myl_native_text_offset(view,next_random()%view->length);
    myl_native_root_pop(heap,&root);
}
/* One operation over texts of `small` and `large` scalars: the work grows with
   the text, not with its square, and stays below a fixed number of octets per
   scalar. `each` is that number, generous enough to hold on every shape. */
static void linear(myl_native_heap *heap, void (*work)(myl_native_heap *, myl_native_text *, size_t), size_t each) {
    const size_t small=25000, large=200000;
    size_t steps[2], sizes[2]={small,large};
    for (int round=0;round<2;round++) {
        uint32_t *points=points_of(sizes[round],400);
        myl_native_text *text=build(heap,points,sizes[round]);
        myl_native_root root;
        myl_native_root_push(heap,&root,&text,&pointer);
        assert(!(text->flags&MYL_TEXT_ASCII) && (text->flags&MYL_TEXT_INDEXED));
        steps[round]=steps_of(work,heap,text,sizes[round]);
        assert(steps[round]<=each*sizes[round]);
        myl_native_root_pop(heap,&root);
        free(points);
    }
    /* Eight times the text is at most twelve times the work. */
    assert(steps[1]<=12*steps[0]+4096);
}
static void complexity(myl_native_heap *heap) {
    linear(heap,scan_in_order,8);
    linear(heap,scan_reversed,8);
    linear(heap,scan_at_random,300);
    linear(heap,slice_in_order,300);
    linear(heap,tails,300);
    linear(heap,views_in_order,300);
    linear(heap,views_at_random,600);
}
#endif
/* spec: TEXT-INDEX-4. The literal index occupies a separately protected page;
 * all lookup orders, inverse indexes and owner-view lookups must only read it. */
static void readonly_literal(myl_native_heap *heap) {
    const size_t page=(size_t)sysconf(_SC_PAGESIZE);
    unsigned char *block=mmap(NULL,2*page,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANONYMOUS,-1,0);
    assert(block!=MAP_FAILED);
    myl_native_object *header=(myl_native_object *)block;
    header->mark=MYL_NATIVE_OBJECT_LITERAL_MARK; header->element=&myl_rc_octet_leaf;
    myl_native_text *text=(myl_native_text *)(header+1);
    size_t bytes=page-sizeof *header-sizeof *text, count=bytes/2;
    assert(bytes%8==0);
    text->length=count; text->bytes=bytes; text->hash=0;
    text->flags=MYL_TEXT_INDEXED|MYL_TEXT_SAMPLED|MYL_TEXT_STATIC_INDEX;
    unsigned char *payload=(unsigned char *)(text+1);
    uint32_t *points=malloc(count*sizeof *points); assert(points);
    for (size_t i=0;i<count;i++) { points[i]=0xe9; payload[2*i]=0xc3; payload[2*i+1]=0xa9; }
    myl_native_text_positions *table=(myl_native_text_positions *)(block+page);
    table->scalar=0; table->octet=0;
    for (size_t i=1;i*MYL_TEXT_SAMPLE_STRIDE<count;i++) table->sample[i-1]=(uint32_t)(2*i*MYL_TEXT_SAMPLE_STRIDE);
    assert(mprotect(block+page,page,PROT_READ)==0);
#ifdef MYL_TEXT_STEPS
    myl_native_text_steps=0;
#endif
    orders(text,points,count);
#ifdef MYL_TEXT_STEPS
    assert(myl_native_text_steps<1024*count);
#endif
    myl_native_text *tail=myl_native_text_tail(heap,text,100,count);
    assert(tail && (tail->flags&MYL_TEXT_VIEW));
    myl_native_root root;
    myl_native_root_push(heap,&root,&tail,&pointer);
    orders(tail,points+100,count-100);
    assert(myl_native_text_hash(text)==myl_native_octets_hash(payload,bytes));
    myl_native_heap_collect(heap);
    assert(myl_native_text_point_at(tail,900)==0xe9 && table->scalar==0 && table->octet==0);
    myl_native_root_pop(heap,&root);
    myl_native_heap_collect(heap);
    free(points);
    assert(munmap(block,2*page)==0);
}
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<24); heap.stress=1;
    shapes(&heap);
    which_carry_an_index(&heap);
    single_scalars(&heap);
    pieces(&heap);
    lazy_table(&heap);
    searching(&heap);
    arenas(&heap);
    readonly_literal(&heap);
#ifdef MYL_TEXT_STEPS
    /* The linear-work checks run without the collection stress that dominates
       a run of this size. */
    heap.stress=0;
    complexity(&heap);
#endif
    myl_native_heap_collect(&heap);
    /* Only the table of shared one-scalar ASCII texts `myl_native_text_at` builds
       outlives its users. */
    assert(heap.objects_live==(heap.text_scalars_ready ? 128u : 0u));
    myl_native_heap_destroy(&heap);
    puts("native text index tests passed");
    return 0;
}
