#define _POSIX_C_SOURCE 200809L
/* Separately compiled scalar runtime. Keep it independent of declaration order. */
#include "qbe_runtime.h"
#include "native_collections.h"
#include "native_text.h"
#include <inttypes.h>
#include <setjmp.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <float.h>
#include <fenv.h>
#include <time.h>
#include <unistd.h>
#if defined(__FAST_MATH__) || FLT_RADIX != 2 || DBL_MANT_DIG != 53 || DBL_MAX_EXP != 1024
#error "mylang binary64 requires strict IEEE binary64 arithmetic"
#endif

typedef __int128 Wide;
typedef unsigned __int128 UnsignedWide;
typedef MylQbeContext Context;
/* Set only by an executable entry that runs one guest program and then returns
 * from `main` (see `myl_qbe_exit_without_sweep`). The exit sweep is a heap check
 * and a courtesy: no guest can observe the freed objects, so a process that is
 * about to release the whole address space skips it. */
static int exit_without_sweep;
void myl_qbe_exit_without_sweep(void) { exit_without_sweep = 1; }
static int execute_config_args(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, int stress, const struct MylangNativeProvidersTag *providers, void (*initialize)(void *), int guest_argc, char **guest_argv, MylQbeResult *result);
_Static_assert(offsetof(Context, steps) == 0, "QBE context steps ABI");
_Static_assert(offsetof(Context, frames) == 8, "QBE context frame count ABI");
_Static_assert(offsetof(Context, max_steps) == 16, "QBE context step limit ABI");
_Static_assert(offsetof(Context, trap) == 32, "QBE context trap ABI");
_Static_assert(offsetof(Context, active_frame) == 48, "QBE context active frame ABI");
_Static_assert(offsetof(Context, frame_limit) == 56, "QBE context frame limit ABI");
_Static_assert(offsetof(Context, frame_floor) == 64, "QBE context frame floor ABI");
_Static_assert(offsetof(MylQbeActiveFrame, function) == 8, "QBE frame function ABI");
_Static_assert(offsetof(MylQbeActiveFrame, position) == 16, "QBE frame position ABI");
/* Generated code now links the root chain itself, so this offset is an ABI:
   mirror any change here in `heap_roots_offset` in src/qbe.zig. */
_Static_assert(offsetof(myl_native_heap, roots) == 16, "QBE heap roots ABI");
/* A root record is four words, and generated code stores the value word at
   offset 24; mirror any change here in `pushRoot` and `allocateStorage`. */
_Static_assert(offsetof(myl_native_root, value) == 24, "QBE root value ABI");
_Static_assert(sizeof(myl_native_root) == 32, "QBE root record ABI");
/* Stable trap for a guest that outgrew its byte ceiling. It is a runtime trap
   like any other R_ code, so it exits 1 rather than reporting a host defect. */
static const char *const memory_budget_code = "R_MEMORY_BUDGET";
/* A budget trap tells the reader which flag imposes it, because a bounded run
   is a deliberate decision, not a program defect. */
static const char *describe(const char *code) {
    if (!strcmp(code, memory_budget_code)) return "memory budget exhausted";
    if (!strcmp(code, "R_STEP_LIMIT")) return "instruction budget exhausted; raise it with --max-steps=N";
    if (!strcmp(code, "R_NO_STEP_ACCOUNTING")) return "this build omits instruction-budget accounting";
    if (!strcmp(code, "R_NO_FRAME_ACCOUNTING")) return "this build omits call-depth accounting";
    if (!strcmp(code, "R_FRAME_LIMIT")) return "call-depth budget exhausted; raise it with --max-frames=N";
    return strncmp(code, "R_", 2) ? "QBE runtime failure" : "native execution failed";
}
/* Wall-clock guard for otherwise unbounded execution. The timer is monotonic,
   so a system clock change cannot move it; when it fires the handler writes a
   stable trap-like diagnostic and leaves via _exit, because only async-signal-
   safe calls are legal there. `--timeout=SECONDS` arms it; no flag leaves the
   program without an elapsed-time ceiling. */
static timer_t timeout_timer;
static void on_timeout(int signal_number) {
    (void)signal_number;
    static const char message[] = "R_TIMEOUT: wall-clock budget exhausted; raise it with --timeout=SECONDS\n";
    ssize_t ignored = write(STDERR_FILENO, message, sizeof message - 1);
    (void)ignored;
    _exit(1);
}
/* Arm the monotonic timer for `seconds`; zero (no flag) arms nothing. Returns 0
   when the process cannot install the handler or the timer. */
