#ifndef MYLANG_NATIVE_PRINT_H
#define MYLANG_NATIVE_PRINT_H
#include "native_dictionary.h"
/* Python-style rendering of native values for `print`. One growable line buffer
   collects a whole call, so a refused write never leaves half a line behind. */
typedef struct { unsigned char *bytes; size_t length, capacity; int failed, unprintable; } MylPrint;
typedef void (*MylPrintFn)(MylPrint *, const void *, unsigned depth);
/* One record field or variant case: its byte offset, renderer (NULL for a case
   without a payload), declared spelling and, for a case, its tag. */
typedef struct { size_t offset; MylPrintFn render; const char *name; uint32_t tag; } MylPrintField;
/* Nesting beyond this depth renders as `...`, so a cyclic graph terminates. */
#define MYL_PRINT_MAX_DEPTH 24u
/* Nonzero once the depth cap has written its ellipsis for this value. */
int myl_print_deep(MylPrint *out, unsigned depth);
void myl_print_raw(MylPrint *out, const void *bytes, size_t length);
void myl_print_integer(MylPrint *out, const void *value, unsigned depth, unsigned width, int is_signed);
void myl_print_bool(MylPrint *out, const void *value, unsigned depth);
/* Authority, callback and resource values have no Python spelling; reaching one
   reports the whole line as unprintable rather than inventing a rendering. */
void myl_print_unprintable(MylPrint *out, const void *value, unsigned depth);
void myl_print_unit(MylPrint *out, const void *value, unsigned depth);
void myl_print_float(MylPrint *out, const void *value, unsigned depth);
/* Text prints raw at the top level and repr-quoted inside a container. */
void myl_print_text(MylPrint *out, const void *value, unsigned depth);
void myl_print_bytes(MylPrint *out, const void *value, unsigned depth);
void myl_print_list(MylPrint *out, const void *value, unsigned depth, MylPrintFn element);
void myl_print_dictionary(MylPrint *out, const void *value, unsigned depth, MylPrintFn key, MylPrintFn item);
void myl_print_array(MylPrint *out, const void *value, unsigned depth, size_t count, size_t stride, MylPrintFn element);
void myl_print_record(MylPrint *out, const void *value, unsigned depth, const char *name, const MylPrintField *fields, size_t count);
void myl_print_domain(MylPrint *out, const void *value, unsigned depth, const char *name, MylPrintFn inner);
/* Case names already carry their printed spelling, bare for results, options
   and `None`, and `Owner.case` for an enum or ordinary union. */
void myl_print_variant(MylPrint *out, const void *value, unsigned depth, const MylPrintField *cases, size_t count);
#endif
