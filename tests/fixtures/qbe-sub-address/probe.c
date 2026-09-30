#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#define LOAD(name) extern uint64_t name(uint64_t)
LOAD(addr_load); LOAD(addr_hold); LOAD(addr_mark); LOAD(addr_min); LOAD(addr_max);
LOAD(addr_outside); LOAD(addr_composed_outside); LOAD(addr_composed_cancel);
LOAD(addr_negative); LOAD(addr_swapped); LOAD(addr_large); LOAD(addr_negative_min);
LOAD(addr_loaded_flags);
extern int addr_store(uint64_t, uint64_t);
extern uint64_t addr_scaled(uint64_t, uint64_t);
extern uint64_t addr_scaled_sub(uint64_t, uint64_t);
extern uint64_t addr_scaled_outside(uint64_t, uint64_t);
extern uint64_t addr_dynamic(uint64_t, uint64_t);
extern uint64_t addr_multi(uint64_t, uint64_t *);
extern uint32_t addr_word(uint32_t);
extern double addr_float(double);
extern int addr_flags(uint64_t, uint64_t *);

int main(void) {
    uint64_t words[64], out;
    unsigned cases = 0;
    const uint64_t flags[] = {0, 1, 31, 32, 33, UINT64_C(1)<<32,
        UINT64_C(1)<<48, UINT64_MAX-1, UINT64_MAX};
    for (size_t i = 0; i < 64; ++i) words[i] = (UINT64_C(1)<<48) + 19*i;
    for (size_t i = 0; i < 16; ++i) {
        uint64_t p = (uintptr_t)&words[16+i];
        uint64_t expected = words[16+i];
        assert(addr_load(p+32) == expected); ++cases;
        assert(addr_hold(p+24) == expected); ++cases;
        assert(addr_mark(p+16) == expected); ++cases;
        assert(addr_scaled((uintptr_t)&words[16]+32, i) == expected); ++cases;
        assert(addr_scaled_sub((uintptr_t)&words[16], i+1) == expected); ++cases;
        assert(addr_min(p+UINT64_C(2147483648)) == expected); ++cases;
        assert(addr_max(p-UINT64_C(2147483647)) == expected); ++cases;
        assert(addr_outside(p+UINT64_C(2147483649)) == expected); ++cases;
        assert(addr_composed_outside(p+UINT64_C(2147483649)) == expected); ++cases;
        assert(addr_composed_cancel(p+UINT64_C(2147483647)) == expected); ++cases;
        assert(addr_scaled_outside((uintptr_t)&words[16], UINT64_C(2147483648)+i) == expected); ++cases;
        assert(addr_negative(p-32) == expected); ++cases;
        assert(addr_dynamic(p+24, 24) == expected); ++cases;
        assert(addr_swapped(UINT64_C(32)-p) == expected); ++cases;
        assert(addr_large(p+UINT64_C(9223372036854775807)) == expected); ++cases;
        assert(addr_negative_min(p-(UINT64_C(1)<<63)) == expected); ++cases;
        assert(addr_multi(p+32, &out) == expected && out == p); ++cases;
        assert(addr_loaded_flags(p+32) == expected); ++cases;
        assert(addr_store(p+32, expected+1) == 0 && words[16+i] == expected+1); ++cases;
    }
    for (size_t i = 0; i < sizeof(flags)/sizeof(flags[0]); ++i) {
        uint64_t x = flags[i];
        assert(addr_flags(x, &out) == (x-32 == 0) && out == x-32); ++cases;
        assert(addr_word((uint32_t)x) == (uint32_t)x-UINT32_C(32)); ++cases;
    }
    assert(addr_float(64.5) == 32.5); ++cases;
    printf("sub address probes: %u cases passed\n", cases);
}
