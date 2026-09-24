#define _POSIX_C_SOURCE 200809L
/* Fresh-process copied-value harness. The parent owns typed JSON conversion.
   A request either performs one copied-value call (tests), samples the same
   call repeatedly with an in-process monotonic clock (benchmarks), or makes
   one copied-value call per input of a batch (property tests). */
#include "native_host.h"
#include "native_providers.h"
#include "native_embed.h"
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define TEST_NODE_LIMIT 100000
#define TEST_STRING_LIMIT 4096
#define TEST_OUTPUT_LIMIT (256u * 1024u)
#define BENCH_BATCH_LIMIT 64
#define TEST_REQUEST_MAGIC UINT64_C(0x3154534554594c4d)
/* "MLYBNCH2"/"MLYBRSP2", one byte per character in little-endian order. */
#define BENCH_REQUEST_MAGIC UINT64_C(0x3248434e42594c4d)
#define BENCH_RESPONSE_MAGIC UINT64_C(0x3250535242594c4d)
/* "MLYPROP1"/"MLYPRSP1"/"MLYPEND1": a property batch request, its response,
   and the trailer that says every input's record was written. */
#define PROPERTY_REQUEST_MAGIC UINT64_C(0x31504f5250594c4d)
#define PROPERTY_RESPONSE_MAGIC UINT64_C(0x3150535250594c4d)
#define PROPERTY_END_MAGIC UINT64_C(0x31444e4550594c4d)
#define PROPERTY_INPUT_LIMIT 4096

typedef int (*Invoke)(const char *, const MylangWireNode *, size_t, MylangWireNode *, size_t, const MylangCodecOptions *, MylangCodecResult *);

/* Set from the optional `--gc-stress` argument; copied into every run's
   options so the runtime collector stress reaches the copied-value call. */
static int stress_flag = 0;

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
/* Captured guest stdout with its exact byte length; NUL-terminated for convenience. */
typedef struct { int saved; FILE *capture; } OutputCapture;
/* Take fd 1 away from the protocol channel for the duration of one guest call.
   A temporary file captures user output when it can be opened; otherwise the
   bytes still leave the protocol alone by going to stderr. */
static OutputCapture capture_stdout(void) {
    OutputCapture state = { -1, NULL };
    fflush(stdout);
    state.capture = tmpfile();
    state.saved = dup(STDOUT_FILENO);
    if (state.saved < 0) {
        if (state.capture) fclose(state.capture);
        state.capture = NULL;
        return state;
    }
    if (state.capture != NULL && dup2(fileno(state.capture), STDOUT_FILENO) >= 0) return state;
    if (state.capture) { fclose(state.capture); state.capture = NULL; }
    if (dup2(STDERR_FILENO, STDOUT_FILENO) < 0) { close(state.saved); state.saved = -1; }
    return state;
}
/* Restore fd 1 and read back what the guest wrote, bounded by TEST_OUTPUT_LIMIT. */
static char *release_stdout(OutputCapture state, size_t *length_out) {
    *length_out = 0;
    fflush(stdout);
    if (state.saved >= 0) { dup2(state.saved, STDOUT_FILENO); close(state.saved); }
    if (state.capture == NULL) return NULL;
    int descriptor = fileno(state.capture);
    off_t size = descriptor >= 0 ? lseek(descriptor, 0, SEEK_END) : -1;
    size_t length = size > 0 ? (size_t)size : 0;
    if (length > TEST_OUTPUT_LIMIT) length = TEST_OUTPUT_LIMIT;
    char *output = calloc(length + 1, 1);
    if (output != NULL && length != 0) {
        ssize_t got = pread(descriptor, output, length, 0);
        if (got < 0 || (size_t)got != length) { free(output); output = NULL; }
    }
    fclose(state.capture);
    if (output == NULL) return NULL;
    output[length] = 0;
    *length_out = length;
    return output;
}
/* Protocol trailer for captured user output; large enough for a whole test's prints. */
static void put_output(const char *bytes, size_t length) {
    if (length > TEST_OUTPUT_LIMIT) length = TEST_OUTPUT_LIMIT;
    put_number(length);
    if (length && fwrite(bytes, 1, length, stdout) != length) fail("NativeTestOutputFailed");
}
/* Benchmark sampling keeps user output off the protocol channel without holding
   an unbounded amount of it: a benchmarked function that prints goes to stderr. */
