/* The C side of test/core/c_address*.selka (MCU-NOC3, `@address` extern funcs, docs/c-ffi.md "Calls through an address"):
 * no function here is called by name from Selka except the getters, which hand back function pointers, one as an
 * `extern type` handle and one as an integer. `weigh` takes eight `int64_t`, so under the System V convention the last
 * two go on the stack; `count_byte` takes a lent span and an out-parameter. */
#include <stdbool.h>
#include <stdint.h>

/* Each argument kept apart in the answer: a + 2b + 3c + ... + 8h, with h weighted by 10^12 so it cannot be lost. */
static int64_t weigh(int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, int64_t f, int64_t g, int64_t h) {
    return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + h * 1000000000000LL;
}

/* Narrow scalars of four widths beside a wide one: a * 1000 + b * 100 + c * 10 + d, plus e when `flag`. */
static int32_t mix(int32_t a, int64_t b, uint8_t c, int16_t d, bool flag, int32_t e, int32_t f, int32_t g) {
    return a * 1000 + (int32_t)b * 100 + (int32_t)c * 10 + d + (flag ? e : 0) + f * g;
}

/* How many octets of `data` are `byte`, through `*count`; whether there was any. */
static bool count_byte(const uint8_t *data, int64_t length, uint8_t byte, int64_t *count) {
    int64_t n = 0;
    for (int64_t i = 0; i < length; ++i) n += data[i] == byte;
    *count = n;
    return n > 0;
}

/* The getters: what a C library hands back as a callback or a plug-in entry. */
void *ffi_weigh_handle(void) { return (void *)weigh; }
uint64_t ffi_weigh_address(void) { return (uint64_t)(uintptr_t)weigh; }
uint64_t ffi_mix_address(void) { return (uint64_t)(uintptr_t)mix; }
void *ffi_count_handle(void) { return (void *)count_byte; }
void *ffi_no_function(void) { return 0; }
