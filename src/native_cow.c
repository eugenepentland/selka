#include "native_cow.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
myl_native_cow_statistics myl_native_cow_counters;
static _Thread_local int cow_depth_exceeded;
int myl_native_cow_take_depth_failure(void) {
    int result = cow_depth_exceeded;
    cow_depth_exceeded = 0;
    return result;
}
static const myl_native_type pointer_type = {
    .size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER
};
static myl_native_object *header_of(const void *payload) {
    return (myl_native_object *)payload - 1;
}
/* Only a counting build calls tally; ordinary checks do no counter work. */
static int counting_enabled;
static void report_at_exit(void) { myl_native_cow_report(stderr); }
void myl_native_cow_tally(uint32_t kind) {
    if (!counting_enabled) {
        counting_enabled = 1;
        atexit(report_at_exit);
    }
    switch (kind) {
    case MYL_NATIVE_COW_MARK: myl_native_cow_counters.marks++; break;
    case MYL_NATIVE_COW_CHECK: myl_native_cow_counters.checks++; break;
    case MYL_NATIVE_COW_HOISTED: myl_native_cow_counters.hoisted++; break;
    case MYL_NATIVE_COW_PIN: myl_native_cow_counters.pins++; break;
    default: break;
    }
}
void myl_native_cow_report(void *stream) {
    const myl_native_cow_statistics *c = &myl_native_cow_counters;
    fprintf((FILE *)stream,
            "cow-stats {\"marks\":%llu,\"checks\":%llu,\"hoisted\":%llu,\"copies\":%llu,"
            "\"copied_bytes\":%llu,\"pinned_copies\":%llu,\"pins\":%llu}\n",
            (unsigned long long)c->marks, (unsigned long long)c->checks, (unsigned long long)c->hoisted,
            (unsigned long long)c->copies, (unsigned long long)c->copied_bytes,
            (unsigned long long)c->pinned_copies, (unsigned long long)c->pins);
}
int myl_native_cow_payload(const void *payload) {
    return myl_native_list_header(payload) || myl_native_dictionary_header(payload);
}
/* Whether a value of `type` can hold a copy-on-write payload directly: a list,
 * byte string or dictionary reference, or an inline aggregate with one inside.
 * A text or a `class` reference cannot. */
/* A descriptor may nest inline aggregates much deeper than 64 levels. A
 * pathological acyclic descriptor over this explicit stack bound fails a
 * transfer rather than silently leaving a mutable descendant unmarked. A
 * recursive box revisits a descriptor on the current path; that edge adds
 * nothing, though sibling fields may still contain mutable collections. */
#define MYL_NATIVE_COW_TYPE_DEPTH_MAX 1024
static int holds_payload_path(const myl_native_type *type, const myl_native_type **seen, unsigned depth) {
    if (!type || type->trace_mode == MYL_NATIVE_TRACE_NONE) return 0;
    if (depth >= MYL_NATIVE_COW_TYPE_DEPTH_MAX) { cow_depth_exceeded = 1; return -1; }
    for (unsigned i = 0; i < depth; ++i) if (seen[i] == type) return 0;
    seen[depth++] = type;
    switch (type->kind) {
    case MYL_NATIVE_POINTER:
        /* A recursive box is immutable but its body can contain collections.
         * A cycle with no collection is safe to share without a value walk. */
        if (type->collection_kind == 5) return type->element ? holds_payload_path(type->element, seen, depth) : 0;
        return type->collection_kind == 1 || type->collection_kind == 3 || type->collection_kind == 4;
    case MYL_NATIVE_ARRAY:
        return type->count && type->field_count ? holds_payload_path(type->fields[0].type, seen, depth) : 0;
    case MYL_NATIVE_RECORD:
    case MYL_NATIVE_VARIANT:
        for (size_t i = 0; i < type->field_count; ++i) {
            int held = holds_payload_path(type->fields[i].type, seen, depth);
            if (held) return held;
        }
        return 0;
    default:
        return 0;
    }
}
static int holds_payload(const myl_native_type *type) {
    /* Generated descriptors have process lifetime. Repeated transfers of an
     * inline record (notably VM call frames) otherwise re-walk its entire
     * schema for every held field on every instruction. Direct-mapped thread
     * local entries need no synchronization; collisions only redo the walk. */
    static _Thread_local struct { const myl_native_type *type; int result; } cache[256];
    if (!type) return 0;
    size_t slot = ((uintptr_t)type >> 4) & 255;
    if (cache[slot].type == type) return cache[slot].result;
    const myl_native_type *seen[MYL_NATIVE_COW_TYPE_DEPTH_MAX];
    int result = holds_payload_path(type, seen, 0);
    if (result >= 0) { cache[slot].type = type; cache[slot].result = result; }
    return result;
}
/* Set SHARED on one payload a transfer or a copy now leaves with a second
 * holder, unless it is pinned, which the caller must copy instead. Answers 1
 * when the payload was marked or needs nothing, 0 when it is pinned. */