static int divert_stdout(void) {
    fflush(stdout);
    int saved = dup(STDOUT_FILENO);
    if (saved < 0) return -1;
    if (dup2(STDERR_FILENO, STDOUT_FILENO) < 0) { close(saved); return -1; }
    return saved;
}
static void restore_stdout(int saved) {
    fflush(stdout);
    if (saved >= 0) { dup2(saved, STDOUT_FILENO); close(saved); }
}
static MylangWireNode *read_nodes(FILE *input, uint64_t count) {
    if (count > TEST_NODE_LIMIT) fail("NativeTestNodeLimit");
    MylangWireNode *nodes = calloc(count ? (size_t)count : 1, sizeof *nodes);
    if (!nodes) fail("OutOfMemory");
    for (size_t i = 0; i < count; ++i) {
        nodes[i].type = string(input); nodes[i].bits = number(input); nodes[i].children = (size_t)number(input);
    }
    return nodes;
}
static Invoke load_invoke(void **library_out, const char *library_path) {
    void *library = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
    if (!library) fail(dlerror());
    void *symbol = dlsym(library, "mylang_native_call_codecs_v1");
    if (!symbol) fail("NativeTestAbiUnavailable");
    Invoke invoke;
    _Static_assert(sizeof invoke == sizeof symbol, "POSIX native function pointer ABI");
    memcpy(&invoke, &symbol, sizeof invoke);
    *library_out = library;
    return invoke;
}
/* Run one copied-value call and normalize its status: a nonzero ABI return
   with no guest status recorded is a host failure, while a guest trap keeps
   its own status. Returns 0 exactly when the call produced a value. */
static int call_once(Invoke invoke, const char *name, const MylangWireNode *inputs, size_t count,
                     MylangWireNode *outputs, const MylangCodecOptions *options, MylangCodecResult *out) {
    int rc = invoke(name, inputs, count, outputs, TEST_NODE_LIMIT, options, out);
    if (out->value.execution.status == 0 && rc != 0) out->value.execution.status = 2;
    return out->value.execution.status;
}
/* Status, step count, trap detail and domain identity are shared by both
   response kinds so the parent parses one common header. */
static void put_prefix(const MylangCodecResult *out) {
    const MylangRunResult *run = &out->value.execution;
    put_number((uint64_t)run->status); put_number(run->steps);
    put_number(out->value.node_count); put_number(run->frame_count); put_number(run->omitted_frames);
    put_number(run->trap_detail.version); put_number(run->trap_detail.present);
    put_number((uint64_t)run->trap_detail.index); put_number(run->trap_detail.length);
    put_number((uint64_t)run->trap_detail.left); put_number((uint64_t)run->trap_detail.right);
    put_number(run->trap_detail.width); put_string(run->trap_detail.operation);
    put_string(run->code); put_string(out->domain); put_number((uint64_t)out->rejected);
}
static void put_tail(const MylangCodecResult *out, const MylangWireNode *nodes) {
    const MylangRunResult *run = &out->value.execution;
    if (run->frame_count > 16 || out->value.node_count > TEST_NODE_LIMIT) fail("InvalidNativeTestResponse");
    for (size_t i = 0; i < run->frame_count; ++i) {
        put_string(run->frames[i].function); put_string(run->frames[i].path);
        put_number(run->frames[i].line); put_number(run->frames[i].column);
    }
    for (size_t i = 0; i < out->value.node_count; ++i) {
        put_string(nodes[i].type); put_number(nodes[i].bits); put_number(nodes[i].children);
    }
}
static int finish(void) { return fflush(stdout) == 0 ? 0 : 2; }

static int run_test(FILE *request, const char *library_path) {
    MylangCodecOptions options = {0};
    options.run.max_steps = number(request); options.run.max_frames = number(request); options.max_calls = number(request);
    options.run.stress = (uint64_t)stress_flag;
    char *name = string(request);
    uint64_t count = number(request);
    MylangWireNode *inputs = read_nodes(request, count);
    MylangWireNode *outputs = calloc(TEST_NODE_LIMIT, sizeof *outputs);
    if (!outputs) fail("OutOfMemory");
    if (fgetc(request) != EOF) fail("InvalidNativeTestRequest");
    fclose(request);
    void *library = NULL;
    Invoke invoke = load_invoke(&library, library_path);
    MylangCodecResult out;
    OutputCapture capture = capture_stdout();
    invoke(name, inputs, (size_t)count, outputs, TEST_NODE_LIMIT, &options, &out);
    size_t output_length = 0;
    char *output = release_stdout(capture, &output_length);
    put_number(TEST_REQUEST_MAGIC);
    put_prefix(&out);
    put_tail(&out, outputs);
    put_output(output, output_length);
    free(output);
    for (size_t i = 0; i < count; ++i) free((void *)inputs[i].type);
    free(inputs); free(outputs); free(name); dlclose(library);
    return finish();
}

