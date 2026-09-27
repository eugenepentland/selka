/* Evidence for the RC runtime's internal fast paths: probe-based metadata,
 * conditional (variant) flat plans, immediate retirement of edge-free objects,
 * recycled scope journal nodes and the allocator's heap-wide teardown API. */
#include "native_rc_alloc.h"
#include "native_rc_internal.h"
#include "native_rc_values.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
static const myl_native_type pointer = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_POINTER};
static const myl_rc_shape owned = {.size = 8, .kind = MYL_RC_SHAPE_POINTER};
static const myl_rc_shape scalar = {.size = 8, .kind = MYL_RC_SHAPE_NONE};

/* Arm 0: {ptr@0, int@8}; arm 1: {int@0, ptr@8}; arm 2: ptr; arm 3: int. The
 * variant's tag is at 0 and every payload starts at 8, so arm 0's pointer and
 * arm 1's integer share bytes 8..15. */
static const myl_native_field first_fields[] = {{.type = &pointer}, {.offset = 8, .type = &number}};
static const myl_native_type first = {.size = 16, .alignment = 8, .kind = MYL_NATIVE_RECORD, .fields = first_fields, .field_count = 2};
static const myl_native_field second_fields[] = {{.type = &number}, {.offset = 8, .type = &pointer}};
static const myl_native_type second = {.size = 16, .alignment = 8, .kind = MYL_NATIVE_RECORD, .fields = second_fields, .field_count = 2};
static const myl_native_field arm_fields[] = {
    {.offset = 8, .type = &first, .tag = 0}, {.offset = 8, .type = &second, .tag = 1},
    {.offset = 8, .type = &pointer, .tag = 2}, {.offset = 8, .type = &number, .tag = 3}};
static const myl_native_type choice = {.size = 24, .alignment = 8, .kind = MYL_NATIVE_VARIANT, .fields = arm_fields, .field_count = 4};
static const myl_rc_field first_edges[] = {{.shape = &owned}, {.offset = 8, .shape = &scalar}};
static const myl_rc_shape first_shape = {.size = 16, .kind = MYL_RC_SHAPE_RECORD, .as.record = {first_edges, 2}};
static const myl_rc_field second_edges[] = {{.shape = &scalar}, {.offset = 8, .shape = &owned}};
static const myl_rc_shape second_shape = {.size = 16, .kind = MYL_RC_SHAPE_RECORD, .as.record = {second_edges, 2}};
static const myl_rc_field arm_edges[] = {
    {.offset = 8, .shape = &first_shape, .tag = 0}, {.offset = 8, .shape = &second_shape, .tag = 1},
    {.offset = 8, .shape = &owned, .tag = 2}, {.offset = 8, .shape = &scalar, .tag = 3}};
static const myl_rc_shape choice_shape = {.size = 24, .kind = MYL_RC_SHAPE_VARIANT, .as.variant = {arm_edges, 4, 0}};
/* A record holding the variant between two unconditional pointers. */
static const myl_native_field outer_fields[] = {{.type = &pointer}, {.offset = 8, .type = &choice}, {.offset = 32, .type = &pointer}};
static const myl_native_type outer = {.size = 40, .alignment = 8, .kind = MYL_NATIVE_RECORD, .fields = outer_fields, .field_count = 3};
static const myl_rc_field outer_edges[] = {{.shape = &owned}, {.offset = 8, .shape = &choice_shape}, {.offset = 32, .shape = &owned}};
static const myl_rc_shape outer_shape = {.size = 40, .kind = MYL_RC_SHAPE_RECORD, .as.record = {outer_edges, 3}};
static const myl_rc_descriptor descriptors[] = {
    {.type = &pointer, .shape = &owned}, {.type = &choice, .shape = &choice_shape}, {.type = &outer, .shape = &outer_shape}};
static const myl_rc_module module = {.abi = MYL_RC_ABI_VERSION, .descriptors = descriptors, .descriptor_count = 3};

typedef struct { uint64_t tag; void *a; void *b; } Choice;
typedef struct { void *left; Choice middle; void *right; } Outer;

