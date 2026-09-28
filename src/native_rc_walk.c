#include "native_rc_internal.h"
#include <string.h>

static void push(myl_native_heap *heap, const myl_rc_shape *shape, unsigned char *address) {
    if (shape->kind == MYL_RC_SHAPE_NONE) return;
    myl_rc_invariant(heap->rc->walk.depth < heap->rc->walk.capacity);
    myl_rc_frame *frame = &heap->rc->walk.frames[heap->rc->walk.depth++];
    *frame = (myl_rc_frame){.shape = shape, .address = address};
}
/* Frames keep the next child/index, not an expanded list of array elements. */
enum { WALK_CLEAR, WALK_RELEASE, WALK_REGION, WALK_UNLOAN };
static unsigned walk(myl_native_heap *heap, unsigned action) {
    unsigned region = 0;
    while (heap->rc->walk.depth) {
        myl_rc_frame *frame = &heap->rc->walk.frames[heap->rc->walk.depth - 1];
        const myl_rc_shape *shape = frame->shape;
        if (shape->kind == MYL_RC_SHAPE_POINTER || shape->kind == MYL_RC_SHAPE_HOLD_POINTER) {
            void *payload;
            memcpy(&payload, frame->address, sizeof payload);
            if (action == WALK_REGION) {
                unsigned found = payload ? myl_native_header_region(payload) : 0;
                if (found > region) region = found;
            } else memset(frame->address, 0, sizeof payload);
            --heap->rc->walk.depth;
            if (action == WALK_RELEASE || action == WALK_UNLOAN) {
                if (shape->kind == MYL_RC_SHAPE_HOLD_POINTER || action == WALK_UNLOAN) {
                    myl_rc_hold hold = {.payload = payload};
                    myl_rc_hold_release(heap, &hold);
                } else myl_rc_edge_release(heap, payload);
            }
        } else if (shape->kind == MYL_RC_SHAPE_ARRAY) {
            if (frame->cursor == shape->as.array.count) { --heap->rc->walk.depth; continue; }
            size_t index = frame->cursor++;
            push(heap, shape->as.array.element, frame->address + index * shape->as.array.stride);
        } else {
            myl_rc_invariant(shape->kind == MYL_RC_SHAPE_RECORD || shape->kind == MYL_RC_SHAPE_VARIANT);
            const myl_rc_field *fields = shape->kind == MYL_RC_SHAPE_RECORD ? shape->as.record.fields : shape->as.variant.fields;
            size_t count = shape->kind == MYL_RC_SHAPE_RECORD ? shape->as.record.count : shape->as.variant.count;
            if (frame->cursor == count) { --heap->rc->walk.depth; continue; }
            const myl_rc_field *field = &fields[frame->cursor++];
            if (shape->kind == MYL_RC_SHAPE_VARIANT) {
                uint32_t tag;
                memcpy(&tag, frame->address + shape->as.variant.tag_offset, sizeof tag);
                if (field->tag != tag) continue;
            }
            push(heap, field->shape, frame->address + field->offset);
        }
    }
    return region;
}
/* Release every live leaf of one shallow value (see myl_rc_shallow): clear
 * each edge, then drop its O or H token, enqueueing any death. `unloan`
 * drops H for every leaf. The caller drains. */
