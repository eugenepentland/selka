/* Copy on write over the tracing collector (D9 stage 3b): the header flags,
   sharing, uniqueness, nested payloads, pinned payloads, arenas, the escape
   copier, and every one of them under collection stress. */
#include "native_cow.h"
#include "native_regions.h"
#include "native_bytes.h"
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
static const myl_native_type pointer = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER};
static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN, .trace_mode = MYL_NATIVE_TRACE_NONE};
/* A managed list of integers and a list of such lists, described the way the
   generated descriptors describe them. */
static const myl_native_type integers = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER, .collection_kind = 1, .element = &number};
static const myl_native_type rows = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER, .collection_kind = 1, .element = &integers};
static const myl_native_type text_type = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER, .collection_kind = 2};
/* A record holding a list and a text, and a variant whose case 1 holds a list. */
typedef struct { myl_native_list *items; myl_native_text *name; int64_t count; } Holder;
static const myl_native_field holder_fields[] = {
    {.offset = offsetof(Holder, items), .type = &integers},
    {.offset = offsetof(Holder, name), .type = &text_type},
    {.offset = offsetof(Holder, count), .type = &number}};
static const myl_native_type holder = {.size = sizeof(Holder), .alignment = _Alignof(Holder), .kind = MYL_NATIVE_RECORD, .fields = holder_fields, .field_count = 3};
typedef struct { myl_native_list *items; } BoxBody;
static const myl_native_field box_fields[] = {{.offset = offsetof(BoxBody, items), .type = &integers}};
static const myl_native_type box_body = {.size = sizeof(BoxBody), .alignment = _Alignof(BoxBody), .kind = MYL_NATIVE_RECORD, .fields = box_fields, .field_count = 1};
static const myl_native_type box_pointer = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER, .collection_kind = 5, .element = &box_body};
typedef struct { int64_t value; void *next; } PureBody;
static const myl_native_type pure_box;
static const myl_native_field pure_fields[] = {
    {.offset = offsetof(PureBody, value), .type = &number},
    {.offset = offsetof(PureBody, next), .type = &pure_box}};
static const myl_native_type pure_body = {.size = sizeof(PureBody), .alignment = _Alignof(PureBody), .kind = MYL_NATIVE_RECORD, .fields = pure_fields, .field_count = 2};
static const myl_native_type pure_box = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER, .collection_kind = 5, .element = &pure_body};
typedef struct { void *next; myl_native_list *items; } MixedBody;
static const myl_native_type mixed_box;
static const myl_native_field mixed_fields[] = {
    {.offset = offsetof(MixedBody, next), .type = &mixed_box},
    {.offset = offsetof(MixedBody, items), .type = &integers}};
static const myl_native_type mixed_body = {.size = sizeof(MixedBody), .alignment = _Alignof(MixedBody), .kind = MYL_NATIVE_RECORD, .fields = mixed_fields, .field_count = 2};
static const myl_native_type mixed_box = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER, .collection_kind = 5, .element = &mixed_body};
typedef struct { uint32_t tag; myl_native_list *payload; } Choice;
static const myl_native_field choice_fields[] = {{.offset = offsetof(Choice, payload), .type = &integers, .tag = 1}};
static const myl_native_type choice = {.size = sizeof(Choice), .alignment = _Alignof(Choice), .kind = MYL_NATIVE_VARIANT, .fields = choice_fields, .field_count = 1};
static uintptr_t flags(const void *payload) {
    return ((const myl_native_object *)payload - 1)->mark & MYL_NATIVE_OBJECT_COW;
}
static myl_native_list *numbers(myl_native_heap *heap, int64_t first, size_t count) {
    myl_native_list *list = myl_native_list_new(heap, &number, count);
    assert(list);
    for (size_t i = 0; i < count; ++i) {
        int64_t value = first + (int64_t)i;
        assert(myl_native_list_append(heap, list, &value));
    }
    return list;
}
static int64_t at(const myl_native_list *list, size_t index) {
    int64_t value;
    assert(myl_native_list_get(list, index, &value));
    return value;
}
/* spec-case: COW-SHARED-1 -- the flags sit above the count and below the
   arena flag: they leave an object's count, its arena depth and its growth
   alone, and the collector keeps them through minor and full collections. */
