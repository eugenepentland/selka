/* Deterministic v7 embedding for the unchanged time_random_provider.my fixture.
   Callbacks return only scalar values. They neither retain guest pointers nor
   mutate provider state; each invocation is independently repeatable. */
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int status; int64_t value; } ClockResult;
typedef struct { int status; uint64_t value; } RandomResult;
typedef struct { int status; size_t length; int present; } EnvironmentResult;
typedef struct { int status; uint64_t handle; } ResourceResult;
typedef struct { int status; size_t length; int eof; } ResourceRead;
typedef struct { int status; size_t length; } ResourceWrite;
typedef struct {
    void *context;
    unsigned permissions;
    ResourceResult (*acquire)(void *, const uint8_t *, size_t, unsigned);
    int (*complete)(void *, uint64_t);
    void (*release)(void *, uint64_t);
    ResourceRead (*read)(void *, uint64_t, uint8_t *, size_t);
    ResourceWrite (*write)(void *, uint64_t, const uint8_t *, size_t);
} ResourceProvider;
typedef struct {
    const void *bindings;
    size_t count;
    uint64_t max_calls, max_work;
    size_t max_values, max_depth, max_payload;
} HostRegistry;
typedef struct {
    void *clock_context;
    ClockResult (*clock_now)(void *);
    void *random_context;
    RandomResult (*random_u64)(void *);
    void *environment_context;
    EnvironmentResult (*environment_get)(void *, const uint8_t *, size_t, uint8_t *, size_t);
    ResourceProvider filesystem, network;
    HostRegistry host;
} NativeProviders;

static int status_for(const char *family) {
    const char *mode = getenv("A05_PROVIDER_MODE");
    size_t size = strlen(family);
    if (!mode || strncmp(mode, family, size) || mode[size] != '_') return 0;
    const char *status = mode + size + 1;
    if (!strcmp(status, "unavailable")) return 1;
    if (!strcmp(status, "denied")) return 2;
    return 3;
}
static ClockResult now(void *context) {
    (void)context;
    return (ClockResult){status_for("clock"), -7};
}
static RandomResult entropy(void *context) {
    (void)context;
    return (RandomResult){status_for("random"), UINT64_C(0x0102030405060708)};
}
NativeProviders mylang_native_providers_v7(void) {
    NativeProviders providers = {0};
    providers.clock_now = now;
    providers.random_u64 = entropy;
    return providers;
}
