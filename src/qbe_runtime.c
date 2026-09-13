/* Separately compiled scalar runtime. Keep it independent of declaration order. */
#include "qbe_runtime.h"
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <float.h>
#include <fenv.h>
#if defined(__FAST_MATH__) || FLT_RADIX != 2 || DBL_MANT_DIG != 53 || DBL_MAX_EXP != 1024
#error "mylang binary64 requires strict IEEE binary64 arithmetic"
#endif

typedef __int128 Wide;
typedef unsigned __int128 UnsignedWide;
typedef MylQbeContext Context;
_Static_assert(offsetof(Context, steps) == 0, "QBE context steps ABI");
_Static_assert(offsetof(Context, max_steps) == 16, "QBE context step limit ABI");
_Static_assert(offsetof(Context, active_frame) == 48, "QBE context active frame ABI");
_Static_assert(offsetof(MylQbeActiveFrame, position) == 8, "QBE frame position ABI");
static uint64_t fail(void *context, const char *code) {
    Context *ctx = context;
    if (!ctx->trap) {
        ctx->trap = code;
        for (uint64_t i = ctx->frames; i && ctx->trace_count < 16; --i) {
            if (!ctx->frame_data) break;
            MylQbeActiveFrame frame = ctx->frame_data[i-1];
            if (!frame.function || frame.position >= frame.function->count) continue;
            MylQbeLocation at = frame.function->locations[frame.position];
            ctx->trace[ctx->trace_count++] = (MylQbeTrace){frame.function->name, at.path, at.line, at.column};
        }
        ctx->omitted_frames = ctx->frames > ctx->trace_count ? ctx->frames-ctx->trace_count : 0;
    }
    return 0;
}
void myl_qbe_fail(void *context, const char *code) { fail(context, code); }
void myl_qbe_fail_equality(void *context, int status) { fail(context, status == -2 ? "CapacityLimit" : "OutOfMemory"); }
uint64_t myl_qbe_failed(void *context) {
    return ((Context *)context)->trap != NULL;
}
void *myl_qbe_root_mark(void *context) { return ((Context *)context)->heap.roots; }
void myl_qbe_root_restore(void *context, void *mark) { ((Context *)context)->heap.roots = mark; }
void myl_qbe_fail_capability(void *context) { fail(context, "R_CAPABILITY"); }
void myl_qbe_fail_slice(void *context) { fail(context, "R_SLICE_BOUNDS"); }
void myl_qbe_fail_text_bounds(void *context) { fail(context, "R_TEXT_BOUNDS"); }
void myl_qbe_fail_missing_key(void *context) { fail(context, "R_MISSING_KEY"); }
void myl_qbe_fail_empty_separator(void *context) { fail(context, "R_EMPTY_SEPARATOR"); }
void myl_qbe_fail_buffer_bounds(void *context) { fail(context, "R_BUFFER_BOUNDS"); }
void myl_qbe_fail_list_bounds(void *context) { fail(context, "R_LIST_BOUNDS"); }
void myl_qbe_fail_list_capacity(void *context) { fail(context, "R_LIST_CAPACITY"); }
void myl_qbe_fail_allocation(void *context) { fail(context, "OutOfMemory"); }
void myl_qbe_fail_iteration(void *context) { fail(context, "R_LIST_ITERATION_MUTATION"); }
void myl_qbe_fail_bounds(void *context) {
    fail(context, "R_INDEX_BOUNDS");
}
myl_native_heap *myl_qbe_heap(void *context) {
    return &((Context *)context)->heap;
}
void myl_qbe_fail_step(void *context) {
    fail(context, "R_STEP_LIMIT");
}
void myl_qbe_fail_overflow(void *context) {
    fail(context, "R_OVERFLOW");
}
static Wide decode(uint64_t value, uint64_t is_signed) {
    int64_t signed_value;
    memcpy(&signed_value, &value, sizeof signed_value);
    return is_signed ? (Wide)signed_value : (Wide)value;
}
static Wide modulus(void *context, uint64_t width) {
    if (!width || width > 64) return fail(context, "R_INTERNAL");
    return (Wide)1 << width;
}
static uint64_t checked(void *context, Wide value, uint64_t is_signed, uint64_t width) {
    Wide mod = modulus(context, width), maximum = (mod >> !!is_signed) - 1;
    Wide minimum = is_signed ? -(mod >> 1) : 0;
    if (value < minimum || value > maximum) return fail(context, "R_OVERFLOW");
    return (uint64_t)value;
}
uint64_t myl_qbe_int_cast(void *context, uint64_t from_signed, uint64_t to_signed, uint64_t width, uint64_t value) {
    return checked(context, decode(value, from_signed), to_signed, width);
}
uint64_t myl_qbe_int_neg(void *context, uint64_t is_signed, uint64_t width, uint64_t value) {
    return checked(context, -decode(value, is_signed), is_signed, width);
}
uint64_t myl_qbe_int_binary(void *context, uint64_t op, uint64_t is_signed, uint64_t width, uint64_t left, uint64_t right) {
    Wide a = decode(left, is_signed), b = decode(right, is_signed), result = 0;
    Wide mod = modulus(context, width), maximum = (mod >> !!is_signed) - 1;
    Wide minimum = is_signed ? -(mod >> 1) : 0;
    UnsignedWide mask = (UnsignedWide)mod - 1, x = (UnsignedWide)a & mask, y = (UnsignedWide)b & mask, raw = 0;
    switch (op) {
        case 0: result = a + b; break;
        case 1: result = a - b; break;
        case 2: if (__builtin_mul_overflow(a, b, &result)) return fail(context, "R_OVERFLOW"); break;
        case 3: case 4: case 5: case 6: {
            if (!b) return fail(context, "R_DIVISION_BY_ZERO");
            Wide q = a / b, r = a % b;
            if (op >= 5 && r && ((r < 0) != (b < 0))) { --q; r += b; }
            result = (op == 3 || op == 5) ? q : r;
            break;
        }
        case 7: return !!a && !!b;
        case 8: return !!a || !!b;
        case 9: return a == b;
        case 10: return a != b;
        case 11: return a < b;
        case 12: return a <= b;
        case 13: return a > b;
        case 14: return a >= b;
        case 15: raw = x & y; goto wrapping;
        case 16: raw = x | y; goto wrapping;
        case 17: raw = x ^ y; goto wrapping;
        case 18: case 19:
            if (b < 0 || b >= (Wide)width) return fail(context, "R_INVALID_SHIFT");
            if (op == 18) { raw = x << (unsigned)b; goto wrapping; }
            result = a < 0 ? -1 - ((-1 - a) / ((Wide)1 << (unsigned)b)) : a / ((Wide)1 << (unsigned)b);
            break;
        case 20: raw = x + y; goto wrapping;
        case 21: raw = x - y; goto wrapping;
        case 22: raw = x * y; goto wrapping;
        case 23: case 24: case 25:
            if (op == 23) result = a + b;
            else if (op == 24) result = a - b;
            else if (__builtin_mul_overflow(a, b, &result)) return (uint64_t)maximum;
            return (uint64_t)(result < minimum ? minimum : result > maximum ? maximum : result);
        default: return fail(context, "R_INTERNAL");
    }
    return checked(context, result, is_signed, width);
wrapping:
    result = (Wide)(raw & mask);
    return (uint64_t)(is_signed && result > maximum ? result - mod : result);
}
static double float_value(uint64_t bits) {
    double value;
    memcpy(&value, &bits, sizeof value);
    return value;
}
static uint64_t float_bits(double value) {
    uint64_t bits;
    if (isnan(value)) return UINT64_C(0x7ff8000000000000);
    memcpy(&bits, &value, sizeof bits);
    return bits;
}
static uint64_t float_environment(void *context) {
    if (fegetround() != FE_TONEAREST) return fail(context, "R_FLOAT_ENVIRONMENT");
    volatile double normal = DBL_MIN, half = 0.5;
    volatile double tiny = float_value(1), one = 1.0;
    if (float_bits(normal * half) != UINT64_C(0x0008000000000000) || float_bits(tiny * one) != 1) return fail(context, "R_FLOAT_ENVIRONMENT");
    return 1;
}
void myl_qbe_float_check(void *context) {
    (void)float_environment(context);
}
uint64_t myl_qbe_float_binary(void *context, uint64_t op, uint64_t left, uint64_t right) {
    if (!float_environment(context)) return 0;
    double a = float_value(left), b = float_value(right);
    switch (op) {
        case 26: return float_bits(a + b);
        case 27: return float_bits(a - b);
        case 28: return float_bits(a * b);
        case 29: return float_bits(a / b);
        case 30: return a == b;
        case 31: return a < b;
        case 32: return a <= b;
        default: return fail(context, "R_INTERNAL");
    }
}
uint64_t myl_qbe_float_unary(void *context, uint64_t op, uint64_t input) {
    if (!float_environment(context)) return 0;
    double a = float_value(input);
    switch (op) {
        case 2: return float_bits(sqrt(a));
        case 3: return float_bits(floor(a));
        case 4: return float_bits(ceil(a));
        case 5: return float_bits(trunc(a));
        case 6: return float_bits(fabs(a));
        case 7: return float_bits(-a);
        case 8: return float_bits((double)input);
        case 9:
            a = trunc(a);
            if (!isfinite(a) || a < 0 || a >= 18446744073709551616.0) return fail(context, "R_FLOAT_CONVERSION");
            return (uint64_t)a;
        case 10: return float_bits((double)decode(input, 1));
        case 11:
            a = trunc(a);
            if (!isfinite(a) || a < -9223372036854775808.0 || a >= 9223372036854775808.0) return fail(context, "R_FLOAT_CONVERSION");
            return (uint64_t)(int64_t)a;
        default: return fail(context, "R_INTERNAL");
    }
}
typedef struct NativeFrameAllocation {
    struct NativeFrameAllocation *previous, *next;
    max_align_t alignment;
} NativeFrameAllocation;
void *myl_qbe_frame_allocate(void *context, uint64_t bytes) {
    Context *ctx=context;
    if (bytes>SIZE_MAX-sizeof(NativeFrameAllocation)) { fail(context,"OutOfMemory");return NULL; }
    NativeFrameAllocation *allocation=calloc(1,sizeof *allocation+(size_t)bytes);
    if (!allocation) { fail(context,"OutOfMemory");return NULL; }
    allocation->next=ctx->frame_allocations;
    if (allocation->next) allocation->next->previous=allocation;
    ctx->frame_allocations=allocation;
    return allocation+1;
}
void myl_qbe_frame_release(void *context, void *payload) {
    if (!payload) return;
    Context *ctx=context;
    NativeFrameAllocation *allocation=(NativeFrameAllocation *)payload-1;
    if (allocation->previous) allocation->previous->next=allocation->next;
    else ctx->frame_allocations=allocation->next;
    if (allocation->next) allocation->next->previous=allocation->previous;
    free(allocation);
}
void myl_qbe_enter(void *context) {
    Context *ctx = context;
    /* The logical budget is independent of the execution stack guard. */
    if (ctx->frames == ctx->max_frames) { fail(context, "R_FRAME_LIMIT"); return; }
    if (ctx->frame_data) {
        ctx->active_frame = &ctx->frame_data[ctx->frames];
        *ctx->active_frame = (MylQbeActiveFrame){0};
    }
    ++ctx->frames;
}
void myl_qbe_leave(void *context) {
    Context *ctx = context;
    if (!ctx->frames) { fail(context, "R_INTERNAL"); return; }
    if (ctx->active_frame) ctx->native_stack_bytes -= ctx->active_frame->native_bytes;
    --ctx->frames;
    ctx->active_frame = ctx->frames && ctx->frame_data ? &ctx->frame_data[ctx->frames-1] : NULL;
}
void myl_qbe_step(void *context) {
    Context *ctx = context;
    if (ctx->steps == ctx->max_steps) { fail(context, "R_STEP_LIMIT"); return; }
    ++ctx->steps;
}
void myl_qbe_enter_at_sized(void *context, const MylQbeFunction *function, uint64_t bytes) {
    Context *ctx=context;
    uint64_t limit=ctx->native_stack_limit ? ctx->native_stack_limit:1048576;
    unsigned char position;
    if (ctx->native_stack_bottom && (uintptr_t)&position<ctx->native_stack_bottom+65536) { fail(context,"R_FRAME_LIMIT");return; }
    if (bytes>limit || ctx->native_stack_bytes>limit-bytes) { fail(context,"R_FRAME_LIMIT");return; }
    myl_qbe_enter_at(context,function);
    if (!ctx->trap) {
        ctx->native_stack_bytes+=bytes;
        if (ctx->active_frame) ctx->active_frame->native_bytes=bytes;
    }
}
void myl_qbe_enter_at(void *context, const MylQbeFunction *function) {
    myl_qbe_enter(context);
    Context *ctx = context;
    if (!ctx->trap && ctx->active_frame) ctx->active_frame->function = function;
}
void myl_qbe_step_at(void *context, uint64_t position) {
    Context *ctx = context;
    if (ctx->active_frame) ctx->active_frame->position = position;
    myl_qbe_step(context);
}
static uint64_t budget(void *context, const char *text) {
    uint64_t value = 0;
    if (!*text) return fail(context, "InvalidBudget");
    for (; *text; ++text) {
        if (*text < '0' || *text > '9' || value > (UINT64_MAX - (unsigned)(*text - '0')) / 10) return fail(context, "InvalidBudget");
        value = value * 10 + (unsigned)(*text - '0');
    }
    if (!value) return fail(context, "InvalidBudget");
    return value;
}
int mylang_qbe_run_options(uint64_t (*entry)(void *), int argc, char **argv) {
    return mylang_qbe_run_providers(entry, argc, argv, NULL);
}
int mylang_qbe_run_providers(uint64_t (*entry)(void *), int argc, char **argv, const struct MylangNativeProvidersTag *providers) {
    Context context = {.max_steps=10000000, .max_frames=1024};
    int saw_steps = 0, saw_frames = 0, stress = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strncmp(argv[i], "--max-steps=", 12) && !saw_steps++) context.max_steps = budget(&context, argv[i] + 12);
        else if (!strncmp(argv[i], "--max-frames=", 13) && !saw_frames++) context.max_frames = budget(&context, argv[i] + 13);
        else if (!strcmp(argv[i], "--gc-stress") && !stress) stress = 1;
        else fail(&context, "InvalidBudget");
    }
    if (context.trap) {
        fprintf(stderr, "%s: QBE runtime failure\n", context.trap);
        return 2;
    }
    MylQbeResult result;
    if (mylang_qbe_execute_providers(entry, context.max_steps, context.max_frames, stress, providers, &result)) {
        if (result.trace_count) {
            const MylQbeTrace *at=&result.trace[0];
            fprintf(stderr,"%s:%" PRIu64 ":%" PRIu64 ": error[%s]: native execution failed\n",at->path,at->line,at->column,result.code);
        } else fprintf(stderr, "%s: QBE runtime failure\n", result.code);
        for (uint64_t i=0; i<result.trace_count; ++i) {
            MylQbeTrace frame = result.trace[i];
            fprintf(stderr, "  in %s at %s:%" PRIu64 ":%" PRIu64 "\n", frame.function, frame.path, frame.line, frame.column);
        }
        return strncmp(result.code,"R_",2) ? 2:1;
    }
    int64_t value;
    memcpy(&value, &result.value, sizeof value);
    printf("%" PRId64 "\n", value);
    return 0;
}
int mylang_qbe_execute(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, MylQbeResult *result) {
    return mylang_qbe_execute_gc(entry, steps, frames, 0, result);
}
int mylang_qbe_execute_gc(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, int stress, MylQbeResult *result) {
    return mylang_qbe_execute_providers(entry, steps, frames, stress, NULL, result);
}
int mylang_qbe_execute_providers(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, int stress, const struct MylangNativeProvidersTag *providers, MylQbeResult *result) {
    return mylang_qbe_execute_config(entry,steps,frames,stress,providers,NULL,result);
}
int mylang_qbe_execute_config(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, int stress, const struct MylangNativeProvidersTag *providers, void (*initialize)(void *), MylQbeResult *result) {
    *result=(MylQbeResult){0};
    if (!steps || !frames) { result->code="InvalidBudget";return 1; }
    if (frames>SIZE_MAX/sizeof(MylQbeActiveFrame)) { result->code="OutOfMemory";return 1; }
    Context *context=calloc(1,sizeof *context);
    if (!context) { result->code="OutOfMemory";return 1; }
    context->max_steps=steps;context->max_frames=frames;context->providers=providers;
    myl_native_heap_init(&context->heap, SIZE_MAX);
    context->heap.stress = stress;
    context->frame_data = calloc((size_t)frames, sizeof(MylQbeActiveFrame));
    if (!context->frame_data) context->trap = "OutOfMemory";
    if (!context->trap && initialize) initialize(context);
    if (!context->trap) result->value = myl_qbe_on_stack(entry,context);
    if (!context->trap && context->frames != 0) context->trap = "R_INTERNAL";
    result->steps = context->steps;
    result->code = context->trap;
    result->trace_count = context->trace_count;
    result->omitted_frames = context->omitted_frames;
    memcpy(result->trace, context->trace, sizeof result->trace);
    if (context->cleanup) context->cleanup(context);
    while (context->frame_allocations) myl_qbe_frame_release(context,(NativeFrameAllocation *)context->frame_allocations+1);
    free(context->host_state);
    free(context->frame_data);
    myl_native_heap_destroy(&context->heap);
    int failed=context->trap != NULL;
    free(context);
    return failed;
}

int mylang_qbe_run(uint64_t (*entry)(void *)) {
    return mylang_qbe_run_options(entry, 0, NULL);
}