static void header_flags(void) {
    assert(MYL_NATIVE_OBJECT_COUNT_MAX == ((size_t)1 << 58) - 1);
    assert(!(MYL_NATIVE_OBJECT_COUNT_BITS & (MYL_NATIVE_OBJECT_COW | MYL_NATIVE_OBJECT_ARENA | 3)));
    assert(!((((uintptr_t)MYL_NATIVE_ARENA_REGION_MAX) << MYL_NATIVE_ARENA_REGION_SHIFT) & MYL_NATIVE_OBJECT_COW));
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    heap.stress = 1;
    myl_native_list *list = numbers(&heap, 10, 3);
    myl_native_root root;
    myl_native_root_push(&heap, &root, &list, &pointer);
    ((myl_native_object *)list - 1)->mark |= MYL_NATIVE_OBJECT_COW;
    for (int i = 0; i < 4; ++i) myl_native_heap_collect(&heap);
    assert(flags(list) == MYL_NATIVE_OBJECT_COW && at(list, 2) == 12);
    /* A block past the largest size class grows in place with its flags. */
    size_t large = MYL_NATIVE_CLASS_LIMIT / 8 + 16;
    int64_t *block = myl_native_heap_alloc(&heap, &number, large);
    assert(block);
    myl_native_root block_root;
    myl_native_root_push(&heap, &block_root, &block, &pointer);
    ((myl_native_object *)block - 1)->mark |= MYL_NATIVE_OBJECT_SHARED;
    block = myl_native_heap_extend(&heap, block, large * 2);
    assert(block && flags(block) == MYL_NATIVE_OBJECT_SHARED);
    assert(myl_native_root_pop(&heap, &block_root));
    /* An arena payload keeps its depth under the flags. */
    assert(myl_native_region_begin(&heap) && myl_native_region_begin(&heap));
    myl_native_list *inner = numbers(&heap, 0, 1);
    ((myl_native_object *)inner - 1)->mark |= MYL_NATIVE_OBJECT_COW;
    assert(myl_native_header_region(inner) == 2);
    myl_native_region_end(&heap);
    myl_native_region_end(&heap);
    assert(myl_native_root_pop(&heap, &root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-SHARED-1 -- sharing sets the flag on a payload and only a
   payload: a text, an immortal literal and NULL pass through untouched. */
static void share_marks(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    myl_native_list *list = numbers(&heap, 1, 2);
    myl_native_root root;
    myl_native_root_push(&heap, &root, &list, &pointer);
    assert(myl_native_cow_payload(list) && !flags(list));
    assert(myl_native_cow_share(&heap, list) == list && flags(list) == MYL_NATIVE_OBJECT_SHARED);
    assert(myl_native_cow_share(&heap, NULL) == NULL);
    myl_native_text *name = myl_native_text_from_utf8(&heap, (const unsigned char *)"name", 4);
    assert(name && !myl_native_cow_payload(name));
    assert(myl_native_cow_share(&heap, name) == name && !flags(name));
    static struct { myl_native_object header; myl_native_list list; } literal = {
        .header = {.mark = MYL_NATIVE_OBJECT_LITERAL_MARK}};
    literal.header.element = ((myl_native_object *)list - 1)->element;
    assert(myl_native_cow_share(&heap, &literal.list) == &literal.list && !flags(&literal.list));
    assert(myl_native_root_pop(&heap, &root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-UNIQUE-1 -- an unshared payload is its own unique value; a
   shared one is copied once, the copy holds the same elements and is
   unshared, and the original is left exactly as it was. */
static void unique_copies(void) {
    /* An ordinary checks build incurs no counter work; this C test enables
       counting explicitly to verify the slow-path copy measurements below. */
    assert(myl_native_cow_counters.copies == 0);
    myl_native_cow_tally(MYL_NATIVE_COW_CHECK);
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    heap.stress = 1;
    myl_native_list *list = numbers(&heap, 5, 4), *copy = NULL;
    myl_native_root root, copy_root;
    myl_native_root_push(&heap, &root, &list, &pointer);
    myl_native_root_push(&heap, &copy_root, &copy, &pointer);
    myl_native_cow_statistics before = myl_native_cow_counters;
    assert(myl_native_cow_unique(&heap, list) == list);
    myl_native_cow_share(&heap, list);
    copy = myl_native_cow_unique(&heap, list);
    assert(copy && copy != list && !flags(copy) && flags(list) == MYL_NATIVE_OBJECT_SHARED);
    assert(copy->length == 4 && at(copy, 3) == 8 && copy->capacity >= copy->length);
    int64_t extra = 99;
    assert(myl_native_list_append(&heap, copy, &extra));
    assert(copy->length == 5 && list->length == 4 && at(list, 3) == 8);
    assert(myl_native_cow_counters.copies == before.copies + 1);
    assert(myl_native_cow_counters.copied_bytes == before.copied_bytes + 32);
    /* An empty list copies to an empty list with no storage. */
    myl_native_list *empty = myl_native_list_new(&heap, &number, 0);
    assert(empty);
    myl_native_cow_share(&heap, empty);
    myl_native_list *fresh = myl_native_cow_unique(&heap, empty);
    assert(fresh && fresh != empty && fresh->length == 0);
    assert(myl_native_root_pop(&heap, &copy_root) && myl_native_root_pop(&heap, &root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-NESTED-1 -- a copy shares its elements' payloads with the
   original, so each is marked shared: writing one row of the copy copies that
   row and leaves the original's row alone. */
static void nested_rows(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    heap.stress = 1;
    myl_native_list *grid = myl_native_list_new(&heap, &integers, 2), *copy = NULL, *row = NULL;
    assert(grid);
    myl_native_root grid_root, copy_root, row_root;
    myl_native_root_push(&heap, &grid_root, &grid, &pointer);
    myl_native_root_push(&heap, &copy_root, &copy, &pointer);
    myl_native_root_push(&heap, &row_root, &row, &pointer);
    for (int64_t i = 0; i < 2; ++i) {
        row = numbers(&heap, 10 * i, 2);
        assert(myl_native_list_append(&heap, grid, &row));
    }
    myl_native_cow_share(&heap, grid);
    copy = myl_native_cow_unique(&heap, grid);
    assert(copy && copy != grid);
    myl_native_list *first = ((myl_native_list **)copy->storage)[0];
    assert(first == ((myl_native_list **)grid->storage)[0] && flags(first) == MYL_NATIVE_OBJECT_SHARED);
    /* The write path: make the copy's row unique where it lives, then write. */
    row = myl_native_cow_unique(&heap, first);
    ((myl_native_list **)copy->storage)[0] = row;
    int64_t value = 7;
    assert(myl_native_list_set(row, 1, &value));
    assert(at(row, 1) == 7 && at(((myl_native_list **)grid->storage)[0], 1) == 1);
    /* The hoisted form makes every shared row unique at once. */
    myl_native_list *second = ((myl_native_list **)copy->storage)[1];
    assert(flags(second) == MYL_NATIVE_OBJECT_SHARED);
    assert(myl_native_cow_elements(&heap, copy));
    assert(((myl_native_list **)copy->storage)[1] != second && ((myl_native_list **)copy->storage)[0] == row);
    assert(!flags(((myl_native_list **)copy->storage)[1]) && at(((myl_native_list **)copy->storage)[1], 1) == 11);
    assert(myl_native_root_pop(&heap, &row_root) && myl_native_root_pop(&heap, &copy_root) && myl_native_root_pop(&heap, &grid_root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-NESTED-1 -- sharing a record or variant marks exactly the
   payloads it holds directly, never its text. */
static void share_values(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    Holder value = {0};
    myl_native_root root;
    myl_native_root_push(&heap, &root, &value, &holder);
    value.items = numbers(&heap, 0, 1);
    value.name = myl_native_text_from_utf8(&heap, (const unsigned char *)"n", 1);
    assert(myl_native_cow_share_value(&heap, &holder, &value));
    assert(flags(value.items) == MYL_NATIVE_OBJECT_SHARED && !flags(value.name));
    Choice none = {.tag = 0, .payload = numbers(&heap, 0, 1)};
    assert(myl_native_cow_share_value(&heap, &choice, &none) && !flags(none.payload));
    Choice some = {.tag = 1, .payload = none.payload};
    assert(myl_native_cow_share_value(&heap, &choice, &some) && flags(some.payload) == MYL_NATIVE_OBJECT_SHARED);
    assert(myl_native_cow_share_value(&heap, &number, &value.count));
    assert(myl_native_root_pop(&heap, &root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-PIN-1 -- a pinned payload is never marked: a transfer gets a
   fresh unique copy instead, inside a record too, and the pinned payload keeps
   being written in place. */
static void pinned_copies(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    heap.stress = 1;
    myl_native_list *list = numbers(&heap, 3, 2), *taken = NULL;
    myl_native_root root, taken_root;
    myl_native_root_push(&heap, &root, &list, &pointer);
    myl_native_root_push(&heap, &taken_root, &taken, &pointer);
    ((myl_native_object *)list - 1)->mark |= MYL_NATIVE_OBJECT_PINNED;
    uint64_t pinned = myl_native_cow_counters.pinned_copies;
    taken = myl_native_cow_share(&heap, list);
    assert(taken && taken != list && flags(list) == MYL_NATIVE_OBJECT_PINNED && !flags(taken));
    assert(myl_native_cow_counters.pinned_copies == pinned + 1);
    int64_t value = 40;
    assert(myl_native_list_set(list, 0, &value) && at(taken, 0) == 3);
    Holder held = {.items = list};
    myl_native_root held_root;
    myl_native_root_push(&heap, &held_root, &held, &holder);
    assert(myl_native_cow_share_value(&heap, &holder, &held));
    assert(held.items != list && at(held.items, 0) == 40 && !flags(held.items));
    assert(myl_native_root_pop(&heap, &held_root));
    assert(myl_native_root_pop(&heap, &taken_root) && myl_native_root_pop(&heap, &root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-UNIQUE-1 -- a dictionary copy keeps every entry, its order
   and its index without rehashing; removed entries are settled first; the
   copy's values are shared with the original; writes stay apart. */
static void dictionaries(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    heap.stress = 1;
    myl_native_dictionary *dict = myl_native_dictionary_new(&heap, &number, &integers, 0), *copy = NULL;
    assert(dict);
    myl_native_list *row = NULL;
    myl_native_root root, copy_root, row_root;
    myl_native_root_push(&heap, &root, &dict, &pointer);
    myl_native_root_push(&heap, &copy_root, &copy, &pointer);
    myl_native_root_push(&heap, &row_root, &row, &pointer);
    for (int64_t key = 0; key < 40; ++key) {
        row = numbers(&heap, key, 1);
        assert(myl_native_dictionary_write(&heap, dict, &key, &row));
    }
    int64_t gone = 7;
    assert(myl_native_dictionary_pop(dict, &gone, &row));
    assert(dict->dead == 1);
    myl_native_cow_share(&heap, dict);
    copy = myl_native_cow_unique(&heap, dict);
    assert(copy && copy != dict && !flags(copy) && myl_native_dictionary_length(copy) == 39);
    assert(!dict->dead && copy->entries->element == &copy->entry_type && copy->index.capacity == dict->index.capacity);
    assert(((myl_native_object *)copy->entries->storage - 1)->element == &copy->entry_type);
    for (int64_t key = 0; key < 40; ++key) {
        myl_native_list *found = NULL;
        int present = myl_native_dictionary_read(copy, &key, &found);
        assert(present == (key != 7));
        if (present) assert(found && at(found, 0) == key && flags(found) == MYL_NATIVE_OBJECT_SHARED);
    }
    int64_t key = 100, first_key = 0;
    myl_native_list *first = NULL;
    row = numbers(&heap, 100, 1);
    assert(myl_native_dictionary_write(&heap, copy, &key, &row));
    assert(myl_native_dictionary_length(copy) == 40 && myl_native_dictionary_length(dict) == 39);
    assert(!myl_native_dictionary_contains(dict, &key));
    assert(myl_native_dictionary_key_at(copy, 0, &first_key) && first_key == 0);
    assert(myl_native_dictionary_value_at(copy, 0, &first) && at(first, 0) == 0);
    assert(myl_native_root_pop(&heap, &row_root) && myl_native_root_pop(&heap, &copy_root) && myl_native_root_pop(&heap, &root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-UNIQUE-1 -- a byte buffer whose block a published snapshot
   reads copies into a private block the snapshot never sees. */
static void byte_buffers(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    heap.stress = 1;
    static const myl_native_type byte = {.size = 1, .alignment = 1, .kind = MYL_NATIVE_PLAIN, .trace_mode = MYL_NATIVE_TRACE_NONE};
    myl_native_bytes *buffer = myl_native_list_new(&heap, &byte, 8), *snapshot = NULL, *copy = NULL;
    assert(buffer);
    myl_native_root root, snapshot_root, copy_root;
    myl_native_root_push(&heap, &root, &buffer, &pointer);
    myl_native_root_push(&heap, &snapshot_root, &snapshot, &pointer);
    myl_native_root_push(&heap, &copy_root, &copy, &pointer);
    for (unsigned char c = 'a'; c < 'e'; ++c) assert(myl_native_list_append(&heap, buffer, &c));
    snapshot = myl_native_bytes_buffer_snapshot(&heap, buffer);
    assert(snapshot && buffer->capacity == 0);
    myl_native_cow_share(&heap, buffer);
    copy = myl_native_cow_unique(&heap, buffer);
    assert(copy && copy != buffer && copy->storage != buffer->storage && !copy->work.owner);
    assert(copy->length == 4 && copy->capacity >= 4 && !memcmp(copy->storage, "abcd", 4));
    ((unsigned char *)copy->storage)[0] = 'z';
    assert(((unsigned char *)snapshot->storage)[0] == 'a');
    assert(myl_native_root_pop(&heap, &copy_root) && myl_native_root_pop(&heap, &snapshot_root) && myl_native_root_pop(&heap, &root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-UNIQUE-1 -- a copy lives where the payload it replaces lives:
   an arena payload is copied into its own arena even from a deeper one, and a
   tracing-heap payload into the tracing heap. The escape copier keeps a shared
   source's clone shared. */
static void arenas(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    assert(myl_native_region_begin(&heap));
    myl_native_list *outer = numbers(&heap, 0, 2);
    assert(myl_native_header_region(outer) == 1);
    myl_native_list *snapshot = outer;
    assert(myl_native_region_begin(&heap));
    myl_native_cow_share(&heap, outer);
    myl_native_list *copy = myl_native_cow_unique(&heap, outer);
    assert(copy && myl_native_header_region(copy) == 1 && myl_native_header_region(copy->storage) == 1);
    outer = copy;
    int64_t updated = 42;
    assert(myl_native_list_set(outer, 0, &updated));
    myl_native_region_end(&heap);
    /* The old owner can still read its replacement after the inner arena's
       whole region was released; allocating the replacement there would leave
       `outer` dangling. The original holder is unchanged. */
    assert(at(outer, 0) == 42 && at(snapshot, 0) == 0);
    myl_native_list *heap_list = NULL;
    myl_native_root root;
    myl_native_root_push(&heap, &root, &heap_list, &pointer);
    myl_native_region_end(&heap);
    heap_list = numbers(&heap, 0, 1);
    assert(myl_native_region_begin(&heap));
    myl_native_cow_share(&heap, heap_list);
    myl_native_list *heap_copy = myl_native_cow_unique(&heap, heap_list);
    assert(heap_copy && myl_native_header_region(heap_copy) == 0);
    heap_list = heap_copy;
    /* Escape: a shared arena list escapes as a shared clone. */
    myl_native_list *grid = myl_native_list_new(&heap, &integers, 2);
    myl_native_list *row = numbers(&heap, 1, 1);
    assert(grid && row && myl_native_list_append(&heap, grid, &row) && myl_native_list_append(&heap, grid, &row));
    myl_native_cow_share(&heap, row);
    myl_native_list *escaped = NULL;
    assert(myl_native_region_escape(&heap, &rows, &grid, &escaped));
    myl_native_list *clone = ((myl_native_list **)escaped->storage)[0];
    assert(clone != row && clone == ((myl_native_list **)escaped->storage)[1]);
    assert(flags(clone) == MYL_NATIVE_OBJECT_SHARED && !flags(escaped));
    myl_native_region_end(&heap);
    assert(at(heap_list, 0) == 0 && myl_native_header_region(heap_list) == 0);
    assert(myl_native_root_pop(&heap, &root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-UNIQUE-1 -- under collection at every allocation, a long run
   of shares, writes and drops keeps every value intact, and once nothing is
   rooted every copy is reclaimed. */
static void stress_run(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    heap.stress = 1;
    myl_native_list *grid = myl_native_list_new(&heap, &integers, 0), *snapshot = NULL, *row = NULL;
    assert(grid);
    myl_native_root grid_root, snapshot_root, row_root;
    myl_native_root_push(&heap, &grid_root, &grid, &pointer);
    myl_native_root_push(&heap, &snapshot_root, &snapshot, &pointer);
    myl_native_root_push(&heap, &row_root, &row, &pointer);
    for (int64_t i = 0; i < 64; ++i) {
        row = numbers(&heap, i, 3);
        assert(myl_native_list_append(&heap, grid, &row));
        row = NULL;
        if (i % 8 == 0) {
            /* A snapshot: share, then write the live value through its path. */
            snapshot = myl_native_cow_share(&heap, grid);
            grid = myl_native_cow_unique(&heap, grid);
            assert(grid && grid != snapshot);
            size_t index = (size_t)i / 2;
            myl_native_list **slot = (myl_native_list **)grid->storage + index;
            *slot = myl_native_cow_unique(&heap, *slot);
            assert(*slot);
            int64_t value = -1;
            assert(myl_native_list_set(*slot, 0, &value));
            assert(at(((myl_native_list **)snapshot->storage)[index], 0) == (int64_t)index);
        }
    }
    assert(grid->length == 64 && at(((myl_native_list **)grid->storage)[63], 2) == 65);
    assert(at(((myl_native_list **)grid->storage)[28], 0) == -1);
    assert(myl_native_root_pop(&heap, &row_root) && myl_native_root_pop(&heap, &snapshot_root) && myl_native_root_pop(&heap, &grid_root));
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 0);
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-SHARED-1 -- inline descriptor nesting beyond 64 levels
   still reaches and marks a mutable payload; an extreme depth is refused
   cleanly instead of silently leaving its descendant unmarked. */
static void deep_inline_descriptors(void) {
    enum { DEPTH = 1030 };
    myl_native_type types[DEPTH];
    myl_native_field fields[DEPTH];
    for (size_t i = 0; i < DEPTH; ++i) {
        fields[i] = (myl_native_field){.offset = 0, .type = i + 1 < DEPTH ? &types[i + 1] : &integers};
        types[i] = (myl_native_type){.size = sizeof(void *), .alignment = _Alignof(void *),
            .kind = MYL_NATIVE_RECORD, .fields = &fields[i], .field_count = 1};
    }
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    myl_native_list *list = numbers(&heap, 1, 1);
    myl_native_root root;
    myl_native_root_push(&heap, &root, &list, &pointer);
    assert(myl_native_cow_share_value(&heap, &types[DEPTH - 81], &list));
    assert(flags(list) == MYL_NATIVE_OBJECT_SHARED);
    ((myl_native_object *)list - 1)->mark &= ~MYL_NATIVE_OBJECT_SHARED;
    assert(!myl_native_cow_share_value(&heap, &types[0], &list));
    assert(myl_native_cow_take_depth_failure());
    assert(!myl_native_cow_take_depth_failure());
    assert(!flags(list));
    assert(myl_native_root_pop(&heap, &root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-SHARED-1 -- a fresh outer list stays unique while its
   directly held mutable children become shared with the shallow-copy source. */
static void fresh_children(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    heap.stress = 1;
    myl_native_list *outer = myl_native_list_new(&heap, &integers, 1);
    myl_native_list *row = NULL;
    assert(outer);
    myl_native_root outer_root, row_root;
    myl_native_root_push(&heap, &outer_root, &outer, &pointer);
    myl_native_root_push(&heap, &row_root, &row, &pointer);
    row = numbers(&heap, 7, 1);
    assert(myl_native_list_append(&heap, outer, &row));
    assert(myl_native_cow_share_children(&heap, &rows, &outer));
    assert(!flags(outer) && flags(row) == MYL_NATIVE_OBJECT_SHARED);
    myl_native_list *copy = myl_native_cow_unique(&heap, row);
    assert(copy && copy != row);
    int64_t changed = 12;
    assert(myl_native_list_set(copy, 0, &changed));
    assert(at(row, 0) == 7);
    assert(myl_native_root_pop(&heap, &row_root) && myl_native_root_pop(&heap, &outer_root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-SHARED-1 -- a bulk source shares children in place until a
   pinned child needs replacement; then only its private source copy changes. */
static void bulk_source_children(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    heap.stress = 1;
    myl_native_list *source = myl_native_list_new(&heap, &integers, 1), *taken = NULL, *row = NULL;
    assert(source);
    myl_native_root source_root, taken_root, row_root;
    myl_native_root_push(&heap, &source_root, &source, &pointer);
    myl_native_root_push(&heap, &taken_root, &taken, &pointer);
    myl_native_root_push(&heap, &row_root, &row, &pointer);
    row = numbers(&heap, 6, 1);
    assert(myl_native_list_append(&heap, source, &row));
    taken = source;
    assert(myl_native_cow_copy_source_children(&heap, &rows, &taken) && taken == source);
    assert(flags(row) == MYL_NATIVE_OBJECT_SHARED);
    ((myl_native_object *)row - 1)->mark &= ~MYL_NATIVE_OBJECT_SHARED;
    ((myl_native_object *)row - 1)->mark |= MYL_NATIVE_OBJECT_PINNED;
    assert(myl_native_cow_copy_source_children(&heap, &rows, &taken));
    assert(taken != source && ((myl_native_list **)source->storage)[0] == row);
    assert(((myl_native_list **)taken->storage)[0] != row);
    assert(flags(row) == MYL_NATIVE_OBJECT_PINNED);
    assert(myl_native_root_pop(&heap, &row_root) && myl_native_root_pop(&heap, &taken_root) && myl_native_root_pop(&heap, &source_root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-NESTED-1 -- copying an immutable recursive box is constant
   time. Projecting its body creates a private inline value and shares only
   directly held mutable children. A pinned child is copied into that value,
   never patched into the source box. */
static void boxed_children(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    heap.stress = 1;
    BoxBody *source = myl_native_heap_alloc(&heap, &box_body, 1), *copy = NULL;
    BoxBody projected = {0}, pinned_projection = {0};
    myl_native_list *row = NULL;
    assert(source);
    myl_native_root source_root, copy_root, row_root, projected_root, pinned_root;
    myl_native_root_push(&heap, &source_root, &source, &box_pointer);
    myl_native_root_push(&heap, &copy_root, &copy, &box_pointer);
    myl_native_root_push(&heap, &row_root, &row, &pointer);
    myl_native_root_push(&heap, &projected_root, &projected, &box_body);
    myl_native_root_push(&heap, &pinned_root, &pinned_projection, &box_body);
    row = numbers(&heap, 4, 1);
    source->items = row;
    copy = source;
    assert(myl_native_cow_share_value(&heap, &box_pointer, &copy));
    assert(copy == source && !flags(row));
    assert(myl_native_cow_unbox(&heap, &box_pointer, copy, &projected));
    assert(projected.items == row && flags(row) == MYL_NATIVE_OBJECT_SHARED);
    /* The child was exposed before another box copy; it is already protected. */
    copy = source;
    assert(myl_native_cow_share_value(&heap, &box_pointer, &copy));
    assert(copy == source);
    myl_native_list *changed = myl_native_cow_unique(&heap, projected.items);
    assert(changed && changed != row);
    projected.items = changed;
    int64_t extra = 9;
    assert(myl_native_list_append(&heap, projected.items, &extra));
    assert(at(source->items, 0) == 4 && source->items->length == 1);
    ((myl_native_object *)row - 1)->mark &= ~MYL_NATIVE_OBJECT_SHARED;
    ((myl_native_object *)row - 1)->mark |= MYL_NATIVE_OBJECT_PINNED;
    assert(myl_native_cow_unbox(&heap, &box_pointer, copy, &pinned_projection));
    assert(copy == source && source->items == row && pinned_projection.items != row);
    assert(flags(row) == MYL_NATIVE_OBJECT_PINNED && at(pinned_projection.items, 0) == 4);
    assert(myl_native_root_pop(&heap, &pinned_root) && myl_native_root_pop(&heap, &projected_root));
    assert(myl_native_root_pop(&heap, &row_root) && myl_native_root_pop(&heap, &copy_root) && myl_native_root_pop(&heap, &source_root));
    myl_native_heap_destroy(&heap);
}
/* spec-case: COW-SHARED-1 -- transferring a recursive box never visits its
   descendants. Projecting a mixed body marks only the sibling list there. */
static void recursive_descriptor_reachability(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 26);
    heap.stress = 1;
    PureBody *head = NULL, *taken = NULL;
    myl_native_root head_root, taken_root;
    myl_native_root_push(&heap, &head_root, &head, &pure_box);
    myl_native_root_push(&heap, &taken_root, &taken, &pure_box);
    for (int64_t i = 0; i < 1200; ++i) {
        PureBody *next = myl_native_heap_alloc(&heap, &pure_body, 1);
        assert(next);
        next->value = i;
        next->next = head;
        head = next;
    }
    taken = head;
    assert(myl_native_cow_share_value(&heap, &pure_box, &taken));
    assert(taken == head && head->value == 1199 && !flags(head));
    MixedBody *mixed = NULL, *mixed_copy = NULL;
    myl_native_list *row = NULL;
    myl_native_root mixed_root, mixed_copy_root, row_root;
    myl_native_root_push(&heap, &mixed_root, &mixed, &mixed_box);
    myl_native_root_push(&heap, &mixed_copy_root, &mixed_copy, &mixed_box);
    myl_native_root_push(&heap, &row_root, &row, &pointer);
    mixed = myl_native_heap_alloc(&heap, &mixed_body, 1);
    assert(mixed);
    row = numbers(&heap, 7, 1);
    mixed->items = row;
    mixed_copy = mixed;
    assert(myl_native_cow_share_value(&heap, &mixed_box, &mixed_copy));
    assert(mixed_copy == mixed && !flags(row));
    MixedBody projected = {0};
    myl_native_root projected_root;
    myl_native_root_push(&heap, &projected_root, &projected, &mixed_body);
    assert(myl_native_cow_unbox(&heap, &mixed_box, mixed_copy, &projected));
    assert(projected.items == row && flags(row) == MYL_NATIVE_OBJECT_SHARED);
    assert(!myl_native_cow_take_depth_failure());
    heap.stress = 0;
    for (int i = 0; i < 1100; ++i) {
        MixedBody *next = myl_native_heap_alloc(&heap, &mixed_body, 1);
        assert(next);
        next->next = mixed;
        mixed = next;
    }
    mixed_copy = mixed;
    assert(myl_native_cow_share_value(&heap, &mixed_box, &mixed_copy));
    assert(mixed_copy == mixed && !myl_native_cow_take_depth_failure());
    assert(myl_native_root_pop(&heap, &projected_root));
    assert(!myl_native_cow_take_depth_failure());
    assert(myl_native_root_pop(&heap, &row_root) && myl_native_root_pop(&heap, &mixed_copy_root) && myl_native_root_pop(&heap, &mixed_root));
    assert(myl_native_root_pop(&heap, &taken_root) && myl_native_root_pop(&heap, &head_root));
    myl_native_heap_destroy(&heap);
}
int main(void) {
    header_flags();
    share_marks();
    unique_copies();
    nested_rows();
    share_values();
    pinned_copies();
    dictionaries();
    byte_buffers();
    arenas();
    stress_run();
    deep_inline_descriptors();
    fresh_children();
    bulk_source_children();
    boxed_children();
    recursive_descriptor_reachability();
    puts("native cow tests passed");
    return 0;
}
