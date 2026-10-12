/* RUNTIME-THREADS-1: serialize complete capability/provider operations, including
   callbacks into a shared embedding provider and the handle/scratch registries.
   Nesting occurs through convenience wrappers and finalizers; only the outer
   operation takes the mutex. Startup freezes options before worker publication. */
static pthread_mutex_t core_io_mutex = PTHREAD_MUTEX_INITIALIZER;
static MYL_TLS unsigned core_io_depth;
static bool core_io_enter(void) {
    if (!core_parallel()) return false;
    if (core_io_depth++ == 0) pthread_mutex_lock(&core_io_mutex);
    return true;
}
static void core_io_leave(bool *active) {
    if (*active && --core_io_depth == 0) pthread_mutex_unlock(&core_io_mutex);
}
#define CORE_IO_GUARD bool core_io_guard __attribute__((cleanup(core_io_leave))) = core_io_enter()

static int core_io_utf8(const unsigned char *p,size_t n);
/* Core capability/provider/resource runtime. Algorithms ported from
 * native_scoped.c and qbe_stand_ins.c; no old runtime object or header is linked.
 * Authority and provider state use Core counted blocks; handles stay weakly
 * registered until closed, dropped or fatal process cleanup. */
#include <time.h>
typedef enum {
    CORE_IO_PROVIDER_OK = 0,
    CORE_IO_PROVIDER_UNAVAILABLE = 1,
    CORE_IO_PROVIDER_DENIED = 2,
    CORE_IO_PROVIDER_FAILED = 3,
    CORE_IO_PROVIDER_OUT_OF_MEMORY = 4,
    CORE_IO_PROVIDER_NO_CAPACITY = 5
} CoreIoProviderStatus;
/* The value member is meaningful only when status is CORE_IO_PROVIDER_OK. */
typedef struct { CoreIoProviderStatus status; int64_t value; } CoreIoClockResult;
typedef struct { CoreIoProviderStatus status; uint64_t value; } CoreIoRandomResult;
/* On success, present is 0 or 1; a present length fits the output capacity.
   Absent lengths and failed-result length/presence fields are ignored.
   Empty present values differ from absent values. Never report truncated success. */
typedef struct { CoreIoProviderStatus status; size_t length; int present; } CoreIoEnvironmentResult;
/* Acquisition success owns a handle; failure owns none. Completion success
   consumes it; completion failure keeps it core_io_scoped_live. Release never implies completion
   and must return without allocation, failure, or guest reentry. */
typedef struct { CoreIoProviderStatus status; uint64_t handle; } CoreIoResourceResult;
/* Transfers keep the handle core_io_scoped_live, including on errors. Success counts fit the
   borrowed buffer; read EOF is 0 or 1. Error count/EOF members are ignored. */
typedef struct { CoreIoProviderStatus status; size_t length; int eof; } CoreIoResourceRead;
typedef struct { CoreIoProviderStatus status; size_t length; } CoreIoResourceWrite;
typedef struct {
    void *context;
    unsigned permissions; /* read=1, write=2, core_io_scoped_complete=4; intersection only */
    CoreIoResourceResult (*acquire)(void *, const uint8_t *, size_t, unsigned);
    CoreIoProviderStatus (*complete)(void *, uint64_t);
    void (*release)(void *, uint64_t);
    CoreIoResourceRead (*read)(void *, uint64_t, uint8_t *, size_t);
    CoreIoResourceWrite (*write)(void *, uint64_t, const uint8_t *, size_t);
} CoreIoResourceProvider;

/* Copied preorder values. Nodes never contain guest addresses. Nominal names are
   exact compiler names; records/arrays have bits=0, variants have a tag in bits,
   domains have one backing-value child. Scalars have no children. */
typedef struct { const char *type; uint64_t bits; size_t children; } CoreIoHostNode;
typedef struct {
    const CoreIoHostNode *arguments;
    size_t argument_nodes;
    CoreIoHostNode *output;
    size_t capacity, output_nodes;
    uint64_t work_remaining;
    int exhausted;
} CoreIoHostCall;
/* Charge before effects. Failed charge is sticky even if a callback returns success. */
static inline int core_io_host_charge(CoreIoHostCall *call, uint64_t work) {
    if (call->exhausted || work > call->work_remaining) { call->exhausted=1;return 0; }
    call->work_remaining-=work;return 1;
}
/* Packed calls are an opt-in fast path for integers, padding-free fixed u8
   arrays and whole immutable `bytes` payloads. Every value points into
   runtime-owned scratch; callbacks may neither retain these copies nor reenter
   the generated program. Payloads have byte alignment only: use memcpy, never
   scalar pointer casts, to access integers.
   A fixed-shape output is runtime-owned scratch that starts zeroed and must
   keep its pointer and size; on success set output_written to exactly
   output.size. A `bytes` result is the one exception: the runtime hands over an
   empty output and the callback publishes its own read-only octets by setting
   output.bytes, output.size and an equal output_written. Those octets are
   copied into a fresh guest byte string before the runtime returns, so they
   need only outlive the callback, and the runtime never writes through them.
   A `bytes` argument arrives as a runtime-owned copy of the guest's octets
   whose size is that byte string's exact length. Return NULL or a static error
   name. */
typedef struct { void *bytes; size_t size; } CoreIoHostPackedValue;
typedef struct {
    const CoreIoHostPackedValue *arguments;
    size_t argument_count;
    CoreIoHostPackedValue output;
    size_t output_written;
    uint64_t work_remaining;
    int exhausted;
} CoreIoHostPackedCall;
static inline int core_io_host_packed_charge(CoreIoHostPackedCall *call, uint64_t work) {
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
    const char *(*invoke)(void *, CoreIoHostCall *);
    /* Optional packed-copy callback. The runtime uses it only after validating
       an all-scalar/fixed-u8-array/`bytes` schema and equivalent node/depth
       quotas; a declaration naming `bytes` has no node-bridge fallback. */
    const char *(*invoke_packed)(void *, CoreIoHostPackedCall *);
} CoreIoHostBinding;
typedef struct {
    const CoreIoHostBinding *bindings;
    size_t count;
    /* Zero selects 10000 calls, 1000000 work, 65536 nodes, 64 levels. */
    uint64_t max_calls, max_work;
    size_t max_values, max_depth;
    /* Ceiling on one copied `bytes` argument or published `bytes` result, in
       octets. Zero selects 1 MiB; above 64 MiB the registry is rejected. */
    size_t max_payload;
} CoreIoHostRegistry;

typedef struct {
    void *clock_context;CoreIoClockResult (*clock_now)(void *);
    void *random_context;CoreIoRandomResult (*random_u64)(void *);
    void *environment_context;CoreIoEnvironmentResult (*environment_get)(void *,const uint8_t *,size_t,uint8_t *,size_t);
    CoreIoResourceProvider filesystem,network;CoreIoHostRegistry host;
} CoreIoNativeProviders;
extern CoreIoNativeProviders mylang_native_providers_v7(void) __attribute__((weak));
static CoreIoNativeProviders core_io_native;
static int core_io_embedding;

/* Directory-relative filesystem provider for native executables, mirroring
   src/scoped_providers.zig: a request is `<mode>:<path>` with mode `r`, `w`,
   `c` (exclusive create), `t` (truncate existing), `a`, `m` (metadata),
   `l` (core_io_scoped_listing), `k` (create directory) or `x` (remove entry). A relative path
   is tried against each granted root in order and the first success wins.
   These grants are an authority boundary for guest source, not a sandbox. */
#define CORE_IO_SCOPED_ROOTS 8
#define CORE_IO_SCOPED_HANDLES 256
#define CORE_IO_SCOPED_ENDPOINTS 8
/* A direct root applies the whole path at once and follows symlinks, so a
   relative path resolves against that directory and an absolute path names
   itself; every other root walks the path component by component. */
typedef struct { int fd; int writable, direct; } CoreIoScopedRoot;
/* An open file, an append-mode file, or one immutable copied snapshot. */
typedef struct { int fd; unsigned char *snapshot; size_t length, position; unsigned char mode; } CoreIoScopedHandle;
/* One granted literal `IP:PORT` endpoint, or `*` for every literal peer. */
typedef struct { char *name; size_t length; } CoreIoScopedEndpoint;
typedef struct {
    CoreIoScopedRoot roots[CORE_IO_SCOPED_ROOTS];
    size_t count;
    CoreIoScopedHandle handles[CORE_IO_SCOPED_HANDLES];
    CoreIoScopedEndpoint endpoints[CORE_IO_SCOPED_ENDPOINTS];
    size_t endpoint_count;
} CoreIoScoped;
/* Reset every root, handle slot and endpoint before the first core_io_scoped_grant. */
void core_io_scoped_init(CoreIoScoped *scoped);
/* Open one granted directory. Returns zero when it cannot be opened or when
   the core_io_scoped_grant limit is already reached; no guest file is acquired here. */
int core_io_scoped_grant(CoreIoScoped *scoped, const char *path, int writable);
/* Grant the working directory directly, the way an ordinary process sees it. */
int core_io_scoped_working_directory(CoreIoScoped *scoped);
/* Record one literal `IP:PORT` endpoint (or `*`), rejecting a malformed or
   repeated value. Returns zero when the core_io_scoped_grant cannot be recorded. */
int core_io_scoped_endpoint(CoreIoScoped *scoped, const char *name);
/* Close every remaining handle and every granted directory. */
void core_io_scoped_close(CoreIoScoped *scoped);
/* Borrow this stable context as a resource provider with those permissions. */
CoreIoResourceProvider core_io_scoped_provider(CoreIoScoped *scoped, unsigned permissions);
/* Borrow the same context as a TCP provider that dials only the granted
   literal endpoints; reads and writes reuse the filesystem handle slots. */
CoreIoResourceProvider core_io_scoped_network_provider(CoreIoScoped *scoped, unsigned permissions);

/* Directory-relative filesystem provider, mirroring src/scoped_providers.zig
   and src/scoped_directory.zig: validated relative requests, per-root write
   authority, and bounded copied metadata and core_io_scoped_listing snapshots. */
#define CORE_IO_SCOPED__POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#define CORE_IO_SCOPED_TRANSFER_LIMIT (64u * 1024u)
#define CORE_IO_SCOPED_SNAPSHOT_BYTES (64u * 1024u)
#define CORE_IO_SCOPED_SNAPSHOT_ENTRIES 256u
#define CORE_IO_SCOPED_NAME_LIMIT 4094u
static CoreIoProviderStatus core_io_scoped_from_errno(void) {
    switch (errno) {
        case ENOMEM: return CORE_IO_PROVIDER_OUT_OF_MEMORY;
        case EACCES: case EPERM: case ELOOP: case ENOTDIR: return CORE_IO_PROVIDER_DENIED;
        default: return CORE_IO_PROVIDER_FAILED;
    }
}
static int core_io_scoped_writing_mode(unsigned char mode) {
    return mode == 'w' || mode == 'a' || mode == 'c' || mode == 't' || mode == 'k' || mode == 'x';
}
/* Reject traversal before anything is opened, created or truncated. */
static int core_io_scoped_valid_path(const char *path, size_t length, unsigned char mode) {
    if (!length) return mode == 'm' || mode == 'l';
    if (memchr(path, '\\', length) || memchr(path, 0, length)) return 0;
    size_t start = 0;
    for (size_t i = 0; i <= length; ++i) {
        if (i != length && path[i] != '/') continue;
        size_t part = i - start;
        if (!part || (part == 1 && path[start] == '.')) return 0;
        if (part == 2 && path[start] == '.' && path[start + 1] == '.') return 0;
        start = i + 1;
    }
    return 1;
}
static size_t core_io_scoped_free_slot(const CoreIoScoped *scoped) {
    for (size_t i = 0; i < CORE_IO_SCOPED_HANDLES; ++i)
        if (scoped->handles[i].fd < 0 && !scoped->handles[i].snapshot) return i;
    return SIZE_MAX;
}
/* Open the parent directory of the final component without following links.
   Returns the root itself for a single-component path; the caller closes any
   other descriptor. */