static int arm_timeout(uint64_t seconds) {
    if (!seconds) return 1;
    struct sigaction action = {0};
    action.sa_handler = on_timeout;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGALRM, &action, NULL)) return 0;
    struct sigevent event = {0};
    event.sigev_notify = SIGEV_SIGNAL;
    event.sigev_signo = SIGALRM;
    if (timer_create(CLOCK_MONOTONIC, &event, &timeout_timer)) return 0;
    struct itimerspec spec = {0};
    spec.it_value.tv_sec = (time_t)seconds;
    return timer_settime(timeout_timer, 0, &spec, NULL) == 0;
}
/* Append one formatted fragment; returns 0 when the bounded buffer would
   truncate. The caller keeps the buffer NUL terminated on success. */
static int append(char *out, size_t size, size_t *used, const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int written = vsnprintf(out + *used, size - *used, format, arguments);
    va_end(arguments);
    if (written < 0 || (size_t)written >= size - *used) return 0;
    *used += (size_t)written;
    return 1;
}
/* Human-readable suffix rendered from the same detail the JSON record carries.
   Writes nothing (0) when no reportable fields are present. */
static size_t detail_text(const MylQbeTrapDetail *detail, char *out, size_t size) {
    if (size == 0) return 0;
    size_t used = 0;
    out[0] = 0;
    if (!detail->version) return 0;
    uint32_t present = detail->present;
    if (present & MYL_QBE_TRAP_PRESENT_INDEX) {
        if (!append(out, size, &used, " (index %" PRId64, detail->index)) return 0;
        if ((present & MYL_QBE_TRAP_PRESENT_LENGTH) &&
            !append(out, size, &used, ", length %" PRIu64, detail->length)) return 0;
        if (!append(out, size, &used, ")")) return 0;
    } else if (present & MYL_QBE_TRAP_PRESENT_LENGTH) {
        if (!append(out, size, &used, " (length %" PRIu64 ")", detail->length)) return 0;
    } else if (present & (MYL_QBE_TRAP_PRESENT_LEFT | MYL_QBE_TRAP_PRESENT_RIGHT | MYL_QBE_TRAP_PRESENT_WIDTH)) {
        if (!append(out, size, &used, " (%s:", detail->operation ? detail->operation : "arithmetic")) return 0;
        if ((present & MYL_QBE_TRAP_PRESENT_LEFT) &&
            !append(out, size, &used, " left %" PRId64, detail->left)) return 0;
        if ((present & MYL_QBE_TRAP_PRESENT_RIGHT) &&
            !append(out, size, &used, ", right %" PRId64, detail->right)) return 0;
        if ((present & MYL_QBE_TRAP_PRESENT_WIDTH) &&
            !append(out, size, &used, ", width %" PRIu64, detail->width)) return 0;
        if (!append(out, size, &used, ")")) return 0;
    } else if (detail->operation && *detail->operation) {
        /* A message-only detail: `assert cond, "text"` records present=0 and the
           assertion text as `operation`, so the human line reads
           `R_ASSERT: text` without disturbing any numeric rendering above. */
        if (!append(out, size, &used, ": %s", detail->operation)) return 0;
    }
    return used;
}
/* Append a quoted JSON string for arbitrary text. An assertion message is guest
   data, so a quote, backslash or control byte is escaped rather than copied; the
   record stays one valid JSON line for every message. Returns 0 on truncation. */
static int append_json_string(char *out, size_t size, size_t *used, const char *value) {
    if (!append(out, size, used, "\"")) return 0;
    for (const unsigned char *byte = (const unsigned char *)value; *byte; ++byte) {
        if (*byte == '"' || *byte == '\\') {
            if (!append(out, size, used, "\\%c", *byte)) return 0;
        } else if (*byte < 0x20) {
            if (!append(out, size, used, "\\u%04x", *byte)) return 0;
        } else if (!append(out, size, used, "%c", *byte)) return 0;
    }
    return append(out, size, used, "\"");
}
/* One bounded line of JSON for the structured transport. Only present numeric
   fields are emitted, matching the downstream `trap_detail` object. */
static size_t detail_json(const MylQbeTrapDetail *detail, char *out, size_t size) {
    if (size == 0) return 0;
    size_t used = 0;
    out[0] = 0;
    if (!detail->version) return 0;
    uint32_t present = detail->present;
    if (!append(out, size, &used, "{\"version\":%u,\"operation\":", detail->version)) return 0;
    if (!append_json_string(out, size, &used, detail->operation ? detail->operation : "operation")) return 0;
    if ((present & MYL_QBE_TRAP_PRESENT_INDEX) &&
        !append(out, size, &used, ",\"index\":%" PRId64, detail->index)) return 0;
    if ((present & MYL_QBE_TRAP_PRESENT_LENGTH) &&
        !append(out, size, &used, ",\"length\":%" PRIu64, detail->length)) return 0;
    if ((present & MYL_QBE_TRAP_PRESENT_LEFT) &&
        !append(out, size, &used, ",\"left\":%" PRId64, detail->left)) return 0;
    if ((present & MYL_QBE_TRAP_PRESENT_RIGHT) &&
        !append(out, size, &used, ",\"right\":%" PRId64, detail->right)) return 0;
    if ((present & MYL_QBE_TRAP_PRESENT_WIDTH) &&
        !append(out, size, &used, ",\"width\":%" PRIu64, detail->width)) return 0;
    if (!append(out, size, &used, "}")) return 0;
    return used;
}
/* Deepest inline-splice nesting one trap walk descends before it stops trusting
   the table and reports the frame it has. A real chain is bounded by the
   inliner's callee size budget and the trace keeps only sixteen frames, so only
   a malformed table can reach this. */
