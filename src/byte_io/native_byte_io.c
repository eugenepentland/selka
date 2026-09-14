/* Trusted raw byte operations for a `mylang-io` guest, compiled into the guest's
   own native executable. All input interpretation still belongs to the guest.
   These callbacks are an authority boundary for guest source, not a sandbox.

   The driver owns publication, so guest output accumulates in a private file it
   reads back only after a clean exit; a trapped or nonzero run publishes nothing.
   Configuration arrives through the environment because a native executable's
   own command line is reserved for capability grants and runtime budgets. */
#define _POSIX_C_SOURCE 200809L
#include "native_providers.h"
#include "native_scoped.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

/* Maximum useful byte payload in one copied host call, matching the guest ABI. */
#define MYLANG_BYTE_IO_BLOCK 256
#define MYLANG_BYTE_IO_SOCKETS 8
#define MYLANG_BYTE_IO_NAMES 1024

/* Borrowed input, the unpublished output file and its remaining byte budget. */
typedef struct {
    unsigned char *input;
    size_t length;
    FILE *output;
    size_t written, limit;
    const char *record, *array;
} MylangByteIo;
static MylangByteIo io;
static MylangScoped scoped;
/* Exactly configured endpoints prevent DNS rebinding and implicit scope growth. */
typedef struct {
    const char *names;
    int sockets[MYLANG_BYTE_IO_SOCKETS];
    size_t count;
} MylangByteNet;
static MylangByteNet net;

