#ifndef MYLANG_QBE_RUNTIME_H
#define MYLANG_QBE_RUNTIME_H
#include <stdint.h>
#include "native_heap.h"

struct MylangNativeProvidersTag;
/* Native ABI v3: execution context and sticky structured traps.
 * One context belongs to a synchronous execution; helpers do not terminate hosts.
 * Context prefix is an ABI contract for inline budget checks. */
typedef struct { const char *path; uint64_t line, column; } MylQbeLocation;
/* `messages` has one entry per pc, `""` for a pc that is not an assertion. It is
 * the `operation` text a failing `assert` reports; `count` bounds both tables.
 * `inlines`/`inline_count` describe the callee bodies spliced into this function
 * by the inliner, so a trap trace can replay the frames a native call would have
 * pushed. Both are appended so metadata without inlining still initializes. */
struct MylQbeInlineFrameTag;
typedef struct { const char *name; const MylQbeLocation *locations; uint64_t count; const char *const *messages; const struct MylQbeInlineFrameTag *inlines; uint64_t inline_count; } MylQbeFunction;
/* One inlined splice: the callee's metadata, the caller pc range `[start,end)`
 * the callee body occupies, the callee-local pc that range starts at, and the
 * caller pc whose location entry is the call site. */
typedef struct MylQbeInlineFrameTag {
    const MylQbeFunction *callee;
    uint64_t start, end, callee_start, call_position;
} MylQbeInlineFrame;
/* One guest activation. Generated code allocates the record in its own native
 * stack frame and links it through `prev` into `ctx->active_frame`; the runtime
 * walks that chain for trap traces, so no frame array is involved. Generated
 * code writes `prev` (+0), `function` (+8) and `position` (+16); `native_bytes`
 * remains for the direct `myl_qbe_enter_at_sized` C entry point. */
typedef struct MylQbeActiveFrame {
    struct MylQbeActiveFrame *prev;
    const MylQbeFunction *function;
    uint64_t position;
    uint64_t native_bytes;
} MylQbeActiveFrame;
typedef struct { const char *function, *path; uint64_t line, column; } MylQbeTrace;
/* Bounded typed values captured at the first failing operation. `present` is a
 * bitmask over the MYL_QBE_TRAP_PRESENT_* bits; an absent field is zero and is
 * omitted from both the text suffix and the structured transport. `operation`
 * is a static bounded name ("index", "pop", "add", ...). */
typedef struct {
    uint32_t version;   /* 1 */
    uint32_t present;   /* bitmask; absent fields are zero and omitted downstream */
    int64_t  index;     /* original index, negative preserved */
    uint64_t length;    /* collection/object length at the failure */
    int64_t  left;      /* arithmetic operand where captured */
    int64_t  right;     /* arithmetic operand where captured */
    uint64_t width;     /* element width / integer width where relevant */
    const char *operation; /* static bounded name, e.g. "index", "pop", "div" */
} MylQbeTrapDetail;
#define MYL_QBE_TRAP_DETAIL_VERSION UINT32_C(1)
#define MYL_QBE_TRAP_PRESENT_INDEX  UINT32_C(1)
#define MYL_QBE_TRAP_PRESENT_LENGTH UINT32_C(2)
#define MYL_QBE_TRAP_PRESENT_LEFT   UINT32_C(4)
#define MYL_QBE_TRAP_PRESENT_RIGHT  UINT32_C(8)
#define MYL_QBE_TRAP_PRESENT_WIDTH  UINT32_C(16)
/* Marker beginning the one-line machine record a native child appends to
 * stderr after its human-readable trap diagnostic. The record JSON carries the
 * same `MylQbeTrapDetail` fields. */
#define MYL_QBE_TRAP_RECORD_MARKER "\x1eMYLANG-TRAP "
/* The runtime's "no logical ceiling" sentinel for steps and frames. A program is
 * unbounded by default; the inline step check compares `steps == max_steps`, so
 * UINT64_MAX is unreachable, and for frames the same value keeps the native
 * stack bounded while the logical call depth stays uncapped. */
