#ifndef MYLANG_QBE_RUNTIME_H
#define MYLANG_QBE_RUNTIME_H
#include <stdint.h>
#include "native_heap.h"

struct MylangNativeProvidersTag;
/* Native ABI v2: execution context and sticky structured traps.
 * One context belongs to a synchronous execution; helpers do not terminate hosts.
 * Context prefix is an ABI contract for inline budget checks. */
typedef struct { const char *path; uint64_t line, column; } MylQbeLocation;
typedef struct { const char *name; const MylQbeLocation *locations; uint64_t count; } MylQbeFunction;
typedef struct { const MylQbeFunction *function; uint64_t position, native_bytes; } MylQbeActiveFrame;
typedef struct { const char *function, *path; uint64_t line, column; } MylQbeTrace;
typedef struct {
    uint64_t steps, frames, max_steps, max_frames;
    const char *trap;
    MylQbeActiveFrame *frame_data, *active_frame;
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
} MylQbeContext;
typedef struct {
    uint64_t value, steps;
    const char *code;
    MylQbeTrace trace[16];
    uint64_t trace_count, omitted_frames;
} MylQbeResult;
void myl_qbe_fail_capability(void *);
uint64_t myl_qbe_on_stack(uint64_t (*entry)(void *), MylQbeContext *);
void *myl_qbe_frame_allocate(void *, uint64_t bytes);
void myl_qbe_frame_release(void *, void *);
void myl_qbe_enter_at_sized(void *, const MylQbeFunction *, uint64_t bytes);
void myl_qbe_enter_at(void *context, const MylQbeFunction *function);
void myl_qbe_step_at(void *context, uint64_t position);
void *myl_qbe_root_mark(void *context);
void myl_qbe_root_restore(void *context, void *mark);
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
myl_native_heap *myl_qbe_heap(void *context);
uint64_t myl_qbe_failed(void *context);
void myl_qbe_float_check(void *context);
void myl_qbe_fail_step(void *context);
void myl_qbe_fail_overflow(void *context);
int mylang_qbe_execute_config(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, int stress, const struct MylangNativeProvidersTag *, void (*initialize)(void *), MylQbeResult *result);
int mylang_qbe_execute_providers(uint64_t (*entry)(void *), uint64_t steps, uint64_t frames, int stress, const struct MylangNativeProvidersTag *, MylQbeResult *result);
void myl_qbe_fail(void *, const char *);
void myl_qbe_fail_equality(void *, int status);
uint64_t myl_qbe_grant_resource(void *, unsigned kind);
uint64_t myl_qbe_restrict_resource(void *, uint64_t authority, unsigned permissions);
int myl_qbe_resource_new(void *, uint64_t authority, unsigned kind, const unsigned char *, size_t, myl_native_resource **);
int myl_qbe_resource_complete(void *, myl_native_resource *);
int myl_qbe_resource_read(void *, myl_native_resource *, unsigned char *, size_t, size_t *, int *);
int myl_qbe_resource_write(void *, myl_native_resource *, const unsigned char *, size_t, size_t *);
uint64_t myl_qbe_grant_external(void *, unsigned kind);
int myl_qbe_external_read(void *, uint64_t authority, unsigned kind, uint64_t *output);
int myl_qbe_environment_get(void *, uint64_t authority, const unsigned char *key, size_t length, unsigned char *output, size_t capacity, size_t *written, int *present);
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
int mylang_qbe_run(uint64_t (*entry)(void *));
int mylang_qbe_run_providers(uint64_t (*entry)(void *), int argc, char **argv, const struct MylangNativeProvidersTag *providers);
int mylang_qbe_run_options(uint64_t (*entry)(void *), int argc, char **argv);
#endif
