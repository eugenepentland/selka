#ifndef MYLANG_NATIVE_RC_DICTIONARY_H
#define MYLANG_NATIVE_RC_DICTIONARY_H
#include "native_dictionary.h"
#include "native_rc_values.h"
/* Borrowed inputs are published as owned logical edges. Reads remain borrowed;
 * pop/pop_last/setdefault initialize an owned success result. A negative pop
 * status reports publication refusal without removing the entry. */
int myl_rc_dictionary_overwrite(myl_native_heap *, myl_native_dictionary *, const void *, const void *);
int myl_rc_dictionary_pop(myl_native_heap *, myl_native_dictionary *, const void *, void *);
int myl_rc_dictionary_pop_last(myl_native_heap *, myl_native_dictionary *, void *);
void myl_rc_dictionary_clear(myl_native_heap *, myl_native_dictionary *);
#endif
