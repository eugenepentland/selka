/* Capability-checked, bounded native storage. This provider implements full
 * write/file-fsync/rename/directory-fsync and crash-released directory ownership.
 * Its process-crash contract does not assert qualified power-loss durability. */
#include <sys/file.h>
#include <linux/openat2.h>
#include <sys/vfs.h>

#define CORE_DURABLE_LIMIT (64u * 1024u * 1024u)
#define CORE_DURABLE_ATOMIC 9u
#define CORE_DURABLE_LOCK 10u
#define CORE_DURABLE_SYNC 11u
#define CORE_DURABLE_READ 12u
#define CORE_DURABLE_LIST 13u
#define CORE_DURABLE_RENAME 14u
#define CORE_DURABLE_STAT 15u
#define CORE_DURABLE_LOCK_FILE 16u
#define CORE_DURABLE_TRY_LOCK_FILE 17u
#define CORE_DURABLE_CANONICAL 18u
#define CORE_DURABLE_CHMOD 19u
#define CORE_DURABLE_TOUCH 20u
#define CORE_DURABLE_SET_MODIFIED 21u
#define CORE_DURABLE_ATOMIC_MODE 22u
#define CORE_DURABLE_STAT_FOLLOW 23u
#define CORE_DURABLE_LIST_ENTRIES 24u
#define CORE_DURABLE_REPLACE 25u
#define CORE_DURABLE_REPLACE_MODE 26u
#define CORE_DURABLE_REPLACE_SYNCED 27u
#define CORE_DURABLE_REPLACE_SYNCED_MODE 28u
#define CORE_DURABLE_SYMLINK 29u
#define CORE_DURABLE_STATFS 30u
#define CORE_DURABLE_READ_AT 31u
#define CORE_DURABLE_READ_LINK 32u
/* The two newest kinds are enumerators, not macros: `runtime_abi.zig` keeps the names of at most 128 `#define`s and hashes the whole
 * runtime source past that, which would make every body edit of the runtime a change of every program's unit keys. */
enum { CORE_DURABLE_LINK = 33, CORE_DURABLE_MKDIR_MODE = 34, CORE_DURABLE_CREATE_MODE = 35 };
#define CORE_DURABLE_MODE_LIMIT 07777
#define CORE_DURABLE_NAME 4096
#ifndef SYS_openat2
#define SYS_openat2 437
#endif
/* The `openat2` call. The native fixture replaces it to run the fallback of a kernel that has none. */
#ifndef CORE_DURABLE_OPENAT2
#define CORE_DURABLE_OPENAT2(base, path, how) syscall(SYS_openat2, (base), (path), (how), sizeof *(how))
#endif
#define CORE_DURABLE_UNCERTAIN 6
/* The failure status of a file lock another holder owns; the error text names it. */
#define CORE_DURABLE_BUSY 7
/* The failure status of a waiting lock on a stand-in filesystem whose lock is held: nothing can release it while the
 * caller waits, so the call fails at once instead of never returning. */
#define CORE_DURABLE_STAND_IN_WAIT 8
/* The failure status of a listing that holds more entries than the caller's `max_entries`, or was given a negative
 * one; `core_io_os_reason` carries the text, which says what the bound is. No other granted root is tried. */
#define CORE_DURABLE_BOUND 9

/* One path resolved inside one granted root. `parent` is the directory holding the final component `leaf`; for the
 * canonical kinds (`core_durable_canonical_kind`) nothing is walked, `parent` is the root itself and `leaf` the whole
 * path relative to it, of which the first `scope` octets are the narrowing prefix when `narrowed` is set. `follow` is set for the
 * unrestricted root, which resolves symbolic links the way an ordinary process does; every granted root refuses them,
 * and so does the unrestricted root under a narrowing (`fs.dir`), except where a canonical kind follows one that stays inside.
 * `borrowed` marks a `parent` that is a root's own descriptor, which the capability keeps open and the caller must not
 * close (`core_durable_release`). */
typedef struct { int parent; bool follow, borrowed, narrowed; size_t scope; char leaf[4096]; } CoreDurablePath;
/* The octets of a request path or payload: the block a `str` or `bytes` owns, or the borrowed span of a view. */
typedef struct { const unsigned char *data; int64_t len; } CoreDurableText;
static uint64_t core_durable_serial;
/* Whether the walk of the last root `core_durable_path` tried failed because a directory on the way does not exist. */
static bool core_durable_walk_missing;

static int core_durable_sync_fd(int fd) {
    int status;
    do { status = fsync(fd); } while (status && errno == EINTR);
    return status;
}

/* The kinds that name the object at a path, following symbolic links where the root allows it, rather than the
 * directory holding it: `canonical_path` and `stat_follow_path`. */
static bool core_durable_canonical_kind(unsigned kind) {
    return kind == CORE_DURABLE_CANONICAL || kind == CORE_DURABLE_STAT_FOLLOW;
}

/* The kinds that describe the final component itself without opening it for reading: `stat_path`, `statfs_path` and
 * `read_link_path`, which resolve their path the same way (the stat rules of every kind of root). */
static bool core_durable_describes(unsigned kind) {
    return kind == CORE_DURABLE_STAT || kind == CORE_DURABLE_STATFS || kind == CORE_DURABLE_READ_LINK;
}

/* The kinds that read the bytes of one regular file: `read_regular_file` and `read_at_path`. */
static bool core_durable_reads(unsigned kind) {
    return kind == CORE_DURABLE_READ || kind == CORE_DURABLE_READ_AT;
}

/* Open the directory holding the last component of `path` the way an ordinary process does, following every symbolic
 * link on the way. Like `core_io_scoped_walk` it returns `root` itself for a single component. */
