// spec-case: RC-COUNTS-1
// spec-case: RC-LAYOUT-1
#include "glue.c"
#include <assert.h>
#include <stdint.h>

typedef struct { void *left, *right; } Pair;
static myl_rc_object *header(void *p) { return (myl_rc_object *)p - 1; }
int main(void) {
    myl_native_heap heap = {.limit = 64u << 20};
    assert(myl_rc_storage_init(&heap) == MYL_RC_OK);
    assert(myl_rc_module_register(&heap, &myl_rc_generated_module) == MYL_RC_OK);
    void *leaf = myl_rc_storage_bytes(&heap, 8, 0);
    void *neighbor = myl_rc_storage_bytes(&heap, 8, 0);
    assert(leaf && neighbor && !((uintptr_t)leaf % _Alignof(max_align_t)));
    assert((unsigned char *)neighbor - (unsigned char *)leaf == 32);
    header(neighbor)->holds = 7;
    myl_rc_owner_release(&heap, leaf);
    leaf = myl_rc_storage_bytes(&heap, 8, 0);
    assert(header(neighbor)->owners == 1 && header(neighbor)->holds == 7);
    header(neighbor)->holds = 0;
    Pair input = {leaf, leaf}, output = {0};
    const uintptr_t mark = header(leaf)->common.mark;
    header(leaf)->owners = UINT32_MAX - 1;
    assert(!PAIR_SYMBOL_rcg_retain(&heap, &output, &input, 0));
    assert(!output.left && !output.right && input.left == leaf && input.right == leaf);
    assert(header(leaf)->owners == UINT32_MAX - 1 && header(leaf)->common.mark == mark);
    assert(myl_rc_take_failure(&heap) == MYL_RC_COUNT_LIMIT);
    assert(!PAIR_SYMBOL_rcg_publish(&heap, &output, &input, 0, MYL_RC_HISTORY_DIRECT));
    assert(!output.left && !output.right && header(leaf)->owners == UINT32_MAX - 1);
    assert(header(leaf)->common.mark == mark && myl_rc_take_failure(&heap) == MYL_RC_COUNT_LIMIT);
    header(leaf)->holds = UINT32_MAX - 1;
    assert(!PAIR_SYMBOL_rcg_loan(&heap, &output, &input));
    assert(!output.left && !output.right && input.left == leaf && input.right == leaf);
    assert(header(leaf)->holds == UINT32_MAX - 1 && myl_rc_take_failure(&heap) == MYL_RC_COUNT_LIMIT);
    header(leaf)->holds = 0;
    header(leaf)->owners = UINT32_MAX - 2;
    assert(PAIR_SYMBOL_rcg_retain(&heap, &output, &input, 0));
    assert(output.left == leaf && output.right == leaf && header(leaf)->owners == UINT32_MAX);
    PAIR_SYMBOL_rcg_drop(&heap, &output);
    assert(!output.left && !output.right && header(leaf)->owners == UINT32_MAX - 2);
    header(leaf)->owners = 1;
    assert(PAIR_SYMBOL_rcg_loan(&heap, &output, &input));
    assert(header(leaf)->holds == 2 && header(leaf)->owners == 1);
    PAIR_SYMBOL_rcg_unloan(&heap, &output);
    assert(!header(leaf)->holds && !output.left && !output.right);
    myl_rc_owner_release(&heap, leaf);
    myl_rc_owner_release(&heap, neighbor);
    assert(!heap.objects_live && header(neighbor)->retired_link == (uintptr_t)header(leaf));
    myl_rc_heap_destroy(&heap);
    assert(!heap.bytes);
    return 0;
}
