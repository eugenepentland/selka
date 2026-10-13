/* Descriptor-driven aggregate copies preserve scalar bits and unique owners. */
#include "core_rt.c"
#include <assert.h>
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
const myl_core_site myl_core_sites[1];
const char myl_core_source_path[] = "owned-copy-stack-regression";
static const core_value_shape scalar = {.kind=1, .size=8};
static const core_value_shape real = {.kind=2, .size=8};
static const core_value_shape text = {.kind=3, .size=8};
static const core_value_shape unit = {.kind=0, .size=0};
static const core_value_shape *const scalars[] = {&scalar};
static const core_value_shape *const texts[] = {&text};
static const core_value_shape numbers = {.kind=8, .size=64, .count=8, .children=scalars};
static const core_value_shape owners = {.kind=8, .size=16, .count=2, .children=texts};
static const core_value_shape *const arms[] = {&scalar, &text};
static const core_value_shape choice = {.kind=5, .size=16, .count=2, .children=arms};
typedef struct { uint64_t tag; union { uint64_t bits; myl_block *owner; } value; } choice_value;
typedef struct { uint64_t number; double real; myl_block *text; myl_block *owners[2]; choice_value choice; uint64_t numbers[8]; } record_value;
_Static_assert(sizeof(record_value)==120, "record shape size");
_Static_assert(offsetof(record_value, choice)==40, "union offset");
static const core_value_shape *const fields[] = {&scalar, &real, &text, &owners, &choice, &numbers, &unit};
static const uint32_t offsets[] = {0, 8, 16, 24, 40, 56, 0};
static const core_value_shape record = {.kind=4, .size=120, .count=7, .children=fields, .offsets=offsets};
static const core_value_shape *const records[] = {&record};
static const core_value_shape root = {.kind=7, .size=8, .children=records};
/* The scalar union arm must never be traversed as an owner. */
static const int32_t layout[] = {120, 4, 1, 16, 0, 24, 0, 32, 0, 48, 1, 40, 1, 0};
static void drop(myl_block *value) {
#ifdef MYL_ZERO_RC
    myl_core_drop_owned(value);
#else
    if (count_release(value)) myl_core_free_block(value);
#endif
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
    myl_block *copy=myl_core_values_copy_box(&root,source);
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
    drop(source);drop(copy);assert(live_count()==0);
}
static void roots(void) {
    assert((uintptr_t)myl_core_values_copy_box(&scalar,(myl_block *)(uintptr_t)UINT64_C(0xabcdef))==UINT64_C(0xabcdef));
    assert(myl_core_values_copy_box(&unit,(myl_block *)(uintptr_t)UINT64_C(0xabcdef))==NULL);
    static const core_value_shape *const units[] = {&unit};
    static const core_value_shape empty = {.kind=8, .size=0, .count=9, .children=units};
    assert(myl_core_values_copy_box(&empty,NULL)==NULL);
    static const core_value_shape box = {.kind=6, .size=8, .children=scalars};
    myl_block *source=myl_core_box_new(8);*(uint64_t *)block_data(source)=UINT64_C(0xabcdef9876543210);
    myl_block *copy=myl_core_values_copy_box(&box,source);
    assert(copy!=source && *(uint64_t *)block_data(copy)==UINT64_C(0xabcdef9876543210));
    drop(source);drop(copy);assert(live_count()==0);
    static const core_value_shape list_shape = {.kind=7, .size=8, .children=scalars};
    source=myl_core_list_new_slow(3,8);source->len=3;
    for (int i=0;i<3;++i) ((uint64_t *)block_data(source))[i]=UINT64_C(0xfedcba9876543210)+(unsigned)i;
    copy=myl_core_values_copy_box(&list_shape,source);
    assert(copy!=source && copy->len==3 && !memcmp(block_data(copy),block_data(source),24));
    drop(source);drop(copy);assert(live_count()==0);
}