static int core_durable_walk_following(int root, const char *path, size_t length, size_t *last) {
    size_t split = length;
    while (split && path[split - 1] != '/') --split;
    *last = split;
    if (!split) return root;
    char parent[4095];
    memcpy(parent, path, split - 1);
    parent[split - 1] = 0;
    return openat(root, parent, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
}

/* The directory holding the last component of `path` below `root`, opened without following a symbolic link anywhere on
 * the way and without leaving `root`: one `openat2` for the whole prefix instead of one `openat` and one `close` for each
 * component. The descriptor is `O_PATH`, so it serves `fstatat` and nothing that reads or syncs the directory. A path of
 * one component answers `root` itself, which the caller must not close. A kernel without `openat2` gets the component by
 * component walk (`core_io_scoped_walk`), which refuses a link the same way. */
static int core_durable_walk_confined(int root, const char *path, size_t length, size_t *last) {
    size_t split = length;
    while (split && path[split - 1] != '/') --split;
    *last = split;
    if (!split) return root;
    char prefix[4095];
    memcpy(prefix, path, split - 1);
    prefix[split - 1] = 0;
    struct open_how how;
    memset(&how, 0, sizeof how);
    how.flags = O_PATH | O_DIRECTORY | O_CLOEXEC;
    how.resolve = RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS;
    long fd = CORE_DURABLE_OPENAT2(root, prefix, &how);
    if (fd >= 0 || (errno != ENOSYS && errno != EPERM)) return (int)fd;
    return core_io_scoped_walk(root, path, length, last);
}

/* Close what a resolved path holds open: its parent directory, unless that is a root's own descriptor. */
static void core_durable_release(CoreDurablePath *path) {
    if (!path->borrowed && path->parent >= 0) close(path->parent);
}

/* Whether `kind` lists a directory: the names alone, or the names with their kinds. */
static bool core_durable_lists(unsigned kind) {
    return kind == CORE_DURABLE_LIST || kind == CORE_DURABLE_LIST_ENTRIES;
}

/* Without `--restrict`, the path a walk takes as an ordinary process reads it: its `.` and empty components dropped in
 * place and a trailing slash taken off (`*directory` set), a leading `/` and every `..` kept for the system. */
static void core_durable_plain(char *path, size_t *length, int *directory) {
    const size_t width = *length;
    const size_t lead = width && path[0] == '/' ? 1 : 0;
    size_t out = lead;
    *directory = 0;
    for (size_t start = lead, i = lead; i <= width; ++i) {
        if (i != width && path[i] != '/') continue;
        const size_t size = i - start;
        const size_t from = start;
        start = i + 1;
        *directory = 1;
        if (!size || (size == 1 && path[from] == '.')) continue;
        *directory = 0;
        if (out > lead) path[out++] = '/';
        memmove(path + out, path + from, size);
        out += size;
    }
    path[out] = 0;
    *length = out;
}

/* A path that ends in `/`, `.` or `..` must name a directory: the resolved final component is one (what a final link names
 * where the root follows links, else the component itself, and a link is refused). */
static int core_durable_must_be_directory(CoreDurablePath *resolved) {
    struct stat info;
    if (!resolved->leaf[0]) return 0;
    if (fstatat(resolved->parent, resolved->leaf, &info, resolved->follow ? 0 : AT_SYMLINK_NOFOLLOW)) {
        core_durable_walk_missing = errno == ENOENT;
        return (int)core_io_scoped_from_errno();
    }
    errno = S_ISLNK(info.st_mode) ? ELOOP : !S_ISDIR(info.st_mode) ? ENOTDIR : 0;
    return errno ? (int)core_io_scoped_from_errno() : 0;
}

/* Join `path` under a `fs.dir` narrowing into `joined` (`*length` octets): the narrowed path keeps the old rule (relative,
 * no empty, `.` or `..` component), refused with the narrowing's own text. */
static int core_durable_narrow(const CoreIoAuthority *authority, char *joined, size_t *length, bool folder) {
    size_t scope = (size_t)authority->scope->len, width = *length;
    const unsigned char *prefix = block_data(authority->scope);
    /* No separator after an empty folder (the working directory) or after `/`. */
    const size_t gap = width && scope && prefix[scope - 1] != '/';
    if (!core_io_scoped_valid_path(joined, width, folder ? 'm' : 'r')) { core_io_os_reason = CORE_IO_REFUSAL_NARROWED; return 2; }
    if (scope + width + gap > 4094) { errno = ENAMETOOLONG; return (int)core_io_scoped_from_errno(); }
    memmove(joined + scope + gap, joined, width);
    memcpy(joined, prefix, scope);
    if (gap) joined[scope] = '/';
    *length = width + scope + gap;
    return 0;
}

/* Rights and the path are checked before anything is opened, and the path is read as docs/io.md, "How a path is read",
 * says. The unrestricted root takes it as an ordinary process does: the describing and listing kinds hand it whole to one
 * call, and the others walk to its final component following the links on the way, which no root follows. Under
 * `--restrict` it is resolved (`core_io_scoped_resolve`) and served by the one grant that holds it, walking the part below
 * the grant without a link; a `fs.dir` narrowing walks without a link in any run. The canonical kinds walk nothing: see
 * `CoreDurablePath`. Each path has one root, so a second call with the same `*next` fails. */
static int core_durable_path(myl_block *cap, CoreDurableText path, unsigned kind,
                             CoreDurablePath *resolved, size_t *next, bool include_readonly) {
    CoreIoAuthority *authority = core_io_authority(cap);
    CoreIoState *state = core_io_state(cap);
    resolved->parent = -1;
    resolved->follow = false;
    resolved->borrowed = false;
    resolved->narrowed = false;
    resolved->scope = 0;
    if (authority->family != 2) return 2;
    if (state->test || core_io_embedding ||
        state->adapter.acquire != core_io_scoped_acquire) return 1;
    unsigned right = core_durable_reads(kind) || core_durable_lists(kind) || core_durable_describes(kind) ||
                     core_durable_canonical_kind(kind) ? 1u : 2u;
    /* `.` alone names the working directory, so `cwd` is the canonical name of `.`. */
    if (kind == CORE_DURABLE_CANONICAL && path.len == 1 && path.data[0] == '.') path.len = 0;
    if (!(authority->rights & state->adapter.permissions & right)) {
        if (!(authority->rights & right)) core_io_os_reason = CORE_IO_REFUSAL_READ_ONLY;
        return 2;
    }
    if (path.len < 0 || path.len > 4094) { errno = ENAMETOOLONG; return (int)core_io_scoped_from_errno(); }
    if (path.len && memchr(path.data, 0, (size_t)path.len)) { core_io_os_reason = CORE_IO_REFUSAL_NUL; return 2; }
    char joined[4095];
    size_t length = (size_t)path.len;
    const size_t user = length;
    if (length) memcpy(joined, path.data, length);
    const bool folder = kind == CORE_DURABLE_LOCK || kind == CORE_DURABLE_SYNC || core_durable_lists(kind) || core_durable_describes(kind) ||
                        core_durable_canonical_kind(kind);
    /* A narrowing to the working directory itself (`fs.dir("")`, `filesystem.dir_at(fs, ".")`) is one too. */
    const bool narrowed = authority->scope != NULL;
    if (narrowed) {
        int refused = core_durable_narrow(authority, joined, &length, folder);
        if (refused) return refused;
    }
    /* A `fs.dir` handle whose folder a grant's given name reaches through a symbolic link (`myl_core_cap_dir`) reaches
       nothing; the describing, listing and canonical kinds walk as one confined `openat2`, the others component by component. */
    if (authority->rights & CORE_IO_DIR_LINKED) {
        const bool confined = core_durable_describes(kind) || core_durable_lists(kind) || core_durable_canonical_kind(kind);
        core_io_os_reason = core_io_dir_link_reason(authority->rights, user == 0, !confined);
        return 2;
    }
    joined[length] = 0;
    CoreIoScoped *scoped = state->adapter.context;
    if (*next >= scoped->count) return 2;
    *next = scoped->count;
    CoreIoScopedRoot root = scoped->roots[0];
    char rest[CORE_IO_SCOPED_PATH];
    const char *relative = joined;
    size_t width = length;
    int must = 0;
    if (narrowed) resolved->scope = (size_t)authority->scope->len;
    const bool whole = core_durable_describes(kind) || core_durable_lists(kind) || core_durable_canonical_kind(kind);
    if (!root.direct) {
        size_t index = 0;
        int status = (int)core_io_scoped_resolve(scoped, joined, length, right == 2 && !include_readonly, &index, rest, &must);
        if (status) { core_durable_walk_missing = status != 2 && errno == ENOENT; return status; }
        root = scoped->roots[index];
        relative = rest;
        width = strlen(rest);
        /* The narrowing's folder is the part of `rest` before the program's own path; none when it is the grant itself. */
        if (narrowed) resolved->scope = width > user ? width - user - (user != 0) : 0;
    } else if (!narrowed && !whole) core_durable_plain(joined, &width, &must);
    resolved->narrowed = narrowed;
    /* A narrowing to an absolute folder (`filesystem.dir_at`) in a run without `--restrict` is walked from `/`. */
    if (narrowed && root.direct && width && relative[0] == '/') {
        root.fd = core_io_slash();
        if (root.fd < 0) return (int)core_io_scoped_from_errno();
        ++relative;
        --width;
        if (resolved->scope) --resolved->scope;
    }
    /* Only the unrestricted root of an unnarrowed capability resolves links as an ordinary process does. */
    const bool follows = root.direct && !narrowed;
    bool absolute = follows && width && relative[0] == '/';
    if (absolute) { ++relative; --width; }
    if (core_durable_describes(kind) || core_durable_lists(kind)) {
        /* A stat holds the directory that contains the leaf for one `fstatat`, and a listing for one `openat` of the
         * directory itself, so neither opens a descriptor of its own where the root allows. The unrestricted root
         * hands the whole path to that one call (its links on the way are followed, an absolute path ignores the
         * descriptor); a granted root, and the unrestricted root under a narrowing, open a prefix of more than one
         * component with one confined `openat2`, and a single component not at all. */
        if (follows) {
            size_t span = width + (absolute ? 1 : 0);
            memcpy(resolved->leaf, absolute ? relative - 1 : relative, span);
            resolved->leaf[span] = 0;
            resolved->parent = root.fd;
            resolved->follow = true;
            resolved->borrowed = true;
            return 0;
        }
        size_t at = 0;
        int holder = core_durable_walk_confined(root.fd, relative, width, &at);
        if (holder < 0) {
            core_durable_walk_missing = errno == ENOENT;
            return (int)core_io_scoped_from_errno();
        }
        memcpy(resolved->leaf, relative + at, width - at);
        resolved->leaf[width - at] = 0;
        resolved->parent = holder;
        resolved->borrowed = holder == root.fd;
        int refused = must ? core_durable_must_be_directory(resolved) : 0;
        if (refused) core_durable_release(resolved);
        return refused;
    }
    int base = absolute ? open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                        : fcntl(root.fd, F_DUPFD_CLOEXEC, 0);
    if (base < 0) return (int)core_io_scoped_from_errno();
    if (core_durable_canonical_kind(kind)) {
        /* A trailing slash stays on the name, so the confined open meets it as the system's would. */
        const bool slash = must && width;
        memcpy(resolved->leaf, relative, width);
        if (slash) resolved->leaf[width] = '/';
        resolved->leaf[width + slash] = 0;
        resolved->parent = base;
        resolved->follow = root.direct;
        return 0;
    }
    size_t last = 0;
    int parent = follows ? core_durable_walk_following(base, relative, width, &last)
                         : core_io_scoped_walk(base, relative, width, &last);
    if (parent != base) close(base);
    if (parent < 0) {
        core_durable_walk_missing = errno == ENOENT;
        return (int)core_io_scoped_from_errno();
    }
    size_t leaf = width - last;
    memcpy(resolved->leaf, relative + last, leaf);
    resolved->leaf[leaf] = 0;
    resolved->parent = parent;
    resolved->follow = follows;
    /* A path that ends in `/` names the directory `mkdir_mode` makes, which does not exist yet. */
    int refused = must && kind != CORE_DURABLE_MKDIR_MODE ? core_durable_must_be_directory(resolved) : 0;
    if (refused) core_durable_release(resolved);
    return refused;
}

static int core_durable_directory(CoreDurablePath *path) {
    return openat(path->parent, path->leaf[0] ? path->leaf : ".",
                  O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
}

/* A directory lease must own every root that later reads could select. Include
 * read-only grants, and allow repeated grants only when they name one inode.
 * External directory replacement is outside this cooperative ownership model. */
static int core_durable_unique_directory(myl_block *cap, CoreDurableText path) {
    size_t next = 0;
    bool found = false;
    struct stat first;
    int status = 2;
    for (;;) {
        CoreDurablePath resolved;
        int failure = core_durable_path(cap, path, CORE_DURABLE_LOCK, &resolved, &next, true);
        if (failure) return found ? 0 : status == 2 ? failure : status;
        int fd = core_durable_directory(&resolved);
        close(resolved.parent);
        if (fd < 0) { status = (int)core_io_scoped_from_errno(); continue; }
        struct stat info;
        int failed = fstat(fd, &info), why = errno;
        close(fd);
        if (failed) return core_io_failed_with(why);
        if (found && (first.st_dev != info.st_dev || first.st_ino != info.st_ino)) return 2;
        if (!found) first = info;
        found = true;
    }
}

static int core_durable_regular(int parent, const char *name, int flags) {
    int fd = openat(parent, name, flags | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) return -1;
    struct stat info;
    int failed = fstat(fd, &info);
    if (failed || !S_ISREG(info.st_mode)) {
        int failure = failed ? errno : EACCES;
        close(fd);
        errno = failure;
        return -1;
    }
    return fd;
}

/* Close `fd`; a failure of the close is the call's failure (with its reason) when nothing failed before it. */
static int core_durable_close(int fd, int status) {
    int closed = close(fd), why = errno;
    return closed && !status ? core_io_failed_with(why) : status;
}

/* Complete partial writes and retry interruptions; zero progress is failure. */
static int core_durable_write(int fd, const unsigned char *data, size_t length) {
    size_t at = 0;
    while (at < length) {
        size_t take = length - at;
        if (take > 65536) take = 65536;
        ssize_t written = write(fd, data + at, take);
        if (written < 0 && errno == EINTR) continue;
        if (written < 0) return core_io_failed_with(errno);
        if (!written) { core_io_os_reason = "no bytes could be written"; return 3; }
        at += (size_t)written;
    }
    return 0;
}

/* The permission bits `atomic_write_file_mode` may ask for. */
static int core_durable_valid_mode(int64_t mode) {
    if (mode >= 0 && mode <= CORE_DURABLE_MODE_LIMIT) return 1;
    core_io_os_reason = "the mode must be between 0 and 0o7777";
    return 0;
}

/* What a publication forces to disk: nothing (`replace_file`), the file before the rename (`replace_file_synced`), or the
 * file before it and the directory after it (`atomic_write_file`). */
typedef enum { CORE_DURABLE_SYNC_NOTHING, CORE_DURABLE_SYNC_FILE, CORE_DURABLE_SYNC_BOTH } CoreDurableSync;

/* Publish `input` as the file `path`: written, [synchronized,] and renamed over the destination from a temporary created
 * with `mode` (the process umask applies, as it does to `open(2)`), so the destination never holds a partial file and a
 * replacement never exposes the wrong permissions. `atomic_write_file` passes 0600 and `CORE_DURABLE_SYNC_BOTH`: the file
 * is synchronized before the rename and the directory after it, so the bytes survive a power loss once the call returns.
 * `replace_file_synced` synchronizes the file and not the directory: a power loss leaves the old file or the complete new
 * one, though the rename may not have reached the disk, and no `fsync` of the directory is paid. `replace_file` is the same
 * publication without either synchronization, as Zig's `AtomicFile` is: a reader sees the old file or the new one, but a
 * power loss may leave the old one (or, on a filesystem that reorders the rename ahead of the data, a short new one). */
/* The refusal of a publication over an entry that is not a regular file, worded for what it is. */
static int core_durable_not_regular(mode_t kind) {
    core_io_os_reason = S_ISDIR(kind) ? "is a directory" : S_ISLNK(kind) ? "is a symbolic link the sandbox does not follow, or links nest too deeply"
                                                                          : "is not a regular file";
    return 2;
}

/* The refusal of a payload over the 64 MiB bound of one write. */
static int core_durable_too_large(void) {
    core_io_os_reason = "is over the 64 MiB bound of one write";
    return 3;
}

static int core_durable_publish(CoreDurablePath *path, CoreDurableText input, mode_t mode, CoreDurableSync sync) {
    if (input.len < 0 || (uint64_t)input.len > CORE_DURABLE_LIMIT) return core_durable_too_large();
    struct stat existing;
    if (fstatat(path->parent, path->leaf, &existing, AT_SYMLINK_NOFOLLOW) == 0) {
        if (!S_ISREG(existing.st_mode)) return core_durable_not_regular(existing.st_mode);
    } else if (errno != ENOENT) return (int)core_io_scoped_from_errno();
    char temporary[192];
    int fd = -1;
    for (unsigned attempt = 0; attempt < 1024; ++attempt) {
        int size = snprintf(temporary, sizeof temporary, ".myl-durable-%.128s-%lu-%llu",
                            path->leaf, (unsigned long)getpid(),
                            (unsigned long long)++core_durable_serial);
        if (size < 0 || (size_t)size >= sizeof temporary) return 3;
        fd = openat(path->parent, temporary,
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode);
        if (fd >= 0 || errno != EEXIST) break;
    }
    if (fd < 0) return (int)core_io_scoped_from_errno();
    int status = core_durable_write(fd, input.data, (size_t)input.len);
    if (!status && sync != CORE_DURABLE_SYNC_NOTHING && core_durable_sync_fd(fd)) status = core_io_failed_with(errno);
    status = core_durable_close(fd, status);
    if (!status && renameat(path->parent, temporary, path->parent, path->leaf))
        status = (int)core_io_scoped_from_errno();
    if (status) { unlinkat(path->parent, temporary, 0); return status; }
    if (sync == CORE_DURABLE_SYNC_BOTH && core_durable_sync_fd(path->parent)) return CORE_DURABLE_UNCERTAIN;
    return 0;
}

/* The reason of a `max_bytes` no read can serve, or 0 for one that is in bounds. */
static int core_durable_bad_limit(int64_t limit) {
    if (limit < 0) core_io_os_reason = "max_bytes must not be negative";
    else if ((uint64_t)limit > CORE_DURABLE_LIMIT) core_io_os_reason = "max_bytes is over the 64 MiB bound of one read";
    else return 0;
    return 3;
}

/* The refusal of a file larger than the `max_bytes` asked for. */
static int core_durable_larger(void) {
    core_io_os_reason = "is larger than max_bytes";
    return 3;
}

static int core_durable_read(CoreDurablePath *path, int64_t limit, myl_block **out) {
    if (core_durable_bad_limit(limit)) return 3;
    int fd = core_durable_regular(path->parent, path->leaf, O_RDONLY);
    if (fd < 0) return (int)core_io_scoped_from_errno();
    struct stat info;
    const int measured = fstat(fd, &info), why = errno;
    if (measured || info.st_size < 0 || (uint64_t)info.st_size > (uint64_t)limit) {
        close(fd);
        return measured ? core_io_failed_with(why) : core_durable_larger();
    }
    CoreIoBytes bytes = {0};
    unsigned char buffer[16384];
    int status = 0;
    while (bytes.length <= (size_t)limit) {
        size_t take = (size_t)limit - bytes.length + 1;
        if (take > sizeof buffer) take = sizeof buffer;
        ssize_t length = read(fd, buffer, take);
        if (length < 0 && errno == EINTR) continue;
        if (length < 0) { status = core_io_failed_with(errno); break; }
        if (!length) break;
        if ((size_t)length > (size_t)limit - bytes.length) { status = core_durable_larger(); break; }
        core_io_append(&bytes, buffer, (size_t)length);
    }
    status = core_durable_close(fd, status);
    if (!status) *out = core_io_string(bytes.bytes, bytes.length, 0);
    free(bytes.bytes);
    return status;
}

/* The offset of a `read_at_path` call, which the typed layer packs as eight little-endian octets (the call has two integers
 * and the runtime entry one integer and one `bytes` operand beside the path), and the count it asks for. A refusal sets the
 * text the caller reads: an offset over the largest `int`, a negative count, or a count over the same bound a whole-file
 * read has. */
static int core_durable_window(CoreDurableText window, int64_t count, uint64_t *offset) {
    uint64_t value = 0;
    if (window.len != 8) { core_io_os_reason = "the offset is damaged"; return 3; }
    for (unsigned i = 0; i < 8; ++i) value |= (uint64_t)window.data[i] << (8 * i);
    if (value > (uint64_t)INT64_MAX) { core_io_os_reason = "the offset must not be negative"; return 3; }
    if (count < 0) { core_io_os_reason = "max_bytes must not be negative"; return 3; }
    if ((uint64_t)count > CORE_DURABLE_LIMIT) { core_io_os_reason = "max_bytes is over the 64 MiB bound of one read"; return 3; }
    *offset = value;
    return 0;
}

/* `read_at_path`: up to `count` octets of the regular file, from byte `offset`: fewer when the file ends first, none at or
 * past the end. The file is opened as `read_regular_file` opens it (not a link, not a device) and read with `pread`, so a
 * file that only grows is read from where the last read stopped without reading what came before. */
static int core_durable_read_at(CoreDurablePath *path, CoreDurableText window, int64_t count, myl_block **out) {
    uint64_t offset;
    int status = core_durable_window(window, count, &offset);
    if (status) return status;
    int fd = core_durable_regular(path->parent, path->leaf, O_RDONLY);
    if (fd < 0) return (int)core_io_scoped_from_errno();
    CoreIoBytes bytes = {0};
    unsigned char buffer[16384];
    while (bytes.length < (size_t)count) {
        size_t take = (size_t)count - bytes.length;
        if (take > sizeof buffer) take = sizeof buffer;
        if (offset > (uint64_t)INT64_MAX - bytes.length) break;
        ssize_t length = pread(fd, buffer, take, (off_t)(offset + bytes.length));
        if (length < 0 && errno == EINTR) continue;
        if (length < 0) { status = (int)core_io_scoped_from_errno(); break; }
        if (!length) break;
        core_io_append(&bytes, buffer, (size_t)length);
    }
    status = core_durable_close(fd, status);
    if (!status) *out = core_io_string(bytes.bytes, bytes.length, 0);
    free(bytes.bytes);
    return status;
}

/* The refusal of a listing whose `max_entries` is negative, or which holds more than `limit` entries. The text names the
 * bound, never the grants. */
static int core_durable_list_bound(int64_t limit, bool negative) {
    static char reason[96];
    if (negative) snprintf(reason, sizeof reason, "max_entries must not be negative");
    else snprintf(reason, sizeof reason, "has more than %lld entries (the max_entries bound)", (long long)limit);
    core_io_os_reason = reason;
    return CORE_DURABLE_BOUND;
}

/* A complete immediate listing, including hidden entries: the names as a `str[]`, or with `kinds` the names and what
 * each is as one packed `bytes` (for each entry a kind octet, a little-endian u16 name length and the name; the kind is
 * the directory record's own). The caller's bound is the only cap: a directory of any size lists whole, or is refused
 * with the bound named; never follow directory symlinks, and never bless a partial readdir snapshot. */
static int core_durable_listing(CoreDurablePath *path, int64_t limit, bool kinds, myl_block **out) {
    if (limit < 0) return core_durable_list_bound(limit, true);
    int fd = core_durable_directory(path);
    if (fd < 0) {
        const int refused = errno;
        int status = (int)core_io_scoped_from_errno();
        /* ENOTDIR names either the path itself or one of its parents: say which, as `listdir` does. */
        struct stat leaf;
        if (refused == ENOTDIR && !fstatat(path->parent, path->leaf, &leaf, AT_SYMLINK_NOFOLLOW) && !S_ISDIR(leaf.st_mode)) core_io_os_reason = "is not a directory";
        return status;
    }
    DIR *directory = fdopendir(fd);
    if (!directory) { int status = (int)core_io_scoped_from_errno(); close(fd); return status; }
    myl_block *list = kinds ? NULL : core_io_list_new(0);
    CoreIoBytes packed = {0};
    int64_t count = 0;
    int status = 0;
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(directory);
        if (!entry) { if (errno) status = (int)core_io_scoped_from_errno(); break; }
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        if (count >= limit) { status = core_durable_list_bound(limit, false); break; }
        size_t length = strlen(entry->d_name);
        if (!length || length > 255 || !core_io_utf8((unsigned char *)entry->d_name, length)) {
            status = 5;
            break;
        }
        if (kinds) {
            unsigned char head[3] = {core_io_scoped_entry_kind(directory, entry), (unsigned char)length, 0};
            core_io_append(&packed, head, sizeof head);
            core_io_append(&packed, (unsigned char *)entry->d_name, length);
        } else core_io_list_add(&list, core_io_string((unsigned char *)entry->d_name, length, 1));
        ++count;
    }
    if (closedir(directory) && !status) status = core_io_failed_with(errno);
    if (status && list) core_io_drop(list);
    else if (!status) *out = kinds ? core_io_string(packed.bytes, packed.length, 0) : list;
    core_io_bytes_release(&packed);
    return status;
}

/* Register before returning the File so every ordinary exit or reference-count
 * drop closes the descriptor. SIGKILL also releases the kernel flock.
 * A directory lease locks the directory inode itself (no removable lockfile can split ownership) and
 * fails at once when it is held. A file lock opens (creating, mode 0600) and locks a regular file:
 * `try` fails at once with BUSY, `wait` blocks until the holder lets go. */
typedef enum { CORE_DURABLE_LEASE_DIRECTORY, CORE_DURABLE_LEASE_TRY, CORE_DURABLE_LEASE_WAIT } CoreDurableLease;
static int core_durable_lock(myl_block *cap, CoreDurablePath *path, CoreDurableLease style, myl_block **out) {
    CoreIoAuthority *authority = core_io_authority(cap);
    CoreIoState *state = core_io_state(cap);
    CoreIoScoped *scoped = state->adapter.context;
    size_t slot = core_io_scoped_free_slot(scoped);
    if (slot == SIZE_MAX || core_io_family_open[0] >= 1024) return 4;
    myl_block *block = block_new(7, sizeof(CoreIoResource), 1);
    block->len = 1;
    block->reserved = (int64_t)(intptr_t)core_io_resource_layout;
    memset(block_data(block), 0, sizeof(CoreIoResource));
    bool file = style != CORE_DURABLE_LEASE_DIRECTORY;
    int fd = file ? openat(path->parent, path->leaf, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600)
                  : core_durable_directory(path);
    int status = fd < 0 ? (int)core_io_scoped_from_errno() : 0;
    struct stat info;
    if (!status && file && fstat(fd, &info)) status = (int)core_io_scoped_from_errno();
    if (!status && file && !S_ISREG(info.st_mode)) {
        core_io_os_reason = S_ISDIR(info.st_mode) ? "is a directory" : "is not a regular file";
        status = 2;
    }
    if (!status && style == CORE_DURABLE_LEASE_WAIT) core_flush_before_wait();
    while (!status && flock(fd, style == CORE_DURABLE_LEASE_WAIT ? LOCK_EX : LOCK_EX | LOCK_NB)) {
        if (errno == EINTR) continue;
        status = errno == EWOULDBLOCK ? CORE_DURABLE_BUSY : 3;
    }
    if (status) {
        if (fd >= 0) close(fd);
        block->reserved = 0;
        block_free(block);
        return status;
    }
    scoped->handles[slot] = (CoreIoScopedHandle){fd, NULL, 0, 0, 'L'};
    CoreIoResource *resource = (CoreIoResource *)block_data(block);
    *resource = (CoreIoResource){cap, slot, 2, authority->rights & state->adapter.permissions,
                               1, 0, core_io_tail, NULL, block};
    if (core_io_tail) core_io_tail->next = resource;
    core_io_tail = resource;
    ++core_io_open_count;
    ++core_io_family_open[0];
    *out = block;
    return 0;
}

/* The little-endian packing `stat_path` answers: size, modification time in nanoseconds, inode, kind (0 other,
 * 1 regular file, 2 directory, 3 symbolic link), permission bits (`st_mode & 07777`), status-change time in
 * nanoseconds, the device (`st_dev`, as `stat(2)` returns it), the owning user (`st_uid`), the owning group (`st_gid`)
 * and the number of hard links (`st_nlink`), ten 64-bit words. */
#define CORE_DURABLE_STAT_WORDS 10u
#define CORE_DURABLE_STAT_BYTES (CORE_DURABLE_STAT_WORDS * 8u)
static void core_durable_pack_stat(const struct stat *info, unsigned char packed[CORE_DURABLE_STAT_BYTES]) {
    uint64_t words[CORE_DURABLE_STAT_WORDS] = {
        (uint64_t)info->st_size,
        (uint64_t)((int64_t)info->st_mtim.tv_sec * 1000000000 + (int64_t)info->st_mtim.tv_nsec),
        (uint64_t)info->st_ino,
        S_ISREG(info->st_mode) ? 1u : S_ISDIR(info->st_mode) ? 2u : S_ISLNK(info->st_mode) ? 3u : 0u,
        (uint64_t)(info->st_mode & 07777),
        (uint64_t)((int64_t)info->st_ctim.tv_sec * 1000000000 + (int64_t)info->st_ctim.tv_nsec),
        (uint64_t)info->st_dev,
        (uint64_t)info->st_uid,
        (uint64_t)info->st_gid,
        (uint64_t)info->st_nlink,
    };
    memcpy(packed, words, CORE_DURABLE_STAT_BYTES);
}

/* The little-endian packing `statfs_path` answers: the size of the filesystem, the bytes free on it and the bytes an
 * ordinary process may still use, in bytes (blocks times the fragment size), three 64-bit words. */
#define CORE_DURABLE_SPACE_WORDS 3u
#define CORE_DURABLE_SPACE_BYTES (CORE_DURABLE_SPACE_WORDS * 8u)
static void core_durable_pack_space(const struct statfs *info, unsigned char packed[CORE_DURABLE_SPACE_BYTES]) {
    const uint64_t unit = info->f_frsize ? (uint64_t)info->f_frsize : (uint64_t)info->f_bsize;
    uint64_t words[CORE_DURABLE_SPACE_WORDS] = {
        (uint64_t)info->f_blocks * unit, (uint64_t)info->f_bfree * unit, (uint64_t)info->f_bavail * unit,
    };
    memcpy(packed, words, CORE_DURABLE_SPACE_BYTES);
}

/* The kernel's own name for the object a descriptor refers to (`/proc/self/fd`), which is its symbolic-link-free
 * absolute path. An object with no link left (the kernel appends ` (deleted)` to the name of one) or outside the
 * process's root has no name. `name` holds `CORE_DURABLE_NAME + 1` octets. */
static int core_durable_fd_name(int fd, char *name) {
    static const char removed[] = " (deleted)";
    char link[48];
    snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
    ssize_t length = readlink(link, name, CORE_DURABLE_NAME);
    struct stat info;
    bool gone = length > (ssize_t)sizeof removed && !memcmp(name + length - (ssize_t)(sizeof removed - 1), removed, sizeof removed - 1) &&
                !fstat(fd, &info) && info.st_nlink == 0;
    if (length <= 0 || length >= CORE_DURABLE_NAME || name[0] != '/' || gone) {
        errno = length >= CORE_DURABLE_NAME ? ENAMETOOLONG : ENOENT;
        return -1;
    }
    name[length] = 0;
    return 0;
}

/* An `O_PATH` descriptor for `path` that cannot leave the directory `base`: a symbolic link is followed only while
 * it stays inside, so an absolute link, or one that climbs out, fails with `EXDEV`. A kernel without `openat2` gets
 * the stricter answer every other granted-root operation gives, no link followed at all. */
static int core_durable_open_beneath(int base, const char *path) {
    struct open_how how;
    memset(&how, 0, sizeof how);
    how.flags = O_PATH | O_CLOEXEC;
    how.resolve = RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS;
    long fd = CORE_DURABLE_OPENAT2(base, path, &how);
    if (fd >= 0 || (errno != ENOSYS && errno != EPERM)) return (int)fd;
    size_t last = 0;
    int parent = core_io_scoped_walk(base, path, strlen(path), &last);
    if (parent < 0) return -1;
    int leaf = openat(parent, path[last] ? path + last : ".", O_PATH | O_NOFOLLOW | O_CLOEXEC);
    int cause = errno;
    if (parent != base) close(parent);
    struct stat info;
    if (leaf >= 0 && (fstat(leaf, &info) || S_ISLNK(info.st_mode))) {
        cause = ELOOP;
        close(leaf);
        leaf = -1;
    }
    errno = cause;
    return leaf;
}

/* Open what a canonical-kind path names, following symbolic links, and name it. The unrestricted root and a grant
 * answer an absolute path, so the name means the same file in a plain and a restricted run; a grant follows a link only
 * while it stays inside the granted directory. A `fs.dir` narrowing answers the path relative to its folder, so a program
 * learns nothing of the host's layout beyond it. A result outside the directory is denied. `*fd` is an `O_PATH` descriptor the caller closes; `name`
 * (`CORE_DURABLE_NAME + 1` octets) and `name_length` are optional. Sets `core_durable_walk_missing` when nothing is
 * at the path. */
static int core_durable_target(const CoreDurablePath *path, int *fd, char *name, size_t *name_length) {
    bool confined = !path->follow || path->narrowed;
    const char *target = path->leaf[0] ? path->leaf : ".";
    *fd = confined ? core_durable_open_beneath(path->parent, target) : openat(path->parent, target, O_PATH | O_CLOEXEC);
    if (*fd < 0) {
        core_durable_walk_missing = errno == ENOENT;
        if (errno == EXDEV) { core_io_os_reason = "resolves outside the granted directory"; return 2; }
        return (int)core_io_scoped_from_errno();
    }
    /* The unrestricted root has nothing to confine, and `stat_follow` asks for no name: the object is what `stat(2)` finds,
     * a pipe or a socket behind `/dev/stdin` or `/proc/self/fd/N` too, which the kernel names with no path. */
    if (!confined && !name) return 0;
    char full[CORE_DURABLE_NAME + 1];
    char granted[CORE_DURABLE_NAME + 1];
    int status = 0;
    if (core_durable_fd_name(*fd, full)) status = (int)core_io_scoped_from_errno();
    size_t length = status ? 0 : strlen(full), skip = 0;
    if (!status && confined) {
        int root = path->parent;
        if (path->narrowed && path->scope) {
            char prefix[4095];
            memcpy(prefix, path->leaf, path->scope);
            prefix[path->scope] = 0;
            root = core_durable_open_beneath(path->parent, prefix);
        }
        int named = root < 0 ? -1 : core_durable_fd_name(root, granted);
        if (root < 0 || named) status = (int)core_io_scoped_from_errno();
        if (root >= 0 && root != path->parent) close(root);
        if (!status) {
            size_t width = strlen(granted);
            bool inside = width == 1 || (length >= width && !strncmp(full, granted, width) && (full[width] == 0 || full[width] == '/'));
            /* A narrowing answers below its folder; a grant answers the absolute name, as a plain run does. */
            if (inside && path->narrowed) skip = width == 1 ? 1 : width + (full[width] == '/');
            if (!inside) { core_io_os_reason = "resolves outside the granted directory"; status = 2; }
        }
    }
    if (status) { close(*fd); *fd = -1; return status; }
    if (name) memmove(name, full + skip, length - skip + 1);
    if (name_length) *name_length = length - skip;
    return 0;
}

/* `canonical_path`: the name `core_durable_target` finds, as a `str`. */
static int core_durable_canonical(const CoreDurablePath *path, myl_block **out) {
    int fd;
    char name[CORE_DURABLE_NAME + 1];
    size_t length = 0;
    int status = core_durable_target(path, &fd, name, &length);
    if (status) return status;
    close(fd);
    if (!core_io_utf8((unsigned char *)name, length)) return 5;
    *out = core_io_string(name, length, 1);
    return 0;
}

/* The `struct stat` of one resolved path: the final component itself, or what it names when `follow` is set. Sets
 * `core_durable_walk_missing` when nothing is there. */
static int core_durable_stat_one(CoreDurablePath *resolved, bool follow, struct stat *info) {
    core_durable_walk_missing = false;
    if (follow) {
        int fd = -1;
        int status = core_durable_target(resolved, &fd, NULL, NULL);
        if (status) return status;
        int failed = fstat(fd, info);
        close(fd);
        return failed ? 3 : 0;
    }
    if (!fstatat(resolved->parent, resolved->leaf[0] ? resolved->leaf : ".", info, AT_SYMLINK_NOFOLLOW)) return 0;
    core_durable_walk_missing = errno == ENOENT;
    return (int)core_io_scoped_from_errno();
}

/* The `struct statfs` of the filesystem that holds one resolved path: an `O_PATH` descriptor of the final component
 * itself (a symbolic link is described by the filesystem that holds the link, as `stat` describes the link). Sets
 * `core_durable_walk_missing` when nothing is there. */
static int core_durable_statfs_one(CoreDurablePath *resolved, struct statfs *info) {
    core_durable_walk_missing = false;
    int fd = openat(resolved->parent, resolved->leaf[0] ? resolved->leaf : ".", O_PATH | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) {
        core_durable_walk_missing = errno == ENOENT;
        return (int)core_io_scoped_from_errno();
    }
    int failed = fstatfs(fd, info);
    int cause = errno;
    close(fd);
    if (!failed) return 0;
    errno = cause;
    return (int)core_io_scoped_from_errno();
}

/* The packed octets of the first granted root that holds `path` (80 for `stat_path`, 24 for `statfs_path`), or an empty
 * `bytes` when no root holds it (a missing leaf, or a missing directory on the way). Every other refusal is a failure.
 * `CORE_DURABLE_STAT_FOLLOW` stats what a final symbolic link names, as `stat_follow_path` does. */
static int core_durable_stat(myl_block *cap, CoreDurableText path, unsigned kind, myl_block **out) {
    size_t next = 0;
    bool missing = false;
    int status = 2;
    const bool follow = kind == CORE_DURABLE_STAT_FOLLOW;
    for (;;) {
        CoreDurablePath resolved;
        core_durable_walk_missing = false;
        int failure = core_durable_path(cap, path, kind, &resolved, &next, false);
        if (failure) {
            if (core_durable_walk_missing) missing = true;
            else if (!missing) status = failure;
            break;
        }
        struct stat info;
        struct statfs space;
        int refusal = kind == CORE_DURABLE_STATFS ? core_durable_statfs_one(&resolved, &space) : core_durable_stat_one(&resolved, follow, &info);
        bool absent = core_durable_walk_missing;
        core_durable_release(&resolved);
        if (!refusal && kind == CORE_DURABLE_STATFS) {
            unsigned char packed[CORE_DURABLE_SPACE_BYTES];
            core_durable_pack_space(&space, packed);
            *out = core_io_string(packed, sizeof packed, 0);
            return 0;
        }
        if (!refusal) {
            unsigned char packed[CORE_DURABLE_STAT_BYTES];
            core_durable_pack_stat(&info, packed);
            *out = core_io_string(packed, sizeof packed, 0);
            return 0;
        }
        if (absent) { missing = true; continue; }
        return refusal;
    }
    if (!missing) return status;
    *out = core_io_string("", 0, 0);
    return 0;
}

/* The reason `read_link_path` gives for an entry that is not a symbolic link (`EINVAL` from `readlinkat`, and the root). */
#define CORE_DURABLE_NOT_A_LINK "is not a symbolic link"

/* `read_link_path` of one resolved path: `readlinkat` of the final component, which is never followed, as `stat_one`
 * describes it. The text is a `str`, so a target that is not UTF-8 is status 5. Sets `core_durable_walk_missing` when
 * nothing is there. */
static int core_durable_link_text(CoreDurablePath *resolved, myl_block **out) {
    core_durable_walk_missing = false;
    char text[CORE_DURABLE_NAME + 1];
    ssize_t length = readlinkat(resolved->parent, resolved->leaf[0] ? resolved->leaf : ".", text, CORE_DURABLE_NAME);
    if (length < 0) {
        const int cause = errno;
        core_durable_walk_missing = cause == ENOENT;
        int status = (int)core_io_scoped_from_errno();
        if (cause == EINVAL) { core_io_os_reason = CORE_DURABLE_NOT_A_LINK; status = 3; }
        return status;
    }
    if (!core_io_utf8((unsigned char *)text, (size_t)length)) return 5;
    *out = core_io_string(text, (size_t)length, 1);
    return 0;
}

/* `read_link_path`: the text of the link in the first granted root that holds `path`, found as `core_durable_stat` finds it
 * (the same roots, the same refusal of a link on the way, the same final component that is not followed). A path with
 * nothing at it in any root fails like every other failed lookup, with the reason of a missing path. */
static int core_durable_read_link(myl_block *cap, CoreDurableText path, myl_block **out) {
    size_t next = 0;
    bool missing = false;
    int status = 2;
    for (;;) {
        CoreDurablePath resolved;
        core_durable_walk_missing = false;
        int failure = core_durable_path(cap, path, CORE_DURABLE_READ_LINK, &resolved, &next, false);
        if (failure) {
            if (core_durable_walk_missing) missing = true;
            else if (!missing) status = failure;
            break;
        }
        int refusal = core_durable_link_text(&resolved, out);
        const bool absent = core_durable_walk_missing;
        core_durable_release(&resolved);
        if (!refusal) return 0;
        if (absent) { missing = true; continue; }
        return refusal;
    }
    if (!missing) return status;
    core_io_os_reason = core_io_reason_missing;
    return 3;
}

/* `chmod_path`: `fchmodat` of the final component, which is not followed; a symbolic link has no mode to change. */
static int core_durable_chmod(CoreDurablePath *path, int64_t mode) {
    if (!core_durable_valid_mode(mode)) return 3;
    if (!fchmodat(path->parent, path->leaf, (mode_t)mode, AT_SYMLINK_NOFOLLOW)) return 0;
    int cause = errno;
    int status = (int)core_io_scoped_from_errno();
    if (cause == EOPNOTSUPP) { core_io_os_reason = "a symbolic link has no permission bits of its own"; status = 3; }
    return status;
}

/* `symlink_path`: `symlinkat` of the target text at the final component of a path whose parent was walked without following a
 * link, so the grant that governs every other write governs this one. The target is stored as written: a relative one, an
 * absolute one or one that names nothing is only text until something follows it, and every call that follows a link
 * (`canonical_path`, `stat_follow_path`) is confined to the grant and refuses a target that leaves it. */
static int core_durable_symlink(CoreDurablePath *path, CoreDurableText target) {
    if (!path->leaf[0]) { core_io_os_reason = "is a directory"; return 2; }
    if (target.len <= 0 || target.len >= (int64_t)sizeof path->leaf || memchr(target.data, 0, (size_t)target.len)) {
        core_io_os_reason = "the link target must be text of 1 to 4094 octets with no NUL";
        return 3;
    }
    char text[sizeof path->leaf];
    memcpy(text, target.data, (size_t)target.len);
    text[target.len] = 0;
    if (!symlinkat(text, path->parent, path->leaf)) return 0;
    return (int)core_io_scoped_from_errno();
}

/* `touch_path` and `set_modified_path`: `utimensat` of the final component, which is not followed. `touch` sets both
 * times to now; the other sets the modification time to `nanoseconds` since the epoch and leaves the access time. */
static int core_durable_times(CoreDurablePath *path, bool now, int64_t nanoseconds) {
    struct timespec times[2];
    memset(times, 0, sizeof times);
    if (now) {
        times[0].tv_nsec = UTIME_NOW;
        times[1].tv_nsec = UTIME_NOW;
    } else {
        int64_t seconds = nanoseconds / 1000000000, rest = nanoseconds % 1000000000;
        if (rest < 0) { rest += 1000000000; --seconds; }
        times[0].tv_nsec = UTIME_OMIT;
        times[1].tv_sec = (time_t)seconds;
        times[1].tv_nsec = (long)rest;
    }
    if (!utimensat(path->parent, path->leaf, times, AT_SYMLINK_NOFOLLOW)) return 0;
    return (int)core_io_scoped_from_errno();
}

/* `renameat` of `from` onto `to` inside the first granted root that holds both; the destination is replaced
 * atomically when it is a file, and a rename across filesystems fails (`EXDEV`) rather than copying. */
/* `rename_path`: each end is resolved on its own (under `--restrict`, by the write grant that holds it), and one `renameat`
 * moves the entry; two grants on different filesystems answer `EXDEV`. */
static int core_durable_rename(myl_block *cap, CoreDurableText from, CoreDurableText to) {
    size_t next = 0, after = 0;
    CoreDurablePath source, target;
    int failure = core_durable_path(cap, from, CORE_DURABLE_RENAME, &source, &next, false);
    if (failure) return failure;
    failure = core_durable_path(cap, to, CORE_DURABLE_RENAME, &target, &after, false);
    if (failure) { core_durable_release(&source); return failure; }
    int renamed = renameat(source.parent, source.leaf, target.parent, target.leaf);
    int cause = errno;
    core_durable_release(&source);
    core_durable_release(&target);
    if (!renamed) return 0;
    errno = cause;
    int status = (int)core_io_scoped_from_errno();
    if (cause == EXDEV) core_io_os_reason = "the paths are on different filesystems";
    return status;
}

/* `link_path`: `linkat` of the existing file `target` as the new name `name`, a second name for one file. Each end is resolved on its
 * own as a rename's two are (under `--restrict` by the write grant that holds it, so a file that is only readable is not linked
 * into a place a program can write, and neither end leaves a grant or a narrowed folder), and the parent of each was walked
 * without following a link where the root allows none. The source is looked at without following it: only a regular file is
 * linked, so a folder, a symbolic link and the rest are refused in the words of a refused publication, and no call links through
 * a link. The link is made with no flag, which names the final component itself; a source swapped for a link after the check
 * is linked as the link it is, a name inside the same grant that no call follows. */
static int core_durable_link(myl_block *cap, CoreDurableText target, CoreDurableText name) {
    size_t next = 0, after = 0;
    CoreDurablePath source, created;
    int failure = core_durable_path(cap, target, CORE_DURABLE_LINK, &source, &next, false);
    if (failure) return failure;
    failure = core_durable_path(cap, name, CORE_DURABLE_LINK, &created, &after, false);
    if (failure) { core_durable_release(&source); return failure; }
    struct stat info;
    int status = 0;
    if (!source.leaf[0]) status = core_durable_not_regular(S_IFDIR);
    else if (fstatat(source.parent, source.leaf, &info, AT_SYMLINK_NOFOLLOW)) status = (int)core_io_scoped_from_errno();
    else if (!S_ISREG(info.st_mode)) status = core_durable_not_regular(info.st_mode);
    else if (!created.leaf[0]) { errno = EEXIST; status = (int)core_io_scoped_from_errno(); }
    else if (linkat(source.parent, source.leaf, created.parent, created.leaf, 0)) status = (int)core_io_scoped_from_errno();
    core_durable_release(&source);
    core_durable_release(&created);
    return status;
}

/* `mkdir_mode`: `mkdirat` of the final component with the permission bits `mode`, which the process umask narrows as it does
 * `open(2)`'s, so the directory never exists with the default mode. The system keeps the nine permission bits and the sticky bit;
 * the set-user and set-group bits are `chmod`'s. A path that is only a directory already there (`.`, `d/..`) already exists. */
static int core_durable_mkdir(CoreDurablePath *path, int64_t mode) {
    if (!core_durable_valid_mode(mode)) return 3;
    if (!path->leaf[0]) { errno = EEXIST; return (int)core_io_scoped_from_errno(); }
    if (!mkdirat(path->parent, path->leaf, (mode_t)mode)) return 0;
    return (int)core_io_scoped_from_errno();
}

/* Register the `File` that `create_mode` opened: provider handle `slot`, with the rights of `fs.open(path, "wb")`'s. */
static myl_block *core_durable_file(myl_block *cap, size_t slot) {
    CoreIoAuthority *authority = core_io_authority(cap);
    CoreIoState *state = core_io_state(cap);
    myl_block *block = block_new(7, sizeof(CoreIoResource), 1);
    block->len = 1;
    block->reserved = (int64_t)(intptr_t)core_io_resource_layout;
    memset(block_data(block), 0, sizeof(CoreIoResource));
    CoreIoResource *resource = (CoreIoResource *)block_data(block);
    *resource = (CoreIoResource){cap, slot, 2, authority->rights & state->adapter.permissions & ~8u, 1, 0, core_io_tail, NULL, block, NULL};
    if (core_io_tail) core_io_tail->next = resource;
    core_io_tail = resource;
    ++core_io_open_count;
    ++core_io_family_open[0];
    return block;
}

/* `create_mode`: `open(path, "wb")` with the permission bits of a new file chosen. A missing file is made by the one `openat`
 * that opens it (`O_CREAT | O_EXCL` with `mode`, which the umask narrows as it does `creat(2)`'s), so it never exists with
 * the default mode; a file already there is opened as `open(path, "wb")` opens it, truncated, its mode kept. The unrestricted
 * root follows a final link to an existing file and writes a pipe or a device, as an ordinary process does; a grant and a
 * narrowing refuse a link and serve a regular file only, opening without waiting so a FIFO cannot stall the program. */
static int core_durable_create(myl_block *cap, CoreDurablePath *path, int64_t mode, myl_block **out) {
    if (!core_durable_valid_mode(mode)) return 3;
    if (!path->leaf[0]) { errno = EISDIR; return (int)core_io_scoped_from_errno(); }
    CoreIoScoped *scoped = core_io_state(cap)->adapter.context;
    size_t slot = core_io_scoped_free_slot(scoped);
    if (slot == SIZE_MAX || core_io_family_open[0] >= 1024) return 4;
    const int waiting = path->follow ? 0 : O_NONBLOCK;
    int fd = openat(path->parent, path->leaf, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | waiting, (mode_t)mode);
    const bool created = fd >= 0;
    if (!created && errno == EEXIST)
        fd = openat(path->parent, path->leaf, O_WRONLY | O_CLOEXEC | waiting | (path->follow ? 0 : O_NOFOLLOW));
    if (fd < 0) return (int)core_io_scoped_from_errno();
    struct stat info;
    int status = fstat(fd, &info) ? (int)core_io_scoped_from_errno() : 0;
    if (!status && (S_ISDIR(info.st_mode) || (!path->follow && !S_ISREG(info.st_mode)))) {
        core_io_os_reason = S_ISDIR(info.st_mode) ? "is a directory" : "is not a regular file";
        status = 2;
    }
    if (!status && waiting && fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)) status = (int)core_io_scoped_from_errno();
    /* Only a regular file has contents to truncate; a FIFO or device has none. */
    if (!status && !created && S_ISREG(info.st_mode) && ftruncate(fd, 0)) status = (int)core_io_scoped_from_errno();
    if (status) {
        close(fd);
        return status;
    }
    scoped->handles[slot] = (CoreIoScopedHandle){fd, NULL, 0, 0, 't'};
    *out = core_durable_file(cap, slot);
    return 0;
}

