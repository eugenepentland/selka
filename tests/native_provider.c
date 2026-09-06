/* Deterministic trusted adapter used only by native provider acceptance. */
#include "native_providers.h"
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
static unsigned clock_calls, random_calls;
static int setting(const char *name) { const char *value = getenv(name); return value ? atoi(value) : 0; }
static MylangClockResult clock_read(void *context) {
    ++*(unsigned *)context;
    return (MylangClockResult){(MylangProviderStatus)setting("TEST_CLOCK_STATUS"), INT64_MIN};
}
static MylangRandomResult random_read(void *context) {
    ++*(unsigned *)context;
    return (MylangRandomResult){(MylangProviderStatus)setting("TEST_RANDOM_STATUS"), UINT64_MAX};
}
static void report(void) { fprintf(stderr, "provider-calls: %u %u\n", clock_calls, random_calls); }
MylangNativeProviders mylang_native_providers(void) {
    atexit(report);
    int missing = setting("TEST_MISSING");
    return (MylangNativeProviders){&clock_calls, missing & 1 ? NULL : clock_read,
        &random_calls, missing & 2 ? NULL : random_read};
}
