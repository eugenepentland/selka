#include "native_rc_internal.h"
int myl_rc_binding_has_unique(myl_native_heap *heap, const myl_rc_binding *binding) { return myl_rc_native_has_unique(heap,binding->descriptor.type); }