static int core_io_scoped_walk(int root, const char *path, size_t length, size_t *last) {
    int parent = root;
    size_t start = 0;
    for (size_t i = 0; i < length; ++i) {
        if (path[i] != '/') continue;
        char name[CORE_IO_SCOPED_NAME_LIMIT + 1];
        size_t part = i - start;
        if (part > CORE_IO_SCOPED_NAME_LIMIT) { errno = ENAMETOOLONG; goto failure; }
        memcpy(name, path + start, part);
        name[part] = 0;
        int child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (parent != root) close(parent);
        if (child < 0) return -1;
        parent = child;
        start = i + 1;
    }
    *last = start;
    return parent;
failure:
    if (parent != root) close(parent);
    return -1;
}
/* A scoped root opens its leaf without blocking, so a FIFO it is about to
   refuse cannot stall the guest waiting for a writer; the flag is cleared
   again once the leaf is known to be a regular file. The direct root blocks
   exactly as an ordinary `open` does. */
static int core_io_scoped_open_leaf(int parent, const char *name, unsigned char mode, int follow) {
    int waiting = follow ? 0 : O_NONBLOCK;
    if (mode == 'c') return openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | waiting, 0666);
    if (mode == 'a') return openat(parent, name, O_WRONLY | O_CREAT | O_CLOEXEC | waiting, 0666);
    int flags = mode == 'r' ? O_RDONLY : O_WRONLY;
    return openat(parent, name, flags | (follow ? 0 : O_NOFOLLOW) | O_CLOEXEC | waiting);
}
/* Whether a root may use the file `fd` opened. A scoped `--restrict` root serves
   regular files only. The default direct root carries the whole process's
   authority, so like C's `fopen` it also reads and writes a FIFO, a character
   device such as `/dev/null`, or a shell's process substitution `/dev/fd/N`; a
   directory is still refused there because it has no bytes to transfer. */
static int core_io_scoped_usable(CoreIoScopedRoot entry, int fd, const struct stat *info) {
    if (!entry.direct) return S_ISREG(info->st_mode) && fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) == 0;
    return !S_ISDIR(info->st_mode);
}
static unsigned char core_io_scoped_kind_of(mode_t value) {
    if (S_ISREG(value)) return 1;
    if (S_ISDIR(value)) return 2;
    if (S_ISLNK(value)) return 3;
    return 0;
}
/* Copy one directory's entries into a bounded snapshot: a leading 1, then a
   kind byte, a little-endian u16 name length and the name for each entry. */
static unsigned char *core_io_scoped_listing(int parent, const char *name, size_t *length, CoreIoProviderStatus *status) {
    int fd = openat(parent, *name ? name : ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) { *status = core_io_scoped_from_errno(); return NULL; }
    DIR *directory = fdopendir(fd);
    if (!directory) { *status = core_io_scoped_from_errno(); close(fd); return NULL; }
    size_t capacity = 1024, used = 1, count = 0;
    unsigned char *bytes = malloc(capacity);
    *status = CORE_IO_PROVIDER_OUT_OF_MEMORY;
    if (bytes) bytes[0] = 1;
    struct dirent *entry;
    while (bytes && (errno = 0, entry = readdir(directory))) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        size_t width = strlen(entry->d_name);
        if (count >= CORE_IO_SCOPED_SNAPSHOT_ENTRIES || !width || width > CORE_IO_SCOPED_NAME_LIMIT) { *status = CORE_IO_PROVIDER_DENIED; free(bytes); bytes = NULL; break; }
        if (used > CORE_IO_SCOPED_SNAPSHOT_BYTES || width + 3 > CORE_IO_SCOPED_SNAPSHOT_BYTES - used) { *status = CORE_IO_PROVIDER_DENIED; free(bytes); bytes = NULL; break; }
        while (used + width + 3 > capacity) {
            unsigned char *grown = realloc(bytes, capacity * 2);
            if (!grown) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; free(bytes); bytes = NULL; break; }
            bytes = grown;
            capacity *= 2;
        }
        if (!bytes) break;
        struct stat info;
        unsigned char kind = 0;
        if (!fstatat(dirfd(directory), entry->d_name, &info, AT_SYMLINK_NOFOLLOW)) kind = core_io_scoped_kind_of(info.st_mode);
        bytes[used++] = kind;
        bytes[used++] = (unsigned char)(width & 0xff);
        bytes[used++] = (unsigned char)((width >> 8) & 0xff);
        memcpy(bytes + used, entry->d_name, width);
        used += width;
        count++;
    }
    closedir(directory);
    if (!bytes) return NULL;
    *status = CORE_IO_PROVIDER_OK;
    *length = used;
    return bytes;
}
/* One acknowledged core_io_scoped_change or metadata read, published as an immutable snapshot. */
static unsigned char *core_io_scoped_change(int parent, const char *name, unsigned char mode, size_t *length, CoreIoProviderStatus *status) {
    struct stat info;
    if (mode == 'm') {
        int failed = *name ? fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) : fstat(parent, &info);
        if (failed) { *status = core_io_scoped_from_errno(); return NULL; }
        unsigned char *bytes = malloc(10);
        if (!bytes) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
        bytes[0] = 1;
        bytes[1] = core_io_scoped_kind_of(info.st_mode);
        for (unsigned i = 0; i < 8; ++i) bytes[2 + i] = (unsigned char)(((uint64_t)info.st_size >> (8 * i)) & 0xff);
        *status = CORE_IO_PROVIDER_OK;
        *length = 10;
        return bytes;
    }
    if (!*name) { *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    if (mode == 'k') {
        if (mkdirat(parent, name, 0777)) { *status = core_io_scoped_from_errno(); return NULL; }
    } else if (unlinkat(parent, name, 0)) {
        if (errno != EISDIR && errno != EPERM) { *status = core_io_scoped_from_errno(); return NULL; }
        if (unlinkat(parent, name, AT_REMOVEDIR)) { *status = core_io_scoped_from_errno(); return NULL; }
    }
    unsigned char *bytes = malloc(1);
    if (!bytes) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    bytes[0] = 1;
    *status = CORE_IO_PROVIDER_OK;
    *length = 1;
    return bytes;
}
static CoreIoResourceResult core_io_scoped_acquire_in(CoreIoScoped *scoped, CoreIoScopedRoot entry, unsigned char mode, const char *path, size_t length) {
    CoreIoResourceResult result = {CORE_IO_PROVIDER_FAILED, 0};
    int root = entry.fd;
    size_t slot = core_io_scoped_free_slot(scoped);
    if (slot == SIZE_MAX) { result.status = CORE_IO_PROVIDER_DENIED; return result; }
    size_t last = 0;
    /* A direct root hands the whole path to one operation, the way an ordinary
       process resolves it; a scoped root opens each component without symlinks. */
    int parent = entry.direct ? root : core_io_scoped_walk(root, path, length, &last);
    if (parent < 0) { result.status = core_io_scoped_from_errno(); return result; }
    char name[CORE_IO_SCOPED_NAME_LIMIT + 1];
    size_t width = length - last;
    if (width > CORE_IO_SCOPED_NAME_LIMIT) { if (parent != root) close(parent); result.status = CORE_IO_PROVIDER_DENIED; return result; }
    memcpy(name, path + last, width);
    name[width] = 0;
    if (mode == 'm' || mode == 'l' || mode == 'k' || mode == 'x') {
        size_t bytes = 0;
        unsigned char *snapshot = mode == 'l' ? core_io_scoped_listing(parent, name, &bytes, &result.status) : core_io_scoped_change(parent, name, mode, &bytes, &result.status);
        if (parent != root) close(parent);
        if (!snapshot) return result;
        scoped->handles[slot] = (CoreIoScopedHandle){-1, snapshot, bytes, 0, mode};
        result.handle = slot;
        return result;
    }
    int fd = core_io_scoped_open_leaf(parent, name, mode, entry.direct);
    if (parent != root) close(parent);
    if (fd < 0) { result.status = core_io_scoped_from_errno(); return result; }
    struct stat info;
    if (fstat(fd, &info)) { result.status = core_io_scoped_from_errno(); close(fd); return result; }
    if (!core_io_scoped_usable(entry, fd, &info)) { result.status = CORE_IO_PROVIDER_DENIED; close(fd); return result; }
    /* Only a regular file has contents to truncate; a FIFO or device has none. */
    if (mode == 't' && S_ISREG(info.st_mode) && ftruncate(fd, 0)) { result.status = core_io_scoped_from_errno(); close(fd); return result; }
    scoped->handles[slot] = (CoreIoScopedHandle){fd, NULL, 0, 0, mode};
    result.status = CORE_IO_PROVIDER_OK;
    result.handle = slot;
    return result;
}
static CoreIoResourceResult core_io_scoped_acquire(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    CoreIoScoped *scoped = context;
    CoreIoResourceResult result = {CORE_IO_PROVIDER_DENIED, 0};
    if (!scoped->count) { result.status = CORE_IO_PROVIDER_UNAVAILABLE; return result; }
    if (length < 2 || length > 4096 || request[1] != ':') return result;
    unsigned char mode = request[0];
    int reading = mode == 'r' || mode == 'm' || mode == 'l';
    if (!reading && !core_io_scoped_writing_mode(mode)) return result;
    if (!(permissions & (reading ? 1u : 2u))) return result;
    const char *path = (const char *)request + 2;
    size_t width = length - 2;
    CoreIoProviderStatus failure = CORE_IO_PROVIDER_DENIED;
    for (size_t i = 0; i < scoped->count; ++i) {
        if (core_io_scoped_writing_mode(mode) && !scoped->roots[i].writable) continue;
        if (!scoped->roots[i].direct && !core_io_scoped_valid_path(path, width, mode)) continue;
        CoreIoResourceResult attempt = core_io_scoped_acquire_in(scoped, scoped->roots[i], mode, path, width);
        if (attempt.status == CORE_IO_PROVIDER_OK || attempt.status == CORE_IO_PROVIDER_OUT_OF_MEMORY) return attempt;
        failure = attempt.status;
    }
    result.status = failure;
    return result;
}
static void core_io_scoped_shut(CoreIoScopedHandle *handle) {
    if (handle->fd >= 0) close(handle->fd);
    free(handle->snapshot);
    *handle = (CoreIoScopedHandle){-1, NULL, 0, 0, 0};
}
static CoreIoScopedHandle *core_io_scoped_live(CoreIoScoped *scoped, uint64_t id) {
    if (id >= CORE_IO_SCOPED_HANDLES) return NULL;
    CoreIoScopedHandle *handle = &scoped->handles[id];
    return handle->fd >= 0 || handle->snapshot ? handle : NULL;
}
static CoreIoProviderStatus core_io_scoped_complete(void *context, uint64_t id) {
    CoreIoScopedHandle *handle = core_io_scoped_live(context, id);
    if (!handle) return CORE_IO_PROVIDER_FAILED;
    core_io_scoped_shut(handle);
    return CORE_IO_PROVIDER_OK;
}
static void core_io_scoped_release(void *context, uint64_t id) {
    CoreIoScopedHandle *handle = core_io_scoped_live(context, id);
    if (handle) core_io_scoped_shut(handle);
}
static CoreIoResourceRead core_io_scoped_read_handle(void *context, uint64_t id, uint8_t *output, size_t capacity) {
    CoreIoResourceRead result = {CORE_IO_PROVIDER_FAILED, 0, 0};
    CoreIoScopedHandle *handle = core_io_scoped_live(context, id);
    if (!handle) return result;
    /* A zero-size callback does not probe EOF, including immutable snapshots. */
    if (!capacity) { result.status = CORE_IO_PROVIDER_OK; return result; }
    if (capacity > CORE_IO_SCOPED_TRANSFER_LIMIT) capacity = CORE_IO_SCOPED_TRANSFER_LIMIT;
    if (handle->snapshot) {
        size_t available = handle->length - handle->position;
        size_t width = available < capacity ? available : capacity;
        memcpy(output, handle->snapshot + handle->position, width);
        handle->position += width;
        result.status = CORE_IO_PROVIDER_OK;
        result.length = width;
        result.eof = handle->position == handle->length;
        return result;
    }
    if (handle->mode == 'a') { result.status = CORE_IO_PROVIDER_DENIED; return result; }
    ssize_t width = read(handle->fd, output, capacity);
    if (width < 0) { result.status = core_io_scoped_from_errno(); return result; }
    result.status = CORE_IO_PROVIDER_OK;
    result.length = (size_t)width;
    result.eof = width == 0;
    return result;
}
static CoreIoResourceWrite core_io_scoped_write_handle(void *context, uint64_t id, const uint8_t *input, size_t length) {
    CoreIoResourceWrite result = {CORE_IO_PROVIDER_FAILED, 0};
    CoreIoScopedHandle *handle = core_io_scoped_live(context, id);
    if (!handle || handle->snapshot) { result.status = handle ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return result; }
    if (length > CORE_IO_SCOPED_TRANSFER_LIMIT) length = CORE_IO_SCOPED_TRANSFER_LIMIT;
    ssize_t width;
    if (handle->mode == 'a') {
        off_t end = lseek(handle->fd, 0, SEEK_END);
        if (end < 0) { result.status = core_io_scoped_from_errno(); return result; }
        width = pwrite(handle->fd, input, length, end);
    } else width = write(handle->fd, input, length);
    if (width < 0) { result.status = core_io_scoped_from_errno(); return result; }
    result.status = CORE_IO_PROVIDER_OK;
    result.length = (size_t)width;
    return result;
}
/* Parse one literal `IP:PORT` into a numeric address. No name resolution or
   redirect following occurs, so the core_io_scoped_grant and the connect name the same peer. */