static myl_block *core_durable_error(CoreDurableText path, CoreDurableText to, unsigned kind, int status) {
    static const char *verbs[] = {"atomic write", "directory lock", "directory sync", "regular read", "directory listing", "rename", "stat", "lock file", "try lock file",
                                  "realpath", "chmod", "touch", "set modified", "atomic write", "stat", "directory listing", "replace", "replace", "replace", "replace", "symlink", "statfs",
                                  "read at", "read link", "link", "mkdir", "open"};
    const char *reason = status == CORE_DURABLE_UNCERTAIN
        ? "directory sync failed; publication may have occurred"
        : status == CORE_DURABLE_BUSY ? "the lock is held by another holder"
        : status == CORE_DURABLE_STAND_IN_WAIT ? "the lock is held (a stand-in cannot wait)"
        : status == CORE_DURABLE_BOUND ? core_io_os_reason
        : status == 1 ? "durable native filesystem provider is unavailable"
        : core_io_reason(status);
    /* A rename and a link name both ends: `rename 'from' to 'to': reason`. */
    size_t second = kind == CORE_DURABLE_RENAME || kind == CORE_DURABLE_LINK ? (size_t)to.len + 6 : 0;
    size_t size = strlen(verbs[kind - CORE_DURABLE_ATOMIC]) + strlen(reason) + (size_t)path.len + second + 6;
    char *text = malloc(size);
    if (!text) out_of_memory();
    size_t used = (size_t)sprintf(text, "%s '", verbs[kind - CORE_DURABLE_ATOMIC]);
    memcpy(text + used, path.data, (size_t)path.len);
    used += (size_t)path.len;
    if (second) {
        used += (size_t)sprintf(text + used, "' to '");
        memcpy(text + used, to.data, (size_t)to.len);
        used += (size_t)to.len;
    }
    used += (size_t)sprintf(text + used, "': %s", reason);
    myl_block *message = core_io_string(text, used, 1);
    free(text);
    return message;
}

