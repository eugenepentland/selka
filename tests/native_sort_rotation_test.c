/* spec-case: LIST-SORT-RUNS-1. Strictly separated ascending runs use one
 * production bulk rotation, while equal/interleaved boundaries keep stable
 * merge order. Host wrappers prove the actual path and unchanged scratch
 * reservation/refusal; the reference is independent stable insertion. */
#include "native_collections.h"
#include "native_text.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *__real_malloc(size_t);
void __real_free(void *);
void *__real_memmove(void *, const void *, size_t);
static int armed, refuse;
static size_t requests, requested, moves, moved, cases, failures;
static void *scratch;

void *__wrap_malloc(size_t bytes) {
    if (!armed) return __real_malloc(bytes);
    assert(requests++ == 0 && !scratch);
    requested = bytes;
    if (refuse) return NULL;
    scratch = __real_malloc(bytes);
    assert(scratch);
    return scratch;
}
void __wrap_free(void *value) {
    if (armed && value) { assert(value == scratch); scratch = NULL; }
    __real_free(value);
}
void *__wrap_memmove(void *to, const void *from, size_t bytes) {
    if (armed) { moves++; moved += bytes; }
    return __real_memmove(to, from, bytes);
}
static void begin(int fail) {
    assert(!armed && !scratch);
    requests = requested = moves = moved = 0;
    armed = 1;
    refuse = fail;
}

