#include "native_rc_dictionary.h"
#include "native_regions.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/resource.h>
static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
static const myl_native_type pointer = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER};
static const myl_rc_shape held = {.size = sizeof(void *), .kind = MYL_RC_SHAPE_HOLD_POINTER};
static const myl_rc_shape owned = {.size = sizeof(void *), .kind = MYL_RC_SHAPE_POINTER};
static const myl_rc_field fields[] = {{.shape = &held}, {.offset = sizeof(void *), .shape = &held}};
static const myl_rc_shape pair = {.size = 2 * sizeof(void *), .kind = MYL_RC_SHAPE_RECORD, .as.record = {fields, 2}};
static const myl_rc_shape *const shapes[] = {&held, &owned, &pair};
static const myl_rc_module module = {.abi = MYL_RC_ABI_VERSION, .shapes = shapes, .shape_count = 3};
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
static myl_rc_slot slot(const myl_rc_shape *shape, void *address, unsigned region) {
    return (myl_rc_slot){.shape = shape, .address = address, .region = region};
}
// spec: RC-HOLD-VIEW-1
static void lifetime_and_identity(void) {
    myl_native_heap heap;
    start(&heap);
    myl_native_dictionary *dict = myl_native_dictionary_new(&heap, &number, &number, 0);
    uint64_t key = 4, value = 12, found;
    assert(dict && myl_native_dictionary_write(&heap, dict, &key, &value));
    void *view = NULL, *copy = NULL;
    myl_rc_slot from = slot(&held, &dict, 0), to = slot(&held, &view, 0);
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_OK);
    assert(view == dict && header(dict)->owners == 1 && header(dict)->holds == 1 && myl_rc_unique(&heap, dict));
    myl_rc_pin pin = {0};
    assert(myl_rc_pin_acquire(&heap, dict, &pin) == MYL_RC_OK);
    from.address = &view;
    to.address = &copy;
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_OK && copy == view);
    assert(header(dict)->owners == 1 && header(dict)->holds == 3);
    myl_rc_pin_release(&heap, &pin);
    value = 22;
    assert(myl_native_dictionary_write(&heap, dict, &key, &value));
    assert(myl_native_dictionary_read(view, &key, &found) && found == 22);
    myl_rc_owner_release(&heap, dict);
    assert(header(view)->owners == 0 && header(view)->holds == 2);
    myl_rc_value_drop(&heap, &from);
    assert(!view && header(copy)->holds == 1);
    assert(myl_native_dictionary_read(copy, &key, &found) && found == 22);
    heap.limit = heap.bytes;
    myl_rc_value_drop(&heap, &to);
    finish(&heap);
}
// spec: RC-HOLD-VIEW-1
static void count_refusal_and_take(void) {
    myl_native_heap heap;
    start(&heap);
    void *payload = myl_rc_storage_bytes(&heap, 8, 0), *output = NULL;
    assert(payload);
    myl_rc_slot from = slot(&held, &payload, 0), to = slot(&held, &output, 0);
    header(payload)->holds = MYL_RC_COUNT_MAX;
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_COUNT_LIMIT);
    assert(!output && header(payload)->holds == MYL_RC_COUNT_MAX && header(payload)->owners == 1);
    assert(myl_rc_value_take(&heap, &to, &from) == MYL_RC_OK);
    assert(!payload && output && header(output)->holds == MYL_RC_COUNT_MAX);
    header(output)->holds = 1;
    myl_rc_owner_release(&heap, output);
    myl_rc_value_drop(&heap, &to);
    finish(&heap);
}
// spec: RC-HOLD-VIEW-1
static void aggregate_rollback(void) {
    myl_native_heap heap;
    start(&heap);
    void *left = myl_rc_storage_bytes(&heap, 8, 0), *right = myl_rc_storage_bytes(&heap, 8, 0);
    assert(left && right);
    void *source[] = {left, right}, *output[2] = {0};
    myl_rc_slot from = slot(&pair, source, 0), to = slot(&pair, output, 0);
    header(right)->holds = MYL_RC_COUNT_MAX;
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_COUNT_LIMIT);
    assert(!output[0] && !output[1] && !header(left)->holds && header(right)->holds == MYL_RC_COUNT_MAX);
    header(right)->holds = 0;
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_OK);
    assert(myl_rc_value_region(&heap, &pair, output) == 0);
    myl_rc_owner_release(&heap, left);
    myl_rc_owner_release(&heap, right);
    heap.limit = heap.bytes;
    myl_rc_value_drop(&heap, &to);
    finish(&heap);
}
// spec: RC-HOLD-VIEW-1
static void arena_escape_and_memo(void) {
    myl_native_heap heap;
    start(&heap);
    assert(myl_native_region_begin(&heap));
    myl_native_dictionary *dict = myl_native_dictionary_new(&heap, &number, &number, 0);
    uint64_t key = 3, value = 41, found;
    assert(dict && myl_native_dictionary_write(&heap, dict, &key, &value));
    void *source[] = {dict, dict}, *output[2] = {0};
    myl_rc_slot from = slot(&pair, source, 1), to = slot(&pair, output, 0);
    assert(myl_rc_value_region(&heap, &pair, source) == 1);
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_REGION_ERROR && !output[0] && !output[1]);
    assert(myl_rc_region_escape(&heap, &to, &from) == MYL_RC_OK);
    assert(output[0] == output[1] && output[0] != dict && source[0] == dict);
    assert(header(output[0])->owners == 0 && header(output[0])->holds == 2);
    value = 55;
    assert(myl_native_dictionary_write(&heap, dict, &key, &value));
    myl_native_region_end(&heap);
    assert(myl_native_dictionary_read(output[0], &key, &found) && found == 41);
    myl_rc_value_drop(&heap, &to);
    finish(&heap);
}
// spec: RC-HOLD-VIEW-1
static void escaped_child_refusal(void) {
    myl_native_heap heap;
    start(&heap);
    void *leaf = myl_rc_storage_bytes(&heap, 8, 0), *limit = myl_rc_storage_bytes(&heap, 8, 0);
    assert(leaf && limit && myl_native_region_begin(&heap));
    myl_native_list *list = myl_native_list_new(&heap, &pointer, 2);
    assert(list && myl_native_list_append(&heap, list, &leaf) && myl_native_list_append(&heap, list, &limit));
    void *output = NULL;
    myl_rc_slot from = slot(&held, &list, 1), to = slot(&held, &output, 0);
    header(limit)->owners = MYL_RC_COUNT_MAX;
    size_t live = heap.objects_live;
    assert(myl_rc_region_escape(&heap, &to, &from) == MYL_RC_COUNT_LIMIT);
    assert(!output && header(leaf)->owners == 2 && heap.objects_live == live);
    header(limit)->owners = 2;
    myl_native_region_end(&heap);
    myl_rc_owner_release(&heap, leaf);
    myl_rc_owner_release(&heap, limit);
    finish(&heap);
}
// spec: RC-HOLD-VIEW-1
static void held_chain_release(void) {
    myl_native_heap heap;
    start(&heap);
    myl_native_type link = pointer;
    myl_rc_descriptor descriptor = {.type = &link, .shape = &held};
    assert(myl_rc_descriptor_register(&heap, &descriptor) == MYL_RC_OK);
    void *head = NULL;
    for (size_t i = 0; i < 100000; ++i) {
        void **next = NULL;
        myl_rc_alloc_request request = {.element = &link, .count = 1};
        assert(myl_rc_new(&heap, &request, (void **)&next) == MYL_RC_OK);
        myl_rc_hold hold = {0};
        assert(myl_rc_hold_acquire(&heap, head, &hold) == MYL_RC_OK);
        *next = head;
        myl_rc_owner_release(&heap, head);
        head = next;
    }
    heap.limit = heap.bytes;
    myl_rc_owner_release(&heap, head);
    finish(&heap);
}
static void held_unique_reuses_ownerless(void) {
    myl_native_heap heap;
    start(&heap);
    void *view = myl_rc_storage_bytes(&heap, 8, 0);
    myl_rc_hold hold = {0};
    assert(view && myl_rc_hold_acquire(&heap, view, &hold) == MYL_RC_OK);
    myl_rc_owner_release(&heap, view);
    void *before = view;
    myl_rc_slot value = slot(&held, &view, 0);
    heap.limit = heap.bytes;
    assert(myl_rc_unique_held(&heap, &value) == MYL_RC_OK && view == before);
    assert(header(view)->owners == 0 && header(view)->holds == 1);
    myl_rc_value_drop(&heap, &value);
    finish(&heap);
}
static void held_unique_isolates_snapshot(void) {
    myl_native_heap heap;
    start(&heap);
    myl_native_dictionary *dict = myl_native_dictionary_new(&heap, &number, &number, 0);
    uint64_t key = 1, value = 7, found;
    assert(dict && myl_native_dictionary_write(&heap, dict, &key, &value));
    assert(myl_rc_owner_acquire(&heap, dict) == MYL_RC_OK);
    myl_rc_hold hold = {0};
    assert(myl_rc_hold_acquire(&heap, dict, &hold) == MYL_RC_OK);
    void *view = dict;
    myl_rc_slot target = slot(&held, &view, 0);
    myl_rc_pin pin = {0};
    assert(myl_rc_pin_acquire(&heap, dict, &pin) == MYL_RC_OK);
    assert(myl_rc_unique_held(&heap, &target) == MYL_RC_OK && view != dict);
    assert(header(dict)->owners == 2 && header(dict)->holds == 1);
    assert(header(view)->owners == 0 && header(view)->holds == 1);
    value = 9;
    assert(myl_native_dictionary_write(&heap, view, &key, &value));
    assert(myl_native_dictionary_read(dict, &key, &found) && found == 7);
    assert(myl_native_dictionary_read(view, &key, &found) && found == 9);
    myl_rc_pin_release(&heap, &pin);
    myl_rc_value_drop(&heap, &target);
    myl_rc_owner_release(&heap, dict);
    myl_rc_owner_release(&heap, dict);
    finish(&heap);
}
static void held_unique_rollback(unsigned region) {
    myl_native_heap heap;
    start(&heap);
    void *leaf = myl_rc_storage_bytes(&heap, 8, 0), *limit = myl_rc_storage_bytes(&heap, 8, 0);
    myl_native_list *source = myl_native_list_new(&heap, &pointer, 2);
    assert(leaf && limit && source && myl_native_list_append(&heap, source, &leaf) && myl_native_list_append(&heap, source, &limit));
    assert(myl_rc_owner_acquire(&heap, source) == MYL_RC_OK);
    myl_rc_hold hold = {0};
    assert(myl_rc_hold_acquire(&heap, source, &hold) == MYL_RC_OK);
    void *view = source;
    if (region) assert(myl_native_region_begin(&heap));
    myl_rc_slot target = slot(&held, &view, region);
    header(limit)->owners = MYL_RC_COUNT_MAX;
    size_t live = heap.objects_live;
    assert(myl_rc_unique_held(&heap, &target) == MYL_RC_COUNT_LIMIT);
    assert(view == source && header(source)->owners == 2 && header(source)->holds == 1);
    assert(header(leaf)->owners == 2);
    assert(region ? heap.objects_live > live : heap.objects_live == live);
    header(limit)->owners = 2;
    if (region) myl_native_region_end(&heap);
    assert(heap.objects_live == live);
    myl_rc_value_drop(&heap, &target);
    myl_rc_owner_release(&heap, source);
    myl_rc_owner_release(&heap, source);
    myl_rc_owner_release(&heap, leaf);
    myl_rc_owner_release(&heap, limit);
    finish(&heap);
}
static void held_scope_leaf(void) {
    myl_native_heap heap;
    start(&heap);
    void *source = myl_rc_storage_bytes(&heap, 8, 0);
    assert(source && myl_rc_owner_acquire(&heap, source) == MYL_RC_OK);
    myl_rc_hold hold = {0};
    assert(myl_rc_hold_acquire(&heap, source, &hold) == MYL_RC_OK);
    void *views[2] = {source, NULL};
    myl_rc_projection path = {.shape = &pair, .offset = 0};
    myl_rc_place place = {.receiver = slot(&pair, views, 0), .path = &path, .count = 1};
    myl_rc_scope scope;
    myl_rc_scope_begin(&heap, &scope);
    assert(myl_rc_scope_prepare(&scope, &place) == MYL_RC_OK && views[0] != source);
    assert(header(views[0])->owners == 0 && header(views[0])->holds == 2);
    assert(header(views[0])->common.mark & MYL_NATIVE_OBJECT_PINNED);
    myl_rc_scope_end(&scope);
    assert(header(views[0])->holds == 1 && !(header(views[0])->common.mark & MYL_NATIVE_OBJECT_PINNED));
    myl_rc_value_drop(&heap, &place.receiver);
    myl_rc_owner_release(&heap, source);
    myl_rc_owner_release(&heap, source);
    finish(&heap);
}
static void held_arena_snapshot(void) {
    myl_native_heap heap;
    start(&heap);
    assert(myl_native_region_begin(&heap));
    myl_native_dictionary *dict = myl_native_dictionary_new(&heap, &number, &number, 0);
    uint64_t key = 1, value = 7, found;
    assert(dict && myl_native_dictionary_write(&heap, dict, &key, &value));
    void *snapshot = NULL, *view = dict;
    myl_rc_slot from = slot(&owned, &dict, 1), to = slot(&owned, &snapshot, 1);
    assert(myl_rc_value_copy(&heap, &to, &from) == MYL_RC_OK && snapshot == dict);
    myl_rc_slot target = slot(&held, &view, 1);
    assert(myl_rc_unique_held(&heap, &target) == MYL_RC_OK && view != dict);
    assert(myl_native_header_region(view) == 1);
    value = 9;
    assert(myl_native_dictionary_write(&heap, view, &key, &value));
    assert(myl_native_dictionary_read(dict, &key, &found) && found == 7);
    assert(myl_native_dictionary_read(view, &key, &found) && found == 9);
    myl_rc_value_drop(&heap, &target);
    myl_native_region_end(&heap);
    finish(&heap);
}
int myl_rc_hold_verify(void) {
    struct rlimit original, bounded;
    assert(!getrlimit(RLIMIT_STACK, &original));
    bounded = original;
    if (bounded.rlim_cur > 262144) { bounded.rlim_cur = 262144; assert(!setrlimit(RLIMIT_STACK, &bounded)); }
    lifetime_and_identity();
    count_refusal_and_take();
    aggregate_rollback();
    arena_escape_and_memo();
    escaped_child_refusal();
    held_chain_release();
    held_unique_reuses_ownerless();
    held_unique_isolates_snapshot();
    held_unique_rollback(0);
    held_unique_rollback(1);
    held_scope_leaf();
    held_arena_snapshot();
    assert(!setrlimit(RLIMIT_STACK, &original));
    return 12;
}
#ifndef MYL_RC_CONTRACT_LIBRARY
int main(void) {
    assert(myl_rc_hold_verify() == 12);
    puts("native RC live holds: 12 tests passed");
    return 0;
}
#endif
