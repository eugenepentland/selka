#include "native_cow.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
myl_native_cow_statistics myl_native_cow_counters;
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
 * pathological descriptor over this explicit stack bound fails a transfer
 * rather than silently leaving a mutable descendant unmarked. */
#define MYL_NATIVE_COW_TYPE_DEPTH_MAX 1024
static int holds_payload(const myl_native_type *type, unsigned depth) {
    if (depth > MYL_NATIVE_COW_TYPE_DEPTH_MAX) return -1;
    if (!type || type->trace_mode == MYL_NATIVE_TRACE_NONE) return 0;
    switch (type->kind) {
    case MYL_NATIVE_POINTER:
        return type->collection_kind == 1 || type->collection_kind == 3 || type->collection_kind == 4;
    case MYL_NATIVE_ARRAY:
        return type->count && type->field_count ? holds_payload(type->fields[0].type, depth + 1) : 0;
    case MYL_NATIVE_RECORD:
    case MYL_NATIVE_VARIANT:
        for (size_t i = 0; i < type->field_count; ++i) {
            int held = holds_payload(type->fields[i].type, depth + 1);
            if (held) return held;
        }
        return 0;
    default:
        return 0;
    }
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
    return 1;
}
/* The walk `share_value` and a copy's element marking share: every payload a
 * value holds directly is marked, and a pinned one is replaced in place by
 * its copy when `heap` is given. Returns 0 when that copy is refused. */
static int share_at(myl_native_heap *heap, const myl_native_type *type, unsigned char *address, unsigned depth) {
    if (depth > MYL_NATIVE_COW_TYPE_DEPTH_MAX) return 0;
    if (type->trace_mode == MYL_NATIVE_TRACE_NONE) return 1;
    switch (type->kind) {
    case MYL_NATIVE_POINTER: {
        int held = holds_payload(type, depth);
        if (held < 0) return 0;
        if (!held) return 1;
        void *payload;
        memcpy(&payload, address, sizeof payload);
        if (mark(payload)) return 1;
        void *copy = myl_native_cow_copy(heap, payload);
        if (!copy) return 0;
        if (counting_enabled) myl_native_cow_counters.pinned_copies++;
        memcpy(address, &copy, sizeof copy);
        return 1;
    }
    case MYL_NATIVE_ARRAY:
        for (size_t i = 0; i < type->count; ++i)
            if (!share_at(heap, type->fields[0].type, address + i * type->stride, depth + 1)) return 0;
        return 1;
    case MYL_NATIVE_RECORD:
    case MYL_NATIVE_VARIANT: {
        uint32_t tag = 0;
        if (type->kind == MYL_NATIVE_VARIANT) memcpy(&tag, address, sizeof tag);
        for (size_t i = 0; i < type->field_count; ++i) {
            const myl_native_field *field = &type->fields[i];
            if (type->kind == MYL_NATIVE_VARIANT && field->tag != tag) continue;
            if (!share_at(heap, field->type, address + field->offset, depth + 1)) return 0;
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
    int held = holds_payload(type, 0);
    if (held < 0) return 0;
    if (!held) return 1;
    return share_at(heap, type, address, 0);
}
/* Mark every payload the elements of a fresh copy `list` hold, now that the
 * original holds them too. A pinned element — possible only if a `mut`
 * argument's payload also sits in storage, which a unique argument never does
 * — is replaced in the copy by a copy of its own, so the copy is rooted here.
 * Returns 0 when such a copy is refused. */
static int mark_elements(myl_native_heap *heap, myl_native_list *list) {
    if (!list->storage) return 1;
    int held = holds_payload(list->element, 0);
    if (held < 0) return 0;
    if (!held) return 1;
    myl_native_root root;
    myl_native_root_push(heap, &root, &list, &pointer_type);
    int done = 1;
    for (size_t i = 0; i < list->length && done; ++i)
        done = share_at(heap, list->element, (unsigned char *)list->storage + i * list->element->size, 0);
    myl_native_root_pop(heap, &root);
    return done;
}
/* Mark every key and value the entries of a fresh copy `dict` hold. */
static int mark_entries(myl_native_heap *heap, myl_native_dictionary *dict) {
    int keys = holds_payload(dict->key, 0), values = holds_payload(dict->value, 0);
    if (keys < 0 || values < 0) return 0;
    if ((!keys && !values) || !dict->entries->storage) return 1;
    myl_native_root root;
    myl_native_root_push(heap, &root, &dict, &pointer_type);
    int done = 1;
    for (size_t i = 0; i < dict->entries->length && done; ++i) {
        unsigned char *entry = (unsigned char *)dict->entries->storage + i * dict->entry_type.size;
        if (keys) done = share_at(heap, dict->key, entry, 0);
        if (done && values) done = share_at(heap, dict->value, entry + dict->value_offset, 0);
    }
    myl_native_root_pop(heap, &root);
    return done;
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
int myl_native_cow_elements(myl_native_heap *heap, myl_native_list *list) {
    if (!list || !list->storage || list->element->kind != MYL_NATIVE_POINTER) return 1;
    int held = holds_payload(list->element, 0);
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