static void shallow_release(myl_native_heap *heap, const myl_rc_shape *shape, unsigned char *address, int unloan) {
    myl_rc_shallow leaves;
    myl_rc_shallow_begin(&leaves, shape, address);
    size_t offset;
    myl_rc_shape_kind kind;
    while (myl_rc_shallow_next(&leaves, &offset, &kind)) {
        void *payload;
        memcpy(&payload, address + offset, sizeof payload);
        memset(address + offset, 0, sizeof payload);
        if (unloan || kind == MYL_RC_SHAPE_HOLD_POINTER) myl_rc_hold_drop(heap, payload);
        else myl_rc_owner_drop(heap, payload);
    }
}
unsigned myl_rc_value_region(myl_native_heap *heap, const myl_rc_shape *source, const void *address) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    const myl_rc_shape *shape = myl_rc_shape_find(heap, source);
    myl_rc_invariant(shape && (!shape->size || address));
    if (myl_rc_shallow_admits(shape)) {
        myl_rc_shallow leaves;
        myl_rc_shallow_begin(&leaves, shape, address);
        size_t offset;
        myl_rc_shape_kind kind;
        unsigned region = 0;
        while (myl_rc_shallow_next(&leaves, &offset, &kind)) {
            void *payload;
            memcpy(&payload, (const unsigned char *)address + offset, sizeof payload);
            unsigned found = payload ? myl_native_header_region(payload) : 0;
            if (found > region) region = found;
        }
        return region;
    }
    push(heap, shape, (unsigned char *)address);
    return walk(heap, WALK_REGION);
}
void myl_rc_edges_release(myl_native_heap *heap, const myl_rc_shape *source, void *address, size_t count) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    const myl_rc_shape *shape = myl_rc_shape_find(heap, source);
    myl_rc_invariant(shape != NULL);
    size_t bytes;
    myl_rc_invariant(myl_rc_size_mul(shape->size, count, &bytes));
    myl_rc_invariant(!bytes || address);
    if (shape->kind == MYL_RC_SHAPE_NONE) return;
    unsigned char *cursor = address;
    if (shape->kind == MYL_RC_SHAPE_POINTER) {
        /* RC-DICT-FAST-1: a run of ordinary pointers, each cleared and released. */
        for (size_t i = 0; i < count; ++i, cursor += sizeof(void *)) {
            void *payload;
            memcpy(&payload, cursor, sizeof payload);
            memset(cursor, 0, sizeof payload);
            myl_rc_owner_drop(heap, payload);
        }
        return;
    }
    int shallow = myl_rc_shallow_admits(shape);
    for (size_t i = 0; i < count; ++i) {
        if (shallow) shallow_release(heap, shape, cursor, 0);
        else {
            push(heap, shape, cursor);
            walk(heap, WALK_RELEASE);
        }
        cursor += shape->size;
    }
}
void myl_rc_flat_edges_release(myl_native_heap *heap, const myl_rc_binding *binding, void *address, size_t count) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth && binding->flat.count <= MYL_RC_FLAT_LEAVES);
    size_t bytes;
    myl_rc_invariant(myl_rc_size_mul(binding->flat.size, count, &bytes) && (!bytes || address));
    if (!binding->flat.count) return;
    unsigned char *cursor = address;
    for (size_t i = 0; i < count; ++i) {
        myl_rc_flat_release_one(heap, &binding->flat, cursor);
        cursor += binding->flat.size;
    }
}
/* Deferred counter updates of one drain's inline retirements: they are
 * applied before any callback runs and when the drain ends, so a callback
 * that allocates always sees a bumped reuse epoch. */
typedef struct { size_t retired, pushed; } drain_tally;
static void tally_apply(myl_native_heap *heap, drain_tally *tally) {
    if (!tally->retired) return;
    myl_rc_invariant(heap->objects_live >= tally->retired);
    heap->objects_live -= tally->retired;
    heap->collections = heap->collections > SIZE_MAX - tally->retired ? SIZE_MAX : heap->collections + tally->retired;
    heap->rc_cache.pushed += tally->pushed;
    *tally = (drain_tally){0};
}
/* Release every live leaf of one dying flat value (RC-DRAIN-FLAT-1). Inside
 * a drain a released last token queues its object directly behind `head`;
 * the dying value's own edge words are not cleared, because its extent is
 * retired right after and never read again. A counted child is live and not
 * dying (checked as one mark test: an immortal or arena child is skipped). */
