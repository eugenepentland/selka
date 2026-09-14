#ifndef MYLANG_NATIVE_TEXT_METHODS_H
#define MYLANG_NATIVE_TEXT_METHODS_H
#include "native_text.h"
/* Python string methods over immutable managed text. Every one reads its
 * receiver and answers a fresh value, so no alias observes a change. Case
 * mapping and classification cover ASCII and leave every other scalar alone.
 * A method that allocates answers NULL once the allocation budget is exhausted;
 * an empty needle is the caller's trap to raise, never this runtime's. */
/* Which ends `strip`, `lstrip` and `rstrip` trim. */
enum { MYL_TEXT_BOTH = 0, MYL_TEXT_LEADING = 1, MYL_TEXT_TRAILING = 2 };
/* Which scalar property `isdigit`, `isalpha` and `isspace` test. */
enum { MYL_TEXT_DIGIT = 0, MYL_TEXT_ALPHA = 1, MYL_TEXT_SPACE = 2 };
myl_native_text *myl_native_text_trim(myl_native_heap *, myl_native_text *, int ends);
myl_native_text *myl_native_text_case(myl_native_heap *, myl_native_text *, int upper);
/* Splits on \n, \r and \r\n without keeping the terminators; empty text has no lines. */
myl_native_list *myl_native_text_lines(myl_native_heap *, myl_native_text *);
/* Replaces every non-overlapping occurrence of a nonempty needle. */
myl_native_text *myl_native_text_replace(myl_native_heap *, myl_native_text *, myl_native_text *needle, myl_native_text *insert);
/* Left-pads with `0` to a scalar width, keeping any leading sign in front. */
myl_native_text *myl_native_text_zfill(myl_native_heap *, myl_native_text *, int64_t width);
/* First scalar index of a nonempty needle, or -1 when it is absent. */
int64_t myl_native_text_find(const myl_native_text *, const myl_native_text *needle);
int64_t myl_native_text_count(const myl_native_text *, const myl_native_text *needle);
/* Whether the text begins (leading) or ends with an affix; an empty affix matches. */
int myl_native_text_edge(const myl_native_text *, const myl_native_text *affix, int leading);
/* Whether every scalar has one property; empty text answers false, as in Python. */
int myl_native_text_every(const myl_native_text *, int property);
/* Scalar storage of one text value, which the shared number grammar reads. */
const uint32_t *myl_native_text_points(const myl_native_text *);
#endif