static void unavailable(const char *channel) {
    fprintf(stderr, "mylang-io: the %s channel is unavailable\n", channel);
    exit(2);
}
static uint64_t number(const char *name, uint64_t fallback) {
    const char *text = getenv(name);
    if (!text || !*text) return fallback;
    char *end = NULL;
    unsigned long long value = strtoull(text, &end, 10);
    if (!end || *end) unavailable(name);
    return (uint64_t)value;
}
/* Copy the whole driver-supplied input once; the guest indexes it afterwards. */
static void load(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) unavailable("input");
    if (fseek(file, 0, SEEK_END)) unavailable("input");
    long size = ftell(file);
    if (size < 0 || fseek(file, 0, SEEK_SET)) unavailable("input");
    io.input = malloc((size_t)size + 1);
    if (!io.input) unavailable("input");
    if (size && fread(io.input, 1, (size_t)size, file) != (size_t)size) unavailable("input");
    io.length = (size_t)size;
    fclose(file);
}
static void release(void) {
    if (io.output) fclose(io.output);
    io.output = NULL;
    free(io.input);
    io.input = NULL;
    for (size_t i = 0; i < net.count; ++i)
        if (net.sockets[i] >= 0) close(net.sockets[i]);
    net.count = 0;
    mylang_scoped_close(&scoped);
}
static const char *length(void *context, MylangHostCall *call) {
    (void)context;
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    if (!call->capacity) return "ValueCountLimit";
    call->output[0] = (MylangHostNode){"i64", (uint64_t)io.length, 0};
    call->output_nodes = 1;
    return NULL;
}
static const char *byte(void *context, MylangHostCall *call) {
    (void)context;
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    if (call->argument_nodes != 1) return "HostFailure";
    int64_t index = (int64_t)call->arguments[0].bits;
    if (index < 0 || (uint64_t)index >= io.length) return "HostFailure";
    if (!call->capacity) return "ValueCountLimit";
    call->output[0] = (MylangHostNode){"u8", io.input[index], 0};
    call->output_nodes = 1;
    return NULL;
}
static const char *put(void *context, MylangHostCall *call) {
    (void)context;
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    if (call->argument_nodes != 1 || !call->capacity) return "HostFailure";
    if (io.written >= io.limit) return "HostWorkLimit";
    if (fputc((int)(call->arguments[0].bits & 0xff), io.output) == EOF) return "HostFailure";
    io.written++;
    call->output[0] = (MylangHostNode){"i64", 0, 0};
    call->output_nodes = 1;
    return NULL;
}
/* Copied fixed-size blocks report EOF as a short count and zero-pad the rest. */
static const char *read_block(void *context, MylangHostCall *call) {
    (void)context;
    if (call->argument_nodes != 1) return "HostFailure";
    int64_t offset = (int64_t)call->arguments[0].bits;
    if (offset < 0 || (uint64_t)offset > io.length) return "HostFailure";
    size_t count = io.length - (size_t)offset;
    if (count > MYLANG_BYTE_IO_BLOCK) count = MYLANG_BYTE_IO_BLOCK;
    if (!mylang_host_charge(call, 1 + count)) return "HostWorkLimit";
    if (call->capacity < MYLANG_BYTE_IO_BLOCK + 3) return "ValueCountLimit";
    call->output[0] = (MylangHostNode){io.record, 0, 2};
    call->output[1] = (MylangHostNode){io.array, 0, MYLANG_BYTE_IO_BLOCK};
    for (size_t i = 0; i < MYLANG_BYTE_IO_BLOCK; ++i) {
        uint64_t value = i < count ? io.input[(size_t)offset + i] : 0;
        call->output[2 + i] = (MylangHostNode){"u8", value, 0};
    }
    call->output[MYLANG_BYTE_IO_BLOCK + 2] = (MylangHostNode){"i64", (uint64_t)count, 0};
    call->output_nodes = MYLANG_BYTE_IO_BLOCK + 3;
    return NULL;
}
static const char *write_block(void *context, MylangHostCall *call) {
    (void)context;
    if (call->argument_nodes != MYLANG_BYTE_IO_BLOCK + 3 || !call->capacity) return "HostFailure";
    int64_t requested = (int64_t)call->arguments[MYLANG_BYTE_IO_BLOCK + 2].bits;
    if (requested < 0 || requested > MYLANG_BYTE_IO_BLOCK) return "HostFailure";
    size_t count = (size_t)requested;
    size_t room = io.limit > io.written ? io.limit - io.written : 0;
    if (count > room) count = room;
    if (!mylang_host_charge(call, 1 + count)) return "HostWorkLimit";
    for (size_t i = 0; i < count; ++i)
        if (fputc((int)(call->arguments[2 + i].bits & 0xff), io.output) == EOF) return "HostFailure";
    io.written += count;
    call->output[0] = (MylangHostNode){"i64", (uint64_t)count, 0};
    call->output_nodes = 1;
    return NULL;
}
/* An allowlist entry is matched verbatim, so `127.0.0.1:8000` names one peer. */
static int allowed(const char *request, size_t width) {
    for (const char *cursor = net.names; cursor && *cursor;) {
        const char *comma = strchr(cursor, ',');
        size_t part = comma ? (size_t)(comma - cursor) : strlen(cursor);
        if (part == width && !memcmp(cursor, request, width)) return 1;
        if (!comma) break;
        cursor = comma + 1;
    }
    return 0;
}
static int dial(const char *name) {
    const char *colon = strrchr(name, ':');
    if (!colon || colon == name) return -1;
    char host[64];
    size_t width = (size_t)(colon - name);
    if (width >= sizeof host) return -1;
    memcpy(host, name, width);
    host[width] = 0;
    struct sockaddr_in address;
    memset(&address, 0, sizeof address);
    address.sin_family = AF_INET;
    unsigned long port = strtoul(colon + 1, NULL, 10);
    if (!port || port > 65535) return -1;
    address.sin_port = htons((unsigned short)port);
    if (inet_pton(AF_INET, host, &address.sin_addr) != 1) return -1;
    int handle = socket(AF_INET, SOCK_STREAM, 0);
    if (handle < 0) return -1;
    if (connect(handle, (struct sockaddr *)&address, sizeof address)) {
        close(handle);
        return -1;
    }
    return handle;
}
static MylangResourceResult acquire(void *context, const uint8_t *request, size_t width, unsigned permissions) {
    (void)context;
    (void)permissions;
    MylangResourceResult result = {MYLANG_PROVIDER_DENIED, 0};
    char name[128];
    if (width >= sizeof name) return result;
    memcpy(name, request, width);
    name[width] = 0;
    if (!allowed(name, width)) return result;
    if (net.count == MYLANG_BYTE_IO_SOCKETS) {
        result.status = MYLANG_PROVIDER_NO_CAPACITY;
        return result;
    }
    int handle = dial(name);
    if (handle < 0) {
        result.status = MYLANG_PROVIDER_FAILED;
        return result;
    }
    net.sockets[net.count] = handle;
    result.status = MYLANG_PROVIDER_OK;
    result.handle = net.count++;
    return result;
}
static int descriptor(uint64_t handle) {
    return handle < net.count ? net.sockets[handle] : -1;
}
static MylangProviderStatus complete(void *context, uint64_t handle) {
    (void)context;
    int socket_fd = descriptor(handle);
    if (socket_fd < 0) return MYLANG_PROVIDER_FAILED;
    if (shutdown(socket_fd, SHUT_WR)) return MYLANG_PROVIDER_FAILED;
    return MYLANG_PROVIDER_OK;
}
static void discard(void *context, uint64_t handle) {
    (void)context;
    int socket_fd = descriptor(handle);
    if (socket_fd < 0) return;
    close(socket_fd);
    net.sockets[handle] = -1;
}
static MylangResourceRead receive(void *context, uint64_t handle, uint8_t *output, size_t capacity) {
    (void)context;
    MylangResourceRead result = {MYLANG_PROVIDER_FAILED, 0, 0};
    int socket_fd = descriptor(handle);
    if (socket_fd < 0) return result;
    ssize_t got = recv(socket_fd, output, capacity, 0);
    if (got < 0) return result;
    result.status = MYLANG_PROVIDER_OK;
    result.length = (size_t)got;
    result.eof = got == 0;
    return result;
}
static MylangResourceWrite transmit(void *context, uint64_t handle, const uint8_t *input, size_t width) {
    (void)context;
    MylangResourceWrite result = {MYLANG_PROVIDER_FAILED, 0};
    int socket_fd = descriptor(handle);
    if (socket_fd < 0) return result;
    ssize_t sent = send(socket_fd, input, width, 0);
    if (sent < 0) return result;
    result.status = MYLANG_PROVIDER_OK;
    result.length = (size_t)sent;
    return result;
}
static const char *i64_parameter[] = {"i64"}, *u8_parameter[] = {"u8"};
static const char *block_parameter[1];
static MylangHostBinding bindings[] = {
    {"io::length", NULL, 0, "i64", 32, 32, NULL, length},
    {"io::byte", i64_parameter, 1, "u8", 32, 32, NULL, byte},
    {"io::put", u8_parameter, 1, "i64", 32, 32, NULL, put},
    {"io::read_block", i64_parameter, 1, NULL, 32, 32, NULL, read_block},
    {"io::write_block", block_parameter, 1, "i64", 32, 32, NULL, write_block},
};
/* The driver names the copied-block types it has already validated structurally,
   so a guest that declares a differently shaped block never reaches a callback. */