static uint64_t now_ns(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) fail("NativeBenchClockFailed");
    return (uint64_t)ts.tv_sec * UINT64_C(1000000000) + (uint64_t)ts.tv_nsec;
}
/* Samples are appended after the shared header and value tree: warmup count,
   calibrated iteration count, batch count, then (iterations, duration_ns). */
static void put_bench_result(const MylangCodecResult *out, const MylangWireNode *nodes,
                             uint64_t warmup, uint64_t calibrated, uint64_t batches,
                             const uint64_t *iterations, const uint64_t *durations) {
    put_number(BENCH_RESPONSE_MAGIC);
    put_prefix(out);
    put_tail(out, nodes);
    put_number(warmup); put_number(calibrated); put_number(batches);
    for (uint64_t i = 0; i < batches; ++i) { put_number(iterations[i]); put_number(durations[i]); }
}
/* One timed batch: run `iterations` copied-value calls and return their wall
   duration. A nonzero return or guest status stops the whole sampling run. */
static int time_batch(Invoke invoke, const char *name, const MylangWireNode *inputs, size_t count,
                      MylangWireNode *outputs, const MylangCodecOptions *options, MylangCodecResult *out,
                      uint64_t iterations, uint64_t *duration_out) {
    uint64_t start = now_ns();
    for (uint64_t i = 0; i < iterations; ++i) {
        if (call_once(invoke, name, inputs, count, outputs, options, out) != 0) return 0;
    }
    *duration_out = now_ns() - start;
    return 1;
}

static int run_benchmark(FILE *request, const char *library_path) {
    MylangCodecOptions options = {0};
    options.run.max_steps = number(request); options.run.max_frames = number(request); options.max_calls = number(request);
    options.run.stress = (uint64_t)stress_flag;
    uint64_t warmup = number(request);
    uint64_t batch_count = number(request);
    uint64_t target_ns = number(request);
    uint64_t max_iterations = number(request);
    if (batch_count > BENCH_BATCH_LIMIT || warmup > 1000 || max_iterations == 0) fail("InvalidNativeTestRequest");
    char *name = string(request);
    uint64_t count = number(request);
    MylangWireNode *inputs = read_nodes(request, count);
    MylangWireNode *outputs = calloc(TEST_NODE_LIMIT, sizeof *outputs);
    if (!outputs) fail("OutOfMemory");
    if (fgetc(request) != EOF) fail("InvalidNativeTestRequest");
    fclose(request);
    void *library = NULL;
    Invoke invoke = load_invoke(&library, library_path);
    MylangCodecResult out;
    memset(&out, 0, sizeof out);
    uint64_t iterations[BENCH_BATCH_LIMIT];
    uint64_t durations[BENCH_BATCH_LIMIT];
    uint64_t batches = 0, calibrated = 0;
    int saved_stdout = divert_stdout();
    /* Validate once outside every timed region; a trap reports no samples. */
    if (call_once(invoke, name, inputs, (size_t)count, outputs, &options, &out) == 0) {
        for (uint64_t i = 0; i < warmup; ++i) {
            if (call_once(invoke, name, inputs, (size_t)count, outputs, &options, &out) != 0) break;
        }
    }
    if (out.value.execution.status == 0) {
        calibrated = 1;
        for (;;) {
            uint64_t duration = 0;
            if (!time_batch(invoke, name, inputs, (size_t)count, outputs, &options, &out, calibrated, &duration)) break;
            if (duration >= target_ns || calibrated >= max_iterations) break;
            calibrated = calibrated > max_iterations / 2 ? max_iterations : calibrated * 2;
        }
    }
    if (out.value.execution.status == 0) {
        for (uint64_t b = 0; b < batch_count; ++b) {
            uint64_t duration = 0;
            if (!time_batch(invoke, name, inputs, (size_t)count, outputs, &options, &out, calibrated, &duration)) break;
            iterations[batches] = calibrated; durations[batches] = duration; batches += 1;
        }
    }
    restore_stdout(saved_stdout);
    put_bench_result(&out, outputs, warmup, calibrated, batches, iterations, durations);
    for (size_t i = 0; i < count; ++i) free((void *)inputs[i].type);
    free(inputs); free(outputs); free(name); dlclose(library);
    return finish();
}

