/* spec: QBE-PHI-WIDTH-1: valid source phis preserve their classes after reuse. */
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>

extern uint64_t long_phi(uint64_t, uint64_t *, uint64_t *);
extern uint32_t word_phi(uint64_t, uint64_t *, uint64_t *);
extern uint64_t cross_phi(uint32_t, uint64_t *);
extern uint64_t same_long_phi(uint32_t, uint64_t *);
extern uint32_t same_word_phi(uint32_t, uint64_t *);
static unsigned checks, failures;

/* Give any incorrectly half-written spill a deterministic nonzero upper word. */
__attribute__((noinline)) static void prime_stack(void) {
    volatile uint64_t dust[128];
    for (unsigned i = 0; i < 128; ++i) dust[i] = UINT64_C(0x9876543212345678);
    __asm__ volatile("" : : "m"(dust) : "memory");
}

static void expect(const char *name, uint64_t got, uint64_t wanted) {
    ++checks;
    if (got == wanted) return;
    ++failures;
    fprintf(stderr, "%s: got=%"PRIu64" expected=%"PRIu64"\n", name, got, wanted);
}

static void pressure(void) {
    const uint64_t cases[] = {0, 1, UINT64_C(1) << 32, UINT64_C(1) << 48, UINT64_MAX};
    uint64_t values[14], total = 0;
    for (unsigned i = 0; i < 14; ++i) total += (values[i] = i + 1);
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; ++i) {
        uint64_t out[2] = {0};
        prime_stack();
        expect("long phi spill", long_phi(cases[i], values, out), total + (cases[i] != 0));
        expect("long branch", out[0], cases[i] ? 17 : 23);
        prime_stack();
        expect("word phi spill", word_phi(cases[i], values, out), total + (cases[i] != 0));
        expect("word branch", out[0], cases[i] ? 17 : 23);
    }
}

static void reuse(void) {
    const uint32_t cases[] = {0, 1, 7, UINT32_MAX};
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; ++i) {
        uint64_t out[2] = {0}, wanted = cases[i] ? UINT64_MAX : 0;
        expect("different phi classes", cross_phi(cases[i], out), wanted);
        expect("narrow predecessor", out[1], (uint32_t)wanted);
        expect("same long phi classes", same_long_phi(cases[i], out), wanted);
        expect("long predecessor", out[1], wanted);
        out[1] = 0;
        expect("same word phi classes", same_word_phi(cases[i], out), (uint32_t)wanted);
        expect("word predecessor", out[1], (uint32_t)wanted);
    }
}

int main(void) {
    pressure();
    reuse();
    if (failures) return 1;
    printf("phi widths: %u passed\n", checks);
    return 0;
}