static int core_durable_attempt(myl_block *cap, unsigned kind, CoreDurablePath *path,
                                CoreDurableText input, int64_t limit, myl_block **value) {
    if (kind == CORE_DURABLE_ATOMIC) return core_durable_publish(path, input, 0600, CORE_DURABLE_SYNC_BOTH);
    if (kind == CORE_DURABLE_ATOMIC_MODE) return core_durable_valid_mode(limit) ? core_durable_publish(path, input, (mode_t)limit, CORE_DURABLE_SYNC_BOTH) : 3;
    if (kind == CORE_DURABLE_REPLACE) return core_durable_publish(path, input, 0600, CORE_DURABLE_SYNC_NOTHING);
    if (kind == CORE_DURABLE_REPLACE_MODE) return core_durable_valid_mode(limit) ? core_durable_publish(path, input, (mode_t)limit, CORE_DURABLE_SYNC_NOTHING) : 3;
    if (kind == CORE_DURABLE_REPLACE_SYNCED) return core_durable_publish(path, input, 0600, CORE_DURABLE_SYNC_FILE);
    if (kind == CORE_DURABLE_REPLACE_SYNCED_MODE) return core_durable_valid_mode(limit) ? core_durable_publish(path, input, (mode_t)limit, CORE_DURABLE_SYNC_FILE) : 3;
    if (kind == CORE_DURABLE_CANONICAL) return core_durable_canonical(path, value);
    if (kind == CORE_DURABLE_CHMOD) return core_durable_chmod(path, limit);
    if (kind == CORE_DURABLE_SYMLINK) return core_durable_symlink(path, input);
    if (kind == CORE_DURABLE_MKDIR_MODE) return core_durable_mkdir(path, limit);
    if (kind == CORE_DURABLE_CREATE_MODE) return core_durable_create(cap, path, limit, value);
    if (kind == CORE_DURABLE_TOUCH) return core_durable_times(path, true, 0);
    if (kind == CORE_DURABLE_SET_MODIFIED) return core_durable_times(path, false, limit);
    if (kind == CORE_DURABLE_READ) return core_durable_read(path, limit, value);
    if (kind == CORE_DURABLE_READ_AT) return core_durable_read_at(path, input, limit, value);
    if (kind == CORE_DURABLE_LOCK) return core_durable_lock(cap, path, CORE_DURABLE_LEASE_DIRECTORY, value);
    if (kind == CORE_DURABLE_LOCK_FILE) return core_durable_lock(cap, path, CORE_DURABLE_LEASE_WAIT, value);
    if (kind == CORE_DURABLE_TRY_LOCK_FILE) return core_durable_lock(cap, path, CORE_DURABLE_LEASE_TRY, value);
    if (kind == CORE_DURABLE_LIST) return core_durable_listing(path, limit, false, value);
    if (kind == CORE_DURABLE_LIST_ENTRIES) return core_durable_listing(path, INT64_MAX, true, value);
    int fd = core_durable_directory(path);
    int status = fd < 0 ? (int)core_io_scoped_from_errno() : 0;
    if (!status && core_durable_sync_fd(fd)) status = core_io_failed_with(errno);
    if (fd >= 0) status = core_durable_close(fd, status);
    return status;
}

