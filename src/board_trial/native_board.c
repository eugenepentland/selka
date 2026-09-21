/* Trusted boundary of the board trial, compiled into the guest's own native
   executable: the request bytes, the observation bytes, and the one rectangle
   kernel the validator may ask for. Every board decision still belongs to the
   guest; this file interprets nothing but rectangles.

   The driver owns publication, so observation bytes accumulate in a private file
   it reads back only after a clean exit, and the exact kernel invocation count
   is written beside it at exit so a trapped run still reports what it spent.
   Configuration arrives through the environment because a native executable's
   own command line is reserved for capability grants and runtime budgets. */
#define _POSIX_C_SOURCE 200809L
#include "native_providers.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The fixed request layout the guest's `wire` module decodes. */
#define MYLANG_BOARD_REQUEST 740
/* A status byte plus at most one report; the guest never writes more. */
#define MYLANG_BOARD_OBSERVATION 64
/* Both rectangle axes, matching the trial contract's micrometre bound. */
#define MYLANG_BOARD_BOUND INT64_C(1000000000)

/* The borrowed request, the unpublished observation and the kernel's own count. */
typedef struct {
    unsigned char request[MYLANG_BOARD_REQUEST];
    size_t length, written;
    FILE *output;
    const char *counted;
    uint64_t calls;
    int unavailable;
} MylangBoard;
static MylangBoard board;
/* The driver names the observation capacity it is prepared to read back. */
static size_t observation_limit = MYLANG_BOARD_OBSERVATION;

static void unavailable_channel(const char *channel) {
    fprintf(stderr, "board-trial: the %s channel is unavailable\n", channel);
    exit(2);
}
static uint64_t number(const char *name, uint64_t fallback) {
    const char *text = getenv(name);
    if (!text || !*text) return fallback;
    char *end = NULL;
    unsigned long long value = strtoull(text, &end, 10);
    if (!end || *end) unavailable_channel(name);
    return (uint64_t)value;
}
/* Copy the whole driver-supplied request once; the guest indexes it afterwards. */
static void load(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) unavailable_channel("request");
    board.length = fread(board.request, 1, MYLANG_BOARD_REQUEST, file);
    if (ferror(file) || getc(file) != EOF) unavailable_channel("request");
    fclose(file);
}
/* The count outlives a trapped run, so a failed case still reports what it spent. */
static void release(void) {
    if (board.output) fclose(board.output);
    board.output = NULL;
    if (!board.counted) return;
    FILE *file = fopen(board.counted, "wb");
    board.counted = NULL;
    if (!file) return;
    fprintf(file, "%llu\n", (unsigned long long)board.calls);
    fclose(file);
}
static const char *length(void *context, MylangHostCall *call) {
    (void)context;
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    if (!call->capacity) return "ValueCountLimit";
    call->output[0] = (MylangHostNode){"i64", (uint64_t)board.length, 0};
    call->output_nodes = 1;
    return NULL;
}
static const char *byte(void *context, MylangHostCall *call) {
    (void)context;
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    if (call->argument_nodes != 1 || !call->capacity) return "HostFailure";
    int64_t position = (int64_t)call->arguments[0].bits;
    if (position < 0 || (uint64_t)position >= board.length) return "HostFailure";
    call->output[0] = (MylangHostNode){"u8", board.request[position], 0};
    call->output_nodes = 1;
    return NULL;
}
static const char *put(void *context, MylangHostCall *call) {
    (void)context;
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    if (call->argument_nodes != 1 || !call->capacity) return "HostFailure";
    if (board.written >= observation_limit) return "HostWorkLimit";
    if (fputc((int)(call->arguments[0].bits & 0xff), board.output) == EOF) return "HostFailure";
    board.written++;
    call->output[0] = (MylangHostNode){"i64", 0, 0};
    call->output_nodes = 1;
    return NULL;
}
/* A rectangle arrives as its record node, then four micrometre domains each
   carrying one signed backing value; nothing else is accepted as one. */
