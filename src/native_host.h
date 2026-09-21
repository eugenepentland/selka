#ifndef MYLANG_NATIVE_HOST_H
#define MYLANG_NATIVE_HOST_H
#include <stddef.h>
#include <stdint.h>
/* Copied preorder values. Nodes never contain guest addresses. Nominal names are
   exact compiler names; records/arrays have bits=0, variants have a tag in bits,
   domains have one backing-value child. Scalars have no children. */
typedef struct { const char *type; uint64_t bits; size_t children; } MylangHostNode;
typedef struct {
    const MylangHostNode *arguments;
    size_t argument_nodes;
    MylangHostNode *output;
    size_t capacity, output_nodes;
    uint64_t work_remaining;
    int exhausted;
} MylangHostCall;
/* Charge before effects. Failed charge is sticky even if a callback returns success. */
static inline int mylang_host_charge(MylangHostCall *call, uint64_t work) {
    if (call->exhausted || work > call->work_remaining) { call->exhausted=1;return 0; }
    call->work_remaining-=work;return 1;
}
/* Packed calls are an opt-in fast path for integers and padding-free fixed u8
   arrays. Every value points into runtime-owned scratch; callbacks may neither
   retain these copies nor reenter the generated program. Payloads have byte
   alignment only: use memcpy, never scalar pointer casts, to access integers.
   The initially zeroed output must keep its pointer and size; on success set
   output_written to exactly output.size. Return NULL or a static error name. */
typedef struct { void *bytes; size_t size; } MylangHostPackedValue;
typedef struct {
    const MylangHostPackedValue *arguments;
    size_t argument_count;
    MylangHostPackedValue output;
    size_t output_written;
    uint64_t work_remaining;
    int exhausted;
} MylangHostPackedCall;
static inline int mylang_host_packed_charge(MylangHostPackedCall *call, uint64_t work) {
    if (call->exhausted || work > call->work_remaining) { call->exhausted=1;return 0; }
    call->work_remaining-=work;return 1;
}
typedef struct {
    const char *name;
    const char *const *parameters;
    size_t parameter_count;
    const char *result;
    unsigned effects, grants;
    void *context;
    /* Return NULL on success or a static error name. Output nodes borrow this
       call's storage; type strings remain valid until copying completes. The
       callback must not retain call buffers or reenter the generated program. */
    const char *(*invoke)(void *, MylangHostCall *);
    /* Optional packed-copy callback. The runtime uses it only after validating
       an all-scalar/fixed-u8-array schema and equivalent node/depth quotas. */
    const char *(*invoke_packed)(void *, MylangHostPackedCall *);
} MylangHostBinding;
typedef struct {
    const MylangHostBinding *bindings;
    size_t count;
    /* Zero selects 10000 calls, 1000000 work, 65536 nodes, 64 levels. */
    uint64_t max_calls, max_work;
    size_t max_values, max_depth;
} MylangHostRegistry;
#endif