/* ---- the durable family on the in-memory filesystem -------------------------------------------------------------
 * A test's `Filesystem` is the `MemoryFs` stand-in (core_io.c), and these calls answer from its entries, so the code a
 * program ships (atomic publication, rename, stat, locks) is the code its tests run. Everything is deterministic and
 * needs no flag: the clock is the filesystem's own logical clock, one second for each call that changes it. The status-change
 * time (`Stat.changed`) is that reading for a call that writes, and for `chmod` and `set_modified_path`, which leave the clock
 * where it is, it is the next nanosecond after the last change, so it still moves.
 *  - Paths follow the real rules: relative, no `.` or `..` component (but `.` alone names the root for `canonical_path`),
 *    a narrowing prefix applies, and an empty path names the root only for the directory kinds. Refusals reuse the
 *    errno wording of the real provider (`core_io_scoped_from_errno`), so the text is the one production prints.
 *  - A symbolic link is an entry that holds the text `symlink_path` was given. As under a granted directory of the real
 *    provider, no call follows one except `canonical_path` and `stat_follow_path`, which follow it only while it stays inside
 *    the filesystem (an absolute target, or `..` past the root, is `resolves outside the granted directory`); every other call
 *    refuses a link on the way to its path, and a read, a write or a lock of a link itself, with the real wording. `stat_path`
 *    of a link is the link, `remove` unlinks it and `rename_path` moves it.
 *  - There is no umask: a mode is stored exactly as asked, so `chmod` and `stat` round trip.
 *  - `atomic_write_file` builds the new file whole and only then swaps it in, so a reader never sees a partial one; the
 *    replacement is a new inode (a handle that holds the old file keeps it, as an unlinked file stays open). A rename
 *    keeps the inode and the time of what it moves. Locks are held on the entry, like `flock` on an inode.
 */

/* A refusal worded by the real provider for the errno `cause`. */
static int core_durable_memory_errno(int cause) {
    errno = cause;
    return (int)core_io_scoped_from_errno();
}

/* Whether every ancestor of `path` exists and is a directory: 0, or the status of the refusal (`*missing` is set when an
 * ancestor does not exist, the case `stat` answers with an empty value). */
/* Whether the call being answered walks the directory that holds its path in one confined step, as a stat and a listing do
 * on the real provider: that step refuses a symbolic link on the way with `ELOOP`, where every other call walks a component
 * at a time and meets `ENOTDIR`, the way a file on the way is refused. Set by `core_durable_memory` for each call. */
static bool core_durable_memory_confined;

static int core_durable_memory_parents(MemoryFs *memory, const unsigned char *path, size_t length, bool *missing) {
    /* Left to right, the first ancestor that is missing, a link or a file. */
    for (size_t i = 0; i < length; ++i) {
        if (path[i] != '/') continue;
        MemoryEntry *ancestor = core_io_memory_find(memory, path, i);
        if (!ancestor) { *missing = true; return core_durable_memory_errno(ENOENT); }
        if (ancestor->target && core_durable_memory_confined) return core_durable_memory_errno(ELOOP);
        if (!ancestor->directory) return core_durable_memory_errno(ENOTDIR);
        if (!core_io_memory_allows(ancestor, CORE_IO_MEMORY_SEARCH)) return core_durable_memory_errno(EACCES);
    }
    return 0;
}

/* Whether the entry that holds `path` allows `want` (`core_io_memory_allows`): 0, or the refusal the real provider words for it. */
static int core_durable_memory_holder_allows(MemoryFs *memory, const unsigned char *path, size_t length, unsigned want) {
    return core_io_memory_allows(core_io_memory_holder(memory, path, length), want) ? 0 : core_durable_memory_errno(EACCES);
}

/* Whether the real provider walks to the directory that holds a path by opening it for reading
 * (`core_durable_walk_following`, `core_io_scoped_walk`): every durable kind but the stats, the canonical names and the
 * listings, which hold the directory with `O_PATH` or open the directory itself. Such a call needs the read bit of that
 * directory as well as its search bit, which the permission table of docs/io.md names. */
static bool core_durable_opens_parent(unsigned kind) {
    return !core_durable_describes(kind) && !core_durable_lists(kind) && !core_durable_canonical_kind(kind);
}

/* The entry at `path` (the root for the empty path), or NULL with `*status` the refusal and `*missing` set when nothing is
 * there or an ancestor is missing. */
static MemoryEntry *core_durable_memory_entry(MemoryFs *memory, const unsigned char *path, size_t length, bool *missing, int *status) {
    if (!length) return &memory->root;
    *status = core_durable_memory_parents(memory, path, length, missing);
    if (*status) return NULL;
    MemoryEntry *entry = core_io_memory_find(memory, path, length);
    if (!entry) {
        *missing = true;
        *status = core_durable_memory_errno(ENOENT);
    }
    return entry;
}

/* Join `path` under the capability's narrowing prefix into `joined` (`CORE_IO_SCOPED_PATH` octets) and read it as
 * docs/io.md says (`core_io_memory_normalize`): 0, or the status of a refusal with its reason. A narrowed path keeps the
 * old rule. `folder` lets the empty path name the root, as the directory kinds do. */
