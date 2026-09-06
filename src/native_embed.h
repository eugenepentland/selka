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
#endif