#define MYL_QBE_UNBOUNDED UINT64_MAX
/* Frame slots and trace storage the runtime reserves when frames are unbounded. */
#define MYL_QBE_FRAME_CAPACITY 1024
/* Environment authority. The root grant is `UINT64_MAX - 2`; `env.only(...)`
 * narrows it to a scope whose index is encoded as `UINT64_MAX - 3 - index`.
 * Each scope borrows a NUL-separated name blob emitted by the backend. */
#define MYL_QBE_ENVIRONMENT_ROOT (UINT64_MAX - 2)
#define MYL_QBE_ENVIRONMENT_SCOPE_BASE (UINT64_MAX - 3)
#define MYL_QBE_ENVIRONMENT_SCOPES 64
#define MYL_QBE_ENVIRONMENT_NAMES 16
#define MYL_QBE_ENVIRONMENT_NAME_LIMIT 128
typedef struct { const unsigned char *names; size_t length; } MylQbeEnvironmentScope;
typedef struct {
    uint64_t steps, frames, max_steps, max_frames;
    const char *trap;
    MylQbeActiveFrame *frame_data, *active_frame;
    /* Generated code reads these two at frozen offsets 56 and 64: the logical
       depth ceiling and the lowest native-stack address a frame record may use.
       Both are widened out of the appended tail so the generated prologue can
       test them without a runtime call. */
    uint64_t frame_limit;
    uintptr_t frame_floor;
    MylQbeTrace trace[16];
    uint64_t trace_count, omitted_frames;
    myl_native_heap heap;
    myl_native_region regions[256];
    uint64_t next_region_identity;
    const struct MylangNativeProvidersTag *providers;
    void *resource_tails[2];
    size_t resource_live[2];
    void (*cleanup)(void *);
    void *host_state;
    uint64_t native_stack_bytes, native_stack_limit;
    uintptr_t native_stack_bottom;
    void *frame_allocations;
    int guest_argc;
    char **guest_argv;
    int reported;
    MylQbeTrapDetail trap_detail;
    /* Shared slot for the direct `myl_qbe_enter` C entry point (the C-model
       frame array), which generated code no longer uses. */
    MylQbeActiveFrame scratch_frame;
    /* Bounded `fs.dir(path)` scope registry: each entry owns the joined prefix
       path a derived Filesystem resolves under, and the resource sentinel carries
       a 1-based index into it. Appended after the frozen ABI prefix. */
    void *resource_scopes;
    size_t resource_scope_count, resource_scope_capacity;
    /* Narrowed `Environment` scopes registered by `env.only(...)`. Appended after
       the frozen ABI prefix, so generated-code offsets stay unchanged. */
    MylQbeEnvironmentScope environment_scopes[MYL_QBE_ENVIRONMENT_SCOPES];
    unsigned environment_scope_count;
    /* Armed by the guest-stack trampoline while generated code runs, so the
       first failure leaves through `longjmp` instead of a sticky flag tested
       after every call. NULL outside execution and in the direct C entry
       points, which keep the sticky behavior. Appended after the frozen ABI
       prefix, so generated-code offsets stay unchanged. */
    void *unwind;
    /* One past the highest address of the guest-stack mapping while generated
       code runs, zero otherwise. With `native_stack_bottom` it bounds the
       frame-pointer walk a frame-map trap performs (QBE-FRAMEMAP-1). Appended
       after the frozen ABI prefix. */
    uintptr_t native_stack_top;
} MylQbeContext;
typedef struct {
    uint64_t value, steps;
    const char *code;
    MylQbeTrace trace[16];
    uint64_t trace_count, omitted_frames;
    int reported;
    MylQbeTrapDetail trap_detail;
} MylQbeResult;
void myl_qbe_fail_capability(void *);
void myl_qbe_fail_missing_capability(void *, const char *flag);
uint64_t myl_qbe_on_stack(uint64_t (*entry)(void *), MylQbeContext *);
void *myl_qbe_frame_allocate(void *, uint64_t bytes);
void myl_qbe_frame_release(void *, void *);
void myl_qbe_enter_at_sized(void *, const MylQbeFunction *, uint64_t bytes);
void myl_qbe_enter_at(void *context, const MylQbeFunction *function);
void myl_qbe_step_at(void *context, uint64_t position);
/* Generated entry code calls this when its build omitted step accounting, so a
 * runtime step ceiling fails loudly instead of being silently ignored. */
