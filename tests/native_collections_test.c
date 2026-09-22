#include "native_collections.h"
#include "native_text.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static const myl_native_type number = { .size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN };
static const myl_native_type pointer = { .size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER };
/* spec-case: LIST-GROWTH-1. A list grown past the size classes keeps every
   element it already stored — the backing is extended in its own reservation,
   so the elements are neither copied nor faulted a second time — and an append
   whose source lies inside the backing being replaced, which is the one value
   that could not survive a move, still copies from the right place. */
static void growth_keeps_elements(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 64u << 20);
    myl_native_list *list = myl_native_list_new(&heap, &number, 0);
    assert(list);
    myl_native_root root;
    myl_native_root_push(&heap, &root, &list, &pointer);
    for (int64_t i = 0; i < 200000; ++i) assert(myl_native_list_append(&heap, list, &i));
    assert(list->length == 200000 && list->capacity >= 262144);
    for (size_t i = 0; i < list->length; i += 9973) {
        int64_t held = -1;
        assert(myl_native_list_get(list, i, &held) && held == (int64_t)i);
    }
    /* Extending a list with itself feeds the append a pointer into the backing
       every growth replaces, so this is the aliased path the copy still serves. */
    assert(myl_native_list_extend(&heap, list, list));
    assert(list->length == 400000);
    for (size_t i = 0; i < list->length; i += 9973) {
        int64_t held = -1;
        assert(myl_native_list_get(list, i, &held) && held == (int64_t)(i % 200000));
    }
    myl_native_heap_collect(&heap);
    int64_t tail = -1;
    assert(myl_native_list_get(list, 399999, &tail) && tail == 199999);
    myl_native_root_pop(&heap, &root);
    myl_native_heap_destroy(&heap);
}
/* spec-case: LIST-SORT-RUNS-1. The adaptive merge against a stable insertion
   reference, over lengths on both sides of the insertion and merge thresholds
   and inputs from random through already sorted, reversed and run-structured.
   Texts with equal payloads in separate objects and signed zeros are the
   equal elements whose order is observable, so they check stability. */
