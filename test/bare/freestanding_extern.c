/* The C side of test/bare/freestanding_extern.selka and freestanding_null_address.selka (MCU-NOC2C): a function a freestanding
 * function calls by name, another it calls through its address (a Thumb one, low bit set, as a boot ROM's table holds
 * them), and a getter that answers no address at all. */
#include <stdint.h>

int32_t weigh_named(int32_t a, int32_t b) { return a * 10 + b; }

static int32_t weigh(int32_t a, int32_t b) { return a * 10 + b; }

uint32_t weigh_address(void) { return (uint32_t)(uintptr_t)&weigh; }

uint32_t no_address(void) { return 0; }
