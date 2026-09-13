#ifndef MYLANG_NATIVE_SCOPED_H
#define MYLANG_NATIVE_SCOPED_H
#include "native_providers.h"
/* Directory-relative filesystem provider for native executables, mirroring
   src/scoped_providers.zig: a request is `<mode>:<path>` with mode `r`, `w`,
   `c` (exclusive create), `t` (truncate existing), `a`, `m` (metadata),
   `l` (listing), `k` (create directory) or `x` (remove entry). A relative path
   is tried against each granted root in order and the first success wins.
   These grants are an authority boundary for guest source, not a sandbox. */
#define MYLANG_SCOPED_ROOTS 8
#define MYLANG_SCOPED_HANDLES 256
/* A direct root applies the whole path at once and follows symlinks, so a
   relative path resolves against that directory and an absolute path names
   itself; every other root walks the path component by component. */
typedef struct { int fd; int writable, direct; } MylangScopedRoot;
/* An open file, an append-mode file, or one immutable copied snapshot. */
typedef struct { int fd; unsigned char *snapshot; size_t length, position; unsigned char mode; } MylangScopedHandle;
typedef struct {
    MylangScopedRoot roots[MYLANG_SCOPED_ROOTS];
    size_t count;
    MylangScopedHandle handles[MYLANG_SCOPED_HANDLES];
} MylangScoped;
/* Reset every root and handle slot before the first grant. */
void mylang_scoped_init(MylangScoped *scoped);
/* Open one granted directory. Returns zero when it cannot be opened or when
   the grant limit is already reached; no guest file is acquired here. */
int mylang_scoped_grant(MylangScoped *scoped, const char *path, int writable);
/* Grant the working directory directly, the way an ordinary process sees it. */
int mylang_scoped_working_directory(MylangScoped *scoped);
/* Close every remaining handle and every granted directory. */
void mylang_scoped_close(MylangScoped *scoped);
/* Borrow this stable context as a resource provider with those permissions. */
MylangResourceProvider mylang_scoped_provider(MylangScoped *scoped, unsigned permissions);
#endif
