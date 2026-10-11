/* Capability-checked, bounded native storage. This provider implements full
 * write/file-fsync/rename/directory-fsync and crash-released directory ownership.
 * Its process-crash contract does not assert qualified power-loss durability. */
#include <sys/file.h>

#define CORE_DURABLE_LIMIT (64u * 1024u * 1024u)
#define CORE_DURABLE_ATOMIC 9u
#define CORE_DURABLE_LOCK 10u
#define CORE_DURABLE_SYNC 11u
#define CORE_DURABLE_READ 12u
#define CORE_DURABLE_LIST 13u
#define CORE_DURABLE_UNCERTAIN 6

typedef struct { int parent; char leaf[4095]; } CoreDurablePath;
static uint64_t core_durable_serial;

static int core_durable_sync_fd(int fd) {
    int status;
    do { status = fsync(fd); } while (status && errno == EINTR);
    return status;
}

/* Scope and permissions are checked before opening anything. An absolute path
 * is admitted only by an unrestricted direct root. Even that root walks every
 * component without following a symlink. Empty paths name a directory root. */
static int core_durable_path(myl_block *cap, myl_block *path, unsigned kind,
                             CoreDurablePath *resolved, size_t *next, bool include_readonly) {
    CoreIoAuthority *authority = core_io_authority(cap);
    CoreIoState *state = core_io_state(cap);
    resolved->parent = -1;
    if (authority->family != 2) return 2;
    if (state->test || core_io_embedding ||
        state->adapter.acquire != core_io_scoped_acquire) return 1;
    unsigned right = kind == CORE_DURABLE_READ || kind == CORE_DURABLE_LIST ? 1u : 2u;
    if (!(authority->rights & state->adapter.permissions & right)) return 2;
    if (path->len < 0 || path->len > 4094) return 2;
    char joined[4095];
    size_t length = (size_t)path->len;
    if (length) memcpy(joined, block_data(path), length);
    if (authority->scope && authority->scope->len) {
        size_t scope = (size_t)authority->scope->len;
        if (length && joined[0] == '/') return 2;
        if (scope + length + (length != 0) > 4094) return 2;
        memmove(joined + scope + (length != 0), joined, length);
        memcpy(joined, block_data(authority->scope), scope);
        if (length) joined[scope] = '/';
        length += scope + (length != 0);
    }
    joined[length] = 0;
    bool directory = kind == CORE_DURABLE_LOCK || kind == CORE_DURABLE_SYNC || kind == CORE_DURABLE_LIST;
    CoreIoScoped *scoped = state->adapter.context;
    int failure = 2;
    for (size_t i = *next; i < scoped->count; ++i) {
        *next = i + 1;
        CoreIoScopedRoot root = scoped->roots[i];
        if (right == 2 && !root.writable && !include_readonly) continue;
        const char *relative = joined;
        size_t width = length;
        bool absolute = width && relative[0] == '/';
        if (absolute && (!root.direct || authority->scope)) continue;
        if (absolute) { ++relative; --width; }
        if (!core_io_scoped_valid_path(relative, width, directory ? 'm' : 'r')) continue;
        int base = absolute ? open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                            : fcntl(root.fd, F_DUPFD_CLOEXEC, 0);
        if (base < 0) { failure = (int)core_io_scoped_from_errno(); continue; }
        size_t last = 0;
        int parent = core_io_scoped_walk(base, relative, width, &last);
        if (parent != base) close(base);
        if (parent < 0) { failure = (int)core_io_scoped_from_errno(); continue; }
        size_t leaf = width - last;
        memcpy(resolved->leaf, relative + last, leaf);
        resolved->leaf[leaf] = 0;
        resolved->parent = parent;
        return 0;
    }
    return failure;
}