/* One copied-value call per input, in one process. Every input's record is
   flushed as soon as it is written, so a child that dies mid-batch (a crash,
   the memory ceiling, the parent's timeout) leaves the records of the inputs
   before the one that killed it, and the parent reruns only from there. Each
   call resets guest state before returning (native_embed.h), so a trap in one
   input does not leak into the next. */
static int run_property(FILE *request, const char *library_path) {
    MylangCodecOptions options = {0};
    options.run.max_steps = number(request); options.run.max_frames = number(request); options.max_calls = number(request);
    options.run.stress = (uint64_t)stress_flag;
    char *name = string(request);
    uint64_t inputs_count = number(request);
    if (inputs_count > PROPERTY_INPUT_LIMIT) fail("InvalidNativeTestRequest");
    MylangWireNode **inputs = calloc(inputs_count ? (size_t)inputs_count : 1, sizeof *inputs);
    uint64_t *counts = calloc(inputs_count ? (size_t)inputs_count : 1, sizeof *counts);
    if (!inputs || !counts) fail("OutOfMemory");
    for (uint64_t i = 0; i < inputs_count; ++i) {
        counts[i] = number(request);
        inputs[i] = read_nodes(request, counts[i]);
    }
    MylangWireNode *outputs = calloc(TEST_NODE_LIMIT, sizeof *outputs);
    if (!outputs) fail("OutOfMemory");
    if (fgetc(request) != EOF) fail("InvalidNativeTestRequest");
    fclose(request);
    void *library = NULL;
    Invoke invoke = load_invoke(&library, library_path);
    put_number(PROPERTY_RESPONSE_MAGIC);
    if (fflush(stdout) != 0) fail("NativeTestOutputFailed");
    for (uint64_t i = 0; i < inputs_count; ++i) {
        MylangCodecResult out;
        memset(&out, 0, sizeof out);
        OutputCapture capture = capture_stdout();
        invoke(name, inputs[i], (size_t)counts[i], outputs, TEST_NODE_LIMIT, &options, &out);
        size_t output_length = 0;
        char *output = release_stdout(capture, &output_length);
        put_number(i);
        put_prefix(&out);
        put_tail(&out, outputs);
        put_output(output, output_length);
        free(output);
        if (fflush(stdout) != 0) fail("NativeTestOutputFailed");
    }
    put_number(PROPERTY_END_MAGIC); put_number(inputs_count);
    for (uint64_t i = 0; i < inputs_count; ++i) {
        for (uint64_t j = 0; j < counts[i]; ++j) free((void *)inputs[i][j].type);
        free(inputs[i]);
    }
    free(inputs); free(counts); free(outputs); free(name); dlclose(library);
    return finish();
}

/* Point the protocol channel (fd 1) at a response file before any byte is
   written, so a parent that runs many children at once reads each answer from
   its own file instead of holding one pipe per child. */
static void respond_to(const char *path) {
    int descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (descriptor < 0) fail("NativeTestResponseUnavailable");
    if (descriptor != STDOUT_FILENO) {
        if (dup2(descriptor, STDOUT_FILENO) < 0) fail("NativeTestResponseUnavailable");
        close(descriptor);
    }
}

int main(int argc, char **argv) {
    if (argc < 3 || argc > 6) fail("InvalidNativeTestArguments");
    for (int index = 3; index < argc; ++index) {
        if (strcmp(argv[index], "--gc-stress") == 0) {
            stress_flag = 1;
        } else if (strcmp(argv[index], "--response") == 0 && index + 1 < argc) {
            respond_to(argv[++index]);
        } else {
            fail("InvalidNativeTestArguments");
        }
    }
    FILE *request = fopen(argv[2], "rb");
    if (!request) fail("NativeTestRequestUnavailable");
    uint64_t magic = number(request);
    if (magic == BENCH_REQUEST_MAGIC) return run_benchmark(request, argv[1]);
    if (magic == PROPERTY_REQUEST_MAGIC) return run_property(request, argv[1]);
    if (magic != TEST_REQUEST_MAGIC) fail("InvalidNativeTestRequest");
    return run_test(request, argv[1]);
}
