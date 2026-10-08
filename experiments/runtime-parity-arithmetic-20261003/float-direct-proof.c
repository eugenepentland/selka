#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>

extern uint64_t from_signed(int64_t);
extern uint64_t from_unsigned(uint64_t);

static uint64_t signed_reference(int64_t input) {
    volatile int64_t value = input;
    double result = (double)value;
    uint64_t bits;
    memcpy(&bits, &result, sizeof bits);
    return bits;
}

static uint64_t unsigned_reference(uint64_t input) {
    volatile uint64_t value = input;
    double result = (double)value;
    uint64_t bits;
    memcpy(&bits, &result, sizeof bits);
    return bits;
}

int main(void) {
    unsigned cases = 0;
    for (unsigned bit = 0; bit < 64; ++bit) {
        for (int delta = -4; delta <= 4; ++delta) {
            uint64_t value = (UINT64_C(1) << bit) + (uint64_t)delta;
            int64_t signed_value;
            memcpy(&signed_value, &value, sizeof value);
            if (from_signed(signed_value) != signed_reference(signed_value)) {
                fprintf(stderr, "signed mismatch: %" PRId64 "\n", signed_value);
                return 1;
            }
            if (from_unsigned(value) != unsigned_reference(value)) {
                fprintf(stderr, "unsigned mismatch: %" PRIu64 "\n", value);
                return 2;
            }
            cases += 2;
        }
    }
    printf("%u signed/unsigned raw-bit conversion cases passed\n", cases);
    return 0;
}
