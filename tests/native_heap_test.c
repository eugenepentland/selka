#define _POSIX_C_SOURCE 200809L
#include "native_heap.h"
#include "native_equal.h"
#include "native_bytes.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
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
typedef struct { uint64_t start, end; } Span;
static const myl_native_type u64_type = {
    .size = sizeof(uint64_t), .alignment = _Alignof(uint64_t),
    .kind = MYL_NATIVE_PLAIN, .trace_mode = MYL_NATIVE_TRACE_NONE
};
static const myl_native_field span_fields[] = {
    { .offset = offsetof(Span, start), .type = &u64_type },
    { .offset = offsetof(Span, end), .type = &u64_type }
};
static const myl_native_type span_type = {
    .size = sizeof(Span), .alignment = _Alignof(Span),
    .kind = MYL_NATIVE_RECORD, .fields = span_fields, .field_count = 2,
    .trace_mode = MYL_NATIVE_TRACE_NONE
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
/* Generated descriptors retain every structural field for equality while the
   collector sees only children that can reach managed allocations. */
static void filtered_trace_map_test(void) {
    typedef struct { Span span; Node *node; } Record;
    typedef struct { uint32_t tag; Node *node; } Variant;
    const myl_native_field record_fields[] = {
        { .offset = offsetof(Record, span), .type = &span_type },
        { .offset = offsetof(Record, node), .type = &pointer_type }
    };
    const myl_native_field record_trace[] = {
        { .offset = offsetof(Record, node), .type = &pointer_type }
    };
    const myl_native_type record_type = {
        .size = sizeof(Record), .alignment = _Alignof(Record),
        .kind = MYL_NATIVE_RECORD, .fields = record_fields, .field_count = 2,
        .trace_fields = record_trace, .trace_field_count = 1,
        .trace_mode = MYL_NATIVE_TRACE_FIELDS
    };
    const myl_native_field variant_fields[] = {
        { .offset = offsetof(Variant, node), .type = &pointer_type, .tag = 1 }
    };
    const myl_native_type variant_type = {
        .size = sizeof(Variant), .alignment = _Alignof(Variant),
        .kind = MYL_NATIVE_VARIANT, .fields = variant_fields, .field_count = 1,
        .trace_fields = variant_fields, .trace_field_count = 1,
        .trace_mode = MYL_NATIVE_TRACE_FIELDS
    };
    const myl_native_field pointer_array_field[] = {{ .type = &pointer_type }};
    const myl_native_type pointer_array_type = {
        .size = 2 * sizeof(Node *), .alignment = _Alignof(Node *),
        .kind = MYL_NATIVE_ARRAY, .fields = pointer_array_field, .field_count = 1,
        .count = 2, .stride = sizeof(Node *),
        .trace_fields = pointer_array_field, .trace_field_count = 1,
        .trace_mode = MYL_NATIVE_TRACE_FIELDS
    };
    const myl_native_field span_array_field[] = {{ .type = &span_type }};
    const myl_native_type span_array_type = {
        .size = 2 * sizeof(Span), .alignment = _Alignof(Span),
        .kind = MYL_NATIVE_ARRAY, .fields = span_array_field, .field_count = 1,
        .count = 2, .stride = sizeof(Span), .trace_mode = MYL_NATIVE_TRACE_NONE
    };
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 20);

    Record record = {{3, 8}, myl_native_heap_alloc(&heap, &node_type, 1)};
    Record same = record, different = record;
    assert(record.node);
    record.node->value = 31;
    different.span.end = 9;
    assert(myl_native_equal(&record_type, &record, &same));
    assert(!myl_native_equal(&record_type, &record, &different));
    myl_native_root record_root;
    myl_native_root_push(&heap, &record_root, &record, &record_type);
    assert(myl_native_heap_alloc(&heap, &node_type, 1));
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 1 && record.node->value == 31);
    assert(myl_native_root_pop(&heap, &record_root));

    Variant variant = {0, (Node *)(uintptr_t)1};
    myl_native_root variant_root;
    myl_native_root_push(&heap, &variant_root, &variant, &variant_type);
    myl_native_heap_collect(&heap); /* inactive pointer bits are ignored */
    assert(heap.objects_live == 0);
    variant.tag = 1;
    variant.node = myl_native_heap_alloc(&heap, &node_type, 1);
    assert(variant.node);
    variant.node->value = 47;
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 1 && variant.node->value == 47);
    assert(myl_native_root_pop(&heap, &variant_root));

    Node *nodes[2] = {myl_native_heap_alloc(&heap, &node_type, 1),
                      myl_native_heap_alloc(&heap, &node_type, 1)};
    assert(nodes[0] && nodes[1]);
    nodes[0]->value = 5; nodes[1]->value = 7;
    myl_native_root array_root;
    myl_native_root_push(&heap, &array_root, nodes, &pointer_array_type);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 2 && nodes[0]->value + nodes[1]->value == 12);
    assert(myl_native_root_pop(&heap, &array_root));

    Span spans[2] = {{1, 2}, {3, 4}};
    myl_native_root spans_root;
    myl_native_root_push(&heap, &spans_root, spans, &span_array_type);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 0 && spans[1].end == 4);
    assert(myl_native_root_pop(&heap, &spans_root));
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
    /* The adaptive pause interval may leave a tail allocated after the last
       collection; it must still have reclaimed some of this garbage stream. */
    assert(heap.collections>0 && heap.objects_live<100000);
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
/* A byte view shares a source's octets and keeps their backing block reachable,
   so a view still reads them after the byte string that owned them is collected:
   the view's header traces the block, not the object that first pointed at it.
   The same holds for a frozen literal, whose block is immortal image data. */
