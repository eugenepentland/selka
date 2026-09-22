/* Byte-string bridges that turn runtime conversion status into guest traps and
   checked-result payloads. The messages match the VM's byte diagnostics. */
#include "qbe_bytes.h"
static const char utf8_message[] = "invalid UTF-8 in byte string";
static const char hex_message[] = "hexadecimal text requires an even number of hex digits";
static myl_native_text *message(void *context, int hexadecimal) {
    const char *text = hexadecimal ? hex_message : utf8_message;
    size_t length = hexadecimal ? sizeof hex_message - 1 : sizeof utf8_message - 1;
    myl_native_text *result = myl_native_text_from_utf8(myl_qbe_heap(context), (const unsigned char *)text, length);
    if (!result) myl_qbe_fail_allocation(context);
    return result;
}
/* Publish a checked payload: 0 stores a success value, 1 an error message. */
static int settle(void *context, void *value, int status, int hexadecimal, void **output) {
    if (status == MYL_BYTES_OK) { *output = value; return 0; }
    if (status != MYL_BYTES_INVALID) { myl_qbe_fail_allocation(context); return -1; }
    *output = message(context, hexadecimal);
    return myl_qbe_failed(context) ? -1 : 1;
}
int myl_qbe_bytes_decode(void *context, myl_native_bytes *input, void **output) {
    int status = MYL_BYTES_OK;
    myl_native_text *text = myl_native_bytes_decode(myl_qbe_heap(context), input, &status);
    return settle(context, text, status, 0, output);
}
int myl_qbe_bytes_decode_range(void *context, myl_native_bytes *input, int64_t start, int64_t end, void **output) {
    int status = MYL_BYTES_OK;
    myl_native_text *text = myl_native_bytes_decode_range(myl_qbe_heap(context), input, start, end, &status);
    return settle(context, text, status, 0, output);
}
int myl_qbe_bytes_from_hex(void *context, myl_native_text *input, void **output) {
    int status = MYL_BYTES_OK;
    myl_native_bytes *value = myl_native_bytes_from_hex(myl_qbe_heap(context), input, &status);
    return settle(context, value, status, 1, output);
}
myl_native_bytes *myl_qbe_bytes_from_list(void *context, myl_native_list *list) {
    int status = MYL_BYTES_OK;
    myl_native_bytes *result = myl_native_bytes_from_list(myl_qbe_heap(context), list, &status);
    if (status == MYL_BYTES_RANGE) myl_qbe_fail(context, "R_BYTE_RANGE");
    else if (!result) myl_qbe_fail_allocation(context);
    return result;
}
myl_native_bytes *myl_qbe_bytes_copy(void *context, myl_native_bytes *input) {
    myl_native_bytes *result = myl_native_bytes_copy(myl_qbe_heap(context), input);
    if (!result) myl_qbe_fail_allocation(context);
    return result;
}
myl_native_bytes *myl_qbe_bytes_snapshot(void *context, myl_native_bytes *input) {
    myl_native_bytes *result = myl_native_bytes_buffer_snapshot(myl_qbe_heap(context), input);
    if (!result) myl_qbe_fail_allocation(context);
    return result;
}
/* Publish the validating scalar count as a checked result: 0 stores the count as
   the success payload, 1 stores the decoder's invalid-UTF-8 message, and -1 is a
   sticky trap the caller detects with myl_qbe_failed. */
int myl_qbe_bytes_scalar_count(void *context, myl_native_bytes *input, void **output) {
    int status = MYL_BYTES_OK;
    int64_t count = myl_native_bytes_scalar_count(input, &status);
    return settle(context, (void *)(intptr_t)count, status, 0, output);
}
int myl_qbe_bytes_scalar_count_range(void *context, myl_native_bytes *input, int64_t start, int64_t end, void **output) {
    int status = MYL_BYTES_OK;
    int64_t count = myl_native_bytes_scalar_count_range(input, start, end, &status);
    return settle(context, (void *)(intptr_t)count, status, 0, output);
}
