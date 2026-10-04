// Shared helpers for the ideal-ladder kernels (not part of any timed region's contract).
#ifndef LADDER_COMMON_H
#define LADDER_COMMON_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static inline int64_t now_ns(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

/* A failed compiler-inserted check: mylang traps (exit 1). */
static _Noreturn void trap(const char *what) {
    fprintf(stderr, "trap: %s\n", what);
    exit(1);
}

/* Python floor division / modulo on i64, as mylang's `//` and `%`. */
static inline int64_t floordiv(int64_t a, int64_t b) {
    int64_t q = a / b;
    if ((a % b != 0) && ((a < 0) != (b < 0))) q -= 1;
    return q;
}
static inline int64_t floormod(int64_t a, int64_t b) {
    int64_t r = a % b;
    if (r != 0 && ((r < 0) != (b < 0))) r += b;
    return r;
}

/* mylang list[int] today: a header (length, storage pointer) plus i64 elements. */
typedef struct { int64_t len; int64_t *data; } list_i64;

#define MOD 1000000007LL
#endif
