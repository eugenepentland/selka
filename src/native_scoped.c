/* Directory-relative filesystem provider, mirroring src/scoped_providers.zig
   and src/scoped_directory.zig: validated relative requests, per-root write
   authority, and bounded copied metadata and listing snapshots. */
#define _POSIX_C_SOURCE 200809L
#include "native_scoped.h"
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
#define TRANSFER_LIMIT (64u * 1024u)
#define SNAPSHOT_BYTES (64u * 1024u)
#define SNAPSHOT_ENTRIES 256u
#define NAME_LIMIT 4094u
static MylangProviderStatus from_errno(void) {
    switch (errno) {
        case ENOMEM: return MYLANG_PROVIDER_OUT_OF_MEMORY;
        case EACCES: case EPERM: case ELOOP: case ENOTDIR: return MYLANG_PROVIDER_DENIED;
        default: return MYLANG_PROVIDER_FAILED;
    }
}
static int writing_mode(unsigned char mode) {
    return mode == 'w' || mode == 'a' || mode == 'c' || mode == 't' || mode == 'k' || mode == 'x';
}
/* Reject traversal before anything is opened, created or truncated. */
static int valid_path(const char *path, size_t length, unsigned char mode) {
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
static size_t free_slot(const MylangScoped *scoped) {
    for (size_t i = 0; i < MYLANG_SCOPED_HANDLES; ++i)
        if (scoped->handles[i].fd < 0 && !scoped->handles[i].snapshot) return i;
    return SIZE_MAX;
}
/* Open the parent directory of the final component without following links.
   Returns the root itself for a single-component path; the caller closes any
   other descriptor. */
static int walk(int root, const char *path, size_t length, size_t *last) {
    int parent = root;
    size_t start = 0;
    for (size_t i = 0; i < length; ++i) {
        if (path[i] != '/') continue;
        char name[NAME_LIMIT + 1];
        size_t part = i - start;
        if (part > NAME_LIMIT) { errno = ENAMETOOLONG; goto failure; }
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
static int open_leaf(int parent, const char *name, unsigned char mode, int follow) {
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
static int usable(MylangScopedRoot entry, int fd, const struct stat *info) {
    if (!entry.direct) return S_ISREG(info->st_mode) && fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) == 0;
    return !S_ISDIR(info->st_mode);
}
static unsigned char kind_of(mode_t value) {
    if (S_ISREG(value)) return 1;
    if (S_ISDIR(value)) return 2;
    if (S_ISLNK(value)) return 3;
    return 0;
}
/* Copy one directory's entries into a bounded snapshot: a leading 1, then a
   kind byte, a little-endian u16 name length and the name for each entry. */
static unsigned char *listing(int parent, const char *name, size_t *length, MylangProviderStatus *status) {
    int fd = openat(parent, *name ? name : ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) { *status = from_errno(); return NULL; }
    DIR *directory = fdopendir(fd);
    if (!directory) { *status = from_errno(); close(fd); return NULL; }
    size_t capacity = 1024, used = 1, count = 0;
    unsigned char *bytes = malloc(capacity);
    *status = MYLANG_PROVIDER_OUT_OF_MEMORY;
    if (bytes) bytes[0] = 1;
    struct dirent *entry;
    while (bytes && (errno = 0, entry = readdir(directory))) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        size_t width = strlen(entry->d_name);
        if (count >= SNAPSHOT_ENTRIES || !width || width > NAME_LIMIT) { *status = MYLANG_PROVIDER_DENIED; free(bytes); bytes = NULL; break; }
        if (used > SNAPSHOT_BYTES || width + 3 > SNAPSHOT_BYTES - used) { *status = MYLANG_PROVIDER_DENIED; free(bytes); bytes = NULL; break; }
        while (used + width + 3 > capacity) {
            unsigned char *grown = realloc(bytes, capacity * 2);
            if (!grown) { *status = MYLANG_PROVIDER_OUT_OF_MEMORY; free(bytes); bytes = NULL; break; }
            bytes = grown;
            capacity *= 2;
        }
        if (!bytes) break;
        struct stat info;
        unsigned char kind = 0;
        if (!fstatat(dirfd(directory), entry->d_name, &info, AT_SYMLINK_NOFOLLOW)) kind = kind_of(info.st_mode);
        bytes[used++] = kind;
        bytes[used++] = (unsigned char)(width & 0xff);
        bytes[used++] = (unsigned char)((width >> 8) & 0xff);
        memcpy(bytes + used, entry->d_name, width);
        used += width;
        count++;
    }
    closedir(directory);
    if (!bytes) return NULL;
    *status = MYLANG_PROVIDER_OK;
    *length = used;
    return bytes;
}
/* One acknowledged change or metadata read, published as an immutable snapshot. */
static unsigned char *change(int parent, const char *name, unsigned char mode, size_t *length, MylangProviderStatus *status) {
    struct stat info;
    if (mode == 'm') {
        int failed = *name ? fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) : fstat(parent, &info);
        if (failed) { *status = from_errno(); return NULL; }
        unsigned char *bytes = malloc(10);
        if (!bytes) { *status = MYLANG_PROVIDER_OUT_OF_MEMORY; return NULL; }
        bytes[0] = 1;
        bytes[1] = kind_of(info.st_mode);
        for (unsigned i = 0; i < 8; ++i) bytes[2 + i] = (unsigned char)(((uint64_t)info.st_size >> (8 * i)) & 0xff);
        *status = MYLANG_PROVIDER_OK;
        *length = 10;
        return bytes;
    }
    if (!*name) { *status = MYLANG_PROVIDER_DENIED; return NULL; }
    if (mode == 'k') {
        if (mkdirat(parent, name, 0777)) { *status = from_errno(); return NULL; }
    } else if (unlinkat(parent, name, 0)) {
        if (errno != EISDIR && errno != EPERM) { *status = from_errno(); return NULL; }
        if (unlinkat(parent, name, AT_REMOVEDIR)) { *status = from_errno(); return NULL; }
    }
    unsigned char *bytes = malloc(1);
    if (!bytes) { *status = MYLANG_PROVIDER_OUT_OF_MEMORY; return NULL; }
    bytes[0] = 1;
    *status = MYLANG_PROVIDER_OK;
    *length = 1;
    return bytes;
}
static MylangResourceResult acquire_in(MylangScoped *scoped, MylangScopedRoot entry, unsigned char mode, const char *path, size_t length) {
    MylangResourceResult result = {MYLANG_PROVIDER_FAILED, 0};
    int root = entry.fd;
    size_t slot = free_slot(scoped);
    if (slot == SIZE_MAX) { result.status = MYLANG_PROVIDER_DENIED; return result; }
    size_t last = 0;
    /* A direct root hands the whole path to one operation, the way an ordinary
       process resolves it; a scoped root opens each component without symlinks. */
    int parent = entry.direct ? root : walk(root, path, length, &last);
    if (parent < 0) { result.status = from_errno(); return result; }
    char name[NAME_LIMIT + 1];
    size_t width = length - last;
    if (width > NAME_LIMIT) { if (parent != root) close(parent); result.status = MYLANG_PROVIDER_DENIED; return result; }
    memcpy(name, path + last, width);
    name[width] = 0;
    if (mode == 'm' || mode == 'l' || mode == 'k' || mode == 'x') {
        size_t bytes = 0;
        unsigned char *snapshot = mode == 'l' ? listing(parent, name, &bytes, &result.status) : change(parent, name, mode, &bytes, &result.status);
        if (parent != root) close(parent);
        if (!snapshot) return result;
        scoped->handles[slot] = (MylangScopedHandle){-1, snapshot, bytes, 0, mode};
        result.handle = slot;
        return result;
    }
    int fd = open_leaf(parent, name, mode, entry.direct);
    if (parent != root) close(parent);
    if (fd < 0) { result.status = from_errno(); return result; }
    struct stat info;
    if (fstat(fd, &info)) { result.status = from_errno(); close(fd); return result; }
    if (!usable(entry, fd, &info)) { result.status = MYLANG_PROVIDER_DENIED; close(fd); return result; }
    /* Only a regular file has contents to truncate; a FIFO or device has none. */
    if (mode == 't' && S_ISREG(info.st_mode) && ftruncate(fd, 0)) { result.status = from_errno(); close(fd); return result; }
    scoped->handles[slot] = (MylangScopedHandle){fd, NULL, 0, 0, mode};
    result.status = MYLANG_PROVIDER_OK;
    result.handle = slot;
    return result;
}
static MylangResourceResult acquire(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    MylangScoped *scoped = context;
    MylangResourceResult result = {MYLANG_PROVIDER_DENIED, 0};
    if (!scoped->count) { result.status = MYLANG_PROVIDER_UNAVAILABLE; return result; }
    if (length < 2 || length > 4096 || request[1] != ':') return result;
    unsigned char mode = request[0];
    int reading = mode == 'r' || mode == 'm' || mode == 'l';
    if (!reading && !writing_mode(mode)) return result;
    if (!(permissions & (reading ? 1u : 2u))) return result;
    const char *path = (const char *)request + 2;
    size_t width = length - 2;
    MylangProviderStatus failure = MYLANG_PROVIDER_DENIED;
    for (size_t i = 0; i < scoped->count; ++i) {
        if (writing_mode(mode) && !scoped->roots[i].writable) continue;
        if (!scoped->roots[i].direct && !valid_path(path, width, mode)) continue;
        MylangResourceResult attempt = acquire_in(scoped, scoped->roots[i], mode, path, width);
        if (attempt.status == MYLANG_PROVIDER_OK || attempt.status == MYLANG_PROVIDER_OUT_OF_MEMORY) return attempt;
        failure = attempt.status;
    }
    result.status = failure;
    return result;
}
static void shut(MylangScopedHandle *handle) {
    if (handle->fd >= 0) close(handle->fd);
    free(handle->snapshot);
    *handle = (MylangScopedHandle){-1, NULL, 0, 0, 0};
}
static MylangScopedHandle *live(MylangScoped *scoped, uint64_t id) {
    if (id >= MYLANG_SCOPED_HANDLES) return NULL;
    MylangScopedHandle *handle = &scoped->handles[id];
    return handle->fd >= 0 || handle->snapshot ? handle : NULL;
}
static MylangProviderStatus complete(void *context, uint64_t id) {
    MylangScopedHandle *handle = live(context, id);
    if (!handle) return MYLANG_PROVIDER_FAILED;
    shut(handle);
    return MYLANG_PROVIDER_OK;
}
static void release(void *context, uint64_t id) {
    MylangScopedHandle *handle = live(context, id);
    if (handle) shut(handle);
}
static MylangResourceRead read_handle(void *context, uint64_t id, uint8_t *output, size_t capacity) {
    MylangResourceRead result = {MYLANG_PROVIDER_FAILED, 0, 0};
    MylangScopedHandle *handle = live(context, id);
    if (!handle) return result;
    /* A zero-size callback does not probe EOF, including immutable snapshots. */
    if (!capacity) { result.status = MYLANG_PROVIDER_OK; return result; }
    if (capacity > TRANSFER_LIMIT) capacity = TRANSFER_LIMIT;
    if (handle->snapshot) {
        size_t available = handle->length - handle->position;
        size_t width = available < capacity ? available : capacity;
        memcpy(output, handle->snapshot + handle->position, width);
        handle->position += width;
        result.status = MYLANG_PROVIDER_OK;
        result.length = width;
        result.eof = handle->position == handle->length;
        return result;
    }
    if (handle->mode == 'a') { result.status = MYLANG_PROVIDER_DENIED; return result; }
    ssize_t width = read(handle->fd, output, capacity);
    if (width < 0) { result.status = from_errno(); return result; }
    result.status = MYLANG_PROVIDER_OK;
    result.length = (size_t)width;
    result.eof = width == 0;
    return result;
}
static MylangResourceWrite write_handle(void *context, uint64_t id, const uint8_t *input, size_t length) {
    MylangResourceWrite result = {MYLANG_PROVIDER_FAILED, 0};
    MylangScopedHandle *handle = live(context, id);
    if (!handle || handle->snapshot) { result.status = handle ? MYLANG_PROVIDER_DENIED : MYLANG_PROVIDER_FAILED; return result; }
    if (length > TRANSFER_LIMIT) length = TRANSFER_LIMIT;
    ssize_t width;
    if (handle->mode == 'a') {
        off_t end = lseek(handle->fd, 0, SEEK_END);
        if (end < 0) { result.status = from_errno(); return result; }
        width = pwrite(handle->fd, input, length, end);
    } else width = write(handle->fd, input, length);
    if (width < 0) { result.status = from_errno(); return result; }
    result.status = MYLANG_PROVIDER_OK;
    result.length = (size_t)width;
    return result;
}
/* Parse one literal `IP:PORT` into a numeric address. No name resolution or
   redirect following occurs, so the grant and the connect name the same peer. */
static int endpoint_address(const char *name, struct sockaddr_in *address) {
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
static int endpoint_allowed(const MylangScoped *scoped, const char *name, size_t length) {
    for (size_t i = 0; i < scoped->endpoint_count; ++i) {
        const MylangScopedEndpoint *entry = &scoped->endpoints[i];
        if (entry->length == 1 && entry->name[0] == '*') return 1;
        if (entry->length == length && !memcmp(entry->name, name, length)) return 1;
    }
    return 0;
}
static int dial(const char *name) {
    struct sockaddr_in address;
    if (!endpoint_address(name, &address)) return -1;
    int handle = socket(AF_INET, SOCK_STREAM, 0);
    if (handle < 0) return -1;
    if (connect(handle, (struct sockaddr *)&address, sizeof address)) { close(handle); return -1; }
    return handle;
}
/* A narrowed Network substitutes its scoped endpoint for the guest request, so
   acquire sees exactly the literals the command line granted. */
static MylangResourceResult acquire_network(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    MylangScoped *scoped = context;
    MylangResourceResult result = {MYLANG_PROVIDER_DENIED, 0};
    if (!scoped->endpoint_count) { result.status = MYLANG_PROVIDER_UNAVAILABLE; return result; }
    if (!(permissions & (1u | 2u))) return result;
    char name[128];
    if (length >= sizeof name) return result;
    memcpy(name, request, length);
    name[length] = 0;
    if (!endpoint_allowed(scoped, name, length)) return result;
    size_t slot = free_slot(scoped);
    if (slot == SIZE_MAX) { result.status = MYLANG_PROVIDER_DENIED; return result; }
    int handle = dial(name);
    if (handle < 0) { result.status = MYLANG_PROVIDER_FAILED; return result; }
    scoped->handles[slot] = (MylangScopedHandle){handle, NULL, 0, 0, 0};
    result.status = MYLANG_PROVIDER_OK;
    result.handle = slot;
    return result;
}
/* Record one literal endpoint (or `*`) before the first acquisition. */
int mylang_scoped_endpoint(MylangScoped *scoped, const char *name) {
    size_t length = strlen(name);
    if (!length || length > 4096 || scoped->endpoint_count >= MYLANG_SCOPED_ENDPOINTS) return 0;
    if (!(length == 1 && name[0] == '*')) {
        struct sockaddr_in address;
        if (!endpoint_address(name, &address)) return 0;
    }
    for (size_t i = 0; i < scoped->endpoint_count; ++i) {
        const MylangScopedEndpoint *entry = &scoped->endpoints[i];
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
MylangResourceProvider mylang_scoped_network_provider(MylangScoped *scoped, unsigned permissions) {
    (void)mylang_host_charge;
    MylangResourceProvider provider = {0};
    provider.context = scoped;
    provider.permissions = permissions;
    provider.acquire = acquire_network;
    provider.complete = complete;
    provider.release = release;
    provider.read = read_handle;
    provider.write = write_handle;
    return provider;
}
void mylang_scoped_init(MylangScoped *scoped) {
    memset(scoped, 0, sizeof *scoped);
    for (size_t i = 0; i < MYLANG_SCOPED_HANDLES; ++i) scoped->handles[i].fd = -1;
}
static int grant(MylangScoped *scoped, const char *path, int writable, int direct) {
    if (scoped->count >= MYLANG_SCOPED_ROOTS) return 0;
    int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return 0;
    scoped->roots[scoped->count++] = (MylangScopedRoot){fd, writable, direct};
    return 1;
}
int mylang_scoped_grant(MylangScoped *scoped, const char *path, int writable) {
    return grant(scoped, path, writable, 0);
}
int mylang_scoped_working_directory(MylangScoped *scoped) {
    return grant(scoped, ".", 1, 1);
}
void mylang_scoped_close(MylangScoped *scoped) {
    for (size_t i = 0; i < MYLANG_SCOPED_HANDLES; ++i)
        if (scoped->handles[i].fd >= 0 || scoped->handles[i].snapshot) shut(&scoped->handles[i]);
    for (size_t i = 0; i < scoped->count; ++i) close(scoped->roots[i].fd);
    scoped->count = 0;
    for (size_t i = 0; i < scoped->endpoint_count; ++i) free(scoped->endpoints[i].name);
    scoped->endpoint_count = 0;
}
MylangResourceProvider mylang_scoped_provider(MylangScoped *scoped, unsigned permissions) {
    (void)mylang_host_charge;
    MylangResourceProvider provider = {0};
    provider.context = scoped;
    provider.permissions = permissions;
    provider.acquire = acquire;
    provider.complete = complete;
    provider.release = release;
    provider.read = read_handle;
    provider.write = write_handle;
    return provider;
}
