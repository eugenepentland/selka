/* Trusted host adapters behind a native executable's explicit capability
   grants. These run in the program's own process: they are an authority
   boundary for guest source, never a sandbox against a compromised host. */
#define _POSIX_C_SOURCE 200809L
#include "qbe_grants.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
/* Parsed `--allow-*` options; every field defaults to no authority at all. */
typedef struct {
    MylangScoped scoped;
    int writable, clock, entropy, environment;
    const char *names;
    uint64_t state;
} MylangGrants;
static MylangClockResult clock_now(void *context) {
    (void)context;
    MylangClockResult result = {MYLANG_PROVIDER_FAILED, 0};
    struct timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now)) return result;
    if (now.tv_sec > (INT64_MAX - now.tv_nsec) / 1000000000) return result;
    result.status = MYLANG_PROVIDER_OK;
    result.value = (int64_t)now.tv_sec * 1000000000 + now.tv_nsec;
    return result;
}
/* A reproducible SplitMix64 stream, seeded by the grant or by the wall clock.
   This is a deterministic generator, not a cryptographic entropy source. */
static MylangRandomResult random_u64(void *context) {
    uint64_t *state = context;
    *state += UINT64_C(0x9e3779b97f4a7c15);
    uint64_t value = *state;
    value = (value ^ (value >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    value = (value ^ (value >> 27)) * UINT64_C(0x94d049bb133111eb);
    MylangRandomResult result = {MYLANG_PROVIDER_OK, value ^ (value >> 31)};
    return result;
}
/* An empty allowlist grants every name the process already holds. */
static int allowed(const char *names, const char *name, size_t length) {
    if (!*names) return 1;
    for (const char *cursor = names; *cursor;) {
        const char *comma = strchr(cursor, ',');
        size_t width = comma ? (size_t)(comma - cursor) : strlen(cursor);
        if (width == length && !memcmp(cursor, name, length)) return 1;
        if (!comma) break;
        cursor = comma + 1;
    }
    return 0;
}
static MylangEnvironmentResult environment_get(void *context, const uint8_t *name, size_t name_length, uint8_t *output, size_t capacity) {
    MylangEnvironmentResult result = {MYLANG_PROVIDER_OK, 0, 0};
    char frame[256];
    if (name_length >= sizeof frame) { result.status = MYLANG_PROVIDER_DENIED; return result; }
    memcpy(frame, name, name_length);
    frame[name_length] = 0;
    if (!allowed(context, frame, name_length)) { result.status = MYLANG_PROVIDER_DENIED; return result; }
    const char *value = getenv(frame);
    if (!value) return result;
    size_t width = strlen(value);
    if (width > capacity) { result.status = MYLANG_PROVIDER_NO_CAPACITY; return result; }
    memcpy(output, value, width);
    result.present = 1;
    result.length = width;
    return result;
}
/* Match a flag that may stand alone or carry a value, rejecting a repeat. */
static const char *optional(const char *argument, const char *flag, int *seen) {
    size_t width = strlen(flag);
    if (strncmp(argument, flag, width)) return NULL;
    if (!argument[width]) return *seen ? NULL : "";
    if (argument[width] != '=' || !argument[width + 1] || *seen) return NULL;
    return argument + width + 1;
}
static int directory(MylangGrants *grants, const char *path, int writable) {
    if (!*path || !mylang_scoped_grant(&grants->scoped, path, writable)) return 0;
    grants->writable = grants->writable || writable;
    return 1;
}
/* Consume one recognized grant option; zero rejects the command line. */
static int accept(MylangGrants *grants, const char *argument, int *matched) {
    *matched = 1;
    if (!strncmp(argument, "--allow-read=", 13)) return directory(grants, argument + 13, 0);
    if (!strncmp(argument, "--allow-write=", 14)) return directory(grants, argument + 14, 1);
    if (!strcmp(argument, "--allow-clock")) return !grants->clock && (grants->clock = 1);
    const char *seed = optional(argument, "--allow-random", &grants->entropy);
    if (seed) {
        grants->entropy = 1;
        grants->state = *seed ? strtoull(seed, NULL, 10) : (uint64_t)clock_now(NULL).value;
        return 1;
    }
    const char *names = optional(argument, "--allow-env", &grants->environment);
    if (names) {
        grants->environment = 1;
        grants->names = names;
        return 1;
    }
    if (!strcmp(argument, "--allow-all")) {
        if (grants->clock || grants->entropy || grants->environment || grants->scoped.count) return 0;
        grants->clock = grants->entropy = grants->environment = 1;
        grants->state = (uint64_t)clock_now(NULL).value;
        grants->names = "";
        return directory(grants, ".", 1);
    }
    *matched = strncmp(argument, "--allow-", 8) == 0;
    return !*matched;
}
static void provision(MylangGrants *grants, MylangNativeProviders *providers) {
    (void)mylang_host_charge;
    if (grants->scoped.count) providers->filesystem = mylang_scoped_provider(&grants->scoped, grants->writable ? 7u : 5u);
    if (grants->clock) providers->clock_now = clock_now;
    if (grants->entropy) {
        providers->random_context = &grants->state;
        providers->random_u64 = random_u64;
    }
    if (grants->environment) {
        providers->environment_context = (void *)(uintptr_t)grants->names;
        providers->environment_get = environment_get;
    }
}
int mylang_qbe_run_grants(uint64_t (*entry)(void *), int argc, char **argv, const MylangNativeProviders *base) {
    MylangGrants grants = {0};
    mylang_scoped_init(&grants.scoped);
    grants.names = "";
    char **kept = calloc(argc > 0 ? (size_t)argc : 1, sizeof *kept);
    if (!kept) { fputs("OutOfMemory: QBE runtime failure\n", stderr); return 2; }
    int count = 0;
    if (argc > 0) kept[count++] = argv[0];
    for (int i = 1; i < argc; ++i) {
        int matched = 0;
        int usable = accept(&grants, argv[i], &matched);
        if (matched && !usable) {
            fprintf(stderr, "mylang: the option %s is not a usable capability grant\n", argv[i]);
            free(kept);
            mylang_scoped_close(&grants.scoped);
            return 2;
        }
        if (!matched) kept[count++] = argv[i];
    }
    MylangNativeProviders providers = base ? *base : (MylangNativeProviders){0};
    provision(&grants, &providers);
    int status = mylang_qbe_run_providers(entry, count, kept, &providers);
    free(kept);
    mylang_scoped_close(&grants.scoped);
    return status;
}
