#ifndef MYLANG_NATIVE_EMBED_H
#define MYLANG_NATIVE_EMBED_H
#include <stdint.h>
#include <stddef.h>
#define MYLANG_NATIVE_EMBED_ABI 1
/* Include native_providers.h first. Build generated C with MYLANG_EMBED.
   One generated program per linked library. No guest pointer escapes this ABI. */
typedef struct {
    uint64_t max_steps, max_frames; /* zero selects 10000000 / 1024 */
    const MylangNativeProviders *providers; /* NULL grants no external authority */
} MylangRunOptions;
typedef struct { const char *function, *path; size_t line, column; } MylangRunFrame;
typedef struct {
    int status; /* 0=value, 1=guest trap, 2=host failure (including Busy) */
    int64_t value;
    uint64_t steps;
    const char *code, *path;
    size_t line, column, frame_count, omitted_frames;
    MylangRunFrame frames[16];
} MylangRunResult;
/* Diagnostic strings remain valid while the generated library is loaded.
   Each call resets guest state and releases guest storage before returning.
   Calls sharing one generated program must not overlap; overlap returns Busy.
   Callbacks must return normally and obey the provider ABI's ownership rules.
   The result pointer is required and must not alias options or provider storage. */
int mylang_native_run_v1(const MylangRunOptions *options, MylangRunResult *result);
/* Scalar bits use unsigned magnitude for unsigned integers and sign-extended
   two's-complement bits for signed integers. Boolean bits are 0 or 1.
   Type names are exact builtin names, e.g. "i64" or "bool". */
typedef struct { const char *type; uint64_t bits; } MylangScalar;
typedef struct { MylangRunResult execution; MylangScalar value; } MylangCallResult;
/* Module-qualified exported function name; private functions and internal
   generic instances are unavailable. The current call ABI accepts builtin
   integer/Boolean signatures without references or capability parameters.
   Unsupported public signatures return UnsupportedSignature; unknown/private
   names return UnknownFunction. Invalid scalar types/ranges/counts return
   InvalidArgument. Arguments are borrowed only for the synchronous call.
   Result storage must not alias any call input or another active result. */
int mylang_native_call_v1(const char *name, const MylangScalar *arguments,
    size_t count, const MylangRunOptions *options, MylangCallResult *result);
/* Preorder value forest: one root per argument. Scalars have no children;
   records/arrays list fields/elements in schema order with bits=0; variants
   use bits as the declared case index and zero or one payload child.
   Node type names must match the checked schema exactly. */
typedef struct { const char *type; uint64_t bits; size_t children; } MylangWireNode;
typedef struct { MylangRunResult execution; size_t node_count; } MylangWireResult;
/* Copies ordinary values into guest storage and writes the returned tree into
   caller-owned output. On OutputTooSmall, node_count is the required capacity
   and output is unchanged; the function has already executed. Other failures
   leave node_count zero. Input/output/result/options must not alias.
   At most 100000 input/output nodes and 128 levels are supported. Domains and
   runtime identities are opaque until an explicit native codec ABI exists. */
int mylang_native_call_values_v1(const char *name, const MylangWireNode *arguments,
    size_t node_count, MylangWireNode *output, size_t capacity,
    const MylangRunOptions *options, MylangWireResult *result);
#endif
