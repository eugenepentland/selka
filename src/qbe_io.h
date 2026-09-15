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
#endif
