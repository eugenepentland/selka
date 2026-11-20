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
    CORE_IO_PROVIDER_NO_CAPACITY = 5,
    /* A connection given time limits (`network.connect_within`) did not connect, read or write in time. It is 7, not
       6, because the guest sees a provider status as its error code and 6 is a stand-in Network's `denied_here()`. */
    CORE_IO_PROVIDER_TIMED_OUT = 7
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
/* A bit no grant holds: `core_io_resource_acquire` adds it to the permissions it hands a filesystem provider's `acquire` when
   the capability is narrowed by `fs.dir`, so the provider resolves the joined path the way a granted root does, whichever
   root serves it. */
#define CORE_IO_PROVIDER_NARROWED 16u
typedef struct {
    void *context;
    unsigned permissions; /* read=1, write=2, complete=4, accept=8; intersection only */
    CoreIoResourceResult (*acquire)(void *, const uint8_t *, size_t, unsigned);
    CoreIoProviderStatus (*complete)(void *, uint64_t);
    void (*release)(void *, uint64_t);
    CoreIoResourceRead (*read)(void *, uint64_t, uint8_t *, size_t);
    CoreIoResourceWrite (*write)(void *, uint64_t, const uint8_t *, size_t);
} CoreIoResourceProvider;

/* The event loop lives in core_poll.c, concatenated after this file. A poller is
   one scoped handle: its listener, epoll set and connection table sit behind this
   pointer, and the handle's read and write carry the poller's responses and
   commands (docs/design/event-loop-2026-10-18.md). */
typedef struct CorePoller CorePoller;
static CorePoller *core_poll_create(int listener);  /* -1: a client's poller, with no listener */
static void core_poll_destroy(CorePoller *poller);
static int core_poll_epoll_descriptor(const CorePoller *poller);
static CoreIoResourceWrite core_poll_command(CorePoller *poller, const uint8_t *command, size_t length);
static CoreIoResourceRead core_poll_response(CorePoller *poller, uint8_t *out, size_t capacity);
static uint32_t core_poll_token(const CorePoller *poller);
static void core_poll_adopt(CorePoller *poller, int fd, uint32_t connect_ms);
static void core_poll_dial_failed(CorePoller *poller, int error);

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
extern CoreIoNativeProviders selka_native_providers_v7(void) __attribute__((weak));
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
   itself; every other root walks the path component by component, and so does
   the direct root for a request through a `fs.dir` narrowing (`CORE_IO_PROVIDER_NARROWED`). A `--restrict` grant also
   keeps its two absolute names, taken once when it is opened (docs/io.md, "How a path is read"): the name it was given,
   made absolute against the working directory as text, and its real path. Each is `""` for `/` and NULL when unknown;
   the given name is kept only when it names the same directory as the real one. */
typedef struct { int fd; int writable, direct; char *spelled, *real; size_t spelled_length, real_length; } CoreIoScopedRoot;
/* An open file, an append-mode file, or one immutable copied snapshot. `size` is a
   readable regular file's length when it was opened (0: unknown or not a regular
   file), the allocation hint of a whole-file read (NEW-CORE-FILE-READ-1). */
