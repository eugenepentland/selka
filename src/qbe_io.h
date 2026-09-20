#ifndef MYLANG_QBE_IO_H
#define MYLANG_QBE_IO_H
#include "native_print.h"
#include "qbe_runtime.h"
/* One `print` call collects its whole line before any byte reaches standard
   output, so a refused write never leaves a partial line behind. NULL after an
   exhausted allocation budget has already set the trap. */
void *myl_qbe_print_begin(void *context);
void *myl_qbe_eprint_begin(void *context);
/* `sep=` and `end=` render raw, the way top-level text does. */
void myl_qbe_print_raw(void *sink, myl_native_text *text);
void myl_qbe_print_byte(void *sink, unsigned value);
/* Publish the line, then trap R_OUTPUT when standard output refuses it. */
void myl_qbe_print_finish(void *context, void *sink);
void myl_qbe_eprint_finish(void *context, void *sink);
/* A `Stream` capability carries its destination in its own sentinel word, so
   one lowering serves `out.print`, `err.print` and a passed-in `log: Stream`. */
#define MYL_QBE_STREAM_STDOUT UINT64_C(1)
#define MYL_QBE_STREAM_STDERR UINT64_C(2)
void *myl_qbe_stream_begin(void *context, uint64_t stream);
void myl_qbe_stream_finish(void *context, void *sink, uint64_t stream);
/* `stream.write(text)` writes the encoded text immediately and answers its
   character count, or zero after an R_OUTPUT trap. */
uint64_t myl_qbe_stream_write(void *context, uint64_t stream, myl_native_text *text);
/* Raw byte output preserves every octet and returns its byte count. */
uint64_t myl_qbe_stream_write_bytes(void *context, uint64_t stream, myl_native_list *bytes);
/* An f-string hole over an aggregate renders through the same sink `print`
   fills, then copies the rendered bytes into fresh managed text and releases
   the sink. NULL once the rendering or the copy has already set the trap. */
myl_native_text *myl_qbe_text_render(void *context, void *sink);
#endif
