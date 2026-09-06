#ifndef MYLANG_NATIVE_PROVIDERS_H
#define MYLANG_NATIVE_PROVIDERS_H
#include <stdint.h>
#define MYLANG_NATIVE_PROVIDER_ABI 1
#define mylang_native_providers mylang_native_providers_v1
/* Trusted synchronous adapters. Contexts outlive the generated program's run.
   No callback is invoked while checking whether an entry grant is available. */
typedef enum {
    MYLANG_PROVIDER_OK = 0,
    MYLANG_PROVIDER_UNAVAILABLE = 1,
    MYLANG_PROVIDER_DENIED = 2,
    MYLANG_PROVIDER_FAILED = 3,
    MYLANG_PROVIDER_OUT_OF_MEMORY = 4
} MylangProviderStatus;
/* The value member is meaningful only when status is MYLANG_PROVIDER_OK. */
typedef struct { MylangProviderStatus status; int64_t value; } MylangClockResult;
typedef struct { MylangProviderStatus status; uint64_t value; } MylangRandomResult;
typedef struct {
    void *clock_context;
    MylangClockResult (*clock_now)(void *context);
    void *random_context;
    MylangRandomResult (*random_u64)(void *context);
} MylangNativeProviders;
/* Adapter setup must not perform a guest read. The default supplies no grants. */
MylangNativeProviders mylang_native_providers(void);
#endif
