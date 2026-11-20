/* The C side of test/bare/extern_address.selka (MCU-NOC3): a function Selka calls through its address, as it would call a
 * boot ROM routine whose address it read from the ROM's table. The address is a Thumb one, its low bit set, as the
 * ROM's table holds them. Under AAPCS `weigh`'s `int64_t` takes the register pair r2:r3, so its last two arguments go
 * on the stack. */
#include <stdint.h>

/* Four scalars of three widths, each kept apart in the answer: a * 1000 + b * 100 + c * 10 + d. */
static int32_t weigh(int32_t a, int64_t b, uint8_t c, int32_t d) { return a * 1000 + (int32_t)b * 100 + (int32_t)c * 10 + d; }

/* The address of `weigh`: a Thumb function's, whose low bit is 1. */
uint32_t weigh_address(void) { return (uint32_t)(uintptr_t)&weigh; }
