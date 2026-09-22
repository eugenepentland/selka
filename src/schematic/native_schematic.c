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
#define MYLANG_SCHEMATIC_BLOCK 256u

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
    (void)context;
    return identify(call, 0);
}
static const char *pinout_input(void *context, MylangHostCall *call) {
    (void)context;
    return identify(call, 1);
}
static const char *interface_input(void *context, MylangHostCall *call) {
    (void)context;
    return identify(call, 2);
}
static const char *length(void *context, MylangHostCall *call) {
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
static size_t block_count(int64_t id, int64_t position) {
    if (!known(id) || position < 0 || (uint64_t)position > state.length[id]) return SIZE_MAX;
    size_t count=state.length[id]-(size_t)position;
    return count>MYLANG_SCHEMATIC_BLOCK?MYLANG_SCHEMATIC_BLOCK:count;
}
static const char *read_block(void *context, MylangHostCall *call) {
    (void)context;
    if (call->argument_nodes!=2 || call->capacity<MYLANG_SCHEMATIC_BLOCK+1) return "HostFailure";
    int64_t id=(int64_t)call->arguments[0].bits, position=(int64_t)call->arguments[1].bits;
    size_t count=block_count(id,position);
    if (count==SIZE_MAX) return "HostFailure";
    if (!mylang_host_charge(call,1+count)) return "HostWorkLimit";
    call->output[0]=(MylangHostNode){"[256]u8",0,MYLANG_SCHEMATIC_BLOCK};
    for (size_t i=0;i<MYLANG_SCHEMATIC_BLOCK;i++)
        call->output[i+1]=(MylangHostNode){"u8",i<count?state.bytes[id][(size_t)position+i]:0,0};
    call->output_nodes=MYLANG_SCHEMATIC_BLOCK+1;
    return NULL;
}
static const char *read_block_packed(void *context, MylangHostPackedCall *call) {
    (void)context;
    if (call->argument_count!=2 || call->arguments[0].size!=8 || call->arguments[1].size!=8 || call->output.size!=MYLANG_SCHEMATIC_BLOCK) return "HostFailure";
    int64_t id,position; memcpy(&id,call->arguments[0].bytes,8); memcpy(&position,call->arguments[1].bytes,8);
    size_t count=block_count(id,position);
    if (count==SIZE_MAX) return "HostFailure";
    if (!mylang_host_packed_charge(call,1+count)) return "HostWorkLimit";
    memset(call->output.bytes,0,MYLANG_SCHEMATIC_BLOCK);
    memcpy(call->output.bytes,state.bytes[id]+(size_t)position,count);
    call->output_written=MYLANG_SCHEMATIC_BLOCK;
    return NULL;
}
/* A declaration carrying `bytes` has no node-bridge form, so the checked
   fallback exists only to satisfy the binding contract and always refuses. */
static const char *payload_only(void *context, MylangHostCall *call) {
    (void)context; (void)call;
    return "HostFailure";
}
/* One whole document as an owned payload: the guest receives its own immutable
   copy, and the provider keeps the octets it loaded at start-up. */
static const char *read_document_packed(void *context, MylangHostPackedCall *call) {
    (void)context;
    if (call->argument_count!=1 || call->arguments[0].size!=8 || call->output.size || call->output.bytes) return "HostFailure";
    int64_t id; memcpy(&id,call->arguments[0].bytes,8);
    if (!known(id)) return "HostFailure";
    size_t count=state.length[id];
    if (!mylang_host_packed_charge(call,1+count)) return "HostWorkLimit";
    call->output.bytes=state.bytes[id];
    call->output.size=count;
    call->output_written=count;
    return NULL;
}
/* One whole rendered payload. The output limit and the byte work charge are
   applied before any octet is written, exactly as for a block write. */
static const char *write_bytes_packed(void *context, MylangHostPackedCall *call) {
    (void)context;
    if (call->argument_count!=1 || call->output.size!=8) return "HostFailure";
    size_t count=call->arguments[0].size;
    if (count>MYLANG_SCHEMATIC_OUTPUT-state.written) return "HostWorkLimit";
    if (!mylang_host_packed_charge(call,1+count)) return "HostWorkLimit";
    if (count && fwrite(call->arguments[0].bytes,1,count,state.output)!=count) return "HostFailure";
    state.written+=count;
    int64_t result=0; memcpy(call->output.bytes,&result,8); call->output_written=8;
    return NULL;
}
static const char *write_block(void *context, MylangHostCall *call) {
    (void)context;
    if (call->argument_nodes!=MYLANG_SCHEMATIC_BLOCK+2 || !call->capacity || call->arguments[0].children!=MYLANG_SCHEMATIC_BLOCK) return "HostFailure";
    int64_t requested=(int64_t)call->arguments[MYLANG_SCHEMATIC_BLOCK+1].bits;
    if (requested<0 || requested>MYLANG_SCHEMATIC_BLOCK || (size_t)requested>MYLANG_SCHEMATIC_OUTPUT-state.written) return "HostWorkLimit";
    size_t count=(size_t)requested;
    if (!mylang_host_charge(call,1+count)) return "HostWorkLimit";
    unsigned char bytes[MYLANG_SCHEMATIC_BLOCK];
    for (size_t i=0;i<count;i++) bytes[i]=(unsigned char)call->arguments[i+1].bits;
    if (count && fwrite(bytes,1,count,state.output)!=count) return "HostFailure";
    state.written+=count;
    call->output[0]=(MylangHostNode){"i64",0,0}; call->output_nodes=1;
    return NULL;
}
static const char *write_block_packed(void *context, MylangHostPackedCall *call) {
    (void)context;
    if (call->argument_count!=2 || call->arguments[0].size!=MYLANG_SCHEMATIC_BLOCK || call->arguments[1].size!=8 || call->output.size!=8) return "HostFailure";
    int64_t requested; memcpy(&requested,call->arguments[1].bytes,8);
    if (requested<0 || requested>MYLANG_SCHEMATIC_BLOCK || (size_t)requested>MYLANG_SCHEMATIC_OUTPUT-state.written) return "HostWorkLimit";
    size_t count=(size_t)requested;
    if (!mylang_host_packed_charge(call,1+count)) return "HostWorkLimit";
    if (count && fwrite(call->arguments[0].bytes,1,count,state.output)!=count) return "HostFailure";
    state.written+=count;
    int64_t result=0; memcpy(call->output.bytes,&result,8); call->output_written=8;
    return NULL;
}
static const char *finish(void *context, MylangHostCall *call) {
    (void)context;
    if (call->argument_nodes || !call->capacity) return "HostFailure";
    if (!mylang_host_charge(call,1)) return "HostWorkLimit";
    if (fflush(state.output)) return "HostFailure";
    call->output[0]=(MylangHostNode){"i64",0,0}; call->output_nodes=1;
    return NULL;
}
static const char *output_limit(void *context, MylangHostCall *call) {
    (void)context;
    if (call->argument_nodes || !call->capacity) return "HostFailure";
    if (!mylang_host_charge(call,1)) return "HostWorkLimit";
    return "HostWorkLimit";
}
/* Only the first located issue survives; later ones describe its consequences. */
static const char *report(void *context, MylangHostCall *call) {
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
static const char *block_and_count[] = {"[256]u8", "i64"};
static const char *one_payload[] = {"bytes"};
static const MylangHostBinding declared[] = {
    {"io::circuit_input", NULL, 0, "i64", 32, 32, NULL, circuit_input, NULL},
    {"io::pinout_input", NULL, 0, "i64", 32, 32, NULL, pinout_input, NULL},
    {"io::interface_input", NULL, 0, "i64", 32, 32, NULL, interface_input, NULL},
    {"io::length", one_i64, 1, "i64", 32, 32, NULL, length, NULL},
    {"io::byte", two_i64, 2, "u8", 32, 32, NULL, byte, NULL},
    {"io::put", one_u8, 1, "i64", 32, 32, NULL, put, NULL},
    {"io::issue", three_i64, 3, "i64", 32, 32, NULL, report, NULL},
    {"io::read_block", two_i64, 2, "[256]u8", 32, 32, NULL, read_block, read_block_packed},
    {"io::write_block", block_and_count, 2, "i64", 32, 32, NULL, write_block, write_block_packed},
    {"io::read_document", one_i64, 1, "bytes", 32, 32, NULL, payload_only, read_document_packed},
    {"io::write_bytes", one_payload, 1, "i64", 32, 32, NULL, payload_only, write_bytes_packed},
    {"io::finish", NULL, 0, "i64", 32, 32, NULL, finish, NULL},
    {"io::output_limit", NULL, 0, "i64", 32, 32, NULL, output_limit, NULL},
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
    if (atexit(release)) unavailable("cleanup");
    MylangNativeProviders providers = {0};
    providers.host.bindings = bindings;
    providers.host.count = selected(names);
    providers.host.max_calls = 4000000;
    providers.host.max_work = 4000000;
    /* One payload never exceeds a whole rendered document's capacity. */
    providers.host.max_payload = MYLANG_SCHEMATIC_OUTPUT;
    return providers;
}
