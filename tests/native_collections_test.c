#include "native_collections.h"
#include "native_text.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static const myl_native_type number = { .size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN };
static const myl_native_type pointer = { .size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER };
int main(void) {
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
