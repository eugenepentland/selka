/* NEW-CORE-ZERO-RC-CONTAINERS-1: generated owned copies use a bounded
   worklist at container boundaries, avoiding native stack recursion. */
/* Generated callbacks describe inline fields. Container boundaries enqueue
   work, so a recursive ownership tree never consumes the native call stack. */
typedef void (*core_owned_copier)(void *, const void *, void *);
typedef struct {
    core_owned_copier copy;
    const void *source;
    void *target;
} core_owned_copy_work;
typedef struct {
    core_owned_copy_work *items;
    size_t count, capacity;
    core_owned_copy_work local[64];
} core_owned_copy_stack;

static void core_owned_copy_push(core_owned_copy_stack *stack, core_owned_copier copy, const void *source, void *target) {
    if (!copy) return;
    if (stack->count == stack->capacity) {
        size_t capacity = stack->capacity * 2;
        if (capacity < stack->capacity || capacity > SIZE_MAX / sizeof *stack->items) out_of_memory();
        core_owned_copy_work *items = malloc(capacity * sizeof *items);
        if (!items) out_of_memory();
        memcpy(items, stack->items, stack->count * sizeof *items);
        if (stack->items != stack->local) free(stack->items);
        stack->items = items;
        stack->capacity = capacity;
    }
    stack->items[stack->count++] = (core_owned_copy_work){copy, source, target};
}

void myl_core_owned_copy_array(void *context, const void *source, void *target, core_owned_copier child, uint64_t count, uint64_t stride) {
    core_owned_copy_stack *stack = context;
    for (uint64_t i = 0; i < count; ++i)
        core_owned_copy_push(stack, child, (const unsigned char *)source + i * stride, (unsigned char *)target + i * stride);
}

void myl_core_owned_copy_leaf(const void *source, void *target) {
    myl_block *leaf = (myl_block *)value_block(source);
    if (!leaf) return;
    myl_block *copy = kind_of(leaf) == MYL_KIND_BUFFER ? myl_core_buffer_copy(leaf) : myl_core_owned_octets_copy(leaf);
    memcpy(target, &copy, sizeof copy);
}

void myl_core_owned_copy_items(void *context, const void *source, void *target, core_owned_copier child, uint64_t size, bool box) {
    const myl_block *block = value_block(source);
    if (!block) return;
    if (!box && !block->len && (block->kind & MYL_STATIC_STORAGE)) return;
    int64_t count = box ? 1 : block->len;
    myl_block *copy = box ? myl_core_box_new((int64_t)size) : block_new(MYL_KIND_LIST, count, (int64_t)size);
    copy->reserved = block->reserved;
    copy->len = block->len;
    memcpy(block_data(copy), (const unsigned char *)block + MYL_HEADER, (size_t)count * size);
    memcpy(target, &copy, sizeof copy);
    if (child) myl_core_owned_copy_array(context, (const unsigned char *)block + MYL_HEADER, block_data(copy), child, (uint64_t)count, size);
}

void myl_core_owned_copy_dictionary(void *context, const void *source, void *target, core_owned_copier key, core_owned_copier value) {
    const myl_block *block = value_block(source);
    if (!block) return;
    myl_block *copy = core_dict_copy_storage(block);
    core_dict_meta *meta = dict_meta(block);
    memcpy(target, &copy, sizeof copy);
    if (!key && !value) return;
    for (uint64_t i = 0; i < meta->elen; ++i) {
        if (!dict_live(meta, i)) continue;
        core_owned_copy_push(context, key, dict_entry(block, i), dict_entry(copy, i));
        core_owned_copy_push(context, value, dict_entry(block, i) + meta->desc->value_offset, dict_entry(copy, i) + meta->desc->value_offset);
    }
}

myl_block *myl_core_values_copy_generated(core_owned_copier root, const myl_block *source) {
    core_owned_copy_stack stack;
    stack.items = stack.local;
    stack.count = 0;
    stack.capacity = sizeof stack.local / sizeof *stack.local;
    myl_block *result = (myl_block *)source;
    core_owned_copy_push(&stack, root, &source, &result);
    while (stack.count) {
        core_owned_copy_work work = stack.items[--stack.count];
        work.copy(&stack, work.source, work.target);
    }
    if (stack.items != stack.local) free(stack.items);
    return result;
}
