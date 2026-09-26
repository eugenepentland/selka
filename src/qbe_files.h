#ifndef MYLANG_QBE_FILES_H
#define MYLANG_QBE_FILES_H
#include "native_bytes.h"
#include "qbe_runtime.h"
/* Whole-path helpers and open-handle methods, mirroring src/file_resources.zig
   over the native resource providers. A request word carries the operation
   ordinal in its low byte, the `open` mode letter in the next byte, and the
   text/binary payload choice in bit 16. */
enum { MYL_FILE_OPEN, MYL_FILE_READ_FILE, MYL_FILE_READ_TEXT, MYL_FILE_WRITE_FILE,
       MYL_FILE_WRITE_TEXT, MYL_FILE_EXISTS, MYL_FILE_LISTDIR, MYL_FILE_MKDIR, MYL_FILE_REMOVE };
enum { MYL_FILE_READ, MYL_FILE_READLINE, MYL_FILE_READLINES, MYL_FILE_WRITE, MYL_FILE_FLUSH, MYL_FILE_CLOSE };
/* Largest whole-file transfer, so one path cannot exhaust host memory. */
#define MYL_FILE_MAX_BYTES (64u * 1024u * 1024u)
/* Located trap for a refused file operation or a closed handle. */
void myl_qbe_fail_file(void *context);
/* Internal provider calls return fatal statuses until their C caller has freed
 * scratch and unpublished results. Public resource entries map them to traps. */
enum { MYL_RESOURCE_OOM = -1, MYL_RESOURCE_PROVIDER = -2,
       MYL_RESOURCE_OWNER = -3, MYL_RESOURCE_CAPABILITY = -4 };
int myl_qbe_resource_status(void *, int);
int myl_qbe_resource_try_new(void *, uint64_t, unsigned, const unsigned char *, size_t, myl_native_resource **);
int myl_qbe_resource_try_complete(void *, myl_native_resource *);
int myl_qbe_resource_try_read(void *, myl_native_resource *, unsigned char *, size_t, size_t *, int *);
int myl_qbe_resource_try_write(void *, myl_native_resource *, const unsigned char *, size_t, size_t *);
/* 0 publishes a success payload in *value, 1 an error message text, and -1 a
   sticky trap the caller detects with myl_qbe_failed. `exists` always reports 0
   and publishes its boolean. */
int myl_qbe_file_access(void *context, uint64_t authority, unsigned request, myl_native_text *path, const void *input, uint64_t *value);
/* 0 publishes the method's payload in *value; -1 means the R_FILE trap is set. */
int myl_qbe_file_method(void *context, void *owner, unsigned request, int64_t count, const void *input, uint64_t *value);
#endif
