#include "native_collections.h"
#include "native_text.h"
#include <assert.h>
#include <stdint.h>
#include <string.h>

static unsigned slow_calls;
static unsigned saturating_calls;
static myl_native_text test_texts[130];
static uint32_t test_points[130];
static size_t test_text_count;

myl_native_text *myl_native_text_new(myl_native_heap *heap, size_t count) {
    (void)heap;
    assert(count <= 1 && test_text_count < 130);
    myl_native_text *text = &test_texts[test_text_count];
    text->storage = &test_points[test_text_count++];
    text->capacity = count;
    return text;
}

myl_native_text *myl_native_text_copy(myl_native_heap *heap, myl_native_text *input,
                                      size_t start, size_t count) {
    myl_native_text *text = myl_native_text_new(heap, count);
    if (count) memcpy(text->storage, (uint32_t *)input->storage + start, count * sizeof(uint32_t));
    text->length = count;
    return text;
}
int __real_myl_native_list_append(myl_native_heap *heap, myl_native_list *list, const void *value) {
    (void)heap; (void)list; (void)value;
    slow_calls++;
    return 7;
}

uint64_t __real_myl_qbe_int_binary(void *context, uint64_t op, uint64_t is_signed,
                                   uint64_t width, uint64_t left, uint64_t right) {
    (void)context; (void)is_signed; (void)width; (void)left; (void)right;
    assert(op >= 23 && op <= 25);
    saturating_calls++;
    return 91;
}

int __wrap_myl_native_list_get(const myl_native_list *, size_t, void *);
int __wrap_myl_native_list_append(myl_native_heap *, myl_native_list *, const void *);
myl_native_text *__wrap_myl_native_text_at(myl_native_heap *, myl_native_text *, int64_t);
myl_native_text *__wrap_myl_native_text_slice(myl_native_heap *, myl_native_text *, int64_t, int64_t);
uint64_t __wrap_myl_qbe_int_cast(void *, uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t __wrap_myl_qbe_int_neg(void *, uint64_t, uint64_t, uint64_t);
uint64_t __wrap_myl_qbe_int_binary(void *, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);

int main(void) {
    const myl_native_type element = { .size = sizeof(uint64_t), .alignment = _Alignof(uint64_t), .kind = MYL_NATIVE_PLAIN };
    uint64_t storage[2] = { 11, 22 }, output = 0, value = 33;
    myl_native_list list = { .length = 2, .capacity = 2, .element = &element, .storage = storage };
    assert(__wrap_myl_native_list_get(&list, 1, &output) == 1 && output == 22);
    assert(__wrap_myl_native_list_append(NULL, &list, &value) == 7 && slow_calls == 1);
    list.length = 1;
    assert(__wrap_myl_native_list_append(NULL, &list, &value) == 1);
    assert(list.length == 2 && list.generation == 1 && storage[1] == 33);
    assert(__wrap_myl_qbe_int_cast(NULL, 1, 1, 8, (uint64_t)-3) == (uint64_t)-3);
    assert(__wrap_myl_qbe_int_neg(NULL, 1, 8, 3) == (uint64_t)-3);
    assert(__wrap_myl_qbe_int_cast(NULL, 0, 0, 8, 253) == 253);
    assert(__wrap_myl_qbe_int_binary(NULL, 20, 1, 8, 127, 1) == (uint64_t)-128);
    assert(__wrap_myl_qbe_int_binary(NULL, 0, 1, 8, 40, 2) == 42);
    assert(__wrap_myl_qbe_int_binary(NULL, 5, 1, 64, (uint64_t)-7, 3) == (uint64_t)-3);
    assert(__wrap_myl_qbe_int_binary(NULL, 6, 1, 64, (uint64_t)-7, 3) == 2);
    assert(__wrap_myl_qbe_int_binary(NULL, 5, 0, 64, UINT64_MAX, 2) == UINT64_MAX / 2);
    assert(__wrap_myl_qbe_int_binary(NULL, 6, 0, 64, UINT64_MAX, 2) == 1);
    assert(__wrap_myl_qbe_int_binary(NULL, 18, 0, 8, 1, 7) == 128);
    assert(__wrap_myl_qbe_int_binary(NULL, 23, 1, 8, 1, 2) == 91 && saturating_calls == 1);

    uint32_t input_points[] = { 'A', 'B', 'C' };
    myl_native_text input = { .length = 3, .capacity = 3, .storage = input_points };
    myl_native_heap heap = { 0 };
    myl_native_text *scalar = __wrap_myl_native_text_at(&heap, &input, -2);
    assert(scalar && scalar->length == 1 && ((uint32_t *)scalar->storage)[0] == 'B');
    assert(__wrap_myl_native_text_at(&heap, &input, 1) == scalar);
    myl_native_text *slice = __wrap_myl_native_text_slice(&heap, &input, 1, -1);
    assert(slice && slice->length == 1 && ((uint32_t *)slice->storage)[0] == 'B');
    return 0;
}
