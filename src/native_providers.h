#ifndef MYLANG_NATIVE_PROVIDERS_H
#define MYLANG_NATIVE_PROVIDERS_H
#include <stdint.h>
#include <stddef.h>
#define MYLANG_NATIVE_PROVIDER_ABI 2
#define mylang_native_providers mylang_native_providers_v2
/* Trusted synchronous adapters. Contexts outlive the generated program's run.
   No callback is invoked while checking whether an entry grant is available. */
typedef enum {
    MYLANG_PROVIDER_OK = 0,
    MYLANG_PROVIDER_UNAVAILABLE = 1,
    MYLANG_PROVIDER_DENIED = 2,
    MYLANG_PROVIDER_FAILED = 3,
    MYLANG_PROVIDER_OUT_OF_MEMORY = 4,
    MYLANG_PROVIDER_NO_CAPACITY = 5
} MylangProviderStatus;
/* The value member is meaningful only when status is MYLANG_PROVIDER_OK. */
typedef struct { MylangProviderStatus status; int64_t value; } MylangClockResult;
typedef struct { MylangProviderStatus status; uint64_t value; } MylangRandomResult;
/* On success, present is 0 or 1 and length fits the supplied output capacity.
   Empty present values differ from absent values. Never report truncated success. */
typedef struct { MylangProviderStatus status; size_t length; int present; } MylangEnvironmentResult;
typedef struct {
    void *clock_context;
    MylangClockResult (*clock_now)(void *context);
    void *random_context;
    MylangRandomResult (*random_u64)(void *context);
    void *environment_context;
    MylangEnvironmentResult (*environment_get)(void *context, const uint8_t *name, size_t name_length, uint8_t *output, size_t capacity);
} MylangNativeProviders;
/* Adapter setup must not perform a guest read. The default supplies no grants. */
MylangNativeProviders mylang_native_providers(void);
#endif
