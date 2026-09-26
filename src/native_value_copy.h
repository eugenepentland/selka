#ifndef MYLANG_NATIVE_VALUE_COPY_H
#define MYLANG_NATIVE_VALUE_COPY_H
#include "native_heap.h"
/* VALUE-SEMANTICS-2: make the value at `value` an independent copy in
 * `output`, duplicating every list, dictionary, set and byte string it
 * reaches; with `children` nonzero the outer collection is already fresh and
 * only its elements are copied. Returns 1, or 0 after an exhausted allocation
 * budget has set the trap. The one runtime entry value semantics calls; stage
 * 3b of D9 replaces it with copy-on-write. */
int myl_qbe_value_copy(void *context, const myl_native_type *type, const void *value, void *output, uint32_t children);
#endif
