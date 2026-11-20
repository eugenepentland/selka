/* Generated aggregate callbacks preserve scalar bits and unique owners. */
#include "core_rt.c"
#include <assert.h>
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
const myl_core_site myl_core_sites[1];
const char myl_core_source_path[] = "owned-aggregate-copy-regression";
typedef struct { uint64_t tag; union { uint64_t bits; myl_block *owner; } value; } choice_value;
typedef struct { uint64_t number; double real; myl_block *text; myl_block *owners[2]; choice_value choice; uint64_t numbers[8]; } record_value;
_Static_assert(sizeof(record_value)==120, "record shape size");
_Static_assert(offsetof(record_value, choice)==40, "union offset");
static void copy_leaf(void *work, const void *source, void *target) {
    (void)work; myl_core_owned_copy_leaf(source,target);
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
static unsigned dictionary_drops,key_drops,value_drops;
static void drop_entry(const unsigned char *entry,void *pending) {
    ++dictionary_drops; myl_block *key,*value;
    memcpy(&key,entry,8);memcpy(&value,entry+8,8);
    myl_core_drop_child_pending(key,pending);myl_core_drop_child_pending(value,pending);
}
static void drop_key(const unsigned char *entry,void *pending) {
    (void)pending;++key_drops;myl_block *key;memcpy(&key,entry,8);drop(key);
}
static void drop_value(const unsigned char *entry,void *pending) {
    (void)pending;++value_drops;myl_block *value;memcpy(&value,entry+8,8);drop(value);
}
static const struct { int32_t words[7]; fixture_drop whole,key,value; } entry_layout = {
    {16,2,-1,0,0,8,0},drop_entry,drop_key,drop_value
};
static const core_dict_descriptor dictionary = {16,8,2,8,entry_layout.words,NULL,NULL};
static void copy_dictionary(void *work,const void *source,void *target) {
    myl_core_owned_copy_dictionary(work,source,target,copy_leaf,copy_leaf);
}
static void dictionaries(void) {
    myl_block *key=str_from("key",3),*value=str_from("value",5);
    myl_block *source=myl_core_dict_new(2,&dictionary);
    source=myl_core_dict_insert(source,myl_core_dict_find(source,&key,dict_hash(&dictionary,&key)),&key,&value,true);
    myl_block *copy=myl_core_values_copy_generated(copy_dictionary,source);
    myl_block *replacement=str_from("new",3);source=myl_core_dict_set(source,0,&replacement);
    assert(value_drops==1 && key_drops==0);
    source=myl_core_dict_remove(source,0);assert(value_drops==2 && key_drops==1);
    drop(source);drop(copy);assert(dictionary_drops==1 && live_count()==0);
}
static void null_and_static_children(void) {
    static const struct { myl_block header; unsigned char text[5]; } literal = {
        .header={.kind=MYL_KIND_STR|MYL_STATIC_STORAGE,.len=4,.cap=4},.text={'s','t','a','y',0}
    };
    myl_block *value=myl_core_list_new_slow(1,sizeof(record_value));value->len=1;
    value->reserved=(int64_t)(intptr_t)layout;record_value *entry=(record_value *)block_data(value);
    memset(entry,0,sizeof *entry);entry->text=(myl_block *)&literal.header;
    entry->owners[1]=str_from("child",5);entry->choice.value.bits=UINT64_C(0xdeadbeefcafef00d);
    drop(value);assert(record_drops==5 && literal.header.len==4 && live_count()==0);
}
int main(void) {
    aggregate();roots();dictionaries();null_and_static_children();assert(live_count()==0);
    puts("aggregate copies preserve bits and owners; live=0");return 0;
}
