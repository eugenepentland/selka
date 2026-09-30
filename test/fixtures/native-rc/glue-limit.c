// spec-case: RC-COUNTS-1
// spec-case: RC-LAYOUT-1
// spec-case: RC-STARTUP-IMAGE-1
// spec-case: RC-ACQUIRE-COPY-1
#include "glue.c"
#include <assert.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct { void *left, *right; } Pair;
typedef struct { void *owner, *held; } Tokens;
typedef struct { uint32_t tag, pad; Pair pair; } Choice;
static myl_rc_object *header(void *p) { return (myl_rc_object *)p - 1; }
static void self_copy_rejected(myl_native_heap *heap, Pair *value, int loan) {
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        struct rlimit core = {0, 0};
        assert(!setrlimit(RLIMIT_CORE, &core));
        assert(freopen("/dev/null", "w", stderr));
        if (loan) PAIR_SYMBOL_rcg_loan(heap, value, value);
        else PAIR_SYMBOL_rcg_retain(heap, value, value, 0);
        _exit(0);
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
}
int main(void) {
    myl_native_heap heap = {.limit = 64u << 20};
    assert(myl_rc_storage_init(&heap) == MYL_RC_OK);
    assert(myl_rc_module_register_image(&heap, &myl_rc_generated_module, &myl_rc_generated_image) == MYL_RC_OK);
    assert(heap.rc->metadata.batches->image == &myl_rc_generated_image);
    assert(myl_rc_shape_find(&heap, &PAIR_SYMBOL_rc) == &PAIR_SYMBOL_rc_image_entry.shape);
    assert(myl_rc_binding_find(&heap, &PAIR_SYMBOL)->flat.count == 2);
    void *leaf = myl_rc_storage_bytes(&heap, 8, 0);
    void *neighbor = myl_rc_storage_bytes(&heap, 8, 0);
    assert(leaf && neighbor && !((uintptr_t)leaf % _Alignof(max_align_t)));
    assert((unsigned char *)neighbor - (unsigned char *)leaf == 48);
    header(neighbor)->holds = 7;
    myl_rc_owner_release(&heap, leaf);
    leaf = myl_rc_storage_bytes(&heap, 8, 0);
    assert(header(neighbor)->owners == 1 && header(neighbor)->holds == 7);
    header(neighbor)->holds = 0;
    Pair input = {leaf, leaf}, output = {0};
    const uintptr_t mark = header(leaf)->common.mark;
    const uint64_t high = UINT64_C(1) << 32;
    header(leaf)->owners = high;
    header(leaf)->holds = high;
    assert(PAIR_SYMBOL_rcg_retain(&heap, &output, &input, 0));
    assert(header(leaf)->owners == high + 2 && header(leaf)->holds == high);
    PAIR_SYMBOL_rcg_drop(&heap, &output);
    assert(header(leaf)->owners == high && header(leaf)->holds == high);
    assert(PAIR_SYMBOL_rcg_loan(&heap, &output, &input));
    assert(header(leaf)->owners == high && header(leaf)->holds == high + 2);
    PAIR_SYMBOL_rcg_unloan(&heap, &output);
    assert(header(leaf)->owners == high && header(leaf)->holds == high);
    myl_rc_scope scope;
    myl_rc_scope_begin(&heap, &scope);
    assert(myl_rc_scope_pin(&scope, leaf) == MYL_RC_OK);
    assert(header(leaf)->holds == high + 1);
    myl_rc_scope_end(&scope);
    assert(header(leaf)->owners == high && header(leaf)->holds == high);
    header(leaf)->holds = 0;
    header(leaf)->owners = MYL_RC_COUNT_MAX - 1;
    assert(!PAIR_SYMBOL_rcg_retain(&heap, &output, &input, 0));
    assert(!output.left && !output.right && input.left == leaf && input.right == leaf);
    assert(header(leaf)->owners == MYL_RC_COUNT_MAX - 1 && header(leaf)->common.mark == mark);
    assert(myl_rc_take_failure(&heap) == MYL_RC_COUNT_LIMIT);
    assert(!PAIR_SYMBOL_rcg_publish(&heap, &output, &input, 0, MYL_RC_HISTORY_DIRECT));
    assert(!output.left && !output.right && header(leaf)->owners == MYL_RC_COUNT_MAX - 1);
    assert(header(leaf)->common.mark == mark && myl_rc_take_failure(&heap) == MYL_RC_COUNT_LIMIT);
    header(leaf)->holds = MYL_RC_COUNT_MAX - 1;
    assert(!PAIR_SYMBOL_rcg_loan(&heap, &output, &input));
    assert(!output.left && !output.right && input.left == leaf && input.right == leaf);
    assert(header(leaf)->holds == MYL_RC_COUNT_MAX - 1 && myl_rc_take_failure(&heap) == MYL_RC_COUNT_LIMIT);
    header(leaf)->holds = 0;
    header(leaf)->owners = MYL_RC_COUNT_MAX - 2;
    assert(PAIR_SYMBOL_rcg_retain(&heap, &output, &input, 0));
    assert(output.left == leaf && output.right == leaf && header(leaf)->owners == MYL_RC_COUNT_MAX);
    PAIR_SYMBOL_rcg_drop(&heap, &output);
    assert(!output.left && !output.right && header(leaf)->owners == MYL_RC_COUNT_MAX - 2);
    header(leaf)->owners = 1;
    assert(PAIR_SYMBOL_rcg_loan(&heap, &output, &input));
    assert(header(leaf)->holds == 2 && header(leaf)->owners == 1);
    PAIR_SYMBOL_rcg_unloan(&heap, &output);
    assert(!header(leaf)->holds && !output.left && !output.right);
    self_copy_rejected(&heap, &input, 0);
    self_copy_rejected(&heap, &input, 1);
    assert(PAIR_SYMBOL_rcg_take(&heap, &input, &input, 0));
    assert(input.left == leaf && input.right == leaf && header(leaf)->owners == 1);

    /* One payload can occur as both tokens. Physical retain preserves the
     * edge kinds while a loan acquires H on both occurrences. */
    Tokens tokens = {leaf, leaf}, acquired = {0};
    header(leaf)->holds = 1;
    assert(TOKENS_SYMBOL_rcg_retain(&heap, &acquired, &tokens, 0));
    assert(acquired.owner == leaf && acquired.held == leaf);
    assert(header(leaf)->owners == 2 && header(leaf)->holds == 2);
    TOKENS_SYMBOL_rcg_drop(&heap, &acquired);
    assert(header(leaf)->owners == 1 && header(leaf)->holds == 1);
    assert(TOKENS_SYMBOL_rcg_loan(&heap, &acquired, &tokens));
    assert(header(leaf)->owners == 1 && header(leaf)->holds == 3);
    TOKENS_SYMBOL_rcg_unloan(&heap, &acquired);
    assert(header(leaf)->owners == 1 && header(leaf)->holds == 1);
    header(leaf)->holds = MYL_RC_COUNT_MAX;
    assert(!TOKENS_SYMBOL_rcg_retain(&heap, &acquired, &tokens, 0));
    assert(!acquired.owner && !acquired.held && header(leaf)->owners == 1);
    assert(header(leaf)->holds == MYL_RC_COUNT_MAX && header(leaf)->common.mark == mark);
    assert(myl_rc_take_failure(&heap) == MYL_RC_COUNT_LIMIT);
    header(leaf)->holds = 0;

    /* An inactive arm's raw payload cannot be read as pointers, even while
     * the output copies those uninterpreted bytes verbatim. */
    Choice choice = {.pair = {(void *)(uintptr_t)1, (void *)(uintptr_t)3}}, choice_out = {0};
    assert(sizeof choice == CHOICE_SYMBOL.size);
    assert(CHOICE_SYMBOL_rcg_retain(&heap, &choice_out, &choice, 0));
    assert(!choice_out.tag && choice_out.pair.left == choice.pair.left);
    CHOICE_SYMBOL_rcg_drop(&heap, &choice_out);
    choice = (Choice){.tag = 1, .pair = input};
    assert(CHOICE_SYMBOL_rcg_loan(&heap, &choice_out, &choice));
    assert(choice_out.tag == 1 && header(leaf)->holds == 2);
    CHOICE_SYMBOL_rcg_unloan(&heap, &choice_out);
    assert(!header(leaf)->holds && header(leaf)->owners == 1);

    myl_native_type foreign_type = PAIR_SYMBOL;
    foreign_type.rc_id = 0;
    myl_rc_descriptor foreign = {.type = &foreign_type, .shape = &PAIR_SYMBOL_rc};
    assert(myl_rc_descriptor_register(&heap, &foreign) == MYL_RC_OK);
    assert(myl_rc_native_retain(&heap, &foreign_type, &output, &input, 0));
    assert(header(leaf)->owners == 3 && output.left == leaf && output.right == leaf);
    myl_rc_native_drop(&heap, &foreign_type, &output);
    assert(header(leaf)->owners == 1);
    assert(myl_rc_native_loan(&heap, &foreign_type, &output, &input));
    assert(header(leaf)->holds == 2);
    myl_rc_native_unloan(&heap, &foreign_type, &output);
    assert(!header(leaf)->holds);

    assert(myl_native_region_begin(&heap));
    void *arena_leaf = myl_rc_storage_bytes(&heap, 8, 1);
    assert(arena_leaf && myl_native_header_region(arena_leaf) == 1);
    Pair arena_input = {leaf, arena_leaf};
    assert(!PAIR_SYMBOL_rcg_retain(&heap, &output, &arena_input, 0));
    assert(!output.left && !output.right && header(leaf)->owners == 1);
    assert(myl_rc_take_failure(&heap) == MYL_RC_REGION_ERROR);
    assert(PAIR_SYMBOL_rcg_retain(&heap, &output, &arena_input, 1));
    assert(output.left == leaf && output.right == arena_leaf && header(leaf)->owners == 2);
    PAIR_SYMBOL_rcg_drop(&heap, &output);
    assert(header(leaf)->owners == 1);
    myl_native_region_end(&heap);

    void *moving = myl_rc_storage_bytes(&heap, 8, 0);
    assert(moving);
    header(moving)->owners = 2;
    void *overlap[3] = {moving, moving, NULL};
    assert(PAIR_SYMBOL_rcg_take(&heap, overlap + 1, overlap, 0));
    assert(!overlap[0] && overlap[1] == moving && overlap[2] == moving);
    assert(header(moving)->owners == 2);
    PAIR_SYMBOL_rcg_drop(&heap, overlap + 1);
    myl_rc_owner_release(&heap, leaf);
    myl_rc_owner_release(&heap, neighbor);
    assert(!heap.objects_live && header(neighbor)->retired_link == (uintptr_t)header(leaf));
    myl_native_heap_destroy(&heap);
    assert(!heap.bytes);
    return 0;
}
