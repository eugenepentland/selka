#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int64_t runtime_bench_now(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC,&now)) abort();
    return (int64_t)now.tv_sec*INT64_C(1000000000)+now.tv_nsec;
}
void local_list_report(int64_t checksum, int64_t elapsed) {
    assert(elapsed>0);
    printf("%" PRId64 " %" PRId64 "\n",checksum,elapsed);
}
static int64_t input(const char *name) {
    const char *text=getenv(name);
    if (!text || !*text) return 0;
    char *end;
    int64_t value=strtoll(text,&end,10);
    return *end?0:value;
}
int64_t local_list_iterations(void) { return input("LOCAL_LIST_ITERATIONS"); }
int64_t local_list_seed(void) { return input("LOCAL_LIST_SEED"); }
