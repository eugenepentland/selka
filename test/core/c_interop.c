/* The C side of the D-FFI fixtures (c_interop*.selka): spans in, a copied bytes result, out-parameters and handles. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Spans: the sum of the octets, scaled, plus the length, so a pointer or length off by one shows. */
int64_t ffi_span_sum(const uint8_t *data, int64_t length, int64_t scale) {
    int64_t total = 0;
    for (int64_t i = 0; i < length; ++i) total += data[i];
    return total * scale + length;
}
int64_t ffi_span_two(const uint8_t *a, int64_t na, const uint8_t *b, int64_t nb) { return na * 1000 + nb + (na && nb && a[0] == b[0]); }

/* A copied bytes result: mode 0 five octets with a NUL, 1 an empty non-null result, 2 a null empty one, 3 a negative
   length and 4 a null pointer with a length (the last two trap). */
static const uint8_t message[] = {'h', 'i', 0, 0xff, 'z'};
const uint8_t *ffi_give(int64_t mode, int64_t *length) {
    switch (mode) {
    case 0: *length = 5; return message;
    case 1: *length = 0; return message;
    case 2: *length = 0; return 0;
    case 3: *length = -1; return message;
    default: *length = 3; return 0;
    }
}
/* A heap result C frees on the next call: the runtime must have copied it already. */
static uint8_t *last;
const uint8_t *ffi_give_heap(int64_t n, int64_t *length) {
    free(last);
    last = malloc((size_t)(n ? n : 1));
    memset(last, 'a', (size_t)n);
    *length = n;
    return last;
}

/* Out-parameters of several widths. */
int32_t ffi_split(int64_t value, int64_t *high, int32_t *low, uint8_t *ok) {
    *high = value >> 32;
    *low = (int32_t)(value & 0xffffffff);
    *ok = 1;
    return 7;
}
void ffi_bump(int64_t *x) { *x += 1; }

/* Handles: a counted heap object behind an opaque pointer. */
typedef struct ffi_thing { int64_t value; } ffi_thing;
static int64_t live_things;
ffi_thing *ffi_thing_new(int64_t value) { ffi_thing *t = malloc(sizeof *t); t->value = value; ++live_things; return t; }
int64_t ffi_thing_value(const ffi_thing *t) { return t ? t->value : -1; }
void ffi_thing_free(ffi_thing *t) { if (t) --live_things; free(t); }
int64_t ffi_live_things(void) { return live_things; }
/* A step that fails on its nth call from now (0: the next one) and then succeeds again; a negative count never fails. */
static int64_t calls_until_failure = -1;
void ffi_fail_after(int64_t n) { calls_until_failure = n; }
int32_t ffi_step(void) {
    if (calls_until_failure == 0) { calls_until_failure = -1; return 1; }
    if (calls_until_failure > 0) --calls_until_failure;
    return 0;
}
/* An out-parameter that is a handle: the C idiom `open(name, &out)`. */
int32_t ffi_thing_open(const uint8_t *name, int64_t length, ffi_thing **out) {
    *out = length ? ffi_thing_new(name[0]) : 0;
    return length ? 0 : 1;
}
