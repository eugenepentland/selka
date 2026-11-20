/* The bare runtime's second unit (-DMYL_BARE), compiled apart from the first so its names cannot clash with the
 * prototypes the kept files declare:
 *  - the atomic operations the compiler calls on a CPU with none (the Cortex-M0+ has no exclusive loads): no interrupt
 *    handler touches runtime state, and with two cores every atomic the runtime keeps is each core's own (MYL_TLS and
 *    SELKA_CORE_LOCAL, core_bare_cores.c), so each is the plain operation;
 *  - the runtime entries that come from a prebuilt x86 object on Linux (float text, format specifications, BLAKE3,
 *    src/core/number_runtime.zig): each ends in `error[R_BARE_UNSUPPORTED]` naming itself, instead of a link error.
 */
#include <stdbool.h>
#include <stdint.h>

#define BARE_ATOMICS(N, T)                                                                                        \
    T bare_load_##N(const volatile T *at, int order) __asm__("__atomic_load_" #N);                               \
    T bare_load_##N(const volatile T *at, int order) { (void)order; return *at; }                                \
    void bare_store_##N(volatile T *at, T value, int order) __asm__("__atomic_store_" #N);                       \
    void bare_store_##N(volatile T *at, T value, int order) { (void)order; *at = value; }                        \
    T bare_exchange_##N(volatile T *at, T value, int order) __asm__("__atomic_exchange_" #N);                    \
    T bare_exchange_##N(volatile T *at, T value, int order) { (void)order; T old = *at; *at = value; return old; } \
    bool bare_cas_##N(volatile T *at, T *expected, T desired, int good, int bad) __asm__("__atomic_compare_exchange_" #N); \
    bool bare_cas_##N(volatile T *at, T *expected, T desired, int good, int bad) {                               \
        (void)good; (void)bad;                                                                                    \
        if (*at == *expected) { *at = desired; return true; }                                                    \
        *expected = *at;                                                                                          \
        return false;                                                                                             \
    }                                                                                                             \
    T bare_add_##N(volatile T *at, T value, int order) __asm__("__atomic_fetch_add_" #N);                        \
    T bare_add_##N(volatile T *at, T value, int order) { (void)order; T old = *at; *at = old + value; return old; } \
    T bare_sub_##N(volatile T *at, T value, int order) __asm__("__atomic_fetch_sub_" #N);                        \
    T bare_sub_##N(volatile T *at, T value, int order) { (void)order; T old = *at; *at = old - value; return old; } \
    T bare_or_##N(volatile T *at, T value, int order) __asm__("__atomic_fetch_or_" #N);                          \
    T bare_or_##N(volatile T *at, T value, int order) { (void)order; T old = *at; *at = old | value; return old; } \
    T bare_and_##N(volatile T *at, T value, int order) __asm__("__atomic_fetch_and_" #N);                        \
    T bare_and_##N(volatile T *at, T value, int order) { (void)order; T old = *at; *at = old & value; return old; }

BARE_ATOMICS(1, uint8_t)
BARE_ATOMICS(2, uint16_t)
BARE_ATOMICS(4, uint32_t)
BARE_ATOMICS(8, uint64_t)

__attribute__((noreturn)) void myl_bare_unsupported(const char *name);
#define BARE_ABSENT(name) \
    __attribute__((weak, noreturn)) void name(void) { myl_bare_unsupported(#name); }
BARE_ABSENT(myl_core_str_from_f64)
BARE_ABSENT(myl_core_buffer_append_f64)
BARE_ABSENT(myl_core_str_from_f32)
BARE_ABSENT(myl_core_format_float32)
BARE_ABSENT(myl_core_parse_f32_range)
BARE_ABSENT(myl_core_span_parse_f32_range)
BARE_ABSENT(myl_core_format_number)
BARE_ABSENT(myl_core_format_float)
BARE_ABSENT(myl_core_format_text)
BARE_ABSENT(myl_core_parse_float_range)
BARE_ABSENT(myl_core_span_parse_float_range)
BARE_ABSENT(myl_core_round_float)
BARE_ABSENT(myl_core_format_len)
BARE_ABSENT(myl_core_format_append)
BARE_ABSENT(myl_core_format_print)
BARE_ABSENT(myl_core_format_write)
BARE_ABSENT(myl_core_print_f64)
BARE_ABSENT(myl_core_str_append_f64)
BARE_ABSENT(myl_core_format_octets_print)
BARE_ABSENT(myl_core_format_octets_append)
BARE_ABSENT(myl_core_format_octets_len)
BARE_ABSENT(myl_core_bytes_blake3)
BARE_ABSENT(myl_core_span_bytes_blake3)