static const myl_native_type test_byte_type = { .size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN };
static void byte_view_test(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 20);
    myl_native_root source_root, view_root, inner_root;
    myl_native_bytes *source = myl_native_bytes_new(&heap, (const unsigned char *)"alpha-bravo", 11);
    assert(source);
    myl_native_root_push(&heap, &source_root, &source, &pointer_type);
    heap.stress = 1;
    /* Clamped endpoints: a reversed or out-of-range request is an empty range,
       a negative start counts from the end and an end past the length clamps. */
    myl_native_bytes *empty = myl_native_bytes_view(&heap, source, 9, 2);
    assert(empty && empty->length == 0);
    myl_native_bytes *tail = myl_native_bytes_view(&heap, source, -5, 99);
    assert(tail && tail->length == 5 && !memcmp(tail->storage, "bravo", 5));
    myl_native_bytes *view = myl_native_bytes_view(&heap, source, 6, 11);
    assert(view && view->length == 5 && !memcmp(view->storage, "bravo", 5));
    myl_native_root_push(&heap, &view_root, &view, &pointer_type);
    /* A view of a view reads the same block one range further in. */
    myl_native_bytes *inner = myl_native_bytes_view(&heap, view, 1, 4);
    assert(inner && inner->length == 3 && !memcmp(inner->storage, "rav", 3));
    myl_native_root_push(&heap, &inner_root, &inner, &pointer_type);
    /* Every read path works on a view exactly as it does on a byte string. */
    myl_native_bytes *copy = myl_native_bytes_slice(&heap, view, 0, 5);
    assert(copy && copy->length == 5 && !memcmp(copy->storage, "bravo", 5));
    myl_native_bytes *needle = myl_native_bytes_new(&heap, (const unsigned char *)"rav", 3);
    assert(needle && myl_native_bytes_find(view, needle) == 1);
    myl_native_bytes *prefix = myl_native_bytes_new(&heap, (const unsigned char *)"bra", 3);
    assert(prefix && myl_native_bytes_starts_with(view, prefix));
    assert(!myl_native_bytes_starts_with(prefix, view));
    /* The owning byte string is unreachable now; the view keeps its octets. The
       root still points at the local, which now publishes nothing. */
    source = NULL;
    myl_native_heap_collect(&heap);
    assert(view->length == 5 && !memcmp(view->storage, "bravo", 5));
    assert(inner->length == 3 && !memcmp(inner->storage, "rav", 3));
    assert(myl_native_root_pop(&heap, &inner_root));
    assert(myl_native_root_pop(&heap, &view_root));
    assert(myl_native_root_pop(&heap, &source_root));
    myl_native_heap_destroy(&heap);
}
/* A frozen literal block is immortal image data: a view of one records the
   block, and the collector neither frees nor re-traces it. */
typedef struct {
    myl_native_object header;
    myl_native_list value;
    myl_native_object storage_header;
    unsigned char storage[4];
} frozen_block;
static frozen_block frozen = {
    .header = { .mark = MYL_NATIVE_OBJECT_LITERAL_MARK },
    .value = { .length = 4, .capacity = 4, .element = &test_byte_type, .storage = frozen.storage },
    .storage_header = { .mark = MYL_NATIVE_OBJECT_LITERAL_MARK },
    .storage = { 'f', 'r', 'o', 'z' }
};
static void byte_view_literal_test(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 20);
    heap.stress = 1;
    myl_native_bytes *view = myl_native_bytes_view(&heap, &frozen.value, 1, 3);
    assert(view && view->length == 2 && !memcmp(view->storage, "ro", 2));
    myl_native_root root;
    myl_native_root_push(&heap, &root, &view, &pointer_type);
    myl_native_heap_collect(&heap);
    assert(view->length == 2 && !memcmp(view->storage, "ro", 2));
    assert(myl_native_root_pop(&heap, &root));
    myl_native_heap_destroy(&heap);
}
/* The validating scalar count accepts exactly the sequences the decoder accepts
   and answers the number of scalars, with no decoded intermediate. */
static void byte_scalar_count_test(void) {
    static const struct { const char *bytes; int64_t scalars; } cases[] = {
        { "", 0 },
        { "ascii", 5 },
        { "a\xce\xbb" "b", 3 },
        { "\xf0\x9f\x98\x80", 1 },
        { "\xff", -1 },
        { "\x80", -1 },
        { "\xc0\xaf", -1 },
        { "\xc1\xbf", -1 },
        { "\xed\xa0\x80", -1 },
        { "\xf4\x90\x80\x80", -1 },
        { "\xf5\x80\x80\x80", -1 },
        { "a\xce", -1 },
        { "a\xce" "b", -1 },
        { "\xe2\x82", -1 },
    };
    for (size_t i=0;i<sizeof cases/sizeof cases[0];++i) {
        size_t length = strlen(cases[i].bytes);
        int status = MYL_BYTES_OK;
        myl_native_bytes view = {.length=length,.capacity=length,.element=&test_byte_type,.storage=(void *)cases[i].bytes};
        int64_t scalars = myl_native_bytes_scalar_count_range(&view,0,(int64_t)length,&status);
        int valid = myl_native_text_valid_utf8((const unsigned char *)cases[i].bytes, length) != 0;
        assert(valid == (cases[i].scalars >= 0));
        if (cases[i].scalars >= 0) assert(status == MYL_BYTES_OK && scalars == cases[i].scalars);
        else assert(status == MYL_BYTES_INVALID);
    }
}
int main(void) {
    budget_test();
    guard_test();
    automatic_collection_test();
    byte_view_test();
    byte_view_literal_test();
    byte_scalar_count_test();
    cycle_test();
    array_and_variant_test();
    filtered_trace_map_test();
    long_chain_test();
    puts("native heap tests passed");
}
