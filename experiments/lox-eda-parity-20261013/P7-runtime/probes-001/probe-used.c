/* Standalone runtime contract checks; cost counters live only in private probes. */
#include "probe-runtime.c"
#include <assert.h>
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
const myl_core_site myl_core_sites[1];
const char myl_core_source_path[] = "runtime-prototype-probe";

static const int32_t pointers[] = {8, 1, 0, 0, 0};
static const int32_t wide_refs[] = {16, 2, 0, 0, 0, 8, 0};
static const int32_t guarded_refs[] = {16, 1, 1, 8, 1, 0, 1, 0};
static const int32_t offset_refs[] = {16, 1, 0, 8, 0};
static const int32_t record_refs[] = {1056, 1, 0, 16, 0};
static const int32_t dict_refs[] = {16, 1, 0, 8, 0};
static const core_value_shape integer_shape = {.kind=1, .size=8};
static const core_value_shape real_shape = {.kind=2, .size=8};
static const core_value_shape text_shape = {.kind=3, .size=8};
static const core_value_shape *const scalar_array_children[] = {&integer_shape};
static const core_value_shape scalar_array_shape = {.kind=8, .size=1024, .count=128, .children=scalar_array_children};
static const core_value_shape *const wide_children[] = {&integer_shape, &real_shape, &text_shape, &scalar_array_shape};
static const uint32_t wide_offsets[] = {0, 8, 16, 24};
static const core_value_shape wide_shape = {.kind=4, .size=1056, .count=4, .children=wide_children, .offsets=wide_offsets};
static const core_value_shape *const wide_list_children[] = {&wide_shape};
static const core_value_shape wide_list_shape = {.kind=7, .size=8, .children=wide_list_children};
static const core_value_shape *const integer_list_children[] = {&integer_shape};
static const core_value_shape integer_list_shape = {.kind=7, .size=8, .children=integer_list_children};
static const core_value_shape *const scalar_box_children[] = {&integer_shape};
static const core_value_shape scalar_box_shape = {.kind=6, .size=8, .children=scalar_box_children};
static const core_value_shape chain_shape;
static const core_value_shape *const chain_children[] = {&chain_shape};
static const core_value_shape chain_shape = {.kind=7, .size=8, .children=chain_children};
static const core_value_shape *const dict_children[] = {&integer_shape, &text_shape};
static const core_value_shape dict_shape = {.kind=9, .size=8, .children=dict_children};
static const core_dict_descriptor dictionary = {.stride=16, .value_offset=8, .key_kind=1, .key_size=8, .layout=dict_refs};