#define MYL_QBE_INLINE_DEPTH 32
/* The inline splice of `function` whose caller pc range contains `position`, or
   NULL when the pc is the function's own instruction. Splices never overlap. */
static const MylQbeInlineFrame *inline_at(const MylQbeFunction *function, uint64_t position) {
    if (!function->inlines) return NULL;
    for (uint64_t i = 0; i < function->inline_count; ++i) {
        const MylQbeInlineFrame *candidate = &function->inlines[i];
        if (position >= candidate->start && position < candidate->end) return candidate;
    }
    return NULL;
}
/* Append one logical frame when the trace has room. `logical` counts every frame
   the un-inlined call chain would have produced, so `omitted_frames` reports the
   depth the pre-inlining compiler reported. */
static void trace_emit(Context *ctx, const MylQbeFunction *function, uint64_t position, uint64_t *logical) {
    ++*logical;
    if (!function || position >= function->count || ctx->trace_count >= 16) return;
    MylQbeLocation at = function->locations[position];
    ctx->trace[ctx->trace_count++] = (MylQbeTrace){function->name, at.path, at.line, at.column};
}
/* Emit the frames one native-stack record stands for, innermost first: when the
   record's pc falls inside an inlined callee, the callee's own chain comes first
   and this function follows at the pc holding the call site. The enclosing frame
   is reported directly rather than re-entered, so a splice whose callee body
   begins at the call pc cannot loop; `depth` bounds a malformed table. */
static void trace_frame(Context *ctx, const MylQbeFunction *function, uint64_t position, unsigned depth, uint64_t *logical) {
    if (!function || position >= function->count) {
        ++*logical;
        return;
    }
    const MylQbeInlineFrame *record = depth < MYL_QBE_INLINE_DEPTH ? inline_at(function, position) : NULL;
    if (!record || !record->callee) {
        trace_emit(ctx, function, position, logical);
        return;
    }
    trace_frame(ctx, record->callee, record->callee_start + (position - record->start), depth + 1, logical);
    trace_emit(ctx, function, record->call_position, logical);
}
static uint64_t fail(void *context, const char *code) {
    Context *ctx = context;
    if (!ctx->trap) {
        ctx->trap = code;
        /* Generated frames link through `prev` in the native stack, so the trace
           is the chain from the innermost active record. Each record expands to
           the callee frames the inliner spliced into it, innermost first. Frames
           without function metadata (the direct C entry points) are skipped, and
           only the first sixteen frames are kept; `omitted_frames` reports the
           logical depth beyond them. */
        uint64_t logical = 0;
        for (const MylQbeActiveFrame *frame = ctx->active_frame; frame; frame = frame->prev) {
            trace_frame(ctx, frame->function, frame->position, 0, &logical);
        }
        ctx->omitted_frames = logical > ctx->trace_count ? logical-ctx->trace_count : 0;
        /* The trace is complete, so leave. Generated code does not test the
           sticky flag after a call; the trampoline armed this jump while the
           entry ran. A context without one (the direct C entry points and
           budget parsing) keeps the sticky behavior. */
        if (ctx->unwind) longjmp(*(jmp_buf *)ctx->unwind, 1);
    }
    return 0;
}
/* Synthetic operation codes for the value-producing helpers that do not carry a
   typed.BinaryOp ordinal. Kept outside the 0..6 binary range. */
#define MYL_QBE_OPERATION_CAST UINT64_C(100)
#define MYL_QBE_OPERATION_NEG  UINT64_C(101)
/* Map the operation that was already evaluated to a stable diagnostic name. */
static const char *operation_name(uint64_t op) {
    switch (op) {
        case 0: return "add";
        case 1: return "sub";
        case 2: return "mul";
        case 3: return "div";
        case 4: return "rem";
        case 5: return "floor_div";
        case 6: return "floor_rem";
        case MYL_QBE_OPERATION_CAST: return "cast";
        case MYL_QBE_OPERATION_NEG: return "neg";
        default: return "arithmetic";
    }
}
/* Record the typed detail only for the first trap; later failures leave the
   sticky first-trap detail untouched, exactly like the trap code itself. */
