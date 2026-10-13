/* NEW-CORE-ZERO-RC-CONTAINERS-1: explicit copies of recursively boxed ownership
   trees. The finite compiler descriptor graph supplies sizes and active union
   arms. A worklist avoids both compiler expansion and native stack recursion. */
typedef struct {
    const core_value_shape *shape;
    const unsigned char *source;
    unsigned char *target;
} core_copy_work;
typedef struct {
    core_copy_work *items;
    size_t count, capacity;
    core_copy_work local[64];
} core_copy_stack;

static void core_copy_push(core_copy_stack *stack, const core_value_shape *shape, const void *source, void *target) {
    if (!shape->size) return;
    if (stack->count == stack->capacity) {
        size_t capacity = stack->capacity * 2;
        if (capacity < stack->capacity || capacity > SIZE_MAX / sizeof *stack->items) out_of_memory();
        core_copy_work *items = malloc(capacity * sizeof *items);
        if (!items) out_of_memory();
        memcpy(items, stack->items, stack->count * sizeof *items);
        if (stack->items != stack->local) free(stack->items);
        stack->items = items;
        stack->capacity = capacity;
    }
    stack->items[stack->count++] = (core_copy_work){shape, source, target};
}

static myl_block *core_copy_container(core_copy_stack *stack, const core_value_shape *shape, const myl_block *source) {
    if (shape->kind == 9) {
        myl_block *copy = core_dict_copy_storage(source);
        core_dict_meta *meta = dict_meta(source);
        for (uint64_t i = 0; i < meta->elen; ++i) {
            if (!dict_live(meta, i)) continue;
            core_copy_push(stack, shape->children[0], dict_entry(source, i), dict_entry(copy, i));
            core_copy_push(stack, shape->children[1], dict_entry(source, i) + meta->desc->value_offset, dict_entry(copy, i) + meta->desc->value_offset);
        }
        return copy;
    }
    const core_value_shape *child = shape->children[0];
    int64_t count = shape->kind == 6 ? 1 : source->len;
    myl_block *copy = shape->kind == 6 ? myl_core_box_new(child->size) : block_new(MYL_KIND_LIST, count, child->size);
    copy->reserved = source->reserved;
    copy->len = source->len;
    /* Immediate primitive list elements need initialization, but no child walk. */
    if (shape->kind == 7 && child->kind <= 2) {
        size_t bytes = block_data_size(count, child->size, false);
        if (bytes) memcpy(block_data(copy), (const unsigned char *)source + MYL_HEADER, bytes);
        return copy;
    }
    for (int64_t i = 0; i < count; ++i)
        core_copy_push(stack, child, (const unsigned char *)source + MYL_HEADER + (size_t)i * child->size, block_data(copy) + (size_t)i * child->size);
    return copy;
}

myl_block *myl_core_values_copy_box(const core_value_shape *root, const myl_block *source) {
    core_copy_stack stack = {0};
    stack.items = stack.local;
    stack.capacity = sizeof stack.local / sizeof *stack.local;
    myl_block *result = NULL;
    core_copy_push(&stack, root, &source, &result);
    while (stack.count) {
        core_copy_work work = stack.items[--stack.count];
        const core_value_shape *shape = work.shape;
        memcpy(work.target, work.source, shape->size);
        switch (shape->kind) {
        case 0: case 1: case 2: break;
        case 3: {
            myl_block *leaf = (myl_block *)value_block(work.source);
            if (!leaf) break;
            myl_block *copy = kind_of(leaf) == MYL_KIND_BUFFER ? myl_core_buffer_copy(leaf) : myl_core_owned_octets_copy(leaf);
            memcpy(work.target, &copy, sizeof copy);
            break;
        }
        case 4:
            for (uint32_t i = 0; i < shape->count; ++i)
                core_copy_push(&stack, shape->children[i], work.source + shape->offsets[i], work.target + shape->offsets[i]);
            break;
        case 5: {
            uint64_t tag = value_tag(shape, work.source);
            if (tag >= shape->count) abort();
            size_t offset = shape->aux ? 0 : 8;
            core_copy_push(&stack, shape->children[tag], work.source + offset, work.target + offset);
            break;
        }
        case 6: case 7: case 9: {
            const myl_block *block = value_block(work.source);
            if (!block) break;
            myl_block *copy = core_copy_container(&stack, shape, block);
            memcpy(work.target, &copy, sizeof copy);
            break;
        }
        case 8:
            for (uint32_t i = 0; i < shape->count; ++i) {
                size_t offset = (size_t)i * shape->children[0]->size;
                core_copy_push(&stack, shape->children[0], work.source + offset, work.target + offset);
            }
            break;
        case 10:
            if (shape->aux == 1) break; /* Function pointer, not a resource. */
            abort();
        default: abort(); /* Resources cannot be duplicated. */
        }
    }
    if (stack.items != stack.local) free(stack.items);
    return result;
}
