#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
extern uint64_t review_phi_spill(uint64_t,uint64_t *,uint64_t *);
__attribute__((noinline)) static void prime_stack(void) {
    volatile uint64_t dust[128];
    for(unsigned i=0;i<128;i++) dust[i]=UINT64_C(0x9876543212345678);
    __asm__ volatile("" : : "m"(dust) : "memory");
}
int main(void) {
    uint64_t values[14],total=0;
    for(unsigned i=0;i<14;i++) total+=(values[i]=i+1);
    unsigned failed=0;
    for(unsigned x=0;x<2;x++) {
        uint64_t out=0; prime_stack();
        uint64_t got=review_phi_spill(x,values,&out),want=total+x;
        printf("%s x=%u got=%"PRIu64" expected=%"PRIu64" branch=%u\n",got==want?"PASS":"FAIL",x,got,want,(unsigned)out);
        failed+=(got!=want);
        if(out!=(x?17:23)) return 2;
    }
    printf("Well-typed long phi spill: %u passed, %u failed\n",2-failed,failed);
    return failed?1:0;
}