static int mark(void *payload) {
    if (!payload || !myl_native_cow_payload(payload)) return 1;
    myl_native_object *header = header_of(payload);
    uintptr_t word = header->mark;
    if (word & MYL_NATIVE_OBJECT_IMMORTAL) return 1;
    if (word & MYL_NATIVE_OBJECT_PINNED) return 0;
    header->mark = word | MYL_NATIVE_OBJECT_SHARED;
    if (counting_enabled) myl_native_cow_counters.marks++;
    return 1;
}
/* The walk `share_value` and a copy's element marking share: every payload a
 * value holds directly is marked, and a pinned one is replaced in place by
 * its copy when `heap` is given. Returns 0 when that copy is refused. */
static int share_at(myl_native_heap *heap, const myl_native_type *type, unsigned char *address, unsigned depth, int replace) {
    if (depth > MYL_NATIVE_COW_TYPE_DEPTH_MAX) { cow_depth_exceeded = 1; return 0; }
    if (type->trace_mode == MYL_NATIVE_TRACE_NONE) return 1;
    switch (type->kind) {
    case MYL_NATIVE_POINTER: {
        const int box = type->collection_kind == 5;
        if (!box && type->collection_kind != 1 && type->collection_kind != 3 && type->collection_kind != 4) return 1;
        if (box) {
            int held = holds_payload(type->element);
            if (held < 0) return 0;
            if (!held) return 1;
        }
        void *payload;
        memcpy(&payload, address, sizeof payload);
        if (box) {
            if (!payload || !type->element) return !payload;
            /* First walk without replacements. If a pinned descendant needs
             * one, clone this immutable box and patch only the fresh body. */
            int result = share_at(heap, type->element, payload, depth + 1, 0);
            if (result != 2 || !replace) return result;
            unsigned region = myl_native_header_region(payload);
            void *clone = myl_native_heap_alloc_at(heap, type->element, 1, region);
            if (!clone) return 0;
            memcpy(clone, payload, type->element->size);
            memcpy(address, &clone, sizeof clone);
            return share_at(heap, type->element, clone, depth + 1, 1);
        }
        if (mark(payload)) return 1;
        if (!replace) return 2;
        void *copy = myl_native_cow_copy(heap, payload);
        if (!copy) return 0;
        if (counting_enabled) myl_native_cow_counters.pinned_copies++;
        memcpy(address, &copy, sizeof copy);
        return 1;
    }
    case MYL_NATIVE_ARRAY:
        for (size_t i = 0; i < type->count; ++i) {
            int result = share_at(heap, type->fields[0].type, address + i * type->stride, depth + 1, replace);
            if (result != 1) return result;
        }
        return 1;
    case MYL_NATIVE_RECORD:
    case MYL_NATIVE_VARIANT: {
        uint32_t tag = 0;
        if (type->kind == MYL_NATIVE_VARIANT) memcpy(&tag, address, sizeof tag);
        for (size_t i = 0; i < type->field_count; ++i) {
            const myl_native_field *field = &type->fields[i];
            if (type->kind == MYL_NATIVE_VARIANT && field->tag != tag) continue;
            int result = share_at(heap, field->type, address + field->offset, depth + 1, replace);
            if (result != 1) return result;
        }
        return 1;
    }
    default:
        return 1;
    }
}
void *myl_native_cow_share(myl_native_heap *heap, void *payload) {
    if (mark(payload)) return payload;
    void *copy = myl_native_cow_copy(heap, payload);
    if (copy && counting_enabled) myl_native_cow_counters.pinned_copies++;
    return copy;
}
int myl_native_cow_share_value(myl_native_heap *heap, const myl_native_type *type, void *address) {
    if (!type || !address) return 1;
    int held = holds_payload(type);
    if (held < 0) return 0;
    if (!held) return 1;
    return share_at(heap, type, address, 0, 1) == 1;
}
/* Mark every payload the elements of a fresh copy `list` hold, now that the
 * original holds them too. A pinned element — possible only if a `mut`
 * argument's payload also sits in storage, which a unique argument never does
 * — is replaced in the copy by a copy of its own, so the copy is rooted here.
 * Returns 0 when such a copy is refused. */
