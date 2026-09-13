#ifndef MYLANG_NATIVE_PROVIDERS_H
#define MYLANG_NATIVE_PROVIDERS_H
#include <stdint.h>
#include <stddef.h>
#ifndef MYLANG_NATIVE_HOST_H
#include "native_host.h"
#endif
#define MYLANG_NATIVE_PROVIDER_ABI 5
#define mylang_native_providers mylang_native_providers_v5
/* Trusted synchronous adapters. Contexts outlive the generated program's run.
   Callbacks must not reenter this generated program. No callback is invoked
   while checking whether an entry grant is available. */
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
/* On success, present is 0 or 1; a present length fits the output capacity.
   Absent lengths and failed-result length/presence fields are ignored.
   Empty present values differ from absent values. Never report truncated success. */
typedef struct { MylangProviderStatus status; size_t length; int present; } MylangEnvironmentResult;
/* Acquisition success owns a handle; failure owns none. Completion success
   consumes it; completion failure keeps it live. Release never implies completion
   and must return without allocation, failure, or guest reentry. */
typedef struct { MylangProviderStatus status; uint64_t handle; } MylangResourceResult;
/* Transfers keep the handle live, including on errors. Success counts fit the
   borrowed buffer; read EOF is 0 or 1. Error count/EOF members are ignored. */
typedef struct { MylangProviderStatus status; size_t length; int eof; } MylangResourceRead;
typedef struct { MylangProviderStatus status; size_t length; } MylangResourceWrite;
typedef struct {
    void *context;
    unsigned permissions; /* read=1, write=2, complete=4; intersection only */
    MylangResourceResult (*acquire)(void *, const uint8_t *, size_t, unsigned);
    MylangProviderStatus (*complete)(void *, uint64_t);
    void (*release)(void *, uint64_t);
    MylangResourceRead (*read)(void *, uint64_t, uint8_t *, size_t);
    MylangResourceWrite (*write)(void *, uint64_t, const uint8_t *, size_t);
} MylangResourceProvider;
typedef struct MylangNativeProvidersTag {
    void *clock_context;
    MylangClockResult (*clock_now)(void *context);
    void *random_context;
    MylangRandomResult (*random_u64)(void *context);
    void *environment_context;
    MylangEnvironmentResult (*environment_get)(void *context, const uint8_t *name, size_t name_length, uint8_t *output, size_t capacity);
    MylangResourceProvider filesystem, network;
    MylangHostRegistry host;
} MylangNativeProviders;
/* Adapter setup must not perform a guest read. The default supplies no grants. */
MylangNativeProviders mylang_native_providers(void);
#endif