void myl_qbe_require_step_accounting(void *context);
/// Refuse a runtime frame ceiling this build omitted accounting for.
void myl_qbe_require_frame_accounting(void *context);
void *myl_qbe_root_mark(void *context);
void myl_qbe_root_restore(void *context, void *mark);
/* Build a managed list[str] from the guest arguments the runtime filtered.
 * `element` is the generated descriptor for the list's str element. Returns
 * NULL after setting an allocation trap. */
void *myl_qbe_argv_list(void *context, const myl_native_type *element);
void myl_qbe_fail_slice(void *context);
void myl_qbe_fail_slice_step(void *context);
void myl_qbe_fail_text_bounds(void *context);
void myl_qbe_fail_missing_key(void *context);
void myl_qbe_fail_empty_separator(void *context);
void myl_qbe_fail_buffer_bounds(void *context);
void myl_qbe_fail_list_bounds(void *context);
void myl_qbe_fail_list_capacity(void *context);
void myl_qbe_fail_list_value(void *context);
void myl_qbe_fail_allocation(void *context);
void myl_qbe_fail_iteration(void *context);
void myl_qbe_fail_assert(void *context);
void myl_qbe_fail_bounds(void *context);
/* Detailed variants record the original values first seen at the failing
 * operation. They are the only paths that populate `trap_detail`; the
 * detail-less entry points above stay for callers without captured values. */
void myl_qbe_fail_index_bounds(void *context, int64_t index, uint64_t length);
/* `length` has already been added to a negative source index by the checked
 * frontend; recover the original by subtracting it back. */
void myl_qbe_fail_normalized_index_bounds(void *context, int64_t normalized_index, uint64_t length);
void myl_qbe_fail_pop_bounds(void *context, uint64_t length);
void myl_qbe_fail_pop_at_bounds(void *context, int64_t index, uint64_t length);
void myl_qbe_fail_text_bounds_detail(void *context, int64_t index, uint64_t length);
void myl_qbe_fail_array_bounds(void *context, int64_t index, uint64_t length);
/* `binary_op` is the typed.BinaryOp ordinal (0=add, 1=sub, 2=mul, 3=div, ...). */
void myl_qbe_fail_division(void *context, uint64_t binary_op, int64_t left, int64_t right);
void myl_qbe_fail_overflow_op(void *context, uint64_t binary_op, int64_t left, int64_t right, uint64_t width);
/* Cold path of an inlined checked integer cast: the value's raw bits and the
 * target width, producing the same detail `myl_qbe_int_cast` reports. */
void myl_qbe_fail_cast(void *context, int64_t value, uint64_t width);
myl_native_heap *myl_qbe_heap(void *context);
uint64_t myl_qbe_failed(void *context);
void myl_qbe_float_check(void *context);
void myl_qbe_fail_step(void *context);
void myl_qbe_fail_overflow(void *context);
/* Cold path of the generated frame prologue: the logical depth ceiling or the
 * execution-stack floor was reached. */