static int core_io_scoped_endpoint_address(const char *name, struct sockaddr_in *address) {
    const char *colon = strrchr(name, ':');
    if (!colon || colon == name) return 0;
    char host[64];
    size_t width = (size_t)(colon - name);
    if (width >= sizeof host) return 0;
    memcpy(host, name, width);
    host[width] = 0;
    unsigned long port = strtoul(colon + 1, NULL, 10);
    if (!port || port > 65535) return 0;
    struct sockaddr_in parsed;
    memset(&parsed, 0, sizeof parsed);
    parsed.sin_family = AF_INET;
    parsed.sin_port = htons((unsigned short)port);
    if (inet_pton(AF_INET, host, &parsed.sin_addr) != 1) return 0;
    *address = parsed;
    return 1;
}
/* An allowlist entry is matched verbatim; `*` names every literal peer. */
static int core_io_scoped_endpoint_allowed(const CoreIoScoped *scoped, const char *name, size_t length) {
    for (size_t i = 0; i < scoped->endpoint_count; ++i) {
        const CoreIoScopedEndpoint *entry = &scoped->endpoints[i];
        if (entry->length == 1 && entry->name[0] == '*') return 1;
        if (entry->length == length && !memcmp(entry->name, name, length)) return 1;
    }
    return 0;
}
static int core_io_scoped_dial(const char *name) {
    struct sockaddr_in address;
    if (!core_io_scoped_endpoint_address(name, &address)) return -1;
    int handle = socket(AF_INET, SOCK_STREAM, 0);
    if (handle < 0) return -1;
    if (connect(handle, (struct sockaddr *)&address, sizeof address)) { close(handle); return -1; }
    return handle;
}
/* A narrowed Network substitutes its scoped endpoint for the guest request, so
   core_io_scoped_acquire sees exactly the literals the command line granted. */
static CoreIoResourceResult core_io_scoped_acquire_network(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    CoreIoScoped *scoped = context;
    CoreIoResourceResult result = {CORE_IO_PROVIDER_DENIED, 0};
    if (!scoped->endpoint_count) { result.status = CORE_IO_PROVIDER_UNAVAILABLE; return result; }
    if (!(permissions & (1u | 2u))) return result;
    char name[128];
    if (length >= sizeof name) return result;
    memcpy(name, request, length);
    name[length] = 0;
    if (!core_io_scoped_endpoint_allowed(scoped, name, length)) return result;
    size_t slot = core_io_scoped_free_slot(scoped);
    if (slot == SIZE_MAX) { result.status = CORE_IO_PROVIDER_DENIED; return result; }
    int handle = core_io_scoped_dial(name);
    if (handle < 0) { result.status = CORE_IO_PROVIDER_FAILED; return result; }
    scoped->handles[slot] = (CoreIoScopedHandle){handle, NULL, 0, 0, 0};
    result.status = CORE_IO_PROVIDER_OK;
    result.handle = slot;
    return result;
}
/* Record one literal endpoint (or `*`) before the first acquisition. */
int core_io_scoped_endpoint(CoreIoScoped *scoped, const char *name) {
    size_t length = strlen(name);
    if (!length || length > 4096 || scoped->endpoint_count >= CORE_IO_SCOPED_ENDPOINTS) return 0;
    if (!(length == 1 && name[0] == '*')) {
        struct sockaddr_in address;
        if (!core_io_scoped_endpoint_address(name, &address)) return 0;
    }
    for (size_t i = 0; i < scoped->endpoint_count; ++i) {
        const CoreIoScopedEndpoint *entry = &scoped->endpoints[i];
        if (entry->length == length && !memcmp(entry->name, name, length)) return 0;
    }
    char *copy = malloc(length + 1);
    if (!copy) return 0;
    memcpy(copy, name, length);
    copy[length] = 0;
    scoped->endpoints[scoped->endpoint_count].name = copy;
    scoped->endpoints[scoped->endpoint_count].length = length;
    scoped->endpoint_count++;
    return 1;
}
CoreIoResourceProvider core_io_scoped_network_provider(CoreIoScoped *scoped, unsigned permissions) {

    CoreIoResourceProvider provider = {0};
    provider.context = scoped;
    provider.permissions = permissions;
    provider.acquire = core_io_scoped_acquire_network;
    provider.complete = core_io_scoped_complete;
    provider.release = core_io_scoped_release;
    provider.read = core_io_scoped_read_handle;
    provider.write = core_io_scoped_write_handle;
    return provider;
}
void core_io_scoped_init(CoreIoScoped *scoped) {
    memset(scoped, 0, sizeof *scoped);
    for (size_t i = 0; i < CORE_IO_SCOPED_HANDLES; ++i) scoped->handles[i].fd = -1;
}
static int core_io_scoped_grant_impl(CoreIoScoped *scoped, const char *path, int writable, int direct) {
    if (scoped->count >= CORE_IO_SCOPED_ROOTS) return 0;
    int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return 0;
    scoped->roots[scoped->count++] = (CoreIoScopedRoot){fd, writable, direct};
    return 1;
}
int core_io_scoped_grant(CoreIoScoped *scoped, const char *path, int writable) {
    return core_io_scoped_grant_impl(scoped, path, writable, 0);
}
int core_io_scoped_working_directory(CoreIoScoped *scoped) {
    return core_io_scoped_grant_impl(scoped, ".", 1, 1);
}
void core_io_scoped_close(CoreIoScoped *scoped) {
    for (size_t i = 0; i < CORE_IO_SCOPED_HANDLES; ++i)
        if (scoped->handles[i].fd >= 0 || scoped->handles[i].snapshot) core_io_scoped_shut(&scoped->handles[i]);
    for (size_t i = 0; i < scoped->count; ++i) close(scoped->roots[i].fd);
    scoped->count = 0;
    for (size_t i = 0; i < scoped->endpoint_count; ++i) free(scoped->endpoints[i].name);
    scoped->endpoint_count = 0;
}
CoreIoResourceProvider core_io_scoped_provider(CoreIoScoped *scoped, unsigned permissions) {

    CoreIoResourceProvider provider = {0};
    provider.context = scoped;
    provider.permissions = permissions;
    provider.acquire = core_io_scoped_acquire;
    provider.complete = core_io_scoped_complete;
    provider.release = core_io_scoped_release;
    provider.read = core_io_scoped_read_handle;
    provider.write = core_io_scoped_write_handle;
    return provider;
}

/* Bounds shared with the host-granted surface. */
#define CORE_IO_MEMORY_NAME_LIMIT 128u
#define CORE_IO_MEMORY_VALUE_LIMIT 16384u
#define CORE_IO_MEMORY_NAMES_LIMIT 64u
#define CORE_IO_MEMORY_MEMORY_HANDLES 256u
#define CORE_IO_MEMORY_MEMORY_BYTES (64u * 1024u * 1024u)
#define CORE_IO_MEMORY_PATH_LIMIT 4094u
#define CORE_IO_MEMORY_SNAPSHOT_BYTES (64u * 1024u)
#define CORE_IO_MEMORY_SNAPSHOT_ENTRIES 256u

/* One file or directory of an in-memory filesystem, named by its full
   relative path. An entry removed while a handle holds it stays allocated
   until that handle is released, as an unlinked POSIX file does. */
typedef struct MemoryEntry {
    char *path;
    size_t length;
    int directory, unlinked;
    unsigned char *bytes;
    size_t size, capacity;
    unsigned open;
} MemoryEntry;
/* An open file (entry, position, mode) or one immutable copied snapshot. */
typedef struct { int core_io_memory_live; MemoryEntry *entry; unsigned char *snapshot; size_t length, position; unsigned char mode; } MemoryHandle;
typedef struct {
    MemoryEntry **entries;
    size_t count, capacity, bytes;
    MemoryHandle handles[CORE_IO_MEMORY_MEMORY_HANDLES];
} MemoryFs;

/* ---- in-memory filesystem ------------------------------------------------ */

/* The scoped-root path rule: relative, no empty, `.` or `..` component, no NUL
   or backslash. An empty path names the root and only metadata/core_io_memory_listing take it. */
static int core_io_memory_valid_path(const unsigned char *path, size_t length, unsigned char mode) {
    if (!length) return mode == 'm' || mode == 'l';
    if (length > CORE_IO_MEMORY_PATH_LIMIT || memchr(path, '\\', length) || memchr(path, 0, length)) return 0;
    size_t start = 0;
    for (size_t i = 0; i <= length; ++i) {
        if (i != length && path[i] != '/') continue;
        size_t part = i - start;
        if (!part || (part == 1 && path[start] == '.')) return 0;
        if (part == 2 && path[start] == '.' && path[start + 1] == '.') return 0;
        start = i + 1;
    }
    return 1;
}
static MemoryEntry *core_io_memory_find(MemoryFs *memory, const unsigned char *path, size_t length) {
    for (size_t i = 0; i < memory->count; ++i) {
        MemoryEntry *entry = memory->entries[i];
        if (entry->length == length && !memcmp(entry->path, path, length)) return entry;
    }
    return NULL;
}
/* Whether every ancestor of `path` is an existing directory: OK, FAILED for a
   missing one, DENIED for one that is a file (POSIX ENOENT and ENOTDIR). */
