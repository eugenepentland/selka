#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

int64_t runtime_bench_now(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) abort();
    return (int64_t)now.tv_sec * INT64_C(1000000000) + now.tv_nsec;
}
