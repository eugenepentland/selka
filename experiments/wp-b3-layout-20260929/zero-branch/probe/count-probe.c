#include "native_rc.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
extern int owner(void *, void *, void **);
extern int hold(void *, void *, void **);
int myl_qbe_rc_status(void *context, unsigned status) {
    assert(status == 2);
    *(unsigned *)context = status;
    return 0;
}
int main(void) {
    _Alignas(16) struct { myl_rc_object header; uintptr_t payload; } value;
    static const uint64_t counts[] = {1, UINT32_MAX, UINT64_C(1)<<32, UINT64_MAX-1, UINT64_MAX};
    size_t passed=0;
    for (unsigned kind=0; kind<2; ++kind) for (size_t i=0;i<sizeof(counts)/sizeof(counts[0]);++i) {
        memset(&value,0,sizeof(value));
        value.header.owners=counts[i]; value.header.holds=counts[i];
        value.header.common.mark=4; value.payload=123;
        unsigned status=0;
        void *output=(void *)(uintptr_t)7;
        int result=(kind ? hold : owner)(&status,&value.payload,&output);
        uint64_t expected=counts[i]==UINT64_MAX ? counts[i] : counts[i]+1;
        assert(value.header.owners==(kind ? counts[i] : expected));
        assert(value.header.holds==(kind ? expected : counts[i]));
        assert(value.header.common.mark==4 && value.payload==123);
        assert(result==(counts[i]!=UINT64_MAX));
        assert(status==(counts[i]==UINT64_MAX ? 2u : 0u));
        assert(output==(counts[i]==UINT64_MAX ? (void *)(uintptr_t)7 : &value.payload));
        ++passed;
    }
    printf("actual emitted carry admission: %zu O/H width/MAX cases passed\n",passed);
}