/* `timed` marks a connection dialled with a read or write time limit, whose EAGAIN is that limit running out. */
typedef struct { int fd; unsigned char *snapshot; size_t length, position; unsigned char mode, listening; size_t size; CorePoller *poller; unsigned char timed; } CoreIoScopedHandle;
/* One granted literal `IP:PORT` endpoint, or `*` for every literal peer. */
typedef struct { char *name; size_t length; } CoreIoScopedEndpoint;
typedef struct {
    CoreIoScopedRoot roots[CORE_IO_SCOPED_ROOTS];
    size_t count;
    CoreIoScopedHandle handles[CORE_IO_SCOPED_HANDLES];
    CoreIoScopedEndpoint endpoints[CORE_IO_SCOPED_ENDPOINTS];
    size_t endpoint_count;
    CoreIoScopedEndpoint listen_endpoints[CORE_IO_SCOPED_ENDPOINTS];
    size_t listen_count;
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
/* Record one literal `IP:PORT` local listening endpoint, rejecting a malformed
   or repeated value. A listen grant never permits an outbound connection. */
int core_io_scoped_listen_endpoint(CoreIoScoped *scoped, const char *name);
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
#include <poll.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>
#define CORE_IO_SCOPED_TRANSFER_LIMIT (64u * 1024u)
#define CORE_IO_SCOPED_NAME_LIMIT 4094u
/* Why the operating system, not the grant policy, refused the last file operation, or NULL when
   the policy did. A file operation clears it on entry (`myl_core_file_access`) and
   `core_io_reason` reads it, so "denied" never claims a grant when the system said "permission
   denied" or "is a directory" (FR-106). */
static const char *core_io_os_reason;
/* The two sentences for a path that is not there. A creating call that finds nothing says the second (`core_io_file_error`
   compares by address), because for it the missing thing is the folder it was to be made in. */
static const char core_io_reason_missing[] = "the path does not exist";
static const char core_io_reason_no_folder[] = "a folder on the way does not exist";
/* The one table from the system's `errno` to a sentence, for every file operation: the durable calls, the whole-file calls, the
   methods of an open file, the in-memory filesystem and the trap of a failed method. An error outside the table gives its
   number and the system's own words, so a reason is never lost; 0 is no error and has none. */
static const char *core_io_errno_reason(int error) {
    static char other[160];
    switch (error) {
        case 0: return NULL;
        case ENOENT: return core_io_reason_missing;
        case ENOSPC: return "no space left on the device";
        case EDQUOT: return "disk quota exceeded";
        case EFBIG: return "the file is too large for the size limit or for the filesystem";
        case EROFS: return "the filesystem is read-only";
        case EACCES: case EPERM: return "permission denied";
        case EMFILE: case ENFILE: return "too many files are open";
        case ENAMETOOLONG: return "the path, or a name in it, is too long";
        case EIO: return "input/output error";
        case EISDIR: return "is a directory";
        case ENOTDIR: return "a parent of the path is not a directory";
        case ELOOP: return "is a symbolic link the sandbox does not follow, or links nest too deeply";
        case EEXIST: return "already exists";
        case ENOTEMPTY: return "the directory is not empty";
        case EBUSY: return "is busy (in use, or a mount point)";
        case ETXTBSY: return "is a program that is running";
        case EXDEV: return "the paths are on different filesystems";
        case EBADF: return "the file is not open for this";
        case EPIPE: return "the other end of the pipe is closed";
        case ENXIO: case ENODEV: return "no device is behind this file";
        case EINTR: return "the operation was interrupted";
        default: break;
    }
    char words[120];
    snprintf(words, sizeof words, "%s", strerror(error));
    if (words[0] >= 'A' && words[0] <= 'Z' && words[1] >= 'a' && words[1] <= 'z') words[0] = (char)(words[0] - 'A' + 'a');
    snprintf(other, sizeof other, "error %d: %s", error, words);
    return other;
}
/* Status 3 (failed) for a system call that set `error`, with the system's reason for it. */
static int core_io_failed_with(int error) {
    core_io_os_reason = core_io_errno_reason(error);
    return 3;
}
static CoreIoProviderStatus core_io_scoped_from_errno(void) {
    if (errno == ENOMEM) return CORE_IO_PROVIDER_OUT_OF_MEMORY;
    core_io_os_reason = core_io_errno_reason(errno);
    switch (errno) {
        case EACCES: case EPERM: case ELOOP: case ENOTDIR: case EISDIR: return CORE_IO_PROVIDER_DENIED;
        default: return CORE_IO_PROVIDER_FAILED;
    }
}
/* The status and reason of a refusal the in-memory filesystem gives as the real one gives it for `error`. */
static CoreIoProviderStatus core_io_memory_errno(int error) {
    errno = error;
    return core_io_scoped_from_errno();
}
static int core_io_scoped_writing_mode(unsigned char mode) {
    return mode == 'w' || mode == 'a' || mode == 'c' || mode == 't' || mode == 'k' || mode == 'x';
}
/* Reject traversal before anything is opened, created or truncated. A backslash is a byte of a name on Linux, the one
   system this compiler targets, so `a\b` names a file in the folder and `..\x` is a name, not a climb (SP1B-F-6). */
static int core_io_scoped_valid_path(const char *path, size_t length, unsigned char mode) {
    if (!length) return mode == 'm' || mode == 'l';
    if (memchr(path, 0, length)) return 0;
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

/* ---- how a path is read under `--restrict` (docs/io.md, "How a path is read") ------------------------------------
 * A path is made absolute against the working directory taken when the run started and normalized as text: `.` and
 * empty components go, and `..` removes the component before it. The result must be one of a grant's two names or lie
 * below one, and the rest is walked down from the descriptor the grant opened at the start without following a link
 * (`core_io_scoped_walk`), so no spelling reaches a file outside every grant. A `..` that removes a component the
 * program wrote is accepted only when the walk finds that component a directory, not a link, inside a grant: otherwise
 * the system, which follows a link before it climbs, could name another directory than the text does. */
#define CORE_IO_SCOPED_PATH 4096u
/* The three refusals (docs/io.md, rule 5); the first two name a path and are formatted into `core_io_scoped_refusal`. */
#define CORE_IO_REFUSAL_OUTSIDE "denied: '%.*s' is outside the granted directories"
#define CORE_IO_REFUSAL_READ_ONLY_GRANT "denied: writing needs a write grant (--allow-write); '%.*s' is granted for reading only"
#define CORE_IO_REFUSAL_CLIMB "denied: '%.*s/..' climbs out of a granted directory named through a symbolic link"
#define CORE_IO_REFUSAL_READ_ONLY "denied: this Filesystem was narrowed by fs.read_only() and does not write"
#define CORE_IO_REFUSAL_NARROWED "denied: a Filesystem narrowed by fs.dir takes a path inside its folder, without '..', '.', an empty part or a leading '/'"
#define CORE_IO_REFUSAL_NUL "the path contains a NUL octet"
static char core_io_scoped_refusal[CORE_IO_SCOPED_PATH + 160];
/* The working directory when the first grant was opened, as the system names it, `""` for `/`. */
static char core_io_scoped_cwd[CORE_IO_SCOPED_PATH];
static size_t core_io_scoped_cwd_length;

/* Set the refusal `format` for the absolute `path` (`""` is `/`) and answer it as a denial. */
static CoreIoProviderStatus core_io_scoped_refuse(const char *format, const char *path, size_t length) {
    snprintf(core_io_scoped_refusal, sizeof core_io_scoped_refusal, format, length ? (int)length : 1, length ? path : "/");
    core_io_os_reason = core_io_scoped_refusal;
    return CORE_IO_PROVIDER_DENIED;
}

/* Append `path` to the absolute, normalized `out` (`*length` octets, `""` for `/`) as text: `.` and empty components
   go, `..` removes the last component. `floor` is the length of the part that came from the working directory and is
   lowered when `..` removes some of it; a `..` that removes a component above it calls `check` with the path that ends
   in that component first, and a `..` at the root calls it with the empty path. `*directory` is set when the path ends in `/`, `.` or `..`. Returns 0 or the status of a
   refusal (the reason set). */
typedef CoreIoProviderStatus (*CoreIoScopedCheck)(void *context, const char *path, size_t length);
static CoreIoProviderStatus core_io_path_normalize(const char *path, size_t width, char *out, size_t *length, size_t *floor,
                                                   CoreIoScopedCheck check, void *context, int *directory) {
    *directory = 0;
    for (size_t start = 0, i = 0; i <= width; ++i) {
        if (i != width && path[i] != '/') continue;
        const char *part = path + start;
        const size_t size = i - start;
        start = i + 1;
        *directory = 1;
        if (!size || (size == 1 && part[0] == '.')) continue;
        if (size == 2 && part[0] == '.' && part[1] == '.') {
            if (!*length) {
                /* `/..` is `/` to the system; a filesystem whose root is not `/` refuses it in `check`. */
                CoreIoProviderStatus status = check ? check(context, out, 0) : CORE_IO_PROVIDER_OK;
                if (status) return status;
                continue;
            }
            size_t at = *length;
            while (out[at - 1] != '/') --at;
            if (at - 1 >= *floor) {
                CoreIoProviderStatus status = check ? check(context, out, *length) : CORE_IO_PROVIDER_OK;
                if (status) return status;
            } else *floor = at - 1;
            *length = at - 1;
            continue;
        }
        *directory = 0;
        if (*length + 1 + size >= CORE_IO_SCOPED_PATH) { errno = ENAMETOOLONG; return core_io_scoped_from_errno(); }
        out[(*length)++] = '/';
        memcpy(out + *length, part, size);
        *length += size;
    }
    return CORE_IO_PROVIDER_OK;
}

/* Whether the absolute `name` (`""` is `/`) is `path` or holds it, and where the part below it starts. */
static int core_io_scoped_holds(const char *name, size_t width, const char *path, size_t length, size_t *rest) {
    if (!name || length < width || memcmp(name, path, width) || (length > width && path[width] != '/')) return 0;
    *rest = length > width ? width + 1 : length;
    return 1;
}

/* The grant that holds the absolute, normalized `path`, the longest name first; -1 when none does. Only writable grants
   count when `writing`. `*rest` is where the part below the grant starts, and `*spelled` is set when only the given name,
   which differs from the real one, holds it. */
static long core_io_scoped_holder(const CoreIoScoped *scoped, const char *path, size_t length, int writing, size_t *rest, int *spelled) {
    long best = -1;
    size_t longest = 0;
    for (size_t i = 0; i < scoped->count; ++i) {
        const CoreIoScopedRoot *root = &scoped->roots[i];
        if (writing && !root->writable) continue;
        size_t below = 0;
        int real = core_io_scoped_holds(root->real, root->real_length, path, length, &below);
        int given = !real && core_io_scoped_holds(root->spelled, root->spelled_length, path, length, &below);
        if ((!real && !given) || (best >= 0 && below <= longest)) continue;
        best = (long)i;
        longest = below;
        *rest = below;
        *spelled = given && strcmp(root->spelled, root->real);
    }
    return best;
}

/* The `check` of `core_io_path_normalize` under `--restrict`: the component a `..` removes must be a directory inside a
   grant, reached without a link, and not a grant named through a link. */
static CoreIoProviderStatus core_io_scoped_climb(void *context, const char *path, size_t length) {
    const CoreIoScoped *scoped = context;
    size_t rest = 0;
    int spelled = 0;
    if (!length) return CORE_IO_PROVIDER_OK;
    long holder = core_io_scoped_holder(scoped, path, length, 0, &rest, &spelled);
    if (holder < 0) return core_io_scoped_refuse(CORE_IO_REFUSAL_OUTSIDE, path, length);
    if (rest == length) return spelled ? core_io_scoped_refuse(CORE_IO_REFUSAL_CLIMB, path, length) : CORE_IO_PROVIDER_OK;
    char below[CORE_IO_SCOPED_PATH + 1];
    size_t width = length - rest;
    memcpy(below, path + rest, width);
    below[width++] = '/';
    size_t last = 0;
    int root = scoped->roots[holder].fd;
    int fd = core_io_scoped_walk(root, below, width, &last);
    if (fd < 0) return core_io_scoped_from_errno();
    if (fd != root) close(fd);
    return CORE_IO_PROVIDER_OK;
}

/* The common case, worked out once when a grant is opened: the grant that holds the working directory for a read (`[0]`)
   and for a write (`[1]`), -1 for none, and where the working directory's part below it starts. A clean relative path
   (no empty, `.` or `..` component) is then the working directory's part and the path, with no text to normalize and no
   grant to search. It is unset (`core_io_scoped_cwd_for` NULL) when a grant lies below the working directory, which could
   hold such a path instead. */
static long core_io_scoped_cwd_holder[2];
static size_t core_io_scoped_cwd_rest[2];
static const CoreIoScoped *core_io_scoped_cwd_for;
static void core_io_scoped_cwd_prepare(const CoreIoScoped *scoped) {
    core_io_scoped_cwd_for = NULL;
    for (size_t i = 0; i < scoped->count; ++i) {
        const CoreIoScopedRoot *root = &scoped->roots[i];
        size_t below = 0;
        if (core_io_scoped_holds(core_io_scoped_cwd, core_io_scoped_cwd_length, root->real, root->real_length, &below) &&
            root->real_length > core_io_scoped_cwd_length) return;
        if (root->spelled && core_io_scoped_holds(core_io_scoped_cwd, core_io_scoped_cwd_length, root->spelled, root->spelled_length, &below) &&
            root->spelled_length > core_io_scoped_cwd_length) return;
    }
    for (int writing = 0; writing < 2; ++writing) {
        int spelled = 0;
        core_io_scoped_cwd_rest[writing] = 0;
        core_io_scoped_cwd_holder[writing] = core_io_scoped_holder(scoped, core_io_scoped_cwd, core_io_scoped_cwd_length, writing,
                                                                   &core_io_scoped_cwd_rest[writing], &spelled);
    }
    core_io_scoped_cwd_for = scoped;
}

/* Whether `path` is relative with no empty, `.` or `..` component: the old rule of a scoped root (`core_io_scoped_valid_path`). */
static int core_io_scoped_clean(const char *path, size_t width) {
    return width && path[0] != '/' && core_io_scoped_valid_path(path, width, 'r');
}

/* Resolve `path` under `--restrict`: the grant that serves it (`*root`), the part below that grant (`rest`, at most
   `CORE_IO_SCOPED_PATH` octets with its NUL, `""` for the grant itself) and whether it must name a directory. A path
   outside every grant, or inside only a read grant for a call that writes, is refused with its own text. */
static CoreIoProviderStatus core_io_scoped_resolve(CoreIoScoped *scoped, const char *path, size_t width, int writing, size_t *root,
                                                   char *rest, int *directory) {
    if (scoped == core_io_scoped_cwd_for && core_io_scoped_cwd_holder[writing] >= 0 && core_io_scoped_clean(path, width)) {
        const size_t from = core_io_scoped_cwd_rest[writing];
        size_t prefix = core_io_scoped_cwd_length - from;
        if (prefix + 1 + width < CORE_IO_SCOPED_PATH) {
            memcpy(rest, core_io_scoped_cwd + from, prefix);
            if (prefix) rest[prefix++] = '/';
            memcpy(rest + prefix, path, width);
            rest[prefix + width] = 0;
            *root = (size_t)core_io_scoped_cwd_holder[writing];
            *directory = 0;
            return CORE_IO_PROVIDER_OK;
        }
    }
    char absolute[CORE_IO_SCOPED_PATH];
    size_t length = 0, floor = 0;
    if (!width || path[0] != '/') {
        memcpy(absolute, core_io_scoped_cwd, core_io_scoped_cwd_length);
        length = floor = core_io_scoped_cwd_length;
    }
    CoreIoProviderStatus status = core_io_path_normalize(path, width, absolute, &length, &floor, core_io_scoped_climb, scoped, directory);
    if (status) return status;
    size_t below = 0;
    int spelled = 0;
    long holder = core_io_scoped_holder(scoped, absolute, length, writing, &below, &spelled);
    if (holder < 0) {
        int readable = writing && core_io_scoped_holder(scoped, absolute, length, 0, &below, &spelled) >= 0;
        return core_io_scoped_refuse(readable ? CORE_IO_REFUSAL_READ_ONLY_GRANT : CORE_IO_REFUSAL_OUTSIDE, absolute, length);
    }
    *root = (size_t)holder;
    memcpy(rest, absolute + below, length - below);
    rest[length - below] = 0;
    return CORE_IO_PROVIDER_OK;
}

/* Under `--restrict`, a path that must name a directory (it ends in `/`, `.` or `..`): its final component `name` in
   `parent` must be one, and not a link, which the system would follow there. A call that creates a file at a missing
   name fails as `open` does for such a path; `mkdir` makes it. */
static int core_io_scoped_directory_leaf(int parent, const char *name, unsigned char mode) {
    struct stat info;
    if (!*name) return 0;
    if (fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW)) {
        if (errno != ENOENT || mode == 'k') return errno == ENOENT ? 0 : -1;
        if (mode == 'c' || mode == 't' || mode == 'w' || mode == 'a') errno = EISDIR;
        return -1;
    }
    if (S_ISLNK(info.st_mode)) { errno = ELOOP; return -1; }
    if (!S_ISDIR(info.st_mode)) { errno = ENOTDIR; return -1; }
    return 0;
}
/* A scoped root opens its leaf without blocking, so a FIFO it is about to
   refuse cannot stall the guest waiting for a writer; the flag is cleared
   again once the leaf is known to be a regular file. The direct root (`blocking`)
   blocks exactly as an ordinary `open` does. `follow` is set for the direct root
   alone, not through a narrowing: it follows a final link, every other root
   refuses one (`O_NOFOLLOW`), an append included: through a link it writes
   nothing and creates nothing, a dangling link too. */
static int core_io_scoped_open_leaf(int parent, const char *name, unsigned char mode, int blocking, int follow) {
    int waiting = blocking ? 0 : O_NONBLOCK;
    int refusing = follow ? 0 : O_NOFOLLOW;
    if (mode == 'c') return openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | waiting, 0666);
    if (mode == 'a') return openat(parent, name, O_WRONLY | O_CREAT | O_CLOEXEC | waiting | refusing, 0666);
    int flags = mode == 'r' ? O_RDONLY : O_WRONLY;
    return openat(parent, name, flags | refusing | O_CLOEXEC | waiting);
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
/* The kind of one directory entry, from its record's own `d_type`: 1 regular file, 2 directory, 3 symbolic link, 0 anything
   else. One `fstatat` (the link itself, not followed) answers only for a record that carries no type (`DT_UNKNOWN`, which
   some filesystems report for every entry). */
static unsigned char core_io_scoped_entry_kind(DIR *directory, const struct dirent *entry) {
    switch (entry->d_type) {
        case DT_REG: return 1;
        case DT_DIR: return 2;
        case DT_LNK: return 3;
        case DT_UNKNOWN: {
            struct stat info;
            if (!fstatat(dirfd(directory), entry->d_name, &info, AT_SYMLINK_NOFOLLOW)) return core_io_scoped_kind_of(info.st_mode);
            return 0;
        }
        default: return 0;
    }
}
/* Copy one directory's entries into a snapshot: a leading 1, then a kind
   byte, a little-endian u16 name length and the name for each entry. The kind
   is the directory record's own (`d_type`), and one `fstatat` answers only for
   a record that does not carry one (`DT_UNKNOWN`). The snapshot grows with the
   directory; the run's byte ceiling bounds the copies the caller makes of it. */
static unsigned char *core_io_scoped_listing(int parent, const char *name, size_t *length, CoreIoProviderStatus *status, int follow) {
    /* The direct root lists what a symbolic link names, as it reads and tests one; a granted root refuses the link. */
    int fd = openat(parent, *name ? name : ".", O_RDONLY | O_DIRECTORY | (follow ? 0 : O_NOFOLLOW) | O_CLOEXEC);
    if (fd < 0) {
        const int refused = errno;
        *status = core_io_scoped_from_errno();
        /* ENOTDIR names either the path itself or one of its parents: say which. */
        struct stat leaf;
        if (refused == ENOTDIR && !fstatat(parent, name, &leaf, AT_SYMLINK_NOFOLLOW) && !S_ISDIR(leaf.st_mode)) core_io_os_reason = "is not a directory";
        return NULL;
    }
    DIR *directory = fdopendir(fd);
    if (!directory) { *status = core_io_scoped_from_errno(); close(fd); return NULL; }
    size_t capacity = 1024, used = 1;
    unsigned char *bytes = malloc(capacity);
    *status = CORE_IO_PROVIDER_OUT_OF_MEMORY;
    if (bytes) bytes[0] = 1;
    struct dirent *entry;
    while (bytes && (errno = 0, entry = readdir(directory))) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        size_t width = strlen(entry->d_name);
        if (!width || width > CORE_IO_SCOPED_NAME_LIMIT) { *status = CORE_IO_PROVIDER_DENIED; core_io_os_reason = "has an entry whose name is too long"; free(bytes); bytes = NULL; break; }
        while (used + width + 3 > capacity) {
            unsigned char *grown = capacity > SIZE_MAX / 2 ? NULL : realloc(bytes, capacity * 2);
            if (!grown) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; free(bytes); bytes = NULL; break; }
            bytes = grown;
            capacity *= 2;
        }
        if (!bytes) break;
        unsigned char kind = core_io_scoped_entry_kind(directory, entry);
        bytes[used++] = kind;
        bytes[used++] = (unsigned char)(width & 0xff);
        bytes[used++] = (unsigned char)((width >> 8) & 0xff);
        memcpy(bytes + used, entry->d_name, width);
        used += width;
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
        if (mkdirat(parent, name, 0777)) {
            *status = core_io_scoped_from_errno();
            if (errno == ENOENT) core_io_os_reason = "the parent directory does not exist";
            return NULL;
        }
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
/* `flags` of `core_io_scoped_acquire_in`: the request came through a `fs.dir` narrowing, and the path must name a directory. */
#define CORE_IO_SCOPED_NARROWED_PATH 1
#define CORE_IO_SCOPED_DIRECTORY_PATH 2
/* A descriptor of `/`, opened once and kept for the run: the root from which a `fs.dir` narrowing to an absolute folder
   (`filesystem.dir_at` in a run without `--restrict`) is walked, without a link, as any narrowing is. -1 with `errno` set
   when `/` cannot be opened. */
static int core_io_slash(void) {
    static int slash = -1;
    int fd = __atomic_load_n(&slash, __ATOMIC_ACQUIRE);
    if (fd >= 0) return fd;
    fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return -1;
    int expected = -1;
    if (__atomic_compare_exchange_n(&slash, &expected, fd, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) return fd;
    close(fd);
    return expected;
}
static CoreIoResourceResult core_io_scoped_acquire_in(CoreIoScoped *scoped, CoreIoScopedRoot entry, unsigned char mode, const char *path, size_t length, int flags) {
    CoreIoResourceResult result = {CORE_IO_PROVIDER_FAILED, 0};
    int root = entry.fd;
    size_t slot = core_io_scoped_free_slot(scoped);
    if (slot == SIZE_MAX) { core_io_os_reason = "too many files are open"; result.status = CORE_IO_PROVIDER_DENIED; return result; }
    size_t last = 0;
    /* A direct root hands the whole path to one operation, the way an ordinary
       process resolves it; a scoped root, and a direct root under a `fs.dir`
       narrowing, open each component without symlinks. */
    const int follow = entry.direct && !(flags & CORE_IO_SCOPED_NARROWED_PATH);
    int parent = follow ? root : core_io_scoped_walk(root, path, length, &last);
    if (parent < 0) {
        result.status = core_io_scoped_from_errno();
        if (errno == ENOENT && mode == 'k') core_io_os_reason = "the parent directory does not exist";
        return result;
    }
    char name[CORE_IO_SCOPED_NAME_LIMIT + 1];
    size_t width = length - last;
    if (width > CORE_IO_SCOPED_NAME_LIMIT) { if (parent != root) close(parent); errno = ENAMETOOLONG; result.status = core_io_scoped_from_errno(); return result; }
    memcpy(name, path + last, width);
    name[width] = 0;
    if ((flags & CORE_IO_SCOPED_DIRECTORY_PATH) && core_io_scoped_directory_leaf(parent, name, mode)) {
        result.status = core_io_scoped_from_errno();
        if (parent != root) close(parent);
        return result;
    }
    if (!*name && mode == 'k') { if (parent != root) close(parent); errno = EEXIST; result.status = core_io_scoped_from_errno(); return result; }
    if (!*name && mode == 'x') {
        if (parent != root) close(parent);
        core_io_os_reason = "denied: a granted directory itself is not removed";
        result.status = CORE_IO_PROVIDER_DENIED;
        return result;
    }
    if (mode == 'm' || mode == 'l' || mode == 'k' || mode == 'x') {
        size_t bytes = 0;
        unsigned char *snapshot = mode == 'l' ? core_io_scoped_listing(parent, name, &bytes, &result.status, follow) : core_io_scoped_change(parent, name, mode, &bytes, &result.status);
        if (parent != root) close(parent);
        if (!snapshot) return result;
        scoped->handles[slot] = (CoreIoScopedHandle){-1, snapshot, bytes, 0, mode};
        result.handle = slot;
        return result;
    }
    int fd = core_io_scoped_open_leaf(parent, *name ? name : ".", mode, entry.direct, follow);
    if (parent != root) close(parent);
    if (fd < 0) { result.status = core_io_scoped_from_errno(); return result; }
    struct stat info;
    if (fstat(fd, &info)) { result.status = core_io_scoped_from_errno(); close(fd); return result; }
    if (!core_io_scoped_usable(entry, fd, &info)) {
        core_io_os_reason = S_ISDIR(info.st_mode) ? "is a directory" : "is not a regular file";
        result.status = CORE_IO_PROVIDER_DENIED;
        close(fd);
        return result;
    }
    /* Only a regular file has contents to truncate; a FIFO or device has none. */
    if (mode == 't' && S_ISREG(info.st_mode) && ftruncate(fd, 0)) { result.status = core_io_scoped_from_errno(); close(fd); return result; }
    scoped->handles[slot] = (CoreIoScopedHandle){fd, NULL, 0, 0, mode, 0, mode == 'r' && S_ISREG(info.st_mode) && info.st_size > 0 ? (size_t)info.st_size : 0};
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
    const int narrowed = (permissions & CORE_IO_PROVIDER_NARROWED) != 0;
    if (memchr(path, 0, width)) { core_io_os_reason = CORE_IO_REFUSAL_NUL; return result; }
    /* Without `--restrict` the one direct root takes the path as an ordinary process does (a narrowing's path was checked
       by `core_io_resource_acquire`); under it the path is resolved and served by the one grant that holds it. */
    if (scoped->roots[0].direct) {
        CoreIoScopedRoot entry = scoped->roots[0];
        /* Only a narrowing to an absolute folder (`filesystem.dir_at`) puts a `/` first; it is walked from `/`. */
        if (narrowed && width && path[0] == '/') {
            entry.fd = core_io_slash();
            if (entry.fd < 0) { result.status = core_io_scoped_from_errno(); return result; }
            ++path;
            --width;
        }
        if (narrowed && !core_io_scoped_valid_path(path, width, mode)) { core_io_os_reason = CORE_IO_REFUSAL_NARROWED; return result; }
        return core_io_scoped_acquire_in(scoped, entry, mode, path, width, narrowed ? CORE_IO_SCOPED_NARROWED_PATH : 0);
    }
    if (!width && mode != 'm' && mode != 'l') { errno = ENOENT; result.status = core_io_scoped_from_errno(); return result; }
    char rest[CORE_IO_SCOPED_PATH];
    size_t root = 0;
    int directory = 0;
    result.status = core_io_scoped_resolve(scoped, path, width, core_io_scoped_writing_mode(mode), &root, rest, &directory);
    if (result.status) return result;
    return core_io_scoped_acquire_in(scoped, scoped->roots[root], mode, rest, strlen(rest),
                                     CORE_IO_SCOPED_NARROWED_PATH | (directory ? CORE_IO_SCOPED_DIRECTORY_PATH : 0));
}
static void core_io_scoped_shut(CoreIoScopedHandle *handle) {
    /* A poller closes its listener and connections; `fd` is its epoll descriptor. */
    if (handle->poller) core_poll_destroy(handle->poller);
    if (handle->fd >= 0) close(handle->fd);
    free(handle->snapshot);
    *handle = (CoreIoScopedHandle){-1, NULL, 0, 0, 0, 0};
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
/* Whether the transfer that just failed on `handle` ran out of the time limit its connection was dialled with: only such a
   socket has SO_RCVTIMEO or SO_SNDTIMEO set, and on it EAGAIN means the limit passed with nothing moved. */
static int core_io_scoped_timed_out(const CoreIoScopedHandle *handle) {
    return handle->timed && (errno == EAGAIN || errno == EWOULDBLOCK);
}
static CoreIoResourceRead core_io_scoped_read_handle(void *context, uint64_t id, uint8_t *output, size_t capacity) {
    CoreIoResourceRead result = {CORE_IO_PROVIDER_FAILED, 0, 0};
    CoreIoScoped *scoped = context;
    CoreIoScopedHandle *handle = core_io_scoped_live(scoped, id);
    if (!handle) return result;
    if (handle->poller) return core_poll_response(handle->poller, output, capacity);
    /* A listener's read is the runtime's accept channel: eight octets carry the
       new slot. This keeps the provider ABI and reuses handle ownership. */
    if (handle->listening) {
        if (!capacity) { result.status = CORE_IO_PROVIDER_OK; return result; }
        if (capacity < sizeof(uint64_t)) { result.status = CORE_IO_PROVIDER_DENIED; return result; }
        core_flush_before_wait();
        int accepted = accept4(handle->fd, NULL, NULL, SOCK_CLOEXEC);
        if (accepted < 0) { result.status = CORE_IO_PROVIDER_FAILED; return result; }
        size_t slot = core_io_scoped_free_slot(scoped);
        if (slot == SIZE_MAX) { close(accepted); result.status = CORE_IO_PROVIDER_NO_CAPACITY; return result; }
        scoped->handles[slot] = (CoreIoScopedHandle){accepted, NULL, 0, 0, 0, 0};
        uint64_t raw = (uint64_t)slot;
        memcpy(output, &raw, sizeof raw);
        result.status = CORE_IO_PROVIDER_OK;
        result.length = sizeof raw;
        result.eof = 0;
        return result;
    }
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
    core_flush_before_wait();
    ssize_t width;
    /* A socket with a `read_ms` limit is not restarted after the stop handler ran (SO_RCVTIMEO): it resumes, the limit
       counting again from the interruption (FR5b). A program without a `Stop` has no handler and no interruption. */
    do width = read(handle->fd, output, capacity); while (width < 0 && errno == EINTR && core_stop_installed());
    if (width < 0) { result.status = core_io_scoped_timed_out(handle) ? CORE_IO_PROVIDER_TIMED_OUT : core_io_scoped_from_errno(); return result; }
    result.status = CORE_IO_PROVIDER_OK;
    result.length = (size_t)width;
    result.eof = width == 0;
    return result;
}
static CoreIoResourceWrite core_io_scoped_write_handle(void *context, uint64_t id, const uint8_t *input, size_t length) {
    CoreIoResourceWrite result = {CORE_IO_PROVIDER_FAILED, 0};
    CoreIoScopedHandle *handle = core_io_scoped_live(context, id);
    if (handle && handle->poller) return core_poll_command(handle->poller, input, length);
    if (!handle || handle->snapshot || handle->listening) { result.status = handle ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return result; }
    if (length > CORE_IO_SCOPED_TRANSFER_LIMIT) length = CORE_IO_SCOPED_TRANSFER_LIMIT;
    ssize_t width;
    if (handle->mode == 'a') {
        off_t end = lseek(handle->fd, 0, SEEK_END);
        if (end < 0) { result.status = core_io_scoped_from_errno(); return result; }
        width = pwrite(handle->fd, input, length, end);
    } else do width = write(handle->fd, input, length); while (width < 0 && errno == EINTR && core_stop_installed());
    if (width < 0) { result.status = core_io_scoped_timed_out(handle) ? CORE_IO_PROVIDER_TIMED_OUT : core_io_scoped_from_errno(); return result; }
    result.status = CORE_IO_PROVIDER_OK;
    result.length = (size_t)width;
    return result;
}
/* Parse one `IP:PORT` into a numeric address: a dotted IPv4 address as inet_pton reads it, a colon, and the port as one
   to five decimal digits up to the end, with no sign, space or trailing text, so a configured `127.0.0.1:80 ` is refused
   rather than read as port 80 (FR5a). No name resolution or redirect following occurs, so the core_io_scoped_grant and
   the connect name the same peer. */
static int core_io_scoped_endpoint_address_in(const char *name, struct sockaddr_in *address, int allow_port_zero) {
    const char *colon = strrchr(name, ':');
    if (!colon || colon == name) return 0;
    char host[64];
    size_t width = (size_t)(colon - name);
    if (width >= sizeof host) return 0;
    memcpy(host, name, width);
    host[width] = 0;
    const char *digits = colon + 1;
    size_t count = strlen(digits);
    if (!count || count > 5 || strspn(digits, "0123456789") != count) return 0;
    unsigned long port = strtoul(digits, NULL, 10);
    /* Port zero asks the kernel for a free port, which only a listener may do. */
    if (!port && !allow_port_zero) return 0;
    if (port > 65535) return 0;
    struct sockaddr_in parsed;
    memset(&parsed, 0, sizeof parsed);
    parsed.sin_family = AF_INET;
    parsed.sin_port = htons((unsigned short)port);
    if (inet_pton(AF_INET, host, &parsed.sin_addr) != 1) return 0;
    *address = parsed;
    return 1;
}
static int core_io_scoped_endpoint_address(const char *name, struct sockaddr_in *address) {
    return core_io_scoped_endpoint_address_in(name, address, 0);
}
/* An allowlist entry is matched verbatim; `*` names every literal peer. */
static int core_io_scoped_listed(const CoreIoScopedEndpoint *entries, size_t count, const char *name, size_t length) {
    for (size_t i = 0; i < count; ++i) {
        const CoreIoScopedEndpoint *entry = &entries[i];
        if (entry->length == 1 && entry->name[0] == '*') return 1;
        if (entry->length == length && !memcmp(entry->name, name, length)) return 1;
    }
    return 0;
}
static int core_io_scoped_endpoint_allowed(const CoreIoScoped *scoped, const char *name, size_t length) {
    return core_io_scoped_listed(scoped->endpoints, scoped->endpoint_count, name, length);
}
static int core_io_scoped_listen_allowed(const CoreIoScoped *scoped, const char *name, size_t length) {
    return core_io_scoped_listed(scoped->listen_endpoints, scoped->listen_count, name, length);
}
static int core_io_scoped_dial(const char *name) {
    struct sockaddr_in address;
    if (!core_io_scoped_endpoint_address(name, &address)) return -1;
    int handle = socket(AF_INET, SOCK_STREAM, 0);
    if (handle < 0) return -1;
    core_flush_before_wait();
    if (connect(handle, (struct sockaddr *)&address, sizeof address)) { close(handle); return -1; }
    return handle;
}
/* The time limits of `network.connect_within`, in milliseconds, and the receive buffer it asks for, in bytes; 0 is no
   limit and the system's buffer. */
typedef struct { uint32_t connect_ms, read_ms, write_ms, receive_bytes; } CoreIoDialLimits;
/* A TCP socket for `address`, with the receive buffer `receive_bytes` (0 keeps the system's) set before the connect, as
   the window it advertises is fixed then. Linux doubles the number for its bookkeeping, keeps at least about 2 KiB and at
   most `net.core.rmem_max`. */
static int core_io_scoped_socket(uint32_t receive_bytes, int flags) {
    int handle = socket(AF_INET, SOCK_STREAM | flags, 0);
    if (handle < 0) return -1;
    if (receive_bytes) {
        int wanted = receive_bytes > 1073741824u ? 1073741824 : (int)receive_bytes;
        if (setsockopt(handle, SOL_SOCKET, SO_RCVBUF, &wanted, sizeof wanted)) { close(handle); return -1; }
    }
    return handle;
}
static int64_t core_io_scoped_now_ms(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}
/* Arm one of SO_RCVTIMEO and SO_SNDTIMEO; a limit of 0 leaves the socket blocking without a bound. */
static int core_io_scoped_arm(int handle, int option, uint32_t millis) {
    if (!millis) return 0;
    struct timeval limit = {.tv_sec = millis / 1000, .tv_usec = (millis % 1000) * 1000};
    return setsockopt(handle, SOL_SOCKET, option, &limit, sizeof limit);
}
/* Dial `name` within `limits`: a nonblocking connect waited on with poll for at most `connect_ms` (no limit at 0), then a
   blocking socket whose reads and writes give up after `read_ms` and `write_ms`. Returns the socket, or -1 with `*status`
   set to CORE_IO_PROVIDER_TIMED_OUT when the connect ran out of time and CORE_IO_PROVIDER_FAILED otherwise. No thread
   and no signal: the deadline is poll's timeout, measured again after an interrupted poll. */
static int core_io_scoped_dial_within(const char *name, CoreIoDialLimits limits, CoreIoProviderStatus *status) {
    *status = CORE_IO_PROVIDER_FAILED;
    struct sockaddr_in address;
    if (!core_io_scoped_endpoint_address(name, &address)) return -1;
    core_flush_before_wait();
    if (!limits.connect_ms) {
        int handle = core_io_scoped_socket(limits.receive_bytes, 0);
        if (handle < 0) return -1;
        if (connect(handle, (struct sockaddr *)&address, sizeof address)) { close(handle); return -1; }
        if (core_io_scoped_arm(handle, SO_RCVTIMEO, limits.read_ms) || core_io_scoped_arm(handle, SO_SNDTIMEO, limits.write_ms)) { close(handle); return -1; }
        return handle;
    }
    int handle = core_io_scoped_socket(limits.receive_bytes, SOCK_NONBLOCK);
    if (handle < 0) return -1;
    if (connect(handle, (struct sockaddr *)&address, sizeof address)) {
        if (errno != EINPROGRESS) { close(handle); return -1; }
        int64_t deadline = core_io_scoped_now_ms() + limits.connect_ms;
        for (;;) {
            int64_t remaining = deadline - core_io_scoped_now_ms();
            if (remaining <= 0) { close(handle); *status = CORE_IO_PROVIDER_TIMED_OUT; return -1; }
            struct pollfd wanted = {.fd = handle, .events = POLLOUT};
            int ready = poll(&wanted, 1, remaining > 86400000 ? 86400000 : (int)remaining);
            if (ready < 0 && errno == EINTR) continue;
            if (ready < 0) { close(handle); return -1; }
            if (ready == 0) { close(handle); *status = CORE_IO_PROVIDER_TIMED_OUT; return -1; }
            break;
        }
        int error = 0;
        socklen_t width = sizeof error;
        if (getsockopt(handle, SOL_SOCKET, SO_ERROR, &error, &width) || error) { close(handle); return -1; }
    }
    int flags = fcntl(handle, F_GETFL);
    if (flags < 0 || fcntl(handle, F_SETFL, flags & ~O_NONBLOCK) < 0) { close(handle); return -1; }
    if (core_io_scoped_arm(handle, SO_RCVTIMEO, limits.read_ms) || core_io_scoped_arm(handle, SO_SNDTIMEO, limits.write_ms)) { close(handle); return -1; }
    return handle;
}
/* The request of `network.connect_within`: mode tag 3, then the connect, read and write limits as little-endian u32
   milliseconds and the receive buffer in bytes, then (after narrowing) the endpoint. */
#define CORE_IO_DIAL_LIMITS_TAG 3u
#define CORE_IO_DIAL_LIMITS_HEADER 17u
/* The request of `network.dial_within`: mode tag 4, the token of the poller that takes the connection, its connect limit
   in milliseconds and its receive buffer in bytes (little-endian u32 each), then (after narrowing) the endpoint. The
   connection is the poller's, never a resource of the program's, so this acquisition answers FAILED after leaving the
   dial's outcome as the poller's next response. */
#define CORE_IO_POLL_DIAL_TAG 4u
#define CORE_IO_POLL_DIAL_HEADER 13u
/* The request of `network.open_client_poller`: mode tag 5 alone, or (through a `net.host` narrowing) with the narrowing's
   endpoint after it. A poller that listens on nothing and holds only the connections its program dials. */
#define CORE_IO_CLIENT_POLLER_TAG 5u
/* The flag of an addressed request (FR5a: `network.connect_to`, `connect_within_to`, `listen_at`, `open_poller_at`,
   `dial_to`, `dial_within_to`): the mode tag with this bit set, the mode's header, then the address as a value. Without
   it a request is the narrowed form, whose address the narrowing supplies. */
#define CORE_IO_ADDRESSED 0x80u
/* The header of an addressed request with mode tag `tag`, flag included: 1 for listen (1) and a poller (2), the limits of
   connect_within (3), and the token and limits of a poller's dial (4). */
static size_t core_io_addressed_header(unsigned char tag) {
    unsigned mode = tag & ~CORE_IO_ADDRESSED;
    return mode == CORE_IO_DIAL_LIMITS_TAG ? CORE_IO_DIAL_LIMITS_HEADER : mode == CORE_IO_POLL_DIAL_TAG ? CORE_IO_POLL_DIAL_HEADER : 1;
}
static uint32_t core_io_scoped_word(const uint8_t *at) {
    return (uint32_t)at[0] | (uint32_t)at[1] << 8 | (uint32_t)at[2] << 16 | (uint32_t)at[3] << 24;
}
static int core_io_scoped_open_listener(const char *name) {
    struct sockaddr_in address;
    if (!core_io_scoped_endpoint_address_in(name, &address, 1)) return -1;
    int handle = socket(AF_INET, SOCK_STREAM, 0);
    if (handle < 0) return -1;
    int yes = 1;
    (void)setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    /* The system maximum, which the kernel clamps to net.core.somaxconn: a poller that holds 1,024
       connections must not drop the SYNs of clients that arrive faster than it accepts (FR-224). */
    if (bind(handle, (struct sockaddr *)&address, sizeof address) || listen(handle, SOMAXCONN)) {
        close(handle);
        return -1;
    }
    return handle;
}
/* Start a nonblocking connect to the granted endpoint `name` and give the socket to the poller whose token is `token`,
   which answers its next read with the dial's outcome: the new connection's id, or the failure that was known at once.
   Nothing waits: the poller learns that the connect finished, or failed, or ran out of `connect_ms`, in a later `wait`.
   The acquisition itself always answers FAILED, so the program owns no new resource; a token that names no poller
   leaves the poller's response empty, which the standard library reads as a refusal. */
static CoreIoResourceResult core_io_scoped_poll_dial(CoreIoScoped *scoped, uint32_t token, const char *name, CoreIoDialLimits limits) {
    CoreIoResourceResult result = {CORE_IO_PROVIDER_FAILED, 0};
    CorePoller *poller = NULL;
    for (size_t i = 0; i < CORE_IO_SCOPED_HANDLES && !poller; ++i)
        if (scoped->handles[i].poller && core_poll_token(scoped->handles[i].poller) == token) poller = scoped->handles[i].poller;
    if (!poller) return result;
    struct sockaddr_in address;
    if (!core_io_scoped_endpoint_address(name, &address)) { core_poll_dial_failed(poller, EINVAL); return result; }
    int handle = core_io_scoped_socket(limits.receive_bytes, SOCK_NONBLOCK | SOCK_CLOEXEC);
    if (handle < 0) { core_poll_dial_failed(poller, errno); return result; }
    int status;
    do status = connect(handle, (struct sockaddr *)&address, sizeof address); while (status < 0 && errno == EINTR);
    if (status < 0 && errno != EINPROGRESS) { int error = errno; close(handle); core_poll_dial_failed(poller, error); return result; }
    core_poll_adopt(poller, handle, limits.connect_ms);
    return result;
}
/* Open a poller that listens on nothing (`network.open_client_poller`). It needs no listen grant, since it binds no socket, and
   no endpoint of its own: each dial it takes is checked against `--allow-endpoint` when the dial is made. It does need the
   connect grant to exist (UNAVAILABLE, as for a connect, when the launch grants no endpoint at all), and through a narrowed
   Network (`name` is the narrowing's endpoint) that endpoint must be granted, as for a connect. */
static CoreIoResourceResult core_io_scoped_open_client_poller(CoreIoScoped *scoped, const uint8_t *name, size_t width, unsigned permissions) {
    CoreIoResourceResult result = {CORE_IO_PROVIDER_DENIED, 0};
    /* Read, write and complete: a poller is read and written for its whole table, and nothing in it accepts. */
    if (!scoped->endpoint_count || (permissions & 7u) != 7u) { result.status = CORE_IO_PROVIDER_UNAVAILABLE; return result; }
    if (width) {
        char local[128];
        if (width >= sizeof local) return result;
        memcpy(local, name, width);
        local[width] = 0;
        if (!core_io_scoped_endpoint_allowed(scoped, local, width)) return result;
    }
    size_t slot = core_io_scoped_free_slot(scoped);
    if (slot == SIZE_MAX) return result;
    CorePoller *poller = core_poll_create(-1);
    if (!poller) { result.status = CORE_IO_PROVIDER_FAILED; return result; }
    scoped->handles[slot] = (CoreIoScopedHandle){core_poll_epoll_descriptor(poller), NULL, 0, 0, 0, 0, 0, poller};
    result.status = CORE_IO_PROVIDER_OK;
    result.handle = slot;
    return result;
}
/* A narrowed Network substitutes its scoped endpoint for the guest request, so
   core_io_scoped_acquire sees exactly the literals the command line granted. */
static CoreIoResourceResult core_io_scoped_acquire_network(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    CoreIoScoped *scoped = context;
    CoreIoResourceResult result = {CORE_IO_PROVIDER_DENIED, 0};
    /* A scoped Network narrows either an outbound peer or a listening endpoint.
       Mode 1 is the standard library's `listen` request and mode 2 its
       `open_poller` request; both are preserved through narrowing and never name
       a dial target. */
    int polling = length && request[0] == 2;
    int listening = polling || (length && request[0] == 1);
    if (length && request[0] == CORE_IO_CLIENT_POLLER_TAG) return core_io_scoped_open_client_poller(scoped, request + 1, length - 1, permissions);
    /* Mode 3 is `connect_within`: its limits come first and the endpoint after them. */
    int limited = length >= CORE_IO_DIAL_LIMITS_HEADER && request[0] == CORE_IO_DIAL_LIMITS_TAG;
    /* Mode 4 is a Poller's `dial`: the poller's token, its limits, then the endpoint. */
    int dialing = length >= CORE_IO_POLL_DIAL_HEADER && request[0] == CORE_IO_POLL_DIAL_TAG;
    CoreIoDialLimits limits = {0, 0, 0, 0};
    if (limited) limits = (CoreIoDialLimits){core_io_scoped_word(request + 1), core_io_scoped_word(request + 5), core_io_scoped_word(request + 9), core_io_scoped_word(request + 13)};
    if (dialing) limits = (CoreIoDialLimits){core_io_scoped_word(request + 5), 0, 0, core_io_scoped_word(request + 9)};
    size_t skip = limited ? CORE_IO_DIAL_LIMITS_HEADER : dialing ? CORE_IO_POLL_DIAL_HEADER : listening ? 1 : 0;
    const unsigned char *name = request + skip;
    size_t width = length - skip;
    if (listening) {
        /* A poller reads, writes, completes and accepts for its whole table. */
        unsigned needed = polling ? 15u : 8u;
        if (!scoped->listen_count || (permissions & needed) != needed) { result.status = CORE_IO_PROVIDER_UNAVAILABLE; return result; }
        if (!width || width >= 128) return result;
        char local[128];
        memcpy(local, name, width);
        local[width] = 0;
        if (!core_io_scoped_listen_allowed(scoped, local, width)) return result;
        /* A granted name with a NUL octet in it is malformed: emptied, it fails to parse, where the parser would read
           only the text before the NUL. */
        if (memchr(local, 0, width)) local[0] = 0;
        /* Only a poller can report the port the kernel chose, so a blocking listener may not ask for one. */
        struct sockaddr_in wanted;
        if (!polling && core_io_scoped_endpoint_address_in(local, &wanted, 1) && wanted.sin_port == 0) return result;
        size_t slot = core_io_scoped_free_slot(scoped);
        if (slot == SIZE_MAX) { result.status = CORE_IO_PROVIDER_DENIED; return result; }
        int handle = core_io_scoped_open_listener(local);
        if (handle < 0) { result.status = CORE_IO_PROVIDER_FAILED; return result; }
        CorePoller *poller = NULL;
        if (polling) {
            poller = core_poll_create(handle);
            if (!poller) { close(handle); result.status = CORE_IO_PROVIDER_FAILED; return result; }
            scoped->handles[slot] = (CoreIoScopedHandle){core_poll_epoll_descriptor(poller), NULL, 0, 0, 0, 0, 0, poller};
        } else scoped->handles[slot] = (CoreIoScopedHandle){handle, NULL, 0, 0, 0, 1, 0, NULL};
        result.status = CORE_IO_PROVIDER_OK;
        result.handle = slot;
        return result;
    }
    if (!scoped->endpoint_count) { result.status = CORE_IO_PROVIDER_UNAVAILABLE; return result; }
    if (!(permissions & (1u | 2u))) return result;
    char local[128];
    if (width >= sizeof local) return result;
    memcpy(local, name, width);
    local[width] = 0;
    if (!core_io_scoped_endpoint_allowed(scoped, local, width)) return result;
    if (memchr(local, 0, width)) local[0] = 0;
    if (dialing) return core_io_scoped_poll_dial(scoped, core_io_scoped_word(request + 1), local, limits);
    size_t slot = core_io_scoped_free_slot(scoped);
    if (slot == SIZE_MAX) { result.status = CORE_IO_PROVIDER_DENIED; return result; }
    CoreIoProviderStatus failure = CORE_IO_PROVIDER_FAILED;
    int handle = limited ? core_io_scoped_dial_within(local, limits, &failure) : core_io_scoped_dial(local);
    if (handle < 0) { result.status = failure; return result; }
    scoped->handles[slot] = (CoreIoScopedHandle){handle, NULL, 0, 0, 0, 0, 0, NULL, (unsigned char)(limited && (limits.read_ms || limits.write_ms))};
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
int core_io_scoped_listen_endpoint(CoreIoScoped *scoped, const char *name) {
    size_t length = strlen(name);
    if (!length || length > 4096 || scoped->listen_count >= CORE_IO_SCOPED_ENDPOINTS) return 0;
    if (!(length == 1 && name[0] == '*')) {
        struct sockaddr_in address;
        /* A listen grant may name port 0: the kernel then assigns the port. */
        if (!core_io_scoped_endpoint_address_in(name, &address, 1)) return 0;
    }
    for (size_t i = 0; i < scoped->listen_count; ++i) {
        const CoreIoScopedEndpoint *entry = &scoped->listen_endpoints[i];
        if (entry->length == length && !memcmp(entry->name, name, length)) return 0;
    }
    char *copy = malloc(length + 1);
    if (!copy) return 0;
    memcpy(copy, name, length);
    copy[length] = 0;
    scoped->listen_endpoints[scoped->listen_count].name = copy;
    scoped->listen_endpoints[scoped->listen_count].length = length;
    scoped->listen_count++;
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
/* A grant's two names (`CoreIoScopedRoot`): the given one made absolute as text, kept only when the system resolves it to
   the same directory as the real one, and the real path. The working directory is taken here too. */
static void core_io_scoped_names(CoreIoScopedRoot *root, const char *path) {
    if (!getcwd(core_io_scoped_cwd, sizeof core_io_scoped_cwd)) return;
    core_io_scoped_cwd_length = strcmp(core_io_scoped_cwd, "/") ? strlen(core_io_scoped_cwd) : 0;
    char *real = realpath(path, NULL);
    if (!real) return;
    char given[CORE_IO_SCOPED_PATH];
    size_t length = 0, floor = 0;
    int directory = 0;
    if (path[0] != '/') {
        memcpy(given, core_io_scoped_cwd, core_io_scoped_cwd_length);
        length = floor = core_io_scoped_cwd_length;
    }
    root->real_length = strcmp(real, "/") ? strlen(real) : 0;
    real[root->real_length] = 0;
    root->real = real;
    if (core_io_path_normalize(path, strlen(path), given, &length, &floor, NULL, NULL, &directory)) return;
    given[length] = 0;
    char *again = realpath(length ? given : "/", NULL);
    if (again && !strcmp(again, length ? real : "/")) {
        root->spelled = strdup(given);
        root->spelled_length = root->spelled ? length : 0;
    }
    free(again);
}
static int core_io_scoped_grant_impl(CoreIoScoped *scoped, const char *path, int writable, int direct) {
    if (scoped->count >= CORE_IO_SCOPED_ROOTS) return 0;
    int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return 0;
    CoreIoScopedRoot root = {fd, writable, direct, NULL, NULL, 0, 0};
    if (!direct) core_io_scoped_names(&root, path);
    if (!direct && !root.real) { close(fd); return 0; }
    scoped->roots[scoped->count++] = root;
    if (!direct) core_io_scoped_cwd_prepare(scoped);
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
    for (size_t i = 0; i < scoped->count; ++i) {
        close(scoped->roots[i].fd);
        free(scoped->roots[i].spelled);
        free(scoped->roots[i].real);
    }
    scoped->count = 0;
    for (size_t i = 0; i < scoped->endpoint_count; ++i) free(scoped->endpoints[i].name);
    scoped->endpoint_count = 0;
    for (size_t i = 0; i < scoped->listen_count; ++i) free(scoped->listen_endpoints[i].name);
    scoped->listen_count = 0;
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

/* What the names of one file share, as an inode does: its bytes, its permission bits, an inode number from the filesystem's
   counter, the modification and status-change times, and the lock. `names` counts every entry that points here, a name
   still in the filesystem or one removed while a handle holds it; `linked` counts the names still in the filesystem, which
   is the file's hard links (`st_nlink`). The body is freed with its last name. */
typedef struct MemoryBody {
    unsigned char *bytes;
    size_t size, capacity;
    /* What `stat` reports: the permission bits (0644 for a file, 0755 for a directory unless set), an inode number
       from the filesystem's counter, and the modification time in nanoseconds on its logical clock. `locked` is set
       while a `lock_file`, `try_lock_file` or `lock_directory` File holds this entry. */
    unsigned mode, locked;
    uint64_t inode;
    int64_t mtime;
    /* The status-change time `stat` reports beside the modification time: the reading of the last call that changed the
       entry or its attributes (a write, a rename, `chmod`, `set_modified`, a new hard link), never earlier than the one
       before it. */
    int64_t ctime;
    unsigned names, linked;
} MemoryBody;
/* One name in an in-memory filesystem, a file or a directory, by its full relative path. An entry removed while a handle
   holds it stays allocated until that handle is released, as an unlinked POSIX file does. A hard link (`link_path`) is a
   second entry whose `body` is the first's. */
typedef struct MemoryEntry {
    char *path;
    size_t length;
    int directory, unlinked;
    unsigned open;
    MemoryBody *body;
    /* The text of a symbolic link (`symlink_path`), or NULL for any other entry. A link is a file entry with no bytes. */
    char *target;
} MemoryEntry;
/* An open file (entry, position, mode) or one immutable copied snapshot. Mode `L` is a lock: it holds `entry` locked
   until it is shut. `fresh` is set by an open that already advanced the clock for the first write; `wrote` once a write
   has. */
typedef struct { int core_io_memory_live; MemoryEntry *entry; unsigned char *snapshot; size_t length, position; unsigned char mode, fresh, wrote; } MemoryHandle;
/* The logical clock starts at the test clock's epoch (1 January 2000) and moves one second for each call that changes
   the filesystem, so a test never sleeps and the same program always reads the same times. The root directory is an
   entry of its own that no path names (`root`, inode 1). */
#define CORE_IO_MEMORY_EPOCH INT64_C(946684800000000000)
#define CORE_IO_MEMORY_TICK INT64_C(1000000000)
typedef struct {
    MemoryEntry **entries;
    size_t count, capacity, bytes;
    MemoryEntry root;
    MemoryBody root_body;
    uint64_t inodes;
    int64_t clock;
    /* The last status-change time given out (`core_io_memory_changed`). */
    int64_t changed;
    /* The open-handle table, grown from four slots up to CORE_IO_MEMORY_MEMORY_HANDLES as handles open at once: a
       memory filesystem lives until its process or test trial ends (5C), so one that opens a few at a time stays small.
       A slot's index is its handle id, and growing keeps every index. */
    MemoryHandle *handles;
    size_t handle_capacity;
} MemoryFs;

/* ---- in-memory filesystem ------------------------------------------------ */

/* The reason a granted root gives for a symbolic link it will not follow, which `core_io_scoped_from_errno` words for `ELOOP`. */
static const char *const core_io_memory_link_reason = "is a symbolic link the sandbox does not follow, or links nest too deeply";
/* The scoped-root path rule: relative, no empty, `.` or `..` component, no NUL
   (a backslash is a byte of a name, as `core_io_scoped_valid_path` says). An empty path names the root and only metadata/core_io_memory_listing
   take it; the guest spells that same root `"."`, which the request path normalizes
   to empty before this rule runs (FR-419). */
static int core_io_memory_valid_path(const unsigned char *path, size_t length, unsigned char mode) {
    if (!length) return mode == 'm' || mode == 'l';
    if (length > CORE_IO_MEMORY_PATH_LIMIT || memchr(path, 0, length)) return 0;
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
/* A fresh filesystem: an empty root directory and the logical clock at its epoch. */
static void core_io_memory_init(MemoryFs *memory) {
    memory->clock = CORE_IO_MEMORY_EPOCH;
    memory->inodes = 1;
    memory->root_body = (MemoryBody){.mode = 0755, .inode = 1, .mtime = CORE_IO_MEMORY_EPOCH, .ctime = CORE_IO_MEMORY_EPOCH, .names = 1, .linked = 1};
    memory->root = (MemoryEntry){.directory = 1, .body = &memory->root_body};
    memory->changed = CORE_IO_MEMORY_EPOCH;
}
/* One tick of the logical clock: the reading a call that changes the filesystem stamps what it changed with. */
static int64_t core_io_memory_tick(MemoryFs *memory) {
    memory->clock = memory->clock > INT64_MAX - CORE_IO_MEMORY_TICK ? INT64_MAX : memory->clock + CORE_IO_MEMORY_TICK;
    return memory->clock;
}
/* Stamp `entry` with the reading `time` of a call that changed its contents: its modification and status-change time are
   that reading, and no later status change can be earlier than it. */
static void core_io_memory_stamp(MemoryFs *memory, MemoryEntry *entry, int64_t time) {
    entry->body->mtime = time;
    entry->body->ctime = time;
    if (time > memory->changed) memory->changed = time;
}
/* The status-change time of a call that changes an entry's attributes without the clock (`chmod`, `set_modified`): the
   clock's reading when it is later than the last change, else one nanosecond past the last. It is strictly later than every
   earlier change and the second-resolution clock does not move, so a rewrite that restores the modification time still
   shows a newer status-change time, as the kernel's does. */
static int64_t core_io_memory_changed(MemoryFs *memory) {
    memory->changed = memory->clock > memory->changed ? memory->clock : memory->changed + 1;
    return memory->changed;
}
static MemoryEntry *core_io_memory_find(MemoryFs *memory, const unsigned char *path, size_t length) {
    for (size_t i = 0; i < memory->count; ++i) {
        MemoryEntry *entry = memory->entries[i];
        if (entry->length == length && !memcmp(entry->path, path, length)) return entry;
    }
    return NULL;
}
/* Give the directory that holds `path` the modification time `time`: adding, removing or renaming an entry changes it. */
/* What a `..` in a path of the in-memory filesystem climbs out of: the filesystem, whose path is as written. */
typedef struct { MemoryFs *memory; const unsigned char *path; size_t length; } CoreIoMemoryClimb;
/* The `check` of `core_io_path_normalize` on the in-memory filesystem: a `..` past the root is outside it, and the entry
   a `..` removes must be a directory, not a link, as under a grant. */
static CoreIoProviderStatus core_io_memory_climb(void *context, const char *path, size_t length) {
    const CoreIoMemoryClimb *climb = context;
    if (!length) return core_io_scoped_refuse(CORE_IO_REFUSAL_OUTSIDE, (const char *)climb->path, climb->length);
    const MemoryEntry *entry = core_io_memory_find(climb->memory, (const unsigned char *)path + 1, length - 1);
    errno = !entry ? ENOENT : entry->target ? ELOOP : !entry->directory ? ENOTDIR : 0;
    return errno ? core_io_scoped_from_errno() : CORE_IO_PROVIDER_OK;
}
/* Read `path` on the in-memory filesystem as docs/io.md says (rule 6): its root is the working directory and the one
   grant, so `.`, empty components and `..` inside it mean what they mean to the system, and an absolute path or a `..`
   past the root is outside. `out` (at least `CORE_IO_SCOPED_PATH` octets) gets the entry's path, `""` for the root.
   The empty path names the root for `mode` `m` and `l` only. Returns 0 or a refusal, the reason set. */
static CoreIoProviderStatus core_io_memory_normalize(MemoryFs *memory, const unsigned char *path, size_t width, unsigned char mode,
                                                     unsigned char *out, size_t *length) {
    if (memchr(path, 0, width)) { core_io_os_reason = CORE_IO_REFUSAL_NUL; return CORE_IO_PROVIDER_DENIED; }
    if (!width && mode != 'm' && mode != 'l') { errno = ENOENT; return core_io_scoped_from_errno(); }
    if (width && path[0] == '/') return core_io_scoped_refuse(CORE_IO_REFUSAL_OUTSIDE, (const char *)path, width);
    char text[CORE_IO_SCOPED_PATH];
    size_t used = 0, floor = 0;
    int directory = 0;
    CoreIoMemoryClimb climb = {memory, path, width};
    CoreIoProviderStatus status = core_io_path_normalize((const char *)path, width, text, &used, &floor, core_io_memory_climb, &climb, &directory);
    if (status) return status;
    if (used > CORE_IO_MEMORY_PATH_LIMIT) { errno = ENAMETOOLONG; return core_io_scoped_from_errno(); }
    *length = used ? used - 1 : 0;
    if (*length) memcpy(out, text + 1, *length);
    const MemoryEntry *entry = directory && *length ? core_io_memory_find(memory, out, *length) : NULL;
    errno = 0;
    if (directory && *length && !entry && (mode == 'c' || mode == 't' || mode == 'w' || mode == 'a')) errno = EISDIR;
    else if (entry && entry->target) errno = ELOOP;
    else if (entry && !entry->directory) errno = ENOTDIR;
    return errno ? core_io_scoped_from_errno() : CORE_IO_PROVIDER_OK;
}
static void core_io_memory_stamp_parent(MemoryFs *memory, const unsigned char *path, size_t length, int64_t time) {
    size_t split = length;
    while (split && path[split - 1] != '/') --split;
    MemoryEntry *parent = split ? core_io_memory_find(memory, path, split - 1) : &memory->root;
    if (parent) core_io_memory_stamp(memory, parent, time);
}
/* The directory that holds `path`: the root for a path of one component. */
static MemoryEntry *core_io_memory_holder(MemoryFs *memory, const unsigned char *path, size_t length) {
    size_t split = length;
    while (split && path[split - 1] != '/') --split;
    return split ? core_io_memory_find(memory, path, split - 1) : &memory->root;
}
/* The permission bits the stand-in honours. An ordinary user owns every entry (a test never runs as another user, and a
   privileged user would pass every check), so the owner triple of an entry's mode decides: `want` is the bits asked for,
   4 to read a file or list a directory, 2 to write a file or to add, remove or rename entries of a directory, and 1 to
   search a directory, which every path that goes through it needs. Which call asks for which bit is listed in
   docs/io.md ("Permission bits on the in-memory filesystem"). */
#define CORE_IO_MEMORY_READ 4u
#define CORE_IO_MEMORY_WRITE 2u
#define CORE_IO_MEMORY_SEARCH 1u
static int core_io_memory_allows(const MemoryEntry *entry, unsigned want) {
    return ((entry->body->mode >> 6) & want) == want;
}
/* The refusal the real provider words for EACCES: denied, with the system's own reason. */
static CoreIoProviderStatus core_io_memory_refuse(void) {
    core_io_os_reason = "permission denied";
    return CORE_IO_PROVIDER_DENIED;
}
/* Whether every ancestor of `path` is an existing directory the caller may search: OK, FAILED for a
   missing one, DENIED for one that is a file or a symbolic link (POSIX ENOENT and ENOTDIR: the component walk of the real
   provider refuses a link on the way as it does a file) or one without the search bit (EACCES, `permission denied`). */
static CoreIoProviderStatus core_io_memory_parents(MemoryFs *memory, const unsigned char *path, size_t length) {
    for (size_t i = 0; i < length; ++i) {
        if (path[i] != '/') continue;
        MemoryEntry *ancestor = core_io_memory_find(memory, path, i);
        if (!ancestor) return core_io_memory_errno(ENOENT);
        if (!ancestor->directory) { core_io_os_reason = "a parent of the path is not a directory"; return CORE_IO_PROVIDER_DENIED; }
        if (!core_io_memory_allows(ancestor, CORE_IO_MEMORY_SEARCH)) return core_io_memory_refuse();
    }
    return CORE_IO_PROVIDER_OK;
}
/* Room for one more entry in the table. */
static int core_io_memory_reserve(MemoryFs *memory) {
    if (memory->count < memory->capacity) return 1;
    size_t grown = memory->capacity ? memory->capacity * 2 : 16;
    MemoryEntry **entries = realloc(memory->entries, grown * sizeof *entries);
    if (!entries) return 0;
    memory->entries = entries;
    memory->capacity = grown;
    return 1;
}
/* A new file or directory: the next inode, the default mode, and the new clock reading as its time and its directory's. */
static MemoryEntry *core_io_memory_create(MemoryFs *memory, const unsigned char *path, size_t length, int directory) {
    if (!core_io_memory_reserve(memory)) return NULL;
    MemoryEntry *entry = calloc(1, sizeof *entry);
    MemoryBody *body = calloc(1, sizeof *body);
    char *copy = malloc(length + 1);
    if (!entry || !body || !copy) { free(entry); free(body); free(copy); return NULL; }
    memcpy(copy, path, length);
    copy[length] = 0;
    entry->path = copy;
    entry->length = length;
    entry->directory = directory;
    entry->body = body;
    body->names = body->linked = 1;
    body->mode = directory ? 0755 : 0644;
    body->inode = ++memory->inodes;
    core_io_memory_stamp(memory, entry, core_io_memory_tick(memory));
    core_io_memory_stamp_parent(memory, path, length, entry->body->mtime);
    memory->entries[memory->count++] = entry;
    return entry;
}
static void core_io_memory_entry_free(MemoryEntry *entry) {
    free(entry->target);
    free(entry->path);
    if (--entry->body->names == 0) {
        free(entry->body->bytes);
        free(entry->body);
    }
    free(entry);
}
/* A name of the filesystem leaves it (a removal, or a replacement by a new file): the file's bytes stop counting against the
   filesystem's budget with its last name, though a handle may still read what is left of it. */
static void core_io_memory_unname(MemoryFs *memory, MemoryEntry *entry) {
    if (--entry->body->linked == 0) memory->bytes -= entry->body->size;
}
static void core_io_memory_unlink_entry(MemoryFs *memory, MemoryEntry *entry) {
    for (size_t i = 0; i < memory->count; ++i) {
        if (memory->entries[i] != entry) continue;
        memory->entries[i] = memory->entries[--memory->count];
        break;
    }
    core_io_memory_unname(memory, entry);
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
static size_t core_io_memory_free_handle(MemoryFs *memory) {
    for (size_t i = 0; i < memory->handle_capacity; ++i) if (!memory->handles[i].core_io_memory_live) return i;
    if (memory->handle_capacity == CORE_IO_MEMORY_MEMORY_HANDLES) return SIZE_MAX;
    size_t old = memory->handle_capacity, next = old ? old * 2 : 4;
    if (next > CORE_IO_MEMORY_MEMORY_HANDLES) next = CORE_IO_MEMORY_MEMORY_HANDLES;
    MemoryHandle *grown = realloc(memory->handles, next * sizeof *grown);
    if (!grown) out_of_memory();
    memset(grown + old, 0, (next - old) * sizeof *grown);
    memory->handles = grown;
    memory->handle_capacity = next;
    return old;
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
        CoreIoProviderStatus chain = core_io_memory_parents(memory, path, length);
        if (chain == CORE_IO_PROVIDER_DENIED) { *status = chain; return NULL; }
        MemoryEntry *directory = core_io_memory_find(memory, path, length);
        if (!directory) { *status = core_io_memory_errno(ENOENT); return NULL; }
        if (!directory->directory) { core_io_os_reason = "is not a directory"; *status = CORE_IO_PROVIDER_DENIED; return NULL; }
        if (!core_io_memory_allows(directory, CORE_IO_MEMORY_READ)) { *status = core_io_memory_refuse(); return NULL; }
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
    qsort(children, count, sizeof *children, core_io_memory_leaf_order);
    unsigned char *snapshot = malloc(bytes);
    if (!snapshot) { free(children); *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    size_t used = 0;
    snapshot[used++] = 1;
    for (size_t i = 0; i < count; ++i) {
        size_t width;
        const char *name = core_io_memory_leaf(children[i], &width);
        snapshot[used++] = children[i]->directory ? 2 : children[i]->target ? 3 : 1;
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
        if (length) {
            CoreIoProviderStatus chain = core_io_memory_parents(memory, path, length);
            if (chain == CORE_IO_PROVIDER_DENIED) { *status = chain; return NULL; }
            if (!entry) { *status = core_io_memory_errno(ENOENT); return NULL; }
        }
        unsigned char *bytes = malloc(10);
        if (!bytes) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
        bytes[0] = 1;
        bytes[1] = !entry || entry->directory ? 2 : 1;
        uint64_t width = entry ? entry->body->size : 0;
        for (unsigned i = 0; i < 8; ++i) bytes[2 + i] = (unsigned char)((width >> (8 * i)) & 0xff);
        *size = 10;
        return bytes;
    }
    if (!length) { *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    if (mode == 'k') {
        CoreIoProviderStatus chain = core_io_memory_parents(memory, path, length);
        if (chain != CORE_IO_PROVIDER_OK) {
            /* A denied walk already named why (a file on the way, or a directory without the search bit). */
            if (chain != CORE_IO_PROVIDER_DENIED) core_io_os_reason = "the parent directory does not exist";
            *status = chain;
            return NULL;
        }
        if (entry) { core_io_os_reason = "already exists"; *status = CORE_IO_PROVIDER_FAILED; return NULL; }
        if (!core_io_memory_allows(core_io_memory_holder(memory, path, length), CORE_IO_MEMORY_WRITE)) { *status = core_io_memory_refuse(); return NULL; }
        if (!core_io_memory_create(memory, path, length, 1)) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    } else {
        CoreIoProviderStatus chain = core_io_memory_parents(memory, path, length);
        if (chain == CORE_IO_PROVIDER_DENIED) { *status = chain; return NULL; }
        if (!entry) { *status = core_io_memory_errno(ENOENT); return NULL; }
        if (!core_io_memory_allows(core_io_memory_holder(memory, path, length), CORE_IO_MEMORY_WRITE)) { *status = core_io_memory_refuse(); return NULL; }
        if (entry->directory && core_io_memory_has_children(memory, entry)) { core_io_os_reason = "the directory is not empty"; *status = CORE_IO_PROVIDER_FAILED; return NULL; }
        core_io_memory_unlink_entry(memory, entry);
        core_io_memory_stamp_parent(memory, path, length, core_io_memory_tick(memory));
    }
    unsigned char *bytes = malloc(1);
    if (!bytes) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    bytes[0] = 1;
    *size = 1;
    return bytes;
}
/* Open a file entry for `r`, `c` (exclusive core_io_memory_create), `t` (truncate an existing
   file) or `a` (append, creating it), with the POSIX outcome of each. */
static MemoryEntry *core_io_memory_open_file(MemoryFs *memory, const unsigned char *path, size_t length, unsigned char mode, CoreIoProviderStatus *status, unsigned char *fresh) {
    *fresh = 0;
    CoreIoProviderStatus chain = core_io_memory_parents(memory, path, length);
    if (chain != CORE_IO_PROVIDER_OK) { *status = chain; return NULL; }
    MemoryEntry *entry = core_io_memory_find(memory, path, length);
    if (entry && entry->directory && mode == 'r' && !core_io_memory_allows(entry, CORE_IO_MEMORY_READ)) { *status = core_io_memory_refuse(); return NULL; }
    if (entry && entry->directory) { core_io_os_reason = "is a directory"; *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    if (entry && entry->target && mode != 'c') { core_io_os_reason = core_io_memory_link_reason; *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    if (mode == 'c' && entry) { *status = core_io_memory_errno(EEXIST); return NULL; }
    if ((mode == 'r' || mode == 't') && !entry) { *status = core_io_memory_errno(ENOENT); return NULL; }
    /* Reading needs the read bit of the file, writing or appending the write bit of an existing file, and creating one
       the write bit of the directory that holds it (the search bit of every directory on the way was checked above). */
    if (entry && !core_io_memory_allows(entry, mode == 'r' ? CORE_IO_MEMORY_READ : CORE_IO_MEMORY_WRITE)) { *status = core_io_memory_refuse(); return NULL; }
    if (!entry && !core_io_memory_allows(core_io_memory_holder(memory, path, length), CORE_IO_MEMORY_WRITE)) { *status = core_io_memory_refuse(); return NULL; }
    if (!entry) {
        entry = core_io_memory_create(memory, path, length, 0);
        if (!entry) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
        *fresh = 1;
    }
    if (mode == 't') { memory->bytes -= entry->body->size; entry->body->size = 0; core_io_memory_stamp(memory, entry, core_io_memory_tick(memory)); *fresh = 1; }
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
    /* The guest names this filesystem's root `"."` (or `./`, `a/..`), while entries store it as the empty path. */
    unsigned char normal[CORE_IO_SCOPED_PATH];
    const unsigned char *path = normal;
    size_t width = 0;
    result.status = core_io_memory_normalize(memory, request + 2, length - 2, mode, normal, &width);
    if (result.status) return result;
    result.status = CORE_IO_PROVIDER_DENIED;
    if (!width && (mode == 'r' || mode == 'c' || mode == 't' || mode == 'a')) {
        core_io_os_reason = "is a directory";
        return result;
    }
    if (!width && mode == 'k') { core_io_os_reason = "already exists"; result.status = CORE_IO_PROVIDER_FAILED; return result; }
    if (!width && mode == 'x') { core_io_os_reason = "denied: a granted directory itself is not removed"; return result; }
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
    unsigned char fresh;
    MemoryEntry *entry = core_io_memory_open_file(memory, path, width, mode, &result.status, &fresh);
    if (!entry) return result;
    entry->open++;
    *handle = (MemoryHandle){1, entry, NULL, 0, 0, mode, fresh, 0};
    result.handle = slot;
    return result;
}
static MemoryHandle *core_io_memory_live(MemoryFs *memory, uint64_t id) {
    if (id >= memory->handle_capacity || !memory->handles[id].core_io_memory_live) return NULL;
    return &memory->handles[id];
}
static void core_io_memory_shut(MemoryHandle *handle) {
    if (handle->entry) {
        if (handle->mode == 'L') handle->entry->body->locked = 0;
        handle->entry->open--;
        if (handle->entry->unlinked && !handle->entry->open) core_io_memory_entry_free(handle->entry);
    }
    free(handle->snapshot);
    *handle = (MemoryHandle){0, NULL, NULL, 0, 0, 0, 0, 0};
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
        if (handle->mode != 'r') { result.status = handle->mode == 'a' ? CORE_IO_PROVIDER_DENIED : core_io_memory_errno(EBADF); return result; }
        bytes = handle->entry->body->bytes;
        total = handle->entry->body->size;
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
    if (handle->mode == 'r' || handle->mode == 'L') { result.status = core_io_memory_errno(EBADF); return result; }
    MemoryEntry *entry = handle->entry;
    size_t at = handle->mode == 'a' ? entry->body->size : handle->position;
    if (at > entry->body->size || length > CORE_IO_MEMORY_MEMORY_BYTES - memory->bytes || at + length > CORE_IO_MEMORY_MEMORY_BYTES) { result.status = core_io_memory_errno(ENOSPC); return result; }
    size_t end = at + length;
    if (end > entry->body->capacity) {
        size_t grown = entry->body->capacity ? entry->body->capacity : 64;
        while (grown < end) grown *= 2;
        unsigned char *bytes = realloc(entry->body->bytes, grown);
        if (!bytes) { result.status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return result; }
        entry->body->bytes = bytes;
        entry->body->capacity = grown;
    }
    if (length) memcpy(entry->body->bytes + at, input, length);
    if (end > entry->body->size) {
        if (entry->body->linked) memory->bytes += end - entry->body->size;
        entry->body->size = end;
    }
    /* The first write that did not follow a creating or truncating open is a changing call of its own; the rest of the
       handle's writes keep the file at the clock's current reading. */
    if (length) {
        core_io_memory_stamp(memory, entry, !handle->wrote && !handle->fresh ? core_io_memory_tick(memory) : memory->clock);
        handle->wrote = 1;
        handle->fresh = 0;
    }
    handle->position = end;
    result.status = CORE_IO_PROVIDER_OK;
    result.length = length;
    return result;
}
static void core_io_memory_free(MemoryFs *memory) {
    for (size_t i = 0; i < memory->handle_capacity; ++i) if (memory->handles[i].core_io_memory_live) core_io_memory_shut(&memory->handles[i]);
    free(memory->handles);
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

/* ---- the in-memory network -------------------------------------------------
   `network.memory()` is a Network stand-in whose endpoints are names, not addresses (stand-in value 1; value 0 stays
   the denied stand-in). `listen` on a narrowed name registers a listener, `connect` to a name somebody listens on makes
   a pair of connected ends and queues the server end on that listener, and `accept` hands the listener's next end out.
   Bytes written to one end queue on the other. Nothing blocks, because a test has one thread: a read with nothing
   queued while the peer is open, an accept with nothing waiting and a connect to a name nobody listens on all fail
   instead of waiting forever. Closing an end gives its peer end of stream once the queued bytes are read. Every handle
   lives in the provider block, which frees the queues when the stand-in is dropped. */
#define CORE_IO_NET_HANDLES 64
#define CORE_IO_NET_QUEUE 1048576
#define CORE_IO_NET_PENDING 16
#define CORE_IO_NET_NAME 128
typedef struct {
    unsigned char kind;        /* 0 free, 1 listener, 2 connection end */
    unsigned char peer_closed; /* a connection end: the peer closed, so the queue is the last of its bytes */
    int peer;                  /* a connection end: the other end's slot, or -1 once that end closed */
    size_t name_length;
    char name[CORE_IO_NET_NAME];
    size_t pending[CORE_IO_NET_PENDING]; /* a listener: server ends not yet accepted, oldest first */
    size_t pending_count;
    unsigned char *queue;      /* a connection end: the bytes its peer wrote and it has not read */
    size_t queue_head, queue_length, queue_capacity;
} NetHandle;
typedef struct { NetHandle handles[CORE_IO_NET_HANDLES]; } MemNet;
static NetHandle *core_io_net_live(MemNet *net, uint64_t id) {
    return id < CORE_IO_NET_HANDLES && net->handles[id].kind ? &net->handles[id] : NULL;
}
static size_t core_io_net_free_slot(const MemNet *net) {
    for (size_t i = 0; i < CORE_IO_NET_HANDLES; ++i) if (!net->handles[i].kind) return i;
    return SIZE_MAX;
}
static void core_io_net_shut(MemNet *net, size_t id) {
    NetHandle *handle = &net->handles[id];
    if (handle->kind == 2 && handle->peer >= 0) {
        net->handles[handle->peer].peer = -1;
        net->handles[handle->peer].peer_closed = 1;
    }
    if (handle->kind == 1) for (size_t i = 0; i < handle->pending_count; ++i) core_io_net_shut(net, handle->pending[i]);
    free(handle->queue);
    memset(handle, 0, sizeof *handle);
}
static void core_io_net_free(MemNet *net) {
    for (size_t i = 0; i < CORE_IO_NET_HANDLES; ++i) free(net->handles[i].queue);
    free(net);
}
/* Mode 1 listens on the name after the tag; a request with no tag connects to its whole text. The unnarrowed
   `connect` request is the single octet 0, which names nothing, and a poller (mode 2) is not provided. */
static CoreIoResourceResult core_io_net_acquire(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    MemNet *net = context;
    CoreIoResourceResult result = {CORE_IO_PROVIDER_DENIED, 0};
    /* No poller, so none of `open_poller` (mode 2), `open_client_poller` (mode 5) or a poller's `dial` (mode 4) is provided. */
    if (length && (request[0] == 2 || request[0] == CORE_IO_POLL_DIAL_TAG || request[0] == CORE_IO_CLIENT_POLLER_TAG)) return result;
    int listening = length && request[0] == 1;
    if (!listening && length == 1 && request[0] == 0) return result;
    /* `connect_within` (mode 3) connects like `connect`: nothing here blocks, so its limits have nothing to bound. */
    int limited = length >= CORE_IO_DIAL_LIMITS_HEADER && request[0] == CORE_IO_DIAL_LIMITS_TAG;
    size_t skip = limited ? CORE_IO_DIAL_LIMITS_HEADER : listening ? 1 : 0;
    const uint8_t *name = request + skip;
    size_t width = length - skip;
    if (!width || width >= CORE_IO_NET_NAME) return result;
    if (listening) {
        if ((permissions & 8u) != 8u) return result;
        for (size_t i = 0; i < CORE_IO_NET_HANDLES; ++i) {
            const NetHandle *other = &net->handles[i];
            if (other->kind == 1 && other->name_length == width && !memcmp(other->name, name, width)) { result.status = CORE_IO_PROVIDER_FAILED; return result; }
        }
        size_t slot = core_io_net_free_slot(net);
        if (slot == SIZE_MAX) return result;
        net->handles[slot].kind = 1;
        net->handles[slot].peer = -1;
        net->handles[slot].name_length = width;
        memcpy(net->handles[slot].name, name, width);
        result.status = CORE_IO_PROVIDER_OK;
        result.handle = slot;
        return result;
    }
    if (!(permissions & (1u | 2u))) return result;
    NetHandle *listener = NULL;
    for (size_t i = 0; i < CORE_IO_NET_HANDLES; ++i) {
        NetHandle *other = &net->handles[i];
        if (other->kind == 1 && other->name_length == width && !memcmp(other->name, name, width)) listener = other;
    }
    if (!listener || listener->pending_count >= CORE_IO_NET_PENDING) { result.status = CORE_IO_PROVIDER_FAILED; return result; }
    size_t client = core_io_net_free_slot(net);
    if (client == SIZE_MAX) return result;
    net->handles[client].kind = 2;
    size_t server = core_io_net_free_slot(net);
    if (server == SIZE_MAX) { net->handles[client].kind = 0; return result; }
    net->handles[server].kind = 2;
    net->handles[client].peer = (int)server;
    net->handles[server].peer = (int)client;
    listener->pending[listener->pending_count++] = server;
    result.status = CORE_IO_PROVIDER_OK;
    result.handle = client;
    return result;
}
static CoreIoProviderStatus core_io_net_complete(void *context, uint64_t id) {
    MemNet *net = context;
    if (!core_io_net_live(net, id)) return CORE_IO_PROVIDER_FAILED;
    core_io_net_shut(net, (size_t)id);
    return CORE_IO_PROVIDER_OK;
}
static void core_io_net_release(void *context, uint64_t id) {
    MemNet *net = context;
    if (core_io_net_live(net, id)) core_io_net_shut(net, (size_t)id);
}
/* A listener's read is the runtime's accept channel: eight octets carry the next waiting end's slot. A connection
   end reads what its peer queued, and reports end of stream, as a socket does, with a read of no octets. */
static CoreIoResourceRead core_io_net_read(void *context, uint64_t id, uint8_t *output, size_t capacity) {
    MemNet *net = context;
    CoreIoResourceRead result = {CORE_IO_PROVIDER_FAILED, 0, 0};
    NetHandle *handle = core_io_net_live(net, id);
    if (!handle) return result;
    if (!capacity) { result.status = CORE_IO_PROVIDER_OK; return result; }
    if (handle->kind == 1) {
        if (capacity < sizeof(uint64_t)) { result.status = CORE_IO_PROVIDER_DENIED; return result; }
        if (!handle->pending_count) return result;
        uint64_t raw = handle->pending[0];
        memmove(handle->pending, handle->pending + 1, (handle->pending_count - 1) * sizeof handle->pending[0]);
        --handle->pending_count;
        memcpy(output, &raw, sizeof raw);
        result.status = CORE_IO_PROVIDER_OK;
        result.length = sizeof raw;
        return result;
    }
    size_t available = handle->queue_length - handle->queue_head;
    if (!available) {
        if (!handle->peer_closed) return result;
        result.status = CORE_IO_PROVIDER_OK;
        result.eof = 1;
        return result;
    }
    size_t width = available < capacity ? available : capacity;
    memcpy(output, handle->queue + handle->queue_head, width);
    handle->queue_head += width;
    if (handle->queue_head == handle->queue_length) handle->queue_head = handle->queue_length = 0;
    result.status = CORE_IO_PROVIDER_OK;
    result.length = width;
    return result;
}
/* A write queues on the peer end, up to a megabyte; with the peer closed, or no room at all, it fails. */
static CoreIoResourceWrite core_io_net_write(void *context, uint64_t id, const uint8_t *input, size_t length) {
    MemNet *net = context;
    CoreIoResourceWrite result = {CORE_IO_PROVIDER_FAILED, 0};
    NetHandle *handle = core_io_net_live(net, id);
    if (!handle || handle->kind != 2) { result.status = handle ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return result; }
    if (handle->peer < 0) return result;
    if (!length) { result.status = CORE_IO_PROVIDER_OK; return result; }
    NetHandle *other = &net->handles[handle->peer];
    size_t room = CORE_IO_NET_QUEUE - (other->queue_length - other->queue_head);
    if (length > room) length = room;
    if (!length) return result;
    if (other->queue_head) {
        memmove(other->queue, other->queue + other->queue_head, other->queue_length - other->queue_head);
        other->queue_length -= other->queue_head;
        other->queue_head = 0;
    }
    size_t end = other->queue_length + length;
    if (end > other->queue_capacity) {
        size_t grown = other->queue_capacity ? other->queue_capacity : 256;
        while (grown < end) grown *= 2;
        unsigned char *bytes = realloc(other->queue, grown);
        if (!bytes) { result.status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return result; }
        other->queue = bytes;
        other->queue_capacity = grown;
    }
    memcpy(other->queue + other->queue_length, input, length);
    other->queue_length = end;
    result.status = CORE_IO_PROVIDER_OK;
    result.length = length;
    return result;
}

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
    myl_core_drop_owned(block);
}
static const int32_t core_io_cap_layout[]={32,2,0,8,0,24,0};
static const int32_t core_io_dependent_layout[]={32,1,0,24,0};
static const int32_t core_io_resource_layout[]={64,0,0};
static const int32_t core_io_result_pointer_layout[]={24,2,0,8,0,16,0};
static const int32_t core_io_result_scalar_layout[]={24,1,0,16,0};
static const int32_t core_io_list_layout[]={8,1,0,0,0};
typedef struct { unsigned family,rights;myl_block *provider,*parent,*scope; } CoreIoAuthority;
/* Rights bits of a `fs.dir` or `filesystem.dir_at` handle under `--restrict` whose folder is reached through a symbolic
   link in a grant's given name (`core_io_dir_link`): the folder is the link, or a link is on the way. Every call through
   such a handle is refused, after the refusals of `fs.read_only()` and of the narrowing's own path rule, with the reason a
   run without `--restrict` gives, whose walk meets the link (DIRAT-LINK, DIR-LITERAL-LINK). */
#define CORE_IO_DIR_LINK 256u
#define CORE_IO_DIR_THROUGH_LINK 512u
#define CORE_IO_DIR_LINKED (CORE_IO_DIR_LINK | CORE_IO_DIR_THROUGH_LINK)
/* That reason for a call with an empty path (`empty`: the folder itself) or a path below it, by how the call walks: one
   that opens each component (`opens`, a read, a write, a listing, `mkdir`) meets the link as a parent that is not a
   directory, or as a folder that is not one; one that describes or lists through one confined walk (`stat`, `realpath`)
   meets it as a link. */
static const char *core_io_dir_link_reason(unsigned rights, int empty, int opens) {
    const int link = (rights & CORE_IO_DIR_LINK) && empty;
    if (opens) return link ? "is not a directory" : core_io_errno_reason(ENOTDIR);
    return link ? "is a symbolic link the sandbox does not follow" : core_io_errno_reason(ELOOP);
}
/* `failing` marks a stand-in clock or entropy that `__stand_fail` armed: it answers `remaining` more reads, then fails. */
/* A scripted `Process` (family 7, test) keeps two byte strings: `script`, the packed rules the `process` module built, and
   `calls`, the packed requests it has been asked to run (core_process.c). */
typedef struct { unsigned family,test,failing;int64_t value;MemoryFs *memory;myl_block *pairs;CoreIoResourceProvider adapter;int64_t monotonic;MemNet *net;int64_t remaining;unsigned char *script,*calls;size_t script_length,calls_length; } CoreIoState;
static const int32_t core_io_provider_layout[]={sizeof(CoreIoState),1,0,offsetof(CoreIoState,pairs),0};
/* `path` is the name a file was opened under (a copy the resource owns; NULL for a resource that is not a file or has none), kept so a
   failure of `f.sync()` can name it. */
typedef struct CoreIoResource { myl_block *authority;uint64_t handle;unsigned family,rights,open,text;struct CoreIoResource *previous,*next;myl_block *block;char *path; } CoreIoResource;
static void core_io_resource_trap(const CoreIoResource *resource,const char *verb,int status);
static CoreIoResource *core_io_tail;
static int64_t core_io_open_count;static unsigned core_io_family_open[2];
static CoreIoScoped core_io_real;
static int core_io_initialized,core_io_restricted,core_io_clock,core_io_entropy,core_io_environment,core_io_host,core_io_process;
static char *core_io_options;
static const char *core_io_names="";
static const char *core_io_enumerated_names="";
static uint64_t core_io_seed;
static CoreIoAuthority *core_io_authority(myl_block *block) { return (CoreIoAuthority *)block_data(block); }
static CoreIoState *core_io_state(myl_block *authority) { return (CoreIoState *)block_data(core_io_authority(authority)->provider); }
static void core_io_fail(const char *code) { core_io_failure(code); }

static myl_block *core_io_provider(unsigned family,int test,int64_t value,myl_block *pairs) {
    if (pairs) pairs = myl_core_owned_octets_copy(pairs);
    myl_block *block=block_new(8,(int64_t)sizeof(CoreIoState),1);block->len=1;block->reserved=(int64_t)(intptr_t)core_io_provider_layout;
    CoreIoState *state=(CoreIoState *)block_data(block);memset(state,0,sizeof *state);
    state->family=family;state->test=(unsigned)test;state->value=value;state->pairs=pairs;
    if(family==2){
        if(!test&&core_io_embedding)state->adapter=core_io_native.filesystem;
        else if(test){state->memory=calloc(1,sizeof(MemoryFs));if(!state->memory)out_of_memory();core_io_memory_init(state->memory);state->adapter=(CoreIoResourceProvider){state->memory,7,core_io_memory_acquire,core_io_memory_complete,core_io_memory_release,core_io_memory_read,core_io_memory_write};}
        else state->adapter=core_io_scoped_provider(&core_io_real,15);
    } else if(family==3) {
        if(test&&value==1){state->net=calloc(1,sizeof(MemNet));if(!state->net)out_of_memory();state->adapter=(CoreIoResourceProvider){state->net,15,core_io_net_acquire,core_io_net_complete,core_io_net_release,core_io_net_read,core_io_net_write};}
        else state->adapter=!test&&core_io_embedding?core_io_native.network:test?(CoreIoResourceProvider){state,7,core_io_memory_network_acquire,core_io_memory_network_complete,core_io_memory_network_release,NULL,NULL}:core_io_scoped_network_provider(&core_io_real,15);
    }
    return block;
}
static myl_block *core_io_cap_new(unsigned family,unsigned rights,myl_block *provider,myl_block *parent,myl_block *scope) {
    myl_block *block=block_new(6,sizeof(CoreIoAuthority),1);block->len=1;block->reserved=(int64_t)(intptr_t)core_io_cap_layout;
    if (parent) block->reserved=(int64_t)(intptr_t)core_io_dependent_layout;
    *(CoreIoAuthority *)block_data(block)=(CoreIoAuthority){family,rights,provider,parent,scope};
    return block;
}
/* Borrowed scope input: publish an independent scope in the owned ABI. */
static myl_block *core_io_cap(unsigned family,unsigned rights,myl_block *provider,myl_block *parent,myl_block *scope) {
    if (scope) scope=myl_core_owned_octets_copy(scope);
    return core_io_cap_new(family,rights,provider,parent,scope);
}
/* 5C: a capability crosses into guest code as a scalar handle, the address of its authority block. The runtime keeps
   every authority it publishes in this table until the process or the test trial ends (`core_io_cleanup`), so copies of
   a handle share one provider state (one memory tree, one seeded stream) and nothing in the program destroys it. The
   table is plain memory, never a counted block, so the leak check counts only what the program itself still owns. */
static myl_block **core_io_table;
static size_t core_io_table_count,core_io_table_capacity;
static int64_t core_io_publish(myl_block *cap){
    if(core_io_table_count==core_io_table_capacity){size_t next=core_io_table_capacity?core_io_table_capacity*2:16;myl_block **grown=realloc(core_io_table,next*sizeof *grown);if(!grown)out_of_memory();core_io_table=grown;core_io_table_capacity=next;}
    core_io_table[core_io_table_count++]=cap;return (int64_t)(intptr_t)cap;
}
static myl_block *core_io_handle(int64_t handle){myl_block *cap=(myl_block *)(intptr_t)handle;if(!cap||kind_of(cap)!=6)core_io_fail("InvalidCapability");return cap;}
/* Destroy every published authority, newest first: a narrowing never outlives the authority it narrows. */
static void core_io_table_free(void){while(core_io_table_count)myl_core_drop_owned(core_io_table[--core_io_table_count]);free(core_io_table);core_io_table=NULL;core_io_table_capacity=0;}
/* The number of capability handles published so far (the memory bound of a trial that makes them in a loop). */
static int64_t core_io_table_size(void){CORE_IO_GUARD;return (int64_t)core_io_table_count;}
typedef struct CoreIoScratch {struct CoreIoScratch *next;unsigned char data[];} CoreIoScratch;
static CoreIoScratch *core_io_scratch_head;
static unsigned char *core_io_copy(const unsigned char *source,size_t length){CORE_IO_GUARD;CoreIoScratch *copy=malloc(sizeof(*copy)+(length?length:1));if(!copy)out_of_memory();copy->next=core_io_scratch_head;core_io_scratch_head=copy;if(source&&length)memcpy(copy->data,source,length);return copy->data;}
static void core_io_copy_free(unsigned char *bytes){CORE_IO_GUARD;CoreIoScratch **at=&core_io_scratch_head;while(*at&&(*at)->data!=bytes)at=&(*at)->next;if(!*at)core_io_fail("InvalidProvider");CoreIoScratch *copy=*at;*at=copy->next;free(copy);}
static void core_io_unlink(CoreIoResource *resource) {
    if(resource->previous)resource->previous->next=resource->next;
    if(resource->next)resource->next->previous=resource->previous;else core_io_tail=resource->previous;
    resource->previous=resource->next=NULL;--core_io_open_count;--core_io_family_open[resource->family-2];
}
/* The name a resource was opened by is kept past its completion, so the trap of a use after close can name the file; the
   block's end (or the run's, for one still open) is where it goes. */
static void core_io_forget_path(CoreIoResource *resource){free(resource->path);resource->path=NULL;}
static void core_io_close(CoreIoResource *resource) {
    if(!resource->open)return;
    CoreIoState *state=core_io_state(resource->authority);
    resource->open=0;core_io_unlink(resource);state->adapter.release(state->adapter.context,resource->handle);core_io_forget_path(resource);
}
static int64_t core_io_live_handles(void){CORE_IO_GUARD;return core_io_open_count;}
static void core_io_cleanup(void) {CORE_IO_GUARD;
    for(unsigned family=3;family>=2;--family){CoreIoResource *resource=core_io_tail;while(resource){CoreIoResource *previous=resource->previous;if(resource->family==family)core_io_close(resource);resource=previous;}}
    while(core_io_scratch_head){CoreIoScratch *copy=core_io_scratch_head;core_io_scratch_head=copy->next;free(copy);}
    core_io_table_free();
    if(core_io_initialized){core_io_scoped_close(&core_io_real);core_io_initialized=0;}
    free(core_io_options);core_io_options=NULL;core_host_cleanup();core_registers_cleanup();
}
static void core_io_finalize(myl_block *block) {
    unsigned kind = kind_of(block);
    if (kind != 7 && kind != 8) return;
    CORE_IO_GUARD;
    if(kind_of(block)==7){core_io_close((CoreIoResource *)block_data(block));core_io_forget_path((CoreIoResource *)block_data(block));}
    if(kind_of(block)==8){CoreIoState *state=(CoreIoState *)block_data(block);if(state->memory)core_io_memory_free(state->memory);if(state->net)core_io_net_free(state->net);free(state->script);free(state->calls);}
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
static void core_io_bad_grant(void){core_io_option_error("selka: the option %s is not a usable capability grant\n",core_io_option_argument);}
/* The refusal of an entry capability a restricted run did not grant. `optional` is the family's optional form (CAP-OPT, `T?`):
   a `main` that declares the parameter so starts without the grant, and the message says so. */
static void core_io_missing_grant(const char *flag,const char *optional){char text[512];snprintf(text,sizeof text,"selka: --restrict is active and this command line did not grant a capability the entry point requests; pass %s, or drop --restrict to grant every capability; or, if the program can run without it, declare the parameter optional (`%s`)\n",flag,optional);core_io_option_error("%s",text);}
static void core_io_grant_request(const char *path,int writable){if(!*path||core_io_grant_count==8)core_io_bad_grant();for(size_t i=0;i<core_io_grant_count;++i)if(core_io_grants[i].writable==writable&&!strcmp(core_io_grants[i].path,path))core_io_bad_grant();core_io_grants[core_io_grant_count++]=(CoreIoGrant){path,writable};}
/* The next option of a writable `SELKA_OPTIONS` copy, unquoted in place, or NULL at
   its end. Options are separated by whitespace; a double quote groups whitespace into
   one option and a backslash inside quotes escapes the next byte. An unterminated
   quote ends the process with status 2. */
static char *core_io_next_option(char **cursor) {
    char *read=*cursor;
    while(*read&&strchr(" \t\n\r",*read))++read;
    if(!*read){*cursor=read;return NULL;}
    char *arg=read,*write=read;int quoted=0;
    while(*read&&(quoted||!strchr(" \t\n\r",*read))){if(*read=='"'){quoted=!quoted;++read;}else if(quoted&&*read=='\\'&&read[1]){++read;*write++=*read++;}else *write++=*read++;}
    if(quoted)core_io_option_error("selka: SELKA_OPTIONS has an unterminated quote\n%s","");
    if(*read)++read;
    *write=0;*cursor=read;
    return arg;
}
/* A runtime budget `myl_core_start` has already answered for the whole process. */
static int core_io_budget_option(const char *arg){return !strncmp(arg,"--max-steps=",12)||!strncmp(arg,"--max-frames=",13)||!strncmp(arg,"--timeout=",10)||!strncmp(arg,"--max-memory=",13);}
/* Core entry uses the same SELKA_OPTIONS grant grammar as qbe_grants.c. */
static void core_io_initialize(void) {
    if(core_io_initialized)return;
    core_io_initialized=1;core_io_scoped_init(&core_io_real);
    if(selka_native_providers_v7){core_io_native=selka_native_providers_v7();core_io_embedding=1;}
    const char *options=getenv("SELKA_OPTIONS");
    core_io_options=strdup(options?options:"");if(!core_io_options)out_of_memory();
    char *cursor=core_io_options,*arg;
    while((arg=core_io_next_option(&cursor))){
        core_io_option_argument=arg;
        if(!strcmp(arg,"--restrict")){if(core_io_restricted)core_io_bad_grant();core_io_restricted=1;}
        else if(!strncmp(arg,"--allow-read=",13)){core_io_grant_request(arg+13,0);}
        else if(!strncmp(arg,"--allow-write=",14)){core_io_grant_request(arg+14,1);}
        else if(!strncmp(arg,"--allow-endpoint=",17)){if(!core_io_scoped_endpoint(&core_io_real,arg+17))core_io_bad_grant();}
        else if(!strncmp(arg,"--allow-listen=",15)){if(!core_io_scoped_listen_endpoint(&core_io_real,arg+15))core_io_bad_grant();}
        else if(!strcmp(arg,"--allow-clock")){if(core_io_clock)core_io_bad_grant();core_io_clock=1;}
        else if(!strcmp(arg,"--allow-host")){if(core_io_host)core_io_bad_grant();core_io_host=1;}
        else if(!strcmp(arg,"--allow-process")){if(core_io_process)core_io_bad_grant();core_io_process=1;}
        else if(!strncmp(arg,"--allow-random",14)&&(arg[14]==0||arg[14]=='=')){if(core_io_entropy||(arg[14]&&!arg[15]))core_io_bad_grant();core_io_entropy=1;core_io_seed=arg[14]?strtoull(arg+15,NULL,10):0;}
        else if(!strncmp(arg,"--allow-env",11)&&(arg[11]==0||arg[11]=='=')){if(core_io_environment||(arg[11]&&!arg[12]))core_io_bad_grant();core_io_environment=1;core_io_names=arg[11]?arg+12:"";}
        else if(!strcmp(arg,"--allow-all")){if(core_io_clock||core_io_entropy||core_io_environment||core_io_host||core_io_process||core_io_grant_count||core_io_real.endpoint_count||core_io_real.listen_count)core_io_bad_grant();core_io_clock=core_io_entropy=core_io_environment=core_io_host=core_io_process=1;core_io_grant_request(".",1);core_io_scoped_endpoint(&core_io_real,"*");core_io_scoped_listen_endpoint(&core_io_real,"*");}
        else if(!strcmp(arg,"--print-result")||core_io_budget_option(arg)){/* read by myl_core_exit and myl_core_start */}
        else if(!strncmp(arg,"--allow-",8)||!strncmp(arg,"--restrict",10))core_io_bad_grant();
        else core_io_option_error("selka: SELKA_OPTIONS names %s, which is not a runtime option\n",arg);
    }
    core_io_enumerated_names=core_io_names;
    if(core_io_restricted){core_io_embedding=0;for(size_t i=0;i<core_io_grant_count;++i)if(!core_io_scoped_grant(&core_io_real,core_io_grants[i].path,core_io_grants[i].writable))core_io_option_error("selka: a requested directory grant could not be opened\n%s","");}
    if(!core_io_restricted){core_io_scoped_close(&core_io_real);core_io_scoped_init(&core_io_real);if(!core_io_embedding){if(!core_io_scoped_working_directory(&core_io_real))core_io_option_error("selka: a requested directory grant could not be opened\n%s","");core_io_scoped_endpoint(&core_io_real,"*");core_io_scoped_listen_endpoint(&core_io_real,"*");}core_io_clock=core_io_environment=core_io_host=core_io_process=1;if(!core_io_entropy&&!core_io_embedding){struct timespec now={0};clock_gettime(CLOCK_REALTIME,&now);core_io_seed=(uint64_t)now.tv_sec*1000000000+(uint64_t)now.tv_nsec;}core_io_entropy=1;}
}
/* Whether the command line (or the embedding host) grants `family`. For the clock (0) this is its wall time: a Clock is
   made without it (STOPWATCH), and `myl_core_external_read` refuses its wall reading when this is false. */
static int core_io_granted(uint32_t family){
    if(core_io_embedding)return family==0?core_io_native.clock_now!=NULL:family==1?core_io_native.random_u64!=NULL:family==2?(core_io_native.filesystem.acquire&&core_io_native.filesystem.complete&&core_io_native.filesystem.release):family==3?(core_io_native.network.acquire&&core_io_native.network.complete&&core_io_native.network.release):family==7?core_io_process:core_io_native.environment_get!=NULL;
    return family==0?core_io_clock:family==1?core_io_entropy:family==2?core_io_real.count!=0:family==3?(core_io_real.endpoint_count!=0||core_io_real.listen_count!=0):family==7?core_io_process:core_io_environment;
}
static int64_t core_io_grant(uint32_t family){
    /* A restricted run's Filesystem keeps the write right with read grants alone: the grant that holds a path decides what
       a call may do there (docs/io.md, "How a path is read"), so a write is refused as needing a write grant. */
    unsigned rights=7;if(family==3)rights=15;
    myl_block *provider=core_io_provider(family,0,(int64_t)core_io_seed,NULL);if(family==2||family==3){unsigned permissions=((CoreIoState *)block_data(provider))->adapter.permissions;if(permissions&~15u)core_io_fail("InvalidCapability");rights&=permissions;}myl_block *cap=core_io_cap(family,rights,provider,NULL,NULL);return core_io_publish(cap);
}
/* An entry `Clock` needs no grant (STOPWATCH): its monotonic reading and `sleep` reveal no wall time. */
int64_t myl_core_cap_grant(uint32_t family) {CORE_IO_GUARD;
    core_io_initialize();
    if(family!=0&&!core_io_granted(family)){const char *flag=family==1?"--allow-random":family==2?"--allow-read=DIR or --allow-write=DIR":family==3?"--allow-endpoint=IP:PORT or --allow-listen=IP:PORT":family==7?"--allow-process":"--allow-env";const char *optional=family==1?"rng: Entropy?":family==2?"fs: Filesystem?":family==3?"net: Network?":family==7?"proc: Process?":"env: Environment?";core_io_missing_grant(flag,optional);}
    return core_io_grant(family);
}
/* An entry `T?` (CAP-OPT): the handle `myl_core_cap_grant` makes when `family` is granted, else 0, which the entry passes as
   `None` (a handle is a block's address, the Host token -6). A `Clock?` is `None` without `--allow-clock`. */
int64_t myl_core_cap_offer(uint32_t family){CORE_IO_GUARD;
    core_io_initialize();
    if(family==6)return core_io_host?-6:0;
    return core_io_granted(family)?core_io_grant(family):0;
}
int64_t myl_core_host_grant(void){CORE_IO_GUARD;core_io_initialize();if(!core_io_host)core_io_missing_grant("--allow-host","host: Host?");return -6;}
void myl_core_host_check(int64_t token){CORE_IO_GUARD;core_io_initialize();if(token!=-6||!core_io_host)core_io_fail("R_CAPABILITY");}
int64_t myl_core_stand_in(uint32_t family,int64_t value){CORE_IO_GUARD;myl_block *state=core_io_provider(family,1,value,NULL);myl_block *cap=core_io_cap(family,family==3&&value==1?15:7,state,NULL,NULL);return core_io_publish(cap);}
/* `__stand_fail(capability, count)`: arm a stand-in Clock or Entropy to answer `count` more reads (none for a count below
   one) and then fail every read. Returns 0, or 1 for a capability that is not a stand-in clock or entropy. */
int64_t myl_core_stand_in_fail(int64_t handle,int64_t count){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);CoreIoState *state=core_io_state(cap);if(!state->test||state->family>1)return 1;state->failing=1;state->remaining=count<0?0:count;return 0;}
int64_t myl_core_environment_fixed(myl_block *pairs){CORE_IO_GUARD;if(!core_io_memory_valid_pairs(block_data(pairs),(size_t)pairs->len))core_io_fail("R_ENVIRONMENT");myl_block *state=core_io_provider(4,1,0,pairs);myl_block *cap=core_io_cap(4,7,state,NULL,NULL);return core_io_publish(cap);}
/* The monotonic reading of a clock, in nanoseconds: it never decreases, whatever wall-clock steps happen. A simulated
   clock keeps its own counter, which only `sleep` moves (`advance` steps the wall reading alone); a host clock reads
   the system's monotonic clock. */
int64_t myl_core_clock_monotonic(int64_t handle){CORE_IO_GUARD;myl_block *clock=core_io_handle(handle);CoreIoState *state=core_io_state(clock);if(state->family!=0)core_io_fail("InvalidCapability");if(state->test)return state->monotonic;struct timespec now={0};if(clock_gettime(CLOCK_MONOTONIC,&now)||now.tv_sec>(INT64_MAX-now.tv_nsec)/1000000000)core_io_fail("R_CAPABILITY");return (int64_t)now.tv_sec*1000000000+now.tv_nsec;}
/* Wait `nanoseconds` on a clock; a count of zero or less waits for nothing. A simulated clock advances its wall and
   monotonic readings by the count instead of waiting, saturating at the top of the 64-bit range. */
void myl_core_clock_sleep(int64_t handle,int64_t nanoseconds){CORE_IO_GUARD;myl_block *clock=core_io_handle(handle);CoreIoState *state=core_io_state(clock);if(state->family!=0)core_io_fail("InvalidCapability");if(nanoseconds<=0)return;if(state->test){state->value=state->value>INT64_MAX-nanoseconds?INT64_MAX:state->value+nanoseconds;state->monotonic=state->monotonic>INT64_MAX-nanoseconds?INT64_MAX:state->monotonic+nanoseconds;return;}core_flush_before_wait();if(core_stop_installed()){core_stop_sleep(nanoseconds);return;}struct timespec wait={.tv_sec=nanoseconds/1000000000,.tv_nsec=nanoseconds%1000000000},rest;while(nanosleep(&wait,&rest)&&errno==EINTR)wait=rest;}
int64_t myl_core_clock_advance(int64_t handle,int64_t delta){CORE_IO_GUARD;myl_block *clock=core_io_handle(handle);CoreIoState *state=core_io_state(clock);if(state->family!=0)core_io_fail("InvalidCapability");if(!state->test)return 1;if((delta>0&&state->value>INT64_MAX-delta)||(delta<0&&state->value<INT64_MIN-delta))return 2;state->value+=delta;return 0;}
/* A host clock's wall reading needs `--allow-clock` (STOPWATCH): without it the read answers status 5, which `time.now`
   fails with "the wall clock is not granted". A stand-in clock reads its own counter and needs no grant. */
myl_block *myl_core_external_read(int64_t handle,uint32_t family){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);CoreIoState *state=core_io_state(cap);if(state->family!=family||family>1)core_io_fail("InvalidCapability");uint64_t value=0;int status=0;
    if(family==0&&!state->test&&!core_io_granted(0))return core_io_result(5,0,NULL,0);
    /* An armed stand-in answers its remaining reads and then fails the way a provider that stopped working does (status 3). */
    if(state->failing){if(!state->remaining)return core_io_result(3,0,NULL,0);--state->remaining;}if(family==0){if(state->test)value=(uint64_t)state->value;else if(core_io_embedding){CoreIoClockResult result=core_io_native.clock_now(core_io_native.clock_context);status=(int)result.status;value=(uint64_t)result.value;}else{struct timespec now={0};status=clock_gettime(CLOCK_REALTIME,&now)||now.tv_sec>(INT64_MAX-now.tv_nsec)/1000000000?3:0;value=status?0:(uint64_t)now.tv_sec*1000000000+(uint64_t)now.tv_nsec;}}else if(!state->test&&core_io_embedding){CoreIoRandomResult result=core_io_native.random_u64(core_io_native.random_context);status=(int)result.status;value=result.value;}else{state->value=(int64_t)((uint64_t)state->value+UINT64_C(0x9e3779b97f4a7c15));value=(uint64_t)state->value;value=(value^(value>>30))*UINT64_C(0xbf58476d1ce4e5b9);value=(value^(value>>27))*UINT64_C(0x94d049bb133111eb);value^=value>>31;}if(status==4)out_of_memory();if(status<0||status>3)core_io_fail("InvalidProviderResult");return core_io_result(status,status?0:value,NULL,0);}
int64_t myl_core_cap_restrict(int64_t handle,uint32_t rights){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);CoreIoAuthority *a=core_io_authority(cap);return core_io_publish(core_io_cap(a->family,(a->rights&rights)|(a->rights&CORE_IO_DIR_LINKED),a->provider,cap,a->scope));}
static myl_block *core_io_scope(myl_block *cap,myl_block *scope,unsigned family,int append){CoreIoAuthority *a=core_io_authority(cap);if(a->family!=family)core_io_fail("InvalidCapability");myl_block *joined=scope;if(append&&a->scope&&a->scope->len){size_t length=(size_t)(a->scope->len+scope->len+(scope->len!=0));unsigned char *bytes=malloc(length);if(!bytes)out_of_memory();memcpy(bytes,block_data(a->scope),(size_t)a->scope->len);if(scope->len){bytes[a->scope->len]='/';memcpy(bytes+a->scope->len+1,block_data(scope),(size_t)scope->len);}joined=core_io_string(bytes,length,1);free(bytes);}else {
    joined=myl_core_owned_octets_copy(scope);
}myl_block *out=core_io_cap_new(family,a->rights,a->provider,cap,joined);
return out;}
/* The folder a `filesystem.dir_at` path names, as the scope a `fs.dir` narrowing keeps (docs/io.md, "A folder named at run
   time"), for a path that is not clean (it is absolute or has an empty, `.` or `..` component) on a handle that is not
   narrowed. On the in-memory filesystem it is read as that filesystem reads a path, below its root. On the real one it is
   made absolute against the working directory (the one taken at the start under `--restrict`, as a path is read there) and
   normalized as text, then written relative to the working directory when it lies inside it, so the scope is the one
   `fs.dir` keeps for the same folder. `dir_at` has checked the folder with `stat` and refused a `..` that steps out of a
   link, and afterwards checks through the new handle that it reaches that folder without a link; this only writes the name
   down, and every call through the handle walks it again. NULL when the path cannot be read here. */
static myl_block *core_io_dir_scope(myl_block *cap, myl_block *path) {
    CoreIoState *state = core_io_state(cap);
    const char *text = (const char *)block_data(path);
    const size_t width = (size_t)path->len;
    if (memchr(text, 0, width) || width >= CORE_IO_SCOPED_PATH) return NULL;
    if (state->test) {
        unsigned char normal[CORE_IO_SCOPED_PATH];
        size_t length = 0;
        if (!state->memory || core_io_memory_normalize(state->memory, (const unsigned char *)text, width, 'm', normal, &length)) return NULL;
        return core_io_string(normal, length, 1);
    }
    if (core_io_embedding || state->adapter.acquire != core_io_scoped_acquire) return NULL;
    const CoreIoScoped *scoped = state->adapter.context;
    char here[CORE_IO_SCOPED_PATH], absolute[CORE_IO_SCOPED_PATH];
    size_t cwd = 0, length = 0, floor = 0, below = 0;
    int directory = 0;
    if (scoped->count && !scoped->roots[0].direct) {
        memcpy(here, core_io_scoped_cwd, core_io_scoped_cwd_length);
        cwd = core_io_scoped_cwd_length;
    } else {
        if (!getcwd(here, sizeof here)) return NULL;
        cwd = strcmp(here, "/") ? strlen(here) : 0;
    }
    if (text[0] != '/') {
        memcpy(absolute, here, cwd);
        length = floor = cwd;
    }
    if (core_io_path_normalize(text, width, absolute, &length, &floor, NULL, NULL, &directory)) return NULL;
    if (core_io_scoped_holds(here, cwd, absolute, length, &below)) return core_io_string(absolute + below, length - below, 1);
    return length ? core_io_string(absolute, length, 1) : core_io_string("/", 1, 1);
}
/* The handle `fs.dir(path)` answers: a literal is clean (the checker sees to it) and kept as written, joined below a
   narrowing's own folder. A computed path comes from `filesystem.dir_at`; one this cannot read gives a handle with no
   rights, which reaches nothing (`dir_at` has refused such a path before it gets here). */
static myl_block *core_io_dir_handle(myl_block *cap,myl_block *path){
    if(!path->len||core_io_memory_valid_path(block_data(path),(size_t)path->len,'m'))return core_io_scope(cap,path,2,1);
    CoreIoAuthority *a=core_io_authority(cap);if(a->family!=2)core_io_fail("InvalidCapability");
    myl_block *scope=a->scope?NULL:core_io_dir_scope(cap,path);
    if(!scope)return core_io_cap_new(2,0,a->provider,cap,myl_core_owned_octets_copy(path));
    return core_io_cap_new(2,a->rights,a->provider,cap,scope);}
static unsigned core_io_dir_link(myl_block *cap,myl_block *scope);
/* `fs.dir(path)`, a literal or `filesystem.dir_at`'s computed path: under `--restrict` a handle whose folder is reached
   through a symbolic link in a grant's given name carries the mark of that link, and every call through it is refused. */
int64_t myl_core_cap_dir(int64_t handle,myl_block *path){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);
    myl_block *made=core_io_dir_handle(cap,path);CoreIoAuthority *a=core_io_authority(made);
    if(a->rights&&a->scope)a->rights|=core_io_dir_link(cap,a->scope);
    return core_io_publish(made);}
/* Under `--restrict`, whether the folder a narrowing's `scope` names is reached through a symbolic link (DIRAT-LINK): the
   grant that holds it holds it only by the name given on the command line, which differs from the grant's real path, so
   that name has a link in it. Every other link is refused by the walk below the grant; this one was followed once, when
   the grant was opened, and a plain path read through the grant's name keeps following it. `CORE_IO_DIR_LINK` when the
   folder is the grant itself and its given name is the link, as `stat` of it says in a run without `--restrict`;
   `CORE_IO_DIR_THROUGH_LINK` for a link on the way; 0 when no link is on the way or the run has no grants. */
static unsigned core_io_dir_link(myl_block *cap,myl_block *scope){
    const CoreIoState *state=core_io_state(cap);
    if(state->test||core_io_embedding||state->adapter.acquire!=core_io_scoped_acquire)return 0;
    const CoreIoScoped *scoped=state->adapter.context;
    if(!scoped->count||scoped->roots[0].direct)return 0;
    const char *text=(const char *)block_data(scope);
    const size_t width=(size_t)scope->len;
    if(memchr(text,0,width)||width>=CORE_IO_SCOPED_PATH)return 0;
    char absolute[CORE_IO_SCOPED_PATH];
    size_t length=0,floor=0;
    int directory=0;
    if(!width||text[0]!='/'){memcpy(absolute,core_io_scoped_cwd,core_io_scoped_cwd_length);length=floor=core_io_scoped_cwd_length;}
    if(core_io_path_normalize(text,width,absolute,&length,&floor,NULL,NULL,&directory))return 0;
    absolute[length]=0;
    /* A read is served by the grant with the longest name that holds the folder, a write by the longest writable one. */
    for(int writing=0;writing<2;++writing){
        size_t below=0;
        int spelled=0;
        if(core_io_scoped_holder(scoped,absolute,length,writing,&below,&spelled)<0||!spelled)continue;
        struct stat info;
        if(below==length&&!lstat(length?absolute:"/",&info)&&S_ISLNK(info.st_mode))return CORE_IO_DIR_LINK;
        return CORE_IO_DIR_THROUGH_LINK;
    }
    return 0;
}
int64_t myl_core_cap_host(int64_t handle,myl_block *name){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);CoreIoAuthority *a=core_io_authority(cap);if(!name->len||name->len>4096||memchr(block_data(name),0,(size_t)name->len))core_io_fail("InvalidCapability");if(a->scope&&!myl_core_str_eq(a->scope,name))core_io_fail("InvalidCapability");return core_io_publish(core_io_scope(cap,name,3,0));}
int64_t myl_core_environment_only(int64_t handle,myl_block *names){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);CoreIoAuthority *a=core_io_authority(cap);if(a->family!=4||a->scope)core_io_fail("R_CAPABILITY");if(!names->len||block_data(names)[names->len-1]!=0)core_io_fail("InvalidCapability");return core_io_publish(core_io_scope(cap,names,4,0));}

static int core_io_resource_acquire(myl_block *cap,const unsigned char *request,size_t length,myl_block **output) {
    CoreIoAuthority *authority=core_io_authority(cap);CoreIoState *state=core_io_state(cap);
    if(authority->family!=2&&authority->family!=3)core_io_fail("InvalidCapability");
    if(authority->family==3&&state->test&&state->value!=1)return 6;
    unsigned char joined[8192];const unsigned char *input=request;size_t width=length;
    int addressed=authority->family==3&&length&&(request[0]&CORE_IO_ADDRESSED);
    /* The refusals of a narrowed handle say which narrowing refused (docs/io.md, rule 5). */
    if(authority->family==2&&length>=2&&request[1]==':'&&core_io_scoped_writing_mode(request[0])&&!(authority->rights&2u)){core_io_os_reason=CORE_IO_REFUSAL_READ_ONLY;return 2;}
    if(authority->scope){size_t scope=(size_t)authority->scope->len;if(authority->family==2){if(length<2||request[1]!=':'||!core_io_memory_valid_path(request+2,length-2,request[0])){core_io_os_reason=CORE_IO_REFUSAL_NARROWED;return 2;}if(scope+length+1>sizeof joined)return 2;joined[0]=request[0];joined[1]=':';memcpy(joined+2,block_data(authority->scope),scope);size_t at=scope+2;if(length>2){if(scope&&block_data(authority->scope)[scope-1]!='/')joined[at++]='/';memcpy(joined+at,request+2,length-2);at+=length-2;}width=at;}else if(!addressed){size_t tag=(length==1&&(request[0]==1||request[0]==2||request[0]==CORE_IO_CLIENT_POLLER_TAG))?1:(length==CORE_IO_DIAL_LIMITS_HEADER&&request[0]==CORE_IO_DIAL_LIMITS_TAG)?CORE_IO_DIAL_LIMITS_HEADER:(length==CORE_IO_POLL_DIAL_HEADER&&request[0]==CORE_IO_POLL_DIAL_TAG)?CORE_IO_POLL_DIAL_HEADER:0;if(scope+tag>sizeof joined)return 2;if(tag)memcpy(joined,request,tag);memcpy(joined+tag,block_data(authority->scope),scope);width=scope+tag;}if(!addressed)input=joined;}
    if(authority->family==2&&(authority->rights&CORE_IO_DIR_LINKED)){core_io_os_reason=core_io_dir_link_reason(authority->rights,length<=2,1);return 2;}
    /* An addressed request (FR5a) names its address after its header: through a narrowed Network only the narrowing's
       own address may be named, and a different one, or none, is refused as outside the grant rather than sent to the
       narrowing's. The provider then sees the request without the flag, as an unnarrowed Network's request. */
    if(addressed){size_t head=core_io_addressed_header(request[0]);if(length<head||length>sizeof joined)return 2;
        if(authority->scope&&(length-head!=(size_t)authority->scope->len||memcmp(request+head,block_data(authority->scope),length-head)))return 2;
        memcpy(joined,request,length);joined[0]&=(unsigned char)~CORE_IO_ADDRESSED;input=joined;width=length;}
    if(!state->adapter.acquire)return 1;
    if(core_io_family_open[authority->family-2]>=1024)return 4;
    /* Allocate bookkeeping before acquiring, so registration cannot fail. */
    myl_block *block=block_new(7,sizeof(CoreIoResource),1);block->len=1;block->reserved=(int64_t)(intptr_t)core_io_resource_layout;
    memset(block_data(block),0,sizeof(CoreIoResource));
    unsigned char *request_copy=core_io_copy(input,width);CoreIoResourceResult result=state->adapter.acquire(state->adapter.context,request_copy,width,(authority->rights&state->adapter.permissions)|(authority->family==2&&authority->scope?CORE_IO_PROVIDER_NARROWED:0u));core_io_copy_free(request_copy);
    if(result.status==CORE_IO_PROVIDER_OUT_OF_MEMORY){block->reserved=0;block_free(block);out_of_memory();}
    if(result.status>3&&result.status!=CORE_IO_PROVIDER_TIMED_OUT){block->reserved=0;block_free(block);core_io_fail("InvalidProvider");}
    if(result.status){block->reserved=0;block_free(block);return (int)result.status;}
    /* Only a listening acquisition (mode tag 1, preserved through narrowing) keeps the accept right. */
    unsigned rights=authority->rights&state->adapter.permissions;if(authority->family!=3||!width||input[0]!=1)rights&=~8u;
    CoreIoResource *resource=(CoreIoResource *)block_data(block);*resource=(CoreIoResource){cap,result.handle,authority->family,rights,1,0,core_io_tail,NULL,block,NULL};
    if(authority->family==2&&width>2){resource->path=malloc(width-1);if(!resource->path)out_of_memory();memcpy(resource->path,input+2,width-2);resource->path[width-2]=0;}
    if(core_io_tail)core_io_tail->next=resource;core_io_tail=resource;++core_io_open_count;++core_io_family_open[authority->family-2];*output=block;return 0;
}
static CoreIoResource *core_io_resource(myl_block *owner){if(!owner||kind_of(owner)!=7)core_io_fail("InvalidOwner");return (CoreIoResource *)block_data(owner);}
static int core_io_complete(myl_block *owner){CoreIoResource *resource=core_io_resource(owner);if(!resource->open){core_io_os_reason="the file is already closed";return 3;}if(!(resource->rights&4))return 2;CoreIoState *state=core_io_state(resource->authority);int status=(int)state->adapter.complete(state->adapter.context,resource->handle);if(status==4)out_of_memory();if(status<0||status>3)core_io_fail("InvalidProvider");if(!status){resource->open=0;core_io_unlink(resource);}return status;}
void myl_core_file_scope_close(myl_block *owner){CORE_IO_GUARD;if(!owner)return;CoreIoResource *resource=core_io_resource(owner);if(!resource->open)return;if(!(resource->rights&4)){core_io_close(resource);return;}core_io_os_reason=NULL;int status=core_io_complete(owner);if(status)core_io_resource_trap(resource,"close",status);}
/* NEW-CORE-ZERO-RC-RESOURCES-1: the explicit provider argument extends its
   compiler lifetime through completion and resource destruction. */
void myl_core_owned_file_scope_end(myl_block *owner, int64_t provider) {
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
    CoreIoResource *resource=core_io_resource(owner);*written=0;*eof=0;if(!resource->open)core_io_fail("InvalidOwner");if(!(resource->rights&1)||(resource->rights&8))return 2;CoreIoState *state=core_io_state(resource->authority);if(!state->adapter.read)return 1;
    /* The runtime's own provider (files, sockets, the poller) is handed `out` itself: the private copy below is the
       boundary to a provider a host embedded, which is not trusted with the program's memory. */
    int own_provider=state->adapter.read==core_io_scoped_read_handle;
    unsigned char *copy=own_provider?out:core_io_copy(NULL,cap);CoreIoResourceRead result=state->adapter.read(state->adapter.context,resource->handle,copy,cap);
    if(result.status==4)out_of_memory();if(result.status>3&&result.status!=CORE_IO_PROVIDER_TIMED_OUT)core_io_fail("InvalidProvider");
    if(!result.status){if(result.length>cap||(result.eof!=0&&result.eof!=1))core_io_fail("InvalidProvider");if(result.length&&!own_provider)memcpy(out,copy,result.length);*written=result.length;*eof=result.eof;}
    if(!own_provider)core_io_copy_free(copy);if(cap>*written)memset(out+*written,0,cap-*written);return (int)result.status;
}
static int core_io_write(myl_block *owner,const unsigned char *data,size_t len,size_t *written){
    CoreIoResource *resource=core_io_resource(owner);*written=0;if(!resource->open)core_io_fail("InvalidOwner");if(!(resource->rights&2)||(resource->rights&8))return 2;CoreIoState *state=core_io_state(resource->authority);if(!state->adapter.write)return 1;
    int own_provider=state->adapter.write==core_io_scoped_write_handle;
    const unsigned char *copy=own_provider?data:core_io_copy(data,len);CoreIoResourceWrite result=state->adapter.write(state->adapter.context,resource->handle,copy,len);
    if(result.status==4)out_of_memory();if(result.status>3&&result.status!=CORE_IO_PROVIDER_TIMED_OUT)core_io_fail("InvalidProvider");if(!result.status){if(result.length>len)core_io_fail("InvalidProvider");*written=result.length;}if(!own_provider)core_io_copy_free((unsigned char *)copy);return (int)result.status;
}

/* Accept one connection through a live listening resource. The provider read
   channel returns the new handle slot as eight octets, so a listener is never
   readable by the guest (core_io_read refuses the accept right) and only a
   listening acquisition holds the accept right (core_io_resource_acquire).
   This function registers the peer as an ordinary network resource with
   read/write/complete rights. */
static int core_io_accept(myl_block *listener,myl_block **output) {
    CoreIoResource *resource=core_io_resource(listener);
    if(!resource->open)return 3;
    if(!(resource->rights&8))return 2;
    CoreIoState *state=core_io_state(resource->authority);
    if(!state->adapter.read)return 1;
    if(core_io_family_open[resource->family-2]>=1024)return 4;
    myl_block *block=block_new(7,sizeof(CoreIoResource),1);block->len=1;block->reserved=(int64_t)(intptr_t)core_io_resource_layout;
    memset(block_data(block),0,sizeof(CoreIoResource));
    uint64_t handle=0;
    unsigned char raw[sizeof handle];CoreIoResourceRead result=state->adapter.read(state->adapter.context,resource->handle,raw,sizeof raw);
    if(result.status==CORE_IO_PROVIDER_OUT_OF_MEMORY){block->reserved=0;block_free(block);out_of_memory();}
    if(result.status>3){block->reserved=0;block_free(block);core_io_fail("InvalidProvider");}
    if(result.status){block->reserved=0;block_free(block);return (int)result.status;}
    if(result.length!=sizeof raw){block->reserved=0;block_free(block);core_io_fail("InvalidProvider");}
    memcpy(&handle,raw,sizeof handle);
    CoreIoResource *accepted=(CoreIoResource *)block_data(block);
    *accepted=(CoreIoResource){resource->authority,handle,resource->family,(resource->rights&state->adapter.permissions)&7u,1,0,core_io_tail,NULL,block};
    if(core_io_tail)core_io_tail->next=accepted;core_io_tail=accepted;++core_io_open_count;++core_io_family_open[resource->family-2];*output=block;return 0;
}
myl_block *myl_core_resource_acquire(int64_t handle,myl_block *request){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);myl_block *resource=NULL;int status=core_io_resource_acquire(cap,block_data(request),(size_t)request->len,&resource);return core_io_result(status,(uint64_t)(uintptr_t)resource,NULL,1);}
myl_block *myl_core_resource_accept(myl_block *owner){CORE_IO_GUARD;myl_block *resource=NULL;int status=core_io_accept(owner,&resource);return core_io_result(status,(uint64_t)(uintptr_t)resource,NULL,1);}
int64_t myl_core_resource_complete(myl_block *owner){CORE_IO_GUARD;return core_io_complete(owner);}
/* What a failed file operation says: the system's reason when it gave one, else the words for the status. Only a filesystem a
   host supplied, which answers "failed" and no reason, reaches the last sentence. */
static const char *core_io_reason(int status){if(status==1)return "no filesystem authority is available";if((status==2||status==3)&&core_io_os_reason)return core_io_os_reason;if(status==2)return "denied: the filesystem refused the request";if(status==4)return "too many files are open";if(status==5)return "the bytes read are not valid UTF-8 text";if(status==CORE_IO_PROVIDER_TIMED_OUT)return "timed out";return "failed: the filesystem gave no reason";}
/* The trap of a failed method of an open file (`f.read`, `f.write`, `f.close`, or a `with` that could not open): `R_FILE` whose
   text names what was asked, the path the program gave and the reason, as the `Err` of the whole-file calls does
   (`write 'out.bin': no space left on the device`). A handle that was not opened by name has no path to give. */
static MYL_TLS char core_io_trap_text[640];
__attribute__((cold,noinline)) static void core_io_file_trap(const char *verb,const char *path,size_t path_len,const char *reason){
    if(path&&path_len)snprintf(core_io_trap_text,sizeof core_io_trap_text,"%s '%.*s': %s",verb,path_len>300?300:(int)path_len,path,reason);
    else snprintf(core_io_trap_text,sizeof core_io_trap_text,"%s: %s",verb,reason);
    core_failure_detail=core_io_trap_text;
    core_io_fail("R_FILE");
}
/* The same trap for a message built elsewhere (the durable calls' `Err` text). */
__attribute__((cold,noinline)) static void core_io_message_trap(const char *text,size_t length){
    snprintf(core_io_trap_text,sizeof core_io_trap_text,"%.*s",length>sizeof core_io_trap_text-1?(int)sizeof core_io_trap_text-1:(int)length,text);
    core_failure_detail=core_io_trap_text;
    core_io_fail("R_FILE");
}
static void core_io_resource_trap(const CoreIoResource *resource,const char *verb,int status){
    core_io_file_trap(verb,resource->path,resource->path?strlen(resource->path):0,core_io_reason(status));
}
static myl_block *core_io_file_error(unsigned kind,const unsigned char *path,uint64_t path_len,int status){static const char *verbs[]={"open","read","read","write","write","stat","listdir","mkdir","remove"};const char *verb=verbs[kind],*reason=core_io_reason(status);size_t length=strlen(verb)+strlen(reason)+(size_t)path_len+5;char *message=malloc(length+1);if(!message)out_of_memory();size_t at=(size_t)sprintf(message,"%s '",verb);memcpy(message+at,path,(size_t)path_len);at+=(size_t)path_len;at+=(size_t)sprintf(message+at,"': %s",reason);myl_block *text=core_io_string(message,at,1);free(message);return text;}
typedef struct {unsigned char *bytes;size_t length,capacity;} CoreIoBytes;
/* FR-021: a whole read has no octet cap. It reads to end of file, and the chunked buffer counts against the
   byte ceiling while it grows (heap_charge), so a read past `--max-memory` traps R_MEMORY_BUDGET instead of
   stopping short. The sized path's block is charged by block_new. */
#define CORE_IO_UNCAPPED SIZE_MAX
static void core_io_bytes_release(CoreIoBytes *bytes){heap_refund(bytes->capacity);free(bytes->bytes);bytes->bytes=NULL;bytes->length=bytes->capacity=0;}
static void core_io_append(CoreIoBytes *bytes,const unsigned char *data,size_t length){if(length>SIZE_MAX-bytes->length)out_of_memory();if(bytes->length+length>bytes->capacity){size_t cap=bytes->capacity?bytes->capacity:128;while(cap<bytes->length+length){if(cap>SIZE_MAX/2){cap=bytes->length+length;break;}cap*=2;}heap_charge(cap-bytes->capacity);unsigned char *grown=realloc(bytes->bytes,cap);if(!grown)out_of_memory();bytes->bytes=grown;bytes->capacity=cap;}if(length)memcpy(bytes->bytes+bytes->length,data,length);bytes->length+=length;}
/* One line, up to `limit` octets, from a built-in file that can seek or from a snapshot: one transfer per
   16 KiB, after which the octets read past the newline go back (the file offset moves back over them, a
   snapshot's position does), so the next read of any kind starts right after the line, as it did when a
   line was read one octet per call. Files open only for reading, writing or appending, so moving the
   offset back never moves a write. Returns -1 for every other resource (pipes, sockets, other providers),
   which keeps the one-octet path. */
static int core_io_read_line_direct(myl_block *owner,size_t limit,CoreIoBytes *out){
    CoreIoResource *resource=core_io_resource(owner);
    if(!resource->open||!(resource->rights&1)||(resource->rights&8))return -1;
    CoreIoState *state=core_io_state(resource->authority);
    if(state->adapter.read!=core_io_scoped_read_handle)return -1;
    CoreIoScopedHandle *handle=core_io_scoped_live(state->adapter.context,resource->handle);
    if(!handle||handle->poller||handle->listening||handle->mode=='a')return -1;
    if(handle->snapshot){
        size_t available=handle->length-handle->position,width=available<limit?available:limit;
        const unsigned char *start=handle->snapshot+handle->position,*newline=memchr(start,'\n',width);
        if(newline)width=(size_t)(newline-start)+1;
        core_io_append(out,start,width);
        handle->position+=width;
        return 0;
    }
    if(handle->fd<0||lseek(handle->fd,0,SEEK_CUR)<0)return -1;
    unsigned char data[16384];
    while(out->length<limit){
        size_t take=sizeof data;
        if(take>limit-out->length)take=limit-out->length;
        CoreIoResourceRead part=core_io_scoped_read_handle(state->adapter.context,resource->handle,data,take);
        if(part.status==CORE_IO_PROVIDER_OUT_OF_MEMORY)out_of_memory();
        if(part.status>3)core_io_fail("InvalidProvider");
        if(part.status)return (int)part.status;
        if(part.length>take)core_io_fail("InvalidProvider");
        const unsigned char *newline=memchr(data,'\n',part.length);
        size_t keep=newline?(size_t)(newline-data)+1:part.length;
        core_io_append(out,data,keep);
        if(keep<part.length&&lseek(handle->fd,-(off_t)(part.length-keep),SEEK_CUR)<0)return core_io_failed_with(errno);
        if(newline||!part.length||part.eof)break;
    }
    return 0;
}
static int core_io_read_all(myl_block *resource,size_t limit,int line,CoreIoBytes *out){if(line){int direct=core_io_read_line_direct(resource,limit,out);if(direct>=0)return direct;}unsigned char data[16384];while(out->length<limit){size_t take=line?1:sizeof data;if(take>limit-out->length)take=limit-out->length;size_t read;int eof;int status=core_io_read(resource,data,take,&read,&eof);if(status)return status;core_io_append(out,data,read);if(!read||eof||(line&&data[0]=='\n'))break;}return 0;}
static int core_io_write_span_all(myl_block *resource,const unsigned char *input,size_t length,size_t *out){*out=0;while(*out<length){size_t written;size_t remaining=length-*out;int status=core_io_write(resource,input+*out,remaining<65536?remaining:65536,&written);if(status)return status;if(!written){core_io_os_reason="no bytes could be written";return 3;}*out+=written;}return 0;}
static myl_block *core_io_sequence(CoreIoBytes *bytes,int text,int *status){if(text&&!core_io_utf8(bytes->bytes,bytes->length)){*status=5;return NULL;}return core_io_string(bytes->bytes,bytes->length,text);}
/* NEW-CORE-FILE-READ-1 (FR-018): the length a whole-file read can expect, when the
   resource is a readable regular file of the built-in filesystem provider that was
   non-empty when opened; 0 for everything else (pipes, /proc, snapshots, the test and
   embedded providers), which keep the chunked path. Invalid resources are not
   diagnosed here: the chunked path reports them. */
static size_t core_io_size_hint(myl_block *owner) {
    CoreIoResource *resource=core_io_resource(owner);
    if(!resource->open||!(resource->rights&1)||(resource->rights&8))return 0;
    CoreIoState *state=core_io_state(resource->authority);
    if(state->adapter.read!=core_io_scoped_read_handle)return 0;
    CoreIoScopedHandle *handle=core_io_scoped_live(state->adapter.context,resource->handle);
    if(!handle||handle->fd<0||handle->snapshot||handle->listening||handle->mode=='a')return 0;
    return handle->size;
}
/* Everything left in `owner` up to `limit` octets, as a new `str` (text) or `bytes`
   block, or NULL with `*status` set (as core_io_read_all; 5: not UTF-8). A file whose
   size is known is read straight into its result block, sized from that length, then
   asked once more for end of file (two `read` calls for a file that fits one transfer,
   and one copy); a file that grew meanwhile, or whose size was not known, goes through
   the chunked buffer as before. */
static myl_block *core_io_read_sequence(myl_block *owner,size_t limit,int text,int *status) {
    *status=0;
    size_t hint=core_io_size_hint(owner),want=hint<limit?hint:limit;
    if(want){
        CoreIoResource *resource=core_io_resource(owner);
        CoreIoState *state=core_io_state(resource->authority);
        myl_block *block=block_new(text?MYL_KIND_STR:MYL_KIND_BYTES,(int64_t)want,1);
        size_t length=0;
        int ended=0;
        while(length<want&&!ended){
            CoreIoResourceRead part=core_io_scoped_read_handle(state->adapter.context,resource->handle,block_data(block)+length,want-length);
            if(part.status==CORE_IO_PROVIDER_OUT_OF_MEMORY)out_of_memory();
            if(part.status>3)core_io_fail("InvalidProvider");
            if(part.status){core_io_drop(block);*status=(int)part.status;return NULL;}
            if(part.length>want-length)core_io_fail("InvalidProvider");
            length+=part.length;
            ended=!part.length||part.eof;
        }
        unsigned char probe[512];
        size_t more=0;
        if(!ended&&length<limit){
            CoreIoResourceRead part=core_io_scoped_read_handle(state->adapter.context,resource->handle,probe,sizeof probe);
            if(part.status==CORE_IO_PROVIDER_OUT_OF_MEMORY)out_of_memory();
            if(part.status>3)core_io_fail("InvalidProvider");
            if(part.status){core_io_drop(block);*status=(int)part.status;return NULL;}
            if(part.length>sizeof probe)core_io_fail("InvalidProvider");
            more=part.length;
        }
        if(!more){
            if(text&&!core_io_utf8(block_data(block),length)){core_io_drop(block);*status=5;return NULL;}
            if(length!=want){
                /* A file shorter than its size said (a truncation, or /sys, which reports a page): keep an exact block. */
                myl_block *exact=core_io_string(block_data(block),length,text);
                core_io_drop(block);
                return exact;
            }
            block->len=(int64_t)length;
            if(text){block_data(block)[length]=0;core_text_publish(block);}
            return block;
        }
        /* The file grew after it was opened: continue in the chunked buffer. */
        CoreIoBytes grown={0};
        core_io_append(&grown,block_data(block),length);
        core_io_append(&grown,probe,more);
        core_io_drop(block);
        *status=core_io_read_all(owner,limit,0,&grown);
        myl_block *value=*status?NULL:core_io_sequence(&grown,text,status);
        core_io_bytes_release(&grown);
        return value;
    }
    CoreIoBytes raw={0};
    *status=core_io_read_all(owner,limit,0,&raw);
    myl_block *value=*status?NULL:core_io_sequence(&raw,text,status);
    core_io_bytes_release(&raw);
    return value;
}
static myl_block *core_io_list_new(size_t capacity){myl_block *list=block_new(MYL_KIND_LIST,(int64_t)capacity,8);list->reserved=(int64_t)(intptr_t)core_io_list_layout;return list;}
static void core_io_list_add(myl_block **list,myl_block *item){*list=myl_core_list_grow(*list,8);myl_block **data=(myl_block **)block_data(*list);data[(*list)->len++]=item;}
static myl_block *core_io_listing(CoreIoBytes *raw,int *status){myl_block *list=core_io_list_new(0);if(!raw->length||raw->bytes[0]!=1){*status=3;return list;}size_t at=1;while(at<raw->length){if(at+3>raw->length){*status=3;break;}size_t width=(size_t)raw->bytes[at+1]|((size_t)raw->bytes[at+2]<<8);at+=3;if(at+width>raw->length||!core_io_utf8(raw->bytes+at,width)){*status=5;break;}core_io_list_add(&list,core_io_string(raw->bytes+at,width,1));at+=width;}return list;}
/* request packs Access, open mode and text bit, as qbe_files.c. */
myl_block *myl_core_span_file_access(int64_t handle,uint32_t request,const unsigned char *path,uint64_t path_len,const unsigned char *input,uint64_t input_len){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);unsigned kind=request&255,mode=(request>>8)&255;int text=(request>>16)&1;static const unsigned char letters[]={0,'r','r','w','w','m','l','k','x'};if(kind>8)core_io_fail("R_FILE");core_io_os_reason=NULL;unsigned char frame[4096];int status=0;myl_block *owner=NULL;uint64_t value=0;if(path_len>4094){status=3;core_io_os_reason=core_io_errno_reason(ENAMETOOLONG);}else{frame[0]=kind?letters[kind]:(unsigned char)mode;frame[1]=':';if(path_len)memcpy(frame+2,path,(size_t)path_len);if(frame[0]=='w'){frame[0]='c';status=core_io_resource_acquire(cap,frame,(size_t)path_len+2,&owner);if(status>0){const char *first=core_io_os_reason;frame[0]='t';core_io_os_reason=NULL;status=core_io_resource_acquire(cap,frame,(size_t)path_len+2,&owner);if(status>0&&first&&core_io_os_reason==core_io_reason_missing)core_io_os_reason=first;}}else status=core_io_resource_acquire(cap,frame,(size_t)path_len+2,&owner);if(status>0&&core_io_os_reason==core_io_reason_missing&&(mode=='w'||mode=='a'||mode=='c'||kind==3||kind==4)&&path_len&&memchr(path,'/',(size_t)path_len))core_io_os_reason=core_io_reason_no_folder;}
    if(!status){CoreIoBytes raw={0};if(kind==0){core_io_resource(owner)->text=(unsigned)text;return (request&(1u<<17))?owner:core_io_result(0,(uint64_t)(uintptr_t)owner,NULL,1);}if(kind==1||kind==2){value=(uint64_t)(uintptr_t)core_io_read_sequence(owner,CORE_IO_UNCAPPED,kind==2,&status);}else if(kind==5||kind==6){status=core_io_read_all(owner,CORE_IO_UNCAPPED,0,&raw);if(!status){if(kind==5)value=1;else value=(uint64_t)(uintptr_t)core_io_listing(&raw,&status);}}else if(kind==3||kind==4){size_t written;status=core_io_write_span_all(owner,input,(size_t)input_len,&written);}(void)core_io_complete(owner);core_io_bytes_release(&raw);core_io_drop(owner);}
    if(kind==0&&(request&(1u<<17)))core_io_file_trap("open",(const char *)path,path_len,core_io_reason(status));
    if(kind==5)return core_io_result(0,status?0:value,NULL,0);
    int pointer=kind==0||kind==1||kind==2||kind==6;if(status&&pointer&&value){core_io_drop((myl_block *)(uintptr_t)value);value=0;}
    return core_io_result(status,value,status?core_io_file_error(kind,path,path_len,status):NULL,pointer);
}
/* The block form lends the path and input octets synchronously. */
myl_block *myl_core_file_access(int64_t cap,uint32_t request,myl_block *path,myl_block *input){return myl_core_span_file_access(cap,request,block_data(path),(uint64_t)path->len,input?block_data(input):NULL,input?(uint64_t)input->len:0);}
/* The words for a failed `fsync(2)`: two sentences of its own (an input/output error says the data may not have reached the disk;
   a device with nothing to synchronize says so plainly) and the table's for every other error. */
static const char *core_io_sync_reason(int error){
    switch(error){
        case EIO:return "input/output error: the data may not have reached the disk";
        case EINVAL:case ENOTSUP:return "this kind of file cannot be synchronized";
        default:break;
    }
    const char *words=core_io_errno_reason(error);
    return words?words:"the system gave no reason";
}
/* `sync: reason` or, for a file opened by name, `sync 'path': reason`, the shape of every other file failure's text. */
static myl_block *core_io_sync_error(const CoreIoResource *resource,const char *reason){
    size_t path=resource->path?strlen(resource->path):0;
    char *message=malloc(path+strlen(reason)+16);if(!message)out_of_memory();
    size_t at=path?(size_t)sprintf(message,"sync '%s': %s",resource->path,reason):(size_t)sprintf(message,"sync: %s",reason);
    myl_block *text=core_io_string(message,at,1);free(message);return text;
}
/* `f.sync()`: everything written through this handle is on stable storage when it answers Ok. A write goes straight to the
   descriptor (nothing is buffered here), so the whole of the work is one `fsync(2)`, after the data and once. A handle opened
   only to read has written nothing, and the in-memory filesystem has no storage to wait for: both answer Ok at once. A
   filesystem a host embedded cannot be asked, and says so rather than promising. */
static myl_block *core_io_file_sync(const CoreIoResource *resource){
    CoreIoState *state=core_io_state(resource->authority);const char *reason=NULL;
    if(state->adapter.write==core_io_scoped_write_handle){
        CoreIoScopedHandle *handle=core_io_scoped_live(state->adapter.context,resource->handle);
        if(!handle)reason="the file is not open";
        else if(handle->fd>=0&&!handle->snapshot&&handle->mode!='r'){
            int done;do done=fsync(handle->fd);while(done<0&&errno==EINTR);
            if(done<0)reason=core_io_sync_reason(errno);
        }
    }else if(state->adapter.write!=core_io_memory_write)reason="the filesystem the program was given cannot synchronize a file";
    return core_io_result(reason?3:0,0,reason?core_io_sync_error(resource,reason):NULL,0);
}
myl_block *myl_core_span_file_method(myl_block *owner,uint32_t request,int64_t count,const unsigned char *input,uint64_t input_len){CORE_IO_GUARD;unsigned kind=request&255;int text=(request>>16)&1;CoreIoResource *resource=core_io_resource(owner);static const char *verbs[]={"read","read","read","write","flush","close","sync"};const char *verb=kind<=6?verbs[kind]:"use";core_io_os_reason=NULL;if(!resource->open){core_io_os_reason="the file is already closed";core_io_resource_trap(resource,verb,3);}if(kind==6)return core_io_file_sync(resource);int status=0;uint64_t value=0;int pointer=kind<=2;CoreIoBytes raw={0};if(kind==0){value=(uint64_t)(uintptr_t)core_io_read_sequence(owner,count<0?CORE_IO_UNCAPPED:(size_t)count,text,&status);}else if(kind==1){status=core_io_read_all(owner,count<0?CORE_IO_UNCAPPED:(size_t)count,1,&raw);if(!status)value=(uint64_t)(uintptr_t)core_io_sequence(&raw,text,&status);}else if(kind==2){myl_block *list=core_io_list_new(0);for(;;){CoreIoBytes line={0};status=core_io_read_all(owner,CORE_IO_UNCAPPED,1,&line);if(status||!line.length){core_io_bytes_release(&line);break;}myl_block *part=core_io_sequence(&line,text,&status);core_io_bytes_release(&line);if(status)break;core_io_list_add(&list,part);}value=(uint64_t)(uintptr_t)list;}else if(kind==3){size_t written;status=core_io_write_span_all(owner,input,(size_t)input_len,&written);value=(uint64_t)written;}else if(kind==5)status=core_io_complete(owner);else if(kind!=4)core_io_fail("R_FILE");core_io_bytes_release(&raw);if(status){if(pointer&&value)core_io_drop((myl_block *)(uintptr_t)value);core_io_resource_trap(resource,verb,status);}return core_io_result(0,value,NULL,pointer);}
myl_block *myl_core_file_method(myl_block *owner,uint32_t request,int64_t count,myl_block *input){return myl_core_span_file_method(owner,request,count,input?block_data(input):NULL,input?(uint64_t)input->len:0);}
static int core_io_allowed(const char *names,const unsigned char *name,size_t length){if(!*names)return 1;for(const char *p=names;*p;){const char *comma=strchr(p,',');size_t width=comma?(size_t)(comma-p):strlen(p);if(width==length&&!memcmp(p,name,length))return 1;if(!comma)break;p=comma+1;}return 0;}
static int core_io_environment_read(myl_block *cap,const unsigned char *name,size_t name_length,unsigned char *output,size_t capacity,size_t *written,int *present){
    CoreIoAuthority *a=core_io_authority(cap);CoreIoState *state=core_io_state(cap);*written=0;*present=0;
    if(a->family!=4)core_io_fail("R_CAPABILITY");
    if(a->scope&&!core_io_memory_blob_has(block_data(a->scope),(size_t)a->scope->len,name,name_length))core_io_fail("R_CAPABILITY");
    if(state->test){myl_block *pairs=state->pairs;if(!pairs)return 0;for(size_t at=0;at<(size_t)pairs->len;){size_t key=core_io_memory_field(block_data(pairs),(size_t)pairs->len,at),value=at+key+1,width=core_io_memory_field(block_data(pairs),(size_t)pairs->len,value);if(key==name_length&&!memcmp(block_data(pairs)+at,name,key)){if(width>capacity)return 4;if(width)memcpy(output,block_data(pairs)+value,width);*written=width;*present=1;break;}at=value+width+1;}return 0;}
    if(core_io_embedding){unsigned char *key_copy=core_io_copy(name,name_length),*copy=core_io_copy(NULL,capacity);CoreIoEnvironmentResult result=core_io_native.environment_get(core_io_native.environment_context,key_copy,name_length,copy,capacity);core_io_copy_free(key_copy);if(result.status==4)out_of_memory();if(result.status){if(result.status>5)core_io_fail("InvalidProvider");core_io_copy_free(copy);return result.status==5?4:(int)result.status;}if((result.present!=0&&result.present!=1)||(result.present&&result.length>capacity))core_io_fail("InvalidProvider");*written=result.present?result.length:0;*present=result.present;if(*written)memcpy(output,copy,*written);core_io_copy_free(copy);return 0;}
    if(!core_io_allowed(core_io_names,name,name_length))return 2;
    if(name_length>255)return 2;
    char key[256];memcpy(key,name,name_length);key[name_length]=0;const char *value=getenv(key);if(!value)return 0;
    size_t length=strlen(value);if(length>capacity)return 4;if(length)memcpy(output,value,length);*written=length;*present=1;return 0;
}
/* Whether `name` can be an environment variable's name at all: nonempty, at most 255 octets, no NUL and no `=`. Any other
   name has no variable to find, so `env.get` answers `None` for it without consulting the allow-list or an `env.only` scope. */
static int core_io_environment_name_valid(const unsigned char *name,size_t length){return length&&length<=255&&!memchr(name,0,length)&&!memchr(name,'=',length);}
/* `env.get(name)`: the value as a `str`, `NULL` (None) when the name is odd or the variable is absent, and a trap when
   the allow-list or the `env.only` scope does not hold the name. */
static myl_block *core_io_environment_text(myl_block *cap,const unsigned char *name,size_t name_length){
    unsigned char output[16384];size_t length;int present;
    if(core_io_authority(cap)->family!=4)core_io_fail("R_CAPABILITY");
    if(!core_io_environment_name_valid(name,name_length))return NULL;
    int status=core_io_environment_read(cap,name,name_length,output,sizeof output,&length,&present);
    if(status)core_io_fail("R_CAPABILITY");if(!present)return NULL;if(!core_io_utf8(output,length))core_io_fail("R_ENVIRONMENT");return core_io_string(output,length,1);
}
myl_block *myl_core_environment_text(int64_t handle,myl_block *name){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);return core_io_environment_text(cap,block_data(name),(size_t)name->len);}
/* The span form: a borrowed `str` name is read in place, with no owned copy of it. */
myl_block *myl_core_span_environment_text(int64_t handle,const unsigned char *name,uint64_t name_length){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);return core_io_environment_text(cap,name,(size_t)name_length);}

typedef struct { const unsigned char *bytes;size_t length; } CoreIoName;
static int core_io_name_order(const void *left,const void *right){const CoreIoName *a=left,*b=right;size_t width=a->length<b->length?a->length:b->length;int order=memcmp(a->bytes,b->bytes,width);return order?order:a->length<b->length?-1:a->length>b->length;}
/* Every name `env.get` could look up: nonempty and at most 255 octets. The list grows with the environment, so a
   program with thousands of variables sees all of them; duplicates are dropped after the sort. */
typedef struct { CoreIoName *items;size_t count,capacity; } CoreIoNameList;
static void core_io_name_add(CoreIoNameList *names,const unsigned char *name,size_t width){
    if(!width||width>255)return;
    if(names->count==names->capacity){size_t grown=names->capacity?names->capacity*2:128;CoreIoName *items=realloc(names->items,grown*sizeof *items);if(!items)out_of_memory();names->items=items;names->capacity=grown;}
    names->items[names->count++]=(CoreIoName){name,width};
}
myl_block *myl_core_environment_names(int64_t handle){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);
    CoreIoAuthority *a=core_io_authority(cap);CoreIoState *state=core_io_state(cap);
    if(a->family!=4)core_io_fail("InvalidCapability");
    myl_block *list=core_io_list_new(0),*blob=a->scope?a->scope:state->pairs;
    CoreIoNameList names={0};
    if(blob){
        for(size_t at=0;at<(size_t)blob->len;){
            size_t width=core_io_memory_field(block_data(blob),(size_t)blob->len,at);
            if(state->test||core_io_allowed(core_io_enumerated_names,block_data(blob)+at,width))core_io_name_add(&names,block_data(blob)+at,width);
            at+=width+1;if(!a->scope)at+=core_io_memory_field(block_data(blob),(size_t)blob->len,at)+1;
        }
    }else if(!state->test){
        if(*core_io_enumerated_names){
            const char *name=core_io_enumerated_names;
            while(*name){const char *comma=strchr(name,',');size_t width=comma?(size_t)(comma-name):strlen(name);core_io_name_add(&names,(const unsigned char *)name,width);if(!comma)break;name=comma+1;}
        }else{
            extern char **environ;
            for(char **entry=environ;entry&&*entry;++entry){char *equal=strchr(*entry,'=');size_t width=equal?(size_t)(equal-*entry):strlen(*entry);core_io_name_add(&names,(const unsigned char *)*entry,width);}
        }
    }
    if(names.count)qsort(names.items,names.count,sizeof(CoreIoName),core_io_name_order);
    for(size_t i=0;i<names.count;++i){
        if(i&&!core_io_name_order(&names.items[i-1],&names.items[i]))continue;
        if(core_io_utf8(names.items[i].bytes,names.items[i].length))core_io_list_add(&list,core_io_string(names.items[i].bytes,names.items[i].length,1));
    }
    free(names.items);
    return list;
}
void myl_core_span_stream_write(int64_t fd,const unsigned char *data,uint64_t length){myl_core_print_view(fd,data,length);stream_commit(stream_for(fd));}
void myl_core_stream_write(int64_t fd,myl_block *text){myl_core_print_str(fd,text);stream_commit(stream_for(fd));}

/* `flush(out)`: push the stream's buffered bytes to the descriptor now. */
/* `__stream_text(stream)`: the text a capturing Stream holds so far, as a new `str`. Any other Stream has no captured
   text, and asking for it fails. */
myl_block *myl_core_stream_text(int64_t fd){CORE_IO_GUARD;const unsigned char *bytes=NULL;size_t length=0;core_stream_lock();int captured=myl_core_stream_capture_view(fd,&bytes,&length);core_stream_unlock();if(!captured)core_io_fail("InvalidCapability");core_stream_lock();myl_block *text=core_io_string(bytes,length,1);core_stream_unlock();return text;}
void myl_core_stream_flush(int64_t fd){stream_flush(stream_for(fd));}
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
/* A bytes block of `capacity` octets that a read is about to fill: only the terminating NUL is written here, and the
   caller clears every octet the read did not set (a read that fills 30 of 16,396 octets clears 16,366, not 16,397 twice). */
static myl_block *core_io_unfilled(size_t capacity){
    if(capacity>64u*1024u*1024u)out_of_memory();
    myl_block *bytes=block_new(MYL_KIND_BYTES,(int64_t)capacity+1,1);bytes->len=(int64_t)capacity;block_data(bytes)[capacity]=0;return bytes;
}
myl_block *myl_core_resource_read(myl_block *owner,uint64_t capacity){CORE_IO_GUARD;
    myl_block *bytes=core_io_unfilled((size_t)capacity);size_t written;int eof;
    int status=core_io_read(owner,block_data(bytes),(size_t)capacity,&written,&eof);
    if(status)memset(block_data(bytes),0,(size_t)capacity);
    return core_io_raw_result(status,bytes,status?0:written,status?0:eof);
}
myl_block *myl_core_resource_write(myl_block *owner,myl_block *input){CORE_IO_GUARD;
    size_t written;int status=core_io_write(owner,block_data(input),(size_t)input->len,&written);
    return core_io_result(status,status?0:written,NULL,0);
}
/* The write of a borrowed `(data, length)` span (C9 bytes): the same write as myl_core_resource_write, which reads the
   octets and owns nothing, so a plain bytes or text parameter is written without a copy of it. */
myl_block *myl_core_span_resource_write(myl_block *owner,const unsigned char *data,uint64_t length){CORE_IO_GUARD;
    size_t written;int status=core_io_write(owner,(unsigned char *)data,(size_t)length,&written);
    return core_io_result(status,status?0:written,NULL,0);
}
myl_block *myl_core_environment_raw(int64_t handle,myl_block *name,uint64_t capacity){CORE_IO_GUARD;myl_block *cap=core_io_handle(handle);
    myl_block *bytes=core_io_padded((size_t)capacity);size_t length;int present;int status=core_io_environment_read(cap,block_data(name),(size_t)name->len,block_data(bytes),(size_t)capacity,&length,&present);
    if(status)memset(block_data(bytes),0,(size_t)capacity);else if(capacity>length)memset(block_data(bytes)+length,0,(size_t)capacity-length);
    return core_io_raw_result(status,bytes,status?0:length,status?0:present);
}