void myl_qbe_fail_frame(void *context);
int mylang_qbe_execute_config(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, int stress, const struct MylangNativeProvidersTag *, void (*initialize)(void *), MylQbeResult *result);
int mylang_qbe_execute_providers(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, int stress, const struct MylangNativeProvidersTag *, MylQbeResult *result);
void myl_qbe_fail(void *, const char *);
void myl_qbe_fail_equality(void *, int status);
uint64_t myl_qbe_grant_resource(void *, unsigned kind);
uint64_t myl_qbe_grant_resource_checked(void *, unsigned kind, const char *flag);
uint64_t myl_qbe_restrict_resource(void *, uint64_t authority, unsigned permissions);
int myl_qbe_resource_new(void *, uint64_t authority, unsigned kind, const unsigned char *, size_t, myl_native_resource **);
int myl_qbe_resource_complete(void *, myl_native_resource *);
int myl_qbe_resource_read(void *, myl_native_resource *, unsigned char *, size_t, size_t *, int *);
int myl_qbe_resource_write(void *, myl_native_resource *, const unsigned char *, size_t, size_t *);
uint64_t myl_qbe_grant_external(void *, unsigned kind);
uint64_t myl_qbe_grant_external_checked(void *, unsigned kind, const char *flag);
int myl_qbe_external_read(void *, uint64_t authority, unsigned kind, uint64_t *output);
int myl_qbe_environment_get(void *, uint64_t authority, const unsigned char *key, size_t length, unsigned char *output, size_t capacity, size_t *written, int *present);
/* Python `env.get`: return a rooted UTF-8 text or NULL when absent. `*present`
   is 1 exactly when a value was returned; a failure traps through the context. */
void *myl_qbe_environment_text(void *, uint64_t authority, const unsigned char *key, size_t length, int *present);
/* `env.only(...)`: register a NUL-separated literal name blob and return the
   narrowed authority. The root authority is the only accepted input. */
uint64_t myl_qbe_environment_only(void *, uint64_t authority, const unsigned char *names, size_t length);
/* `env.names()`: build a sorted managed `list[str]` of the visible names, or
   NULL after setting an allocation trap. */
void *myl_qbe_environment_names(void *, uint64_t authority);
int mylang_qbe_execute_gc(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, int stress, MylQbeResult *result);
int mylang_qbe_execute(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, MylQbeResult *result);

/* Scalar values: one word per value, signed integers sign extended, floats
 * represented by their IEEE bits; the first guest argument is an opaque context.
 * Operation numbers are typed.BinaryOp / typed.UnaryOp ordinals. */
uint64_t myl_qbe_int_binary(void *context, uint64_t op, uint64_t is_signed, uint64_t width, uint64_t a, uint64_t b);
uint64_t myl_qbe_int_cast(void *context, uint64_t from_signed, uint64_t to_signed, uint64_t width, uint64_t value);
uint64_t myl_qbe_int_neg(void *context, uint64_t is_signed, uint64_t width, uint64_t value);
uint64_t myl_qbe_float_binary(void *context, uint64_t op, uint64_t a, uint64_t b);
uint64_t myl_qbe_float_unary(void *context, uint64_t op, uint64_t value);
void myl_qbe_enter(void *context);
void myl_qbe_leave(void *context);
void myl_qbe_step(void *context);
/* The runtime controls one process runs under. A native executable reads them
 * from `MYLANG_OPTIONS`, never from its own arguments: `--max-steps=N`,
 * `--max-frames=N`, `--timeout=SECONDS`, `--gc-stress` and `--print-result`.
 * A zero-initialized value is unbounded, unstressed and silent. `error` names
 * the first malformed or repeated control. */
typedef struct MylQbeControls {
    uint64_t max_steps, max_frames, timeout;
    int seen_steps, seen_frames, seen_timeout, stress, print;
    const char *error;
} MylQbeControls;
/* Consume one runtime control into `controls`; 0 when `option` names none. */
int myl_qbe_control(MylQbeControls *controls, const char *option);
/* Run `entry` as the whole process under `controls`, handing the guest its
 * `argc` arguments unchanged. Returns the process exit status. */
int mylang_qbe_run_process(uint64_t (*entry)(void *), const MylQbeControls *controls, int argc, char **argv, const struct MylangNativeProvidersTag *providers);
int mylang_qbe_run(uint64_t (*entry)(void *));
/* Run `entry` with `argv[1..]` as runtime controls and no guest arguments. */
int mylang_qbe_run_options(uint64_t (*entry)(void *), int argc, char **argv);
/* Declare that this process runs one guest program and then exits, so the runner
 * may leave the managed heap to the process instead of freeing every live object
 * first. A host that runs the guest more than once in one process must never
 * call this: it would leave the heap of every run but the last unreclaimed. */
void myl_qbe_exit_without_sweep(void);
#endif