typedef struct { uint64_t integer; double real; myl_block *text; uint64_t array[128]; uint64_t tail; } wide_value;
_Static_assert(sizeof(wide_value)==1056, "wide descriptor size");
_Static_assert(offsetof(wide_value,text)==16, "managed field offset");
static void drop(myl_block *value) {
#ifdef MYL_ZERO_RC
    myl_core_drop_owned(value);
#else
    if (count_release(value)) myl_core_free_block(value);
#endif
}
static myl_block *list(int64_t count, int64_t stride, const int32_t *layout) {
    myl_block *result=myl_core_list_new_slow(count,stride);
    result->len=count;result->reserved=(int64_t)(intptr_t)layout;
    memset(block_data(result),0,(size_t)count*(size_t)stride);
    return result;
}
static void copying(void) {
    myl_block *source=list(3,sizeof(wide_value),record_refs);
    wide_value *values=(wide_value *)block_data(source);
    for (int i=0;i<3;++i) {
        values[i].integer=UINT64_C(0xfedcba9876543210)+(unsigned)i;
        uint64_t bits=UINT64_C(0x7ff8000000000042)+(unsigned)i;memcpy(&values[i].real,&bits,8);
        values[i].text=str_from("independent",11);
        for (int j=0;j<128;++j) values[i].array[j]=(uint64_t)(1000*i+j);
        values[i].tail=UINT64_C(0x123456789abcdef0);
    }
    uint64_t before=probe_copy_pushes, allocs=probe_block_allocs;
    myl_block *copy=myl_core_values_copy_box(&wide_list_shape,source);
    uint64_t pushes=probe_copy_pushes-before, blocks=probe_block_allocs-allocs;
    wide_value *saved=(wide_value *)block_data(copy);
    for (int i=0;i<3;++i) {
        assert(saved[i].integer==values[i].integer && !memcmp(&saved[i].real,&values[i].real,8));
        assert(saved[i].tail==values[i].tail && !memcmp(saved[i].array,values[i].array,sizeof saved[i].array));
        assert(saved[i].text!=values[i].text && !memcmp(block_data(saved[i].text),"independent",11));
        values[i].array[17]=99999;block_data(values[i].text)[0]='X';
        assert(saved[i].array[17]!=(uint64_t)99999 && block_data(saved[i].text)[0]=='i');
    }
    drop(source);drop(copy);
    myl_block *ints=list(5,8,NULL);for (int i=0;i<5;++i)((uint64_t *)block_data(ints))[i]=(uint64_t)(42+i);
    myl_block *ints_copy=myl_core_values_copy_box(&integer_list_shape,ints);
    assert(!memcmp(block_data(ints),block_data(ints_copy),40));drop(ints);drop(ints_copy);
    myl_block *box=myl_core_box_new(8);*(uint64_t *)block_data(box)=UINT64_C(0xabcdef9876543210);
    myl_block *box_copy=myl_core_values_copy_box(&scalar_box_shape,box);
    assert(box_copy!=box && *(uint64_t *)block_data(box_copy)==UINT64_C(0xabcdef9876543210));drop(box);drop(box_copy);
    printf("copy_pushes=%llu copy_blocks=%llu\n",(unsigned long long)pushes,(unsigned long long)blocks);
}
static unsigned visitor_calls;
static void visit_only(myl_block *value,void *context) { (void)value;(void)context;++visitor_calls; }
static myl_block immortal={.kind=MYL_KIND_STR|MYL_STATIC_STORAGE};
static void pointer_drops(void) {
#ifndef MYL_ZERO_RC
    immortal.count=MYL_SATURATED;
#endif
    myl_block *root=list(5,8,pointers),*nested=list(1,8,pointers),*box=myl_core_box_new(8);
    box->reserved=(int64_t)(intptr_t)pointers;
    ((myl_block **)block_data(nested))[0]=str_from("nested",6);
    *(myl_block **)block_data(box)=str_from("boxed",5);
    myl_block *children[]={NULL,str_from("leaf",4),nested,box,&immortal};memcpy(block_data(root),children,sizeof children);
    core_children(root,visit_only,NULL);assert(visitor_calls==4);
    uint64_t before=probe_reference_reads;drop(root);
    printf("pointer_references=%llu\n",(unsigned long long)(probe_reference_reads-before));
    root=list(1,16,wide_refs);
    ((myl_block **)block_data(root))[0]=str_from("left",4);((myl_block **)block_data(root))[1]=str_from("right",5);drop(root);
    root=list(2,16,guarded_refs);uint64_t *cells=(uint64_t *)block_data(root);cells[0]=0;cells[1]=UINT64_C(0xdeadbeef);cells[2]=1;
    myl_block *active=str_from("active",6);memcpy(&cells[3],&active,sizeof active);drop(root);
    root=list(1,16,offset_refs);*(uint64_t *)block_data(root)=UINT64_C(0xdeadbeef);active=str_from("offset",6);memcpy(block_data(root)+8,&active,8);drop(root);
}
static void dictionary_copy(void) {
    myl_block *dict=myl_core_dict_new(12,&dictionary);
    for (uint64_t key=0;key<12;++key) {myl_block *value=str_from("dict",4);dict=myl_core_dict_insert(dict,-1,&key,&value,false);}
    myl_block *copy=myl_core_values_copy_box(&dict_shape,dict);assert(copy!=dict && copy->len==12);
    for(uint64_t i=0;i<12;++i) {myl_block *a,*b;memcpy(&a,dict_entry(dict,i)+8,8);memcpy(&b,dict_entry(copy,i)+8,8);assert(a!=b && !memcmp(block_data(b),"dict",4));}
    drop(dict);drop(copy);
}
static void recursive_cleanup(void) {
    myl_block *head=list(1,8,pointers),*tail=head;
    for(int i=0;i<20000;++i) {myl_block *next=list(1,8,pointers);*(myl_block **)block_data(tail)=next;tail=next;}
    tail->len=0;myl_block *copy=myl_core_values_copy_box(&chain_shape,head);assert(copy!=head);
    uint64_t before=probe_reference_reads;drop(head);drop(copy);
    printf("recursive_references=%llu\n",(unsigned long long)(probe_reference_reads-before));
}
static void invalid(const char *name) {
    core_value_shape child=integer_shape;
    if (!strcmp(name,"resource")) {child.kind=10;child.aux=0;}
    if (!strcmp(name,"descriptor")) child.kind=255;
    const core_value_shape *children[]={&child};uint32_t offset=0;
    core_value_shape record={.kind=4,.size=8,.count=1,.children=children,.offsets=&offset};
    const core_value_shape *roots[]={&record};core_value_shape shape={.kind=7,.size=8,.children=roots};
    if (!strcmp(name,"tag")) {record.kind=5;record.size=16;record.count=1;}
    myl_block *source=list(1,record.size,NULL);*(uint64_t *)block_data(source)=99;
    (void)myl_core_values_copy_box(&shape,source);exit(77);
}
int main(int argc,char **argv) {
    if (argc>1) invalid(argv[1]);
    copying();pointer_drops();dictionary_copy();recursive_cleanup();
    assert(live_count()==0);puts("runtime contracts passed; live=0");return 0;
}
