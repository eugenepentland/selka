/* C functions for v_extern_narrow.selka (NEW-CORE-S5-EXTERN-ABI-1): each widens or
   narrows one scalar, so an argument passed without its SysV extension shows up
   as a wrong number. */
#include <stdbool.h>
#include <stdint.h>

int64_t widen_i8(int8_t x) { return x; }
int64_t widen_i16(int16_t x) { return x; }
int64_t widen_u8(uint8_t x) { return x; }
int64_t widen_u16(uint16_t x) { return x; }
int64_t widen_i32(int32_t x) { return x; }
int64_t widen_u32(uint32_t x) { return x; }
int64_t widen_bool(bool x) { return x ? 7 : 3; }
int8_t neg_i8(int64_t x) { return (int8_t)(-x); }
uint8_t make_u8(int64_t x) { return (uint8_t)x; }
int16_t neg_i16(int64_t x) { return (int16_t)(-x); }
uint16_t make_u16(int64_t x) { return (uint16_t)x; }
bool is_odd(int64_t x) { return (x & 1) != 0; }
int64_t many(int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, int64_t f, int64_t g, int8_t h, uint16_t i, double x, double y, double z) {
    return a + 2 * b + 3 * c + 4 * d + 5 * e + 6 * f + 7 * g + 8 * h + 9 * i + (int64_t)(x + y * 2 + z * 3);
}
