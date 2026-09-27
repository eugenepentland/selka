#include "native_rc_internal.h"
#include <stdio.h>
int main(void) {
    printf("{\"flat\":%zu,\"binding\":%zu,\"count\":%zu,\"loanable\":%zu,\"state\":%zu,\"heap\":%zu}\n",
        sizeof(myl_rc_flat),sizeof(myl_rc_binding),offsetof(myl_rc_flat,count),offsetof(myl_rc_flat,loanable),
        sizeof(struct myl_rc_state),sizeof(myl_native_heap));
}
