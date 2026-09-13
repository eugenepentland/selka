/* Binary64 bit-pattern API. Only emitted for programs using floating intrinsics. */
#include <math.h>
#include <float.h>
#include <fenv.h>
#if defined(__FAST_MATH__) || FLT_RADIX != 2 || DBL_MANT_DIG != 53 || DBL_MAX_EXP != 1024
#error "mylang binary64 requires strict IEEE binary64 arithmetic"
#endif
static double float_value(uint64_t bits) {
    double value;
    memcpy(&value, &bits, sizeof value);
    return value;
}
static uint64_t float_bits(double value) {
    uint64_t bits;
    if (isnan(value)) return UINT64_C(0x7ff8000000000000);
    memcpy(&bits, &value, sizeof bits);
    return bits;
}
static void float_environment(void) {
    if (fegetround() != FE_TONEAREST) trap("R_FLOAT_ENVIRONMENT");
    volatile double normal = DBL_MIN, half = 0.5;
    volatile double tiny = float_value(1), one = 1.0;
    if (float_bits(normal * half) != UINT64_C(0x0008000000000000) || float_bits(tiny * one) != 1) trap("R_FLOAT_ENVIRONMENT");
}
static V float_binary(int op, uint64_t left, uint64_t right) {
    float_environment();
    double a = float_value(left), b = float_value(right);
    switch (op) {
        case 0: return float_bits(a + b);
        case 1: return float_bits(a - b);
        case 2: return float_bits(a * b);
        case 3: return float_bits(a / b);
        case 4: return a == b;
        case 5: return a < b;
        case 6: return a <= b;
        default: host_failure("InternalError");
    }
}
static V float_unary(int op, uint64_t input) {
    float_environment();
    double a = float_value(input);
    switch (op) {
        case 0: return float_bits(sqrt(a));
        case 1: return float_bits(floor(a));
        case 2: return float_bits(ceil(a));
        case 3: return float_bits(trunc(a));
        case 4: return float_bits(fabs(a));
        case 5: return float_bits(-a);
        case 6: return float_bits((double)input);
        case 7:
            a = trunc(a);
            if (!isfinite(a) || a < 0 || a >= 18446744073709551616.0) trap("R_FLOAT_CONVERSION");
            return (uint64_t)a;
        case 8: {
            int64_t signed_input;
            memcpy(&signed_input, &input, sizeof signed_input);
            return float_bits((double)signed_input);
        }
        case 9:
            a = trunc(a);
            if (!isfinite(a) || a < -9223372036854775808.0 || a >= 9223372036854775808.0) trap("R_FLOAT_CONVERSION");
            return (int64_t)a;
        default: host_failure("InternalError");
    }
}