static int rectangle(const MylangHostCall *call, size_t *cursor, int64_t axes[4]) {
    if (*cursor >= call->argument_nodes) return 0;
    const MylangHostNode *record = &call->arguments[(*cursor)++];
    if (!record->type || strcmp(record->type, "model::Rect") || record->children != 4) return 0;
    for (size_t i = 0; i < 4; ++i) {
        if (*cursor + 1 >= call->argument_nodes) return 0;
        const MylangHostNode *domain = &call->arguments[(*cursor)++];
        const MylangHostNode *scalar = &call->arguments[(*cursor)++];
        if (!domain->type || strcmp(domain->type, "units::Micrometres") || domain->children != 1) return 0;
        if (!scalar->type || strcmp(scalar->type, "i64") || scalar->children) return 0;
        axes[i] = (int64_t)scalar->bits;
    }
    return 1;
}
/* Reject endpoints before adding them, so the sum below cannot overflow. */
static int axis(int64_t origin, int64_t extent) {
    if (origin < -MYLANG_BOARD_BOUND || origin > MYLANG_BOARD_BOUND) return 0;
    if (extent < 1 || extent > MYLANG_BOARD_BOUND) return 0;
    return origin + extent <= MYLANG_BOARD_BOUND;
}
static int checked(const int64_t axes[4]) {
    return axis(axes[0], axes[2]) && axis(axes[1], axes[3]);
}
static int span(int64_t a, int64_t width, int64_t b, int64_t extent) {
    return a < b + extent && b < a + width;
}
/* One declared result: the case tag of `model::Overlap` and its payload case. */
static const char *decided(MylangHostCall *call, const char *payload, uint64_t outcome, uint64_t tag) {
    if (call->capacity < 2) return "ValueCountLimit";
    call->output[0] = (MylangHostNode){"model::Overlap", outcome, 1};
    call->output[1] = (MylangHostNode){payload, tag, 0};
    call->output_nodes = 2;
    return NULL;
}
static const char *overlap(void *context, MylangHostCall *call) {
    (void)context;
    if (!mylang_host_charge(call, 1)) return "HostWorkLimit";
    board.calls++;
    int64_t first[4], second[4];
    size_t cursor = 0;
    if (!rectangle(call, &cursor, first) || !rectangle(call, &cursor, second)) return "HostFailure";
    if (cursor != call->argument_nodes) return "HostFailure";
    if (!checked(first) || !checked(second)) return decided(call, "model::GeometryFailure", 1, 0);
    if (board.unavailable) return decided(call, "model::GeometryFailure", 1, 1);
    int hit = span(first[0], first[2], second[0], second[2]) && span(first[1], first[3], second[1], second[3]);
    return decided(call, "model::Contact", 0, hit ? 1 : 0);
}
static const char *i64_parameter[] = {"i64"}, *u8_parameter[] = {"u8"};
static const char *rect_parameters[] = {"model::Rect", "model::Rect"};
static const MylangHostBinding bindings[] = {
    {"io::length", NULL, 0, "i64", 32, 32, NULL, length, NULL},
    {"io::byte", i64_parameter, 1, "u8", 32, 32, NULL, byte, NULL},
    {"io::put", u8_parameter, 1, "i64", 32, 32, NULL, put, NULL},
    {"geometry::overlap", rect_parameters, 2, "model::Overlap", 32, 32, NULL, overlap, NULL},
};
MylangNativeProviders mylang_native_providers(void) {
    const char *request = getenv("MYLANG_BOARD_REQUEST");
    const char *observation = getenv("MYLANG_BOARD_OBSERVATION");
    const char *injected = getenv("MYLANG_BOARD_UNAVAILABLE");
    board.counted = getenv("MYLANG_BOARD_CALLS");
    if (!request || !observation || !board.counted) unavailable_channel("board");
    load(request);
    board.output = fopen(observation, "wb");
    if (!board.output) unavailable_channel("observation");
    board.unavailable = injected && *injected == '1';
    observation_limit = (size_t)number("MYLANG_BOARD_MAX_OUTPUT", MYLANG_BOARD_OBSERVATION);
    if (atexit(release)) unavailable_channel("cleanup");
    MylangNativeProviders providers = {0};
    providers.host.bindings = bindings;
    providers.host.count = sizeof bindings / sizeof *bindings;
    providers.host.max_calls = 4000000;
    providers.host.max_work = 4000000;
    return providers;
}