static const int32_t pointer_layout[] = {8, 1, 0, 0, 0};
static const core_value_shape chain;
static const core_value_shape *const chain_children[] = {&chain};
static const core_value_shape chain = {.kind=7, .size=8, .children=chain_children};
static void growth_and_recursion(void) {
    static const int lengths[] = {0, 1, 63, 64, 65, 129};
    static const core_value_shape list_shape = {.kind=7, .size=8, .children=scalars};
    for (unsigned at=0;at<sizeof lengths/sizeof *lengths;++at) {
        int n=lengths[at];myl_block *source=myl_core_list_new_slow(n,8);source->len=n;
        for (int i=0;i<n;++i) ((uint64_t *)block_data(source))[i]=UINT64_C(0xfedcba9876543210)+(unsigned)i;
        myl_block *copy=myl_core_values_copy_box(&list_shape,source);
        assert(copy!=source && copy->len==n && !memcmp(block_data(copy),block_data(source),(size_t)n*8));
        drop(source);drop(copy);assert(live_count()==0);
    }
    uint64_t values[65], saved[65];core_copy_stack stack;
    stack.items=stack.local;stack.count=0;stack.capacity=64;
    for (int i=0;i<65;++i) {values[i]=(uint64_t)(42+i);core_copy_push(&stack,&scalar,&values[i],&saved[i]);}
    assert(stack.count==65 && stack.capacity==128 && stack.items!=stack.local);
    while(stack.count) {core_copy_work work=stack.items[--stack.count];memcpy(work.target,work.source,work.shape->size);}
    assert(!memcmp(values,saved,sizeof values));free(stack.items);
    myl_block *head=myl_core_list_new_slow(1,8), *tail=head;
    head->len=1;head->reserved=(int64_t)(intptr_t)pointer_layout;
    for (int i=0;i<20000;++i) {
        myl_block *next=myl_core_list_new_slow(1,8);next->len=1;next->reserved=(int64_t)(intptr_t)pointer_layout;
        *(myl_block **)block_data(tail)=next;tail=next;
    }
    tail->len=0;myl_block *copy=myl_core_values_copy_box(&chain,head);assert(copy!=head);
    drop(head);drop(copy);assert(live_count()==0);
}
static void static_and_empty(void) {
    static const struct { myl_block header; unsigned char bytes[5]; } literal = {
        .header={.kind=MYL_KIND_STR|MYL_STATIC_STORAGE, .len=4, .cap=4,
#ifndef MYL_ZERO_RC
        .count=MYL_SATURATED,
#endif
        }, .bytes={'p','i','n','s',0}
    };
    myl_block *copy=myl_core_values_copy_box(&text,&literal.header);
    assert(copy!=&literal.header && copy->len==4 && !memcmp(block_data(copy),"pins",4));
    drop(copy);drop((myl_block *)&literal.header);
    assert(myl_core_values_copy_box(&text,NULL)==NULL);assert(live_count()==0);
}

static void refusal(const char *mode) {
    if (!strcmp(mode,"tag")) {
        static const core_value_shape *const union_child[] = {&choice};
        static const core_value_shape box = {.kind=6, .size=8, .children=union_child};
        myl_block *source=myl_core_box_new(16);memset(block_data(source),0,16);*(uint64_t *)block_data(source)=2;
        (void)myl_core_values_copy_box(&box,source);
    } else {
        core_value_shape rejected={.kind=!strcmp(mode,"resource")?10:99, .size=8};
        (void)myl_core_values_copy_box(&rejected,NULL);
    }
    exit(77); /* Successful validation is a test failure. */
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
    if(argc>1) refusal(argv[1]);
    aggregate();roots();growth_and_recursion();static_and_empty();assert(live_count()==0);
#ifdef P7_STACK_COUNTED
    myl_count_dump();
#endif
    puts("copy stack paths passed; live=0");return 0;
}