static CoreIoProviderStatus core_io_memory_parents(MemoryFs *memory, const unsigned char *path, size_t length) {
    for (size_t i = 0; i < length; ++i) {
        if (path[i] != '/') continue;
        MemoryEntry *ancestor = core_io_memory_find(memory, path, i);
        if (!ancestor) return CORE_IO_PROVIDER_FAILED;
        if (!ancestor->directory) return CORE_IO_PROVIDER_DENIED;
    }
    return CORE_IO_PROVIDER_OK;
}
static MemoryEntry *core_io_memory_create(MemoryFs *memory, const unsigned char *path, size_t length, int directory) {
    if (memory->count == memory->capacity) {
        size_t grown = memory->capacity ? memory->capacity * 2 : 16;
        MemoryEntry **entries = realloc(memory->entries, grown * sizeof *entries);
        if (!entries) return NULL;
        memory->entries = entries;
        memory->capacity = grown;
    }
    MemoryEntry *entry = calloc(1, sizeof *entry);
    char *copy = malloc(length + 1);
    if (!entry || !copy) { free(entry); free(copy); return NULL; }
    memcpy(copy, path, length);
    copy[length] = 0;
    entry->path = copy;
    entry->length = length;
    entry->directory = directory;
    memory->entries[memory->count++] = entry;
    return entry;
}
static void core_io_memory_entry_free(MemoryEntry *entry) {
    free(entry->path);
    free(entry->bytes);
    free(entry);
}
static void core_io_memory_unlink_entry(MemoryFs *memory, MemoryEntry *entry) {
    for (size_t i = 0; i < memory->count; ++i) {
        if (memory->entries[i] != entry) continue;
        memory->entries[i] = memory->entries[--memory->count];
        break;
    }
    memory->bytes -= entry->size;
    if (entry->open) entry->unlinked = 1;
    else core_io_memory_entry_free(entry);
}
static int core_io_memory_has_children(MemoryFs *memory, const MemoryEntry *directory) {
    for (size_t i = 0; i < memory->count; ++i) {
        const MemoryEntry *entry = memory->entries[i];
        if (entry->length > directory->length && entry->path[directory->length] == '/' && !memcmp(entry->path, directory->path, directory->length)) return 1;
    }
    return 0;
}
static size_t core_io_memory_free_handle(const MemoryFs *memory) {
    for (size_t i = 0; i < CORE_IO_MEMORY_MEMORY_HANDLES; ++i) if (!memory->handles[i].core_io_memory_live) return i;
    return SIZE_MAX;
}
/* The final component of an entry's path, which is how a core_io_memory_listing names it. */
static const char *core_io_memory_leaf(const MemoryEntry *entry, size_t *width) {
    const char *slash = NULL;
    for (size_t i = 0; i < entry->length; ++i) if (entry->path[i] == '/') slash = entry->path + i;
    const char *start = slash ? slash + 1 : entry->path;
    *width = entry->length - (size_t)(start - entry->path);
    return start;
}
static int core_io_memory_in_directory(const MemoryEntry *entry, const unsigned char *path, size_t length) {
    if (!length) return !memchr(entry->path, '/', entry->length);
    if (entry->length <= length + 1 || entry->path[length] != '/' || memcmp(entry->path, path, length)) return 0;
    return !memchr(entry->path + length + 1, '/', entry->length - length - 1);
}
static int core_io_memory_leaf_order(const void *a, const void *b) {
    size_t left_width, right_width;
    const char *left = core_io_memory_leaf(*(MemoryEntry *const *)a, &left_width), *right = core_io_memory_leaf(*(MemoryEntry *const *)b, &right_width);
    size_t shortest = left_width < right_width ? left_width : right_width;
    int order = shortest ? memcmp(left, right, shortest) : 0;
    if (order) return order;
    return left_width < right_width ? -1 : left_width > right_width ? 1 : 0;
}
/* The same snapshot the scoped provider publishes: a leading 1, then a kind
   byte, a little-endian u16 name length and the name per entry. Entries are
   sorted by name, so a core_io_memory_listing never depends on insertion order. */