static int core_durable_memory_resolve(MemoryFs *memory, const CoreIoAuthority *authority, CoreDurableText path, bool folder,
                                       unsigned char *joined, size_t *length) {
    if (path.len < 0 || path.len > 4094) { errno = ENAMETOOLONG; return (int)core_io_scoped_from_errno(); }
    char spelled[4095];
    size_t width = (size_t)path.len;
    if (width) memcpy(spelled, path.data, width);
    if (authority->scope) {
        int refused = core_durable_narrow(authority, spelled, &width, folder);
        if (refused) return refused;
    }
    return (int)core_io_memory_normalize(memory, (const unsigned char *)spelled, width, folder ? 'm' : 'r', joined, length);
}

/* The device every entry of the in-memory filesystem is on: the number `stat(2)` would give for major 0 and minor 1. */
#define CORE_DURABLE_MEMORY_DEVICE 1u
/* What `statfs_path` answers on the in-memory filesystem, in bytes, whatever it holds: one GiB in all, half of it free
 * and 384 MiB of that available to an ordinary process (so a test can tell the three apart). */
#define CORE_DURABLE_MEMORY_SIZE UINT64_C(1073741824)
#define CORE_DURABLE_MEMORY_FREE UINT64_C(536870912)
#define CORE_DURABLE_MEMORY_AVAILABLE UINT64_C(402653184)

/* The user and the group that own every entry of the in-memory filesystem: 1000, the first ordinary account of a system, the
 * one whose permission bits the stand-in honours. A fixed number keeps a test the same on every machine. */
#define CORE_DURABLE_MEMORY_OWNER 1000u
#define CORE_DURABLE_MEMORY_GROUP 1000u

/* The hard links of an entry of the in-memory filesystem: the names a file has (`link_path` makes more; a symbolic link has
 * one), and for a directory 2 (its own name and its `.`) plus one for the `..` of each directory inside it, as `ext4` and
 * `tmpfs` count. */
static uint64_t core_durable_memory_links(const MemoryFs *memory, const MemoryEntry *entry) {
    if (!entry->directory) return entry->body->linked;
    uint64_t links = 2u;
    for (size_t i = 0; i < memory->count; ++i)
        if (memory->entries[i]->directory && core_io_memory_in_directory(memory->entries[i], (const unsigned char *)entry->path, entry->length)) ++links;
    return links;
}

/* The ten packed words `stat_path` answers on the real filesystem: size (a link's is the length of its target),
 * modification time in nanoseconds, inode, kind (1 file, 2 directory, 3 symbolic link; a stand-in has no specials),
 * permission bits, status-change time, the device (one fixed number for every entry), the owning user and group (one fixed
 * number each) and the hard links. */
static myl_block *core_durable_memory_packed(const MemoryFs *memory, const MemoryEntry *entry) {
    uint64_t size = entry->target ? (uint64_t)strlen(entry->target) : entry->directory ? 0u : (uint64_t)entry->body->size;
    uint64_t words[CORE_DURABLE_STAT_WORDS] = {size, (uint64_t)entry->body->mtime, entry->body->inode,
                                               entry->directory ? 2u : entry->target ? 3u : 1u, (uint64_t)entry->body->mode, (uint64_t)entry->body->ctime,
                                               CORE_DURABLE_MEMORY_DEVICE, CORE_DURABLE_MEMORY_OWNER, CORE_DURABLE_MEMORY_GROUP,
                                               core_durable_memory_links(memory, entry)};
    unsigned char packed[CORE_DURABLE_STAT_BYTES];
    memcpy(packed, words, sizeof packed);
    return core_io_string(packed, sizeof packed, 0);
}

/* The three packed words `statfs_path` answers on the in-memory filesystem: the fixed size, free and available bytes. */
static myl_block *core_durable_memory_space(void) {
    const uint64_t words[CORE_DURABLE_SPACE_WORDS] = {CORE_DURABLE_MEMORY_SIZE, CORE_DURABLE_MEMORY_FREE, CORE_DURABLE_MEMORY_AVAILABLE};
    unsigned char packed[CORE_DURABLE_SPACE_BYTES];
    memcpy(packed, words, sizeof packed);
    return core_io_string(packed, sizeof packed, 0);
}

/* The walk `canonical_path` and `stat_follow_path` make: `joined` (the narrowing prefix, `scope` octets, then the path) resolved
 * through the symbolic links of the filesystem, which are followed only while they stay inside the prefix: an absolute target,
 * or `..` past the prefix, is `resolves outside the granted directory`, and more than 40 links in one walk is the real
 * provider's `ELOOP`. `resolved` (`CORE_DURABLE_NAME + 1` octets) gets the link-free path, `*resolved_length` its width. The
 * answer is the entry the path names (the root for the empty path), or NULL with `*missing` set when nothing is there (a link
 * to nothing included) and `*status` the refusal. */
#define CORE_DURABLE_LINK_DEPTH 40
static MemoryEntry *core_durable_memory_follow(MemoryFs *memory, const unsigned char *joined, size_t length, size_t scope,
                                               char *resolved, size_t *resolved_length, bool *missing, int *status) {
    char pending[2 * CORE_DURABLE_NAME + 2];
    size_t used = scope, at = 0, first = scope ? scope + 1 : 0, end = length > first ? length - first : 0;
    memcpy(resolved, joined, scope);
    if (end) memcpy(pending, joined + first, end);
    int links = 0;
    while (at < end) {
        const char *name = pending + at;
        size_t width = 0;
        while (at + width < end && name[width] != '/') ++width;
        size_t after = at + width + (at + width < end ? 1 : 0);
        if (width == 1 && name[0] == '.') { at = after; continue; }
        if (width == 2 && name[0] == '.' && name[1] == '.') {
            if (used <= scope) { core_io_os_reason = "resolves outside the granted directory"; *status = 2; return NULL; }
            while (used > scope && resolved[used - 1] != '/') --used;
            if (used > scope) --used;
            at = after;
            continue;
        }
        size_t next = used + (used ? 1 : 0) + width;
        if (next > CORE_DURABLE_NAME) { *status = core_durable_memory_errno(ENAMETOOLONG); return NULL; }
        const MemoryEntry *here = used ? core_io_memory_find(memory, (const unsigned char *)resolved, used) : &memory->root;
        if (here && !core_io_memory_allows(here, CORE_IO_MEMORY_SEARCH)) { *status = core_durable_memory_errno(EACCES); return NULL; }
        if (used) resolved[used] = '/';
        memcpy(resolved + used + (used ? 1 : 0), name, width);
        MemoryEntry *entry = core_io_memory_find(memory, (const unsigned char *)resolved, next);
        if (!entry) { *missing = true; *status = core_durable_memory_errno(ENOENT); return NULL; }
        if (entry->target) {
            size_t target = strlen(entry->target), rest = end - after;
            if (++links > CORE_DURABLE_LINK_DEPTH) { *status = core_durable_memory_errno(ELOOP); return NULL; }
            if (entry->target[0] == '/') { core_io_os_reason = "resolves outside the granted directory"; *status = 2; return NULL; }
            if (target + (rest ? rest + 1 : 0) > sizeof pending) { *status = core_durable_memory_errno(ENAMETOOLONG); return NULL; }
            char joined_rest[sizeof pending];
            memcpy(joined_rest, entry->target, target);
            if (rest) { joined_rest[target] = '/'; memcpy(joined_rest + target + 1, pending + after, rest); }
            end = target + (rest ? rest + 1 : 0);
            memcpy(pending, joined_rest, end);
            at = 0;
            continue;
        }
        at = after;
        used = next;
        if (at < end && !entry->directory) { *status = core_durable_memory_errno(ENOTDIR); return NULL; }
    }
    *resolved_length = used;
    MemoryEntry *entry = used ? core_io_memory_find(memory, (const unsigned char *)resolved, used) : &memory->root;
    if (!entry) { *missing = true; *status = core_durable_memory_errno(ENOENT); }
    return entry;
}

/* `stat_path`, `stat_follow_path` and (with `space`) `statfs_path`: the packed words, or an empty value when nothing is at the
 * path. A followed stat describes what the links name, within the filesystem; the other one describes the final link itself. */
static int core_durable_memory_stat(MemoryFs *memory, const unsigned char *path, size_t length, size_t scope, bool follow, bool space, myl_block **out) {
    bool missing = false;
    int status = 0;
    char resolved[CORE_DURABLE_NAME + 1];
    size_t width = 0;
    MemoryEntry *entry = follow ? core_durable_memory_follow(memory, path, length, scope, resolved, &width, &missing, &status)
                                : core_durable_memory_entry(memory, path, length, &missing, &status);
    if (entry && space) *out = core_durable_memory_space();
    else if (entry) *out = core_durable_memory_packed(memory, entry);
    else if (missing) *out = core_io_string("", 0, 0);
    else return status;
    return 0;
}

/* `atomic_write_file` and `atomic_write_file_mode`: the file at `path` becomes `input` with permission bits `mode`, all at
 * once. The replacement is a new entry (a new inode) built before anything changes, so no failure leaves half a write. */
static int core_durable_memory_atomic(MemoryFs *memory, const unsigned char *path, size_t length, CoreDurableText input, unsigned mode) {
    if (input.len < 0 || (uint64_t)input.len > CORE_DURABLE_LIMIT) return core_durable_too_large();
    bool missing = false;
    int status = core_durable_memory_parents(memory, path, length, &missing);
    if (status) return status;
    MemoryEntry *old = core_io_memory_find(memory, path, length);
    if (old && old->directory) return core_durable_not_regular(S_IFDIR);
    if (old && old->target) return core_durable_not_regular(S_IFLNK);
    /* The publication writes a temporary beside the destination and renames it over, so it needs the write bit of the
     * directory, never the destination's own (a read-only file in a writable directory is replaced, as on disk). */
    status = core_durable_memory_holder_allows(memory, path, length, CORE_IO_MEMORY_WRITE);
    if (status) return status;
    size_t size = (size_t)input.len;
    /* A file with other names keeps its bytes when this one is replaced, so only a file with this name alone frees its size. */
    if (size + (memory->bytes - (old && old->body->linked == 1 ? old->body->size : 0)) > CORE_IO_MEMORY_MEMORY_BYTES) return core_durable_memory_errno(ENOSPC);
    if (!old && !core_io_memory_reserve(memory)) out_of_memory();
    MemoryEntry *entry = calloc(1, sizeof *entry);
    MemoryBody *body = calloc(1, sizeof *body);
    char *copy = malloc(length + 1);
    unsigned char *bytes = malloc(size ? size : 1);
    if (!entry || !body || !copy || !bytes) out_of_memory();
    entry->body = body;
    body->names = body->linked = 1;
    memcpy(copy, path, length);
    copy[length] = 0;
    if (size) memcpy(bytes, input.data, size);
    entry->path = copy;
    entry->length = length;
    entry->body->bytes = bytes;
    entry->body->size = entry->body->capacity = size;
    entry->body->mode = mode;
    entry->body->inode = ++memory->inodes;
    core_io_memory_stamp(memory, entry, core_io_memory_tick(memory));
    if (old) {
        for (size_t i = 0; i < memory->count; ++i) if (memory->entries[i] == old) memory->entries[i] = entry;
        core_io_memory_unname(memory, old);
        if (old->open) old->unlinked = 1;
        else core_io_memory_entry_free(old);
    } else memory->entries[memory->count++] = entry;
    memory->bytes += size;
    core_io_memory_stamp_parent(memory, path, length, entry->body->mtime);
    return 0;
}

/* Give `entry`, which lived at `from` (`from_length` octets), the path `to` with its tail kept: a directory moves its
 * descendants with it. */
static void core_durable_memory_repath(MemoryEntry *entry, size_t from_length, const unsigned char *to, size_t to_length) {
    size_t tail = entry->length - from_length;
    char *path = malloc(to_length + tail + 1);
    if (!path) out_of_memory();
    memcpy(path, to, to_length);
    memcpy(path + to_length, entry->path + from_length, tail);
    path[to_length + tail] = 0;
    free(entry->path);
    entry->path = path;
    entry->length = to_length + tail;
}

/* `rename_path`: `rename(2)` inside the filesystem. A file replaces a file, a directory replaces an empty directory, and
 * the moved entry keeps its inode, mode and time; the directories it leaves and enters get the new clock reading. */
static int core_durable_memory_rename(MemoryFs *memory, const unsigned char *from, size_t from_length, const unsigned char *to, size_t to_length) {
    bool missing = false;
    int status = core_durable_memory_parents(memory, from, from_length, &missing);
    if (status) return status;
    MemoryEntry *source = core_io_memory_find(memory, from, from_length);
    if (!source) return core_durable_memory_errno(ENOENT);
    status = core_durable_memory_parents(memory, to, to_length, &missing);
    if (status) return status;
    MemoryEntry *target = core_io_memory_find(memory, to, to_length);
    /* Two names of one file: the system does nothing and says so. */
    if (target == source || (target && !source->directory && target->body == source->body)) return 0;
    if (source->directory && to_length > from_length && to[from_length] == '/' && !memcmp(to, from, from_length)) {
        core_io_os_reason = "a directory cannot be moved into itself";
        return 3;
    }
    /* Both directories need the write bit, and a directory that moves to another parent needs its own (its `..` changes). */
    status = core_durable_memory_holder_allows(memory, from, from_length, CORE_IO_MEMORY_WRITE);
    if (!status) status = core_durable_memory_holder_allows(memory, to, to_length, CORE_IO_MEMORY_WRITE);
    if (!status && source->directory && core_io_memory_holder(memory, from, from_length) != core_io_memory_holder(memory, to, to_length))
        status = core_io_memory_allows(source, CORE_IO_MEMORY_WRITE) ? 0 : core_durable_memory_errno(EACCES);
    if (status) return status;
    if (target && source->directory != target->directory) return core_durable_memory_errno(target->directory ? EISDIR : ENOTDIR);
    if (target && target->directory && core_io_memory_has_children(memory, target)) return core_durable_memory_errno(ENOTEMPTY);
    int64_t now = core_io_memory_tick(memory);
    source->body->ctime = now;
    if (now > memory->changed) memory->changed = now;
    if (target) core_io_memory_unlink_entry(memory, target);
    for (size_t i = 0; source->directory && i < memory->count; ++i) {
        MemoryEntry *inside = memory->entries[i];
        if (inside->length > from_length && inside->path[from_length] == '/' && !memcmp(inside->path, from, from_length))
            core_durable_memory_repath(inside, from_length, to, to_length);
    }
    core_durable_memory_repath(source, from_length, to, to_length);
    core_io_memory_stamp_parent(memory, from, from_length, now);
    core_io_memory_stamp_parent(memory, to, to_length, now);
    return 0;
}