static int less(const unsigned char *a, const unsigned char *b, size_t width, unsigned order) {
    if (order == 3) {
        myl_native_text *x, *y; memcpy(&x, a, 8); memcpy(&y, b, 8);
        return myl_native_text_compare(x, y) < 0;
    }
    if (order == 2) {
        double x, y; memcpy(&x, a, 8); memcpy(&y, b, 8);
        if (isnan(x)) return 0;
        if (isnan(y)) return 1;
        return x < y;
    }
    if (order == 1) {
        uint64_t x, y;
        if (width == 1) { x = *a; y = *b; }
        else if (width == 2) { uint16_t p, q; memcpy(&p, a, 2); memcpy(&q, b, 2); x = p; y = q; }
        else if (width == 4) { uint32_t p, q; memcpy(&p, a, 4); memcpy(&q, b, 4); x = p; y = q; }
        else { memcpy(&x, a, 8); memcpy(&y, b, 8); }
        return x < y;
    }
    int64_t x, y;
    if (width == 1) { int8_t p, q; memcpy(&p, a, 1); memcpy(&q, b, 1); x = p; y = q; }
    else if (width == 2) { int16_t p, q; memcpy(&p, a, 2); memcpy(&q, b, 2); x = p; y = q; }
    else if (width == 4) { int32_t p, q; memcpy(&p, a, 4); memcpy(&q, b, 4); x = p; y = q; }
    else { memcpy(&x, a, 8); memcpy(&y, b, 8); }
    return x < y;
}
static void put(unsigned char *data, size_t at, size_t width, unsigned order, int64_t value) {
    if (order == 2) { double real = (double)value / 2; memcpy(data + at * width, &real, 8); }
    else if (order == 0) {
        if (width == 1) { int8_t x = (int8_t)value; memcpy(data + at, &x, 1); }
        else if (width == 2) { int16_t x = (int16_t)value; memcpy(data + at * width, &x, 2); }
        else if (width == 4) { int32_t x = (int32_t)value; memcpy(data + at * width, &x, 4); }
        else memcpy(data + at * width, &value, 8);
    } else {
        if (width == 1) { uint8_t x = (uint8_t)value; memcpy(data + at, &x, 1); }
        else if (width == 2) { uint16_t x = (uint16_t)value; memcpy(data + at * width, &x, 2); }
        else if (width == 4) { uint32_t x = (uint32_t)value; memcpy(data + at * width, &x, 4); }
        else { uint64_t x = (uint64_t)value; memcpy(data + at * width, &x, 8); }
    }
}
static void check(const unsigned char *input, size_t count, size_t width, unsigned order, int expected_moves, size_t expected_bytes, int fail) {
    size_t bytes = count * width;
    unsigned char *data = malloc(bytes), *expected = malloc(bytes);
    assert(data && expected);
    memcpy(data, input, bytes);
    memcpy(expected, input, bytes);
    unsigned char held[8];
    for (size_t i = 1; i < count; i++) {
        memcpy(held, expected + i * width, width);
        size_t j = i;
        while (j && less(held, expected + (j - 1) * width, width, order)) {
            memcpy(expected + j * width, expected + (j - 1) * width, width);
            j--;
        }
        memcpy(expected + j * width, held, width);
    }
    const myl_native_type type = { .size = width, .alignment = 1, .kind = order == 2 ? MYL_NATIVE_FLOAT : order == 3 ? MYL_NATIVE_POINTER : MYL_NATIVE_PLAIN };
    myl_native_list list = { .length = count, .capacity = count + 7, .generation = 93, .element = &type, .storage = data };
    begin(fail);
    int result = myl_native_list_sort(&list, order);
    armed = 0;
    assert(!scratch && requests == 1 && requested == count / 2 * width);
    assert(list.length == count && list.capacity == count + 7 && list.generation == 93 && list.element == &type && list.storage == data);
    if (fail) {
        assert(!result && !moves && !memcmp(data, input, bytes));
        failures++;
    } else {
        assert(result && !memcmp(data, expected, bytes));
        if (expected_moves >= 0) assert(moves == (size_t)expected_moves && moved == expected_bytes);
        cases++;
    }
    free(expected); free(data);
}
enum { SEPARATED, EQUAL_BOUNDARY, INTERLEAVED, ASCENDING, DESCENDING, RANDOM };
static void shape(size_t count, size_t left, size_t width, unsigned order, unsigned pattern, int fail) {
    unsigned char *input = malloc(count * width);
    assert(input);
    uint64_t state = 123457;
    for (size_t i = 0; i < count; i++) {
        int64_t value;
        if (pattern == SEPARATED) value = (int64_t)(i < left ? count - left + i : i - left);
        else if (pattern == EQUAL_BOUNDARY) value = i < left ? (int64_t)(left / 2 + i / 2) : (int64_t)(1 + (i - left) / 2);
        else if (pattern == INTERLEAVED) value = (int64_t)(i < left ? 2 * i + 1 : 2 * (i - left));
        else if (pattern == ASCENDING) value = (int64_t)i;
        else if (pattern == DESCENDING) value = (int64_t)(count - i);
        else { state ^= state << 13; state ^= state >> 7; state ^= state << 17; value = (int64_t)(state % 31); }
        put(input, i, width, order, value);
    }
    int rotations = pattern == SEPARATED ? 1 : pattern == RANDOM ? -1 : 0;
    size_t bytes = pattern == SEPARATED ? (left > count - left ? left : count - left) * width : 0;
    check(input, count, width, order, rotations, bytes, fail);
    free(input);
}
static void integers_and_runs(void) {
    for (unsigned order = 0; order < 2; order++)
        for (size_t width = 1; width <= 8; width *= 2)
            for (unsigned pattern = SEPARATED; pattern <= RANDOM; pattern++) shape(64, 32, width, order, pattern, 0);
    for (size_t width = 2; width <= 8; width *= 2) {
        shape(96, 32, width, 0, SEPARATED, 0);
        shape(96, 64, width, 0, SEPARATED, 0);
        shape(65, 32, width, 1, SEPARATED, 0);
        shape(127, 63, width, 1, SEPARATED, 0);
    }
    shape(257, 32, 8, 0, SEPARATED, 0);
    shape(257, 225, 8, 0, SEPARATED, 0);
    shape(4099, 2050, 8, 0, RANDOM, 0);
    for (unsigned pattern = SEPARATED; pattern <= RANDOM; pattern++) shape(64, 32, 8, 0, pattern, 1);
}
static void floating_and_ties(void) {
    for (unsigned pattern = SEPARATED; pattern <= RANDOM; pattern++) shape(64, 32, 8, 2, pattern, 0);
    shape(96, 32, 8, 2, SEPARATED, 0);
    shape(96, 64, 8, 2, SEPARATED, 0);
    double input[64];
    /* Finite right values precede an all-NaN left run; each distinct NaN
       payload must retain its original position within the stable tie. */
    for (size_t i = 0; i < 32; i++) {
        uint64_t bits = UINT64_C(0x7ff8000000000000) + i + 1;
        memcpy(input + i, &bits, 8); input[32 + i] = (double)i;
    }
    check((unsigned char *)input, 64, 8, 2, 1, 32 * 8, 0);
    check((unsigned char *)input, 64, 8, 2, 0, 0, 1);
    /* Both runs contain distinct NaNs. Overlap trimming leaves the right
       NaNs untouched; the strict finite remainder rotates while original
       left NaNs still precede those later right ties. */
    for (size_t i = 0; i < 64; i++) {
        uint64_t bits = UINT64_C(0x7ff8000000000000) + i + 1;
        if (i % 32 >= 24) memcpy(input + i, &bits, 8);
        else input[i] = i < 32 ? 32.0 + (double)i : (double)(i - 32);
    }
    check((unsigned char *)input, 64, 8, 2, 1, 32 * 8, 0);
    for (size_t i = 0; i < 64; i++) {
        uint64_t bits = UINT64_C(0x7ff8000000000000) + i + 1;
        memcpy(input + i, &bits, 8);
    }
    check((unsigned char *)input, 64, 8, 2, 0, 0, 0);
    /* Equal zero boundaries never rotate: distinguish zero signs bytewise. */
    for (size_t i = 0; i < 32; i++) {
        input[i] = i < 8 ? (i % 2 ? -0.0 : 0.0) : (double)(i - 7);
        input[32 + i] = i < 24 ? (double)i - 24.0 : (i % 2 ? 0.0 : -0.0);
    }
    check((unsigned char *)input, 64, 8, 2, 0, 0, 0);
    for (size_t i = 0; i < 32; i++) { input[i] = INFINITY; input[32 + i] = -INFINITY; }
    check((unsigned char *)input, 64, 8, 2, 1, 32 * 8, 0);
}
static void text_identity_ties(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 64u << 20);
    const myl_native_type pointer = { .size = 8, .alignment = 8, .kind = MYL_NATIVE_POINTER };
    myl_native_list *held = myl_native_list_new(&heap, &pointer, 128);
    assert(held);
    myl_native_root root;
    myl_native_root_push(&heap, &root, &held, &pointer);
    myl_native_text *input[64];
    for (unsigned pattern = 0; pattern < 2; pattern++) {
        for (size_t i = 0; i < 64; i++) {
            size_t rank = pattern == 0 ? (i < 32 ? 32 + i : i - 32) : (i < 32 ? 16 + i / 2 : 1 + (i - 32) / 2);
            unsigned char word = (unsigned char)(33 + rank);
            input[i] = myl_native_text_from_utf8(&heap, &word, 1);
            assert(input[i] && myl_native_list_append(&heap, held, input + i));
        }
        check((unsigned char *)input, 64, 8, 3, pattern == 0 ? 1 : 0, pattern == 0 ? 32 * 8 : 0, 0);
    }
    myl_native_root_pop(&heap, &root);
    myl_native_heap_destroy(&heap);
}
int main(void) {
    integers_and_runs(); floating_and_ties(); text_identity_ties();
    printf("native sort rotation: %zu stable run cases, %zu unchanged scratch refusals passed\n", cases, failures);
    return 0;
}
