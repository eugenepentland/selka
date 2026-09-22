/* Bounded byte input/output only; parsing and schematic decisions belong to the
   guest. These callbacks are the trusted half of the schematic pilot's boundary
   and are compiled into the guest's own native executable.

   The driver owns publication, so rendered bytes accumulate in a private file it
   reads back only after a clean exit, and the first located guest issue is left
   in another private file for the driver to report. Configuration arrives
   through the environment because a native executable's own command line is
   reserved for capability grants and runtime budgets. */
#define _POSIX_C_SOURCE 200809L
#include "native_providers.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Three explicitly supplied source documents, each bounded by the driver. */
#define MYLANG_SCHEMATIC_DOCUMENTS 3
/* Unpublished rendered output never grows past the pilot's fixed capacity. */
#define MYLANG_SCHEMATIC_OUTPUT (4u * 1024u * 1024u)

/* Borrowed documents, the unpublished output file and the first located issue. */
typedef struct {
    unsigned char *bytes[MYLANG_SCHEMATIC_DOCUMENTS];
    size_t length[MYLANG_SCHEMATIC_DOCUMENTS];
    size_t count, written;
    FILE *output;
    const char *issue;
    int reported;
} MylangSchematic;
static MylangSchematic state;
enum { COUNT_CIRCUIT, COUNT_PINOUT, COUNT_INTERFACE, COUNT_LENGTH,
       COUNT_BYTE, COUNT_PUT, COUNT_ISSUE, COUNT_TOTAL };
static uint64_t counts[COUNT_TOTAL];
static void dump_counts(void) {
    if (!getenv("MYLANG_HOST_COUNTS")) return;
    static const char *names[COUNT_TOTAL] = {
        "io::circuit_input", "io::pinout_input", "io::interface_input",
        "io::length", "io::byte", "io::put", "io::issue"
    };
    for (size_t i = 0; i < COUNT_TOTAL; ++i)
        fprintf(stderr, "HOST_COUNT %s %llu\n", names[i],
                (unsigned long long)counts[i]);
}

