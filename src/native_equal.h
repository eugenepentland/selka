#ifndef MYLANG_NATIVE_EQUAL_H
#define MYLANG_NATIVE_EQUAL_H
#include "native_dictionary.h"
/* 1 equal/present, 0 different/absent, -1 allocation failure, -2 work limit.
 * Inputs are addresses of native values with the supplied canonical descriptor.
 * No guest allocation or safepoint occurs during comparison. */
int myl_native_equal(const myl_native_type *, const void *, const void *);
int myl_native_list_contains(const myl_native_list *, const myl_native_type *, const void *);
#endif
