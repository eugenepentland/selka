#ifndef MYLANG_NATIVE_PYTHON_H
#define MYLANG_NATIVE_PYTHON_H
#include "native_bytes.h"
/* Append-only search modes, shared with buffer_operations.Search. */
enum { MYL_SEARCH_FIND, MYL_SEARCH_RFIND, MYL_SEARCH_INDEX, MYL_SEARCH_RINDEX,
       MYL_SEARCH_COUNT, MYL_SEARCH_PREFIX, MYL_SEARCH_SUFFIX };
/* Allocation-free Python bounds; text endpoints/answers count scalars. */
int64_t myl_native_text_search_range(const myl_native_text *, const myl_native_text *, int64_t, int64_t, int);
int64_t myl_native_bytes_search_range(const myl_native_bytes *, const myl_native_bytes *, int64_t, int64_t, int);
/* Null charset selects Unicode16 whitespace for text, ASCII whitespace for bytes. */
myl_native_text *myl_native_text_trim_chars(myl_native_heap *, myl_native_text *, const myl_native_text *, int);
myl_native_bytes *myl_native_bytes_trim_chars(myl_native_heap *, myl_native_bytes *, const myl_native_bytes *, int);
/* Exact scalar repr, separate from ordinary printing and str conversion. */
myl_native_text *myl_native_text_repr(myl_native_heap *, myl_native_text *);
myl_native_text *myl_native_bytes_repr(myl_native_heap *, myl_native_bytes *);
#ifdef MYL_SEARCH_STEPS
extern size_t myl_native_search_steps;
#endif
#ifdef MYL_PYTHON_STEPS
/* Test-only scan counters; production builds carry no instrumentation. */
extern size_t myl_native_trim_steps, myl_native_repr_steps;
#endif
#endif
