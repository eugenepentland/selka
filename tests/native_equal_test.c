#include "native_equal.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static const myl_native_type integer={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type floating={.size=8,.alignment=8,.kind=MYL_NATIVE_FLOAT};
static const myl_native_type list_integer={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=1,.element=&integer};
static const myl_native_type list_float={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=1,.element=&floating};
static const myl_native_type recursive={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=1,.element=&recursive};
static const myl_native_type dict_integer={.size=8,.alignment=8,.kind=MYL_NATIVE_POINTER,.collection_kind=3,.element=&integer,.key=&integer};
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,1<<24); heap.stress=1;
    myl_native_root roots[4];
    myl_native_list *a=myl_native_list_new(&heap,&integer,0); assert(a);
    myl_native_root_push(&heap,&roots[0],&a,&list_integer);
    myl_native_list *b=myl_native_list_new(&heap,&integer,0); assert(b);
    myl_native_root_push(&heap,&roots[1],&b,&list_integer);
    int64_t one=1,two=2;
    assert(myl_native_list_append(&heap,a,&one)); assert(myl_native_list_append(&heap,b,&one));
    assert(myl_native_equal(&list_integer,&a,&b)==1);
    assert(myl_native_list_contains(a,&integer,&one)==1);
    assert(myl_native_list_contains(a,&integer,&two)==0);
    assert(myl_native_list_append(&heap,b,&two)); assert(myl_native_equal(&list_integer,&a,&b)==0);
    myl_native_heap_destroy(&heap);
    myl_native_heap_init(&heap,1<<24); heap.stress=1;
    a=myl_native_list_new(&heap,&recursive,0); assert(a);
    myl_native_root_push(&heap,&roots[0],&a,&recursive);
    b=myl_native_list_new(&heap,&recursive,0); assert(b);
    myl_native_root_push(&heap,&roots[1],&b,&recursive);
    assert(myl_native_list_append(&heap,a,&a)); assert(myl_native_list_append(&heap,b,&b));
    assert(myl_native_equal(&recursive,&a,&b)==1);
    myl_native_heap_destroy(&heap);
    myl_native_heap_init(&heap,1<<24); heap.stress=1;
    a=myl_native_list_new(&heap,&floating,0); assert(a);
    myl_native_root_push(&heap,&roots[0],&a,&list_float);
    double value=NAN;
    assert(myl_native_list_append(&heap,a,&value)); assert(myl_native_equal(&list_float,&a,&a)==0);
    value=-0.0; assert(myl_native_list_set(a,0,&value));
    b=myl_native_list_new(&heap,&floating,0); assert(b);
    myl_native_root_push(&heap,&roots[1],&b,&list_float);
    value=0.0; assert(myl_native_list_append(&heap,b,&value)); assert(myl_native_equal(&list_float,&a,&b)==1);
    myl_native_dictionary *x=myl_native_dictionary_new(&heap,&integer,&integer,0); assert(x);
    myl_native_root_push(&heap,&roots[2],&x,&dict_integer);
    myl_native_dictionary *y=myl_native_dictionary_new(&heap,&integer,&integer,0); assert(y);
    myl_native_root_push(&heap,&roots[3],&y,&dict_integer);
    assert(myl_native_dictionary_write(&heap,x,&one,&two)); assert(myl_native_dictionary_write(&heap,x,&two,&one));
    assert(myl_native_dictionary_write(&heap,y,&two,&one)); assert(myl_native_dictionary_write(&heap,y,&one,&two));
    assert(myl_native_equal(&dict_integer,&x,&y)==1);
    assert(myl_native_dictionary_write(&heap,y,&one,&one)); assert(myl_native_equal(&dict_integer,&x,&y)==0);
    myl_native_heap_destroy(&heap);
    const myl_native_type unit={.size=0,.alignment=1,.kind=MYL_NATIVE_PLAIN};
    const myl_native_field field={.offset=0,.type=&unit};
    const myl_native_type huge={.size=0,.alignment=1,.kind=MYL_NATIVE_ARRAY,.count=100001,.stride=0,.fields=&field,.field_count=1};
    /* spec-case: RECURSIVE-VALUES-3 — a large value no longer hits a fixed work limit. */
    assert(myl_native_equal(&huge,&one,&two)==1);
    puts("native structural equality tests passed");
}