static inline __attribute__((always_inline)) myl_rc_object *drain_leaf(myl_native_heap *heap,
        const unsigned char *leaf, myl_rc_object *head) {
    (void)heap;
    void *child;
    __builtin_memcpy(&child, leaf, sizeof child);
    if (!child) return head;
    myl_rc_object *object = (myl_rc_object *)child - 1;
    uintptr_t mark = object->common.mark;
    if (mark & (MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_ARENA | MYL_RC_OBJECT_DYING)) {
        myl_rc_invariant(!(mark & MYL_RC_OBJECT_DYING));
        return head;
    }
    uintptr_t owners = object->owners;
    MYL_RC_STAT(heap, MYL_RC_STAT_OWNER_RELEASE);
    if (owners == 1 && !object->holds) {
        object->common.mark = mark | MYL_RC_OBJECT_DYING;
        object->owners = (uintptr_t)head;
        return object;
    }
    myl_rc_invariant(owners != 0);
    object->owners = owners - 1;
    return head;
}
static inline __attribute__((always_inline)) myl_rc_object *drain_leaves(myl_native_heap *heap,
        const myl_rc_flat *flat, unsigned live, const unsigned char *payload, myl_rc_object *head) {
    for (; live; live &= live - 1) head = drain_leaf(heap, payload + flat->offsets[__builtin_ctz(live)], head);
    return head;
}
/* One dying object outside the fast loop: any allocator, a large extent, an
 * element count other than one, a conditional or generic plan, or a hook. The
 * drain's list and tally are published first, because any of these may run a
 * callback; the new list head is returned. */
static __attribute__((noinline)) myl_rc_object *drain_one(myl_native_heap *heap, myl_rc_object *object,
        myl_rc_object *head, drain_tally *tally) {
    myl_rc_state *rc = heap->rc;
    rc->dead.head = head;
    tally_apply(heap, tally);
    void *payload = object + 1;
    const myl_rc_binding *binding = myl_rc_binding_find(heap, object->common.element);
    myl_rc_invariant(binding != NULL);
    uintptr_t mark = object->common.mark;
    myl_rc_invariant((mark & (MYL_RC_OBJECT_DYING | MYL_NATIVE_OBJECT_IMMORTAL |
        MYL_NATIVE_OBJECT_ARENA)) == MYL_RC_OBJECT_DYING);
    size_t count = (size_t)((mark & MYL_NATIVE_OBJECT_COUNT_BITS) >> MYL_NATIVE_OBJECT_COUNT_SHIFT);
    if (binding->flat.count <= MYL_RC_FLAT_LEAVES) {
        /* Admission excludes every custom hook: no callback runs and ordered
         * ordinary edges only queue more deaths. */
        if (count == 1) rc->dead.head = drain_leaves(heap, &binding->flat, myl_rc_flat_live(&binding->flat, payload), payload, rc->dead.head);
        else myl_rc_flat_edges_release(heap, binding, payload, count);
    } else {
        /* A unique close hook can inspect its managed context. Run it while
         * child tokens are intact, with no descriptor frame leased. Nested
         * releases only enqueue. Reacquire metadata after a registering hook. */
        void (*finalize)(myl_native_heap *, void *) = binding->descriptor.finalize;
        if (finalize) finalize(heap, payload);
        binding = myl_rc_binding_find(heap, object->common.element);
        myl_rc_invariant(binding && !rc->walk.depth);
        if (binding->descriptor.edges) binding->descriptor.edges(heap, payload, count);
        else myl_rc_edges_release(heap, binding->descriptor.shape, payload, count);
    }
    myl_rc_invariant(!rc->walk.depth);
    myl_rc_retire(heap, object);
    return rc->dead.head;
}
/* The fast loop's state between calls: its list head, the previous death's
 * type with that type's plan, the fast test for it (every flag and count bit
 * that must match, and their expected value; all ones never matches), the
 * type's unconditional live set, and the deferred counters. */
typedef struct {
    myl_rc_object *head;
    const myl_native_type *last;
    const myl_rc_flat *flat;
    uintptr_t mask, want;
    unsigned all;
    drain_tally tally;
} drain_cursor;
/* RC-DRAIN-PAIR-1: the live set of a plan of exactly two unconditional leaves
 * (a binary node, say): bit i names offsets[i], so no other plan has it. */
#define DRAIN_PAIR 3u
#define DRAIN_NEVER (~(uintptr_t)0)
/* The fast test of every admitted plan with a leaf: dying, counted, not large
 * and a single element. */
#define DRAIN_ONE_MASK (MYL_RC_OBJECT_DYING | MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_ARENA | \
    MYL_NATIVE_OBJECT_LARGE | MYL_NATIVE_OBJECT_COUNT_BITS)
