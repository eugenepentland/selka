/* Native v7 provider fixture: fail loudly on duplicate completion/release,
   use-after-completion, invalid borrowed buffers, or handles left open. */
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
typedef struct { int status; int64_t value; } ClockResult;
typedef struct { int status; uint64_t value; } RandomResult;
typedef struct { int status; size_t length; int present; } EnvironmentResult;
typedef struct { int status; uint64_t handle; } ResourceResult;
typedef struct { int status; size_t length; int eof; } ResourceRead;
typedef struct { int status; size_t length; } ResourceWrite;
typedef struct {
    void *context; unsigned permissions;
    ResourceResult (*acquire)(void *, const uint8_t *, size_t, unsigned);
    int (*complete)(void *, uint64_t);
    void (*release)(void *, uint64_t);
    ResourceRead (*read)(void *, uint64_t, uint8_t *, size_t);
    ResourceWrite (*write)(void *, uint64_t, const uint8_t *, size_t);
} ResourceProvider;
typedef struct { const void *bindings; size_t count; uint64_t max_calls, max_work; size_t max_values, max_depth, max_payload; } HostRegistry;
typedef struct {
    void *clock_context; ClockResult (*clock_now)(void *);
    void *random_context; RandomResult (*random_u64)(void *);
    void *environment_context; EnvironmentResult (*environment_get)(void *, const uint8_t *, size_t, uint8_t *, size_t);
    ResourceProvider filesystem, network; HostRegistry host;
} NativeProviders;
static unsigned opened, completed, released;
static unsigned char active[128];
static ResourceResult acquire(void *ctx, const uint8_t *request, size_t n, unsigned rights) {
    if (ctx != active || n < 2 || request[1] != ':' || !rights || (rights & ~7u)) abort();
    if (n == 13 && !memcmp(request + 2, "missing.txt", 11)) return (ResourceResult){1, 0};
    if (++opened >= sizeof active) abort();
    active[opened] = 1;
    return (ResourceResult){0, opened};
}
static void consume(void *ctx, uint64_t handle) {
    if (ctx != active || handle >= sizeof active || !active[handle]) abort();
    active[handle] = 0;
}
static int complete(void *ctx, uint64_t handle) { consume(ctx, handle); ++completed; return 0; }
static void release(void *ctx, uint64_t handle) { consume(ctx, handle); ++released; }
static ResourceWrite write_value(void *ctx, uint64_t handle, const uint8_t *input, size_t n) {
    if (ctx != active || handle >= sizeof active || !active[handle] || n != 5 || memcmp(input, "saved", 5)) abort();
    return (ResourceWrite){0, n};
}
int64_t resource_counts(void) {
    unsigned live = 0;
    for (size_t i = 0; i < sizeof active; ++i) live += active[i];
    if (live || completed != 5 || released) abort();
    return (int64_t)(completed * 100 + released * 10 + live);
}
NativeProviders mylang_native_providers_v7(void) {
    NativeProviders providers = {0};
    providers.filesystem = (ResourceProvider){active, 7, acquire, complete, release, NULL, write_value};
    return providers;
}