static int mark_elements(myl_native_heap *heap, myl_native_list *list) {
    if (!list->storage) return 1;
    int held = holds_payload(list->element);
    if (held < 0) return 0;
    if (!held) return 1;
    myl_native_root root;
    myl_native_root_push(heap, &root, &list, &pointer_type);
    int done = 1;
    for (size_t i = 0; i < list->length && done; ++i)
        done = share_at(heap, list->element, (unsigned char *)list->storage + i * list->element->size, 0, 1) == 1;
    myl_native_root_pop(heap, &root);
    return done;
}
/* Mark every key and value the entries of a fresh copy `dict` hold. */
static int mark_entries(myl_native_heap *heap, myl_native_dictionary *dict) {
    int keys = holds_payload(dict->key), values = holds_payload(dict->value);
    if (keys < 0 || values < 0) return 0;
    if ((!keys && !values) || !dict->entries->storage) return 1;
    myl_native_root root;
    myl_native_root_push(heap, &root, &dict, &pointer_type);
    int done = 1;
    for (size_t i = 0; i < dict->entries->length && done; ++i) {
        unsigned char *entry = (unsigned char *)dict->entries->storage + i * dict->entry_type.size;
        if (keys) done = share_at(heap, dict->key, entry, 0, 1) == 1;
        if (done && values) done = share_at(heap, dict->value, entry + dict->value_offset, 0, 1) == 1;
    }
    myl_native_root_pop(heap, &root);
    return done;
}
int myl_native_cow_share_children(myl_native_heap *heap, const myl_native_type *type, void *address) {
    if (!type || !address) return 1;
    if (type->kind != MYL_NATIVE_POINTER) return myl_native_cow_share_value(heap, type, address);
    void *payload;
    memcpy(&payload, address, sizeof payload);
    if (!payload) return 1;
    if (type->collection_kind == 1 || type->collection_kind == 4)
        return mark_elements(heap, payload);
    if (type->collection_kind == 3)
        return mark_entries(heap, payload);
    return 1;
}
int myl_native_cow_copy_source_children(myl_native_heap *heap, const myl_native_type *type, void *address) {
    if (!type || !address || type->kind != MYL_NATIVE_POINTER) return myl_native_cow_share_children(heap, type, address);
    void *payload;
    memcpy(&payload, address, sizeof payload);
    if (!payload) return 1;
    if (type->collection_kind != 1 && type->collection_kind != 3 && type->collection_kind != 4)
        return myl_native_cow_share_children(heap, type, address);
    /* The common path marks children in place without allocating. A pinned
     * descendant needs replacement, so clone only then: the source's storage
     * belongs to another holder and must never receive that replacement. */
    int scan = 1;
    if (type->collection_kind == 1 || type->collection_kind == 4) {
        myl_native_list *list = payload;
        int held = holds_payload(list->element);
        if (held < 0) return 0;
        if (held && list->storage) for (size_t i = 0; i < list->length && scan == 1; ++i)
            scan = share_at(heap, list->element, (unsigned char *)list->storage + i * list->element->size, 0, 0);
    } else {
        myl_native_dictionary *dict = payload;
        int keys = holds_payload(dict->key), values = holds_payload(dict->value);
        if (keys < 0 || values < 0) return 0;
        if (dict->entries->storage) for (size_t i = 0; i < dict->entries->length && scan == 1; ++i) {
            unsigned char *entry = (unsigned char *)dict->entries->storage + i * dict->entry_type.size;
            if (keys) scan = share_at(heap, dict->key, entry, 0, 0);
            if (scan == 1 && values) scan = share_at(heap, dict->value, entry + dict->value_offset, 0, 0);
        }
    }
    if (scan == 0) return 0;
    if (scan == 1) return 1;
    void *copy = myl_native_cow_copy(heap, payload);
    if (!copy) return 0;
    memcpy(address, &copy, sizeof copy);
    return 1;
}
void *myl_native_cow_copy(myl_native_heap *heap, void *payload) {
    if (!payload) return NULL;
    unsigned region = myl_native_header_region(payload);
    if (myl_native_list_header(payload)) {
        const myl_native_list *list = payload;
        myl_native_list *copy = myl_native_list_clone_at(heap, list, list->element, region);
        if (!copy || !mark_elements(heap, copy)) return NULL;
        if (counting_enabled) {
            myl_native_cow_counters.copies++;
            myl_native_cow_counters.copied_bytes += copy->length * copy->element->size;
        }
        return copy;
    }
    if (myl_native_dictionary_header(payload)) {
        myl_native_dictionary *copy = myl_native_dictionary_clone_at(heap, payload, region);
        if (!copy || !mark_entries(heap, copy)) return NULL;
        if (counting_enabled) {
            myl_native_cow_counters.copies++;
            myl_native_cow_counters.copied_bytes += copy->entries->length * copy->entry_type.size;
        }
        return copy;
    }
    /* Anything else is immutable or a shared reference by design: it is its
     * own value. */
    return payload;
}
void *myl_native_cow_unique(myl_native_heap *heap, void *payload) {
    if (!payload || !(header_of(payload)->mark & MYL_NATIVE_OBJECT_SHARED)) return payload;
    return myl_native_cow_copy(heap, payload);
}
void *myl_native_cow_unique_in(myl_native_heap *heap, void *payload, void *container) {
    if (!payload || !(header_of(payload)->mark & MYL_NATIVE_OBJECT_SHARED)) return payload;
    myl_native_root root;
    myl_native_root_push(heap, &root, &container, &pointer_type);
    void *copy = myl_native_cow_copy(heap, payload);
    myl_native_root_pop(heap, &root);
    return copy;
}
void *myl_native_cow_rebox(myl_native_heap *heap, const myl_native_type *type,
                           void *old_box, void *body) {
    if (!old_box || !body || !type || type->collection_kind != 5 || !type->element) return NULL;
    myl_native_root old_root, body_root;
    myl_native_root_push(heap, &old_root, &old_box, type);
    myl_native_root_push(heap, &body_root, body, type->element);
    void *copy = myl_native_heap_alloc_at(heap, type->element, 1, myl_native_header_region(old_box));
    if (copy) memcpy(copy, body, type->element->size);
    myl_native_root_pop(heap, &body_root);
    myl_native_root_pop(heap, &old_root);
    return copy;
}
int myl_native_cow_elements(myl_native_heap *heap, myl_native_list *list) {
    if (!list || !list->storage || list->element->kind != MYL_NATIVE_POINTER) return 1;
    int held = holds_payload(list->element);
    if (held < 0) return 0;
    if (!held) return 1;
    myl_native_root root;
    myl_native_root_push(heap, &root, &list, &pointer_type);
    int done = 1;
    for (size_t i = 0; i < list->length; ++i) {
        void **slot = (void **)((unsigned char *)list->storage + i * sizeof(void *));
        void *element = *slot;
        if (!element || !(header_of(element)->mark & MYL_NATIVE_OBJECT_SHARED)) continue;
        void *unique = myl_native_cow_copy(heap, element);
        if (!unique) { done = 0; break; }
        /* The copy may have collected, but the collector never moves storage
         * and the rooted list keeps its block, so the slot is found again at
         * the same place. */
        slot = (void **)((unsigned char *)list->storage + i * sizeof(void *));
        *slot = unique;
    }
    myl_native_root_pop(heap, &root);
    return done;
}
