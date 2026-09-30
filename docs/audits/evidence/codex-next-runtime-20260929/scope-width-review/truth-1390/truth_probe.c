/* Ordinary regression: actual generated pin-entry conditional, no dereference. */
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
extern int review_pin_entry_truth(uint64_t);
int main(void) {
    const uint64_t values[]={0,1,UINT64_C(1)<<32,UINT64_C(1)<<48};
    unsigned failures=0;
    for (unsigned i=0;i<4;i++) {
        const int got=review_pin_entry_truth(values[i]);
        const int expected=values[i]!=0;
        printf("%s input=%"PRIu64" emitted_truth=%d expected=%d\n",got==expected?"PASS":"FAIL",values[i],got,expected);
        failures+=(got!=expected);
    }
    printf("Actual emitted pin-entry truth: %u passed, %u failed\n",4-failures,failures);
    return failures?1:0;
}
