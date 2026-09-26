#include "native_rc_internal.h"
#include <string.h>

typedef struct {
    const myl_rc_shape *source;
    size_t cursor, depth;
    unsigned color;
} shape_node;
typedef struct {
    myl_native_heap *heap;
    shape_node *nodes;
    size_t *slots;
    size_t count, capacity;
    size_t fields;
} shape_builder;
static size_t pointer_hash(const void *pointer) {
    uintptr_t value = (uintptr_t)pointer >> 3;
    value ^= value >> 30;
    value *= UINT64_C(0xbf58476d1ce4e5b9);
    value ^= value >> 27;
    return (size_t)value;
}
static size_t builder_slot(const shape_builder *builder, const myl_rc_shape *shape) {
    size_t slot = pointer_hash(shape) & (builder->capacity * 2 - 1);
    while (builder->slots[slot] && builder->nodes[builder->slots[slot] - 1].source != shape)
        slot = (slot + 1) & (builder->capacity * 2 - 1);
    return slot;
}
static int builder_grow(shape_builder *builder) {
    size_t capacity = builder->capacity ? builder->capacity * 2 : 16;
    size_t node_bytes, slot_bytes;
    if (capacity < builder->capacity || !myl_rc_size_mul(capacity, sizeof(shape_node), &node_bytes) ||
        !myl_rc_size_mul(capacity, 2 * sizeof(size_t), &slot_bytes)) return 0;
    shape_node *nodes = myl_rc_meta_alloc(builder->heap, node_bytes);
    if (!nodes) return 0;
    size_t *slots = myl_rc_meta_alloc(builder->heap, slot_bytes);
    if (!slots) { myl_rc_meta_free(builder->heap, nodes, node_bytes); return 0; }
    if (builder->count) memcpy(nodes, builder->nodes, builder->count * sizeof *nodes);
    myl_rc_meta_free(builder->heap, builder->nodes, builder->capacity * sizeof *nodes);
    myl_rc_meta_free(builder->heap, builder->slots, builder->capacity * 2 * sizeof *slots);
    builder->nodes = nodes;
    builder->slots = slots;
    builder->capacity = capacity;
    for (size_t i = 0; i < builder->count; ++i)
        slots[builder_slot(builder, nodes[i].source)] = i + 1;
    return 1;
}
static int builder_add(shape_builder *builder, const myl_rc_shape *shape) {
    myl_rc_invariant(shape != NULL);
    if (builder->capacity && builder->slots[builder_slot(builder, shape)]) return 1;
    if (builder->count == builder->capacity && !builder_grow(builder)) return 0;
    size_t slot = builder_slot(builder, shape);
    builder->nodes[builder->count].source = shape;
    builder->slots[slot] = ++builder->count;
    return 1;
}
static size_t child_count(const myl_rc_shape *shape) {
    switch (shape->kind) {
        case MYL_RC_SHAPE_NONE: case MYL_RC_SHAPE_POINTER: return 0;
        case MYL_RC_SHAPE_RECORD: return shape->as.record.count;
        case MYL_RC_SHAPE_ARRAY: return shape->as.array.count ? 1 : 0;
        case MYL_RC_SHAPE_VARIANT: return shape->as.variant.count;
    }
    myl_rc_invariant(0);
    return 0;
}
static const myl_rc_field *shape_fields(const myl_rc_shape *shape) {
    return shape->kind == MYL_RC_SHAPE_RECORD ? shape->as.record.fields : shape->as.variant.fields;
}
static const myl_rc_shape *child_shape(const myl_rc_shape *shape, size_t index) {
    if (shape->kind == MYL_RC_SHAPE_ARRAY) return shape->as.array.element;
    return shape_fields(shape)[index].shape;
}
/* Validate the physical extent before touching any child address at runtime. */
static int validate_shape(shape_builder *builder, const myl_rc_shape *shape) {
    size_t children = child_count(shape), extent;
    if (shape->kind == MYL_RC_SHAPE_POINTER) myl_rc_invariant(shape->size == sizeof(void *));
    if (shape->kind == MYL_RC_SHAPE_ARRAY) {
        if (!children) return 1;
        myl_rc_invariant(shape->as.array.element != NULL);
        myl_rc_invariant(shape->as.array.stride >= shape->as.array.element->size);
        if (!myl_rc_size_mul(shape->as.array.count - 1, shape->as.array.stride, &extent) ||
            !myl_rc_size_add(extent, shape->as.array.element->size, &extent)) return 0;
        myl_rc_invariant(extent <= shape->size);
    } else if (shape->kind == MYL_RC_SHAPE_RECORD || shape->kind == MYL_RC_SHAPE_VARIANT) {
        const myl_rc_field *fields = shape_fields(shape);
        myl_rc_invariant(!children || fields);
        if (shape->kind == MYL_RC_SHAPE_VARIANT) {
            if (!myl_rc_size_add(shape->as.variant.tag_offset, sizeof(uint32_t), &extent)) return 0;
            myl_rc_invariant(extent <= shape->size);
        }
        if (!myl_rc_size_add(builder->fields, children, &builder->fields)) return 0;
        for (size_t i = 0; i < children; ++i) {
            myl_rc_invariant(fields[i].shape != NULL);
            if (!myl_rc_size_add(fields[i].offset, fields[i].shape->size, &extent)) return 0;
            myl_rc_invariant(extent <= shape->size);
        }
    }
    for (size_t i = 0; i < children; ++i)
        if (!builder_add(builder, child_shape(shape, i))) return 0;
    return 1;
}
static int compute_depths(shape_builder *builder, size_t *maximum) {
    size_t bytes;
    if (!myl_rc_size_mul(builder->count, sizeof(size_t), &bytes)) return 0;
    size_t *stack = bytes ? myl_rc_meta_alloc(builder->heap, bytes) : NULL;
    if (bytes && !stack) return 0;
    *maximum = 0;
    for (size_t root = 0; root < builder->count; ++root) {
        if (builder->nodes[root].color == 2) continue;
        size_t used = 1;
        stack[0] = root;
        while (used) {
            shape_node *node = &builder->nodes[stack[used - 1]];
            node->color = 1;
            if (node->cursor < child_count(node->source)) {
                const myl_rc_shape *child = child_shape(node->source, node->cursor);
                size_t index = builder->slots[builder_slot(builder, child)] - 1;
                shape_node *next = &builder->nodes[index];
                myl_rc_invariant(next->color != 1); /* inline cycles are invalid */
                if (next->color == 0) { stack[used++] = index; continue; }
                if (next->depth > node->depth) node->depth = next->depth;
                ++node->cursor;
            } else {
                if (node->source->kind == MYL_RC_SHAPE_POINTER) node->depth = 1;
                else if (node->depth) ++node->depth;
                if (node->depth > *maximum) *maximum = node->depth;
                node->color = 2;
                --used;
            }
        }
    }
    myl_rc_meta_free(builder->heap, stack, bytes);
    return 1;
}
static const myl_rc_shape *copied_shape(const shape_builder *builder, const myl_rc_batch *batch,
                                       const myl_rc_shape *source) {
    size_t index = builder->slots[builder_slot(builder, source)] - 1;
    return &batch->shapes[index].shape;
}
static void batch_index(myl_rc_batch *batch, const myl_rc_shape *key, size_t index) {
    size_t slot = pointer_hash(key) & (batch->lookup.capacity - 1);
    while (batch->lookup.slots[slot]) slot = (slot + 1) & (batch->lookup.capacity - 1);
    batch->lookup.slots[slot] = index + 1;
}
/* One reservation keeps all copied metadata addresses stable until teardown. */
static myl_rc_batch *build_batch(shape_builder *builder, const myl_rc_module *module) {
    size_t shape_bytes, field_bytes, descriptor_bytes, slot_bytes, bytes = sizeof(myl_rc_batch);
    size_t descriptors = module ? module->descriptor_count : 0;
    if (!myl_rc_size_mul(builder->count, sizeof(myl_rc_shape_entry), &shape_bytes) ||
        !myl_rc_size_mul(builder->fields, sizeof(myl_rc_field), &field_bytes) ||
        !myl_rc_size_mul(descriptors, sizeof(myl_rc_descriptor), &descriptor_bytes) ||
        !myl_rc_size_mul(builder->capacity, 4 * sizeof(size_t), &slot_bytes) ||
        !myl_rc_size_add(bytes, shape_bytes, &bytes) || !myl_rc_size_add(bytes, field_bytes, &bytes) ||
        !myl_rc_size_add(bytes, descriptor_bytes, &bytes) || !myl_rc_size_add(bytes, slot_bytes, &bytes)) return NULL;
    myl_rc_batch *batch = myl_rc_meta_alloc(builder->heap, bytes);
    if (!batch) return NULL;
    batch->module = module;
    batch->count.shapes = builder->count;
    batch->count.descriptors = descriptors;
    batch->bytes = bytes;
    batch->shapes = (myl_rc_shape_entry *)(batch + 1);
    myl_rc_field *fields = (myl_rc_field *)((unsigned char *)batch->shapes + shape_bytes);
    batch->descriptors = (myl_rc_descriptor *)((unsigned char *)fields + field_bytes);
    batch->lookup.slots = (size_t *)((unsigned char *)batch->descriptors + descriptor_bytes);
    batch->lookup.capacity = builder->capacity * 4;
    for (size_t i = 0; i < builder->count; ++i) {
        const myl_rc_shape *source = builder->nodes[i].source;
        myl_rc_shape_entry *entry = &batch->shapes[i];
        entry->source = module ? source : NULL;
        entry->shape = *source;
        entry->depth = builder->nodes[i].depth;
        if (!entry->depth) entry->shape.kind = MYL_RC_SHAPE_NONE;
        if (source->kind == MYL_RC_SHAPE_ARRAY && source->as.array.count)
            entry->shape.as.array.element = copied_shape(builder, batch, source->as.array.element);
        if (source->kind == MYL_RC_SHAPE_RECORD || source->kind == MYL_RC_SHAPE_VARIANT) {
            size_t count = child_count(source);
            const myl_rc_field *original = shape_fields(source);
            for (size_t j = 0; j < count; ++j) {
                fields[j] = original[j];
                fields[j].shape = copied_shape(builder, batch, original[j].shape);
            }
            if (source->kind == MYL_RC_SHAPE_RECORD) entry->shape.as.record.fields = fields;
            else entry->shape.as.variant.fields = fields;
            fields += count;
        }
        batch_index(batch, &entry->shape, i);
        if (module) batch_index(batch, source, i);
    }
    for (size_t i = 0; i < descriptors; ++i) {
        batch->descriptors[i] = module->descriptors[i];
        batch->descriptors[i].shape = copied_shape(builder, batch, module->descriptors[i].shape);
    }
    return batch;
}
static void builder_free(shape_builder *builder) {
    myl_rc_meta_free(builder->heap, builder->nodes, builder->capacity * sizeof(shape_node));
    myl_rc_meta_free(builder->heap, builder->slots, builder->capacity * 2 * sizeof(size_t));
}
static myl_rc_status register_shapes(shape_builder *builder, const myl_rc_module *module,
                                      const myl_rc_shape **out) {
    myl_native_heap *heap = builder->heap;
    size_t maximum;
    for (size_t i = 0; i < builder->count; ++i)
        if (!validate_shape(builder, builder->nodes[i].source)) return MYL_RC_ALLOCATION_REFUSED;
    if (!compute_depths(builder, &maximum)) return MYL_RC_ALLOCATION_REFUSED;
    myl_rc_batch *batch = build_batch(builder, module);
    if (!batch) return MYL_RC_ALLOCATION_REFUSED;
    myl_rc_frame *frames = NULL;
    if (maximum > heap->rc->walk.capacity) {
        size_t bytes;
        if (!myl_rc_size_mul(maximum, sizeof(myl_rc_frame), &bytes) || !(frames = myl_rc_meta_alloc(heap, bytes))) {
            myl_rc_meta_free(heap, batch, batch->bytes);
            return MYL_RC_ALLOCATION_REFUSED;
        }
    }
    /* No fallible work after this point. Old values always retain a complete
     * stack until the replacement metadata and stack can commit together. */
    if (frames) {
        myl_rc_meta_free(heap, heap->rc->walk.frames, heap->rc->walk.capacity * sizeof(myl_rc_frame));
        heap->rc->walk.frames = frames;
        heap->rc->walk.capacity = maximum;
    }
    batch->next = heap->rc->metadata.batches;
    heap->rc->metadata.batches = batch;
    if (out) *out = &batch->shapes[0].shape;
    return MYL_RC_OK;
}
myl_rc_status myl_rc_module_register(myl_native_heap *heap, const myl_rc_module *module) {
    myl_rc_invariant(heap && heap->rc && module && module->abi == MYL_RC_ABI_VERSION && !heap->rc->walk.depth);
    for (myl_rc_batch *batch = heap->rc->metadata.batches; batch; batch = batch->next)
        if (batch->module == module) return MYL_RC_OK;
    myl_rc_invariant(!module->shape_count || module->shapes);
    myl_rc_invariant(!module->descriptor_count || module->descriptors);
    shape_builder builder = {.heap = heap};
    myl_rc_status status = MYL_RC_ALLOCATION_REFUSED;
    for (size_t i = 0; i < module->shape_count; ++i)
        if (!builder_add(&builder, module->shapes[i])) goto done;
    for (size_t i = 0; i < module->descriptor_count; ++i) {
        const myl_rc_descriptor *descriptor = &module->descriptors[i];
        myl_rc_invariant(descriptor->type && descriptor->shape && descriptor->type->size == descriptor->shape->size);
        myl_rc_invariant(!myl_rc_descriptor_find(heap, descriptor->type));
        for (size_t j = 0; j < i; ++j) myl_rc_invariant(module->descriptors[j].type != descriptor->type);
        if (!builder_add(&builder, descriptor->shape)) goto done;
    }
    status = register_shapes(&builder, module, NULL);
done:
    builder_free(&builder);
    return status;
}
myl_rc_status myl_rc_shape_import(myl_native_heap *heap, const myl_rc_shape *source, const myl_rc_shape **out) {
    myl_rc_invariant(heap && heap->rc && source && out && !heap->rc->walk.depth);
    *out = NULL;
    shape_builder builder = {.heap = heap};
    myl_rc_status status = MYL_RC_ALLOCATION_REFUSED;
    if (builder_add(&builder, source)) status = register_shapes(&builder, NULL, out);
    builder_free(&builder);
    return status;
}
const myl_rc_shape *myl_rc_shape_resolve(const myl_native_heap *heap, const myl_rc_shape *source) {
    if (!heap || !heap->rc || !source) return NULL;
    for (myl_rc_batch *batch = heap->rc->metadata.batches; batch; batch = batch->next) {
        if (!batch->lookup.capacity) continue;
        size_t slot = pointer_hash(source) & (batch->lookup.capacity - 1);
        while (batch->lookup.slots[slot]) {
            myl_rc_shape_entry *entry = &batch->shapes[batch->lookup.slots[slot] - 1];
            if (source == entry->source || source == &entry->shape) return &entry->shape;
            slot = (slot + 1) & (batch->lookup.capacity - 1);
        }
    }
    return NULL;
}
const myl_rc_descriptor *myl_rc_descriptor_find(const myl_native_heap *heap, const myl_native_type *type) {
    if (!heap || !heap->rc) return NULL;
    for (myl_rc_batch *batch = heap->rc->metadata.batches; batch; batch = batch->next)
        for (size_t i = 0; i < batch->count.descriptors; ++i)
            if (batch->descriptors[i].type == type) return &batch->descriptors[i];
    return NULL;
}

