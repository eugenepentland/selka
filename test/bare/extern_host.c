/* The C side of test/bare/extern_host.selka and extern_registers.selka (MCU-EXT): plain functions a device program calls
 * through `extern func`, as the platform's C (the boot ROM's flash routines) would be. Under AAPCS `mix`'s `int64_t`
 * takes the register pair r2:r3, so its last two arguments go on the stack: the call crosses both ways. */
#include <stdint.h>

/* A computed value: x * x + 1. */
int32_t square_plus(int32_t x) { return x * x + 1; }

/* Four scalars of three widths, each kept apart in the answer: a * 1000 + b * 100 + c * 10 + d. */
int32_t mix(int32_t a, int64_t b, uint8_t c, int32_t d) { return a * 1000 + (int32_t)b * 100 + (int32_t)c * 10 + d; }

/* The word a flash chip's unique-ID read would answer, here a constant, for the program that also has registers. */
uint32_t chip_word(void) { return 0x5E41u; }