#define DRAIN_ONE_WANT (MYL_RC_OBJECT_DYING | ((uintptr_t)1 << MYL_NATIVE_OBJECT_COUNT_SHIFT))
/* RC-DRAIN-TYPES-1: the plan of a death's type from the drain's two most
 * recent types, most recent first, or from one binding probe that makes it
 * the most recent. */
static inline __attribute__((always_inline)) const myl_rc_flat *drain_plan(myl_native_heap *heap, const myl_native_type *type) {
    myl_rc_state *rc = heap->rc;
    if (rc->dead.types[0] == type) return rc->dead.flats[0];
    const myl_rc_flat *flat;
    if (rc->dead.types[1] == type) flat = rc->dead.flats[1];
    else {
        const myl_rc_binding *binding = myl_rc_binding_find(heap, type);
        myl_rc_invariant(binding != NULL);
        flat = &binding->flat;
    }
    rc->dead.types[1] = rc->dead.types[0];
    rc->dead.flats[1] = rc->dead.flats[0];
    rc->dead.types[0] = type;
    rc->dead.flats[0] = flat;
    return flat;
}
/* RC-DRAIN-PAIR-1: one run of consecutive deaths of a two-leaf type, from
 * `object` (already popped; `head` is the rest of the list). Each death's two
 * leaves are released at the plan's offsets, in the plan's order, and its slot
 * goes on its class list: a one-element slab object's class follows from its
 * type's size alone, so the whole run shares one list, written once, and its
 * listed bytes are counted once. The run stops at an empty list, a death of
 * another type or one the constant one-element fast test refuses, which stays
 * queued; the new head is returned. A call of its own keeps the loop's few
 * values in registers. */
static __attribute__((noinline)) myl_rc_object *drain_pairs(myl_native_heap *heap, myl_rc_object *object,
        myl_rc_object *head, const myl_rc_flat *flat, drain_tally *tally) {
    const myl_native_type *type = object->common.element;
    const myl_rc_slab_class *slab = (const myl_rc_slab_class *)((uintptr_t)object & ~(uintptr_t)(MYL_RC_SLAB_BYTES - 1));
    void **list = &heap->rc_cache.free[slab->index];
    const size_t first = flat->offsets[0], second = flat->offsets[1];
    size_t count = 0;
    void *top = *list;
    for (;;) {
        const unsigned char *payload = (const unsigned char *)(object + 1);
        head = drain_leaf(heap, payload + first, head);
        head = drain_leaf(heap, payload + second, head);
        MYL_RC_STAT(heap, MYL_RC_STAT_RETIRE);
        object->common.mark = MYL_RC_RETIRED_MARK;
        object->owners = (uintptr_t)top;
        top = object;
        ++count;
        if (!head || head->common.element != type || (head->common.mark & DRAIN_ONE_MASK) != DRAIN_ONE_WANT) break;
        object = head;
        head = (myl_rc_object *)object->owners;
    }
    *list = top;
    tally->retired += count;
    tally->pushed += count * slab->stride;
    return head;
}
/* Run the call-free fast loop until the list is empty (NULL) or the next
 * death needs drain_one (returned, already popped). It admits a dying object
 * of the production allocator that is slab-sized and, unless its plan has no
 * leaf, a single element of an unconditional flat plan: its leaves are
 * released, its deaths queued on the loop's own list and its slot pushed on
 * its class's free list. */