static uint64_t fail_detail(void *context, const char *code, const char *operation,
                            uint32_t present, int64_t index, uint64_t length,
                            int64_t left, int64_t right, uint64_t width) {
    Context *ctx = context;
    if (!ctx->trap) ctx->trap_detail = (MylQbeTrapDetail){
        .version = MYL_QBE_TRAP_DETAIL_VERSION,
        .present = present, .index = index, .length = length,
        .left = left, .right = right, .width = width,
        .operation = operation ? operation : "operation",
    };
    return fail(context, code);
}
void myl_qbe_fail(void *context, const char *code) { fail(context, code); }
void myl_qbe_fail_equality(void *context, int status) { fail(context, status == -2 ? "CapacityLimit" : "OutOfMemory"); }
uint64_t myl_qbe_failed(void *context) {
    return ((Context *)context)->trap != NULL;
}
void *myl_qbe_argv_list(void *context, const myl_native_type *element) {
    static const myl_native_type pointer_type = { .size=sizeof(void *), .alignment=_Alignof(void *), .kind=MYL_NATIVE_POINTER };
    Context *ctx = context;
    myl_native_list *list = myl_native_list_new(&ctx->heap, element, (size_t)ctx->guest_argc);
    if (!list) { myl_qbe_fail_allocation(context); return NULL; }
    /* Keep the growing list visible across each string allocation; appending the
       old backing copies the value before growing, but a stress collection can
       still run before the list itself is rooted by the append helper. */
    myl_native_root root;
    myl_native_root_push(&ctx->heap, &root, &list, &pointer_type);
    for (int i = 0; i < ctx->guest_argc; ++i) {
        const char *argument = ctx->guest_argv[i];
        myl_native_text *text = myl_native_text_from_utf8(&ctx->heap, (const unsigned char *)argument, strlen(argument));
        if (!text) { myl_qbe_fail_allocation(context); myl_native_root_pop(&ctx->heap, &root); return NULL; }
        if (!myl_native_list_append(&ctx->heap, list, &text)) { myl_qbe_fail_allocation(context); myl_native_root_pop(&ctx->heap, &root); return NULL; }
    }
    myl_native_root_pop(&ctx->heap, &root);
    return list;
}
void *myl_qbe_root_mark(void *context) { return ((Context *)context)->heap.roots; }
void myl_qbe_root_restore(void *context, void *mark) { ((Context *)context)->heap.roots = mark; }
void myl_qbe_fail_capability(void *context) { fail(context, "R_CAPABILITY"); }
void myl_qbe_fail_missing_capability(void *context, const char *flag) {
    if (flag) fprintf(stderr, "mylang: --restrict is active and this command line did not grant a capability the entry point requests; pass %s, or drop --restrict to grant every capability\n", flag);
    else fputs("mylang: --restrict is active and this command line did not grant a capability the entry point requests; pass an --allow-* flag, or drop --restrict to grant every capability\n", stderr);
    Context *ctx = context;
    ctx->reported = 1;
    fail(context, "CapabilityUnavailable");
}
void myl_qbe_fail_slice(void *context) { fail(context, "R_SLICE_BOUNDS"); }
void myl_qbe_fail_slice_step(void *context) { fail(context, "R_SLICE_STEP"); }
void myl_qbe_fail_text_bounds(void *context) { fail(context, "R_TEXT_BOUNDS"); }
void myl_qbe_fail_missing_key(void *context) { fail(context, "R_MISSING_KEY"); }
void myl_qbe_fail_empty_separator(void *context) { fail(context, "R_EMPTY_SEPARATOR"); }
void myl_qbe_fail_buffer_bounds(void *context) { fail(context, "R_BUFFER_BOUNDS"); }
void myl_qbe_fail_list_bounds(void *context) { fail(context, "R_LIST_BOUNDS"); }
void myl_qbe_fail_list_capacity(void *context) { fail(context, "R_LIST_CAPACITY"); }
void myl_qbe_fail_list_value(void *context) { fail(context, "R_LIST_VALUE"); }
/* A refused managed allocation names the budget when the heap declined it and
   the host only when the process itself could not produce the bytes. */
void myl_qbe_fail_allocation(void *context) {
    fail(context, ((Context *)context)->heap.exhausted ? memory_budget_code : "OutOfMemory");
}
void myl_qbe_fail_iteration(void *context) { fail(context, "R_LIST_ITERATION_MUTATION"); }
/* A failed assertion reports the `assert cond, "text"` message the current pc's
   function metadata carries, as the trap's `operation`, so both the human stderr
   line and the structured record name the message. A pc without a message (or a
   frame whose function metadata predates messages) keeps the bare trap. */