static int core_durable_directory(CoreDurablePath *path) {
    return openat(path->parent, path->leaf[0] ? path->leaf : ".",
                  O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
}

/* A directory lease must own every root that later reads could select. Include
 * read-only grants, and allow repeated grants only when they name one inode.
 * External directory replacement is outside this cooperative ownership model. */
static int core_durable_unique_directory(myl_block *cap, myl_block *path) {
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
        int failed = fstat(fd, &info);
        close(fd);
        if (failed) return 3;
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

/* Complete partial writes and retry interruptions; zero progress is failure. */
static int core_durable_write(int fd, const unsigned char *data, size_t length) {
    size_t at = 0;
    while (at < length) {
        size_t take = length - at;
        if (take > 65536) take = 65536;
        ssize_t written = write(fd, data + at, take);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return 3;
        at += (size_t)written;
    }
    return 0;
}

static int core_durable_publish(CoreDurablePath *path, myl_block *input) {
    if (input->len < 0 || (uint64_t)input->len > CORE_DURABLE_LIMIT) return 3;
    struct stat existing;
    if (fstatat(path->parent, path->leaf, &existing, AT_SYMLINK_NOFOLLOW) == 0) {
        if (!S_ISREG(existing.st_mode)) return 2;
    } else if (errno != ENOENT) return (int)core_io_scoped_from_errno();
    char temporary[192];
    int fd = -1;
    for (unsigned attempt = 0; attempt < 1024; ++attempt) {
        int size = snprintf(temporary, sizeof temporary, ".myl-durable-%.128s-%lu-%llu",
                            path->leaf, (unsigned long)getpid(),
                            (unsigned long long)++core_durable_serial);
        if (size < 0 || (size_t)size >= sizeof temporary) return 3;
        fd = openat(path->parent, temporary,
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
        if (fd >= 0 || errno != EEXIST) break;
    }
    if (fd < 0) return (int)core_io_scoped_from_errno();
    int status = core_durable_write(fd, block_data(input), (size_t)input->len);
    if (!status && core_durable_sync_fd(fd)) status = 3;
    if (close(fd) && !status) status = 3;
    if (!status && renameat(path->parent, temporary, path->parent, path->leaf))
        status = (int)core_io_scoped_from_errno();
    if (status) { unlinkat(path->parent, temporary, 0); return status; }
    if (core_durable_sync_fd(path->parent)) return CORE_DURABLE_UNCERTAIN;
    return 0;
}

static int core_durable_read(CoreDurablePath *path, int64_t limit, myl_block **out) {
    if (limit < 0 || (uint64_t)limit > CORE_DURABLE_LIMIT) return 3;
    int fd = core_durable_regular(path->parent, path->leaf, O_RDONLY);
    if (fd < 0) return (int)core_io_scoped_from_errno();
    struct stat info;
    if (fstat(fd, &info) || info.st_size < 0 || (uint64_t)info.st_size > (uint64_t)limit) {
        close(fd);
        return 3;
    }
    CoreIoBytes bytes = {0};
    unsigned char buffer[16384];
    int status = 0;
    while (bytes.length <= (size_t)limit) {
        size_t take = (size_t)limit - bytes.length + 1;
        if (take > sizeof buffer) take = sizeof buffer;
        ssize_t length = read(fd, buffer, take);
        if (length < 0 && errno == EINTR) continue;
        if (length < 0) { status = 3; break; }
        if (!length) break;
        if ((size_t)length > (size_t)limit - bytes.length) { status = 3; break; }
        core_io_append(&bytes, buffer, (size_t)length);
    }
    if (close(fd) && !status) status = 3;
    if (!status) *out = core_io_string(bytes.bytes, bytes.length, 0);
    free(bytes.bytes);
    return status;
}

/* A complete immediate listing, including hidden entries. Bound before growth,
 * never follow directory symlinks, and never bless a partial readdir snapshot. */
static int core_durable_listing(CoreDurablePath *path, int64_t limit, myl_block **out) {
    if (limit < 0 || limit > 4096) return 3;
    int fd = core_durable_directory(path);
    if (fd < 0) return (int)core_io_scoped_from_errno();
    DIR *directory = fdopendir(fd);
    if (!directory) { int status = (int)core_io_scoped_from_errno(); close(fd); return status; }
    myl_block *list = core_io_list_new(0);
    int status = 0;
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(directory);
        if (!entry) { if (errno) status = (int)core_io_scoped_from_errno(); break; }
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        if (list->len >= limit) { status = 3; break; }
        size_t length = strlen(entry->d_name);
        if (!length || length > 255 || !core_io_utf8((unsigned char *)entry->d_name, length)) {
            status = 5;
            break;
        }
        core_io_list_add(&list, core_io_string((unsigned char *)entry->d_name, length, 1));
    }
    if (closedir(directory) && !status) status = 3;
    if (status) myl_core_release(list);
    else *out = list;
    return status;
}

/* Register before returning the File so every ordinary exit or reference-count
 * drop closes the directory descriptor. SIGKILL also releases the kernel flock.
 * Lock the directory inode itself; no removable lockfile can split ownership. */
static int core_durable_lock(myl_block *cap, CoreDurablePath *path, myl_block **out) {
    CoreIoAuthority *authority = core_io_authority(cap);
    CoreIoState *state = core_io_state(cap);
    CoreIoScoped *scoped = state->adapter.context;
    size_t slot = core_io_scoped_free_slot(scoped);
    if (slot == SIZE_MAX || core_io_family_open[0] >= 1024) return 4;
    myl_block *block = block_new(7, sizeof(CoreIoResource), 1);
    block->len = 1;
    block->reserved = (int64_t)(intptr_t)core_io_resource_layout;
    memset(block_data(block), 0, sizeof(CoreIoResource));
    int fd = core_durable_directory(path);
    int status = fd < 0 ? (int)core_io_scoped_from_errno() : 0;
    if (!status && flock(fd, LOCK_EX | LOCK_NB)) status = 3;
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
    core_io_retain(cap);
    if (core_io_tail) core_io_tail->next = resource;
    core_io_tail = resource;
    ++core_io_open_count;
    ++core_io_family_open[0];
    *out = block;
    return 0;
}

static myl_block *core_durable_error(myl_block *path, unsigned kind, int status) {
    static const char *verbs[] = {"atomic write", "directory lock", "directory sync", "regular read", "directory listing"};
    const char *reason = status == CORE_DURABLE_UNCERTAIN
        ? "directory sync failed; publication may have occurred"
        : status == 1 ? "durable native filesystem provider is unavailable"
        : core_io_reason(status);
    size_t size = strlen(verbs[kind - CORE_DURABLE_ATOMIC]) + strlen(reason) + (size_t)path->len + 6;
    char *text = malloc(size);
    if (!text) out_of_memory();
    size_t used = (size_t)sprintf(text, "%s '", verbs[kind - CORE_DURABLE_ATOMIC]);
    memcpy(text + used, block_data(path), (size_t)path->len);
    used += (size_t)path->len;
    used += (size_t)sprintf(text + used, "': %s", reason);
    myl_block *message = core_io_string(text, used, 1);
    free(text);
    return message;
}

static int core_durable_attempt(myl_block *cap, unsigned kind, CoreDurablePath *path,
                                myl_block *input, int64_t limit, myl_block **value) {
    if (kind == CORE_DURABLE_ATOMIC) return core_durable_publish(path, input);
    if (kind == CORE_DURABLE_READ) return core_durable_read(path, limit, value);
    if (kind == CORE_DURABLE_LOCK) return core_durable_lock(cap, path, value);
    if (kind == CORE_DURABLE_LIST) return core_durable_listing(path, limit, value);
    int fd = core_durable_directory(path);
    int status = fd < 0 ? (int)core_io_scoped_from_errno() : 0;
    if (!status && core_durable_sync_fd(fd)) status = 3;
    if (fd >= 0 && close(fd) && !status) status = 3;
    return status;
}

myl_block *myl_core_durable_access(myl_block *cap, uint32_t request, myl_block *path,
                                  myl_block *input, int64_t limit) {
    CORE_IO_GUARD;
    unsigned kind = request & 255;
    if (kind < CORE_DURABLE_ATOMIC || kind > CORE_DURABLE_LIST) core_io_fail("R_FILE");
    myl_block *value = NULL;
    size_t next = 0;
    int status = kind == CORE_DURABLE_LOCK ? core_durable_unique_directory(cap, path) : 0;
    bool admitted = status == 0;
    if (admitted) status = 2;
    while (admitted) {
        CoreDurablePath resolved;
        int failure = core_durable_path(cap, path, kind, &resolved, &next, false);
        if (failure) { if (status == 2) status = failure; break; }
        status = core_durable_attempt(cap, kind, &resolved, input, limit, &value);
        close(resolved.parent);
        /* Never retry another root after a rename whose directory sync failed:
         * the first root may already contain the published value. */
        if (!status || status == 4 || status == CORE_DURABLE_UNCERTAIN) break;
    }
    if (request & (1u << 17)) {
        if (status) core_io_fail("R_FILE");
        return value;
    }
    bool pointer = kind == CORE_DURABLE_LOCK || kind == CORE_DURABLE_READ || kind == CORE_DURABLE_LIST;
    return core_io_result(status, (uint64_t)(uintptr_t)value,
                          status ? core_durable_error(path, kind, status) : NULL, pointer);
}