static void start(myl_native_heap *heap) {
    myl_native_heap_init(heap, 64u << 20);
    if (!myl_rc_enabled(heap)) assert(myl_rc_storage_init(heap) == MYL_RC_OK);
    assert(myl_rc_module_register(heap, &module) == MYL_RC_OK);
}
static void finish(myl_native_heap *heap) {
    assert(!heap->objects_live);
    myl_native_heap_destroy(heap);
    assert(!heap->bytes);
}
static myl_rc_object *header(void *payload) { return (myl_rc_object *)payload - 1; }
static void *bytes8(myl_native_heap *heap) {
    void *payload = myl_rc_storage_bytes(heap, 8, 0);
    assert(payload);
    return payload;
}
static const myl_rc_flat *plan(myl_native_heap *heap, const myl_native_type *type) {
    const myl_rc_binding *binding = myl_rc_binding_find(heap, type);
    assert(binding);
    return &binding->flat;
}

// spec: RC-FLAT-VARIANT-1
static void variant_plan_layout(void) {
    myl_native_heap heap;
    start(&heap);
    const myl_rc_flat *flat = plan(&heap, &choice);
    assert(flat->count == 3 && flat->conditional && flat->loanable && flat->arm_offset == 0);
    assert(flat->offsets[0] == 8 && flat->offsets[1] == 16 && flat->offsets[2] == 8);
    assert(flat->arms[0] == 1 && flat->arms[1] == 2 && flat->arms[2] == 4 && flat->arms[3] == 0 && flat->always == 0);
    Choice value = {.tag = 1, .a = (void *)(uintptr_t)77, .b = NULL};
    assert(myl_rc_flat_live(flat, (const unsigned char *)&value) == 2);
    value.tag = 40;
    assert(myl_rc_flat_live(flat, (const unsigned char *)&value) == 0);
    /* Unconditional leaves stay live around the variant, in walker order. */
    const myl_rc_flat *wide = plan(&heap, &outer);
    assert(wide->count == 5 && wide->conditional && wide->arm_offset == 8 && wide->always == 0x11);
    assert(wide->offsets[0] == 0 && wide->offsets[1] == 16 && wide->offsets[2] == 24 && wide->offsets[3] == 16 && wide->offsets[4] == 32);
    assert(wide->arms[0] == 0x13 && wide->arms[1] == 0x15 && wide->arms[2] == 0x19 && wide->arms[3] == 0x11);
    finish(&heap);
}
// spec-case: RC-FLAT-VARIANT-1
static void variant_plan_operations(void) {
    myl_native_heap heap;
    start(&heap);
    for (uint64_t tag = 0; tag < 4; ++tag) {
        void *child = bytes8(&heap), *other = bytes8(&heap);
        Choice value = {.tag = tag};
        /* Arm 1's integer overlaps arm 0's pointer; arm 3 keeps a raw word. */
        if (tag == 0) value.a = child, value.b = (void *)(uintptr_t)5;
        if (tag == 1) value.a = (void *)(uintptr_t)6, value.b = child;
        if (tag == 2) value.a = child;
        if (tag == 3) value.a = (void *)(uintptr_t)0xdeadbeef;
        size_t expected = tag == 3 ? 1 : 2;
        Choice copy = {0}, loan = {0}, taken = {0};
        assert(myl_rc_native_copy(&heap, &choice, &copy, &value, 0));
        assert(!memcmp(&copy, &value, sizeof copy) && header(child)->owners == expected);
        assert(myl_rc_native_loan(&heap, &choice, &loan, &value));
        assert(!memcmp(&loan, &value, sizeof loan) && header(child)->holds == expected - 1);
        myl_rc_native_unloan(&heap, &choice, &loan);
        Choice empty = {0};
        assert(!memcmp(&loan, &empty, sizeof loan) && !header(child)->holds);
        assert(myl_rc_native_take(&heap, &choice, &taken, &copy, 0));
        assert(!memcmp(&copy, &empty, sizeof copy) && header(child)->owners == expected);
        assert(myl_rc_native_retain_replace(&heap, &choice, &taken, &value, 0));
        assert(header(child)->owners == expected);
        myl_rc_native_drop(&heap, &choice, &taken);
        assert(!memcmp(&taken, &empty, sizeof taken) && header(child)->owners == 1);
        /* A heap body with one element dies through the conditional plan. */
        Outer *body = myl_native_heap_alloc(&heap, &outer, 1);
        assert(body);
        body->left = other;
        assert(myl_rc_owner_acquire(&heap, other) == MYL_RC_OK);
        assert(myl_rc_native_retain(&heap, &choice, &body->middle, &value, 0));
        size_t live = heap.objects_live;
        myl_rc_owner_release(&heap, body);
        assert(heap.objects_live == live - 1 && header(other)->owners == 1 && header(child)->owners == 1);
        assert(!heap.rc->dead.head);
        myl_rc_owner_release(&heap, child);
        myl_rc_owner_release(&heap, other);
    }
    finish(&heap);
}
// spec-case: RC-FLAT-VARIANT-1
static void variant_plan_refusals(void) {
    /* A live variant nested inside an arm keeps the generic walker. */
    static const myl_native_field nest_fields[] = {{.offset = 8, .type = &choice, .tag = 0}, {.offset = 8, .type = &number, .tag = 1}};
    static const myl_native_type nest = {.size = 32, .alignment = 8, .kind = MYL_NATIVE_VARIANT, .fields = nest_fields, .field_count = 2};
    static const myl_rc_field nest_edges[] = {{.offset = 8, .shape = &choice_shape, .tag = 0}, {.offset = 8, .shape = &scalar, .tag = 1}};
    static const myl_rc_shape nest_shape = {.size = 32, .kind = MYL_RC_SHAPE_VARIANT, .as.variant = {nest_edges, 2, 0}};
    /* A tag word inside a pointer word can never be read safely after a clear. */
    static const myl_native_field clash_fields[] = {{.offset = 0, .type = &pointer, .tag = 0}};
    static const myl_native_type clash = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_VARIANT, .fields = clash_fields, .field_count = 1};
    static const myl_rc_field clash_edges[] = {{.offset = 0, .shape = &owned, .tag = 0}};
    static const myl_rc_shape clash_shape = {.size = 8, .kind = MYL_RC_SHAPE_VARIANT, .as.variant = {clash_edges, 1, 0}};
    myl_native_heap heap;
    start(&heap);
    const myl_rc_descriptor nested = {.type = &nest, .shape = &nest_shape}, clashing = {.type = &clash, .shape = &clash_shape};
    assert(myl_rc_descriptor_import(&heap, &nested) == MYL_RC_OK);
    assert(myl_rc_descriptor_import(&heap, &clashing) == MYL_RC_OK);
    assert(plan(&heap, &nest)->count > MYL_RC_FLAT_LEAVES && plan(&heap, &clash)->count > MYL_RC_FLAT_LEAVES);
    /* The generic walker still handles the nested value. */
    void *child = bytes8(&heap);
    struct { uint64_t tag; Choice inner; } value = {.tag = 0, .inner = {.tag = 2, .a = child}}, copy = {0};
    assert(myl_rc_native_copy(&heap, &nest, &copy, &value, 0) && header(child)->owners == 2);
    myl_rc_native_drop(&heap, &nest, &copy);
    assert(header(child)->owners == 1);
    myl_rc_owner_release(&heap, child);
    finish(&heap);
}
// spec: RC-METADATA-MAP-1
static void metadata_maps(void) {
    static myl_native_type types[300];
    static const myl_rc_shape *const source_shapes[] = {&owned};
    static const myl_rc_module shapes_only = {.abi = MYL_RC_ABI_VERSION, .shapes = source_shapes, .shape_count = 1};
    myl_native_heap heap;
    start(&heap);
    const myl_rc_shape *registered = myl_rc_shape_resolve(&heap, &owned);
    assert(registered && registered != &owned && myl_rc_shape_resolve(&heap, registered) == registered);
    assert(myl_rc_shape_find(&heap, &owned) == registered && !myl_rc_shape_resolve(&heap, NULL));
    size_t bytes = heap.bytes;
    assert(myl_rc_module_register(&heap, &module) == MYL_RC_OK && myl_rc_module_register(&heap, &shapes_only) == MYL_RC_OK);
    assert(myl_rc_module_register(&heap, &shapes_only) == MYL_RC_OK);
    size_t stable = heap.bytes;
    assert(stable > bytes && myl_rc_module_register(&heap, &module) == MYL_RC_OK && heap.bytes == stable);
    for (size_t i = 0; i < 300; ++i) {
        types[i] = number;
        const myl_rc_descriptor descriptor = {.type = &types[i], .shape = &scalar};
        assert(myl_rc_descriptor_import(&heap, &descriptor) == MYL_RC_OK);
    }
    assert(heap.rc->metadata.bindings.count >= 300 && heap.rc->metadata.bindings.count <= (heap.rc->metadata.bindings.mask + 1) / 2);
    for (size_t i = 0; i < 300; ++i) {
        const myl_rc_binding *binding = myl_rc_binding_find(&heap, &types[i]);
        assert(binding && binding->descriptor.type == &types[i] && &binding->descriptor == myl_rc_descriptor_find(&heap, &types[i]));
        assert(myl_rc_descriptor_of(&heap, &types[i]) == &binding->descriptor && !binding->flat.count);
    }
    /* A refused registration leaves every map and charge unchanged. */
    static myl_native_type refused = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
    const myl_rc_map before = heap.rc->metadata.bindings;
    size_t charged = heap.bytes;
    heap.limit = heap.bytes;
    const myl_rc_descriptor descriptor = {.type = &refused, .shape = &scalar};
    assert(myl_rc_descriptor_import(&heap, &descriptor) == MYL_RC_ALLOCATION_REFUSED);
    assert(heap.bytes == charged && heap.rc->metadata.bindings.entries == before.entries);
    assert(heap.rc->metadata.bindings.count == before.count && !myl_rc_binding_find(&heap, &refused));
    heap.limit = 64u << 20;
    heap.exhausted = 0;
    finish(&heap);
}
// spec: RC-LEAF-RETIRE-1
static void edge_free_objects_retire_at_once(void) {
    myl_native_heap heap;
    start(&heap);
    myl_rc_counters counters;
    void *leaf = bytes8(&heap);
    assert(myl_rc_stats_snapshot(&heap, &counters));
    uint64_t retired = counters.events[MYL_RC_STAT_RETIRE];
    size_t live = heap.objects_live;
    /* Outside a drain an edge-free death never enters the queue. */
    myl_rc_edge_release(&heap, leaf);
    assert(!heap.rc->dead.head && heap.objects_live == live - 1);
    assert(myl_rc_stats_snapshot(&heap, &counters) && counters.events[MYL_RC_STAT_RETIRE] == retired + 1);
    /* An object with edges still queues, and its edge-free children queue
     * behind it inside the active drain. */
    Outer *body = myl_native_heap_alloc(&heap, &outer, 1);
    assert(body);
    body->left = bytes8(&heap);
    body->right = bytes8(&heap);
    live = heap.objects_live;
    myl_rc_edge_release(&heap, body);
    assert(heap.rc->dead.head == header(body) && heap.objects_live == live);
    myl_rc_drain(&heap);
    assert(!heap.rc->dead.head && heap.objects_live == live - 3);
    finish(&heap);
}
static void count_visit(myl_native_heap *heap, void *payload, void *context) {
    (void)heap;
    size_t *seen = context;
    assert(!(((myl_native_object *)payload - 1)->mark & MYL_NATIVE_OBJECT_ARENA));
    ++*seen;
}
// spec: RC-STORAGE-TEARDOWN-1
static void storage_visit_and_release_all(void) {
    myl_native_heap heap;
    start(&heap);
    size_t baseline = 0;
    myl_rc_storage_visit(&heap, count_visit, &baseline);
    enum { count = 5000 };
    static void *values[count];
    for (size_t i = 0; i < count; ++i) values[i] = bytes8(&heap);
    void *large = myl_rc_storage_bytes(&heap, 100000, 0);
    assert(large);
    /* Retired slots are not visited; queued deaths are. */
    for (size_t i = 0; i < count; i += 2) myl_rc_owner_release(&heap, values[i]);
    Outer *body = myl_native_heap_alloc(&heap, &outer, 1);
    assert(body);
    myl_rc_edge_release(&heap, body);
    assert(heap.rc->dead.head == header(body));
    size_t seen = 0;
    myl_rc_storage_visit(&heap, count_visit, &seen);
    assert(seen == baseline + count / 2 + 2);
    size_t objects = heap.objects_live, reserved = myl_rc_storage_reserved(&heap);
    assert(reserved > 100000);
    myl_rc_storage_release_all(&heap);
    assert(!heap.rc->dead.head && heap.objects_live == objects - (seen - baseline) - baseline);
    seen = 0;
    myl_rc_storage_visit(&heap, count_visit, &seen);
    assert(!seen && myl_rc_storage_reserved(&heap) < reserved);
    /* The heap stays usable: metadata survives and new objects allocate. */
    void *again = myl_native_heap_alloc(&heap, &outer, 1);
    assert(again && myl_rc_binding_find(&heap, &outer));
    myl_rc_owner_release(&heap, again);
    finish(&heap);
}
// spec: RC-SCOPE-SPARE-1
static void scope_journal_nodes_recycle(void) {
    myl_native_heap heap;
    start(&heap);
    void *values[4];
    for (size_t i = 0; i < 4; ++i) values[i] = bytes8(&heap);
    size_t bytes = heap.bytes, metadata = myl_rc_metadata_bytes(&heap);
    for (unsigned round = 0; round < 3; ++round) {
        myl_rc_scope scope;
        myl_rc_scope_begin(&heap, &scope);
        for (size_t i = 0; i < 4; ++i) assert(myl_rc_scope_pin(&scope, values[i]) == MYL_RC_OK);
        assert(heap.bytes > bytes && header(values[3])->holds == 1);
        myl_rc_scope_end(&scope);
        /* Released nodes are uncharged while spare and reused next round. */
        assert(heap.bytes == bytes && myl_rc_metadata_bytes(&heap) == metadata && heap.rc->spare.count == 4);
    }
    /* A spare node repeats the budget admission of a fresh allocation. */
    myl_rc_scope scope;
    myl_rc_scope_begin(&heap, &scope);
    heap.limit = heap.bytes;
    assert(myl_rc_scope_pin(&scope, values[0]) == MYL_RC_ALLOCATION_REFUSED);
    assert(heap.bytes == bytes && heap.exhausted && !scope.journal && !header(values[0])->holds);
    heap.limit = 64u << 20;
    heap.exhausted = 0;
    myl_rc_scope_end(&scope);
    for (size_t i = 0; i < 4; ++i) myl_rc_owner_release(&heap, values[i]);
    finish(&heap);
}
// spec: RC-CHECKED-1
static void checked_mode_in_counting_builds(void) {
    assert(MYL_RC_CHECKED == 1);
    myl_native_heap heap;
    start(&heap);
    /* The checked allocation invariant accepts a registered element. */
    myl_rc_alloc_request request = {.element = &outer, .count = 1};
    void *value = NULL;
    assert(myl_rc_new(&heap, &request, &value) == MYL_RC_OK && value);
    myl_rc_owner_release(&heap, value);
    finish(&heap);
}

int myl_rc_fast_verify(void) {
    variant_plan_layout();
    variant_plan_operations();
    variant_plan_refusals();
    metadata_maps();
    edge_free_objects_retire_at_once();
    storage_visit_and_release_all();
    scope_journal_nodes_recycle();
    checked_mode_in_counting_builds();
    return 8;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) {
    assert(myl_rc_fast_verify() == 8);
    puts("native RC fast paths: 8 tests passed");
    return 0;
}
#endif
