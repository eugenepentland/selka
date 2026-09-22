#ifndef MYLANG_QBE_BYTES_H
#define MYLANG_QBE_BYTES_H
#include "native_bytes.h"
#include "qbe_runtime.h"
/* Checked byte conversions: 0 publishes a success payload, 1 an error message
   and -1 a sticky trap the caller detects with myl_qbe_failed. */
int myl_qbe_bytes_decode(void *context, myl_native_bytes *input, void **output);
/* The fused `s[a:b].decode()` form: validate and widen one clamped range
   without building the intermediate byte string. */
int myl_qbe_bytes_decode_range(void *context, myl_native_bytes *input, int64_t start, int64_t end, void **output);
int myl_qbe_bytes_from_hex(void *context, myl_native_text *input, void **output);
/* NULL after an R_BYTE_RANGE trap or an exhausted allocation budget. */
myl_native_bytes *myl_qbe_bytes_from_list(void *context, myl_native_list *list);
/* A fresh immutable copy of a byte-kind buffer's current octets; NULL after an
   exhausted allocation budget. */
myl_native_bytes *myl_qbe_bytes_copy(void *context, myl_native_bytes *input);
/* The buffer's current octets as an immutable snapshot that reads them where they
   are, retaining their block and leaving the buffer to detach on its next write;
   NULL after an exhausted allocation budget. */
myl_native_bytes *myl_qbe_bytes_snapshot(void *context, myl_native_bytes *input);
/* The validating scalar count as a checked result: 0 publishes the count, 1 the
   invalid-UTF-8 message, -1 a sticky trap. */
int myl_qbe_bytes_scalar_count(void *context, myl_native_bytes *input, void **output);
int myl_qbe_bytes_scalar_count_range(void *context, myl_native_bytes *input, int64_t start, int64_t end, void **output);
#endif
