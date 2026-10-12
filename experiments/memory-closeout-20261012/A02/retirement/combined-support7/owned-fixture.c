/* Scratch Stage 4 ABI/copy/drop qualification; not a production runtime. */
#include "core_rt.c"

myl_block *myl_core_task_call(void *run, myl_block *env) {
    return ((myl_block *(*)(myl_block *))run)(env);
}

_Static_assert(sizeof(myl_block) == 32, "owned header size");
_Static_assert(offsetof(myl_block, kind) == 0, "owned kind offset");
_Static_assert(offsetof(myl_block, len) == 8, "owned length offset");
_Static_assert(offsetof(myl_block, cap) == 16, "owned capacity offset");
_Static_assert(offsetof(myl_block, reserved) == 24, "owned layout offset");

static const int32_t pointer_layout[] = {8, 1, 0, 0, 0};
static const core_value_shape text_shape = {.kind = 3, .size = 8};
static const core_value_shape *const list_children[] = {&text_shape};
static const core_value_shape list_shape = {.kind = 7, .size = 8, .count = 1, .children = list_children};

int main(void) {
    myl_block *list = myl_core_list_new_slow(1, 8);
    list->reserved = (int64_t)(intptr_t)pointer_layout;
    for (int64_t i = 0; i < 3; ++i) {
        list = myl_core_list_grow(list, 8);
        ((myl_block **)block_data(list))[list->len++] = str_from("abc" + i, 1);
    }
    myl_block *copy = myl_core_values_copy_box(&list_shape, list);
    if (myl_core_owned_same_block(list, copy)) return 1;
    for (int64_t i = 0; i < 3; ++i) {
        myl_block *left = ((myl_block **)block_data(list))[i];
        myl_block *right = ((myl_block **)block_data(copy))[i];
        if (myl_core_owned_same_block(left, right) || block_data(right)[0] != "abc"[i]) return 2;
    }
    myl_block *identity = list;
    list = myl_core_owned_list_rotate(list, 0, 8, 0);
    list = myl_core_owned_list_reverse(list, 8);
    if (!myl_core_owned_same_block(identity, list)) return 3;
    for (int64_t i = 0; i < 3; ++i)
        if (block_data(((myl_block **)block_data(list))[i])[0] != "acb"[i]) return 4;
    myl_block *removed = ((myl_block **)block_data(list))[--list->len];
    myl_core_drop_owned(removed);
    myl_core_drop_owned(list);
    for (int64_t i = 0; i < 3; ++i)
        if (block_data(((myl_block **)block_data(copy))[i])[0] != "abc"[i]) return 5;
    myl_core_drop_owned(copy);
    myl_block *units = myl_core_list_new_slow(3, 0);
    units->len = 3;
    units = myl_core_owned_list_rotate(units, 0, 0, 1);
    units = myl_core_owned_list_reverse(units, 0);
    myl_core_drop_owned(units);
    myl_block *box = myl_core_box_new(8);
    myl_block *child = str_from("shell", 5);
    memcpy(block_data(box), &child, sizeof child);
    myl_core_box_drop_shell(box);
    if (block_data(child)[0] != 's') return 6;
    myl_core_drop_owned(child);
    myl_block *buffer = myl_core_buffer_new(0);
    buffer = myl_core_buffer_push(buffer, 7);
    myl_block *saved = myl_core_buffer_copy(buffer);
    buffer = myl_core_buffer_push(buffer, 9);
    if (saved->len != 1 || block_data(saved)[0] != 7 || buffer->len != 2) return 7;
    myl_core_drop_owned(saved);
    myl_core_drop_owned(buffer);
    if (live_count()) return 8;
    puts("owned layout copy rotate reverse transfer drop preserved");
    return 0;
}
