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
static int mylang_host_charge(MylangHostCall *call, uint64_t work) {
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
} MylangHostBinding;
typedef struct {
    const MylangHostBinding *bindings;
    size_t count;
    /* Zero selects 10000 calls, 1000000 work, 65536 nodes, 64 levels. */
    uint64_t max_calls, max_work;
    size_t max_values, max_depth;
} MylangHostRegistry;
#endif
