/* Runtime support for generated scalar C. No bytecode decoder is linked. */
#include <stdint.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
typedef __int128 V;
typedef struct { V *locals; size_t base, target, function, call_site; } Frame;
static V *values;
static size_t nv, cv, nf, cf, site;
static Frame *frames;
static uint64_t steps, max_steps = 10000000, max_frames = 1024;
static const char *const *source_paths;
static const char *const *function_names;
static const size_t *source_lines, *source_columns;
static void cleanup(void) {
    while (nf) free(frames[--nf].locals);
    free(frames); free(values);
    frames = NULL; values = NULL;
}
static void host_failure(const char *message) {
    fprintf(stderr, "mylang: host failure: %s\n", message);
    cleanup(); exit(2);
}
static void trap(const char *code) {
    fprintf(stderr, "%s:%zu:%zu: error[%s]\n", source_paths[site], source_lines[site], source_columns[site], code);
    size_t location = site, shown = 0;
    for (size_t i = nf; i && shown < 16; --i, ++shown) {
        Frame f = frames[i - 1];
        fprintf(stderr, "  at %s (%s:%zu:%zu)\n", function_names[f.function], source_paths[location], source_lines[location], source_columns[location]);
        location = f.call_site;
    }
    if (nf > shown) fprintf(stderr, "  ... %zu frames omitted\n", nf - shown);
    cleanup(); exit(1);
}
static void *grow(void *old, size_t *capacity, size_t needed, size_t size) {
    if (needed <= *capacity) return old;
    if (needed > SIZE_MAX / size) host_failure("OutOfMemory");
    size_t next = *capacity ? *capacity : 8;
    while (next < needed) {
        if (next > SIZE_MAX / 2) { next = needed; break; }
        next *= 2;
    }
    if (next > SIZE_MAX / size) next = needed;
    void *result = realloc(old, next * size);
    if (!result) host_failure("OutOfMemory");
    *capacity = next; return result;
}
static void push(V value) {
    if (nv == SIZE_MAX) host_failure("OutOfMemory");
    values = grow(values, &cv, nv + 1, sizeof(V));
    values[nv++] = value;
}
static V pop(void) {
    if (!nf || nv <= frames[nf - 1].base) host_failure("InternalError");
    return values[--nv];
}
static void enter(size_t function, size_t locals, size_t arguments, size_t target) {
    if (nf >= max_frames) trap("R_FRAME_LIMIT");
    if (arguments > nv || (nf && arguments > nv - frames[nf - 1].base)) host_failure("InternalError");
    if (nf == SIZE_MAX || locals > SIZE_MAX / sizeof(V)) host_failure("OutOfMemory");
    frames = grow(frames, &cf, nf + 1, sizeof(Frame));
    V *storage = calloc(locals ? locals : 1, sizeof(V));
    if (!storage) host_failure("OutOfMemory");
    size_t base = nv - arguments;
    for (size_t i = 0; i < arguments; ++i) storage[i] = values[base + i];
    frames[nf++] = (Frame){storage, base, target, function, site};
    nv = base;
}
static size_t leave(V result) {
    Frame f = frames[--nf];
    free(f.locals); nv = f.base;
    push(result); return f.target;
}
static void tick(size_t location) {
    site = location;
    if (steps == max_steps) trap("R_STEP_LIMIT");
    ++steps;
}
static V checked(V value, V minimum, V maximum) {
    if (value < minimum || value > maximum) trap("R_OVERFLOW");
    return value;
}
static V arithmetic(int operation, V a, V b, V minimum, V maximum) {
    V result = 0;
    int overflow = 0;
    switch (operation) {
        case 0: overflow = __builtin_add_overflow(a, b, &result); break;
        case 1: overflow = __builtin_sub_overflow(a, b, &result); break;
        case 2: overflow = __builtin_mul_overflow(a, b, &result); break;
        case 3: if (!b) trap("R_DIVISION_BY_ZERO"); result = a / b; break;
        case 4: if (!b) trap("R_DIVISION_BY_ZERO"); result = a % b; break;
        default: host_failure("InternalError");
    }
    if (overflow) trap("R_OVERFLOW");
    return checked(result, minimum, maximum);
}
static uint64_t budget(const char *text) {
    uint64_t result = 0;
    if (!*text) host_failure("InvalidBudget");
    for (; *text; ++text) {
        if (*text < '0' || *text > '9' || result > (UINT64_MAX - (unsigned)(*text - '0')) / 10) host_failure("InvalidBudget");
        result = result * 10 + (unsigned)(*text - '0');
    }
    if (!result) host_failure("InvalidBudget");
    return result;
}
static void options(int argc, char **argv) {
    int saw_steps = 0, saw_frames = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strncmp(argv[i], "--max-steps=", 12) && !saw_steps++) max_steps = budget(argv[i] + 12);
        else if (!strncmp(argv[i], "--max-frames=", 13) && !saw_frames++) max_frames = budget(argv[i] + 13);
        else host_failure("InvalidBudget");
    }
}
