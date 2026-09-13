#ifndef MYLANG_QBE_BYTES_H
#define MYLANG_QBE_BYTES_H
#include "native_bytes.h"
#include "qbe_runtime.h"
/* Checked byte conversions: 0 publishes a success payload, 1 an error message
   and -1 a sticky trap the caller detects with myl_qbe_failed. */
int myl_qbe_bytes_decode(void *context, myl_native_bytes *input, void **output);
int myl_qbe_bytes_from_hex(void *context, myl_native_text *input, void **output);
/* NULL after an R_BYTE_RANGE trap or an exhausted allocation budget. */
myl_native_bytes *myl_qbe_bytes_from_list(void *context, myl_native_list *list);
#endif
