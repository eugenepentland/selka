/* Standard output for the native backend. The VM renders a whole `print` line
   through one writer and flushes it; this runtime buffers the same bytes and
   writes them once, so both backends interleave output identically. */
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
