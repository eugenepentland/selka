#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#define DECLARE(name) extern int name(uint64_t, uint64_t *)
DECLARE(branch_add); DECLARE(branch_sub); DECLARE(branch_ne); DECLARE(branch_reverse);
DECLARE(branch_word); DECLARE(branch_width); DECLARE(branch_nonzero);
DECLARE(branch_clobber); DECLARE(branch_other); DECLARE(branch_call);
DECLARE(branch_multi); DECLARE(branch_wrongresult);
extern uint64_t branch_spill(uint64_t, uint64_t *);
static volatile unsigned touched;
int touch(void) { return ++touched; }
void record_yes(uint64_t *out) { out[24]=1; }
void record_no(uint64_t *out) { out[24]=0; }
int main(void) {
    const uint64_t values[] = {0, 1, 6, 7, UINT32_MAX, UINT64_C(1)<<32,
        (UINT64_C(1)<<32)-2, UINT64_C(1)<<48, UINT64_MAX-1, UINT64_MAX};
    unsigned cases=0;
    for (size_t i=0;i<sizeof(values)/sizeof(values[0]);++i) {
        uint64_t x=values[i], scratch[25], sum=0;
        for (size_t n=0;n<24;++n) { scratch[n]=n+1; sum+=scratch[n]; }
        int zero=x+1==0;
        assert(branch_add(x,scratch)==zero); ++cases;
        assert(branch_sub(x,scratch)==(x-1==0)); ++cases;
        assert(branch_ne(x,scratch)==!zero); ++cases;
        assert(branch_reverse(x,scratch)==zero); ++cases;
        assert(branch_word(x,scratch)==((uint32_t)x+UINT32_C(1)==0)); ++cases;
        assert(branch_width(x,scratch)==((uint32_t)(x+1)==0)); ++cases;
        assert(branch_nonzero(x,scratch)==(x+1==7)); ++cases;
        assert(branch_clobber(x,scratch)==zero); ++cases;
        assert(branch_other(x,scratch)==zero); ++cases;
        assert(branch_call(x,scratch)==zero); ++cases;
        assert(branch_multi(x,scratch)==zero && scratch[0]==(uint64_t)zero); ++cases;
        assert(branch_wrongresult(x,scratch)==(x==0) && scratch[0]==x-1); ++cases;
        for (size_t n=0;n<24;++n) scratch[n]=n+1;
        assert(branch_spill(x,scratch)==sum && scratch[24]==(uint64_t)zero); ++cases;
    }
    assert(touched==sizeof(values)/sizeof(values[0]));
    printf("zero branch probes: %u cases passed\n",cases);
}