void myl_qbe_fail_assert(void *context) {
    Context *ctx = context;
    const MylQbeActiveFrame *frame = ctx->active_frame;
    if (frame && frame->function && frame->function->messages &&
        frame->position < frame->function->count) {
        const char *message = frame->function->messages[frame->position];
        if (message && *message) {
            fail_detail(context, "R_ASSERT", message, 0, 0, 0, 0, 0, 0);
            return;
        }
    }
    fail(context, "R_ASSERT");
}
void myl_qbe_fail_bounds(void *context) {
    fail(context, "R_INDEX_BOUNDS");
}
void myl_qbe_fail_index_bounds(void *context, int64_t index, uint64_t length) {
    fail_detail(context, "R_LIST_BOUNDS", "index",
        MYL_QBE_TRAP_PRESENT_INDEX | MYL_QBE_TRAP_PRESENT_LENGTH, index, length, 0, 0, 0);
}
void myl_qbe_fail_normalized_index_bounds(void *context, int64_t index, uint64_t length) {
    const int64_t original = index < 0 ? index - (int64_t)length : index;
    fail_detail(context, "R_LIST_BOUNDS", "index",
        MYL_QBE_TRAP_PRESENT_INDEX | MYL_QBE_TRAP_PRESENT_LENGTH, original, length, 0, 0, 0);
}
void myl_qbe_fail_pop_bounds(void *context, uint64_t length) {
    fail_detail(context, "R_LIST_BOUNDS", "pop",
        MYL_QBE_TRAP_PRESENT_LENGTH, 0, length, 0, 0, 0);
}
void myl_qbe_fail_pop_at_bounds(void *context, int64_t index, uint64_t length) {
    fail_detail(context, "R_LIST_BOUNDS", "pop",
        MYL_QBE_TRAP_PRESENT_INDEX | MYL_QBE_TRAP_PRESENT_LENGTH, index, length, 0, 0, 0);
}
void myl_qbe_fail_text_bounds_detail(void *context, int64_t index, uint64_t length) {
    fail_detail(context, "R_TEXT_BOUNDS", "index",
        MYL_QBE_TRAP_PRESENT_INDEX | MYL_QBE_TRAP_PRESENT_LENGTH, index, length, 0, 0, 0);
}
void myl_qbe_fail_array_bounds(void *context, int64_t index, uint64_t length) {
    fail_detail(context, "R_INDEX_BOUNDS", "index",
        MYL_QBE_TRAP_PRESENT_INDEX | MYL_QBE_TRAP_PRESENT_LENGTH, index, length, 0, 0, 0);
}
void myl_qbe_fail_division(void *context, uint64_t binary_op, int64_t left, int64_t right) {
    fail_detail(context, "R_DIVISION_BY_ZERO", operation_name(binary_op),
        MYL_QBE_TRAP_PRESENT_LEFT | MYL_QBE_TRAP_PRESENT_RIGHT, 0, 0, left, right, 0);
}
void myl_qbe_fail_overflow_op(void *context, uint64_t binary_op, int64_t left, int64_t right, uint64_t width) {
    fail_detail(context, "R_OVERFLOW", operation_name(binary_op),
        MYL_QBE_TRAP_PRESENT_LEFT | MYL_QBE_TRAP_PRESENT_RIGHT | MYL_QBE_TRAP_PRESENT_WIDTH,
        0, 0, left, right, width);
}
void myl_qbe_fail_cast(void *context, int64_t value, uint64_t width) {
    fail_detail(context, "R_OVERFLOW", "cast",
        MYL_QBE_TRAP_PRESENT_LEFT | MYL_QBE_TRAP_PRESENT_WIDTH, 0, 0, value, 0, width);
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
void myl_qbe_fail_frame(void *context) {
    fail(context, "R_FRAME_LIMIT");
}
static Wide decode(uint64_t value, uint64_t is_signed) {
    int64_t signed_value;
    memcpy(&signed_value, &value, sizeof signed_value);
    return is_signed ? (Wide)signed_value : (Wide)value;
}
/* Reinterpret already-evaluated bits as the signed operand the diagnostic shows. */
static int64_t as_i64(uint64_t value, uint64_t is_signed) {
    int64_t signed_value;
    memcpy(&signed_value, &value, sizeof signed_value);
    return is_signed ? signed_value : (int64_t)value;
}
static Wide modulus(void *context, uint64_t width) {
    if (!width || width > 64) return fail(context, "R_INTERNAL");
    return (Wide)1 << width;
}
static uint64_t checked(void *context, Wide value, uint64_t is_signed, uint64_t width,
                        uint64_t operation, uint32_t present, int64_t left, int64_t right) {
    Wide mod = modulus(context, width), maximum = (mod >> !!is_signed) - 1;
    Wide minimum = is_signed ? -(mod >> 1) : 0;
    if (value < minimum || value > maximum)
        return fail_detail(context, "R_OVERFLOW", operation_name(operation),
            present | MYL_QBE_TRAP_PRESENT_WIDTH, 0, 0, left, right, width);
    return (uint64_t)value;
}
uint64_t myl_qbe_int_cast(void *context, uint64_t from_signed, uint64_t to_signed, uint64_t width, uint64_t value) {
    return checked(context, decode(value, from_signed), to_signed, width,
        MYL_QBE_OPERATION_CAST, MYL_QBE_TRAP_PRESENT_LEFT, as_i64(value, from_signed), 0);
}
uint64_t myl_qbe_int_neg(void *context, uint64_t is_signed, uint64_t width, uint64_t value) {
    return checked(context, -decode(value, is_signed), is_signed, width,
        MYL_QBE_OPERATION_NEG, MYL_QBE_TRAP_PRESENT_LEFT, as_i64(value, is_signed), 0);
}
uint64_t myl_qbe_int_binary(void *context, uint64_t op, uint64_t is_signed, uint64_t width, uint64_t left, uint64_t right) {
    Wide a = decode(left, is_signed), b = decode(right, is_signed), result = 0;
    Wide mod = modulus(context, width), maximum = (mod >> !!is_signed) - 1;
    Wide minimum = is_signed ? -(mod >> 1) : 0;
    UnsignedWide mask = (UnsignedWide)mod - 1, x = (UnsignedWide)a & mask, y = (UnsignedWide)b & mask, raw = 0;
    switch (op) {
        case 0: result = a + b; break;
        case 1: result = a - b; break;
        case 2: if (__builtin_mul_overflow(a, b, &result))
            return fail_detail(context, "R_OVERFLOW", operation_name(op),
                MYL_QBE_TRAP_PRESENT_LEFT | MYL_QBE_TRAP_PRESENT_RIGHT | MYL_QBE_TRAP_PRESENT_WIDTH,
                0, 0, (int64_t)a, (int64_t)b, width);
            break;
        case 3: case 4: case 5: case 6: {
            if (!b) return fail_detail(context, "R_DIVISION_BY_ZERO", operation_name(op),
                MYL_QBE_TRAP_PRESENT_LEFT | MYL_QBE_TRAP_PRESENT_RIGHT, 0, 0, (int64_t)a, (int64_t)b, 0);
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
    return checked(context, result, is_signed, width, op,
        MYL_QBE_TRAP_PRESENT_LEFT | MYL_QBE_TRAP_PRESENT_RIGHT, (int64_t)a, (int64_t)b);
wrapping:
    result = (Wide)(raw & mask);
    return (uint64_t)(is_signed && result > maximum ? result - mod : result);
}
static double float_value(uint64_t bits) {
    double value;
    memcpy(&value, &bits, sizeof value);
    return value;
}
/* FLOAT-NAN-OBSERVED-1: a result keeps the bits the operation produced, NaN
   payload and sign included; a NaN is canonicalized only where its bits can be
   observed (formatting, hashing, the host and wire boundaries). */
static uint64_t float_bits(double value) {
    uint64_t bits;
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
/* QBE-FLOAT-ENV-1: the environment is verified once at context start-up (see
   execute_config_args) and again after every C FFI boundary, so the value
   helpers below no longer re-check it on each call. */
void myl_qbe_float_check(void *context) {
    (void)float_environment(context);
}
uint64_t myl_qbe_float_binary(void *context, uint64_t op, uint64_t left, uint64_t right) {
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
    /* The logical ceiling is independent of the execution stack guard. A
       context with unbounded frames still tracks at most `max_frames` slots for
       trace reporting; deeper frames share one scratch slot. */
    if (ctx->frames == ctx->frame_limit) { fail(context, "R_FRAME_LIMIT"); return; }
    if (ctx->frame_data) {
        ctx->active_frame = ctx->frames < ctx->max_frames ? &ctx->frame_data[ctx->frames] : &ctx->scratch_frame;
        *ctx->active_frame = (MylQbeActiveFrame){0};
    }
    ++ctx->frames;
}
void myl_qbe_leave(void *context) {
    Context *ctx = context;
    if (!ctx->frames) { fail(context, "R_INTERNAL"); return; }
    if (ctx->active_frame) ctx->native_stack_bytes -= ctx->active_frame->native_bytes;
    --ctx->frames;
    if (!ctx->frames || !ctx->frame_data) {
        ctx->active_frame = NULL;
        return;
    }
    ctx->active_frame = ctx->frames <= ctx->max_frames ? &ctx->frame_data[ctx->frames-1] : &ctx->scratch_frame;
}
void myl_qbe_step(void *context) {
    Context *ctx = context;
    if (ctx->steps == ctx->max_steps) { fail(context, "R_STEP_LIMIT"); return; }
    ++ctx->steps;
}
/* A build that omitted instruction-budget accounting cannot honor a runtime step
   ceiling. The generated entry point calls this once, before any guest
   instruction runs, so the mismatch is reported instead of silently ignored. */
void myl_qbe_require_step_accounting(void *context) {
    Context *ctx = context;
    if (ctx->max_steps == MYL_QBE_UNBOUNDED) return;
    fail_detail(ctx, "R_NO_STEP_ACCOUNTING", "run it under `mylang run --max-steps=N`, or rebuild it with --mode Debug", 0, 0, 0, 0, 0, 0);
}
/* A build that omitted call-depth accounting cannot honor a runtime frame
   ceiling. The generated entry point calls this once, before any guest
   instruction runs, so the mismatch is reported instead of silently ignored. */
void myl_qbe_require_frame_accounting(void *context) {
    Context *ctx = context;
    if (ctx->frame_limit == MYL_QBE_UNBOUNDED) return;
    fail_detail(ctx, "R_NO_FRAME_ACCOUNTING", "run it under `mylang run --max-frames=N`, or rebuild it with --mode Debug", 0, 0, 0, 0, 0, 0);
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
/* Parse one positive decimal budget; zero reports an empty, zero, non-numeric
   or overflowing value. */
static uint64_t budget(const char *text) {
    uint64_t value = 0;
    if (!*text) return 0;
    for (; *text; ++text) {
        if (*text < '0' || *text > '9' || value > (UINT64_MAX - (unsigned)(*text - '0')) / 10) return 0;
        value = value * 10 + (unsigned)(*text - '0');
    }
    return value;
}
/* Consume one budget control spelled `prefix` plus a value into `slot`. */
static int budget_control(MylQbeControls *controls, const char *option, const char *prefix, uint64_t *slot, int *seen) {
    size_t width = strlen(prefix);
    if (strncmp(option, prefix, width)) return 0;
    uint64_t value = budget(option + width);
    if (*seen || !value) controls->error = *seen ? "RepeatedRuntimeOption" : "InvalidBudget";
    *seen = 1;
    *slot = value;
    return 1;
}
/* Consume one switch control spelled exactly `name`. */
static int switch_control(MylQbeControls *controls, const char *option, const char *name, int *slot) {
    if (strcmp(option, name)) return 0;
    if (*slot) controls->error = "RepeatedRuntimeOption";
    *slot = 1;
    return 1;
}
int myl_qbe_control(MylQbeControls *controls, const char *option) {
    if (budget_control(controls, option, "--max-steps=", &controls->max_steps, &controls->seen_steps)) return 1;
    if (budget_control(controls, option, "--max-frames=", &controls->max_frames, &controls->seen_frames)) return 1;
    if (budget_control(controls, option, "--timeout=", &controls->timeout, &controls->seen_timeout)) return 1;
    if (switch_control(controls, option, "--gc-stress", &controls->stress)) return 1;
    return switch_control(controls, option, "--print-result", &controls->print);
}
int mylang_qbe_run_options(uint64_t (*entry)(void *), int argc, char **argv) {
    MylQbeControls controls = {0};
    for (int i = 1; i < argc; ++i) {
        if (myl_qbe_control(&controls, argv[i])) continue;
        fprintf(stderr, "mylang: %s is not a runtime option\n", argv[i]);
        return 2;
    }
    return mylang_qbe_run_process(entry, &controls, 0, NULL, NULL);
}
int mylang_qbe_run_process(uint64_t (*entry)(void *), const MylQbeControls *controls, int argc, char **argv, const struct MylangNativeProvidersTag *providers) {
    /* Unbounded by default: the memory ceiling contains a runaway allocation,
       and --timeout=SECONDS is the elapsed-time guard. */
    if (controls->error) {
        fprintf(stderr, "%s: QBE runtime failure\n", controls->error);
        return 2;
    }
    uint64_t steps = controls->seen_steps ? controls->max_steps : MYL_QBE_UNBOUNDED;
    uint64_t frames = controls->seen_frames ? controls->max_frames : MYL_QBE_UNBOUNDED;
    if (!arm_timeout(controls->timeout)) {
        fputs("mylang: cannot arm the --timeout wall-clock guard\n", stderr);
        return 2;
    }
    /* The guest receives its arguments exactly as the process was given them:
       no runtime option is read from them, so `--gc-stress` or `--` is data. */
    for (int i = 0; i < argc; ++i) {
        if (!myl_native_text_valid_utf8((const unsigned char *)argv[i], strlen(argv[i]))) {
            fprintf(stderr, "mylang: guest argument is not valid UTF-8\n");
            return 2;
        }
    }
    MylQbeResult result;
    if (execute_config_args(entry, steps, frames, controls->stress, providers, NULL, argc, argv, &result)) {
        if (result.reported) return 2;
        char suffix[192] = "";
        (void)detail_text(&result.trap_detail, suffix, sizeof suffix);
        if (result.trace_count) {
            const MylQbeTrace *at=&result.trace[0];
            fprintf(stderr,"%s:%" PRIu64 ":%" PRIu64 ": error[%s]: %s%s\n",at->path,at->line,at->column,result.code,describe(result.code),suffix);
        } else fprintf(stderr, "%s: %s%s\n", result.code, describe(result.code), suffix);
        for (uint64_t i=0; i<result.trace_count; ++i) {
            MylQbeTrace frame = result.trace[i];
            fprintf(stderr, "  in %s at %s:%" PRIu64 ":%" PRIu64 "\n", frame.function, frame.path, frame.line, frame.column);
        }
        char record[256];
        if (detail_json(&result.trap_detail, record, sizeof record) != 0)
            fprintf(stderr, "%s%s\n", MYL_QBE_TRAP_RECORD_MARKER, record);
        return strncmp(result.code,"R_",2) ? 2:1;
    }
    /* The entry point's integer result becomes the process exit status, the way
       a Python or Go program returns an exit code, truncated to the low 8 bits
       (POSIX `waitpid` semantics: status = value & 0xFF). `--print-result` is now
       orthogonal: it still prints the full value to stdout when asked, but the
       status reflects the value whether or not it was printed. A trap outranks the
       status and returns 1 above, because the program never reached its return. */
    int64_t value;
    memcpy(&value, &result.value, sizeof value);
    if (controls->print) printf("%" PRId64 "\n", value);
    return (int)((uint64_t)value & 0xFF);
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
static int execute_config_args(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, int stress, const struct MylangNativeProvidersTag *providers, void (*initialize)(void *), int guest_argc, char **guest_argv, MylQbeResult *result) {
    *result=(MylQbeResult){0};
    if (!steps || !frames) { result->code="InvalidBudget";return 1; }
    /* Unbounded frames still need a bounded native stack and trace buffer, so the
       logical ceiling and the slot capacity are separate values. */
    uint64_t capacity = frames == MYL_QBE_UNBOUNDED ? MYL_QBE_FRAME_CAPACITY : frames;
    if (capacity>SIZE_MAX/sizeof(MylQbeActiveFrame)) { result->code="OutOfMemory";return 1; }
    /* Read the ceiling and arm the kernel backstop before the first allocation,
       so a runtime defect cannot outgrow the budget the heap will enforce. */
    int budgeted=1;
    size_t budget=myl_native_budget_environment(&budgeted);
    if (!budgeted) { result->code="InvalidMemoryLimit";return 1; }
    myl_native_budget_guard(budget);
    Context *context=calloc(1,sizeof *context);
    if (!context) { result->code="OutOfMemory";return 1; }
    context->max_steps=steps;context->max_frames=capacity;context->frame_limit=frames;context->providers=providers;
    context->guest_argc=guest_argc;context->guest_argv=guest_argv;
    myl_native_heap_init(&context->heap, budget ? budget : SIZE_MAX);
    context->heap.stress = stress;
    context->frame_data = calloc((size_t)capacity, sizeof(MylQbeActiveFrame));
    if (!context->frame_data) context->trap = "OutOfMemory";
    /* QBE-FLOAT-ENV-1: verify the process floating-point environment exactly
       once, before any guest or host code runs. The per-operation checks are
       gone, so this is what preserves R_FLOAT_ENVIRONMENT for a process that
       starts with a non-default rounding mode; a C FFI call re-checks after it
       returns (see qbe_c_abi.zig). The probe costs one fegetround plus two
       multiplies, so a build that never uses floats only pays it once. */
    if (!context->trap) (void)float_environment(context);
    if (!context->trap && initialize) initialize(context);
    if (!context->trap) result->value = myl_qbe_on_stack(entry,context);
    if (!context->trap && context->frames != 0) context->trap = "R_INTERNAL";
    result->steps = context->steps;
    result->code = context->trap;
    result->trace_count = context->trace_count;
    result->omitted_frames = context->omitted_frames;
    result->reported = context->reported;
    result->trap_detail = context->trap_detail;
    memcpy(result->trace, context->trace, sizeof result->trace);
    if (context->cleanup) context->cleanup(context);
    while (context->frame_allocations) myl_qbe_frame_release(context,(NativeFrameAllocation *)context->frame_allocations+1);
    free(context->host_state);
    free(context->frame_data);
    if (!exit_without_sweep) myl_native_heap_destroy(&context->heap);
    int failed=context->trap != NULL;
    free(context);
    return failed;
}
int mylang_qbe_execute_config(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, int stress, const struct MylangNativeProvidersTag *providers, void (*initialize)(void *), MylQbeResult *result) {
    return execute_config_args(entry,steps,frames,stress,providers,initialize,0,NULL,result);
}
int mylang_qbe_run(uint64_t (*entry)(void *)) {
    return mylang_qbe_run_options(entry, 0, NULL);
}
