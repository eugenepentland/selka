#include "native_rc_internal.h"
#include <string.h>

typedef struct {
    const myl_rc_shape *source;
    size_t cursor, depth, inline_depth;
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
enum { INDEX_SHAPE = 1, INDEX_DESCRIPTOR = 2, INDEX_MODULE = 3 };
static size_t index_slot(const myl_rc_index_entry *entries, size_t capacity, const void *key, unsigned kind) {
    size_t slot = (pointer_hash(key) ^ kind) & (capacity - 1);
    while (entries[slot].key && (entries[slot].key != key || entries[slot].kind != kind))
        slot = (slot + 1) & (capacity - 1);
    return slot;
}
static const myl_rc_index_entry *index_find(const myl_native_heap *heap, const void *key, unsigned kind) {
    if (!heap || !heap->rc || !key || !heap->rc->metadata.index.capacity) return NULL;
    size_t slot = index_slot(heap->rc->metadata.index.entries, heap->rc->metadata.index.capacity, key, kind);
    return heap->rc->metadata.index.entries[slot].key ? &heap->rc->metadata.index.entries[slot] : NULL;
}
static int index_prepare(myl_native_heap *heap, size_t additional, myl_rc_index_entry **out, size_t *capacity) {
    *out = NULL;
    *capacity = heap->rc->metadata.index.capacity;
    size_t needed, bytes;
    if (!myl_rc_size_add(heap->rc->metadata.index.count, additional, &needed)) return 0;
    if (needed <= *capacity / 2) return 1;
    if (!*capacity) *capacity = 32;
    while (needed > *capacity / 2) {
        if (*capacity > SIZE_MAX / 2) return 0;
        *capacity *= 2;
    }
    if (!myl_rc_size_mul(*capacity, sizeof(myl_rc_index_entry), &bytes)) return 0;
    myl_rc_index_entry *entries = myl_rc_meta_alloc(heap, bytes);
    if (!entries) return 0;
    for (size_t i = 0; i < heap->rc->metadata.index.capacity; ++i) {
        myl_rc_index_entry old = heap->rc->metadata.index.entries[i];
        old.recent_descriptor = 0; /* Hints name slots in the previous table. */
        if (old.key) entries[index_slot(entries, *capacity, old.key, old.kind)] = old;
    }
    *out = entries;
    return 1;
}
static void index_insert(myl_native_heap *heap, myl_rc_index_entry entry) {
    size_t slot = index_slot(heap->rc->metadata.index.entries, heap->rc->metadata.index.capacity, entry.key, entry.kind);
    if (heap->rc->metadata.index.entries[slot].key) return;
    heap->rc->metadata.index.entries[slot] = entry;
    ++heap->rc->metadata.index.count;
}
static void index_commit(myl_native_heap *heap, myl_rc_batch *batch, myl_rc_index_entry *grown, size_t capacity) {
    if (grown) {
        myl_rc_meta_free(heap, heap->rc->metadata.index.entries, heap->rc->metadata.index.capacity * sizeof *grown);
        heap->rc->metadata.index.entries = grown;
        heap->rc->metadata.index.capacity = capacity;
    }
    if (batch->module)
        index_insert(heap, (myl_rc_index_entry){.key = batch->module, .value = batch, .kind = INDEX_MODULE});
    for (size_t i = 0; i < batch->count.shapes; ++i) {
        const myl_rc_shape_entry *shape = &batch->shapes[i];
        index_insert(heap, (myl_rc_index_entry){.key = &shape->shape, .value = &shape->shape, .depth = shape->depth, .inline_depth = shape->inline_depth, .kind = INDEX_SHAPE});
        if (shape->source)
            index_insert(heap, (myl_rc_index_entry){.key = shape->source, .value = &shape->shape, .depth = shape->depth, .inline_depth = shape->inline_depth, .kind = INDEX_SHAPE});
    }
    for (size_t i = 0; i < batch->count.descriptors; ++i) {
        const myl_rc_descriptor *descriptor = &batch->bindings[i].descriptor;
        index_insert(heap, (myl_rc_index_entry){.key = descriptor->type, .value = descriptor, .kind = INDEX_DESCRIPTOR});
    }
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
        case MYL_RC_SHAPE_NONE: case MYL_RC_SHAPE_POINTER: case MYL_RC_SHAPE_HOLD_POINTER: return 0;
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
    if (shape->kind == MYL_RC_SHAPE_POINTER || shape->kind == MYL_RC_SHAPE_HOLD_POINTER) myl_rc_invariant(shape->size == sizeof(void *));
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
                if (next->inline_depth > node->inline_depth) node->inline_depth = next->inline_depth;
                ++node->cursor;
            } else {
                if (node->source->kind == MYL_RC_SHAPE_POINTER || node->source->kind == MYL_RC_SHAPE_HOLD_POINTER) node->depth = 1;
                else if (node->depth) ++node->depth;
                ++node->inline_depth;
                const myl_rc_index_entry *known = index_find(builder->heap, node->source, INDEX_SHAPE);
                if (known && known->inline_depth > node->inline_depth) node->inline_depth = known->inline_depth;
                if (node->inline_depth > *maximum) *maximum = node->inline_depth;
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
typedef struct {
    const myl_native_type *type;
    const myl_rc_shape *shape;
    size_t offset, cursor;
} flat_frame;
/* This is admission to an optional optimization, not a type-depth limit.
 * Bounded inspection refuses deep/wide metadata and keeps the general walker.
 * The GC scan plan alone cannot distinguish O from H or raw unique resources. */
static void flat_build(myl_rc_binding *binding) {
    const myl_rc_descriptor *descriptor = &binding->descriptor;
    myl_rc_flat *flat = &binding->flat;
    flat->count = MYL_RC_FLAT_LEAVES + 1;
    flat->loanable = 0;
    if (descriptor->edges || descriptor->finalize || descriptor->clone || descriptor->shell || descriptor->next) return;
    flat_frame frames[16] = {{.type = descriptor->type, .shape = descriptor->shape}};
    size_t depth = 1, inspected = 0;
    unsigned count = 0, loanable = 1;
    while (depth) {
        /* Root counts as a frame. Stay within the generic loan visitor's
         * eight local frames; deeper loans retain its allocation/refusal. */
        if (depth > 8) loanable = 0;
        if (++inspected > 128) return;
        flat_frame *frame = &frames[depth - 1];
        const myl_native_type *type = frame->type;
        const myl_rc_shape *shape = frame->shape;
        if (!type || (shape && type->size != shape->size)) return;
        unsigned kind = shape ? shape->kind : MYL_RC_SHAPE_NONE;
        if (type->kind == MYL_NATIVE_PLAIN || type->kind == MYL_NATIVE_FLOAT) {
            if (kind != MYL_RC_SHAPE_NONE) return;
            --depth;
            continue;
        }
        if (type->kind == MYL_NATIVE_POINTER) {
            /* Even NULL boxes can carry a native unique-body obligation.
             * Refuse every typed box rather than depend on module order. */
            if (type->collection_kind == 5 && type->element) loanable = 0;
            if (kind != MYL_RC_SHAPE_POINTER || type->size != sizeof(void *) || count == MYL_RC_FLAT_LEAVES) return;
            for (unsigned i = 0; i < count; ++i) {
                size_t old = flat->offsets[i], next = frame->offset;
                if (old > next ? old - next < sizeof(void *) : next - old < sizeof(void *)) return;
            }
            flat->offsets[count++] = frame->offset;
            --depth;
            continue;
        }
        const myl_native_type *child;
        const myl_rc_shape *child_shape = NULL;
        size_t offset;
        if (type->kind == MYL_NATIVE_RECORD) {
            if (kind != MYL_RC_SHAPE_RECORD && kind != MYL_RC_SHAPE_NONE) return;
            if (kind == MYL_RC_SHAPE_RECORD && type->field_count != shape->as.record.count) return;
            if (frame->cursor == type->field_count) { --depth; continue; }
            if (!type->fields) return;
            size_t index = frame->cursor++;
            child = type->fields[index].type;
            offset = type->fields[index].offset;
            if (kind == MYL_RC_SHAPE_RECORD) {
                if (offset != shape->as.record.fields[index].offset) return;
                child_shape = shape->as.record.fields[index].shape;
            }
        } else if (type->kind == MYL_NATIVE_ARRAY) {
            if (kind != MYL_RC_SHAPE_ARRAY && kind != MYL_RC_SHAPE_NONE) return;
            if (kind == MYL_RC_SHAPE_ARRAY && (type->count != shape->as.array.count || type->stride != shape->as.array.stride)) return;
            if (frame->cursor == type->count) { --depth; continue; }
            child = type->element;
            if (!myl_rc_size_mul(frame->cursor++, type->stride, &offset)) return;
            if (kind == MYL_RC_SHAPE_ARRAY) child_shape = shape->as.array.element;
        } else return; /* Includes variants, owned buffers/pools and raw resources. */
        if (depth == sizeof frames / sizeof frames[0] || !child || offset > type->size || child->size > type->size - offset) return;
        if (!myl_rc_size_add(frame->offset, offset, &offset)) return;
        frames[depth++] = (flat_frame){.type = child, .shape = child_shape, .offset = offset};
    }
    flat->count = count;
    flat->loanable = loanable;
}
/* One reservation keeps all copied metadata addresses stable until teardown. */
static myl_rc_batch *build_batch(shape_builder *builder, const myl_rc_module *module, int persistent) {
    size_t shape_bytes, field_bytes, descriptor_bytes, bytes = sizeof(myl_rc_batch);
    size_t descriptors = module ? module->descriptor_count : 0;
    if (!myl_rc_size_mul(builder->count, sizeof(myl_rc_shape_entry), &shape_bytes) ||
        !myl_rc_size_mul(builder->fields, sizeof(myl_rc_field), &field_bytes) ||
        !myl_rc_size_mul(descriptors, sizeof(myl_rc_binding), &descriptor_bytes) ||
        !myl_rc_size_add(bytes, shape_bytes, &bytes) || !myl_rc_size_add(bytes, field_bytes, &bytes) ||
        !myl_rc_size_add(bytes, descriptor_bytes, &bytes)) return NULL;
    myl_rc_batch *batch = myl_rc_meta_alloc(builder->heap, bytes);
    if (!batch) return NULL;
    batch->module = persistent ? module : NULL;
    batch->count.shapes = builder->count;
    batch->count.descriptors = descriptors;
    batch->bytes = bytes;
    batch->shapes = (myl_rc_shape_entry *)(batch + 1);
    myl_rc_field *fields = (myl_rc_field *)((unsigned char *)batch->shapes + shape_bytes);
    batch->bindings = (myl_rc_binding *)((unsigned char *)fields + field_bytes);
    for (size_t i = 0; i < builder->count; ++i) {
        const myl_rc_shape *source = builder->nodes[i].source;
        myl_rc_shape_entry *entry = &batch->shapes[i];
        entry->source = persistent ? source : NULL;
        entry->shape = *source;
        entry->depth = builder->nodes[i].depth;
        entry->inline_depth = builder->nodes[i].inline_depth;
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
    }
    for (size_t i = 0; i < descriptors; ++i) {
        batch->bindings[i].descriptor = module->descriptors[i];
        batch->bindings[i].descriptor.shape = copied_shape(builder, batch, module->descriptors[i].shape);
        flat_build(&batch->bindings[i]);
    }
    return batch;
}
static void builder_free(shape_builder *builder) {
    myl_rc_meta_free(builder->heap, builder->nodes, builder->capacity * sizeof(shape_node));
    myl_rc_meta_free(builder->heap, builder->slots, builder->capacity * 2 * sizeof(size_t));
}
static myl_rc_status register_shapes(shape_builder *builder, const myl_rc_module *module,
                                      const myl_rc_shape **out, int persistent) {
    myl_native_heap *heap = builder->heap;
    size_t maximum;
    for (size_t i = 0; i < builder->count; ++i)
        if (!validate_shape(builder, builder->nodes[i].source)) return MYL_RC_ALLOCATION_REFUSED;
    if (!compute_depths(builder, &maximum)) return MYL_RC_ALLOCATION_REFUSED;
    myl_rc_batch *batch = build_batch(builder, module, persistent);
    if (!batch) return MYL_RC_ALLOCATION_REFUSED;
    myl_rc_frame *frames = NULL;
    if (maximum > heap->rc->walk.capacity) {
        size_t bytes;
        if (!myl_rc_size_mul(maximum, sizeof(myl_rc_frame), &bytes) || !(frames = myl_rc_meta_alloc(heap, bytes))) {
            myl_rc_meta_free(heap, batch, batch->bytes);
            return MYL_RC_ALLOCATION_REFUSED;
        }
    }
    size_t keys, capacity;
    myl_rc_index_entry *grown;
    if (!myl_rc_size_mul(batch->count.shapes, persistent ? 2 : 1, &keys) ||
        !myl_rc_size_add(keys, batch->count.descriptors, &keys) ||
        !myl_rc_size_add(keys, persistent ? 1 : 0, &keys) || !index_prepare(heap, keys, &grown, &capacity)) {
        myl_rc_meta_free(heap, frames, maximum * sizeof(myl_rc_frame));
        myl_rc_meta_free(heap, batch, batch->bytes);
        return MYL_RC_ALLOCATION_REFUSED;
    }
    /* No fallible work after this point. Old values always retain a complete
     * stack until the replacement metadata, index and stack commit together. */
    index_commit(heap, batch, grown, capacity);
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
    if (index_find(heap, module, INDEX_MODULE)) return MYL_RC_OK;
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
    status = register_shapes(&builder, module, NULL, 1);
done:
    builder_free(&builder);
    return status;
}
myl_rc_status myl_rc_shape_import(myl_native_heap *heap, const myl_rc_shape *source, const myl_rc_shape **out) {
    myl_rc_invariant(heap && heap->rc && source && out && !heap->rc->walk.depth);
    *out = NULL;
    shape_builder builder = {.heap = heap};
    myl_rc_status status = MYL_RC_ALLOCATION_REFUSED;
    if (builder_add(&builder, source)) status = register_shapes(&builder, NULL, out, 0);
    builder_free(&builder);
    return status;
}
const myl_rc_shape *myl_rc_shape_resolve(const myl_native_heap *heap, const myl_rc_shape *source) {
    const myl_rc_index_entry *entry = index_find(heap, source, INDEX_SHAPE);
    return entry ? entry->value : NULL;
}
size_t myl_rc_shape_depth(const myl_native_heap *heap, const myl_rc_shape *source) {
    const myl_rc_index_entry *entry = index_find(heap, source, INDEX_SHAPE);
    myl_rc_invariant(entry != NULL);
    return entry->depth;
}
const myl_rc_descriptor *myl_rc_descriptor_find(const myl_native_heap *heap, const myl_native_type *type) {
    const myl_rc_index_entry *entry = index_find(heap, type, INDEX_DESCRIPTOR);
    return entry ? entry->value : NULL;
}
/* Opt-in repeat identity for scalar room-append admission. General lookups
 * retain the original path and neither pay for nor evict this hint. */
const myl_rc_descriptor *myl_rc_descriptor_repeat(const myl_native_heap *heap, const myl_native_type *type) {
    if (!heap || !heap->rc || !type || !heap->rc->metadata.index.capacity) return NULL;
    myl_rc_index_entry *entries = heap->rc->metadata.index.entries;
    unsigned recent = entries[0].recent_descriptor;
    if (recent && (size_t)recent <= heap->rc->metadata.index.capacity) {
        const myl_rc_index_entry *cached = &entries[recent - 1];
        if (cached->key == type && cached->kind == INDEX_DESCRIPTOR) return cached->value;
    }
    const myl_rc_index_entry *entry = index_find(heap, type, INDEX_DESCRIPTOR);
    if (entry) {
        size_t slot = (size_t)(entry - entries);
        entries[0].recent_descriptor = slot < UINT32_MAX ? (unsigned)(slot + 1) : 0;
    }
    return entry ? entry->value : NULL;
}

myl_rc_status myl_rc_descriptor_register(myl_native_heap *heap, const myl_rc_descriptor *descriptor) {
    myl_rc_invariant(heap && heap->rc && descriptor && descriptor->type && !heap->rc->walk.depth);
    const myl_rc_shape *shape = myl_rc_shape_resolve(heap, descriptor->shape);
    myl_rc_invariant(shape && shape->size == descriptor->type->size);
    const myl_rc_descriptor *old = myl_rc_descriptor_find(heap, descriptor->type);
    if (old) {
        myl_rc_invariant(old->shape == shape && old->edges == descriptor->edges && old->finalize == descriptor->finalize && old->clone == descriptor->clone && old->shell == descriptor->shell && old->next == descriptor->next);
        return MYL_RC_OK;
    }
    size_t bytes = sizeof(myl_rc_batch) + sizeof(myl_rc_binding);
    myl_rc_batch *batch = myl_rc_meta_alloc(heap, bytes);
    if (!batch) return MYL_RC_ALLOCATION_REFUSED;
    batch->bytes = bytes;
    batch->count.descriptors = 1;
    batch->bindings = (myl_rc_binding *)(batch + 1);
    batch->bindings[0].descriptor = *descriptor;
    batch->bindings[0].descriptor.shape = shape;
    flat_build(&batch->bindings[0]);
    myl_rc_index_entry *grown;
    size_t capacity;
    if (!index_prepare(heap, 1, &grown, &capacity)) {
        myl_rc_meta_free(heap, batch, bytes);
        return MYL_RC_ALLOCATION_REFUSED;
    }
    index_commit(heap, batch, grown, capacity);
    batch->next = heap->rc->metadata.batches;
    heap->rc->metadata.batches = batch;
    return MYL_RC_OK;
}

myl_rc_status myl_rc_descriptor_import(myl_native_heap *heap, const myl_rc_descriptor *descriptor) {
    myl_rc_invariant(heap && heap->rc && descriptor && descriptor->type && descriptor->shape && !heap->rc->walk.depth);
    myl_rc_invariant(descriptor->shape->size == descriptor->type->size);
    const myl_rc_descriptor *old = myl_rc_descriptor_find(heap, descriptor->type);
    if (old) {
        myl_rc_invariant(old->edges == descriptor->edges && old->finalize == descriptor->finalize && old->clone == descriptor->clone && old->shell == descriptor->shell && old->next == descriptor->next);
        return MYL_RC_OK;
    }
    const myl_rc_module module = {.abi = MYL_RC_ABI_VERSION, .descriptors = descriptor, .descriptor_count = 1};
    shape_builder builder = {.heap = heap};
    myl_rc_status status = MYL_RC_ALLOCATION_REFUSED;
    if (builder_add(&builder, descriptor->shape)) status = register_shapes(&builder, &module, NULL, 0);
    builder_free(&builder);
    return status;
}
