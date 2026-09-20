#include "native_collections.h"
#include "qbe_runtime.h"
#include <assert.h>
#include <stdint.h>
#include <string.h>

uint64_t __wrap_myl_qbe_int_cast(void *, uint64_t, uint64_t, uint64_t, uint64_t);
uint64_t __wrap_myl_qbe_int_neg(void *, uint64_t, uint64_t, uint64_t);
uint64_t __wrap_myl_qbe_int_binary(void *, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);

int __real_myl_native_list_append(myl_native_heap *heap, myl_native_list *list,
                                  const void *value) {
    return myl_native_list_append(heap, list, value);
}
uint64_t __real_myl_qbe_int_binary(void *context, uint64_t op, uint64_t is_signed,
                                   uint64_t width, uint64_t left, uint64_t right) {
    return myl_qbe_int_binary(context, op, is_signed, width, left, right);
}

static void clear_context(MylQbeContext *context) {
    memset(context, 0, sizeof(*context));
}

static int canonical(uint64_t value, uint64_t is_signed, uint64_t width) {
    if (width == 64) return 1;
    uint64_t mask = (UINT64_C(1) << width) - 1;
    if (!is_signed) return value == (value & mask);
    uint64_t sign = UINT64_C(1) << (width - 1);
    uint64_t extended = (value & sign) ? (value | ~mask) : (value & mask);
    return value == extended;
}

int main(void) {
    MylQbeContext context;
    size_t casts = 0, negations = 0, successes[65][2][26] = {{{0}}};

    for (uint64_t width = 1; width <= 64; width++) {
        uint64_t mask = width == 64 ? UINT64_MAX : (UINT64_C(1) << width) - 1;
        uint64_t sign = UINT64_C(1) << (width - 1);
        uint64_t signed_min = width == 64 ? sign : UINT64_MAX << (width - 1);
        uint64_t values[] = { 0, 1, 2, 3, mask, mask - !!mask, sign, sign - 1,
                              signed_min, UINT64_MAX, UINT64_C(1) << 63 };
        for (uint64_t is_signed = 0; is_signed <= 1; is_signed++) {
            for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
                uint64_t value = values[i];
                for (uint64_t to_signed = 0; to_signed <= 1; to_signed++) {
                    clear_context(&context);
                    uint64_t expected = myl_qbe_int_cast(&context, is_signed, to_signed,
                                                         width, value);
                    if (!context.trap) {
                        assert(__wrap_myl_qbe_int_cast(&context, is_signed, to_signed,
                                                       width, value) == expected);
                        casts++;
                    }
                }

                if (canonical(value, is_signed, width)) {
                    clear_context(&context);
                    uint64_t expected = myl_qbe_int_neg(&context, is_signed, width, value);
                    if (!context.trap) {
                        assert(__wrap_myl_qbe_int_neg(&context, is_signed, width, value) == expected);
                        negations++;
                    }
                }
            }

            for (uint64_t op = 0; op <= 25; op++) {
                for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); i++) {
                    for (size_t j = 0; j < sizeof(values) / sizeof(values[0]); j++) {
                        uint64_t left = values[i], right = values[j];
                        if (!canonical(left, is_signed, width) ||
                            !canonical(right, is_signed, width)) continue;
                        clear_context(&context);
                        uint64_t expected = myl_qbe_int_binary(&context, op, is_signed,
                                                               width, left, right);
                        if (context.trap) continue;
                        clear_context(&context);
                        uint64_t actual = __wrap_myl_qbe_int_binary(
                            &context, op, is_signed, width, left, right);
                        assert(!context.trap);
                        assert(actual == expected);
                        successes[width][is_signed][op]++;
                    }
                }
                assert(successes[width][is_signed][op] > 0);
            }
        }
    }
    assert(casts > 0 && negations > 0);
    return 0;
}