/* `canonical_path`: the link-free name of an existing path relative to the filesystem (the narrowing prefix), `""` for the
 * root. A link on the way is followed while it stays inside the prefix (`core_durable_memory_follow`). */
static int core_durable_memory_canonical(MemoryFs *memory, const unsigned char *joined, size_t length, size_t scope, myl_block **out) {
    bool missing = false;
    int status = 0;
    char resolved[CORE_DURABLE_NAME + 1];
    size_t width = 0;
    if (!core_durable_memory_follow(memory, joined, length, scope, resolved, &width, &missing, &status)) return status;
    size_t skip = scope && width > scope ? scope + 1 : scope;
    *out = core_io_string(resolved + skip, width - skip, 1);
    return 0;
}

/* `read_link_path`: the text of the link at `path`, which is not followed (the entry is found as a stat finds it: a link on the
 * way is refused, a missing entry or ancestor is the generic failure). Any other entry, the root included, is not a link. */
static int core_durable_memory_read_link(MemoryFs *memory, const unsigned char *path, size_t length, myl_block **out) {
    bool missing = false;
    int status = 0;
    MemoryEntry *entry = core_durable_memory_entry(memory, path, length, &missing, &status);
    if (!entry) return status;
    if (!entry->target) { core_io_os_reason = CORE_DURABLE_NOT_A_LINK; return 3; }
    *out = core_io_string(entry->target, strlen(entry->target), 1);
    return 0;
}

/* `symlink_path`: the link `path` holding the text `target`. It makes a new entry (so the directory's time moves), refuses a
 * path that exists, and keeps the text as written, as the real call does; the target is not followed or checked. */
static int core_durable_memory_symlink(MemoryFs *memory, const unsigned char *path, size_t length, CoreDurableText target) {
    if (target.len <= 0 || target.len >= CORE_DURABLE_NAME || memchr(target.data, 0, (size_t)target.len)) {
        core_io_os_reason = "the link target must be text of 1 to 4094 octets with no NUL";
        return 3;
    }
    bool missing = false;
    int status = core_durable_memory_parents(memory, path, length, &missing);
    if (status) return status;
    if (core_io_memory_find(memory, path, length)) return core_durable_memory_errno(EEXIST);
    status = core_durable_memory_holder_allows(memory, path, length, CORE_IO_MEMORY_WRITE);
    if (status) return status;
    char *text = malloc((size_t)target.len + 1);
    if (!text) out_of_memory();
    memcpy(text, target.data, (size_t)target.len);
    text[target.len] = 0;
    MemoryEntry *entry = core_io_memory_create(memory, path, length, 0);
    if (!entry) { free(text); out_of_memory(); }
    entry->target = text;
    entry->body->mode = 0777;
    return 0;
}

/* `link_path`: a second name `path` for the file at `target`, which shares its bytes, mode, inode and times, so a write through one
 * name is read through the other and `stat` counts both as links. The source must be a regular file (a folder, a symbolic link
 * and the root are refused as a publication over one is), the new name must not exist, and the directory that holds it needs the
 * write bit. The link changes the file's status (so its status-change time moves) and the directory's modification time. */
static int core_durable_memory_link(MemoryFs *memory, const unsigned char *target, size_t target_length, const unsigned char *path, size_t length, bool slash) {
    bool missing = false;
    int status = 0;
    MemoryEntry *source = core_durable_memory_entry(memory, target, target_length, &missing, &status);
    if (!source) return status;
    if (source->directory) return core_durable_not_regular(S_IFDIR);
    if (source->target) return core_durable_not_regular(S_IFLNK);
    status = core_durable_memory_parents(memory, path, length, &missing);
    if (status) return status;
    if (!length || core_io_memory_find(memory, path, length)) return core_durable_memory_errno(EEXIST);
    /* A name that ends in `/` names a folder, and a file is not made where one is wanted (`link(2)` answers ENOENT). */
    if (slash) return core_durable_memory_errno(ENOENT);
    status = core_durable_memory_holder_allows(memory, path, length, CORE_IO_MEMORY_WRITE);
    if (status) return status;
    if (!core_io_memory_reserve(memory)) out_of_memory();
    MemoryEntry *entry = calloc(1, sizeof *entry);
    char *copy = malloc(length + 1);
    if (!entry || !copy) out_of_memory();
    memcpy(copy, path, length);
    copy[length] = 0;
    entry->path = copy;
    entry->length = length;
    entry->body = source->body;
    ++entry->body->names;
    ++entry->body->linked;
    memory->entries[memory->count++] = entry;
    const int64_t now = core_io_memory_tick(memory);
    entry->body->ctime = now;
    if (now > memory->changed) memory->changed = now;
    core_io_memory_stamp_parent(memory, path, length, now);
    return 0;
}

/* `mkdir_mode`: a new directory `path` with the permission bits `mode` (the system's nine and the sticky bit; the stand-in has no
 * umask), made as `mkdir` makes one: its parent must exist, be searchable and writable, and the name must be free. */
static int core_durable_memory_mkdir(MemoryFs *memory, const unsigned char *path, size_t length, int64_t mode) {
    if (!core_durable_valid_mode(mode)) return 3;
    bool missing = false;
    int status = core_durable_memory_parents(memory, path, length, &missing);
    if (status) return status;
    if (!length || core_io_memory_find(memory, path, length)) return core_durable_memory_errno(EEXIST);
    status = core_durable_memory_holder_allows(memory, path, length, CORE_IO_MEMORY_WRITE);
    if (status) return status;
    MemoryEntry *entry = core_io_memory_create(memory, path, length, 1);
    if (!entry) out_of_memory();
    entry->body->mode = (unsigned)mode & 01777u;
    return 0;
}

/* `chmod_path`, `touch_path` and `set_modified_path` of an existing entry. `touch` reads the clock; `set_modified` sets
 * the time it is given and `chmod` changes no modification time, so neither moves the clock, and both still change the
 * entry's status (`core_io_memory_changed`). A link has no permission bits to set; `touch` and `set_modified` change it. */
static int core_durable_memory_attributes(MemoryFs *memory, unsigned kind, const unsigned char *path, size_t length, int64_t value) {
    if (kind == CORE_DURABLE_CHMOD && !core_durable_valid_mode(value)) return 3;
    bool missing = false;
    int status = 0;
    MemoryEntry *entry = core_durable_memory_entry(memory, path, length, &missing, &status);
    if (!entry) return status;
    if (kind == CORE_DURABLE_CHMOD && entry->target) { core_io_os_reason = "a symbolic link has no permission bits of its own"; return 3; }
    if (kind == CORE_DURABLE_CHMOD) {
        entry->body->mode = (unsigned)value;
        entry->body->ctime = core_io_memory_changed(memory);
    } else if (kind == CORE_DURABLE_TOUCH) core_io_memory_stamp(memory, entry, core_io_memory_tick(memory));
    else {
        entry->body->mtime = value;
        entry->body->ctime = core_io_memory_changed(memory);
    }
    return 0;
}

/* `read_regular_file`: the bytes of a file no larger than `limit`. */
static int core_durable_memory_read(MemoryFs *memory, const unsigned char *path, size_t length, int64_t limit, myl_block **out) {
    if (core_durable_bad_limit(limit)) return 3;
    bool missing = false;
    int status = 0;
    MemoryEntry *entry = core_durable_memory_entry(memory, path, length, &missing, &status);
    if (!entry) return status;
    if (entry->directory) return core_durable_memory_errno(EACCES);
    if (entry->target) return core_durable_memory_errno(ELOOP);
    if (!core_io_memory_allows(entry, CORE_IO_MEMORY_READ)) return core_durable_memory_errno(EACCES);
    if ((uint64_t)entry->body->size > (uint64_t)limit) return core_durable_larger();
    *out = core_io_string(entry->body->bytes, entry->body->size, 0);
    return 0;
}

/* `read_at_path`: up to `count` octets of a file from byte `offset`, fewer at the end and none past it. */
static int core_durable_memory_read_at(MemoryFs *memory, const unsigned char *path, size_t length, CoreDurableText window, int64_t count, myl_block **out) {
    uint64_t offset;
    int status = core_durable_window(window, count, &offset);
    if (status) return status;
    bool missing = false;
    MemoryEntry *entry = core_durable_memory_entry(memory, path, length, &missing, &status);
    if (!entry) return status;
    if (entry->directory) return core_durable_memory_errno(EACCES);
    if (entry->target) return core_durable_memory_errno(ELOOP);
    if (!core_io_memory_allows(entry, CORE_IO_MEMORY_READ)) return core_durable_memory_errno(EACCES);
    const size_t from = offset < (uint64_t)entry->body->size ? (size_t)offset : entry->body->size;
    size_t take = entry->body->size - from;
    if (take > (size_t)count) take = (size_t)count;
    *out = core_io_string(entry->body->bytes + from, take, 0);
    return 0;
}

/* `list_directory` and `list_entries_path`: every name in a directory, sorted (the real provider answers in the system's
 * order), as a `str[]` or, with `kinds`, packed with each entry's kind as the real listing packs it. A refusal when there
 * are more than `limit` of them. */
static int core_durable_memory_list(MemoryFs *memory, const unsigned char *path, size_t length, int64_t limit, bool kinds, myl_block **out) {
    if (limit < 0) return core_durable_list_bound(limit, true);
    bool missing = false;
    int status = 0;
    MemoryEntry *directory = core_durable_memory_entry(memory, path, length, &missing, &status);
    if (!directory) return status;
    if (!directory->directory) {
        status = core_durable_memory_errno(ENOTDIR);
        core_io_os_reason = "is not a directory";
        return status;
    }
    if (!core_io_memory_allows(directory, CORE_IO_MEMORY_READ)) return core_durable_memory_errno(EACCES);
    MemoryEntry **children = malloc((memory->count ? memory->count : 1) * sizeof *children);
    if (!children) out_of_memory();
    size_t count = 0;
    for (size_t i = 0; i < memory->count; ++i) if (core_io_memory_in_directory(memory->entries[i], path, length)) children[count++] = memory->entries[i];
    if ((int64_t)count > limit) { free(children); return core_durable_list_bound(limit, false); }
    qsort(children, count, sizeof *children, core_io_memory_leaf_order);
    myl_block *list = kinds ? NULL : core_io_list_new(0);
    CoreIoBytes packed = {0};
    for (size_t i = 0; i < count && !status; ++i) {
        size_t width;
        const char *name = core_io_memory_leaf(children[i], &width);
        if (width > 255 || !core_io_utf8((const unsigned char *)name, width)) status = 5;
        else if (kinds) {
            unsigned char head[3] = {children[i]->directory ? 2 : children[i]->target ? 3 : 1, (unsigned char)width, 0};
            core_io_append(&packed, head, sizeof head);
            core_io_append(&packed, (const unsigned char *)name, width);
        } else core_io_list_add(&list, core_io_string(name, width, 1));
    }
    free(children);
    if (status && list) core_io_drop(list);
    else if (!status) *out = kinds ? core_io_string(packed.bytes, packed.length, 0) : list;
    core_io_bytes_release(&packed);
    return status;
}

/* `lock_directory`, `lock_file` and `try_lock_file`: a `File` that holds the entry locked until it is released, on every exit
 * of its `with` scope. A file lock creates the file (mode 0600) when it is missing, as the real one does. A lock that is
 * held fails at once: `lock_file` cannot wait, since nothing else runs while it would, so its failure says so. */
