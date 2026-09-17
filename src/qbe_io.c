/* Standard output for the native backend. The VM renders a whole `print` line
   through one writer and flushes it; this runtime buffers the same bytes and
   writes them once, so both backends interleave output identically. An f-string
   hole over an aggregate fills the same buffer and keeps the bytes instead of
   writing them, so a value has one spelling printed or interpolated. */
#include "qbe_io.h"
#include <stdio.h>
#include <stdlib.h>
static void *print_begin(void *context) {
    MylPrint *out = calloc(1, sizeof *out);
    if (!out) myl_qbe_fail_allocation(context);
    return out;
}
void *myl_qbe_print_begin(void *context) { return print_begin(context); }
void *myl_qbe_eprint_begin(void *context) { return print_begin(context); }
void myl_qbe_print_raw(void *sink, myl_native_text *text) { myl_print_text(sink, &text, 0); }
void myl_qbe_print_byte(void *sink, unsigned value) {
    unsigned char octet = (unsigned char)value;
    myl_print_raw(sink, &octet, 1);
}
static void print_finish(void *context, void *sink, FILE *stream) {
    MylPrint *out = sink;
    if (!out) return;
    /* A float the VM cannot fit in its formatting frame is a host fault on both
       backends rather than a guest-visible trap. */
    if (out->unprintable) myl_qbe_fail(context, "InternalError");
    else if (out->failed) myl_qbe_fail_allocation(context);
    else if (out->length && fwrite(out->bytes, 1, out->length, stream) != out->length) myl_qbe_fail(context, "R_OUTPUT");
    else if (fflush(stream)) myl_qbe_fail(context, "R_OUTPUT");
    free(out->bytes);
    free(out);
}
void myl_qbe_print_finish(void *context, void *sink) { print_finish(context, sink, stdout); }
void myl_qbe_eprint_finish(void *context, void *sink) { print_finish(context, sink, stderr); }
static FILE *stream_file(uint64_t stream) { return stream == MYL_QBE_STREAM_STDERR ? stderr : stdout; }
void *myl_qbe_stream_begin(void *context, uint64_t stream) {
    (void)stream;
    return print_begin(context);
}
void myl_qbe_stream_finish(void *context, void *sink, uint64_t stream) { print_finish(context, sink, stream_file(stream)); }
uint64_t myl_qbe_stream_write(void *context, uint64_t stream, myl_native_text *text) {
    MylPrint out = {0};
    if (!text) return 0;
    myl_print_text(&out, &text, 0);
    if (out.unprintable) { free(out.bytes); myl_qbe_fail(context, "InternalError"); return 0; }
    if (out.failed) { free(out.bytes); myl_qbe_fail_allocation(context); return 0; }
    FILE *file = stream_file(stream);
    if (out.length && fwrite(out.bytes, 1, out.length, file) != out.length) { free(out.bytes); myl_qbe_fail(context, "R_OUTPUT"); return 0; }
    if (fflush(file)) { free(out.bytes); myl_qbe_fail(context, "R_OUTPUT"); return 0; }
    free(out.bytes);
    return (uint64_t)text->length;
}
myl_native_text *myl_qbe_text_render(void *context, void *sink) {
    MylPrint *out = sink;
    myl_native_text *text = NULL;
    if (!out) return NULL;
    if (out->unprintable) myl_qbe_fail(context, "InternalError");
    else if (out->failed) myl_qbe_fail_allocation(context);
    else if (!(text = myl_native_text_from_utf8(myl_qbe_heap(context), out->bytes, out->length))) myl_qbe_fail_allocation(context);
    free(out->bytes);
    free(out);
    return text;
}
