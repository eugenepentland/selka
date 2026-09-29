/* spec-case: EQUALITY-SCRATCH-1. Count only equality's scratch allocations:
 * fixture storage and the rest of the runtime use their ordinary allocator. */
#include "native_equal.h"
#include "native_memory.h"
#define myl_native_equal allocation_equal
#define myl_native_list_contains allocation_contains
#include "../src/native_equal.c"
#undef myl_native_equal
#undef myl_native_list_contains
#include <assert.h>
#include <math.h>

static const myl_native_type integer={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type octet={.size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type floating={.size=8,.alignment=8,.kind=MYL_NATIVE_FLOAT};
static const myl_native_type text={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=2};
static const myl_native_type bytes={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=4,.element=&octet};
static const myl_native_type float_box={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=5,.element=&floating};
static const myl_native_type floats={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=1,.element=&floating};
static const myl_native_type recursive={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=1,.element=&recursive};

static void allocation_free_values(void) {
    size_t before=test_attempts;
    int64_t one=1,two=2;
    assert(allocation_equal(&integer,&one,&one)==1);
    assert(allocation_equal(&integer,&one,&two)==0);
    double a=-0.0,b=0.0,nan=NAN;
    assert(allocation_equal(&floating,&a,&b)==1);
    assert(allocation_equal(&floating,&nan,&nan)==0);
    const double *box=&nan;
    assert(allocation_equal(&float_box,&box,&box)==0);
    box=&a;
    const double *other=&b;
    assert(allocation_equal(&float_box,&box,&other)==1);

    struct { myl_native_text header; unsigned char payload[32]; } owned={
        .header={.length=16,.bytes=16,.flags=MYL_TEXT_ASCII},.payload="0123456789abcdef"};
    struct { myl_native_text header; unsigned char payload[32]; } copy={
        .header={.length=12,.bytes=12,.flags=MYL_TEXT_ASCII},.payload="23456789abcd"};
    myl_native_text_view view={.text={.length=12,.bytes=12,.flags=MYL_TEXT_ASCII|MYL_TEXT_VIEW,.hash=2},.owner=&owned.header};
    const myl_native_text *x=&view.text,*y=&copy.header;
    assert(allocation_equal(&text,&x,&y)==1);
    copy.payload[8]='X';
    assert(allocation_equal(&text,&x,&y)==0);

    unsigned char source[]={0,1,2,3,4,5},equal[]={1,2,3,4};
    myl_native_list slice={.length=4,.element=&octet,.storage=source+1};
    myl_native_list independent={.length=4,.element=&octet,.storage=equal};
    const myl_native_list *left=&slice,*right=&independent;
    assert(allocation_equal(&bytes,&left,&right)==1);
    equal[3]=5;
    assert(allocation_equal(&bytes,&left,&right)==0);
    myl_native_list empty={.element=&octet};
    left=right=&empty;
    assert(allocation_equal(&bytes,&left,&right)==1);

    double values[]={1.0,-0.0,3.0},same[]={1.0,0.0,3.0};
    myl_native_list first={.length=3,.element=&floating,.storage=values};
    myl_native_list second={.length=3,.element=&floating,.storage=same};
    left=&first; right=&second;
    assert(allocation_equal(&floats,&left,&right)==1);
    assert(allocation_contains(&first,&floating,&a)==1);
    values[2]=NAN;
    assert(allocation_equal(&floats,&left,&left)==0);

    myl_native_list cycle_a={.length=1,.element=&recursive};
    myl_native_list cycle_b={.length=1,.element=&recursive};
    left=&cycle_a; right=&cycle_b;
    cycle_a.storage=&left; cycle_b.storage=&right;
    assert(allocation_equal(&recursive,&left,&right)==1);
    assert(test_attempts==before && test_live==0);
}

typedef struct Node { struct Node *next; double value; } Node;
static const myl_native_type node;
static const myl_native_type node_box={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=5,.element=&node};
static const myl_native_field node_fields[]={
    {.offset=offsetof(Node,next),.type=&node_box},
    {.offset=offsetof(Node,value),.type=&floating},
};
static const myl_native_type node={.size=sizeof(Node),.alignment=_Alignof(Node),.kind=MYL_NATIVE_RECORD,.fields=node_fields,.field_count=2};

/* Neither broad composites nor deep cycles acquire a fixed work limit. Every
 * real growth allocation can fail; prior buffers must be freed on that path. */
static void fault_paths(const myl_native_type *type,const void *left,const void *right) {
    test_attempts=0; test_fail_at=0;
    assert(allocation_equal(type,left,right)==1 && test_live==0);
    size_t attempts=test_attempts;
    assert(attempts>0);
    for (size_t fail=1;fail<=attempts;fail++) {
        test_attempts=0; test_fail_at=fail;
        assert(allocation_equal(type,left,right)==-1);
        assert(test_live==0);
    }
    test_fail_at=0;
    assert(allocation_equal(type,left,right)==1 && test_live==0);
}
static void growing_worklists(void) {
    enum { COUNT=1024 };
    Node a[COUNT],b[COUNT];
    for (size_t i=0;i<COUNT;i++) {
        a[i]=(Node){.next=&a[(i+1)%COUNT],.value=(double)i};
        b[i]=(Node){.next=&b[(i+1)%COUNT],.value=(double)i};
    }
    const Node *left=a,*right=b;
    fault_paths(&node_box,&left,&right);
    b[COUNT/2].value=NAN;
    assert(allocation_equal(&node_box,&left,&right)==0 && test_live==0);
    b[COUNT/2].value=(double)(COUNT/2);

    const myl_native_field field={.type=&node};
    const myl_native_type wide={.size=sizeof(a),.alignment=_Alignof(Node),.kind=MYL_NATIVE_ARRAY,
        .fields=&field,.field_count=1,.count=COUNT,.stride=sizeof(Node)};
    fault_paths(&wide,a,b);
    /* All paths into a shared DAG still compare its distinct box pair once. */
    for (size_t i=0;i<COUNT;i++) { a[i].next=a; b[i].next=b; }
    assert(allocation_equal(&wide,a,b)==1 && test_live==0);
    b[0].value=NAN;
    assert(allocation_equal(&wide,a,b)==0 && test_live==0);
}
int main(void) {
    allocation_free_values();
    growing_worklists();
    puts("native equality scratch allocation tests passed");
}