static void unavailable(const char *channel) {
    fprintf(stderr, "schematic-svg: the %s channel is unavailable\n", channel);
    exit(2);
}
/* Copy one whole driver-supplied document; the guest indexes it afterwards. */
static void load(size_t index, const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) unavailable("document");
    if (fseek(file, 0, SEEK_END)) unavailable("document");
    long size = ftell(file);
    if (size < 0 || fseek(file, 0, SEEK_SET)) unavailable("document");
    state.bytes[index] = malloc((size_t)size + 1);
    if (!state.bytes[index]) unavailable("document");
    if (size && fread(state.bytes[index], 1, (size_t)size, file) != (size_t)size) unavailable("document");
    state.length[index] = (size_t)size;
    fclose(file);
}
static void release(void) {
    if (state.output) fclose(state.output);
    state.output = NULL;
    for (size_t i = 0; i < state.count; ++i) free(state.bytes[i]);
    state.count = 0;
}
/* A document identifier is valid only while the driver supplied that document. */
static int known(int64_t id) {
    return id >= 0 && (size_t)id < state.count;
}
static const char *identify(MylangHostCall *call, int64_t id) {
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    if (!known(id) || !call->capacity) return "HostFailure";
    call->output[0] = (MylangHostNode){"i64", (uint64_t)id, 0};
    call->output_nodes = 1;
    return NULL;
}
static const char *circuit_input(void *context, MylangHostCall *call) {
    counts[COUNT_CIRCUIT]++;
    (void)context;
    return identify(call, 0);
}
static const char *pinout_input(void *context, MylangHostCall *call) {
    counts[COUNT_PINOUT]++;
    (void)context;
    return identify(call, 1);
}
static const char *interface_input(void *context, MylangHostCall *call) {
    counts[COUNT_INTERFACE]++;
    (void)context;
    return identify(call, 2);
}
static const char *length(void *context, MylangHostCall *call) {
    counts[COUNT_LENGTH]++;
    (void)context;
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    if (call->argument_nodes != 1 || !call->capacity) return "HostFailure";
    int64_t id = (int64_t)call->arguments[0].bits;
    if (!known(id)) return "HostFailure";
    call->output[0] = (MylangHostNode){"i64", (uint64_t)state.length[id], 0};
    call->output_nodes = 1;
    return NULL;
}
static const char *byte(void *context, MylangHostCall *call) {
    counts[COUNT_BYTE]++;
    (void)context;
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    if (call->argument_nodes != 2 || !call->capacity) return "HostFailure";
    int64_t id = (int64_t)call->arguments[0].bits, position = (int64_t)call->arguments[1].bits;
    if (!known(id) || position < 0 || (uint64_t)position >= state.length[id]) return "HostFailure";
    call->output[0] = (MylangHostNode){"u8", state.bytes[id][position], 0};
    call->output_nodes = 1;
    return NULL;
}
static const char *put(void *context, MylangHostCall *call) {
    counts[COUNT_PUT]++;
    (void)context;
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    if (call->argument_nodes != 1 || !call->capacity) return "HostFailure";
    if (state.written == MYLANG_SCHEMATIC_OUTPUT) return "HostWorkLimit";
    if (fputc((int)(call->arguments[0].bits & 0xff), state.output) == EOF) return "HostFailure";
    state.written++;
    call->output[0] = (MylangHostNode){"i64", 0, 0};
    call->output_nodes = 1;
    return NULL;
}
/* Only the first located issue survives; later ones describe its consequences. */
static const char *report(void *context, MylangHostCall *call) {
    counts[COUNT_ISSUE]++;
    (void)context;
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    if (call->argument_nodes != 3 || !call->capacity) return "HostFailure";
    if (!state.reported) {
        state.reported = 1;
        FILE *file = fopen(state.issue, "wb");
        if (!file) return "HostFailure";
        fprintf(file, "%lld %lld %lld\n", (long long)(int64_t)call->arguments[0].bits,
                (long long)(int64_t)call->arguments[1].bits, (long long)(int64_t)call->arguments[2].bits);
        if (fclose(file)) return "HostFailure";
    }
    call->output[0] = (MylangHostNode){"i64", 0, 0};
    call->output_nodes = 1;
    return NULL;
}
static const char *one_i64[] = {"i64"}, *two_i64[] = {"i64", "i64"};
static const char *three_i64[] = {"i64", "i64", "i64"}, *one_u8[] = {"u8"};
static const MylangHostBinding declared[] = {
    {"io::circuit_input", NULL, 0, "i64", 32, 32, NULL, circuit_input},
    {"io::pinout_input", NULL, 0, "i64", 32, 32, NULL, pinout_input},
    {"io::interface_input", NULL, 0, "i64", 32, 32, NULL, interface_input},
    {"io::length", one_i64, 1, "i64", 32, 32, NULL, length},
    {"io::byte", two_i64, 2, "u8", 32, 32, NULL, byte},
    {"io::put", one_u8, 1, "i64", 32, 32, NULL, put},
    {"io::issue", three_i64, 3, "i64", 32, 32, NULL, report},
};
static MylangHostBinding bindings[sizeof declared / sizeof *declared];
/* An older guest may omit the named input providers, so the driver names the
   declarations it found and nothing else is registered. */
static size_t selected(const char *names) {
    size_t count = 0;
    for (size_t i = 0; i < sizeof declared / sizeof *declared; ++i) {
        const char *found = strstr(names, declared[i].name);
        size_t width = strlen(declared[i].name);
        if (!found || (found[width] && found[width] != ',')) continue;
        bindings[count++] = declared[i];
    }
    return count;
}
MylangNativeProviders mylang_native_providers(void) {
    const char *output = getenv("MYLANG_SCHEMATIC_OUTPUT");
    const char *names = getenv("MYLANG_SCHEMATIC_DECLARED");
    state.issue = getenv("MYLANG_SCHEMATIC_ISSUE");
    if (!output || !names || !state.issue) unavailable("schematic");
    for (size_t i = 0; i < MYLANG_SCHEMATIC_DOCUMENTS; ++i) {
        char variable[32];
        snprintf(variable, sizeof variable, "MYLANG_SCHEMATIC_INPUT_%zu", i);
        const char *path = getenv(variable);
        if (!path) break;
        load(i, path);
        state.count = i + 1;
    }
    state.output = fopen(output, "wb");
    if (!state.output) unavailable("output");
    if (atexit(dump_counts) || atexit(release)) unavailable("cleanup");
    MylangNativeProviders providers = {0};
    providers.host.bindings = bindings;
    providers.host.count = selected(names);
    providers.host.max_calls = 4000000;
    providers.host.max_work = 4000000;
    return providers;
}