static int core_durable_memory_lock(myl_block *cap, const unsigned char *path, size_t length, CoreDurableLease style, myl_block **out) {
    CoreIoAuthority *authority = core_io_authority(cap);
    CoreIoState *state = core_io_state(cap);
    MemoryFs *memory = state->memory;
    size_t slot = core_io_memory_free_handle(memory);
    if (slot == SIZE_MAX || core_io_family_open[0] >= 1024) return 4;
    bool missing = false, file = style != CORE_DURABLE_LEASE_DIRECTORY;
    int status = core_durable_memory_parents(memory, path, length, &missing);
    if (status) return status;
    MemoryEntry *entry = length ? core_io_memory_find(memory, path, length) : &memory->root;
    const bool existed = entry != NULL;
    if (!entry && !file) return core_durable_memory_errno(ENOENT);
    if (!entry) {
        status = core_durable_memory_holder_allows(memory, path, length, CORE_IO_MEMORY_WRITE);
        if (status) return status;
        entry = core_io_memory_create(memory, path, length, 0);
        if (!entry) out_of_memory();
        entry->body->mode = 0600;
    }
    if (file && entry->directory) { core_io_os_reason = "is a directory"; return 2; }
    if (entry->target) return core_durable_memory_errno(ELOOP);
    if (!file && !entry->directory) return core_durable_memory_errno(ENOTDIR);
    /* A directory lease opens the directory for reading, a file lock opens the file for reading and writing. */
    if (!file && !core_io_memory_allows(entry, CORE_IO_MEMORY_READ)) return core_durable_memory_errno(EACCES);
    if (file && existed && !core_io_memory_allows(entry, CORE_IO_MEMORY_READ | CORE_IO_MEMORY_WRITE)) return core_durable_memory_errno(EACCES);
    if (entry->body->locked) return style == CORE_DURABLE_LEASE_WAIT ? CORE_DURABLE_STAND_IN_WAIT : CORE_DURABLE_BUSY;
    myl_block *block = block_new(7, sizeof(CoreIoResource), 1);
    block->len = 1;
    block->reserved = (int64_t)(intptr_t)core_io_resource_layout;
    memset(block_data(block), 0, sizeof(CoreIoResource));
    entry->body->locked = 1;
    entry->open++;
    memory->handles[slot] = (MemoryHandle){1, entry, NULL, 0, 0, 'L', 0, 0};
    CoreIoResource *resource = (CoreIoResource *)block_data(block);
    *resource = (CoreIoResource){cap, slot, 2, authority->rights & state->adapter.permissions, 1, 0, core_io_tail, NULL, block};
    if (core_io_tail) core_io_tail->next = resource;
    core_io_tail = resource;
    ++core_io_open_count;
    ++core_io_family_open[0];
    *out = block;
    return 0;
}

/* `create_mode` on the stand-in: `open(path, "wb")` as the stand-in opens it, a new file given the permission bits `mode` as
 * given (it has no umask), an existing one truncated with its own. */
static int core_durable_memory_create(myl_block *cap, const unsigned char *path, size_t length, int64_t mode, myl_block **out) {
    if (!core_durable_valid_mode(mode)) return 3;
    MemoryFs *memory = core_io_state(cap)->memory;
    if (!length) { core_io_os_reason = "is a directory"; return 2; }
    size_t slot = core_io_memory_free_handle(memory);
    if (slot == SIZE_MAX || core_io_family_open[0] >= 1024) return 4;
    const unsigned char letter = core_io_memory_find(memory, path, length) ? 't' : 'c';
    CoreIoProviderStatus status = CORE_IO_PROVIDER_OK;
    unsigned char fresh = 0;
    MemoryEntry *entry = core_io_memory_open_file(memory, path, length, letter, &status, &fresh);
    if (!entry && status == CORE_IO_PROVIDER_OUT_OF_MEMORY) out_of_memory();
    if (!entry) return (int)status;
    if (letter == 'c') entry->body->mode = (unsigned)mode;
    entry->open++;
    memory->handles[slot] = (MemoryHandle){1, entry, NULL, 0, 0, letter, fresh, 0};
    *out = core_durable_file(cap, slot);
    return 0;
}

/* One durable call on a test's Filesystem: the grant and path rules of `core_durable_path`, then the operation on the
 * stand-in's entries. */
static int core_durable_memory(myl_block *cap, unsigned kind, CoreDurableText path, CoreDurableText input, int64_t limit, myl_block **value) {
    CoreIoAuthority *authority = core_io_authority(cap);
    CoreIoState *state = core_io_state(cap);
    MemoryFs *memory = state->memory;
    core_durable_memory_confined = core_durable_describes(kind) || core_durable_lists(kind);
    unsigned right = core_durable_reads(kind) || core_durable_lists(kind) || core_durable_describes(kind) || core_durable_canonical_kind(kind) ? 1u : 2u;
    bool directory = kind == CORE_DURABLE_LOCK || kind == CORE_DURABLE_SYNC || core_durable_lists(kind) || core_durable_describes(kind) ||
                     core_durable_canonical_kind(kind);
    CoreDurableText named = path;
    if (kind == CORE_DURABLE_CANONICAL && path.len == 1 && path.data[0] == '.') named.len = 0;
    if (!(authority->rights & state->adapter.permissions & right)) {
        if (!(authority->rights & right)) core_io_os_reason = CORE_IO_REFUSAL_READ_ONLY;
        return 2;
    }
    unsigned char joined[CORE_IO_SCOPED_PATH], destination[CORE_IO_SCOPED_PATH];
    size_t length = 0, other = 0, scope = authority->scope ? (size_t)authority->scope->len : 0;
    int refused = core_durable_memory_resolve(memory, authority, named, directory, joined, &length);
    const bool two = kind == CORE_DURABLE_RENAME || kind == CORE_DURABLE_LINK;
    if (!refused && two) refused = core_durable_memory_resolve(memory, authority, input, false, destination, &other);
    if (refused) return refused;
    if (core_durable_opens_parent(kind)) {
        bool missing = false;
        int status = core_durable_memory_parents(memory, joined, length, &missing);
        if (!status) status = core_durable_memory_holder_allows(memory, joined, length, CORE_IO_MEMORY_READ);
        if (!status && two) status = core_durable_memory_parents(memory, destination, other, &missing);
        if (!status && two) status = core_durable_memory_holder_allows(memory, destination, other, CORE_IO_MEMORY_READ);
        if (status) return status;
    }
    switch (kind) {
    case CORE_DURABLE_ATOMIC: case CORE_DURABLE_REPLACE: case CORE_DURABLE_REPLACE_SYNCED:
        return core_durable_memory_atomic(memory, joined, length, input, 0600);
    case CORE_DURABLE_ATOMIC_MODE: case CORE_DURABLE_REPLACE_MODE: case CORE_DURABLE_REPLACE_SYNCED_MODE: return core_durable_valid_mode(limit) ? core_durable_memory_atomic(memory, joined, length, input, (unsigned)limit) : 3;
    case CORE_DURABLE_RENAME: return core_durable_memory_rename(memory, joined, length, destination, other);
    case CORE_DURABLE_LINK: return core_durable_memory_link(memory, joined, length, destination, other, input.len > 0 && input.data[input.len - 1] == '/');
    case CORE_DURABLE_MKDIR_MODE: return core_durable_memory_mkdir(memory, joined, length, limit);
    case CORE_DURABLE_CREATE_MODE: return core_durable_memory_create(cap, joined, length, limit, value);
    case CORE_DURABLE_STAT: case CORE_DURABLE_STAT_FOLLOW: case CORE_DURABLE_STATFS:
        return core_durable_memory_stat(memory, joined, length, scope, kind == CORE_DURABLE_STAT_FOLLOW, kind == CORE_DURABLE_STATFS, value);
    case CORE_DURABLE_CANONICAL: return core_durable_memory_canonical(memory, joined, length, scope, value);
    case CORE_DURABLE_READ_LINK: return core_durable_memory_read_link(memory, joined, length, value);
    case CORE_DURABLE_SYMLINK: return core_durable_memory_symlink(memory, joined, length, input);
    case CORE_DURABLE_CHMOD: case CORE_DURABLE_TOUCH: case CORE_DURABLE_SET_MODIFIED: return core_durable_memory_attributes(memory, kind, joined, length, limit);
    case CORE_DURABLE_READ: return core_durable_memory_read(memory, joined, length, limit, value);
    case CORE_DURABLE_READ_AT: return core_durable_memory_read_at(memory, joined, length, input, limit, value);
    case CORE_DURABLE_LIST: return core_durable_memory_list(memory, joined, length, limit, false, value);
    case CORE_DURABLE_LIST_ENTRIES: return core_durable_memory_list(memory, joined, length, INT64_MAX, true, value);
    case CORE_DURABLE_LOCK: return core_durable_memory_lock(cap, joined, length, CORE_DURABLE_LEASE_DIRECTORY, value);
    case CORE_DURABLE_LOCK_FILE: return core_durable_memory_lock(cap, joined, length, CORE_DURABLE_LEASE_WAIT, value);
    case CORE_DURABLE_TRY_LOCK_FILE: return core_durable_memory_lock(cap, joined, length, CORE_DURABLE_LEASE_TRY, value);
    default: {
        /* `sync_directory`: nothing to flush, but the path must be a directory. */
        bool missing = false;
        int status = 0;
        MemoryEntry *entry = core_durable_memory_entry(memory, joined, length, &missing, &status);
        if (!entry) return status;
        if (!entry->directory) return core_durable_memory_errno(ENOTDIR);
        return core_io_memory_allows(entry, CORE_IO_MEMORY_READ) ? 0 : core_durable_memory_errno(EACCES);
    }
    }
}

/* The granted-directory providers: every kind resolves its path in each granted root in turn. */
static int core_durable_native(myl_block *cap, unsigned kind, CoreDurableText path, CoreDurableText input, int64_t limit, myl_block **value) {
    size_t next = 0;
    int status = kind == CORE_DURABLE_LOCK ? core_durable_unique_directory(cap, path) : 0;
    const bool described = core_durable_describes(kind) || kind == CORE_DURABLE_STAT_FOLLOW;
    bool admitted = status == 0 && kind != CORE_DURABLE_RENAME && kind != CORE_DURABLE_LINK && !described;
    if (kind == CORE_DURABLE_RENAME) status = core_durable_rename(cap, path, input);
    else if (kind == CORE_DURABLE_LINK) status = core_durable_link(cap, path, input);
    else if (kind == CORE_DURABLE_READ_LINK) status = core_durable_read_link(cap, path, value);
    else if (described) status = core_durable_stat(cap, path, kind, value);
    if (admitted) status = 2;
    while (admitted) {
        CoreDurablePath resolved;
        int failure = core_durable_path(cap, path, kind, &resolved, &next, false);
        if (failure) { if (status == 2) status = failure; break; }
        status = core_durable_attempt(cap, kind, &resolved, input, limit, value);
        core_durable_release(&resolved);
        /* Never retry another root after a rename whose directory sync failed:
         * the first root may already contain the published value. */
        if (!status || status == 4 || status == CORE_DURABLE_UNCERTAIN || status == CORE_DURABLE_BUSY || status == CORE_DURABLE_BOUND) break;
    }
    return status;
}

/* The calls that make something new beside a path: a failed one that found nothing there found no folder to make it in. */
static bool core_durable_creates(unsigned kind) {
    return kind == CORE_DURABLE_ATOMIC || kind == CORE_DURABLE_ATOMIC_MODE || kind == CORE_DURABLE_SYMLINK || kind == CORE_DURABLE_CREATE_MODE ||
           (kind >= CORE_DURABLE_REPLACE && kind <= CORE_DURABLE_REPLACE_SYNCED_MODE);
}

static myl_block *core_durable_access(myl_block *cap, uint32_t request, CoreDurableText path,
                                      CoreDurableText input, int64_t limit) {
    CORE_IO_GUARD;
    unsigned kind = request & 255;
    if (kind < CORE_DURABLE_ATOMIC || kind > CORE_DURABLE_CREATE_MODE) core_io_fail("R_FILE");
    core_io_os_reason = NULL;
    myl_block *value = NULL;
    CoreIoState *state = core_io_state(cap);
    /* A test's Filesystem is the in-memory stand-in: the same calls, answered from its entries. */
    int status = core_io_authority(cap)->family == 2 && state->test && state->memory
        ? core_durable_memory(cap, kind, path, input, limit, &value)
        : core_durable_native(cap, kind, path, input, limit, &value);
    if (status && core_io_os_reason == core_io_reason_missing && path.len > 0 && memchr(path.data, '/', (size_t)path.len)) {
        /* `mkdir_mode` words it as `mkdir` does. */
        if (kind == CORE_DURABLE_MKDIR_MODE) core_io_os_reason = "the parent directory does not exist";
        else if (core_durable_creates(kind)) core_io_os_reason = core_io_reason_no_folder;
    }
    /* The `File` keeps the name the program gave, so a failed write on it names the path. */
    if (!status && kind == CORE_DURABLE_CREATE_MODE && value) {
        CoreIoResource *resource = core_io_resource(value);
        resource->path = malloc((size_t)path.len + 1);
        if (!resource->path) out_of_memory();
        if (path.len) memcpy(resource->path, path.data, (size_t)path.len);
        resource->path[path.len] = 0;
    }
    if (request & (1u << 17)) {
        if (status) {
            myl_block *message = core_durable_error(path, input, kind, status);
            core_io_message_trap((const char *)block_data(message), (size_t)message->len);
        }
        return value;
    }
    bool pointer = kind == CORE_DURABLE_LOCK || core_durable_reads(kind) || core_durable_lists(kind) || core_durable_describes(kind) ||
                   kind == CORE_DURABLE_LOCK_FILE || kind == CORE_DURABLE_TRY_LOCK_FILE || kind == CORE_DURABLE_CANONICAL ||
                   kind == CORE_DURABLE_STAT_FOLLOW || kind == CORE_DURABLE_CREATE_MODE;
    return core_io_result(status, (uint64_t)(uintptr_t)value,
                          status ? core_durable_error(path, input, kind, status) : NULL, pointer);
}

myl_block *myl_core_durable_access(int64_t cap, uint32_t request, myl_block *path,
                                  myl_block *input, int64_t limit) {
    return core_durable_access(core_io_handle(cap), request, (CoreDurableText){block_data(path), path->len},
                               (CoreDurableText){block_data(input), input->len}, limit);
}

/* The span form (C9): a borrowed `str` or `bytes` view is read in place, with no owned copy of the path or payload. */
myl_block *myl_core_span_durable_access(int64_t cap, uint32_t request, const unsigned char *path,
                                       uint64_t path_length, const unsigned char *input, uint64_t input_length,
                                       int64_t limit) {
    return core_durable_access(core_io_handle(cap), request, (CoreDurableText){path, (int64_t)path_length},
                               (CoreDurableText){input, (int64_t)input_length}, limit);
}
