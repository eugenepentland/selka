/* Opt-in valid-input upper-bound shims for the frozen LLVM benchmark.
 *
 * Link with the --wrap options documented in README.md.  These are deliberately
 * not production runtime replacements: the benchmark oracle establishes that
 * every indexed access is in range and that list generation cannot overflow.
 */
#include "native_collections.h"
#include "native_text.h"
#include <string.h>

static inline void copy_element(void *destination, const void *source, size_t size) {
    memcpy(destination, source, size);
}

/* The guest IR has already normalized and checked this index. */
int __wrap_myl_native_list_get(const myl_native_list *list, size_t index, void *output) {
    copy_element(output,
        (const unsigned char *)list->storage + index * list->element->size,
        list->element->size);
    return 1;
}

/* Avoid the impossible generation-overflow branch on the common reserved-space
 * path. Growth remains delegated to the real runtime, preserving allocation,
 * rooting, arena ownership and failure behavior. */
int __real_myl_native_list_append(myl_native_heap *, myl_native_list *, const void *);
int __wrap_myl_native_list_append(myl_native_heap *heap, myl_native_list *list, const void *value) {
    if (list->length < list->capacity) {
        copy_element((unsigned char *)list->storage + list->length * list->element->size,
            value, list->element->size);
        list->length++;
        list->generation++;
        return 1;
    }
    return __real_myl_native_list_append(heap, list, value);
}

/* Valid-input text indexing. Negative indices are normalized exactly as the
 * production helper does; the caller proves the normalized position exists. */
static myl_native_text *unchecked_ascii_scalar(myl_native_heap *heap, uint32_t point) {
    if (!heap->text_scalars_ready) {
        heap->text_scalars_ready = 1;
        unsigned depth = heap->region_depth;
        heap->region_depth = 0;
        for (unsigned code = 0; code < 128; code++) {
            myl_native_text *text = myl_native_text_new(heap, 1);
            if (!text) { heap->region_depth = depth; return NULL; }
            ((uint32_t *)text->storage)[0] = code;
            text->length = 1;
            heap->text_scalars[code] = text;
        }
        heap->region_depth = depth;
    }
    return heap->text_scalars[point];
}

myl_native_text *__wrap_myl_native_text_at(myl_native_heap *heap, myl_native_text *input, int64_t index) {
    size_t at = index < 0 ? input->length - (size_t)(-(index + 1)) - 1 : (size_t)index;
    uint32_t point = ((const uint32_t *)input->storage)[at];
    if (point < 128) {
        myl_native_text *scalar = unchecked_ascii_scalar(heap, point);
        if (scalar) return scalar;
    }
    return myl_native_text_copy(heap, input, at, 1);
}

static size_t unchecked_endpoint(size_t length, int64_t index) {
    return index < 0 ? length - (size_t)(-(index + 1)) - 1 : (size_t)index;
}

myl_native_text *__wrap_myl_native_text_slice(myl_native_heap *heap, myl_native_text *input,
                                               int64_t start, int64_t end) {
    size_t first = unchecked_endpoint(input->length, start);
    size_t last = unchecked_endpoint(input->length, end);
    return myl_native_text_copy(heap, input, first, last > first ? last - first : 0);
}

/* The frozen guest uses width 1..64 and reaches these wrappers only after its
 * own checked branches have established representability/nonzero divisors and
 * valid shift counts. Arithmetic uses unsigned bits to avoid C signed-overflow
 * undefined behavior. */
static uint64_t width_mask(uint64_t width) {
    return width == 64 ? UINT64_MAX : (UINT64_C(1) << width) - 1;
}
static int64_t signed_bits(uint64_t value, uint64_t width) {
    uint64_t mask = width_mask(width), sign = UINT64_C(1) << (width - 1);
    value &= mask;
    return (int64_t)((value ^ sign) - sign);
}
static uint64_t result_bits(uint64_t value, uint64_t is_signed, uint64_t width) {
    value &= width_mask(width);
    return is_signed ? (uint64_t)signed_bits(value, width) : value;
}
uint64_t __wrap_myl_qbe_int_cast(void *context, uint64_t from_signed, uint64_t to_signed, uint64_t width, uint64_t value) {
    (void)context; (void)from_signed;
    return result_bits(value, to_signed, width);
}
uint64_t __wrap_myl_qbe_int_neg(void *context, uint64_t is_signed, uint64_t width, uint64_t value) {
    (void)context;
    return result_bits(UINT64_C(0) - value, is_signed, width);
}
uint64_t __real_myl_qbe_int_binary(void *, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t __wrap_myl_qbe_int_binary(void *context, uint64_t op, uint64_t is_signed, uint64_t width, uint64_t left, uint64_t right) {
    (void)context;
    const uint64_t mask = width_mask(width), x = left & mask, y = right & mask;
    const int64_t a = is_signed ? signed_bits(left, width) : (int64_t)x;
    const int64_t b = is_signed ? signed_bits(right, width) : (int64_t)y;
    switch (op) {
    case 0: case 20: return result_bits(x + y, is_signed, width);
    case 1: case 21: return result_bits(x - y, is_signed, width);
    case 2: case 22: return result_bits(x * y, is_signed, width);
    case 3: return is_signed ? (uint64_t)(a / b) : x / y;
    case 4:
        if (is_signed && a == INT64_MIN && b == -1) return 0;
        return is_signed ? (uint64_t)(a % b) : x % y;
    case 5: {
        if (!is_signed) return x / y;
        int64_t q = a / b, r = a % b;
        if (r && ((r < 0) != (b < 0))) q--;
        return (uint64_t)q;
    }
    case 6: {
        if (!is_signed) return x % y;
        if (a == INT64_MIN && b == -1) return 0;
        int64_t r = a % b;
        if (r && ((r < 0) != (b < 0))) r += b;
        return (uint64_t)r;
    }
    case 7: return !!x && !!y;
    case 8: return !!x || !!y;
    case 9: return x == y;
    case 10: return x != y;
    case 11: return is_signed ? a < b : x < y;
    case 12: return is_signed ? a <= b : x <= y;
    case 13: return is_signed ? a > b : x > y;
    case 14: return is_signed ? a >= b : x >= y;
    case 15: return result_bits(x & y, is_signed, width);
    case 16: return result_bits(x | y, is_signed, width);
    case 17: return result_bits(x ^ y, is_signed, width);
    case 18: return result_bits(x << (unsigned)y, is_signed, width);
    case 19: return is_signed ? (uint64_t)(a >> (unsigned)y) : x >> (unsigned)y;
    case 23: case 24: case 25:
        return __real_myl_qbe_int_binary(context, op, is_signed, width, left, right);
    default: __builtin_unreachable();
    }
}