static size_t declared(void) {
    io.record = getenv("MYLANG_BYTE_IO_BLOCK_TYPE");
    io.array = getenv("MYLANG_BYTE_IO_ARRAY_TYPE");
    if (!io.record || !io.array) return 3;
    bindings[3].result = io.record;
    block_parameter[0] = io.record;
    return 5;
}
static void grant(MylangNativeProviders *providers) {
    const char *directory = getenv("MYLANG_BYTE_IO_DIR");
    mylang_scoped_init(&scoped);
    if (directory && *directory) {
        int writable = getenv("MYLANG_BYTE_IO_WRITABLE") != NULL;
        if (!mylang_scoped_grant(&scoped, directory, writable)) unavailable("directory grant");
        providers->filesystem = mylang_scoped_provider(&scoped, writable ? 7u : 5u);
    }
    net.names = getenv("MYLANG_BYTE_IO_ENDPOINTS");
    if (!net.names || !*net.names) return;
    if (strlen(net.names) >= MYLANG_BYTE_IO_NAMES) unavailable("endpoint grant");
    providers->network = (MylangResourceProvider){NULL, 7u, acquire, complete, discard, receive, transmit};
}
MylangNativeProviders mylang_native_providers(void) {
    const char *input = getenv("MYLANG_BYTE_IO_INPUT"), *output = getenv("MYLANG_BYTE_IO_OUTPUT");
    if (!input || !output) unavailable("byte");
    load(input);
    io.output = fopen(output, "wb");
    if (!io.output) unavailable("output");
    io.limit = (size_t)number("MYLANG_BYTE_IO_MAX_OUTPUT", 128u * 1024u * 1024u);
    if (atexit(release)) unavailable("cleanup");
    MylangNativeProviders providers = {0};
    grant(&providers);
    providers.host.bindings = bindings;
    providers.host.count = declared();
    providers.host.max_calls = number("MYLANG_BYTE_IO_MAX_CALLS", 300000000u);
    providers.host.max_work = number("MYLANG_BYTE_IO_MAX_WORK", 300000000u);
    return providers;
}
