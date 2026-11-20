/* Generated aggregate callbacks preserve scalar bits and unique owners. */
#include "core_rt.c"
#include <assert.h>
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
const myl_core_site myl_core_sites[1];
const char myl_core_source_path[] = "owned-copy-stack-regression";
typedef struct { uint64_t tag; union { uint64_t bits; myl_block *owner; } value; } choice_value;
typedef struct { uint64_t number; double real; myl_block *text; myl_block *owners[2]; choice_value choice; uint64_t numbers[8]; } record_value;
_Static_assert(sizeof(record_value)==120, "record shape size");
_Static_assert(offsetof(record_value, choice)==40, "union offset");
static void copy_leaf(void *work, const void *source, void *target) {
    (void)work; myl_core_owned_copy_leaf(source,target);
}
static void copy_scalar(void *work, const void *source, void *target) {
    (void)work; memcpy(target,source,8);
}
static void copy_record(void *work, const void *source, void *target) {
    const record_value *from=source; record_value *to=target;
    copy_leaf(work,&from->text,&to->text);
    myl_core_owned_copy_array(work,from->owners,to->owners,copy_leaf,2,8);
    if (from->choice.tag==1) copy_leaf(work,&from->choice.value.owner,&to->choice.value.owner);
}
static void copy_records(void *work, const void *source, void *target) {
    myl_core_owned_copy_items(work,source,target,copy_record,sizeof(record_value),false);
}
static void copy_scalar_box(void *work, const void *source, void *target) {
    myl_core_owned_copy_items(work,source,target,NULL,8,true);
}
static void copy_scalar_list(void *work, const void *source, void *target) {
    myl_core_owned_copy_items(work,source,target,NULL,8,false);
}
/* The scalar union arm must never be traversed as an owner. */
static unsigned record_drops;
typedef void (*fixture_drop)(const unsigned char *, void *);
static void drop_record(const unsigned char *element, void *pending) {
    const record_value *value=(const record_value *)element; ++record_drops;
    myl_core_drop_child_pending(value->text,pending);
    for (int i=0;i<2;++i) myl_core_drop_child_pending(value->owners[i],pending);
    if (value->choice.tag==1) myl_core_drop_child_pending(value->choice.value.owner,pending);
}
static const struct { int32_t words[14]; fixture_drop whole,key,value; } record_layout = {
    {120,4,-2,16,0,24,0,32,0,48,1,40,1,0},drop_record,NULL,NULL
};
#define layout record_layout.words
static void drop(myl_block *value) {
    myl_core_drop_owned(value);
}
static void aggregate(void) {
    myl_block *source=myl_core_list_new_slow(2,sizeof(record_value));
    source->len=2;source->reserved=(int64_t)(intptr_t)layout;
    record_value *values=(record_value *)block_data(source);memset(values,0,2*sizeof *values);
    for (int i=0;i<2;++i) {
        values[i].number=UINT64_C(0xfedcba9876543210)+(unsigned)i;
        uint64_t bits=UINT64_C(0x7ff8000000000042)+(unsigned)i;memcpy(&values[i].real,&bits,8);
        values[i].text=str_from("record",6);
        for (int j=0;j<2;++j) values[i].owners[j]=str_from("array",5);
        values[i].choice.tag=(uint64_t)i;
        if (i) values[i].choice.value.owner=str_from("union",5);
        else values[i].choice.value.bits=UINT64_C(0xdeadbeefcafef00d);
        for (int j=0;j<8;++j) values[i].numbers[j]=(uint64_t)(100*i+j);
    }
    myl_block *copy=myl_core_values_copy_generated(copy_records,source);
    assert(copy!=source && copy->len==source->len && copy->reserved==source->reserved);
    record_value *saved=(record_value *)block_data(copy);
    for (int i=0;i<2;++i) {
        assert(saved[i].number==values[i].number && !memcmp(&saved[i].real,&values[i].real,8));
        assert(!memcmp(saved[i].numbers,values[i].numbers,sizeof saved[i].numbers));
        assert(saved[i].text!=values[i].text && !memcmp(block_data(saved[i].text),"record",6));
        block_data(values[i].text)[0]='X';assert(block_data(saved[i].text)[0]=='r');
        for (int j=0;j<2;++j) {
            assert(saved[i].owners[j]!=values[i].owners[j]);
            block_data(values[i].owners[j])[0]='X';assert(block_data(saved[i].owners[j])[0]=='a');
        }
        values[i].numbers[3]=999;assert(saved[i].numbers[3]!=999);
    }
    assert(saved[0].choice.value.bits==UINT64_C(0xdeadbeefcafef00d));
    assert(saved[1].choice.value.owner!=values[1].choice.value.owner);
    block_data(values[1].choice.value.owner)[0]='X';assert(block_data(saved[1].choice.value.owner)[0]=='u');
    drop(source);drop(copy);assert(live_count()==0 && record_drops==4);
}
static void roots(void) {
    assert((uintptr_t)myl_core_values_copy_generated(NULL,(myl_block *)(uintptr_t)UINT64_C(0xabcdef))==UINT64_C(0xabcdef));
    assert(myl_core_values_copy_generated(NULL,NULL)==NULL);
    myl_block *source=myl_core_box_new(8);*(uint64_t *)block_data(source)=UINT64_C(0xabcdef9876543210);
    myl_block *copy=myl_core_values_copy_generated(copy_scalar_box,source);
    assert(copy!=source && *(uint64_t *)block_data(copy)==UINT64_C(0xabcdef9876543210));
    drop(source);drop(copy);assert(live_count()==0);
    source=myl_core_list_new_slow(3,8);source->len=3;
    for (int i=0;i<3;++i) ((uint64_t *)block_data(source))[i]=UINT64_C(0xfedcba9876543210)+(unsigned)i;
    copy=myl_core_values_copy_generated(copy_scalar_list,source);
    assert(copy!=source && copy->len==3 && !memcmp(block_data(copy),block_data(source),24));
    drop(source);drop(copy);assert(live_count()==0);
}