myl_rc_status myl_rc_descriptor_register(myl_native_heap *heap, const myl_rc_descriptor *descriptor) {
    myl_rc_invariant(heap && heap->rc && descriptor && descriptor->type && !heap->rc->walk.depth);
    const myl_rc_shape *shape = myl_rc_shape_resolve(heap, descriptor->shape);
    myl_rc_invariant(shape && shape->size == descriptor->type->size);
    const myl_rc_descriptor *old = myl_rc_descriptor_find(heap, descriptor->type);
    if (old) {
        myl_rc_invariant(old->shape == shape && old->edges == descriptor->edges && old->finalize == descriptor->finalize);
        return MYL_RC_OK;
    }
    size_t bytes = sizeof(myl_rc_batch) + sizeof(myl_rc_descriptor);
    myl_rc_batch *batch = myl_rc_meta_alloc(heap, bytes);
    if (!batch) return MYL_RC_ALLOCATION_REFUSED;
    batch->bytes = bytes;
    batch->count.descriptors = 1;
    batch->descriptors = (myl_rc_descriptor *)(batch + 1);
    batch->descriptors[0] = *descriptor;
    batch->descriptors[0].shape = shape;
    batch->next = heap->rc->metadata.batches;
    heap->rc->metadata.batches = batch;
    return MYL_RC_OK;
}
