/* SHARED-COUNTS-2: compare enumerated edges, marked nodes and actual decrements
 * against explicit fixture ownership, including aliases and inactive words. */
#include "core_rt_all.c"
#undef NDEBUG
#include <assert.h>
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
typedef struct { myl_block *blocks[32]; unsigned seen[32]; size_t length; } expected_edges;
static void observe(myl_block *child, void *context) {
    expected_edges *edges = context;
    for (size_t i = 0; i < edges->length; ++i) if (edges->blocks[i] == child) { ++edges->seen[i]; return; }
    assert(!"unexpected child edge");
}
static void differential(myl_block *parent, myl_block **children, const unsigned *expected, size_t length) {
    expected_edges edges = {.length = length};
    uint32_t before[32];
    for (size_t i = 0; i < length; ++i) { edges.blocks[i] = children[i]; before[i] = count_load(children[i]); }
    core_children(parent, observe, &edges);
    for (size_t i = 0; i < length; ++i) assert(edges.seen[i] == expected[i]);
    myl_core_share(parent);
    assert(count_load(parent) == SELKA_SHARED + 1);
    for (size_t i = 0; i < length; ++i)
        assert(count_load(children[i]) == (expected[i] ? before[i] | SELKA_SHARED : before[i]));
    myl_core_share(parent); /* neither aliases nor repeat publication add owners */
    myl_core_release(parent);
    for (size_t i = 0; i < length; ++i) {
        uint32_t wanted = expected[i] ? (before[i] | SELKA_SHARED) - expected[i] : before[i];
        assert(count_load(children[i]) == wanted);
        myl_core_release(children[i]);
    }
    assert(live_count() == 0);
}
static myl_block *leaf(void) { return str_from("value", 5); }
static void leaves(void) {
    myl_block *str = leaf();
    differential(str, NULL, NULL, 0);
    myl_block *bytes = block_new(SELKA_KIND_BYTES, 64, 1);
    bytes->len = 64;
    differential(bytes, NULL, NULL, 0);
    myl_block *buffer = myl_core_buffer_new(64);
    differential(buffer, NULL, NULL, 0);
    static const myl_block immortal = {SELKA_SATURATED, SELKA_KIND_STR, 0, 0, 0};
    myl_core_share(NULL);
    myl_core_share((myl_block *)&immortal);
    assert(count_load(&immortal) == SELKA_SATURATED);
}
static void aliases(void) {
    myl_block *children[] = {leaf(), leaf()};
    myl_block *parent = myl_core_list_new_slow(4, 8);
    parent->reserved = (int64_t)(intptr_t)layout_blocks;
    parent->len = 4;
    myl_block **items = (myl_block **)block_data(parent);
    items[0] = children[0]; items[1] = NULL; items[2] = children[1]; items[3] = children[0];
    count_retain(children[0]); count_retain(children[0]); count_retain(children[1]);
    const unsigned expected[] = {2, 1};
    differential(parent, children, expected, 2);
}
static void guarded_box(void) {
    /* Two nested tag guards, then one unguarded field. The inactive payload
     * contains 0xdeadbeef, so accidentally following it also fails loudly. */
    static const int32_t layout[] = {40, 3, 2, 16, 2, 24, 1, 32, 0, 0, 2, 0, 8, 3, 1};
    myl_block *children[] = {leaf(), leaf(), leaf()};
    myl_block *parent = myl_core_box_new(40);
    parent->reserved = (int64_t)(intptr_t)layout;
    uint64_t *words = (uint64_t *)block_data(parent);
    words[0] = 2; words[1] = 0; words[2] = UINT64_C(0xdeadbeef);
    words[3] = (uintptr_t)children[1]; words[4] = (uintptr_t)children[2];
    count_retain(children[1]); count_retain(children[2]);
    const unsigned expected[] = {0, 1, 1};
    differential(parent, children, expected, 3);
}
static void guarded_list(void) {
    static const int32_t layout[] = {16, 1, 1, 8, 1, 0, 1, 0};
    myl_block *children[] = {leaf()};
    myl_block *parent = myl_core_list_new_slow(3, 16);
    parent->reserved = (int64_t)(intptr_t)layout; parent->len = 3;
    uint64_t *words = (uint64_t *)block_data(parent);
    words[0] = 1; words[1] = (uintptr_t)children[0];
    words[2] = 0; words[3] = UINT64_C(0xdeadbeef);
    words[4] = 1; words[5] = (uintptr_t)children[0];
    count_retain(children[0]); count_retain(children[0]);
    const unsigned expected[] = {2};
    differential(parent, children, expected, 1);
}
static void boxed_view(void) {
    static const int32_t layout[] = {24, 1, 0, 16, 0};
    myl_block *children[] = {leaf()};
    myl_block *parent = myl_core_box_new(24);
    parent->reserved = (int64_t)(intptr_t)layout;
    uint64_t *words = (uint64_t *)block_data(parent);
    words[0] = (uintptr_t)block_data(children[0]); words[1] = 5; words[2] = (uintptr_t)children[0];
    count_retain(children[0]);
    const unsigned expected[] = {1};
    differential(parent, children, expected, 1);
}
static void dictionary(void) {
    static const int32_t layout[] = {16, 2, 0, 0, 0, 8, 0};
    static const core_dict_descriptor desc = {16, 8, 2, 8, layout, NULL, NULL};
    myl_block *children[11]; unsigned expected[11];
    children[10] = leaf(); expected[10] = 9;
    myl_block *parent = myl_core_dict_new(16, &desc);
    for (int i = 0; i < 10; ++i) {
        char name = 'a' + i;
        children[i] = str_from(&name, 1); expected[i] = i == 3 ? 0 : 1;
        count_retain(children[i]); count_retain(children[10]);
        uint64_t hash = myl_core_dict_hash(parent, &children[i]);
        int64_t probe = myl_core_dict_find(parent, &children[i], hash);
        parent = myl_core_dict_insert(parent, probe, &children[i], &children[10], true);
    }
    assert(dict_meta(parent)->index);
    parent = myl_core_dict_remove(parent, 3);
    assert(dict_meta(parent)->dead && parent->len == 9);
    differential(parent, children, expected, 11);
}
static void io_blocks(void) {
    myl_block *pairs[] = {str_from("KEY\0value\0", 10)};
    myl_block *provider = core_io_provider(4, 1, 0, pairs[0]);
    const unsigned one[] = {1};
    differential(provider, pairs, one, 1);
    myl_block *children[] = {leaf(), leaf(), leaf()};
    myl_block *cap = core_io_cap(4, 7, children[0], children[1], children[2]);
    const unsigned three[] = {1, 1, 1};
    differential(cap, children, three, 3);
    myl_block *authority[] = {leaf()};
    myl_block *resource = block_new(7, sizeof(CoreIoResource), 1);
    resource->len = 1; resource->reserved = (int64_t)(intptr_t)core_io_resource_layout;
    memset(block_data(resource), 0, sizeof(CoreIoResource));
    ((CoreIoResource *)block_data(resource))->authority = authority[0];
    count_retain(authority[0]);
    differential(resource, authority, one, 1);
}
static void deep(void) {
    myl_block *root = leaf();
    for (int i = 0; i < 100000; ++i) {
        myl_block *next = myl_core_box_new(8);
        next->reserved = (int64_t)(intptr_t)layout_blocks;
        *(myl_block **)block_data(next) = root;
        root = next;
    }
    myl_core_share(root);
    myl_block *at = root;
    for (int i = 0; i < 100000; ++i) {
        assert(count_load(at) == SELKA_SHARED + 1);
        at = *(myl_block **)block_data(at);
    }
    assert(count_load(at) == SELKA_SHARED + 1);
    myl_core_share(root);
    myl_core_release(root);
    assert(live_count() == 0);
}
static void *saturated_child(void *argument) {
    myl_block *child = argument;
    for (int i = 0; i < 100000; ++i) {
        count_retain(child);
        assert(!count_release(child));
    }
    return NULL;
}
static void saturation(void) {
    myl_block *child = leaf();
    myl_block *root = myl_core_box_new(8);
    root->reserved = (int64_t)(intptr_t)layout_blocks;
    *(myl_block **)block_data(root) = child;
    root->count = SELKA_PLAIN_MAX;
    count_retain(root);
    assert(count_load(root) == SELKA_SATURATED);
    assert(count_load(child) == SELKA_SHARED + 1);
    myl_core_share(root);
    assert(count_load(child) == SELKA_SHARED + 1);
    pthread_t threads[8];
    for (int i = 0; i < 8; ++i) assert(!pthread_create(&threads[i], NULL, saturated_child, child));
    for (int i = 0; i < 8; ++i) assert(!pthread_join(threads[i], NULL));
    assert(count_load(child) == SELKA_SHARED + 1);
    assert(live_count() == 2); /* the intentional permanent root owns the leaf */
    puts("plain saturation shares descendants before immortal publication (8 workers)");
}
int main(int argc, char **argv) {
    alarm(30);
    if (argc > 1 && !strcmp(argv[1], "saturation")) {
        saturation();
        return myl_core_exit(0);
    }
    leaves(); aliases(); guarded_box(); guarded_list(); boxed_view(); dictionary(); io_blocks(); deep();
    puts("share walk: all block kinds, aliases, guards, tombstones, providers and 100000 levels ok");
    return myl_core_exit(0);
}
