/* Deterministic lifecycle adapter; release only records into fixed storage. */
#include "native_providers.h"
#include <stdio.h>
#include <stdlib.h>
typedef struct { unsigned kind, next, live, completions; } Context;
typedef struct { char op; unsigned kind, handle, permissions, status; size_t length; uint64_t key; } Event;
static Context contexts[2] = {{.kind=0}, {.kind=1}};
static Event events[65536];
static size_t event_count;
static unsigned setting(const char *name, unsigned fallback) {
    const char *text = getenv(name); return text ? (unsigned)strtoul(text, NULL, 10) : fallback;
}
static void record(Event event) {
    if (event_count == 65536) _Exit(92);
    events[event_count++] = event;
}
static MylangResourceResult acquire(void *opaque, const uint8_t *bytes, size_t length, unsigned permissions) {
    Context *context = opaque;
    unsigned status = setting("TEST_RESOURCE_ACQUIRE", 0);
    uint64_t key = 0;
    for (size_t i = 0; i < length; ++i) key = key * 257 + bytes[i];
    unsigned handle = 0;
    if (!status) { handle = ++context->next; ++context->live; }
    record((Event){'A', context->kind, handle, permissions, status, length, key});
    return (MylangResourceResult){(MylangProviderStatus)status, status ? UINT64_MAX : handle};
}
static MylangProviderStatus complete(void *opaque, uint64_t handle) {
    Context *context = opaque;
    unsigned mode = setting("TEST_RESOURCE_COMPLETE", 0), status = 0;
    ++context->completions;
    if (mode == 1 && context->completions == 1) status = 3;
    if (mode == 2) status = 2;
    if (mode == 3) status = 4;
    if (mode == 4) status = 99;
    if (!status) --context->live;
    record((Event){'C', context->kind, (unsigned)handle, 0, status, 0, 0});
    return (MylangProviderStatus)status;
}
static void release(void *opaque, uint64_t handle) {
    Context *context = opaque;
    --context->live;
    record((Event){'R', context->kind, (unsigned)handle, 0, 0, 0, 0});
}
static void finish(void) {
    for (size_t i = 0; i < event_count; ++i) {
        Event e = events[i];
        fprintf(stderr, "resource-event: %c %u %u %u %u %zu %llu\n", e.op, e.kind, e.handle, e.permissions, e.status, e.length, (unsigned long long)e.key);
    }
    fprintf(stderr, "resource-live: %u %u\n", contexts[0].live, contexts[1].live);
    if (contexts[0].live || contexts[1].live) _Exit(91);
}
__attribute__((constructor)) static void setup(void) { atexit(finish); }
MylangNativeProviders mylang_native_providers(void) {
    MylangNativeProviders result = {0};
    if (!setting("TEST_RESOURCE_MISSING", 0)) {
        result.filesystem = (MylangResourceProvider){&contexts[0], setting("TEST_RESOURCE_PERMISSIONS", 7), acquire, complete, release};
        result.network = (MylangResourceProvider){&contexts[1], setting("TEST_RESOURCE_PERMISSIONS", 7), acquire, complete, release};
    }
    return result;
}
