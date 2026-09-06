/* Deterministic environment adapter for VM/native acceptance, never ambient getenv lookup. */
#include "native_providers.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
static unsigned calls;
static int setting(const char *name) { const char *text = getenv(name); return text ? atoi(text) : 0; }
static MylangEnvironmentResult lookup(void *context, const uint8_t *name, size_t length, uint8_t *output, size_t capacity) {
    ++*(unsigned *)context;
    const uint8_t key[] = {75, 0, 255};
    if (setting("TEST_EMPTY_NAME") ? length != 0 : length != 3 || memcmp(name, key, 3))
        return (MylangEnvironmentResult){MYLANG_PROVIDER_FAILED, 0, 0};
    int mode = setting("TEST_ENV_MODE");
    if (mode == 9) return (MylangEnvironmentResult){MYLANG_PROVIDER_OK, 2, 1};
    memset(output, 170, capacity);
    switch (mode) {
        case 1: return (MylangEnvironmentResult){MYLANG_PROVIDER_OK, SIZE_MAX, 0};
        case 2: return (MylangEnvironmentResult){MYLANG_PROVIDER_OK, 0, 1};
        case 3: return (MylangEnvironmentResult){MYLANG_PROVIDER_NO_CAPACITY, 0, 0};
        case 4: return (MylangEnvironmentResult){MYLANG_PROVIDER_DENIED, 0, 0};
        case 5: return (MylangEnvironmentResult){MYLANG_PROVIDER_FAILED, 0, 0};
        case 6: return (MylangEnvironmentResult){MYLANG_PROVIDER_UNAVAILABLE, 0, 0};
        case 7: return (MylangEnvironmentResult){MYLANG_PROVIDER_OUT_OF_MEMORY, 0, 0};
        case 8: return (MylangEnvironmentResult){MYLANG_PROVIDER_OK, capacity + 1, 1};
        case 10:
            if (!capacity) return (MylangEnvironmentResult){MYLANG_PROVIDER_NO_CAPACITY, 0, 0};
            output[0] = (uint8_t)calls;
            return (MylangEnvironmentResult){MYLANG_PROVIDER_OK, 1, 1};
        default:
            if (capacity < 3) return (MylangEnvironmentResult){MYLANG_PROVIDER_NO_CAPACITY, 0, 0};
            output[0] = 65; output[1] = 0; output[2] = 255;
            return (MylangEnvironmentResult){MYLANG_PROVIDER_OK, 3, 1};
    }
}
static void report(void) { fprintf(stderr, "environment-calls: %u\n", calls); }
MylangNativeProviders mylang_native_providers(void) {
    atexit(report);
    return (MylangNativeProviders){.environment_context=&calls,
        .environment_get=setting("TEST_ENV_MISSING") ? NULL : lookup};
}
