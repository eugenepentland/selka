/* Fresh-process copied-value test harness. The parent owns typed JSON conversion. */
#include "native_host.h"
#include "native_providers.h"
#include "native_embed.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TEST_NODE_LIMIT 100000
#define TEST_STRING_LIMIT 4096
static void fail(const char *message) { fputs(message, stderr); fputc('\n', stderr); exit(2); }
static uint64_t number(FILE *input) {
    uint64_t value;
    if (fread(&value, sizeof value, 1, input) != 1) fail("InvalidNativeTestRequest");
    return value;
}
static char *string(FILE *input) {
    uint64_t length = number(input);
    if (length > TEST_STRING_LIMIT) fail("NativeTestStringLimit");
    char *value = malloc((size_t)length + 1);
    if (!value) fail("OutOfMemory");
    if (length && fread(value, 1, (size_t)length, input) != length) fail("InvalidNativeTestRequest");
    if (memchr(value, 0, (size_t)length)) fail("InvalidNativeTestRequest");
    value[length] = 0;
    return value;
}
static void put_number(uint64_t value) {
    if (fwrite(&value, sizeof value, 1, stdout) != 1) fail("NativeTestOutputFailed");
}
static void put_string(const char *value) {
    size_t length = value ? strlen(value) : 0;
    if (length > TEST_STRING_LIMIT) fail("NativeTestStringLimit");
    put_number(length);
    if (length && fwrite(value, 1, length, stdout) != length) fail("NativeTestOutputFailed");
}
static void result(const MylangCodecResult *out, const MylangWireNode *nodes) {
    const MylangRunResult *run = &out->value.execution;
    put_number(UINT64_C(0x3154534554594c4d));
    put_number((uint64_t)run->status); put_number(run->steps);
    put_number(out->value.node_count); put_number(run->frame_count); put_number(run->omitted_frames);
    put_string(run->code); put_string(out->domain); put_number((uint64_t)out->rejected);
    if (run->frame_count > 16 || out->value.node_count > TEST_NODE_LIMIT) fail("InvalidNativeTestResponse");
    for (size_t i = 0; i < run->frame_count; ++i) {
        put_string(run->frames[i].function); put_string(run->frames[i].path);
        put_number(run->frames[i].line); put_number(run->frames[i].column);
    }
    for (size_t i = 0; i < out->value.node_count; ++i) {
        put_string(nodes[i].type); put_number(nodes[i].bits); put_number(nodes[i].children);
    }
}
int main(int argc, char **argv) {
    if (argc != 3) fail("InvalidNativeTestArguments");
    FILE *request = fopen(argv[2], "rb");
    if (!request) fail("NativeTestRequestUnavailable");
    if (number(request) != UINT64_C(0x3154534554594c4d)) fail("InvalidNativeTestRequest");
    MylangCodecOptions options = {0};
    options.run.max_steps = number(request); options.run.max_frames = number(request); options.max_calls = number(request);
    char *name = string(request);
    uint64_t count = number(request);
    if (count > TEST_NODE_LIMIT) fail("NativeTestNodeLimit");
    MylangWireNode *inputs = calloc(count ? (size_t)count : 1, sizeof *inputs);
    MylangWireNode *outputs = calloc(TEST_NODE_LIMIT, sizeof *outputs);
    if (!inputs || !outputs) fail("OutOfMemory");
    for (size_t i = 0; i < count; ++i) {
        inputs[i].type = string(request); inputs[i].bits = number(request); inputs[i].children = (size_t)number(request);
    }
    if (fgetc(request) != EOF) fail("InvalidNativeTestRequest");
    fclose(request);
    void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!library) fail(dlerror());
    typedef int (*Invoke)(const char *, const MylangWireNode *, size_t, MylangWireNode *, size_t, const MylangCodecOptions *, MylangCodecResult *);
    void *symbol = dlsym(library, "mylang_native_call_codecs_v1");
    if (!symbol) fail("NativeTestAbiUnavailable");
    Invoke invoke;
    _Static_assert(sizeof invoke == sizeof symbol, "POSIX native function pointer ABI");
    memcpy(&invoke, &symbol, sizeof invoke);
    MylangCodecResult out;
    invoke(name, inputs, (size_t)count, outputs, TEST_NODE_LIMIT, &options, &out);
    result(&out, outputs);
    for (size_t i = 0; i < count; ++i) free((void *)inputs[i].type);
    free(inputs); free(outputs); free(name); dlclose(library);
    return fflush(stdout) == 0 ? 0 : 2;
}