static __attribute__((noinline)) myl_rc_object *drain_fast(myl_native_heap *heap, drain_cursor *cursor, int cached) {
    myl_rc_object *head = cursor->head;
    const myl_native_type *last = cursor->last;
    const myl_rc_flat *flat = cursor->flat;
    uintptr_t mask = cursor->mask, want = cursor->want;
    unsigned all = cursor->all;
    size_t retired = cursor->tally.retired, pushed = cursor->tally.pushed;
    myl_rc_object *slow = NULL;
    while (head) {
        myl_rc_object *object = head;
        head = (myl_rc_object *)object->owners;
        const myl_native_type *element = object->common.element;
        if (element != last) {
            last = element;
            flat = drain_plan(heap, element);
            unsigned leaves = flat->count;
            all = leaves ? flat->all : 0;
            mask = MYL_RC_OBJECT_DYING | MYL_NATIVE_OBJECT_IMMORTAL | MYL_NATIVE_OBJECT_ARENA | MYL_NATIVE_OBJECT_LARGE;
            want = MYL_RC_OBJECT_DYING;
            if (leaves) {
                mask |= MYL_NATIVE_OBJECT_COUNT_BITS;
                want |= (uintptr_t)1 << MYL_NATIVE_OBJECT_COUNT_SHIFT;
            }
            if (!cached || leaves > MYL_RC_FLAT_LEAVES || flat->conditional) want = DRAIN_NEVER;
        }
        if ((object->common.mark & mask) != want) { slow = object; break; }
        /* Consecutive deaths of one type run in an inner loop, which leaves
         * the object queued at the first death of another type or one the
         * fast test refuses. */
        if (all == DRAIN_PAIR) {
            drain_tally run = {.retired = retired, .pushed = pushed};
            head = drain_pairs(heap, object, head, flat, &run);
            retired = run.retired;
            pushed = run.pushed;
            continue;
        }
        for (;;) {
            head = drain_leaves(heap, flat, all, (const unsigned char *)(object + 1), head);
            MYL_RC_STAT(heap, MYL_RC_STAT_RETIRE);
            const myl_rc_slab_class *slab = (const myl_rc_slab_class *)((uintptr_t)object & ~(uintptr_t)(MYL_RC_SLAB_BYTES - 1));
            size_t index = slab->index;
            object->common.mark = MYL_RC_RETIRED_MARK;
            object->owners = (uintptr_t)heap->rc_cache.free[index];
            heap->rc_cache.free[index] = object;
            pushed += slab->stride;
            ++retired;
            if (!head || head->common.element != last || (head->common.mark & mask) != want) break;
            object = head;
            head = (myl_rc_object *)object->owners;
        }
    }
    *cursor = (drain_cursor){.head = head, .last = last, .flat = flat, .mask = mask, .want = want, .all = all,
        .tally = {.retired = retired, .pushed = pushed}};
    return slow;
}
/* Bindings are immutable batch allocations published through the binding map
 * and never replaced, and the allocator hooks never change. The previous
 * death's type answers a repeated type without a probe. */
void myl_rc_drain(myl_native_heap *heap) {
    myl_rc_invariant(heap && heap->rc);
    myl_rc_state *rc = heap->rc;
    if (!rc->dead.head || rc->dead.active || rc->walk.depth) return;
    rc->dead.active = 1;
    const int cached = rc->allocator.hooks.retire == myl_rc_storage_retire;
    drain_cursor cursor = {.head = rc->dead.head, .want = DRAIN_NEVER};
    for (;;) {
        myl_rc_object *object = drain_fast(heap, &cursor, cached);
        if (!object) break;
        cursor.head = drain_one(heap, object, cursor.head, &cursor.tally);
    }
    rc->dead.head = NULL;
    tally_apply(heap, &cursor.tally);
    rc->dead.active = 0;
}
void myl_rc_value_drop(myl_native_heap *heap, myl_rc_slot *slot) {
    myl_rc_invariant(slot && slot->shape && slot->address);
    myl_rc_edges_release(heap, slot->shape, slot->address, 1);
    memset(slot->address, 0, slot->shape->size);
    myl_rc_drain(heap);
}
void myl_rc_loan_drop(myl_native_heap *heap, const myl_rc_shape *source, void *address) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    const myl_rc_shape *shape = myl_rc_shape_find(heap, source);
    myl_rc_invariant(shape && (!shape->size || address));
    if (myl_rc_shallow_admits(shape)) shallow_release(heap, shape, address, 1);
    else {
        push(heap, shape, address);
        walk(heap, WALK_UNLOAN);
    }
    memset(address, 0, shape->size);
    myl_rc_drain(heap);
}
/* Registration reserved the full inline depth, including count-free native
 * records. Check every variant arm without reading a value or closing a token. */
