/* spec-case: PY-TEXT-RANGE-1, PY-TEXT-TRIM-1, PRELUDE-REPR-1.
   Real-runtime owned/view/arena checks and deterministic linear-work bounds.
   The small expected values are CPython3.14.4 / Unicode16.0.0 results. */
#include "native_python.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static myl_native_list *bag;
void myl_qbe_fail(void *context,const char *code) {
    (void)context; (void)code;
    assert(0 && "unexpected text trap");
}
static void keep(myl_native_heap *heap,void *value) {
    assert(value);
    myl_native_root root;
    myl_native_root_push(heap,&root,&value,&pointer);
    assert(myl_native_list_append(heap,bag,&value));
    myl_native_root_pop(heap,&root);
}
static myl_native_text *text(myl_native_heap *heap,const char *value) {
    myl_native_text *out=myl_native_text_from_utf8(heap,(const unsigned char *)value,strlen(value));
    keep(heap,out);
    return out;
}
static void equals(const myl_native_text *value,const char *expected) {
    assert(value && value->bytes==strlen(expected));
    assert(!memcmp(myl_native_text_storage(value),expected,value->bytes));
}
static uint64_t seed=UINT64_C(0xB120260929);
static unsigned next(void) {
    seed=seed*UINT64_C(6364136223846793005)+1;
    return (unsigned)(seed>>32);
}
static int64_t naive_rfind(const unsigned char *a,size_t n,const unsigned char *b,size_t m) {
    if (m>n) return -1;
    for (size_t at=n-m+1;at--;) if (!memcmp(a+at,b,m)) return (int64_t)at;
    return -1;
}
static void random_reverse(void) {
    unsigned char a[256],b[80];
    for (unsigned trial=0;trial<4000;trial++) {
        size_t n=next()%sizeof a,m=next()%sizeof b;
        for (size_t i=0;i<n;i++) a[i]=(unsigned char)(next()%4);
        for (size_t i=0;i<m;i++) b[i]=(unsigned char)(next()%4);
        myl_native_bytes input={.storage=a,.length=n},needle={.storage=b,.length=m};
        assert(myl_native_bytes_search_range(&input,&needle,0,INT64_MAX,MYL_SEARCH_RFIND)==naive_rfind(a,n,b,m));
    }
}
static void periodic_reverse(size_t count) {
    size_t width=count/8;
    unsigned char *a=malloc(count),*b=malloc(width);
    assert(a && b);
    memset(a,'a',count);memset(b,'a',width);
    myl_native_bytes input={.storage=a,.length=count},needle={.storage=b,.length=width};
    for (unsigned end=0;end<2;end++) {
        b[end ? width-1 : 0]='b';
        myl_native_search_steps=0;
        assert(myl_native_bytes_search_range(&input,&needle,0,INT64_MAX,MYL_SEARCH_RFIND)==-1);
        assert(myl_native_search_steps<=20*(count+width));
        b[end ? width-1 : 0]='a';
    }
    assert(myl_native_bytes_search_range(&input,&needle,0,INT64_MAX,MYL_SEARCH_RFIND)==(int64_t)(count-width));
    free(a);free(b);
}
static myl_native_text *alternating(myl_native_heap *heap,size_t count) {
    uint32_t *points=malloc(count*sizeof *points);
    assert(points);
    for (size_t i=0;i<count;i++) points[i]=i%2 ? 0x1f600 : 0xe9;
    myl_native_text *out=myl_native_text_from_scalars(heap,points,count);
    free(points);keep(heap,out);
    return out;
}
static void unicode_windows(const myl_native_text *input,const myl_native_text *needle) {
    myl_native_text_steps=myl_native_search_steps=0;
    size_t queries=0;
    for (size_t first=0;first<input->length;first+=17) {
        size_t last=first+64<input->length ? first+64 : input->length;
        int64_t expected=(int64_t)((last-1)&~(size_t)1);
        if (expected<(int64_t)first) expected=-1;
        assert(myl_native_text_search_range(input,needle,(int64_t)first,(int64_t)last,MYL_SEARCH_RFIND)==expected);
        queries++;
    }
    /* The sampled position index bounds unrelated windows too; repeatedly
       walking from scalar zero would exceed this without relying on a clock. */
    assert(myl_native_text_steps<=input->bytes*3+queries*4096);
    assert(myl_native_search_steps<=queries*512);
}
static void unicode_views(myl_native_heap *heap) {
    myl_native_text *input=alternating(heap,32768),*needle=text(heap,"é");
    unicode_windows(input,needle);
    myl_native_text *view=myl_native_text_copy(heap,input,2048,24576);keep(heap,view);
    assert(view->flags&MYL_TEXT_VIEW);unicode_windows(view,needle);
    myl_native_text *nested=myl_native_text_copy(heap,view,2048,16384);keep(heap,nested);
    assert(nested->flags&MYL_TEXT_VIEW);unicode_windows(nested,needle);
    myl_native_repr_steps=myl_native_text_steps=0;
    myl_native_text *represented=myl_native_text_repr(heap,nested);keep(heap,represented);
    assert(represented->length==nested->length+2);
    assert(myl_native_repr_steps<=32*nested->bytes);
    for (size_t i=1;i<represented->length-1;i++)
        assert(myl_native_text_point_at(represented,i)==(i%2 ? 0xe9 : 0x1f600));
    assert(myl_native_text_steps<=8*represented->bytes);
}
static void charset_budget(myl_native_heap *heap) {
    uint32_t points[40];
    for (unsigned i=0;i<40;i++) points[i]=0x400+i;
    myl_native_text *chars=myl_native_text_from_scalars(heap,points,40);keep(heap,chars);
    uint32_t *input=malloc(65536*sizeof *input);assert(input);
    for (size_t i=0;i<65536;i++) input[i]=points[i%40];
    input[32768]='x';
    myl_native_text *value=myl_native_text_from_scalars(heap,input,65536);free(input);keep(heap,value);
    size_t original_limit=heap->limit,bytes=heap->bytes;
    heap->limit=bytes+0x110000/8-1;heap->exhausted=0;
    assert(!myl_native_text_trim_chars(heap,value,chars,0));
    assert(heap->exhausted && heap->bytes==bytes);
    heap->limit=original_limit;heap->exhausted=0;
    myl_native_trim_steps=myl_native_text_steps=0;
    myl_native_text *trimmed=myl_native_text_trim_chars(heap,value,chars,0);keep(heap,trimmed);
    equals(trimmed,"x");
    assert(myl_native_trim_steps<=4*(value->length+chars->length)+4096);
    assert(myl_native_text_steps<=4*value->bytes);
}
static void arena_repr(myl_native_heap *heap) {
    assert(myl_native_region_begin(heap));
    bag=myl_native_list_new(heap,&pointer,0);assert(bag);
    myl_native_text *input=text(heap,"\xc2\xa0'\xc3\xa9'\xc2\xa0"),*chars=text(heap,"\xc2\xa0'");
    myl_native_text *trimmed=myl_native_text_trim_chars(heap,input,chars,0);keep(heap,trimmed);equals(trimmed,"é");
    myl_native_text *represented=myl_native_text_repr(heap,input);keep(heap,represented);equals(represented,"\"\\xa0'é'\\xa0\"");
    /* Discard all roots into this arena before its contents are retired. */
    bag=NULL;
    myl_native_region_end(heap);
}
static void repr_refusal(void) {
    myl_native_heap heap;myl_native_heap_init(&heap,1u<<20);heap.stress=1;
    unsigned char data[10000]={0};
    myl_native_text *input=myl_native_text_from_utf8(&heap,data,sizeof data);assert(input);
    /* Escapes require a new allocation larger than the input's size class;
       a refused allocation must not publish a partial represented value. */
    heap.limit=heap.bytes;heap.exhausted=0;
    assert(!myl_native_text_repr(&heap,input));assert(heap.exhausted);
    myl_native_heap_destroy(&heap);
}
int main(void) {
    random_reverse();
    for (size_t n=4096;n<=65536;n*=4) periodic_reverse(n);
    myl_native_heap heap;myl_native_heap_init(&heap,1u<<25);heap.stress=1;
    bag=myl_native_list_new(&heap,&pointer,0);assert(bag);
    myl_native_root root;myl_native_root_push(&heap,&root,&bag,&pointer);
    unicode_views(&heap);charset_budget(&heap);arena_repr(&heap);
    myl_native_root_pop(&heap,&root);myl_native_heap_destroy(&heap);
    repr_refusal();
    puts("native-python: 4000 reverse oracles, periodic linear bounds, indexed Unicode views, trim budget, repr arena/refusal passed");
    return 0;
}