static uint64_t sort_state = 88172645463325252u;
static uint64_t sort_noise(void) {
    sort_state ^= sort_state << 13;
    sort_state ^= sort_state >> 7;
    sort_state ^= sort_state << 17;
    return sort_state;
}
static int64_t sort_shape(size_t i, size_t count, int shape) {
    switch (shape) {
    case 0: return (int64_t)(sort_noise() >> 40) - 8388608;
    case 1: return (int64_t)i;
    case 2: return (int64_t)(count - i);
    case 3: return (int64_t)(i % 37);
    case 4: return (i / 50) % 2 ? (int64_t)i : (int64_t)(count - i);
    default: return (int64_t)(sort_noise() >> 61);
    }
}
static void sort_matches_reference(void) {
    static const size_t lengths[] = { 2, 3, 16, 17, 31, 32, 33, 64, 65, 257, 1000, 4099 };
    static const unsigned char *const words[] = { (const unsigned char *)"", (const unsigned char *)"a",
        (const unsigned char *)"\xc3\xa9", (const unsigned char *)"\xf0\x9f\x98\x80", (const unsigned char *)"ab",
        (const unsigned char *)"\xe2\x82\xac", (const unsigned char *)"A", (const unsigned char *)"\x7f" };
    myl_native_heap heap;
    myl_native_heap_init(&heap, 64u << 20);
    /* Every object stays reachable from a root: the texts through `held`, and
       each round's three lists through their own roots. */
    myl_native_list *held = myl_native_list_new(&heap, &pointer, 32);
    assert(held);
    myl_native_root held_root;
    myl_native_root_push(&heap, &held_root, &held, &pointer);
    myl_native_text *texts[32];
    for (size_t i = 0; i < 32; i++) {
        texts[i] = myl_native_text_from_utf8(&heap, words[i % 8], strlen((const char *)words[i % 8]));
        assert(texts[i] && myl_native_list_append(&heap, held, &texts[i]));
    }
    int64_t *expected = malloc(4099 * sizeof *expected);
    myl_native_text **order = malloc(4099 * sizeof *order);
    double *zeros = malloc(4099 * sizeof *zeros);
    assert(expected && order && zeros);
    for (size_t l = 0; l < sizeof lengths / sizeof lengths[0]; l++) {
        size_t count = lengths[l];
        for (int shape = 0; shape < 6; shape++) {
            myl_native_list *numbers = NULL, *strings = NULL, *floats = NULL;
            myl_native_root numbers_root, strings_root, floats_root;
            myl_native_root_push(&heap, &numbers_root, &numbers, &pointer);
            myl_native_root_push(&heap, &strings_root, &strings, &pointer);
            myl_native_root_push(&heap, &floats_root, &floats, &pointer);
            numbers = myl_native_list_new(&heap, &number, count);
            strings = myl_native_list_new(&heap, &pointer, count);
            floats = myl_native_list_new(&heap, &number, count);
            assert(numbers && strings && floats);
            for (size_t i = 0; i < count; i++) {
                int64_t value = sort_shape(i, count, shape);
                myl_native_text *text = texts[(uint64_t)value % 32];
                double real = value % 3 == 0 ? (value % 2 ? -0.0 : 0.0) : (double)value;
                assert(myl_native_list_append(&heap, numbers, &value));
                assert(myl_native_list_append(&heap, strings, &text));
                assert(myl_native_list_append(&heap, floats, &real));
                size_t at = i;
                while (at > 0 && expected[at - 1] > value) { expected[at] = expected[at - 1]; at--; }
                expected[at] = value;
                at = i;
                while (at > 0 && myl_native_text_compare(order[at - 1], text) > 0) { order[at] = order[at - 1]; at--; }
                order[at] = text;
                at = i;
                while (at > 0 && zeros[at - 1] > real) { zeros[at] = zeros[at - 1]; at--; }
                zeros[at] = real;
            }
            assert(myl_native_list_sort(numbers, 0) && myl_native_list_sort(strings, 3) && myl_native_list_sort(floats, 2));
            assert(memcmp(numbers->storage, expected, count * sizeof *expected) == 0);
            assert(memcmp(strings->storage, order, count * sizeof *order) == 0);
            assert(memcmp(floats->storage, zeros, count * sizeof *zeros) == 0);
            myl_native_root_pop(&heap, &floats_root);
            myl_native_root_pop(&heap, &strings_root);
            myl_native_root_pop(&heap, &numbers_root);
        }
    }
    myl_native_root_pop(&heap, &held_root);
    free(zeros);
    free(order);
    free(expected);
    myl_native_heap_destroy(&heap);
}
int main(void) {
    growth_keeps_elements();
    sort_matches_reference();
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 20);
    heap.stress = 1;
    myl_native_list *list = myl_native_list_new(&heap, &number, 0);
    assert(list);
    myl_native_root root;
    myl_native_root_push(&heap, &root, &list, &pointer);
    myl_native_list *identity = list;
    for (int64_t i = 0; i < 100; ++i) assert(myl_native_list_append(&heap, list, &i));
    assert(list == identity && list->length == 100);
    for (int64_t i = 0; i < 100; ++i) {
        int64_t value;
        assert(myl_native_list_get(list, (size_t)i, &value) && value == i);
    }
    int64_t value;
    assert(!myl_native_list_get(list, 100, &value));
    assert(myl_native_list_pop(list, &value) && value == 99);
    myl_native_list_clear(list);
    assert(list->length == 0);
    /* Reverse-ordered input is large enough to catch a quadratic in-place
       implementation, and duplicate keys retain their source order. */
    for (int64_t i = 4095; i >= 0; --i) assert(myl_native_list_append(&heap, list, &i));
    assert(myl_native_list_sort(list, 0));
    for (int64_t i = 0; i < 4096; ++i) {
        int64_t sorted;
        assert(myl_native_list_get(list, (size_t)i, &sorted) && sorted == i);
    }
    myl_native_list *floats = myl_native_list_new(&heap, &number, 4);
    assert(floats);
    myl_native_root floats_root;
    myl_native_root_push(&heap, &floats_root, &floats, &pointer);
    double nan = NAN, negative_zero = -0.0, positive_zero = 0.0, low = -1.0;
    assert(myl_native_list_append(&heap, floats, &nan));
    assert(myl_native_list_append(&heap, floats, &negative_zero));
    assert(myl_native_list_append(&heap, floats, &positive_zero));
    assert(myl_native_list_append(&heap, floats, &low));
    assert(myl_native_list_sort(floats, 2));
    double sorted_float;
    assert(myl_native_list_get(floats, 0, &sorted_float) && sorted_float == -1.0);
    assert(myl_native_list_get(floats, 1, &sorted_float) && signbit(sorted_float));
    assert(myl_native_list_get(floats, 2, &sorted_float) && !signbit(sorted_float));
    assert(myl_native_list_get(floats, 3, &sorted_float) && isnan(sorted_float));
    myl_native_list *texts = myl_native_list_new(&heap, &pointer, 3);
    assert(texts);
    myl_native_root texts_root;
    myl_native_root_push(&heap, &texts_root, &texts, &pointer);
    myl_native_text *accent = myl_native_text_from_utf8(&heap, (const unsigned char *)"\xc3\xa9", 2);
    assert(accent);
    assert(myl_native_list_append(&heap, texts, &accent));
    myl_native_text *apple = myl_native_text_from_utf8(&heap, (const unsigned char *)"apple", 5);
    assert(apple);
    assert(myl_native_list_append(&heap, texts, &apple));
    myl_native_text *capital = myl_native_text_from_utf8(&heap, (const unsigned char *)"Apple", 5);
    assert(capital);
    assert(myl_native_list_append(&heap, texts, &capital));
    assert(myl_native_list_sort(texts, 3));
    myl_native_text *sorted_text;
    assert(myl_native_list_get(texts, 0, &sorted_text) && sorted_text == capital);
    assert(myl_native_list_get(texts, 1, &sorted_text) && sorted_text == apple);
    assert(myl_native_list_get(texts, 2, &sorted_text) && sorted_text == accent);
    assert(myl_native_text_compare(capital, apple) < 0);
    assert(myl_native_text_compare(accent, accent) == 0);
    myl_native_root_pop(&heap, &texts_root);
    myl_native_root_pop(&heap, &floats_root);
    myl_native_list_clear(list);
    assert(list->length == 0);
    myl_native_list *refs = myl_native_list_new(&heap, &pointer, 0);
    assert(refs);
    myl_native_root refs_root;
    myl_native_root_push(&heap, &refs_root, &refs, &pointer);
    /* Self cycle and child list survive allocation safepoints. */
    assert(myl_native_list_append(&heap, refs, &refs));
    assert(myl_native_list_append(&heap, refs, &list));
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 4);
    myl_native_list *child;
    assert(myl_native_list_get(refs, 0, &child) && child == refs);
    assert(myl_native_list_get(refs, 1, &child) && child == list);
    myl_native_root_pop(&heap, &refs_root);
    myl_native_root_pop(&heap, &root);
    myl_native_heap_collect(&heap);
    assert(heap.objects_live == 0 && heap.bytes == 0);
    myl_native_heap_destroy(&heap);
    /* Failed growth leaves list contents and root chain intact. */
    myl_native_heap_init(&heap, 256);
    list = myl_native_list_new(&heap, &number, 0);
    assert(list);
    myl_native_root_push(&heap, &root, &list, &pointer);
    int64_t sentinel = 31;
    size_t accepted = 0;
    while (myl_native_list_append(&heap, list, &sentinel)) accepted++;
    assert(list->length == accepted && heap.roots == &root);
    for (size_t i = 0; i < accepted; i++) {
        assert(myl_native_list_get(list, i, &value) && value == sentinel);
    }
    list->generation = UINT64_MAX;
    assert(!myl_native_list_append(&heap, list, &sentinel));
    assert(list->generation == UINT64_MAX);
    myl_native_heap_destroy(&heap);
    puts("native collections tests passed");
}
