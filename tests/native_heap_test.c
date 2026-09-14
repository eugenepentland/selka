#define _POSIX_C_SOURCE 200809L
#include "native_heap.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <sys/resource.h>
typedef struct Node { struct Node *next; int64_t value; } Node;
static const myl_native_type pointer_type = {
    .size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER
};
static const myl_native_field node_fields[] = {{ .offset = offsetof(Node, next), .type = &pointer_type }};
static const myl_native_type node_type = {
    .size = sizeof(Node), .alignment = _Alignof(Node), .kind = MYL_NATIVE_RECORD,
    .fields = node_fields, .field_count = 1
};
static void cycle_test(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 20);
    heap.stress = 1;
    Node *first = myl_native_heap_alloc(&heap, &node_type, 1);
    assert(first);
    myl_native_root root;
    myl_native_root_push(&heap, &root, &first, &pointer_type);
    first->value = 42;
    first->next = myl_native_heap_alloc(&heap, &node_type, 1);
    assert(first->next);
    first->next->next = first;
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 2 && first->next->next->value == 42);
    myl_native_root wrong;
    assert(!myl_native_root_pop(&heap, &wrong));
    assert(myl_native_root_pop(&heap, &root));
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 0 && heap.bytes == 0);
    myl_native_heap_destroy(&heap);
}
static void array_and_variant_test(void) {
    typedef struct { uint32_t tag; Node *value; } Variant;
    const myl_native_field cases[] = {{ .offset = offsetof(Variant, value), .type = &pointer_type, .tag = 1 }};
    const myl_native_type variant = { .size = sizeof(Variant), .alignment = _Alignof(Variant), .fields = cases, .field_count = 1, .kind = MYL_NATIVE_VARIANT };
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 20);
    Variant *items = myl_native_heap_alloc(&heap, &variant, 3);
    myl_native_root root;
    myl_native_root_push(&heap, &root, &items, &pointer_type);
    items[1].tag = 1;
    items[1].value = myl_native_heap_alloc(&heap, &node_type, 1);
    assert(items[1].value);
    items[1].value->value = 17;
    /* The inactive pointer bits must never be interpreted by the collector. */
    items[0].value = (Node *)(uintptr_t)1;
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 2 && items[1].value->value == 17);
    items[1].tag = 0;
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 1);
    assert(!myl_native_heap_alloc(&heap, &variant, SIZE_MAX));
    myl_native_heap_destroy(&heap);
}
static void long_chain_test(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 32 << 20);
    Node *head = NULL;
    myl_native_root root;
    myl_native_root_push(&heap, &root, &head, &pointer_type);
    for (int i = 0; i < 100000; ++i) {
        Node *next = myl_native_heap_alloc(&heap, &node_type, 1);
        assert(next);
        next->next = head;
        head = next;
    }
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 100000);
    assert(myl_native_root_pop(&heap, &root));
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 0);
    myl_native_heap_destroy(&heap);
}
static void automatic_collection_test(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap,SIZE_MAX);
    for (size_t i=0;i<100000;i++) assert(myl_native_heap_alloc(&heap,&node_type,1));
    assert(heap.collections>0 && heap.objects_live<1000);
    myl_native_heap_destroy(&heap);
}
/* A budget refuses growth after a collection and says so, so the caller can
   trap on the budget rather than reporting a host out-of-memory. */
static void budget_test(void) {
    myl_native_heap heap;
    myl_native_root root;
    Node *head = NULL;
    size_t bytes = 0;
    size_t held = 0;
    myl_native_heap_init(&heap, 64 * 1024);
    myl_native_root_push(&heap, &root, &head, &pointer_type);
    for (;;) {
        Node *next = myl_native_heap_alloc(&heap, &node_type, 1);
        if (!next) break;
        next->next = head;
        head = next;
        held++;
    }
    assert(held > 0 && heap.exhausted && heap.bytes <= heap.limit);
    assert(myl_native_root_pop(&heap, &root));
    myl_native_heap_destroy(&heap);
    assert(myl_native_budget_parse("1024", &bytes) && bytes == 1024);
    assert(myl_native_budget_parse("4M", &bytes) && bytes == (((size_t)4) << 20));
    assert(myl_native_budget_parse("2g", &bytes) && bytes == (((size_t)2) << 30));
    assert(myl_native_budget_parse("8k", &bytes) && bytes == 8192);
    assert(myl_native_budget_parse("0", &bytes) && bytes == 0);
    assert(!myl_native_budget_parse("", &bytes));
    assert(!myl_native_budget_parse("M", &bytes));
    assert(!myl_native_budget_parse("12x", &bytes));
    assert(!myl_native_budget_parse("1MM", &bytes));
    assert(!myl_native_budget_parse("-4", &bytes));
}
/* The kernel backstop is installed at the budget plus headroom and never
   loosens a tighter ceiling. A sanitizer build declines it, because its shadow
   mapping reserves more address space than any budget would allow. */
static void guard_test(void) {
    struct rlimit ceiling;
    size_t budget = ((size_t)1) << 40;
    int applied = myl_native_budget_guard(budget);
    assert(!myl_native_budget_guard(0));
    assert(!getrlimit(RLIMIT_AS, &ceiling));
    if (applied) assert(ceiling.rlim_cur == (rlim_t)(budget + MYL_NATIVE_BUDGET_HEADROOM));
    /* Twice the budget must not raise the ceiling the first call installed. */
    assert(!myl_native_budget_guard(budget * 2));
}
int main(void) {
    budget_test();
    guard_test();
    automatic_collection_test();
    cycle_test();
    array_and_variant_test();
    long_chain_test();
    puts("native heap tests passed");
}
