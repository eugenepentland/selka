/* A linked C unit that embeds the program with its own native providers
   (`selka_native_providers_v7`, the record `src/core/runtime/core_io.c` reads
   when a linked unit defines it), here only an Environment context. The record
   is spelled out field for field because the old back end's header that
   declared it is gone. Environment names still come from the grants alone. */
#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef struct { int status; int64_t value; } ClockResult;
typedef struct { int status; uint64_t value; } RandomResult;
typedef struct { int status; size_t length; int present; } EnvironmentResult;
typedef struct {
    void *context;
    unsigned permissions;
    void *acquire, *complete, *release, *read, *write;
} ResourceProvider;
typedef struct {
    const void *bindings;
    size_t count;
    uint64_t max_calls, max_work;
    size_t max_values, max_depth;
    size_t max_payload;
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

static EnvironmentResult absent(void *context, const uint8_t *name, size_t length, uint8_t *output, size_t capacity) {
    (void)name; (void)length; (void)output; (void)capacity;
    return (EnvironmentResult){context && !strcmp(context, "CUSTOM") ? 0 : 3, 0, 0};
}

NativeProviders selka_native_providers_v7(void) {
    static char context[] = "CUSTOM";
    NativeProviders providers = {0};
    providers.environment_context = context;
    providers.environment_get = absent;
    return providers;
}