int myl_rc_native_has_unique(myl_native_heap *heap, const myl_native_type *type) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    for (;;) {
        if (type->kind == MYL_NATIVE_POINTER && type->collection_kind == 5 && type->element) {
            const myl_rc_descriptor *body = myl_rc_descriptor_of(heap, type->element);
            myl_rc_invariant(body != NULL);
            if (body->finalize) { heap->rc->walk.depth = 0; return 1; }
        }
        if (type->kind == MYL_NATIVE_RESOURCE || type->kind == MYL_NATIVE_OWNED_BUFFER ||
            type->kind == MYL_NATIVE_OWNED_POOL) { heap->rc->walk.depth = 0; return 1; }
        if (type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT || type->kind == MYL_NATIVE_ARRAY) {
            myl_rc_invariant(heap->rc->walk.depth < heap->rc->walk.capacity);
            heap->rc->walk.frames[heap->rc->walk.depth++] = (myl_rc_frame){.type = type};
        }
        for (;;) {
            if (!heap->rc->walk.depth) return 0;
            myl_rc_frame *frame = &heap->rc->walk.frames[heap->rc->walk.depth - 1];
            size_t count = frame->type->kind == MYL_NATIVE_ARRAY ? (frame->type->count ? 1 : 0) : frame->type->field_count;
            if (frame->cursor < count) { type = frame->type->fields[frame->cursor++].type; break; }
            --heap->rc->walk.depth;
        }
    }
}
int myl_rc_binding_has_unique(myl_native_heap *heap, const myl_rc_binding *binding) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth && binding);
    unsigned fact = binding->flat.native_unique;
    if (!fact) {
        /* No callback or registration occurs in this walk. In particular, a
         * missing typed-box body must fail before a negative fact is published. */
        fact = myl_rc_native_has_unique(heap, binding->descriptor.type) ? 2 : 1;
        ((myl_rc_binding *)binding)->flat.native_unique = (unsigned char)fact;
    }
    myl_rc_invariant(fact <= 2);
    return fact == 2;
}
void myl_rc_value_relocate(myl_rc_slot *destination, myl_rc_slot *source) {
    myl_rc_invariant(destination && source && destination->shape && source->shape);
    myl_rc_invariant(destination->shape->size == source->shape->size);
    size_t bytes = source->shape->size;
    if (destination->address == source->address) return;
    uintptr_t dst = (uintptr_t)destination->address, src = (uintptr_t)source->address;
    myl_rc_invariant(dst > src ? dst - src >= bytes : src - dst >= bytes);
    memcpy(destination->address, source->address, bytes);
    memset(source->address, 0, bytes);
}