static unsigned char *core_io_memory_listing(MemoryFs *memory, const unsigned char *path, size_t length, size_t *size, CoreIoProviderStatus *status) {
    if (length) {
        MemoryEntry *directory = core_io_memory_find(memory, path, length);
        if (!directory) { *status = CORE_IO_PROVIDER_FAILED; return NULL; }
        if (!directory->directory) { *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    }
    MemoryEntry **children = malloc((memory->count ? memory->count : 1) * sizeof *children);
    if (!children) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    size_t count = 0, bytes = 1;
    for (size_t i = 0; i < memory->count; ++i) {
        if (!core_io_memory_in_directory(memory->entries[i], path, length)) continue;
        size_t width;
        (void)core_io_memory_leaf(memory->entries[i], &width);
        children[count++] = memory->entries[i];
        bytes += width + 3;
    }
    if (count > CORE_IO_MEMORY_SNAPSHOT_ENTRIES || bytes > CORE_IO_MEMORY_SNAPSHOT_BYTES) { free(children); *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    qsort(children, count, sizeof *children, core_io_memory_leaf_order);
    unsigned char *snapshot = malloc(bytes);
    if (!snapshot) { free(children); *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    size_t used = 0;
    snapshot[used++] = 1;
    for (size_t i = 0; i < count; ++i) {
        size_t width;
        const char *name = core_io_memory_leaf(children[i], &width);
        snapshot[used++] = children[i]->directory ? 2 : 1;
        snapshot[used++] = (unsigned char)(width & 0xff);
        snapshot[used++] = (unsigned char)((width >> 8) & 0xff);
        memcpy(snapshot + used, name, width);
        used += width;
    }
    free(children);
    *status = CORE_IO_PROVIDER_OK;
    *size = used;
    return snapshot;
}
/* Metadata (`m`), `mkdir` (`k`) and `remove` (`x`) as one acknowledged snapshot. */
static unsigned char *core_io_memory_change(MemoryFs *memory, const unsigned char *path, size_t length, unsigned char mode, size_t *size, CoreIoProviderStatus *status) {
    MemoryEntry *entry = length ? core_io_memory_find(memory, path, length) : NULL;
    *status = CORE_IO_PROVIDER_OK;
    if (mode == 'm') {
        if (length && !entry) { *status = core_io_memory_parents(memory, path, length) == CORE_IO_PROVIDER_DENIED ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return NULL; }
        unsigned char *bytes = malloc(10);
        if (!bytes) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
        bytes[0] = 1;
        bytes[1] = !entry || entry->directory ? 2 : 1;
        uint64_t width = entry ? entry->size : 0;
        for (unsigned i = 0; i < 8; ++i) bytes[2 + i] = (unsigned char)((width >> (8 * i)) & 0xff);
        *size = 10;
        return bytes;
    }
    if (!length) { *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    if (mode == 'k') {
        CoreIoProviderStatus chain = core_io_memory_parents(memory, path, length);
        if (chain != CORE_IO_PROVIDER_OK) { *status = chain; return NULL; }
        if (entry) { *status = CORE_IO_PROVIDER_FAILED; return NULL; }
        if (!core_io_memory_create(memory, path, length, 1)) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    } else {
        if (!entry) { *status = core_io_memory_parents(memory, path, length) == CORE_IO_PROVIDER_DENIED ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return NULL; }
        if (entry->directory && core_io_memory_has_children(memory, entry)) { *status = CORE_IO_PROVIDER_FAILED; return NULL; }
        core_io_memory_unlink_entry(memory, entry);
    }
    unsigned char *bytes = malloc(1);
    if (!bytes) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    bytes[0] = 1;
    *size = 1;
    return bytes;
}
/* Open a file entry for `r`, `c` (exclusive core_io_memory_create), `t` (truncate an existing
   file) or `a` (append, creating it), with the POSIX outcome of each. */
static MemoryEntry *core_io_memory_open_file(MemoryFs *memory, const unsigned char *path, size_t length, unsigned char mode, CoreIoProviderStatus *status) {
    CoreIoProviderStatus chain = core_io_memory_parents(memory, path, length);
    if (chain != CORE_IO_PROVIDER_OK) { *status = chain; return NULL; }
    MemoryEntry *entry = core_io_memory_find(memory, path, length);
    if (entry && entry->directory) { *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    if (mode == 'c' && entry) { *status = CORE_IO_PROVIDER_FAILED; return NULL; }
    if ((mode == 'r' || mode == 't') && !entry) { *status = CORE_IO_PROVIDER_FAILED; return NULL; }
    if (!entry) {
        entry = core_io_memory_create(memory, path, length, 0);
        if (!entry) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    }
    if (mode == 't') { memory->bytes -= entry->size; entry->size = 0; }
    *status = CORE_IO_PROVIDER_OK;
    return entry;
}
static CoreIoResourceResult core_io_memory_acquire(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    MemoryFs *memory = context;
    CoreIoResourceResult result = {CORE_IO_PROVIDER_DENIED, 0};
    if (length < 2 || length > CORE_IO_MEMORY_PATH_LIMIT + 2 || request[1] != ':') return result;
    unsigned char mode = request[0];
    int reading = mode == 'r' || mode == 'm' || mode == 'l';
    int writing = mode == 'c' || mode == 't' || mode == 'a' || mode == 'k' || mode == 'x';
    if ((!reading && !writing) || !(permissions & (reading ? 1u : 2u))) return result;
    const unsigned char *path = request + 2;
    size_t width = length - 2;
    if (!core_io_memory_valid_path(path, width, mode)) return result;
    size_t slot = core_io_memory_free_handle(memory);
    if (slot == SIZE_MAX) return result;
    MemoryHandle *handle = &memory->handles[slot];
    if (mode == 'm' || mode == 'l' || mode == 'k' || mode == 'x') {
        size_t size = 0;
        unsigned char *snapshot = mode == 'l' ? core_io_memory_listing(memory, path, width, &size, &result.status) : core_io_memory_change(memory, path, width, mode, &size, &result.status);
        if (!snapshot) return result;
        *handle = (MemoryHandle){1, NULL, snapshot, size, 0, mode};
        result.handle = slot;
        return result;
    }
    MemoryEntry *entry = core_io_memory_open_file(memory, path, width, mode, &result.status);
    if (!entry) return result;
    entry->open++;
    *handle = (MemoryHandle){1, entry, NULL, 0, 0, mode};
    result.handle = slot;
    return result;
}
static MemoryHandle *core_io_memory_live(MemoryFs *memory, uint64_t id) {
    if (id >= CORE_IO_MEMORY_MEMORY_HANDLES || !memory->handles[id].core_io_memory_live) return NULL;
    return &memory->handles[id];
}
static void core_io_memory_shut(MemoryHandle *handle) {
    if (handle->entry) {
        handle->entry->open--;
        if (handle->entry->unlinked && !handle->entry->open) core_io_memory_entry_free(handle->entry);
    }
    free(handle->snapshot);
    *handle = (MemoryHandle){0, NULL, NULL, 0, 0, 0};
}
static CoreIoProviderStatus core_io_memory_complete(void *context, uint64_t id) {
    MemoryHandle *handle = core_io_memory_live(context, id);
    if (!handle) return CORE_IO_PROVIDER_FAILED;
    core_io_memory_shut(handle);
    return CORE_IO_PROVIDER_OK;
}
static void core_io_memory_release(void *context, uint64_t id) {
    MemoryHandle *handle = core_io_memory_live(context, id);
    if (handle) core_io_memory_shut(handle);
}
static CoreIoResourceRead core_io_memory_read(void *context, uint64_t id, uint8_t *output, size_t capacity) {
    CoreIoResourceRead result = {CORE_IO_PROVIDER_FAILED, 0, 0};
    MemoryHandle *handle = core_io_memory_live(context, id);
    if (!handle) return result;
    if (!capacity) { result.status = CORE_IO_PROVIDER_OK; return result; }
    const unsigned char *bytes = handle->snapshot;
    size_t total = handle->length;
    if (handle->entry) {
        if (handle->mode != 'r') { result.status = handle->mode == 'a' ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return result; }
        bytes = handle->entry->bytes;
        total = handle->entry->size;
    }
    size_t available = handle->position < total ? total - handle->position : 0;
    size_t width = available < capacity ? available : capacity;
    if (width) memcpy(output, bytes + handle->position, width);
    handle->position += width;
    result.status = CORE_IO_PROVIDER_OK;
    result.length = width;
    result.eof = handle->position >= total;
    return result;
}
static CoreIoResourceWrite core_io_memory_write(void *context, uint64_t id, const uint8_t *input, size_t length) {
    MemoryFs *memory = context;
    CoreIoResourceWrite result = {CORE_IO_PROVIDER_FAILED, 0};
    MemoryHandle *handle = core_io_memory_live(memory, id);
    if (!handle || !handle->entry) { result.status = handle ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return result; }
    if (handle->mode == 'r') return result;
    MemoryEntry *entry = handle->entry;
    size_t at = handle->mode == 'a' ? entry->size : handle->position;
    if (at > entry->size || length > CORE_IO_MEMORY_MEMORY_BYTES - memory->bytes || at + length > CORE_IO_MEMORY_MEMORY_BYTES) return result;
    size_t end = at + length;
    if (end > entry->capacity) {
        size_t grown = entry->capacity ? entry->capacity : 64;
        while (grown < end) grown *= 2;
        unsigned char *bytes = realloc(entry->bytes, grown);
        if (!bytes) { result.status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return result; }
        entry->bytes = bytes;
        entry->capacity = grown;
    }
    if (length) memcpy(entry->bytes + at, input, length);
    if (end > entry->size) {
        if (!entry->unlinked) memory->bytes += end - entry->size;
        entry->size = end;
    }
    handle->position = end;
    result.status = CORE_IO_PROVIDER_OK;
    result.length = length;
    return result;
}
static void core_io_memory_free(MemoryFs *memory) {
    for (size_t i = 0; i < CORE_IO_MEMORY_MEMORY_HANDLES; ++i) if (memory->handles[i].core_io_memory_live) core_io_memory_shut(&memory->handles[i]);
    for (size_t i = 0; i < memory->count; ++i) core_io_memory_entry_free(memory->entries[i]);
    free(memory->entries);
    free(memory);
}
/* A stand-in `Network` has no endpoint to reach; qbe_resources.c answers every
   acquisition with MYL_QBE_STAND_IN_DENIED before this would run. */
static CoreIoResourceResult core_io_memory_network_acquire(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    (void)context; (void)request; (void)length; (void)permissions;
    CoreIoResourceResult result = {CORE_IO_PROVIDER_DENIED, 0};
    return result;
}
static CoreIoProviderStatus core_io_memory_network_complete(void *context, uint64_t id) { (void)context; (void)id; return CORE_IO_PROVIDER_FAILED; }
static void core_io_memory_network_release(void *context, uint64_t id) { (void)context; (void)id; }

/* ---- environment ---------------------------------------------------------- */

/* Walk one NUL-terminated core_io_memory_field of a blob; returns its length or SIZE_MAX. */
static size_t core_io_memory_field(const unsigned char *blob, size_t length, size_t cursor) {
    const unsigned char *end = memchr(blob + cursor, 0, length - cursor);
    return end ? (size_t)(end - blob) - cursor : SIZE_MAX;
}
static int core_io_memory_valid_name(const unsigned char *name, size_t width) {
    return width && width <= CORE_IO_MEMORY_NAME_LIMIT && !memchr(name, '=', width) && core_io_utf8(name, width);
}
/* Validate `NAME\0VALUE\0...`: bounded, unique, nonempty names without `=`. */
static int core_io_memory_valid_pairs(const unsigned char *blob, size_t length) {
    size_t cursor = 0, count = 0;
    while (cursor < length) {
        size_t name = core_io_memory_field(blob, length, cursor);
        if (name == SIZE_MAX || !core_io_memory_valid_name(blob + cursor, name)) return 0;
        size_t value_at = cursor + name + 1;
        size_t value = value_at < length ? core_io_memory_field(blob, length, value_at) : SIZE_MAX;
        if (value == SIZE_MAX || value > CORE_IO_MEMORY_VALUE_LIMIT || ++count > CORE_IO_MEMORY_NAMES_LIMIT) return 0;
        for (size_t other = 0; other < cursor;) {
            size_t width = core_io_memory_field(blob, length, other);
            if (width == name && !memcmp(blob + other, blob + cursor, name)) return 0;
            other += width + 1;
            other += core_io_memory_field(blob, length, other) + 1;
        }
        cursor = value_at + value + 1;
    }
    return 1;
}
static int core_io_memory_blob_has(const unsigned char *blob, size_t length, const unsigned char *key, size_t width) {
    for (size_t cursor = 0; cursor < length;) {
        size_t name = core_io_memory_field(blob, length, cursor);
        if (name == width && !memcmp(blob + cursor, key, width)) return 1;
        cursor += name + 1;
    }
    return 0;
}



/* Raw validation follows native_text_utf8, without a legacy text object. */
static int core_io_utf8(const unsigned char *p,size_t n) {
    for (size_t i=0;i<n;) {
        unsigned a=p[i++];
        if(a<128) continue;
        unsigned need=a>=0xc2&&a<=0xdf?1:a>=0xe0&&a<=0xef?2:a>=0xf0&&a<=0xf4?3:99;
        if(need>n-i) return 0;
        unsigned b=p[i];
        if((a==0xe0&&b<0xa0)||(a==0xed&&b>=0xa0)||(a==0xf0&&b<0x90)||(a==0xf4&&b>=0x90))return 0;
        while(need--)if((p[i++]&0xc0)!=0x80)return 0;
    }
    return 1;
}
static myl_block *core_io_string(const void *bytes,size_t len,int text) {
    myl_block *value=block_new(text?MYL_KIND_STR:MYL_KIND_BYTES,(int64_t)len,1);
    value->len=(int64_t)len;
    if(len)memcpy(block_data(value),bytes,len);
    if(text){block_data(value)[len]=0;core_text_publish(value);}
    return value;
}
static void core_io_drop(myl_block *block) {
#ifdef MYL_ZERO_RC
    myl_core_drop_owned(block);
#else
    myl_core_release(block);
#endif
}
static void core_io_retain(myl_block *block) {
#ifndef MYL_ZERO_RC
    count_retain(block);
#else
    (void)block; /* Caller-checked dependencies borrow; root providers transfer. */
#endif
}
static void core_io_root_transferred(myl_block *provider) {
#ifndef MYL_ZERO_RC
    myl_core_release(provider);
#else
    (void)provider;
#endif
}
#ifdef MYL_ZERO_RC
static const int32_t core_io_cap_layout[]={32,2,0,8,0,24,0};
static const int32_t core_io_dependent_layout[]={32,1,0,24,0};
static const int32_t core_io_resource_layout[]={64,0,0};
#else
static const int32_t core_io_cap_layout[]={32,3,0,8,0,16,0,24,0};
static const int32_t core_io_resource_layout[]={64,1,0,0,0};
#endif
static const int32_t core_io_result_pointer_layout[]={24,2,0,8,0,16,0};
static const int32_t core_io_result_scalar_layout[]={24,1,0,16,0};
static const int32_t core_io_list_layout[]={8,1,0,0,0};
typedef struct { unsigned family,rights;myl_block *provider,*parent,*scope; } CoreIoAuthority;
typedef struct { unsigned family,test;int64_t value;MemoryFs *memory;myl_block *pairs;CoreIoResourceProvider adapter; } CoreIoState;
static const int32_t core_io_provider_layout[]={sizeof(CoreIoState),1,0,offsetof(CoreIoState,pairs),0};
typedef struct CoreIoResource { myl_block *authority;uint64_t handle;unsigned family,rights,open,text;struct CoreIoResource *previous,*next;myl_block *block; } CoreIoResource;
static CoreIoResource *core_io_tail;
static int64_t core_io_open_count;static unsigned core_io_family_open[2];
static CoreIoScoped core_io_real;
static int core_io_initialized,core_io_restricted,core_io_clock,core_io_entropy,core_io_environment,core_io_host;
static char *core_io_options;
static const char *core_io_names="";
static const char *core_io_enumerated_names="";
static uint64_t core_io_seed;
static CoreIoAuthority *core_io_authority(myl_block *block) { return (CoreIoAuthority *)block_data(block); }
static CoreIoState *core_io_state(myl_block *authority) { return (CoreIoState *)block_data(core_io_authority(authority)->provider); }
static void core_io_fail(const char *code) { core_io_failure(code); }

static myl_block *core_io_provider(unsigned family,int test,int64_t value,myl_block *pairs) {
#ifdef MYL_ZERO_RC
    if (pairs) pairs = myl_core_owned_octets_copy(pairs);
#endif
    myl_block *block=block_new(8,(int64_t)sizeof(CoreIoState),1);block->len=1;block->reserved=(int64_t)(intptr_t)core_io_provider_layout;
    CoreIoState *state=(CoreIoState *)block_data(block);memset(state,0,sizeof *state);
    state->family=family;state->test=(unsigned)test;state->value=value;state->pairs=pairs;core_io_retain(pairs);
    if(family==2){
        if(!test&&core_io_embedding)state->adapter=core_io_native.filesystem;
        else if(test){state->memory=calloc(1,sizeof(MemoryFs));if(!state->memory)out_of_memory();state->adapter=(CoreIoResourceProvider){state->memory,7,core_io_memory_acquire,core_io_memory_complete,core_io_memory_release,core_io_memory_read,core_io_memory_write};}
        else state->adapter=core_io_scoped_provider(&core_io_real,7);
    } else if(family==3) state->adapter=!test&&core_io_embedding?core_io_native.network:test?(CoreIoResourceProvider){state,7,core_io_memory_network_acquire,core_io_memory_network_complete,core_io_memory_network_release,NULL,NULL}:core_io_scoped_network_provider(&core_io_real,7);
    return block;
}
static myl_block *core_io_cap_new(unsigned family,unsigned rights,myl_block *provider,myl_block *parent,myl_block *scope) {
    myl_block *block=block_new(6,sizeof(CoreIoAuthority),1);block->len=1;block->reserved=(int64_t)(intptr_t)core_io_cap_layout;
#ifdef MYL_ZERO_RC
    if (parent) block->reserved=(int64_t)(intptr_t)core_io_dependent_layout;
#endif
    *(CoreIoAuthority *)block_data(block)=(CoreIoAuthority){family,rights,provider,parent,scope};
    core_io_retain(provider);core_io_retain(parent);core_io_retain(scope);return block;
}
/* Borrowed scope input: publish an independent scope in the owned ABI. */
static myl_block *core_io_cap(unsigned family,unsigned rights,myl_block *provider,myl_block *parent,myl_block *scope) {
#ifdef MYL_ZERO_RC
    if (scope) scope=myl_core_owned_octets_copy(scope);
#endif
    return core_io_cap_new(family,rights,provider,parent,scope);
}
typedef struct CoreIoScratch {struct CoreIoScratch *next;unsigned char data[];} CoreIoScratch;
static CoreIoScratch *core_io_scratch_head;
static unsigned char *core_io_copy(const unsigned char *source,size_t length){CORE_IO_GUARD;CoreIoScratch *copy=malloc(sizeof(*copy)+(length?length:1));if(!copy)out_of_memory();copy->next=core_io_scratch_head;core_io_scratch_head=copy;if(source&&length)memcpy(copy->data,source,length);return copy->data;}
static void core_io_copy_free(unsigned char *bytes){CORE_IO_GUARD;CoreIoScratch **at=&core_io_scratch_head;while(*at&&(*at)->data!=bytes)at=&(*at)->next;if(!*at)core_io_fail("InvalidProvider");CoreIoScratch *copy=*at;*at=copy->next;free(copy);}
static void core_io_unlink(CoreIoResource *resource) {
    if(resource->previous)resource->previous->next=resource->next;
    if(resource->next)resource->next->previous=resource->previous;else core_io_tail=resource->previous;
    resource->previous=resource->next=NULL;--core_io_open_count;--core_io_family_open[resource->family-2];
}
static void core_io_close(CoreIoResource *resource) {
    if(!resource->open)return;
    CoreIoState *state=core_io_state(resource->authority);
    resource->open=0;core_io_unlink(resource);state->adapter.release(state->adapter.context,resource->handle);
}
static int64_t core_io_live_handles(void){CORE_IO_GUARD;return core_io_open_count;}
static void core_io_cleanup(void) {CORE_IO_GUARD;
    for(unsigned family=3;family>=2;--family){CoreIoResource *resource=core_io_tail;while(resource){CoreIoResource *previous=resource->previous;if(resource->family==family)core_io_close(resource);resource=previous;}}
    while(core_io_scratch_head){CoreIoScratch *copy=core_io_scratch_head;core_io_scratch_head=copy->next;free(copy);}
    if(core_io_initialized){core_io_scoped_close(&core_io_real);core_io_initialized=0;}
    free(core_io_options);core_io_options=NULL;core_host_cleanup();
}
static void core_io_finalize(myl_block *block) {
    unsigned kind = kind_of(block);
    if (kind != 7 && kind != 8) return;
    CORE_IO_GUARD;
    if(kind_of(block)==7)core_io_close((CoreIoResource *)block_data(block));
    if(kind_of(block)==8){CoreIoState *state=(CoreIoState *)block_data(block);if(state->memory)core_io_memory_free(state->memory);}
}
/* Three fields in an explicit result slot. Pointer/scalar helpers choose the
   matching child descriptor, never scanning a status or numeric word. */
static myl_block *core_io_result(int status,uint64_t value,myl_block *error,int pointer) {
    myl_block *box=block_new(MYL_KIND_BOX,24,1);box->len=1;
    box->reserved=(int64_t)(intptr_t)(pointer?core_io_result_pointer_layout:core_io_result_scalar_layout);
    uint64_t *data=(uint64_t *)block_data(box);data[0]=(uint64_t)status;data[1]=value;data[2]=(uint64_t)(uintptr_t)error;
    return box;
}
typedef struct {const char *path;int writable;} CoreIoGrant;
static CoreIoGrant core_io_grants[8];static size_t core_io_grant_count;
static const char *core_io_option_argument;
static void core_io_option_error(const char *format,const char *argument){char text[1024];int length=snprintf(text,sizeof text,format,argument);flush_all();os_write(2,(const unsigned char *)text,(size_t)(length<(int)sizeof text?length:(int)sizeof text-1));os_exit(2);}
static void core_io_bad_grant(void){core_io_option_error("mylang: the option %s is not a usable capability grant\n",core_io_option_argument);}
static void core_io_missing_grant(const char *flag){core_io_option_error("mylang: --restrict is active and this command line did not grant a capability the entry point requests; pass %s, or drop --restrict to grant every capability\n",flag);}
static void core_io_grant_request(const char *path,int writable){if(!*path||core_io_grant_count==8)core_io_bad_grant();for(size_t i=0;i<core_io_grant_count;++i)if(core_io_grants[i].writable==writable&&!strcmp(core_io_grants[i].path,path))core_io_bad_grant();core_io_grants[core_io_grant_count++]=(CoreIoGrant){path,writable};}
/* The next option of a writable `MYLANG_OPTIONS` copy, unquoted in place, or NULL at
   its end. Options are separated by whitespace; a double quote groups whitespace into
   one option and a backslash inside quotes escapes the next byte. An unterminated
   quote ends the process with status 2. */
static char *core_io_next_option(char **cursor) {
    char *read=*cursor;
    while(*read&&strchr(" \t\n\r",*read))++read;
    if(!*read){*cursor=read;return NULL;}
    char *arg=read,*write=read;int quoted=0;
    while(*read&&(quoted||!strchr(" \t\n\r",*read))){if(*read=='"'){quoted=!quoted;++read;}else if(quoted&&*read=='\\'&&read[1]){++read;*write++=*read++;}else *write++=*read++;}
    if(quoted)core_io_option_error("mylang: MYLANG_OPTIONS has an unterminated quote\n%s","");
    if(*read)++read;
    *write=0;*cursor=read;
    return arg;
}
/* A runtime budget `myl_core_start` has already answered for the whole process. */
static int core_io_budget_option(const char *arg){return !strncmp(arg,"--max-steps=",12)||!strncmp(arg,"--max-frames=",13)||!strncmp(arg,"--timeout=",10);}
/* Core entry uses the same MYLANG_OPTIONS grant grammar as qbe_grants.c. */
static void core_io_initialize(void) {
    if(core_io_initialized)return;
    core_io_initialized=1;core_io_scoped_init(&core_io_real);
    if(mylang_native_providers_v7){core_io_native=mylang_native_providers_v7();core_io_embedding=1;}
    const char *options=getenv("MYLANG_OPTIONS");
    core_io_options=strdup(options?options:"");if(!core_io_options)out_of_memory();
    char *cursor=core_io_options,*arg;
    while((arg=core_io_next_option(&cursor))){
        core_io_option_argument=arg;
        if(!strcmp(arg,"--restrict")){if(core_io_restricted)core_io_bad_grant();core_io_restricted=1;}
        else if(!strncmp(arg,"--allow-read=",13)){core_io_grant_request(arg+13,0);}
        else if(!strncmp(arg,"--allow-write=",14)){core_io_grant_request(arg+14,1);}
        else if(!strncmp(arg,"--allow-endpoint=",17)){if(!core_io_scoped_endpoint(&core_io_real,arg+17))core_io_bad_grant();}
        else if(!strcmp(arg,"--allow-clock")){if(core_io_clock)core_io_bad_grant();core_io_clock=1;}
        else if(!strcmp(arg,"--allow-host")){if(core_io_host)core_io_bad_grant();core_io_host=1;}
        else if(!strncmp(arg,"--allow-random",14)&&(arg[14]==0||arg[14]=='=')){if(core_io_entropy||(arg[14]&&!arg[15]))core_io_bad_grant();core_io_entropy=1;core_io_seed=arg[14]?strtoull(arg+15,NULL,10):0;}
        else if(!strncmp(arg,"--allow-env",11)&&(arg[11]==0||arg[11]=='=')){if(core_io_environment||(arg[11]&&!arg[12]))core_io_bad_grant();core_io_environment=1;core_io_names=arg[11]?arg+12:"";}
        else if(!strcmp(arg,"--allow-all")){if(core_io_clock||core_io_entropy||core_io_environment||core_io_host||core_io_grant_count||core_io_real.endpoint_count)core_io_bad_grant();core_io_clock=core_io_entropy=core_io_environment=core_io_host=1;core_io_grant_request(".",1);core_io_scoped_endpoint(&core_io_real,"*");}
        else if(!strcmp(arg,"--print-result")||core_io_budget_option(arg)){/* read by myl_core_exit and myl_core_start */}
        else if(!strncmp(arg,"--allow-",8)||!strncmp(arg,"--restrict",10))core_io_bad_grant();
        else core_io_option_error("mylang: MYLANG_OPTIONS names %s, which is not a runtime option\n",arg);
    }
    core_io_enumerated_names=core_io_names;
    if(core_io_restricted){core_io_embedding=0;for(size_t i=0;i<core_io_grant_count;++i)if(!core_io_scoped_grant(&core_io_real,core_io_grants[i].path,core_io_grants[i].writable))core_io_option_error("mylang: a requested directory grant could not be opened\n%s","");}
    if(!core_io_restricted){core_io_scoped_close(&core_io_real);core_io_scoped_init(&core_io_real);if(!core_io_embedding){if(!core_io_scoped_working_directory(&core_io_real))core_io_option_error("mylang: a requested directory grant could not be opened\n%s","");core_io_scoped_endpoint(&core_io_real,"*");}core_io_clock=core_io_environment=core_io_host=1;if(!core_io_entropy&&!core_io_embedding){struct timespec now={0};clock_gettime(CLOCK_REALTIME,&now);core_io_seed=(uint64_t)now.tv_sec*1000000000+(uint64_t)now.tv_nsec;}core_io_entropy=1;}
}
myl_block *myl_core_cap_grant(uint32_t family) {CORE_IO_GUARD;
    core_io_initialize();
    int available=core_io_embedding?(family==0?core_io_native.clock_now!=NULL:family==1?core_io_native.random_u64!=NULL:family==2?(core_io_native.filesystem.acquire&&core_io_native.filesystem.complete&&core_io_native.filesystem.release):family==3?(core_io_native.network.acquire&&core_io_native.network.complete&&core_io_native.network.release):core_io_native.environment_get!=NULL):family==0?core_io_clock:family==1?core_io_entropy:family==2?core_io_real.count!=0:family==3?core_io_real.endpoint_count!=0:core_io_environment;
    if(!available){const char *flag=family==0?"--allow-clock":family==1?"--allow-random":family==2?"--allow-read=DIR":family==3?"--allow-endpoint=IP:PORT":"--allow-env";core_io_missing_grant(flag);}
    unsigned rights=7;if(family==2&&core_io_restricted){rights=5;for(size_t i=0;i<core_io_real.count;++i)if(core_io_real.roots[i].writable)rights=7;}
    myl_block *provider=core_io_provider(family,0,(int64_t)core_io_seed,NULL);if(family==2||family==3){unsigned permissions=((CoreIoState *)block_data(provider))->adapter.permissions;if(permissions&~7u)core_io_fail("InvalidCapability");rights&=permissions;}myl_block *cap=core_io_cap(family,rights,provider,NULL,NULL);core_io_root_transferred(provider);return cap;
}
int64_t myl_core_host_grant(void){CORE_IO_GUARD;core_io_initialize();if(!core_io_host)core_io_missing_grant("--allow-host");return -6;}
void myl_core_host_check(int64_t token){CORE_IO_GUARD;core_io_initialize();if(token!=-6||!core_io_host)core_io_fail("R_CAPABILITY");}
myl_block *myl_core_stand_in(uint32_t family,int64_t value){CORE_IO_GUARD;myl_block *state=core_io_provider(family,1,value,NULL);myl_block *cap=core_io_cap(family,7,state,NULL,NULL);core_io_root_transferred(state);return cap;}
myl_block *myl_core_environment_fixed(myl_block *pairs){CORE_IO_GUARD;if(!core_io_memory_valid_pairs(block_data(pairs),(size_t)pairs->len))core_io_fail("R_ENVIRONMENT");myl_block *state=core_io_provider(4,1,0,pairs);myl_block *cap=core_io_cap(4,7,state,NULL,NULL);core_io_root_transferred(state);return cap;}
int64_t myl_core_clock_advance(myl_block *clock,int64_t delta){CORE_IO_GUARD;CoreIoState *state=core_io_state(clock);if(state->family!=0)core_io_fail("InvalidCapability");if(!state->test)return 1;if((delta>0&&state->value>INT64_MAX-delta)||(delta<0&&state->value<INT64_MIN-delta))return 2;state->value+=delta;return 0;}
myl_block *myl_core_external_read(myl_block *cap,uint32_t family){CORE_IO_GUARD;CoreIoState *state=core_io_state(cap);if(state->family!=family||family>1)core_io_fail("InvalidCapability");uint64_t value=0;int status=0;if(family==0){if(state->test)value=(uint64_t)state->value;else if(core_io_embedding){CoreIoClockResult result=core_io_native.clock_now(core_io_native.clock_context);status=(int)result.status;value=(uint64_t)result.value;}else{struct timespec now={0};status=clock_gettime(CLOCK_REALTIME,&now)||now.tv_sec>(INT64_MAX-now.tv_nsec)/1000000000?3:0;value=status?0:(uint64_t)now.tv_sec*1000000000+(uint64_t)now.tv_nsec;}}else if(!state->test&&core_io_embedding){CoreIoRandomResult result=core_io_native.random_u64(core_io_native.random_context);status=(int)result.status;value=result.value;}else{state->value=(int64_t)((uint64_t)state->value+UINT64_C(0x9e3779b97f4a7c15));value=(uint64_t)state->value;value=(value^(value>>30))*UINT64_C(0xbf58476d1ce4e5b9);value=(value^(value>>27))*UINT64_C(0x94d049bb133111eb);value^=value>>31;}if(status==4)out_of_memory();if(status<0||status>3)core_io_fail("InvalidProviderResult");return core_io_result(status,status?0:value,NULL,0);}
myl_block *myl_core_cap_restrict(myl_block *cap,uint32_t rights){CORE_IO_GUARD;CoreIoAuthority *a=core_io_authority(cap);return core_io_cap(a->family,a->rights&rights,a->provider,cap,a->scope);}
static myl_block *core_io_scope(myl_block *cap,myl_block *scope,unsigned family,int append){CoreIoAuthority *a=core_io_authority(cap);if(a->family!=family)core_io_fail("InvalidCapability");myl_block *joined=scope;if(append&&a->scope&&a->scope->len){size_t length=(size_t)(a->scope->len+scope->len+(scope->len!=0));unsigned char *bytes=malloc(length);if(!bytes)out_of_memory();memcpy(bytes,block_data(a->scope),(size_t)a->scope->len);if(scope->len){bytes[a->scope->len]='/';memcpy(bytes+a->scope->len+1,block_data(scope),(size_t)scope->len);}joined=core_io_string(bytes,length,1);free(bytes);}else {
#ifdef MYL_ZERO_RC
    joined=myl_core_owned_octets_copy(scope);
#else
    core_io_retain(joined);
#endif
}myl_block *out=core_io_cap_new(family,a->rights,a->provider,cap,joined);
#ifndef MYL_ZERO_RC
core_io_drop(joined);
#endif
return out;}
myl_block *myl_core_cap_dir(myl_block *cap,myl_block *path){CORE_IO_GUARD;if(path->len&&!core_io_memory_valid_path(block_data(path),(size_t)path->len,'m'))core_io_fail("InvalidCapability");return core_io_scope(cap,path,2,1);}
myl_block *myl_core_cap_host(myl_block *cap,myl_block *name){CORE_IO_GUARD;CoreIoAuthority *a=core_io_authority(cap);if(!name->len||name->len>4096||memchr(block_data(name),0,(size_t)name->len))core_io_fail("InvalidCapability");if(a->scope&&!myl_core_str_eq(a->scope,name))core_io_fail("InvalidCapability");return core_io_scope(cap,name,3,0);}
myl_block *myl_core_environment_only(myl_block *cap,myl_block *names){CORE_IO_GUARD;CoreIoAuthority *a=core_io_authority(cap);if(a->family!=4||a->scope)core_io_fail("R_CAPABILITY");if(!names->len||block_data(names)[names->len-1]!=0)core_io_fail("InvalidCapability");return core_io_scope(cap,names,4,0);}

static int core_io_resource_acquire(myl_block *cap,const unsigned char *request,size_t length,myl_block **output) {
    CoreIoAuthority *authority=core_io_authority(cap);CoreIoState *state=core_io_state(cap);
    if(authority->family!=2&&authority->family!=3)core_io_fail("InvalidCapability");
    if(authority->family==3&&state->test)return 6;
    unsigned char joined[8192];const unsigned char *input=request;size_t width=length;
    if(authority->scope){size_t scope=(size_t)authority->scope->len;if(authority->family==2){if(length<2||request[1]!=':'||!core_io_memory_valid_path(request+2,length-2,request[0]))return 2;if(scope+length+1>sizeof joined)return 2;joined[0]=request[0];joined[1]=':';memcpy(joined+2,block_data(authority->scope),scope);size_t at=scope+2;if(length>2){if(scope)joined[at++]='/';memcpy(joined+at,request+2,length-2);at+=length-2;}width=at;}else{if(scope>sizeof joined)return 2;memcpy(joined,block_data(authority->scope),scope);width=scope;}input=joined;}
    if(!state->adapter.acquire)return 1;
    if(core_io_family_open[authority->family-2]>=1024)return 4;
    /* Allocate bookkeeping before acquiring, so registration cannot fail. */
    myl_block *block=block_new(7,sizeof(CoreIoResource),1);block->len=1;block->reserved=(int64_t)(intptr_t)core_io_resource_layout;
    memset(block_data(block),0,sizeof(CoreIoResource));
    unsigned char *request_copy=core_io_copy(input,width);CoreIoResourceResult result=state->adapter.acquire(state->adapter.context,request_copy,width,authority->rights&state->adapter.permissions);core_io_copy_free(request_copy);
    if(result.status==CORE_IO_PROVIDER_OUT_OF_MEMORY){block->reserved=0;block_free(block);out_of_memory();}
    if(result.status>3){block->reserved=0;block_free(block);core_io_fail("InvalidProvider");}
    if(result.status){block->reserved=0;block_free(block);return (int)result.status;}
    CoreIoResource *resource=(CoreIoResource *)block_data(block);*resource=(CoreIoResource){cap,result.handle,authority->family,authority->rights&state->adapter.permissions,1,0,core_io_tail,NULL,block};core_io_retain(cap);
    if(core_io_tail)core_io_tail->next=resource;core_io_tail=resource;++core_io_open_count;++core_io_family_open[authority->family-2];*output=block;return 0;
}
static CoreIoResource *core_io_resource(myl_block *owner){if(!owner||kind_of(owner)!=7)core_io_fail("InvalidOwner");return (CoreIoResource *)block_data(owner);}
static int core_io_complete(myl_block *owner){CoreIoResource *resource=core_io_resource(owner);if(!resource->open)return 3;if(!(resource->rights&4))return 2;CoreIoState *state=core_io_state(resource->authority);int status=(int)state->adapter.complete(state->adapter.context,resource->handle);if(status==4)out_of_memory();if(status<0||status>3)core_io_fail("InvalidProvider");if(!status){resource->open=0;core_io_unlink(resource);}return status;}
void myl_core_file_scope_close(myl_block *owner){CORE_IO_GUARD;if(!owner)return;CoreIoResource *resource=core_io_resource(owner);if(!resource->open)return;if(!(resource->rights&4)){core_io_close(resource);return;}if(core_io_complete(owner))core_io_fail("R_FILE");}
/* NEW-CORE-ZERO-RC-RESOURCES-1: the explicit provider argument extends its
   compiler lifetime through completion and resource destruction. */
void myl_core_owned_file_scope_end(myl_block *owner, myl_block *provider) {
    (void)provider;
    myl_core_file_scope_close(owner);
    myl_core_drop_owned(owner);
}
void myl_core_owned_cap_scope_end(myl_block *owner, myl_block *provider) {
    (void)provider;
    myl_core_drop_owned(owner);
}
/* NEW-CORE-ZERO-RC-RESOURCES-1: an IR lifetime use, never an extra owner.
   Generated cleanup uses this after destroying dependent resource values. */
void myl_core_provider_keepalive(myl_block *provider) {
    (void)provider;
}
myl_block *myl_core_result_take_pointer(myl_block *box, uint32_t field) {
    if (field != 1 && field != 2) abort();
    myl_block **slot = (myl_block **)(block_data(box) + (size_t)field * 8);
    myl_block *value = *slot;
    *slot = NULL;
    return value;
}
static int core_io_read(myl_block *owner,unsigned char *out,size_t cap,size_t *written,int *eof){
    CoreIoResource *resource=core_io_resource(owner);*written=0;*eof=0;if(!resource->open)core_io_fail("InvalidOwner");if(!(resource->rights&1))return 2;CoreIoState *state=core_io_state(resource->authority);if(!state->adapter.read)return 1;
    unsigned char *copy=core_io_copy(NULL,cap);CoreIoResourceRead result=state->adapter.read(state->adapter.context,resource->handle,copy,cap);
    if(result.status==4)out_of_memory();if(result.status>3)core_io_fail("InvalidProvider");
    if(!result.status){if(result.length>cap||(result.eof!=0&&result.eof!=1))core_io_fail("InvalidProvider");if(result.length)memcpy(out,copy,result.length);*written=result.length;*eof=result.eof;}
    core_io_copy_free(copy);if(cap>*written)memset(out+*written,0,cap-*written);return (int)result.status;
}
static int core_io_write(myl_block *owner,const unsigned char *data,size_t len,size_t *written){
    CoreIoResource *resource=core_io_resource(owner);*written=0;if(!resource->open)core_io_fail("InvalidOwner");if(!(resource->rights&2))return 2;CoreIoState *state=core_io_state(resource->authority);if(!state->adapter.write)return 1;
    unsigned char *copy=core_io_copy(data,len);CoreIoResourceWrite result=state->adapter.write(state->adapter.context,resource->handle,copy,len);
    if(result.status==4)out_of_memory();if(result.status>3)core_io_fail("InvalidProvider");if(!result.status){if(result.length>len)core_io_fail("InvalidProvider");*written=result.length;}core_io_copy_free(copy);return (int)result.status;
}

myl_block *myl_core_resource_acquire(myl_block *cap,myl_block *request){CORE_IO_GUARD;myl_block *resource=NULL;int status=core_io_resource_acquire(cap,block_data(request),(size_t)request->len,&resource);return core_io_result(status,(uint64_t)(uintptr_t)resource,NULL,1);}
int64_t myl_core_resource_complete(myl_block *owner){CORE_IO_GUARD;return core_io_complete(owner);}
static const char *core_io_reason(int status){if(status==1)return "no filesystem authority is available";if(status==2)return "denied: outside the granted directories, or the mode needs a write grant";if(status==4)return "too many files are open";if(status==5)return "the bytes read are not valid UTF-8 text";return "failed: the path does not exist or could not be used";}
static myl_block *core_io_file_error(unsigned kind,myl_block *path,int status){static const char *verbs[]={"open","read","read","write","write","stat","listdir","mkdir","remove"};const char *verb=verbs[kind],*reason=core_io_reason(status);size_t length=strlen(verb)+strlen(reason)+(size_t)path->len+5;char *message=malloc(length+1);if(!message)out_of_memory();size_t at=(size_t)sprintf(message,"%s '",verb);memcpy(message+at,block_data(path),(size_t)path->len);at+=(size_t)path->len;at+=(size_t)sprintf(message+at,"': %s",reason);myl_block *text=core_io_string(message,at,1);free(message);return text;}
typedef struct {unsigned char *bytes;size_t length,capacity;} CoreIoBytes;
static void core_io_append(CoreIoBytes *bytes,const unsigned char *data,size_t length){if(bytes->length+length>64u*1024u*1024u)core_io_fail("R_FILE");if(bytes->length+length>bytes->capacity){size_t cap=bytes->capacity?bytes->capacity:128;while(cap<bytes->length+length)cap*=2;unsigned char *grown=realloc(bytes->bytes,cap);if(!grown)out_of_memory();bytes->bytes=grown;bytes->capacity=cap;}if(length)memcpy(bytes->bytes+bytes->length,data,length);bytes->length+=length;}
static int core_io_read_all(myl_block *resource,size_t limit,int line,CoreIoBytes *out){unsigned char data[16384];while(out->length<limit){size_t take=line?1:sizeof data;if(take>limit-out->length)take=limit-out->length;size_t read;int eof;int status=core_io_read(resource,data,take,&read,&eof);if(status)return status;core_io_append(out,data,read);if(!read||eof||(line&&data[0]=='\n'))break;}return 0;}
static int core_io_write_all(myl_block *resource,myl_block *input,size_t *out){*out=0;while(*out<(size_t)input->len){size_t written;size_t remaining=(size_t)input->len-*out;int status=core_io_write(resource,block_data(input)+*out,remaining<65536?remaining:65536,&written);if(status)return status;if(!written)return 3;*out+=written;}return 0;}
static myl_block *core_io_sequence(CoreIoBytes *bytes,int text,int *status){if(text&&!core_io_utf8(bytes->bytes,bytes->length)){*status=5;return NULL;}return core_io_string(bytes->bytes,bytes->length,text);}
static myl_block *core_io_list_new(size_t capacity){myl_block *list=block_new(MYL_KIND_LIST,(int64_t)capacity,8);list->reserved=(int64_t)(intptr_t)core_io_list_layout;return list;}
static void core_io_list_add(myl_block **list,myl_block *item){*list=myl_core_list_grow(*list,8);myl_block **data=(myl_block **)block_data(*list);data[(*list)->len++]=item;}
static myl_block *core_io_listing(CoreIoBytes *raw,int *status){myl_block *list=core_io_list_new(0);if(!raw->length||raw->bytes[0]!=1){*status=3;return list;}size_t at=1;while(at<raw->length){if(at+3>raw->length){*status=3;break;}size_t width=(size_t)raw->bytes[at+1]|((size_t)raw->bytes[at+2]<<8);at+=3;if(at+width>raw->length||!core_io_utf8(raw->bytes+at,width)){*status=5;break;}core_io_list_add(&list,core_io_string(raw->bytes+at,width,1));at+=width;}return list;}
/* request packs Access, open mode and text bit, as qbe_files.c. */
myl_block *myl_core_file_access(myl_block *cap,uint32_t request,myl_block *path,myl_block *input){CORE_IO_GUARD;unsigned kind=request&255,mode=(request>>8)&255;int text=(request>>16)&1;static const unsigned char letters[]={0,'r','r','w','w','m','l','k','x'};if(kind>8)core_io_fail("R_FILE");unsigned char frame[4096];int status=0;myl_block *owner=NULL;uint64_t value=0;if(path->len>4094)status=2;else{frame[0]=kind?letters[kind]:(unsigned char)mode;frame[1]=':';if(path->len)memcpy(frame+2,block_data(path),(size_t)path->len);if(frame[0]=='w'){frame[0]='c';status=core_io_resource_acquire(cap,frame,(size_t)path->len+2,&owner);if(status>0){frame[0]='t';status=core_io_resource_acquire(cap,frame,(size_t)path->len+2,&owner);}}else status=core_io_resource_acquire(cap,frame,(size_t)path->len+2,&owner);}
    if(!status){CoreIoBytes raw={0};if(kind==0){core_io_resource(owner)->text=(unsigned)text;return (request&(1u<<17))?owner:core_io_result(0,(uint64_t)(uintptr_t)owner,NULL,1);}if(kind==1||kind==2||kind==5||kind==6){status=core_io_read_all(owner,64u*1024u*1024u,0,&raw);if(!status){if(kind==5)value=1;else if(kind==6)value=(uint64_t)(uintptr_t)core_io_listing(&raw,&status);else value=(uint64_t)(uintptr_t)core_io_sequence(&raw,kind==2,&status);}}else if(kind==3||kind==4){size_t written;status=core_io_write_all(owner,input,&written);}(void)core_io_complete(owner);free(raw.bytes);core_io_drop(owner);}
    if(kind==0&&(request&(1u<<17)))core_io_fail("R_FILE");
    if(kind==5)return core_io_result(0,status?0:value,NULL,0);
    int pointer=kind==0||kind==1||kind==2||kind==6;if(status&&pointer&&value){core_io_drop((myl_block *)(uintptr_t)value);value=0;}
    return core_io_result(status,value,status?core_io_file_error(kind,path,status):NULL,pointer);
}
myl_block *myl_core_file_method(myl_block *owner,uint32_t request,int64_t count,myl_block *input){CORE_IO_GUARD;unsigned kind=request&255;int text=(request>>16)&1;CoreIoResource *resource=core_io_resource(owner);if(!resource->open)core_io_fail("R_FILE");int status=0;uint64_t value=0;int pointer=kind<=2;CoreIoBytes raw={0};if(kind==0||kind==1){status=core_io_read_all(owner,count<0?64u*1024u*1024u:(size_t)count,kind==1,&raw);if(!status)value=(uint64_t)(uintptr_t)core_io_sequence(&raw,text,&status);}else if(kind==2){myl_block *list=core_io_list_new(0);for(;;){CoreIoBytes line={0};status=core_io_read_all(owner,64u*1024u*1024u,1,&line);if(status||!line.length){free(line.bytes);break;}myl_block *part=core_io_sequence(&line,text,&status);free(line.bytes);if(status)break;core_io_list_add(&list,part);}value=(uint64_t)(uintptr_t)list;}else if(kind==3){size_t written;status=core_io_write_all(owner,input,&written);value=(uint64_t)written;}else if(kind==5)status=core_io_complete(owner);else if(kind!=4)core_io_fail("R_FILE");free(raw.bytes);if(status){if(pointer&&value)core_io_drop((myl_block *)(uintptr_t)value);core_io_fail("R_FILE");}return core_io_result(0,value,NULL,pointer);}
static int core_io_allowed(const char *names,const unsigned char *name,size_t length){if(!*names)return 1;for(const char *p=names;*p;){const char *comma=strchr(p,',');size_t width=comma?(size_t)(comma-p):strlen(p);if(width==length&&!memcmp(p,name,length))return 1;if(!comma)break;p=comma+1;}return 0;}
static int core_io_environment_read(myl_block *cap,myl_block *name,unsigned char *output,size_t capacity,size_t *written,int *present){
    CoreIoAuthority *a=core_io_authority(cap);CoreIoState *state=core_io_state(cap);*written=0;*present=0;
    if(a->family!=4)core_io_fail("R_CAPABILITY");
    if(a->scope&&!core_io_memory_blob_has(block_data(a->scope),(size_t)a->scope->len,block_data(name),(size_t)name->len))core_io_fail("R_CAPABILITY");
    if(state->test){myl_block *pairs=state->pairs;if(!pairs)return 0;for(size_t at=0;at<(size_t)pairs->len;){size_t key=core_io_memory_field(block_data(pairs),(size_t)pairs->len,at),value=at+key+1,width=core_io_memory_field(block_data(pairs),(size_t)pairs->len,value);if(key==(size_t)name->len&&!memcmp(block_data(pairs)+at,block_data(name),key)){if(width>capacity)return 4;if(width)memcpy(output,block_data(pairs)+value,width);*written=width;*present=1;break;}at=value+width+1;}return 0;}
    if(core_io_embedding){unsigned char *key_copy=core_io_copy(block_data(name),(size_t)name->len),*copy=core_io_copy(NULL,capacity);CoreIoEnvironmentResult result=core_io_native.environment_get(core_io_native.environment_context,key_copy,(size_t)name->len,copy,capacity);core_io_copy_free(key_copy);if(result.status==4)out_of_memory();if(result.status){if(result.status>5)core_io_fail("InvalidProvider");core_io_copy_free(copy);return result.status==5?4:(int)result.status;}if((result.present!=0&&result.present!=1)||(result.present&&result.length>capacity))core_io_fail("InvalidProvider");*written=result.present?result.length:0;*present=result.present;if(*written)memcpy(output,copy,*written);core_io_copy_free(copy);return 0;}
    if(!core_io_allowed(core_io_names,block_data(name),(size_t)name->len))return 2;
    if((size_t)name->len>255)return 2;
    char key[256];memcpy(key,block_data(name),(size_t)name->len);key[name->len]=0;const char *value=getenv(key);if(!value)return 0;
    size_t length=strlen(value);if(length>capacity)return 4;if(length)memcpy(output,value,length);*written=length;*present=1;return 0;
}
myl_block *myl_core_environment_text(myl_block *cap,myl_block *name){CORE_IO_GUARD;unsigned char output[16384];size_t length;int present;int status=core_io_environment_read(cap,name,output,sizeof output,&length,&present);if(status)core_io_fail("R_CAPABILITY");if(!present)return NULL;if(!core_io_utf8(output,length))core_io_fail("R_ENVIRONMENT");return core_io_string(output,length,1);}

typedef struct { const unsigned char *bytes;size_t length; } CoreIoName;
static int core_io_name_order(const void *left,const void *right){const CoreIoName *a=left,*b=right;size_t width=a->length<b->length?a->length:b->length;int order=memcmp(a->bytes,b->bytes,width);return order?order:a->length<b->length?-1:a->length>b->length;}
/* Collect at most 64 raw names before filtering UTF-8, matching the old boundary. */
static void core_io_name_add(CoreIoName *names,unsigned *count,const unsigned char *name,size_t width){
    if(!width||width>128||*count==64)return;
    for(unsigned i=0;i<*count;++i)if(names[i].length==width&&!memcmp(names[i].bytes,name,width))return;
    names[(*count)++]=(CoreIoName){name,width};
}
myl_block *myl_core_environment_names(myl_block *cap){CORE_IO_GUARD;
    CoreIoAuthority *a=core_io_authority(cap);CoreIoState *state=core_io_state(cap);
    if(a->family!=4)core_io_fail("InvalidCapability");
    myl_block *list=core_io_list_new(0),*blob=a->scope?a->scope:state->pairs;
    CoreIoName names[64];unsigned count=0;
    if(blob){
        for(size_t at=0;at<(size_t)blob->len;){
            size_t width=core_io_memory_field(block_data(blob),(size_t)blob->len,at);
            if(state->test||core_io_allowed(core_io_enumerated_names,block_data(blob)+at,width))core_io_name_add(names,&count,block_data(blob)+at,width);
            at+=width+1;if(!a->scope)at+=core_io_memory_field(block_data(blob),(size_t)blob->len,at)+1;
        }
    }else if(!state->test){
        if(*core_io_enumerated_names){
            const char *name=core_io_enumerated_names;
            while(*name){const char *comma=strchr(name,',');size_t width=comma?(size_t)(comma-name):strlen(name);core_io_name_add(names,&count,(const unsigned char *)name,width);if(!comma)break;name=comma+1;}
        }else{
            extern char **environ;
            for(char **entry=environ;entry&&*entry;++entry){char *equal=strchr(*entry,'=');size_t width=equal?(size_t)(equal-*entry):strlen(*entry);core_io_name_add(names,&count,(const unsigned char *)*entry,width);}
        }
    }
    qsort(names,count,sizeof(CoreIoName),core_io_name_order);
    for(unsigned i=0;i<count;++i)if(core_io_utf8(names[i].bytes,names[i].length))core_io_list_add(&list,core_io_string(names[i].bytes,names[i].length,1));
    return list;
}
void myl_core_stream_write(int64_t fd,myl_block *text){myl_core_print_str(fd,text);stream_commit(stream_for(fd));}
/* `Stream.write(bytes)`: the same length-prefixed block as `str`, declared with its own type. */
void myl_core_stream_write_bytes(int64_t fd,myl_block *data){myl_core_print_str(fd,data);stream_commit(stream_for(fd));}
/* `Stream.write(byte_buffer)`: the buffer's current octets. */
void myl_core_stream_write_buffer(int64_t fd,myl_block *buffer){myl_core_print_str(fd,buffer);stream_commit(stream_for(fd));}
int64_t myl_core_s3_token_roundtrip(int64_t token){return token;}

myl_block *myl_core_io_bytes_from_u8_list(myl_block *list){CORE_IO_GUARD;return core_io_string(block_data(list),(size_t)list->len,0);}

/* Fixed provider payloads carry a padded byte block plus count/flag. The
   builder copies octets into its checked fixed array and owns this box normally. */
static const int32_t core_io_raw_layout[]={32,1,0,8,0};
static myl_block *core_io_raw_result(int status,myl_block *bytes,uint64_t length,int flag){
    myl_block *box=block_new(MYL_KIND_BOX,32,1);box->len=1;box->reserved=(int64_t)(intptr_t)core_io_raw_layout;
    uint64_t *data=(uint64_t *)block_data(box);data[0]=(uint64_t)status;data[1]=(uint64_t)(uintptr_t)bytes;data[2]=length;data[3]=(uint64_t)flag;return box;
}
static myl_block *core_io_padded(size_t capacity){
    if(capacity>64u*1024u*1024u)out_of_memory();
    myl_block *bytes=block_new(MYL_KIND_BYTES,(int64_t)capacity+1,1);bytes->len=(int64_t)capacity;memset(block_data(bytes),0,capacity+1);return bytes;
}
myl_block *myl_core_resource_read(myl_block *owner,uint64_t capacity){CORE_IO_GUARD;
    myl_block *bytes=core_io_padded((size_t)capacity);size_t written;int eof;
    int status=core_io_read(owner,block_data(bytes),(size_t)capacity,&written,&eof);
    return core_io_raw_result(status,bytes,status?0:written,status?0:eof);
}
myl_block *myl_core_resource_write(myl_block *owner,myl_block *input){CORE_IO_GUARD;
    size_t written;int status=core_io_write(owner,block_data(input),(size_t)input->len,&written);
    return core_io_result(status,status?0:written,NULL,0);
}
myl_block *myl_core_environment_raw(myl_block *cap,myl_block *name,uint64_t capacity){CORE_IO_GUARD;
    myl_block *bytes=core_io_padded((size_t)capacity);size_t length;int present;int status=core_io_environment_read(cap,name,block_data(bytes),(size_t)capacity,&length,&present);
    if(status)memset(block_data(bytes),0,(size_t)capacity);else if(capacity>length)memset(block_data(bytes)+length,0,(size_t)capacity-length);
    return core_io_raw_result(status,bytes,status?0:length,status?0:present);
}
