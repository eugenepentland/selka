/* Evidence for the RC runtime's internal fast paths: probe-based metadata,
 * conditional (variant) flat plans, immediate retirement of edge-free objects,
 * recycled scope journal nodes and the allocator's heap-wide teardown API. */
#include "native_collections.h"
#include "native_rc_alloc.h"
#include "native_rc_collections.h"
#include "native_rc_internal.h"
#include "native_rc_values.h"
#include "native_regions.h"
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
// spec-case: RC-SLAB-POOLS-1
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
    /* The heap stays usable: metadata survives and new objects allocate,
     * reusing a released slab range (64 KiB aligned) from the spare list. */
    void *again = myl_native_heap_alloc(&heap, &outer, 1);
    assert(again && myl_rc_binding_find(&heap, &outer));
    assert(!(((uintptr_t)again - MYL_RC_PREFIX_BYTES - 80) & 0xffff));
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
    /* Only a production RC artifact (MYL_NATIVE_RC without counting) is unchecked. */
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

/* A record {O ptr, int, H ptr} and the choice variant are shallow (depth 2). */
static const myl_rc_shape held = {.size = 8, .kind = MYL_RC_SHAPE_HOLD_POINTER};
static const myl_rc_field mixed_edges[] = {{.shape = &owned}, {.offset = 8, .shape = &scalar}, {.offset = 16, .shape = &held}};
static const myl_rc_shape mixed_shape = {.size = 24, .kind = MYL_RC_SHAPE_RECORD, .as.record = {mixed_edges, 3}};
static const myl_rc_field pick_edges[] = {{.offset = 8, .shape = &owned, .tag = 0}, {.offset = 8, .shape = &scalar, .tag = 1}};
static const myl_rc_shape pick_shape = {.size = 16, .kind = MYL_RC_SHAPE_VARIANT, .as.variant = {pick_edges, 2, 0}};
static const myl_rc_shape *const shallow_shapes[] = {&mixed_shape, &pick_shape};
static const myl_rc_module shallow_module = {.abi = MYL_RC_ABI_VERSION, .shapes = shallow_shapes, .shape_count = 2};
typedef struct { uint64_t tag; void *value; } Pick;
typedef struct { void *owner; uint64_t word; void *view; } Mixed;
// spec: RC-SHALLOW-WALK-1
static void shallow_shapes_skip_the_walker(void) {
    myl_native_heap heap;
    start(&heap);
    assert(myl_rc_module_register(&heap, &shallow_module) == MYL_RC_OK);
    const myl_rc_shape *mixed = myl_rc_shape_find(&heap, &mixed_shape);
    assert(mixed && myl_rc_shallow_admits(mixed) && myl_rc_shallow_admits(myl_rc_shape_find(&heap, &pick_shape)));
    assert(!myl_rc_shallow_admits(myl_rc_shape_find(&heap, &choice_shape)));
    void *owner = bytes8(&heap), *view = bytes8(&heap);
    Mixed value = {owner, 99, view}, seeded = {0};
    /* Seeding copies scalars and clears O and H leaves alike. */
    myl_rc_value_seed(&heap, &mixed_shape, &seeded, &value, 1);
    assert(!seeded.owner && seeded.word == 99 && !seeded.view && !heap.rc->walk.depth);
    /* Copy acquires O for the owner leaf and H for the view leaf. */
    myl_rc_slot to = {.shape = &mixed_shape, .address = &seeded}, from = {.shape = &mixed_shape, .address = &value};
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_OK);
    assert(seeded.owner == owner && seeded.view == view && header(owner)->owners == 2 && header(view)->holds == 1);
    assert(!myl_rc_value_region(&heap, &mixed_shape, &seeded));
    /* Release drops O and H, clearing both edges before any death. */
    myl_rc_edges_release(&heap, &mixed_shape, &seeded, 1);
    myl_rc_drain(&heap);
    assert(!seeded.owner && !seeded.view && seeded.word == 99);
    assert(header(owner)->owners == 1 && !header(view)->holds && header(view)->owners == 1);
    /* A loan of the shallow shape holds every leaf; unloan drops H only. */
    Mixed loan = {0};
    assert(myl_rc_loan_copy(&heap, &mixed_shape, &loan, &value) == MYL_RC_OK);
    assert(header(owner)->holds == 1 && header(view)->holds == 1 && header(owner)->owners == 1);
    myl_rc_loan_drop(&heap, &mixed_shape, &loan);
    assert(!loan.owner && !loan.view && !loan.word && !header(owner)->holds && !header(view)->holds);
    /* A variant's inactive arm is neither cleared nor released. */
    Pick arm = {.tag = 1, .value = (void *)(uintptr_t)6}, copy = {0};
    myl_rc_value_seed(&heap, &pick_shape, &copy, &arm, 1);
    assert(copy.tag == 1 && copy.value == arm.value);
    myl_rc_edges_release(&heap, &pick_shape, &copy, 1);
    assert(copy.value == arm.value);
    arm = (Pick){.tag = 0, .value = owner};
    myl_rc_value_seed(&heap, &pick_shape, &copy, &arm, 1);
    assert(!copy.tag && !copy.value);
    myl_rc_owner_release(&heap, owner);
    myl_rc_owner_release(&heap, view);
    finish(&heap);
}
static const myl_rc_descriptor item_descriptor = {.type = &first, .shape = &first_shape};
typedef struct { void *text; uint64_t n; } Item;
// spec: RC-LIST-DIRECT-APPEND-1
static void list_append_publishes_in_place(void) {
    myl_native_heap heap;
    start(&heap);
    assert(myl_rc_descriptor_import(&heap, &item_descriptor) == MYL_RC_OK);
    myl_native_list *list = myl_native_list_new(&heap, &first, 0);
    assert(list);
    void *text = bytes8(&heap);
    Item value = {text, 1};
    for (uint64_t i = 0; i < 40; ++i) {
        value.n = i;
        assert(myl_rc_list_append(&heap, list, &value));
    }
    assert(list->length == 40 && header(text)->owners == 41);
    /* A borrowed element of the list itself survives the growth it causes. */
    while (list->length < list->capacity) assert(myl_rc_list_append(&heap, list, &value));
    size_t length = list->length;
    assert(myl_rc_list_append(&heap, list, (Item *)list->storage + 3));
    assert(list->length == length + 1 && ((Item *)list->storage)[length].n == 3 && header(text)->owners == length + 2);
    /* An input inside the spare capacity takes the staged path. */
    Item *spare = (Item *)list->storage + list->length + 1;
    assert(list->length + 1 < list->capacity);
    *spare = (Item){text, 77};
    assert(myl_rc_list_append(&heap, list, spare));
    assert(((Item *)list->storage)[length + 1].n == 77 && header(text)->owners == length + 3);
    memset(spare, 0, sizeof *spare);
    /* A queued death keeps the staged path (its drain may run callbacks). */
    Outer *body = myl_native_heap_alloc(&heap, &outer, 1);
    assert(body);
    myl_rc_edge_release(&heap, body);
    assert(heap.rc->dead.head);
    assert(myl_rc_list_append(&heap, list, &value) && !heap.rc->dead.head);
    myl_rc_owner_release(&heap, list);
    assert(header(text)->owners == 1);
    myl_rc_owner_release(&heap, text);
    finish(&heap);
}
// spec: RC-RAW-BLOCK-1
static void raw_bytes_and_blocks(void) {
    myl_native_heap heap;
    start(&heap);
    unsigned char *dirty = myl_rc_storage_bytes(&heap, 40, 0);
    assert(dirty && header(dirty)->owners == 1 && header(dirty)->common.element);
    memset(dirty, 0xab, 40);
    myl_rc_owner_release(&heap, dirty);
    /* The zero-filled contract holds on a reused slot. */
    unsigned char *clean = myl_rc_storage_bytes(&heap, 40, 0);
    assert(clean == dirty);
    for (size_t i = 0; i < 40; ++i) assert(!clean[i]);
    memset(clean, 0xcd, 40);
    myl_rc_owner_release(&heap, clean);
    /* A block keeps an exact header but leaves its payload to the caller. */
    unsigned char *block = myl_rc_storage_block(&heap, 40, 0);
    assert(block == dirty && header(block)->owners == 1 && !header(block)->holds);
    assert(((header(block)->common.mark & MYL_NATIVE_OBJECT_COUNT_BITS) >> MYL_NATIVE_OBJECT_COUNT_SHIFT) == 40);
    myl_rc_owner_release(&heap, block);
    /* Large and arena requests keep the generic path. */
    void *large = myl_rc_storage_block(&heap, 100000, 0);
    assert(large && (header(large)->common.mark & MYL_NATIVE_OBJECT_LARGE));
    myl_rc_owner_release(&heap, large);
    assert(myl_native_region_begin(&heap));
    unsigned char *arena = myl_rc_storage_bytes(&heap, 16, 1);
    assert(arena && myl_native_header_region(arena) == 1 && !arena[0]);
    myl_rc_arena_close(&heap, 1);
    finish(&heap);
}
// spec: RC-CLONE-SPAN-1
static void list_clone_spans(void) {
    myl_native_heap heap;
    start(&heap);
    assert(myl_rc_descriptor_import(&heap, &item_descriptor) == MYL_RC_OK);
    myl_native_list *list = myl_native_list_new(&heap, &first, 0);
    assert(list);
    void *text = bytes8(&heap), *pinned = bytes8(&heap);
    for (uint64_t i = 0; i < 300; ++i) {
        Item value = {i == 150 ? pinned : text, i};
        assert(myl_rc_list_append(&heap, list, &value));
    }
    /* A pinned element payload is snapshotted; every other leaf is shared. */
    myl_rc_pin pin = {0};
    assert(myl_rc_pin_acquire(&heap, pinned, &pin) == MYL_RC_OK);
    assert(myl_rc_owner_acquire(&heap, list) == MYL_RC_OK);
    myl_rc_counters before, after;
    assert(myl_rc_stats_snapshot(&heap, &before));
    void *slot = list;
    myl_rc_slot unique = {.shape = &owned, .address = &slot};
    assert(myl_rc_unique_owned(&heap, &unique) == MYL_RC_OK);
    myl_native_list *copy = slot;
    assert(copy != list && copy->length == 300 && header(list)->owners == 1);
    assert(myl_rc_stats_snapshot(&heap, &after));
    assert(after.events[MYL_RC_STAT_CLONE] == before.events[MYL_RC_STAT_CLONE] + 2);
    assert(header(text)->owners == 1 + 2 * 299 && header(pinned)->owners == 2);
    Item *items = copy->storage;
    assert(items[150].text != pinned && items[150].n == 150 && header(items[150].text)->owners == 1);
    for (size_t i = 0; i < 300; ++i) assert(items[i].n == i && (i == 150 || items[i].text == text));
    myl_rc_pin_release(&heap, &pin);
    myl_rc_owner_release(&heap, copy);
    myl_rc_owner_release(&heap, list);
    assert(header(text)->owners == 1 && header(pinned)->owners == 1);
    myl_rc_owner_release(&heap, text);
    myl_rc_owner_release(&heap, pinned);
    finish(&heap);
}
static int shared(const void *payload) { return (header((void *)payload)->common.mark & MYL_NATIVE_OBJECT_SHARED) != 0; }
// spec: RC-SEMANTIC-FLAT-1
static void flat_semantic_publication(void) {
    myl_native_heap heap;
    start(&heap);
    assert(myl_rc_descriptor_import(&heap, &item_descriptor) == MYL_RC_OK);
    myl_native_list *list = myl_native_list_new(&heap, &number, 0);
    void *text = bytes8(&heap);
    assert(list);
    /* COPY acquires every leaf and marks a reused mutable payload SHARED. */
    Item value = {list, 5}, copy = {0};
    assert(myl_rc_native_publish(&heap, &first, &copy, &value, 0, MYL_RC_HISTORY_DIRECT));
    assert(copy.text == list && copy.n == 5 && header(list)->owners == 2 && shared(list));
    myl_rc_native_drop(&heap, &first, &copy);
    /* A non-mutable payload is shared without a mark; TAKE moves the token. */
    Item word = {text, 6}, moved = {0};
    assert(myl_rc_native_publish(&heap, &first, &moved, &word, 0, MYL_RC_HISTORY_DIRECT | MYL_RC_HISTORY_TAKE));
    assert(moved.text == text && !word.text && !word.n && header(text)->owners == 1 && !shared(text));
    /* A refused acquisition commits no history and leaves the output empty. */
    myl_native_list *fresh = myl_native_list_new(&heap, &number, 0);
    assert(fresh);
    header(fresh)->owners = MYL_RC_COUNT_MAX;
    Item refused = {fresh, 7}, out = {0};
    assert(!myl_rc_native_publish(&heap, &first, &out, &refused, 0, MYL_RC_HISTORY_DIRECT));
    assert(myl_rc_take_failure(&heap) == MYL_RC_COUNT_LIMIT && !out.text && !out.n && !shared(fresh));
    header(fresh)->owners = 1;
    /* A pinned leaf keeps the general transaction, which snapshots it. */
    myl_rc_pin pin = {0};
    assert(myl_rc_pin_acquire(&heap, fresh, &pin) == MYL_RC_OK);
    assert(myl_rc_native_publish(&heap, &first, &out, &refused, 0, MYL_RC_HISTORY_DIRECT));
    assert(out.text && out.text != fresh && out.n == 7 && header(fresh)->owners == 1);
    myl_rc_native_drop(&heap, &first, &out);
    myl_rc_pin_release(&heap, &pin);
    myl_rc_native_drop(&heap, &first, &moved);
    myl_rc_owner_release(&heap, fresh);
    myl_rc_owner_release(&heap, list);
    finish(&heap);
}
// spec: RC-FLAT-TAKE-1
static void flat_take_publishes_in_place(void) {
    myl_native_heap heap;
    start(&heap);
    assert(myl_rc_descriptor_import(&heap, &item_descriptor) == MYL_RC_OK);
    void *text = bytes8(&heap);
    Item value = {text, 9}, out = {0};
    assert(myl_rc_native_take(&heap, &first, &out, &value, 0));
    assert(out.text == text && out.n == 9 && !value.text && !value.n && header(text)->owners == 1);
    /* Taking a slot onto itself keeps the value. */
    assert(myl_rc_native_take(&heap, &first, &out, &out, 0));
    assert(out.text == text && out.n == 9 && header(text)->owners == 1);
    /* With a queued death the staged path still publishes the same value. */
    Outer *body = myl_native_heap_alloc(&heap, &outer, 1);
    assert(body);
    myl_rc_edge_release(&heap, body);
    Item again = {0};
    assert(myl_rc_native_take(&heap, &first, &again, &out, 0));
    assert(again.text == text && !out.text && !heap.rc->dead.head && header(text)->owners == 1);
    myl_rc_native_drop(&heap, &first, &again);
    finish(&heap);
}
static const myl_rc_descriptor number_descriptor = {.type = &number, .shape = &scalar};
// spec: RC-OPAQUE-EXTEND-1
static void opaque_extension_keeps_prefix(void) {
    myl_native_heap heap;
    start(&heap);
    assert(myl_rc_descriptor_import(&heap, &number_descriptor) == MYL_RC_OK);
    assert(plan(&heap, &number)->count == 0 && plan(&heap, &pointer)->count == 1);
    /* A plain list grows in place far past the slab classes, and every
     * element it ever stored survives each extension. */
    myl_native_list *list = myl_native_list_new(&heap, &number, 0);
    assert(list);
    for (uint64_t i = 0; i < 100000; ++i) assert(myl_rc_list_append(&heap, list, &i));
    assert(list->length == 100000 && list->capacity >= 100000);
    for (uint64_t i = 0; i < 100000; ++i) assert(((uint64_t *)list->storage)[i] == i);
    /* A pointer list's new capacity is still zero: its drop walks slots. */
    myl_native_list *pointers = myl_native_list_new(&heap, &pointer, 0);
    assert(pointers);
    void *text = bytes8(&heap);
    for (size_t i = 0; i < 5000; ++i) assert(myl_rc_list_append(&heap, pointers, &text));
    for (size_t i = pointers->length; i < pointers->capacity; ++i) assert(!((void **)pointers->storage)[i]);
    assert(header(text)->owners == 5001);
    myl_rc_owner_release(&heap, pointers);
    myl_rc_owner_release(&heap, list);
    assert(header(text)->owners == 1);
    myl_rc_owner_release(&heap, text);
    finish(&heap);
}
// spec-case: RC-ALLOC-CACHE-1
static void allocation_cache_reuse(void) {
    myl_native_heap heap;
    start(&heap);
    /* An 8-byte payload behind the 32-byte prefix is the 48-byte class 2. */
    void *first = bytes8(&heap);
    size_t live = heap.objects_live;
    myl_rc_edge_release(&heap, first);
    assert(heap.objects_live == live - 1 && header(first)->common.mark == MYL_RC_RETIRED_MARK);
    assert(heap.rc_cache.free[2] == header(first) && heap.rc_cache.pushed >= 48);
    /* The next allocation of the class pops the same slot, zeroed. */
    void *again = bytes8(&heap);
    assert(again == first && header(again)->owners == 1 && !header(again)->holds && heap.objects_live == live);
    assert(!*(uint64_t *)again);
    myl_rc_owner_release(&heap, again);
    /* A budget refusal gives every listed slot back to its slab and releases
     * the slabs that empties before admitting the request again. */
    void *values[64];
    for (size_t i = 0; i < 64; ++i) values[i] = bytes8(&heap);
    for (size_t i = 0; i < 64; ++i) myl_rc_owner_release(&heap, values[i]);
    assert(heap.rc_cache.free[2]);
    size_t reserved = myl_rc_storage_reserved(&heap);
    heap.limit = heap.bytes + 1024;
    void *large = myl_rc_storage_bytes(&heap, 16384, 0);
    assert(large && !heap.rc_cache.free[2] && !heap.rc_cache.pushed);
    assert(myl_rc_storage_reserved(&heap) < reserved + 16384);
    myl_rc_owner_release(&heap, large);
    heap.limit = 64u << 20;
    /* The class refills from a fresh slab in address order. */
    void *fresh = bytes8(&heap);
    assert(fresh && !(((uintptr_t)fresh - MYL_RC_PREFIX_BYTES - 80) & 0xffff));
    myl_rc_owner_release(&heap, fresh);
    finish(&heap);
}
// spec-case: RC-DRAIN-FLAT-1
static void drain_releases_trees_inline(void) {
    myl_native_heap heap;
    start(&heap);
    myl_rc_counters before, after;
    assert(myl_rc_stats_snapshot(&heap, &before));
    size_t live = heap.objects_live;
    /* A chain of bodies, each also holding an edge-free multi-element extent
     * whose death is queued inside the drain. */
    Outer *root = NULL;
    for (size_t i = 0; i < 100; ++i) {
        Outer *body = myl_native_heap_alloc(&heap, &outer, 1);
        assert(body);
        body->left = root;
        body->right = myl_rc_storage_bytes(&heap, 100, 0);
        assert(body->right && ((myl_native_object *)body->right - 1)->mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT != 1);
        root = body;
    }
    assert(heap.objects_live == live + 200);
    myl_rc_owner_release(&heap, root);
    assert(!heap.rc->dead.head && !heap.rc->dead.active && heap.objects_live == live);
    assert(myl_rc_stats_snapshot(&heap, &after));
    assert(after.events[MYL_RC_STAT_RETIRE] == before.events[MYL_RC_STAT_RETIRE] + 200);
    assert(after.events[MYL_RC_STAT_OWNER_RELEASE] == before.events[MYL_RC_STAT_OWNER_RELEASE] + 200);
    finish(&heap);
}
// spec-case: RC-PLAIN-TYPE-1
static void plain_elements_copy_as_bytes(void) {
    myl_native_heap heap;
    start(&heap);
    myl_native_list *list = myl_native_list_new(&heap, &number, 0);
    assert(list);
    for (uint64_t i = 0; i < 100; ++i) assert(myl_rc_list_append(&heap, list, &i));
    assert(heap.rc->plain == &number && list->length == 100);
    /* spec-case: RC-LIST-HEADER-1. The header module is registered once and
     * grown plain backings keep every live element. */
    assert(heap.rc->lists && list->capacity >= 100);
    for (uint64_t i = 0; i < 100; ++i) assert(((uint64_t *)list->storage)[i] == i);
    myl_rc_counters before, after;
    assert(myl_rc_stats_snapshot(&heap, &before));
    myl_native_list *copy = myl_native_list_copy(&heap, list);
    assert(copy && copy != list && copy->length == 100 && copy->storage != list->storage);
    for (uint64_t i = 0; i < 100; ++i) assert(((uint64_t *)copy->storage)[i] == i);
    assert(myl_rc_stats_snapshot(&heap, &after));
    assert(after.events[MYL_RC_STAT_OWNER_ACQUIRE] == before.events[MYL_RC_STAT_OWNER_ACQUIRE]);
    /* A keyed sorted copy of plain elements gathers straight into its result:
     * keys 99..0 reverse the elements. */
    myl_native_list *keys = myl_native_list_new(&heap, &number, 100);
    myl_native_list *sorted = myl_native_list_new(&heap, &number, 100);
    assert(keys && sorted);
    for (uint64_t i = 0; i < 100; ++i) {
        uint64_t key = 99 - i;
        assert(myl_rc_list_append(&heap, keys, &key));
    }
    size_t live = heap.objects_live;
    myl_rc_sort_request request = {.values = sorted, .source = list, .keys = keys, .shape = 1};
    assert(myl_rc_list_sort_keyed(&heap, &request) && sorted->length == 100 && heap.objects_live == live);
    for (uint64_t i = 0; i < 100; ++i) assert(((uint64_t *)sorted->storage)[i] == 99 - i);
    myl_rc_owner_release(&heap, sorted);
    myl_rc_owner_release(&heap, keys);
    myl_rc_owner_release(&heap, copy);
    myl_rc_owner_release(&heap, list);
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
    shallow_shapes_skip_the_walker();
    list_append_publishes_in_place();
    raw_bytes_and_blocks();
    list_clone_spans();
    flat_semantic_publication();
    flat_take_publishes_in_place();
    opaque_extension_keeps_prefix();
    allocation_cache_reuse();
    drain_releases_trees_inline();
    plain_elements_copy_as_bytes();
    return 18;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) {
    assert(myl_rc_fast_verify() == 18);
    puts("native RC fast paths: 18 tests passed");
    return 0;
}
#endif
