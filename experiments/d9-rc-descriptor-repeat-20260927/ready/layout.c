#include "native_rc_internal.h"
#include <stdio.h>
int main(void) {
    printf("index=%zu kind=%zu state=%zu heap=%zu binding=%zu\n", sizeof(myl_rc_index_entry), offsetof(myl_rc_index_entry,kind), sizeof(myl_rc_state), sizeof(myl_native_heap), sizeof(myl_rc_binding));
    return 0;
}
