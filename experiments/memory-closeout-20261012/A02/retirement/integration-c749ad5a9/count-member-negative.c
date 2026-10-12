#include "core_rt.c"
int retired_count_member(void) { return offsetof(myl_block, count); }
