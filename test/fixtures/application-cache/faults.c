/* Developer-only real syscall fault injection; never linked into applications. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

static char last_publication[512];
static unsigned long matching_calls;
static int injected;

static const char *leaf(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

static int selected(const char *operation, const char *path) {
    const char *wanted_operation = getenv("W7_FAULT_OPERATION");
    const char *wanted_path = getenv("W7_FAULT_TARGET");
    if (injected || !wanted_operation || !wanted_path) return 0;
    const char *name = leaf(path);
    const char *prefix = ".myl-durable-";
    if (!strcmp(wanted_path, "@directory")) {
        if (strncmp(operation, "directory-sync-", 15)) return 0;
    } else if (!strncmp(name, prefix, strlen(prefix))) {
        name += strlen(prefix);
        if (strncmp(name, wanted_path, strlen(wanted_path)) || name[strlen(wanted_path)] != '-') return 0;
    } else if (strcmp(name, wanted_path)) return 0;
    if (strcmp(operation, wanted_operation)) return 0;
    matching_calls++;
    const char *number = getenv("W7_FAULT_OCCURRENCE");
    unsigned long wanted = number ? strtoul(number, NULL, 10) : 1;
    return wanted > 0 && matching_calls == wanted;
}

static void announce(const char *operation, const char *path) {
    const char *marker = getenv("W7_FAULT_MARKER");
    if (!marker) _exit(121);
    int fd = (int)syscall(SYS_openat, AT_FDCWD, marker, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd < 0) _exit(122);
    char message[1024];
    int length = snprintf(message, sizeof(message), "%ld\t%s\t%s\t%lu\n", (long)getpid(), operation, path, matching_calls);
    if (length < 0 || length >= (int)sizeof(message)) _exit(123);
    if (syscall(SYS_write, fd, message, (size_t)length) != length) _exit(124);
    if (syscall(SYS_fsync, fd) != 0) _exit(125);
    syscall(SYS_close, fd);
    injected = 1;
}

static void stop_at(const char *operation, const char *path) {
    if (!selected(operation, path)) return;
    announce(operation, path);
    syscall(SYS_kill, getpid(), SIGSTOP);
}

static int descriptor_path(int fd, char *path, size_t capacity) {
    char link[64];
    snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
    ssize_t size = readlink(link, path, capacity - 1);
    if (size < 0) return 0;
    path[size] = 0;
    return 1;
}

ssize_t write(int fd, const void *bytes, size_t size) {
    char path[1024];
    int named = descriptor_path(fd, path, sizeof(path));
    if (named && selected("write-error", path)) {
        announce("write-error", path);
        errno = EIO;
        return -1;
    }
    if (named) stop_at("write-before", path);
    ssize_t result = syscall(SYS_write, fd, bytes, size);
    if (named && result == (ssize_t)size) stop_at("write-after", path);
    return result;
}

int renameat(int from_dir, const char *from, int to_dir, const char *to) {
    if (selected("rename-error", to)) {
        announce("rename-error", to);
        errno = EIO;
        return -1;
    }
    stop_at("rename-before", to);
    int result = (int)syscall(SYS_renameat, from_dir, from, to_dir, to);
    if (result == 0) {
        snprintf(last_publication, sizeof(last_publication), "%s", to);
        stop_at("rename-after", to);
    }
    return result;
}

int rename(const char *from, const char *to) {
    return renameat(AT_FDCWD, from, AT_FDCWD, to);
}

int fsync(int fd) {
    struct stat state;
    int directory = fstat(fd, &state) == 0 && S_ISDIR(state.st_mode);
    char path[1024];
    const char *target = directory ? last_publication : path;
    int named = directory || descriptor_path(fd, path, sizeof(path));
    const char *error_operation = directory ? "directory-sync-error" : "file-sync-error";
    if (named && selected(error_operation, target)) {
        announce(error_operation, target);
        errno = EIO;
        return -1;
    }
    if (directory) stop_at("directory-sync-before", target);
    int result = (int)syscall(SYS_fsync, fd);
    if (result == 0 && directory) stop_at("directory-sync-after", target);
    return result;
}