void myl_rc_value_seed(myl_native_heap *heap, const myl_rc_shape *source_shape,
                        void *destination, const void *source, size_t count) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth && destination != source);
    const myl_rc_shape *shape = myl_rc_shape_find(heap, source_shape);
    size_t bytes;
    myl_rc_invariant(shape != NULL);
    myl_rc_invariant(myl_rc_size_mul(shape->size, count, &bytes));
    if (shape->kind == MYL_RC_SHAPE_POINTER || shape->kind == MYL_RC_SHAPE_HOLD_POINTER) {
        memset(destination, 0, bytes);
        return;
    }
    memcpy(destination, source, bytes);
    if (shape->kind == MYL_RC_SHAPE_NONE) return;
    unsigned char *cursor = destination;
    int shallow = myl_rc_shallow_admits(shape);
    for (size_t i = 0; i < count; ++i) {
        if (shallow) {
            myl_rc_shallow leaves;
            myl_rc_shallow_begin(&leaves, shape, cursor);
            size_t offset;
            myl_rc_shape_kind kind;
            while (myl_rc_shallow_next(&leaves, &offset, &kind)) memset(cursor + offset, 0, sizeof(void *));
        } else {
            push(heap, shape, cursor);
            walk(heap, WALK_CLEAR);
        }
        cursor += shape->size;
    }
}
void myl_rc_construction_abort(myl_native_heap *heap, void *payload) {
    if (!payload) return;
    myl_native_object *header = (myl_native_object *)payload - 1;
    myl_rc_invariant(!(header->mark & MYL_NATIVE_OBJECT_IMMORTAL));
    if (!(header->mark & MYL_NATIVE_OBJECT_ARENA)) { myl_rc_owner_release(heap, payload); return; }
    if (header->mark & MYL_RC_OBJECT_DYING) return;
    header->mark |= MYL_RC_OBJECT_DYING;
    const myl_rc_descriptor *descriptor = myl_rc_descriptor_of(heap, header->element);
    myl_rc_invariant(descriptor != NULL);
    size_t count = (header->mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT) & MYL_NATIVE_ARENA_COUNT_MAX;
    if (descriptor->finalize) descriptor->finalize(heap, payload);
    descriptor = myl_rc_descriptor_of(heap, header->element);
    if (descriptor->edges) descriptor->edges(heap, payload, count);
    else myl_rc_edges_release(heap, descriptor->shape, payload, count);
    size_t bytes;
    myl_rc_invariant(myl_rc_size_mul(header->element->size, count, &bytes));
    memset(payload, 0, bytes);
    myl_rc_drain(heap);
}
static void unique_push(myl_native_heap *heap, const myl_native_type *type, unsigned char *address,
                          myl_native_drop_link **work) {
    if (type->kind == MYL_NATIVE_RESOURCE) {
        myl_native_resource *resource;
        memcpy(&resource, address, sizeof resource);
        memset(address, 0, sizeof resource);
        if (resource) {
            resource->work = (myl_native_drop_link){.next = *work, .owner = resource, .kind = type->kind};
            *work = &resource->work;
        }
    } else if (type->kind == MYL_NATIVE_ARRAY || type->kind == MYL_NATIVE_RECORD || type->kind == MYL_NATIVE_VARIANT) {
        myl_rc_invariant(heap->rc->walk.depth < heap->rc->walk.capacity);
        heap->rc->walk.frames[heap->rc->walk.depth++] = (myl_rc_frame){.type = type, .address = address};
    }
}
void myl_rc_owned_drop(myl_native_heap *heap, const myl_native_type *type, void *value) {
    myl_rc_invariant(heap && heap->rc && !heap->rc->walk.depth);
    myl_native_drop_link *work = NULL;
    unique_push(heap, type, value, &work);
    while (heap->rc->walk.depth) {
        myl_rc_frame *frame = &heap->rc->walk.frames[heap->rc->walk.depth - 1];
        type = frame->type;
        if (type->kind == MYL_NATIVE_ARRAY) {
            if (frame->cursor == type->count) { --heap->rc->walk.depth; continue; }
            size_t offset = frame->cursor++ * type->stride;
            unique_push(heap, type->fields[0].type, frame->address + offset, &work);
        } else {
            if (frame->cursor == type->field_count) { --heap->rc->walk.depth; continue; }
            const myl_native_field *field = &type->fields[frame->cursor++];
            if (type->kind == MYL_NATIVE_VARIANT) {
                uint32_t tag;
                memcpy(&tag, frame->address, sizeof tag);
                if (tag != field->tag) continue;
            }
            unique_push(heap, field->type, frame->address + field->offset, &work);
        }
    }
    /* All token slots are disarmed before the first callback. The intrusive
     * schedule is independent of metadata and stays valid if a close hook
     * allocates, registers descriptors, or starts another unique traversal. */
    while (work) {
        myl_native_resource *resource = work->owner;
        work = work->next;
        resource->drop(resource);
    }
}
void myl_rc_finalize_unique(myl_native_heap *heap, void *payload) {
    const myl_native_object *header = (const myl_native_object *)payload - 1;
    size_t count = (header->mark >> MYL_NATIVE_OBJECT_COUNT_SHIFT) &
        (header->mark & MYL_NATIVE_OBJECT_ARENA ? MYL_NATIVE_ARENA_COUNT_MAX : MYL_NATIVE_OBJECT_COUNT_MAX);
    myl_rc_invariant(!heap->rc->walk.depth);
    for (size_t i = 0; i < count; ++i)
        myl_rc_owned_drop(heap, header->element, (unsigned char *)payload + i * header->element->size);
}
