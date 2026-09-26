#include "native_equal.h"
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
/* The pending comparisons live on the heap and grow with the values, so a
 * list of any length or a recursive value of any depth compares without host
 * recursion (RECURSIVE-VALUES-3); only running out of memory stops it. */
typedef struct { const myl_native_type *type; const void *left,*right; } Pair;
typedef struct { Pair *items; size_t length,capacity; Pair *seen; size_t seen_count,seen_capacity; } Work;
static int push(Work *work, const myl_native_type *type, const void *left, const void *right) {
    if (work->length==work->capacity) {
        size_t capacity=work->capacity?work->capacity*2:32;
        if (capacity>SIZE_MAX/sizeof(Pair)) return -1;
        Pair *items=realloc(work->items,capacity*sizeof(Pair));
        if (!items) return -1;
        work->items=items; work->capacity=capacity;
    }
    work->items[work->length++]=(Pair){type,left,right};
    return 1;
}
static size_t hash(Pair pair) {
    uintptr_t value=((uintptr_t)pair.left>>3)^((uintptr_t)pair.right<<7)^((uintptr_t)pair.type>>4);
    value^=value>>17; value*=UINT64_C(0x9e3779b97f4a7c15); value^=value>>23;
    return (size_t)value;
}
/* 1 newly visited, 0 visited already, negative failure. */
static int visit(Work *work, Pair pair) {
    if (!work->seen_capacity || work->seen_count>=work->seen_capacity/2) {
        size_t capacity=work->seen_capacity?work->seen_capacity*2:64;
        Pair *seen=calloc(capacity,sizeof(Pair));
        if (!seen) return -1;
        for (size_t i=0;i<work->seen_capacity;i++) if (work->seen[i].type) {
            size_t at=hash(work->seen[i])&(capacity-1);
            while (seen[at].type) at=(at+1)&(capacity-1);
            seen[at]=work->seen[i];
        }
        free(work->seen); work->seen=seen; work->seen_capacity=capacity;
    }
    size_t at=hash(pair)&(work->seen_capacity-1);
    while (work->seen[at].type) {
        Pair prior=work->seen[at];
        if (prior.type==pair.type && prior.left==pair.left && prior.right==pair.right) return 0;
        at=(at+1)&(work->seen_capacity-1);
    }
    work->seen[at]=pair; work->seen_count++;
    return 1;
}
static int managed(Work *work,Pair pair) {
    const void *left,*right;
    memcpy(&left,pair.left,sizeof(left)); memcpy(&right,pair.right,sizeof(right));
    if (!left || !right) return left==right;
    /* A box (RECURSIVE-VALUES-2) compares the value it holds, even against
     * itself, so a NaN inside one is unequal exactly as it is inline. Each pair
     * of boxes is compared once, so values that share subtrees compare in time
     * proportional to their distinct box pairs rather than their paths. */
    Pair identity={pair.type,left,right};
    int visited=visit(work,identity);
    if (visited<=0) return visited<0?visited:1;
    if (pair.type->collection_kind==5) return push(work,pair.type->element,left,right);
    if (pair.type->collection_kind==3) {
        const myl_native_dictionary *a=left,*b=right;
        if (myl_native_dictionary_length(a)!=myl_native_dictionary_length(b)) return 0;
        /* Every key of one side is looked up in the other's table, hashing and
         * comparing it structurally (HASH-KEYS-1), so equality ignores
         * insertion order and costs one expected-constant probe per entry. */
        myl_native_dictionary_settle(a);
        for (size_t i=0;i<a->entries->length;i++) {
            const unsigned char *entry=(const unsigned char *)a->entries->storage+i*a->entry_type.size;
            const void *other=myl_native_dictionary_find(b,entry);
            if (!other) return 0;
            int status=push(work,pair.type->element,entry+a->value_offset,other);
            if (status<0) return status;
        }
        return 1;
    }
    if (!pair.type->collection_kind) return left==right;
    if (pair.type->collection_kind==2) return myl_native_text_equal(left,right);
    const myl_native_list *a=left,*b=right;
    if (a->length!=b->length) return 0;
    /* 4 is an immutable byte string; its elements compare exactly like a list of u8. */
    if (pair.type->collection_kind!=1&&pair.type->collection_kind!=4) return left==right;
    for (size_t i=0;i<a->length;i++) {
        int status=push(work,pair.type->element,(const unsigned char *)a->storage+i*a->element->size,(const unsigned char *)b->storage+i*b->element->size);
        if (status<0) return status;
    }
    return 1;
}
static int compare(Work *work,Pair pair) {
    const myl_native_type *type=pair.type;
    if (type->kind==MYL_NATIVE_POINTER) return managed(work,pair);
    if (type->kind==MYL_NATIVE_FLOAT) {
        double a,b;
        memcpy(&a,pair.left,sizeof(a)); memcpy(&b,pair.right,sizeof(b));
        return a==b;
    }
    const unsigned char *a=pair.left,*b=pair.right;
    if (type->kind==MYL_NATIVE_ARRAY) {
        for (size_t i=0;i<type->count;i++) {
            int status=push(work,type->fields[0].type,a+i*type->stride,b+i*type->stride);
            if (status<0) return status;
        }
        return 1;
    }
    if (type->kind==MYL_NATIVE_RECORD || type->kind==MYL_NATIVE_VARIANT) {
        uint32_t tag=0;
        if (type->kind==MYL_NATIVE_VARIANT) {
            uint32_t other;
            memcpy(&tag,a,4); memcpy(&other,b,4);
            if (tag!=other) return 0;
        }
        for (size_t i=0;i<type->field_count;i++) {
            const myl_native_field *field=&type->fields[i];
            if (type->kind==MYL_NATIVE_VARIANT && field->tag!=tag) continue;
            int status=push(work,field->type,a+field->offset,b+field->offset);
            if (status<0) return status;
        }
        return 1;
    }
    return !memcmp(a,b,type->size);
}
int myl_native_equal(const myl_native_type *type,const void *left,const void *right) {
    Work work={0};
    int status=push(&work,type,left,right);
    while (status>0 && work.length) {
        Pair pair=work.items[--work.length];
        status=compare(&work,pair);
    }
    free(work.items); free(work.seen);
    return status;
}
int myl_native_list_contains(const myl_native_list *list,const myl_native_type *element,const void *needle) {
    for (size_t i=0;i<list->length;i++) {
        int result=myl_native_equal(element,(const unsigned char *)list->storage+i*element->size,needle);
        if (result!=0) return result;
    }
    return 0;
}