static unsigned pointer_drops;
static void drop_pointer(const unsigned char *element, void *pending) {
    ++pointer_drops; myl_block *child; memcpy(&child,element,sizeof child);
    myl_core_drop_child_pending(child,pending);
}
static const struct { int32_t words[5]; fixture_drop whole,key,value; } pointer_descriptor = {
    {8,1,-1,0,0},drop_pointer,NULL,NULL
};
#define pointer_layout pointer_descriptor.words
static void copy_chain(void *work, const void *source, void *target) {
    myl_core_owned_copy_items(work,source,target,copy_chain,8,false);
}
static void growth_and_recursion(void) {
    static const int lengths[] = {0, 1, 63, 64, 65, 129};
    for (unsigned at=0;at<sizeof lengths/sizeof *lengths;++at) {
        int n=lengths[at];myl_block *source=myl_core_list_new_slow(n,8);source->len=n;
        for (int i=0;i<n;++i) ((uint64_t *)block_data(source))[i]=UINT64_C(0xfedcba9876543210)+(unsigned)i;
        myl_block *copy=myl_core_values_copy_generated(copy_scalar_list,source);
        assert(copy!=source && copy->len==n && !memcmp(block_data(copy),block_data(source),(size_t)n*8));
        drop(source);drop(copy);assert(live_count()==0);
    }
    uint64_t values[65], saved[65];core_owned_copy_stack stack;
    stack.items=stack.local;stack.count=0;stack.capacity=64;
    for (int i=0;i<65;++i) {values[i]=(uint64_t)(42+i);core_owned_copy_push(&stack,copy_scalar,&values[i],&saved[i]);}
    assert(stack.count==65 && stack.capacity==128 && stack.items!=stack.local);
    while(stack.count) {core_owned_copy_work work=stack.items[--stack.count];work.copy(&stack,work.source,work.target);}
    assert(!memcmp(values,saved,sizeof values));free(stack.items);
    myl_block *head=myl_core_list_new_slow(1,8), *tail=head;
    head->len=1;head->reserved=(int64_t)(intptr_t)pointer_layout;
    for (int i=0;i<20000;++i) {
        myl_block *next=myl_core_list_new_slow(1,8);next->len=1;next->reserved=(int64_t)(intptr_t)pointer_layout;
        *(myl_block **)block_data(tail)=next;tail=next;
    }
    tail->len=0;myl_block *copy=myl_core_values_copy_generated(copy_chain,head);assert(copy!=head);
    drop(head);drop(copy);assert(live_count()==0 && pointer_drops==40000);
}
static void static_and_empty(void) {
    static const struct { myl_block header; unsigned char bytes[5]; } literal = {
        .header={.kind=MYL_KIND_STR|MYL_STATIC_STORAGE, .len=4, .cap=4,
        }, .bytes={'p','i','n','s',0}
    };
    myl_block *copy=myl_core_values_copy_generated(copy_leaf,&literal.header);
    assert(copy!=&literal.header && copy->len==4 && !memcmp(block_data(copy),"pins",4));
    drop(copy);drop((myl_block *)&literal.header);
    assert(myl_core_values_copy_generated(copy_leaf,NULL)==NULL);assert(live_count()==0);
    static const myl_block empty = {.kind=MYL_KIND_LIST|MYL_STATIC_STORAGE};
    copy=myl_core_values_copy_generated(copy_scalar_list,&empty);
    assert(copy==&empty && live_count()==0);
    myl_block *first=myl_core_list_grow((myl_block *)&empty,8);
    myl_block *second=myl_core_list_grow((myl_block *)&empty,8);
    assert(first!=second && first!=&empty && second!=&empty && empty.len==0 && empty.cap==0);
    first->len=1;*(uint64_t *)block_data(first)=99;
    assert(second->len==0 && empty.len==0);drop(first);drop(second);assert(live_count()==0);
}

static void sanitizer_control(int argc, bool address) {
    if (address) {
        volatile unsigned char *bytes=malloc(8);bytes[argc*4]=7;free((void *)bytes);
    } else {
        volatile uint64_t values[1]={42};printf("%llu\n",(unsigned long long)values[argc]);
    }
}
int main(int argc,char **argv) {
    if(argc>1 && (!strcmp(argv[1],"asan-control") || !strcmp(argv[1],"ubsan-control"))) {
        sanitizer_control(argc,!strcmp(argv[1],"asan-control"));return 77;
    }
    aggregate();roots();growth_and_recursion();static_and_empty();assert(live_count()==0);
#ifdef P7_STACK_COUNTED
    myl_count_dump();
#endif
    puts("copy stack paths passed; live=0");return 0;
}
