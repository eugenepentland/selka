#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#define _XOPEN_SOURCE 700
#include <stdio.h>
#include <stdarg.h>
#include <unistd.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
ssize_t durable_fixture_write(int fd, const void *bytes, size_t length);
int durable_fixture_fsync(int fd);
int durable_fixture_renameat(int oldfd, const char *old, int newfd, const char *name);
struct dirent *durable_fixture_readdir(DIR *directory);
long durable_fixture_openat2(int base, const char *path, void *how);
int durable_fixture_fstatat(int base, const char *path, struct stat *info, int flags);
int durable_fixture_openat(int base, const char *path, int flags, ...);
int durable_fixture_fcntl(int fd, int command, ...);
int durable_fixture_close(int fd);
#define CORE_DURABLE_OPENAT2(base, path, how) durable_fixture_openat2((base), (path), (how))
#define fstatat durable_fixture_fstatat
#define openat durable_fixture_openat
#define fcntl durable_fixture_fcntl
#define close durable_fixture_close
#define write durable_fixture_write
#define fsync durable_fixture_fsync
#define renameat durable_fixture_renameat
#define readdir durable_fixture_readdir
#undef _POSIX_C_SOURCE
#undef _XOPEN_SOURCE
#include "core_rt.c"
#undef write
#undef fsync
#undef renameat
#undef readdir
#undef fstatat
#undef openat
#undef fcntl
#undef close
#undef NDEBUG
#include <assert.h>
#include <sys/wait.h>
#include <sys/resource.h>

myl_block *myl_core_task_call(void *run, myl_block *env) {
    return ((myl_block *(*)(myl_block *))run)(env);
}

enum { NORMAL, PARTIAL, ZERO_WRITE, FILE_SYNC_ERROR, DIRECTORY_SYNC_ERROR,
       STOP_BEFORE_RENAME, STOP_AFTER_RENAME, DIRECTORY_READ_ERROR, NO_OPENAT2, UNKNOWN_TYPES };
static int injection;
static unsigned directory_reads;
/* The system calls the runtime made since the last `reset_calls`, for the tests that pin what a stat or a listing costs. */
static struct { unsigned fstatat, openat, openat2, fcntl, close, fsync, directory_fsync; } calls;
static void reset_calls(void) { memset(&calls, 0, sizeof calls); }

int durable_fixture_fstatat(int base, const char *path, struct stat *info, int flags) {
    ++calls.fstatat;
    return fstatat(base, path, info, flags);
}
int durable_fixture_openat(int base, const char *path, int flags, ...) {
    ++calls.openat;
    mode_t mode = 0;
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list arguments;
        va_start(arguments, flags);
        mode = va_arg(arguments, mode_t);
        va_end(arguments);
    }
    return openat(base, path, flags, mode);
}
int durable_fixture_fcntl(int fd, int command, ...) {
    ++calls.fcntl;
    va_list arguments;
    va_start(arguments, command);
    long argument = va_arg(arguments, long);
    va_end(arguments);
    return fcntl(fd, command, argument);
}
int durable_fixture_close(int fd) {
    ++calls.close;
    return close(fd);
}

ssize_t durable_fixture_write(int fd, const void *bytes, size_t length) {
    if (injection == ZERO_WRITE) return 0;
    if (injection == PARTIAL && length > 2) length = 2;
    return syscall(SYS_write, fd, bytes, length);
}
int durable_fixture_fsync(int fd) {
    ++calls.fsync;
    struct stat info;
    assert(!fstat(fd, &info));
    if (S_ISDIR(info.st_mode)) ++calls.directory_fsync;
    if ((injection == FILE_SYNC_ERROR && S_ISREG(info.st_mode)) ||
        (injection == DIRECTORY_SYNC_ERROR && S_ISDIR(info.st_mode))) {
        errno = EIO;
        return -1;
    }
    return (int)syscall(SYS_fsync, fd);
}
int durable_fixture_renameat(int oldfd, const char *old, int newfd, const char *name) {
    if (injection == STOP_BEFORE_RENAME) raise(SIGSTOP);
    int status = (int)syscall(SYS_renameat, oldfd, old, newfd, name);
    if (injection == STOP_AFTER_RENAME) raise(SIGSTOP);
    return status;
}
long durable_fixture_openat2(int base, const char *path, void *how) {
    ++calls.openat2;
    if (injection == NO_OPENAT2) {
        errno = ENOSYS;
        return -1;
    }
    return syscall(SYS_openat2, base, path, how, sizeof(struct open_how));
}
struct dirent *durable_fixture_readdir(DIR *directory) {
    if (injection == DIRECTORY_READ_ERROR && ++directory_reads > 3) {
        errno = EIO;
        return NULL;
    }
    struct dirent *entry = readdir(directory);
    /* A filesystem that reports no entry type: every record is `DT_UNKNOWN`. */
    if (entry && injection == UNKNOWN_TYPES) entry->d_type = DT_UNKNOWN;
    return entry;
}

static myl_block *text(const char *value) {
    return core_io_string((const unsigned char *)value, strlen(value), 1);
}
static myl_block *octets(const char *value) {
    return core_io_string((const unsigned char *)value, strlen(value), 0);
}
static int access_status(myl_block *cap, unsigned kind, const char *name,
                         const char *bytes, int64_t limit) {
    myl_block *path = text(name), *input = octets(bytes);
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, kind, path, input, limit);
    int status = (int)((uint64_t *)block_data(result))[0];
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
    return status;
}
static void read_exact(myl_block *cap, const char *expected) {
    myl_block *path = text("data"), *input = octets("");
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, CORE_DURABLE_READ, path, input, 64);
    uint64_t *fields = (uint64_t *)block_data(result);
    assert(!fields[0]);
    myl_block *value = (myl_block *)(uintptr_t)fields[1];
    assert((size_t)value->len == strlen(expected));
    assert(!memcmp(block_data(value), expected, strlen(expected)));
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
}
static myl_block *acquire_lock(myl_block *cap, int expected) {
    myl_block *path = text(""), *input = octets("");
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, CORE_DURABLE_LOCK, path, input, 0);
    uint64_t *fields = (uint64_t *)block_data(result);
    assert((int)fields[0] == expected);
    myl_block *owner = expected ? NULL : (myl_block *)(uintptr_t)fields[1];
    if (owner) fields[1] = 0; /* Move the resource out before dropping its result shell. */
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
    return owner;
}
static void basic(myl_block *cap) {
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "data", "old", 0));
    injection = PARTIAL;
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "data", "partial writes complete", 0));
    injection = NORMAL;
    read_exact(cap, "partial writes complete");
    assert(access_status(cap, CORE_DURABLE_READ, "data", "", 2));
    assert(access_status(cap, CORE_DURABLE_READ, "data", "", -1));
    assert(access_status(cap, CORE_DURABLE_READ, "data", "", CORE_DURABLE_LIMIT + 1));
    assert(!access_status(cap, CORE_DURABLE_SYNC, "", "", 0));
    myl_block *readonly = core_io_cap(2, 1, core_io_authority(cap)->provider, cap, NULL);
    assert(access_status(readonly, CORE_DURABLE_ATOMIC, "denied", "x", 0) == 2);
    assert(access_status(readonly, CORE_DURABLE_SYNC, "", "", 0) == 2);
    assert(access_status(readonly, CORE_DURABLE_LOCK, "", "", 0) == 2);
    assert(!access_status(readonly, CORE_DURABLE_READ, "data", "", 64));
    myl_core_drop_owned(readonly);
    myl_block *provider = core_io_provider(2, 1, 0, NULL);
    myl_block *memory = core_io_cap(2, 7, provider, NULL, NULL);
    /* A test's filesystem is durable too: the calls answer from the stand-in's entries. */
    assert(!access_status(memory, CORE_DURABLE_ATOMIC, "data", "x", 0));
    assert(!access_status(memory, CORE_DURABLE_READ, "data", "", 64));
    assert(access_status(memory, CORE_DURABLE_READ, "data", "", 0) == 3);
    myl_core_drop_owned(memory);
    puts("partial writes, exact bounded reads, permission refusal and the in-memory stand-in");
}
/* One durable call's status, and the text of a `str` answer or the ten words of a packed stat (three for a `statfs`). */
#define STAT_WORDS 10
static int answer(myl_block *cap, unsigned kind, const char *name, int64_t limit, char *text_out, uint64_t *words) {
    myl_block *path = text(name), *input = octets("");
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, kind, path, input, limit);
    uint64_t *fields = (uint64_t *)block_data(result);
    int status = (int)fields[0];
    myl_block *value = (myl_block *)(uintptr_t)fields[1];
    if (!status && text_out) snprintf(text_out, 4096, "%.*s", (int)value->len, (char *)block_data(value));
    if (!status && words) {
        assert(value->len == 8 * STAT_WORDS || value->len == 24 || value->len == 0);
        memset(words, 0, 8 * STAT_WORDS);
        if (value->len) memcpy(words, block_data(value), (size_t)value->len);
    }
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
    return status;
}
/* The absolute name of `relative` in the working directory, the granted root: a grant's canonical names are absolute, as a
   plain run's are (docs/io.md, "How a path is read"). One static buffer, read before the next call. */
static const char *granted(const char *relative) {
    static char whole[4096];
    assert(getcwd(whole, sizeof whole));
    if (*relative) assert(strlen(whole) + strlen(relative) + 2 < sizeof whole && strcat(strcat(whole, "/"), relative));
    return whole;
}
static void metadata(myl_block *cap) {
    char name[4096];
    uint64_t words[STAT_WORDS];
    struct stat info;
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "plain", "x", 0));
    assert(!mkdir("sub", 0700));
    assert(!symlink("plain", "ln") && !symlink("sub", "dirln") && !symlink("..", "esc") && !symlink("/", "abs"));
    /* A granted root answers the absolute name, following a link only while it stays inside. */
    assert(!answer(cap, CORE_DURABLE_CANONICAL, "plain", 0, name, NULL) && !strcmp(name, granted("plain")));
    assert(!answer(cap, CORE_DURABLE_CANONICAL, "ln", 0, name, NULL) && !strcmp(name, granted("plain")));
    assert(!answer(cap, CORE_DURABLE_CANONICAL, "dirln", 0, name, NULL) && !strcmp(name, granted("sub")));
    assert(!answer(cap, CORE_DURABLE_CANONICAL, "", 0, name, NULL) && !strcmp(name, granted("")));
    assert(!answer(cap, CORE_DURABLE_CANONICAL, ".", 0, name, NULL) && !strcmp(name, granted("")));
    assert(answer(cap, CORE_DURABLE_CANONICAL, "esc", 0, name, NULL) == 2);
    assert(answer(cap, CORE_DURABLE_CANONICAL, "abs", 0, name, NULL) == 2);
    assert(answer(cap, CORE_DURABLE_CANONICAL, "missing", 0, name, NULL) == 3);
    assert(answer(cap, CORE_DURABLE_CANONICAL, "a/./b", 0, name, NULL) == 3);
    assert(answer(cap, CORE_DURABLE_CANONICAL, "../x", 0, name, NULL) == 2);
    /* A kernel without openat2 gets the strict rule: no link is followed at all. */
    injection = NO_OPENAT2;
    assert(!answer(cap, CORE_DURABLE_CANONICAL, "plain", 0, name, NULL) && !strcmp(name, granted("plain")));
    assert(!answer(cap, CORE_DURABLE_CANONICAL, "", 0, name, NULL) && !strcmp(name, granted("")));
    assert(answer(cap, CORE_DURABLE_CANONICAL, "ln", 0, name, NULL) == 2);
    assert(answer(cap, CORE_DURABLE_CANONICAL, "dirln/x", 0, name, NULL) == 2);
    assert(answer(cap, CORE_DURABLE_STAT_FOLLOW, "ln", 0, NULL, words) == 2);
    injection = NORMAL;
    /* stat and stat_follow: seven words, the final component followed only by the second. */
    assert(!answer(cap, CORE_DURABLE_STAT, "ln", 0, NULL, words) && words[3] == 3);
    assert(!answer(cap, CORE_DURABLE_STAT_FOLLOW, "ln", 0, NULL, words) && words[0] == 1 && words[3] == 1);
    assert(!answer(cap, CORE_DURABLE_STAT_FOLLOW, "dirln", 0, NULL, words) && words[3] == 2);
    assert(!answer(cap, CORE_DURABLE_STAT_FOLLOW, "missing", 0, NULL, words) && words[0] == 0 && words[3] == 0);
    assert(answer(cap, CORE_DURABLE_STAT_FOLLOW, "esc", 0, NULL, words) == 2);
    /* Permissions and times; the final component is never followed. */
    assert(!answer(cap, CORE_DURABLE_CHMOD, "plain", 0640, NULL, NULL));
    assert(!stat("plain", &info) && (info.st_mode & 07777) == 0640);
    assert(!answer(cap, CORE_DURABLE_STAT, "plain", 0, NULL, words) && words[4] == 0640);
    /* The sixth word is the kernel's status-change time, in nanoseconds, which a chmod has just moved. */
    assert(!stat("plain", &info) && words[5] == (uint64_t)((int64_t)info.st_ctim.tv_sec * 1000000000 + info.st_ctim.tv_nsec));
    assert(answer(cap, CORE_DURABLE_CHMOD, "ln", 0600, NULL, NULL) == 3);
    assert(answer(cap, CORE_DURABLE_CHMOD, "plain", -1, NULL, NULL) == 3);
    assert(answer(cap, CORE_DURABLE_CHMOD, "plain", 010000, NULL, NULL) == 3);
    assert(answer(cap, CORE_DURABLE_CHMOD, "missing", 0600, NULL, NULL) == 3);
    assert(!answer(cap, CORE_DURABLE_SET_MODIFIED, "plain", 1500000000123456789LL, NULL, NULL));
    assert(!stat("plain", &info) && info.st_mtim.tv_sec == 1500000000 && info.st_mtim.tv_nsec == 123456789);
    /* The modification time is back in 2017 and the status-change time is still now: the change cannot be hidden. */
    assert(!answer(cap, CORE_DURABLE_STAT, "plain", 0, NULL, words) && words[1] == 1500000000123456789ULL && words[5] > 1700000000000000000ULL);
    assert(!answer(cap, CORE_DURABLE_SET_MODIFIED, "plain", -1500000000, NULL, NULL));
    assert(!stat("plain", &info) && info.st_mtim.tv_sec == -2 && info.st_mtim.tv_nsec == 500000000);
    assert(!answer(cap, CORE_DURABLE_TOUCH, "plain", 0, NULL, NULL));
    assert(!stat("plain", &info) && info.st_mtim.tv_sec > 1700000000);
    assert(answer(cap, CORE_DURABLE_TOUCH, "missing", 0, NULL, NULL) == 3);
    assert(access(".", F_OK) == 0 && access("missing", F_OK) != 0);
    assert(!answer(cap, CORE_DURABLE_SET_MODIFIED, "ln", 1000000000, NULL, NULL));
    assert(!lstat("ln", &info) && info.st_mtim.tv_sec == 1);
    assert(!stat("plain", &info) && info.st_mtim.tv_sec > 1700000000);
    /* symlink_path: `symlinkat` of the target text at the final component, in a root that walks no link; the target is stored as
     * written, a taken name, an empty target, a path outside the grant and a read-only grant are refused. */
    assert(!access_status(cap, CORE_DURABLE_SYMLINK, "made", "plain", 0));
    assert(!access_status(cap, CORE_DURABLE_SYMLINK, "made-abs", "/etc/passwd", 0));
    assert(!access_status(cap, CORE_DURABLE_SYMLINK, "made-nothing", "no/such/target", 0));
    char target[64];
    ssize_t width = readlink("made", target, sizeof target);
    assert(width == 5 && !memcmp(target, "plain", 5));
    width = readlink("made-abs", target, sizeof target);
    assert(width == 11 && !memcmp(target, "/etc/passwd", 11));
    assert(!lstat("made-nothing", &info) && S_ISLNK(info.st_mode) && info.st_size == 14);
    assert(!answer(cap, CORE_DURABLE_STAT, "made", 0, NULL, words) && words[3] == 3 && words[0] == 5);
    assert(!answer(cap, CORE_DURABLE_CANONICAL, "made", 0, name, NULL) && !strcmp(name, granted("plain")));
    assert(access_status(cap, CORE_DURABLE_SYMLINK, "made", "plain", 0) == 3);
    assert(access_status(cap, CORE_DURABLE_SYMLINK, "empty", "", 0) == 3 && access("empty", F_OK) != 0);
    assert(access_status(cap, CORE_DURABLE_SYMLINK, "dirln/inner", "plain", 0) == 2 && access("sub/inner", F_OK) != 0);
    assert(access_status(cap, CORE_DURABLE_SYMLINK, "../escape", "plain", 0) == 2);
    assert(access_status(cap, CORE_DURABLE_SYMLINK, "a/./b", "plain", 0) == 3);
    assert(access_status(cap, CORE_DURABLE_SYMLINK, "no/dir/ln", "plain", 0) == 3);
    /* atomic_write_file keeps 0600; the mode form creates the temporary with the mode, the umask applying. */
    mode_t before = umask(0);
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "private", "p", 0));
    assert(!stat("private", &info) && (info.st_mode & 07777) == 0600);
    assert(!access_status(cap, CORE_DURABLE_ATOMIC_MODE, "shared", "s", 0644));
    assert(!stat("shared", &info) && (info.st_mode & 07777) == 0644);
    assert(!access_status(cap, CORE_DURABLE_ATOMIC_MODE, "private", "q", 0755));
    assert(!stat("private", &info) && (info.st_mode & 07777) == 0755 && info.st_size == 1);
    umask(077);
    assert(!access_status(cap, CORE_DURABLE_ATOMIC_MODE, "masked", "m", 0666));
    assert(!stat("masked", &info) && (info.st_mode & 07777) == 0600);
    umask(before);
    assert(access_status(cap, CORE_DURABLE_ATOMIC_MODE, "bad", "b", -1) == 3);
    assert(access_status(cap, CORE_DURABLE_ATOMIC_MODE, "bad", "b", 010000) == 3);
    assert(access("bad", F_OK) != 0);
    /* The read-only grant reads names and stats but changes nothing. */
    myl_block *readonly = core_io_cap(2, 1, core_io_authority(cap)->provider, cap, NULL);
    assert(!answer(readonly, CORE_DURABLE_CANONICAL, "ln", 0, name, NULL) && !strcmp(name, granted("plain")));
    assert(!answer(readonly, CORE_DURABLE_STAT_FOLLOW, "ln", 0, NULL, words) && words[3] == 1);
    assert(answer(readonly, CORE_DURABLE_CHMOD, "plain", 0600, NULL, NULL) == 2);
    assert(answer(readonly, CORE_DURABLE_TOUCH, "plain", 0, NULL, NULL) == 2);
    assert(answer(readonly, CORE_DURABLE_SET_MODIFIED, "plain", 5, NULL, NULL) == 2);
    assert(access_status(readonly, CORE_DURABLE_SYMLINK, "ro-link", "plain", 0) == 2 && access("ro-link", F_OK) != 0);
    assert(answer(readonly, CORE_DURABLE_ATOMIC_MODE, "new", 0644, NULL, NULL) == 2);
    myl_core_drop_owned(readonly);
    myl_block *provider = core_io_provider(2, 1, 0, NULL);
    myl_block *memory = core_io_cap(2, 7, provider, NULL, NULL);
    /* A test's filesystem answers the same kinds from its own entries, with exact modes and a logical clock. */
    assert(answer(memory, CORE_DURABLE_CANONICAL, "plain", 0, name, NULL) == 3);
    assert(!answer(memory, CORE_DURABLE_ATOMIC_MODE, "plain", 0644, NULL, NULL));
    assert(!answer(memory, CORE_DURABLE_CANONICAL, "plain", 0, name, NULL) && !strcmp(name, "plain"));
    assert(!answer(memory, CORE_DURABLE_STAT_FOLLOW, "plain", 0, NULL, words) && words[3] == 1 && words[4] == 0644);
    assert(!answer(memory, CORE_DURABLE_CHMOD, "plain", 0600, NULL, NULL));
    assert(!answer(memory, CORE_DURABLE_SET_MODIFIED, "plain", 5, NULL, NULL));
    assert(!answer(memory, CORE_DURABLE_STAT, "plain", 0, NULL, words) && words[1] == 5 && words[4] == 0600);
    assert(!answer(memory, CORE_DURABLE_TOUCH, "plain", 0, NULL, NULL));
    assert(!answer(memory, CORE_DURABLE_STAT, "plain", 0, NULL, words) && words[1] > 5);
    assert(answer(memory, CORE_DURABLE_CHMOD, "plain", 010000, NULL, NULL) == 3);
    /* The status-change time is the write's reading, then a nanosecond past it for a call that leaves the clock alone. */
    assert(!answer(memory, CORE_DURABLE_ATOMIC_MODE, "stamped", 0644, NULL, NULL));
    assert(!answer(memory, CORE_DURABLE_STAT, "stamped", 0, NULL, words) && words[5] == words[1]);
    uint64_t written = words[5];
    assert(!answer(memory, CORE_DURABLE_SET_MODIFIED, "stamped", 5, NULL, NULL));
    assert(!answer(memory, CORE_DURABLE_STAT, "stamped", 0, NULL, words) && words[1] == 5 && words[5] == written + 1);
    assert(!answer(memory, CORE_DURABLE_CHMOD, "stamped", 0600, NULL, NULL));
    assert(!answer(memory, CORE_DURABLE_STAT, "stamped", 0, NULL, words) && words[5] == written + 2);
    /* A link is an entry of its own: stat says so, only the followed calls look through it, and a read refuses it. */
    assert(!access_status(memory, CORE_DURABLE_SYMLINK, "ml", "stamped", 0));
    assert(access_status(memory, CORE_DURABLE_SYMLINK, "ml", "stamped", 0) == 3);
    assert(access_status(memory, CORE_DURABLE_SYMLINK, "empty", "", 0) == 3);
    assert(!answer(memory, CORE_DURABLE_STAT, "ml", 0, NULL, words) && words[3] == 3 && words[0] == 7 && words[4] == 0777);
    assert(!answer(memory, CORE_DURABLE_STAT_FOLLOW, "ml", 0, NULL, words) && words[3] == 1 && words[4] == 0600);
    assert(!answer(memory, CORE_DURABLE_CANONICAL, "ml", 0, name, NULL) && !strcmp(name, "stamped"));
    assert(answer(memory, CORE_DURABLE_READ, "ml", 8, name, NULL) == 2 && answer(memory, CORE_DURABLE_CHMOD, "ml", 0600, NULL, NULL) == 3);
    assert(!access_status(memory, CORE_DURABLE_SYMLINK, "up", "..", 0) && !access_status(memory, CORE_DURABLE_SYMLINK, "abs", "/etc", 0));
    assert(answer(memory, CORE_DURABLE_CANONICAL, "up", 0, name, NULL) == 2 && answer(memory, CORE_DURABLE_CANONICAL, "abs", 0, name, NULL) == 2);
    myl_core_drop_owned(memory);
    puts("canonical names, followed stat, permissions, times and atomic modes");
}
/* One `read_at_path` call: `count` octets of the file `name` from `offset`, the offset packed as eight little-endian octets as the
 * typed layer packs it. Answers the status and, for a success, the octets read. */
static int window(myl_block *cap, const char *name, uint64_t offset, int64_t count, char *data, size_t *length) {
    unsigned char packed[8];
    for (unsigned i = 0; i < 8; ++i) packed[i] = (unsigned char)(offset >> (8 * i));
    myl_block *path = text(name), *input = core_io_string(packed, sizeof packed, 0);
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, CORE_DURABLE_READ_AT, path, input, count);
    uint64_t *fields = (uint64_t *)block_data(result);
    int status = (int)fields[0];
    if (!status) {
        myl_block *value = (myl_block *)(uintptr_t)fields[1];
        *length = (size_t)value->len;
        memcpy(data, block_data(value), *length);
    }
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
    return status;
}
/* The reads at one offset the real provider and the stand-in answer alike. */
static void windows(myl_block *cap) {
    char data[64];
    size_t length = 99;
    assert(!window(cap, "window", 0, 4, data, &length) && length == 4 && !memcmp(data, "0123", 4));
    assert(!window(cap, "window", 4, 4, data, &length) && length == 4 && !memcmp(data, "4567", 4));
    assert(!window(cap, "window", 8, 4, data, &length) && length == 2 && !memcmp(data, "89", 2));
    assert(!window(cap, "window", 10, 4, data, &length) && length == 0);
    assert(!window(cap, "window", 5000000, 4, data, &length) && length == 0);
    assert(!window(cap, "window", 3, 0, data, &length) && length == 0);
    assert(!window(cap, "window", 0, 64, data, &length) && length == 10 && !memcmp(data, "0123456789", 10));
    assert(window(cap, "missing", 0, 4, data, &length) == 3);
    assert(window(cap, "window", 0, -1, data, &length) == 3);
    assert(window(cap, "window", 0, CORE_DURABLE_LIMIT + 1, data, &length) == 3);
    assert(window(cap, "window", UINT64_C(0x8000000000000000), 4, data, &length) == 3);
    assert(window(cap, "a/./b", 0, 4, data, &length) == 3);
    assert(window(cap, "../a", 0, 4, data, &length) == 2);
    /* A file that only grows is read from where the last read stopped. */
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "window", "0123456789abcdef", 0));
    assert(!window(cap, "window", 10, 64, data, &length) && length == 6 && !memcmp(data, "abcdef", 6));
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "window", "0123456789", 0));
}
/* `Stat.device`, `statfs_path` and `read_at_path` on a granted directory and on the in-memory stand-in. */
static void space_and_windows(myl_block *cap) {
    uint64_t words[STAT_WORDS];
    struct stat info;
    struct statfs space;
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "window", "0123456789", 0));
    assert(!mkdir("spacedir", 0700) && !symlink("window", "spacelink"));
    /* The seventh word of a stat is the device the kernel names for the entry, which an inode needs to name a file. */
    assert(!answer(cap, CORE_DURABLE_STAT, "window", 0, NULL, words) && !stat("window", &info) && words[6] == (uint64_t)info.st_dev && words[2] == (uint64_t)info.st_ino);
    assert(!answer(cap, CORE_DURABLE_STAT, "", 0, NULL, words) && !stat(".", &info) && words[6] == (uint64_t)info.st_dev);
    assert(!answer(cap, CORE_DURABLE_STAT_FOLLOW, "spacelink", 0, NULL, words) && !stat("window", &info) && words[6] == (uint64_t)info.st_dev);
    /* The space of the filesystem that holds a path: blocks times the fragment size, the link described by the filesystem that holds it. */
    assert(!statfs(".", &space));
    const uint64_t unit = space.f_frsize ? (uint64_t)space.f_frsize : (uint64_t)space.f_bsize;
    const uint64_t size = (uint64_t)space.f_blocks * unit;
    assert(!answer(cap, CORE_DURABLE_STATFS, "", 0, NULL, words) && words[0] == size && words[2] <= words[1] && words[1] <= words[0]);
    assert(!answer(cap, CORE_DURABLE_STATFS, "window", 0, NULL, words) && words[0] == size && words[0] > 0);
    assert(!answer(cap, CORE_DURABLE_STATFS, "spacedir", 0, NULL, words) && words[0] == size);
    assert(!answer(cap, CORE_DURABLE_STATFS, "spacelink", 0, NULL, words) && words[0] == size);
    assert(!answer(cap, CORE_DURABLE_STATFS, "missing", 0, NULL, words) && words[0] == 0 && words[1] == 0 && words[2] == 0);
    assert(!answer(cap, CORE_DURABLE_STATFS, "missing/below", 0, NULL, words) && words[0] == 0);
    assert(answer(cap, CORE_DURABLE_STATFS, "../outside", 0, NULL, words) == 2);
    assert(!answer(cap, CORE_DURABLE_STATFS, "a/./b", 0, NULL, words) && words[0] == 0);
    assert(answer(cap, CORE_DURABLE_STATFS, "/etc", 0, NULL, words) == 2);
    myl_block *readonly = core_io_cap(2, 1, core_io_authority(cap)->provider, cap, NULL);
    assert(!answer(readonly, CORE_DURABLE_STATFS, "window", 0, NULL, words) && words[0] == size);
    myl_core_drop_owned(readonly);
    windows(cap);
    assert(window(cap, "spacedir", 0, 4, (char[64]){0}, &(size_t){0}) != 0);
    assert(window(cap, "spacelink", 0, 4, (char[64]){0}, &(size_t){0}) != 0);
    myl_block *provider = core_io_provider(2, 1, 0, NULL);
    myl_block *memory = core_io_cap(2, 7, provider, NULL, NULL);
    /* The stand-in has one device, one fixed space, and the same windows. */
    assert(!access_status(memory, CORE_DURABLE_ATOMIC, "window", "0123456789", 0));
    assert(!answer(memory, CORE_DURABLE_STAT, "window", 0, NULL, words) && words[6] == 1);
    assert(!answer(memory, CORE_DURABLE_STAT, "", 0, NULL, words) && words[6] == 1);
    assert(!answer(memory, CORE_DURABLE_STATFS, "window", 0, NULL, words) && words[0] == UINT64_C(1073741824) && words[1] == UINT64_C(536870912) && words[2] == UINT64_C(402653184));
    assert(!answer(memory, CORE_DURABLE_STATFS, "", 0, NULL, words) && words[0] == UINT64_C(1073741824));
    assert(!answer(memory, CORE_DURABLE_STATFS, "missing", 0, NULL, words) && words[0] == 0);
    assert(!answer(memory, CORE_DURABLE_STATFS, "a/./b", 0, NULL, words) && words[0] == 0);
    assert(answer(memory, CORE_DURABLE_STATFS, "../b", 0, NULL, words) == 2);
    windows(memory);
    myl_core_drop_owned(memory);
    puts("stat names the device, statfs the space of the filesystem that holds a path, and read_at reads from an offset");
}
static void failures(myl_block *cap) {
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "data", "old", 0));
    injection = ZERO_WRITE;
    assert(access_status(cap, CORE_DURABLE_ATOMIC, "data", "new", 0));
    injection = NORMAL;
    read_exact(cap, "old");
    pid_t limited = fork();
    assert(limited >= 0);
    if (!limited) {
        assert(signal(SIGXFSZ, SIG_IGN) != SIG_ERR);
        struct rlimit bound = {1, 1};
        assert(!setrlimit(RLIMIT_FSIZE, &bound));
        assert(access_status(cap, CORE_DURABLE_ATOMIC, "data", "size-limited", 0));
        _exit(0);
    }
    int limited_status;
    assert(waitpid(limited, &limited_status, 0) == limited);
    assert(WIFEXITED(limited_status) && WEXITSTATUS(limited_status) == 0);
    read_exact(cap, "old");
    injection = FILE_SYNC_ERROR;
    assert(access_status(cap, CORE_DURABLE_ATOMIC, "data", "new", 0));
    injection = NORMAL;
    read_exact(cap, "old");
    injection = DIRECTORY_SYNC_ERROR;
    assert(access_status(cap, CORE_DURABLE_ATOMIC, "data", "new", 0) == CORE_DURABLE_UNCERTAIN);
    injection = NORMAL;
    read_exact(cap, "new");
    assert(!mkdir("directory", 0700));
    assert(access_status(cap, CORE_DURABLE_ATOMIC, "directory", "x", 0));
    assert(!symlink("data", "link"));
    assert(access_status(cap, CORE_DURABLE_ATOMIC, "link", "x", 0));
    assert(access_status(cap, CORE_DURABLE_READ, "link", "", 64));
    assert(!mkfifo("pipe", 0600));
    assert(access_status(cap, CORE_DURABLE_READ, "pipe", "", 64));
    assert(access_status(cap, CORE_DURABLE_ATOMIC, "../escape", "x", 0) == 2);
    assert(!symlink("directory", "alias"));
    assert(access_status(cap, CORE_DURABLE_SYNC, "alias", "", 0));
    assert(access_status(cap, CORE_DURABLE_ATOMIC, "alias/x", "x", 0));
    puts("zero write and storage failure preserve old bytes; uncertain rename is explicit; special paths refused");
}
static void scopes(myl_block *cap) {
    myl_block *scope = text("directory");
    myl_block *narrowed = core_io_cap(2, 7, core_io_authority(cap)->provider, cap, scope);
    myl_core_drop_owned(scope);
    assert(!access_status(narrowed, CORE_DURABLE_ATOMIC, "data", "scoped", 0));
    read_exact(narrowed, "scoped");
    read_exact(cap, "new");
    assert(access_status(narrowed, CORE_DURABLE_READ, "../data", "", 64) == 2);
    char absolute[4095];
    assert(getcwd(absolute, sizeof absolute));
    assert(strlen(absolute) + 6 < sizeof absolute);
    strcat(absolute, "/data");
    /* A path is read as a plain run reads it and must fall inside a grant (docs/io.md, "How a path is read"): the absolute
       name of a file in the grant reads it; through a narrowing it stays refused. */
    assert(!access_status(cap, CORE_DURABLE_READ, absolute, "", 64));
    core_io_real.roots[0].direct = 1;
    assert(!access_status(cap, CORE_DURABLE_READ, absolute, "", 64));
    assert(access_status(narrowed, CORE_DURABLE_READ, absolute, "", 64) == 2);
    core_io_real.roots[0].direct = 0;
    myl_core_drop_owned(narrowed);
    core_io_embedding = 1;
    assert(access_status(cap, CORE_DURABLE_ATOMIC, "data", "x", 0) == 1);
    core_io_embedding = 0;
    myl_block *path = text("data"), *input = octets("x");
    input->len = CORE_DURABLE_LIMIT + 1;
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, CORE_DURABLE_ATOMIC, path, input, 0);
    assert(((uint64_t *)block_data(result))[0] == 3);
    input->len = 1;
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
    read_exact(cap, "new");
    assert(!mkdir("later", 0700));
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "later/other", "later root", 0));
    assert(core_io_scoped_grant(&core_io_real, "later", 1));
    /* One spelling names one file: `other` is the working directory's, which has none, and `later/other` the grant's. */
    assert(access_status(cap, CORE_DURABLE_READ, "other", "", 64) == 3);
    assert(!access_status(cap, CORE_DURABLE_READ, "later/other", "", 64));
    /* So a lease on the working directory owns the only root that reads of its paths select, the grant `later` aside. */
    myl_block *lease = acquire_lock(cap, 0);
    assert(lease);
    myl_core_drop_owned(lease);
    core_io_real.roots[1].writable = 0;
    lease = acquire_lock(cap, 0);
    assert(lease);
    myl_core_drop_owned(lease);
    close(core_io_real.roots[1].fd);
    core_io_real.count = 1;
    assert(core_io_scoped_grant(&core_io_real, ".", 0));
    myl_block *owner = acquire_lock(cap, 0);
    assert(owner);
    myl_core_drop_owned(owner);
    close(core_io_real.roots[1].fd);
    core_io_real.count = 1;
}
/* The failure text of one durable call given `bytes`, copied into `out`; the status when the call fails and zero when it succeeds. */
static int failure_text_of(myl_block *cap, unsigned kind, const char *name, const char *bytes, int64_t limit, char *out) {
    myl_block *path = text(name), *input = octets(bytes);
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, kind, path, input, limit);
    uint64_t *fields = (uint64_t *)block_data(result);
    int status = (int)fields[0];
    out[0] = 0;
    if (status) {
        myl_block *message = (myl_block *)(uintptr_t)fields[2];
        snprintf(out, 4096, "%.*s", (int)message->len, (char *)block_data(message));
    }
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
    return status;
}
/* The same for a call with no payload. */
static int failure_text(myl_block *cap, unsigned kind, const char *name, int64_t limit, char *out) {
    return failure_text_of(cap, kind, name, "", limit, out);
}
/* `read_link_path` and the owner, the group and the hard links of a stat, on a granted directory and on the in-memory stand-in. */
static void links_and_owners(myl_block *cap) {
    uint64_t words[STAT_WORDS];
    char found[4096], message[4096];
    struct stat info;
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "rl-file", "hello", 0));
    assert(!mkdir("rl-dir", 0700) && !mkdir("rl-dir/inner", 0700));
    assert(!symlink("rl-file", "rl-rel") && !symlink("/no/such/place", "rl-abs") && !symlink("rl-rel", "rl-chain"));
    assert(!symlink("rl-dir", "rl-dirln") && !symlink("../outside", "rl-esc") && !symlink("rl-file", "rl-dir/inside") && !symlink("\xff\xfe", "rl-bad"));
    /* The text is what the link stores, whatever it names and however many links lie behind it. */
    assert(!answer(cap, CORE_DURABLE_READ_LINK, "rl-rel", 0, found, NULL) && !strcmp(found, "rl-file"));
    assert(!answer(cap, CORE_DURABLE_READ_LINK, "rl-abs", 0, found, NULL) && !strcmp(found, "/no/such/place"));
    assert(!answer(cap, CORE_DURABLE_READ_LINK, "rl-chain", 0, found, NULL) && !strcmp(found, "rl-rel"));
    assert(!answer(cap, CORE_DURABLE_READ_LINK, "rl-esc", 0, found, NULL) && !strcmp(found, "../outside"));
    assert(!answer(cap, CORE_DURABLE_READ_LINK, "rl-dirln", 0, found, NULL) && !strcmp(found, "rl-dir"));
    assert(!answer(cap, CORE_DURABLE_READ_LINK, "rl-dir/inside", 0, found, NULL) && !strcmp(found, "rl-file"));
    /* An entry that is not a link, nothing at the path, a link on the way, a path outside the grant and a target that is not text. */
    assert(failure_text(cap, CORE_DURABLE_READ_LINK, "rl-file", 0, message) == 3 && !strcmp(message, "read link 'rl-file': is not a symbolic link"));
    assert(failure_text(cap, CORE_DURABLE_READ_LINK, "rl-dir", 0, message) == 3 && !strcmp(message, "read link 'rl-dir': is not a symbolic link"));
    assert(failure_text(cap, CORE_DURABLE_READ_LINK, "", 0, message) == 3 && !strcmp(message, "read link '': is not a symbolic link"));
    assert(failure_text(cap, CORE_DURABLE_READ_LINK, "rl-nothing", 0, message) == 3 && !strcmp(message, "read link 'rl-nothing': the path does not exist"));
    assert(failure_text(cap, CORE_DURABLE_READ_LINK, "rl-nodir/x", 0, message) == 3 && strstr(message, "the path does not exist"));
    assert(failure_text(cap, CORE_DURABLE_READ_LINK, "rl-dirln/inside", 0, message) == 2 && strstr(message, "is a symbolic link the sandbox does not follow"));
    assert(failure_text(cap, CORE_DURABLE_READ_LINK, "/rl-rel", 0, message) == 2 && !failure_text(cap, CORE_DURABLE_READ_LINK, "rl-dir/../rl-rel", 0, message));
    assert(failure_text(cap, CORE_DURABLE_READ_LINK, "rl-bad", 0, message) == 5 && !strcmp(message, "read link 'rl-bad': the bytes read are not valid UTF-8 text"));
    /* A read-only grant reads a link's text too. */
    myl_block *readonly = core_io_cap(2, 1, core_io_authority(cap)->provider, cap, NULL);
    assert(!answer(readonly, CORE_DURABLE_READ_LINK, "rl-esc", 0, found, NULL) && !strcmp(found, "../outside"));
    assert(failure_text(readonly, CORE_DURABLE_READ_LINK, "rl-file", 0, message) == 3);
    myl_core_drop_owned(readonly);
    /* The eighth to tenth words are what the kernel keeps: the user, the group and the number of hard links. */
    assert(!link("rl-file", "rl-second"));
    assert(!answer(cap, CORE_DURABLE_STAT, "rl-file", 0, NULL, words) && !lstat("rl-file", &info));
    assert(words[7] == (uint64_t)info.st_uid && words[8] == (uint64_t)info.st_gid && words[9] == 2 && info.st_nlink == 2);
    assert(!answer(cap, CORE_DURABLE_STAT, "rl-dir", 0, NULL, words) && !lstat("rl-dir", &info) && words[9] == (uint64_t)info.st_nlink);
    assert(!answer(cap, CORE_DURABLE_STAT, "rl-rel", 0, NULL, words) && !lstat("rl-rel", &info) && words[7] == (uint64_t)info.st_uid && words[9] == 1);
    assert(!answer(cap, CORE_DURABLE_STAT_FOLLOW, "rl-rel", 0, NULL, words) && !stat("rl-file", &info) && words[7] == (uint64_t)info.st_uid && words[9] == 2);
    /* A test's filesystem answers the same call from its entries: the text stored, the owner 1000, the group 1000 and one link. */
    myl_block *provider = core_io_provider(2, 1, 0, NULL);
    myl_block *memory = core_io_cap(2, 7, provider, NULL, NULL);
    assert(!access_status(memory, CORE_DURABLE_ATOMIC, "mfile", "x", 0));
    assert(!access_status(memory, CORE_DURABLE_SYMLINK, "mlink", "../mfile", 0));
    assert(!answer(memory, CORE_DURABLE_READ_LINK, "mlink", 0, found, NULL) && !strcmp(found, "../mfile"));
    assert(failure_text(memory, CORE_DURABLE_READ_LINK, "mfile", 0, message) == 3 && !strcmp(message, "read link 'mfile': is not a symbolic link"));
    assert(failure_text(memory, CORE_DURABLE_READ_LINK, "", 0, message) == 3 && !strcmp(message, "read link '': is not a symbolic link"));
    assert(failure_text(memory, CORE_DURABLE_READ_LINK, "mnothing", 0, message) == 3 && !strcmp(message, "read link 'mnothing': the path does not exist"));
    assert(failure_text(memory, CORE_DURABLE_READ_LINK, "mlink/x", 0, message) == 2 && strstr(message, "is a symbolic link the sandbox does not follow"));
    assert(failure_text(memory, CORE_DURABLE_READ_LINK, "a/./b", 0, message) == 3);
    assert(!answer(memory, CORE_DURABLE_STAT, "mfile", 0, NULL, words) && words[7] == 1000 && words[8] == 1000 && words[9] == 1);
    assert(!answer(memory, CORE_DURABLE_STAT, "mlink", 0, NULL, words) && words[7] == 1000 && words[8] == 1000 && words[9] == 1 && words[3] == 3);
    assert(!answer(memory, CORE_DURABLE_STAT, "", 0, NULL, words) && words[9] == 2);
    myl_core_drop_owned(memory);
    puts("read_link names the text a link stores and refuses what stat refuses, and stat names the owner, the group and the hard links");
}
/* `link_path` and `mkdir_mode` on a granted directory and on the in-memory stand-in: a second name for one file that counts its links, a
 * source that must be a regular file, both names inside the grant, and a folder made with its mode. */
static void hard_links_and_modes(myl_block *cap) {
    uint64_t words[STAT_WORDS], other[STAT_WORDS];
    char message[4096];
    struct stat info, second;
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "hl-file", "hello", 0));
    assert(!mkdir("hl-dir", 0700) && !mkfifo("hl-fifo", 0600));
    assert(!symlink("hl-file", "hl-rel") && !symlink("hl-dir", "hl-dirln") && !symlink("hl-file", "hl-dir/inside"));
    /* The new name is the same file: one inode, two links, and the kernel agrees. */
    assert(!access_status(cap, CORE_DURABLE_LINK, "hl-file", "hl-second", 0));
    assert(!lstat("hl-file", &info) && !lstat("hl-second", &second) && info.st_ino == second.st_ino && info.st_nlink == 2);
    assert(!answer(cap, CORE_DURABLE_STAT, "hl-file", 0, NULL, words) && !answer(cap, CORE_DURABLE_STAT, "hl-second", 0, NULL, other));
    assert(words[2] == other[2] && words[9] == 2 && other[9] == 2);
    assert(!access_status(cap, CORE_DURABLE_LINK, "hl-second", "hl-dir/third", 0) && !lstat("hl-file", &info) && info.st_nlink == 3);
    /* A source that is not a regular file is refused in the words of a refused publication, and no name is made. */
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "hl-dir", "hl-x", 0, message) == 2 && !strcmp(message, "link 'hl-dir' to 'hl-x': is a directory"));
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "hl-rel", "hl-x", 0, message) == 2 &&
           !strcmp(message, "link 'hl-rel' to 'hl-x': is a symbolic link the sandbox does not follow, or links nest too deeply"));
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "hl-fifo", "hl-x", 0, message) == 2 && !strcmp(message, "link 'hl-fifo' to 'hl-x': is not a regular file"));
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "hl-dirln/inside", "hl-x", 0, message) == 2 && strstr(message, "a parent of the path is not a directory"));
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "hl-file", "hl-dirln/x", 0, message) == 2 && strstr(message, "a parent of the path is not a directory"));
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "", "hl-x", 0, message) == 2 && strstr(message, "is a directory"));
    assert(lstat("hl-x", &info) && errno == ENOENT);
    /* A taken name, a missing source and a missing folder fail as the system's call does. */
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "hl-file", "hl-second", 0, message) == 3 && !strcmp(message, "link 'hl-file' to 'hl-second': already exists"));
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "hl-nothing", "hl-x", 0, message) == 3 && !strcmp(message, "link 'hl-nothing' to 'hl-x': the path does not exist"));
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "hl-file", "hl-nodir/x", 0, message) == 3 && strstr(message, "the path does not exist"));
    /* Neither end leaves the grant, and a read-only capability links nothing. */
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "/etc/hostname", "hl-x", 0, message) == 2 && strstr(message, "is outside the granted directories"));
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "hl-file", "/tmp/hl-x", 0, message) == 2 && strstr(message, "is outside the granted directories"));
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "../hl-file", "hl-x", 0, message) == 2 && strstr(message, "is outside the granted directories"));
    assert(failure_text_of(cap, CORE_DURABLE_LINK, "hl-file", "../hl-x", 0, message) == 2 && strstr(message, "is outside the granted directories"));
    myl_block *readonly = core_io_cap(2, 1, core_io_authority(cap)->provider, cap, NULL);
    assert(access_status(readonly, CORE_DURABLE_LINK, "hl-file", "hl-x", 0) == 2 && access_status(readonly, CORE_DURABLE_MKDIR_MODE, "hl-made", "", 0700) == 2);
    myl_core_drop_owned(readonly);
    assert(lstat("hl-x", &info) && lstat("hl-made", &info));
    /* A folder is made with its mode at creation: a mode no umask could give a folder the process then changes is there at once. */
    assert(!access_status(cap, CORE_DURABLE_MKDIR_MODE, "hl-private", "", 0700) && !lstat("hl-private", &info) && S_ISDIR(info.st_mode) && (info.st_mode & 0777) == 0700);
    assert(!access_status(cap, CORE_DURABLE_MKDIR_MODE, "hl-closed", "", 0) && !lstat("hl-closed", &info) && (info.st_mode & 07777) == 0);
    assert(!access_status(cap, CORE_DURABLE_MKDIR_MODE, "hl-slash/", "", 0500) && !lstat("hl-slash", &info) && (info.st_mode & 0777) == 0500);
    assert(!access_status(cap, CORE_DURABLE_CHMOD, "hl-closed", "", 0755) && !lstat("hl-closed", &info) && (info.st_mode & 0777) == 0755);
    assert(failure_text(cap, CORE_DURABLE_MKDIR_MODE, "hl-private", 0700, message) == 3 && !strcmp(message, "mkdir 'hl-private': already exists"));
    assert(failure_text(cap, CORE_DURABLE_MKDIR_MODE, "hl-file", 0700, message) == 3 && !strcmp(message, "mkdir 'hl-file': already exists"));
    assert(failure_text(cap, CORE_DURABLE_MKDIR_MODE, "hl-dir/..", 0700, message) == 3 && !strcmp(message, "mkdir 'hl-dir/..': already exists"));
    assert(failure_text(cap, CORE_DURABLE_MKDIR_MODE, "hl-nodir/x", 0700, message) == 3 && !strcmp(message, "mkdir 'hl-nodir/x': the parent directory does not exist"));
    assert(failure_text(cap, CORE_DURABLE_MKDIR_MODE, "hl-file/x", 0700, message) == 2 && strstr(message, "a parent of the path is not a directory"));
    assert(failure_text(cap, CORE_DURABLE_MKDIR_MODE, "hl-dirln/x", 0700, message) == 2 && strstr(message, "a parent of the path is not a directory"));
    assert(failure_text(cap, CORE_DURABLE_MKDIR_MODE, "hl-bad", 010000, message) == 3 && !strcmp(message, "mkdir 'hl-bad': the mode must be between 0 and 0o7777"));
    assert(failure_text(cap, CORE_DURABLE_MKDIR_MODE, "hl-bad", -1, message) == 3 && lstat("hl-bad", &info));
    assert(failure_text(cap, CORE_DURABLE_MKDIR_MODE, "/tmp/hl-bad", 0700, message) == 2 && strstr(message, "is outside the granted directories"));
    assert(failure_text(cap, CORE_DURABLE_MKDIR_MODE, "../hl-bad", 0700, message) == 2 && strstr(message, "is outside the granted directories"));
    /* A test's filesystem answers both from its entries: one shared file, a count of links, and the mode as given. */
    myl_block *provider = core_io_provider(2, 1, 0, NULL);
    myl_block *memory = core_io_cap(2, 7, provider, NULL, NULL);
    assert(!access_status(memory, CORE_DURABLE_ATOMIC, "mfile", "x", 0));
    assert(!access_status(memory, CORE_DURABLE_LINK, "mfile", "msecond", 0));
    assert(!answer(memory, CORE_DURABLE_STAT, "mfile", 0, NULL, words) && !answer(memory, CORE_DURABLE_STAT, "msecond", 0, NULL, other));
    assert(words[2] == other[2] && words[9] == 2 && other[9] == 2);
    assert(failure_text_of(memory, CORE_DURABLE_LINK, "mfile", "msecond", 0, message) == 3 && !strcmp(message, "link 'mfile' to 'msecond': already exists"));
    assert(!access_status(memory, CORE_DURABLE_MKDIR_MODE, "mdir", "", 0750) && !answer(memory, CORE_DURABLE_STAT, "mdir", 0, NULL, words));
    assert(words[3] == 2 && words[4] == 0750 && words[9] == 2);
    assert(failure_text_of(memory, CORE_DURABLE_LINK, "mdir", "mx", 0, message) == 2 && !strcmp(message, "link 'mdir' to 'mx': is a directory"));
    assert(failure_text(memory, CORE_DURABLE_MKDIR_MODE, "mdir", 0700, message) == 3 && !strcmp(message, "mkdir 'mdir': already exists"));
    assert(failure_text(memory, CORE_DURABLE_MKDIR_MODE, "mnone/x", 0700, message) == 3 && !strcmp(message, "mkdir 'mnone/x': the parent directory does not exist"));
    myl_core_drop_owned(memory);
    puts("link_path makes a second name for a regular file inside the grants and mkdir_mode makes a folder with its mode");
}
/* The number of names a listing answers, or -1 when it fails. */
static int64_t listed(myl_block *cap, const char *name, int64_t limit) {
    myl_block *path = text(name), *input = octets("");
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, CORE_DURABLE_LIST, path, input, limit);
    uint64_t *fields = (uint64_t *)block_data(result);
    int64_t count = fields[0] ? -1 : ((myl_block *)(uintptr_t)fields[1])->len;
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
    return count;
}
static void listings(myl_block *cap) {
    for (unsigned index = 0; index < 300; ++index) {
        char name[32];
        assert(snprintf(name, sizeof name, "many-%u", index) > 0);
        int fd = open(name, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0600);
        assert(fd >= 0 && !close(fd));
    }
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, ".hidden", "x", 0));
    assert(access_status(cap, CORE_DURABLE_LIST, "", "", 256));
    assert(access_status(cap, CORE_DURABLE_LIST, "", "", -1));
    /* The bound is the caller's, not a ceiling of the provider's: 4,097 and more are fine, and a bound the directory
     * outgrows names itself rather than the grants. */
    assert(!access_status(cap, CORE_DURABLE_LIST, "", "", 4097));
    char message[4096];
    assert(failure_text(cap, CORE_DURABLE_LIST, "", 256, message) == CORE_DURABLE_BOUND);
    assert(!strcmp(message, "directory listing '': has more than 256 entries (the max_entries bound)"));
    assert(failure_text(cap, CORE_DURABLE_LIST, "", -1, message) == CORE_DURABLE_BOUND);
    assert(!strcmp(message, "directory listing '': max_entries must not be negative"));
    assert(access_status(cap, CORE_DURABLE_LIST, "alias", "", 4096));
    myl_block *path = text(""), *input = octets("");
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, CORE_DURABLE_LIST, path, input, 4096);
    uint64_t *fields = (uint64_t *)block_data(result);
    assert(!fields[0]);
    myl_block *list = (myl_block *)(uintptr_t)fields[1];
    assert(list->len > 300 && list->len < 4096);
    myl_block **items = (myl_block **)block_data(list);
    bool hidden = false;
    for (int64_t i = 0; i < list->len; ++i)
        if (items[i]->len == 7 && !memcmp(block_data(items[i]), ".hidden", 7)) hidden = true;
    assert(hidden);
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
    /* Past 4,096 entries: the names list whole under a bound of 8,192, and a bound they outgrow names itself. */
    const int64_t before = listed(cap, "", 4096);
    assert(before > 300 && before < 4096);
    const int64_t total = before + 4800;
    for (unsigned index = 0; index < 4800; ++index) {
        char name[32];
        assert(snprintf(name, sizeof name, "big-%u", index) > 0);
        int fd = open(name, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0600);
        assert(fd >= 0 && !close(fd));
    }
    assert(listed(cap, "", 8192) == total);
    assert(listed(cap, "", total) == total);
    assert(listed(cap, "", total - 1) == -1);
    assert(failure_text(cap, CORE_DURABLE_LIST, "", 4999, message) == CORE_DURABLE_BOUND);
    assert(!strcmp(message, "directory listing '': has more than 4999 entries (the max_entries bound)"));
    for (unsigned index = 0; index < 4800; ++index) {
        char name[32];
        assert(snprintf(name, sizeof name, "big-%u", index) > 0);
        assert(!unlink(name));
    }
    injection = DIRECTORY_READ_ERROR;
    directory_reads = 0;
    assert(access_status(cap, CORE_DURABLE_LIST, "", "", 4096));
    injection = NORMAL;
    for (unsigned index = 0; index < 300; ++index) {
        char name[32];
        assert(snprintf(name, sizeof name, "many-%u", index) > 0);
        assert(!unlink(name));
    }
    assert(!unlink(".hidden"));
    puts("complete bounded directory snapshot includes hidden entries beyond 256 and 4096, names its bound, and refuses partial readdir");
}
/* The kind of the entry called `name` in packed listing octets, or -1 when it is not there. */
static int entry_kind(const unsigned char *packed, size_t length, const char *name) {
    size_t at = 0, width = strlen(name);
    while (at + 3 <= length) {
        size_t size = (size_t)packed[at + 1] | ((size_t)packed[at + 2] << 8);
        if (size == width && !memcmp(packed + at + 3, name, width)) return packed[at];
        at += 3 + size;
    }
    return -1;
}
/* The entries of a directory, packed: the number of entries, with the kind of each of the five named by the caller
 * written to `kinds` (-1 for a name that is missing); -1 when the listing fails. */
static int64_t packed_entries(myl_block *cap, const char *directory, const char *const names[5], int kinds[5]) {
    myl_block *path = text(directory), *input = octets("");
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, CORE_DURABLE_LIST_ENTRIES, path, input, 0);
    uint64_t *fields = (uint64_t *)block_data(result);
    int64_t count = -1;
    if (!fields[0]) {
        myl_block *value = (myl_block *)(uintptr_t)fields[1];
        const unsigned char *packed = block_data(value);
        count = 0;
        for (size_t at = 0; at + 3 <= (size_t)value->len; at += 3 + ((size_t)packed[at + 1] | ((size_t)packed[at + 2] << 8))) ++count;
        for (int i = 0; i < 5; ++i) kinds[i] = entry_kind(packed, (size_t)value->len, names[i]);
    }
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
    return count;
}
static void stat_cost(myl_block *cap) {
    uint64_t words[STAT_WORDS];
    assert(!mkdir("cost", 0700) && !mkdir("cost/b", 0700) && !mkdir("cost/b/c", 0700));
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "cost/b/c/f.txt", "abc", 0));
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "cost/top.txt", "abc", 0));
    assert(!symlink("b", "cost/ln"));
    /* A granted root: a path of one component is one fstatat; a deeper one adds a single confined openat2 and the close of
     * the descriptor it returns, however deep the path is. No descriptor is duplicated. */
    reset_calls();
    assert(!answer(cap, CORE_DURABLE_STAT, "cost", 0, NULL, words) && words[3] == 2);
    assert(calls.fstatat == 1 && calls.openat == 0 && calls.openat2 == 0 && calls.fcntl == 0 && calls.close == 0);
    reset_calls();
    assert(!answer(cap, CORE_DURABLE_STAT, "cost/b/c/f.txt", 0, NULL, words) && words[0] == 3 && words[3] == 1);
    assert(calls.fstatat == 1 && calls.openat2 == 1 && calls.close == 1 && calls.openat == 0 && calls.fcntl == 0);
    reset_calls();
    assert(!answer(cap, CORE_DURABLE_STAT, "cost/b/c/missing", 0, NULL, words) && words[3] == 0);
    assert(!answer(cap, CORE_DURABLE_STAT, "cost/nowhere/x/y", 0, NULL, words) && words[3] == 0);
    /* The refusals are the walk's: a link on the way is denied, a file on the way is not a directory, a link at the end
     * is itself. */
    assert(answer(cap, CORE_DURABLE_STAT, "cost/ln/c/f.txt", 0, NULL, words) == 2);
    assert(answer(cap, CORE_DURABLE_STAT, "cost/top.txt/x", 0, NULL, words) == 2);
    assert(!answer(cap, CORE_DURABLE_STAT, "cost/ln", 0, NULL, words) && words[3] == 3);
    /* The unrestricted root hands the whole path to one fstatat and follows the links on the way. */
    core_io_real.roots[0].direct = 1;
    reset_calls();
    assert(!answer(cap, CORE_DURABLE_STAT, "cost/b/c/f.txt", 0, NULL, words) && words[0] == 3 && words[3] == 1);
    assert(calls.fstatat == 1 && calls.openat == 0 && calls.openat2 == 0 && calls.fcntl == 0 && calls.close == 0);
    assert(!answer(cap, CORE_DURABLE_STAT, "cost/ln/c/f.txt", 0, NULL, words) && words[0] == 3 && words[3] == 1);
    assert(!answer(cap, CORE_DURABLE_STAT, "cost/ln", 0, NULL, words) && words[3] == 3);
    char absolute[4095];
    assert(getcwd(absolute, sizeof absolute) && strlen(absolute) + 20 < sizeof absolute);
    strcat(absolute, "/cost/top.txt");
    reset_calls();
    assert(!answer(cap, CORE_DURABLE_STAT, absolute, 0, NULL, words) && words[0] == 3 && words[3] == 1);
    assert(calls.fstatat == 1 && calls.openat == 0 && calls.fcntl == 0 && calls.close == 0);
    assert(answer(cap, CORE_DURABLE_STAT, "cost/top.txt/x", 0, NULL, words) == 2);
    assert(!answer(cap, CORE_DURABLE_STAT, "cost/nowhere/x/y", 0, NULL, words) && words[3] == 0);
    core_io_real.roots[0].direct = 0;
    /* A kernel without openat2 walks the prefix component by component and refuses a link the same way. */
    injection = NO_OPENAT2;
    reset_calls();
    assert(!answer(cap, CORE_DURABLE_STAT, "cost/b/c/f.txt", 0, NULL, words) && words[0] == 3 && words[3] == 1);
    assert(calls.openat == 3 && calls.fstatat == 1);
    assert(answer(cap, CORE_DURABLE_STAT, "cost/ln/c/f.txt", 0, NULL, words) == 2);
    injection = NORMAL;
    /* A listing opens the directory once and nothing else: a descriptor of the root's own is lent, never duplicated. */
    static const char *const none[5] = {"", "", "", "", ""};
    int unused[5];
    reset_calls();
    assert(packed_entries(cap, "cost", none, unused) == 3);
    assert(calls.openat == 1 && calls.fcntl == 0 && calls.close == 0 && calls.openat2 == 0 && calls.fstatat == 0);
    reset_calls();
    assert(packed_entries(cap, "cost/b/c", none, unused) == 1);
    assert(calls.openat2 == 1 && calls.openat == 1 && calls.close == 1 && calls.fcntl == 0);
    core_io_real.roots[0].direct = 1;
    reset_calls();
    assert(packed_entries(cap, "cost/b/c", none, unused) == 1);
    assert(calls.openat == 1 && calls.openat2 == 0 && calls.fcntl == 0 && calls.close == 0);
    core_io_real.roots[0].direct = 0;
    assert(listed(cap, "cost", 10) == 3);
    assert(!unlink("cost/ln"));
    puts("stat opens no descriptor of its own: one fstatat from the root, one confined openat2 below it");
}
static void entries(myl_block *cap) {
    static const char *const names[5] = {"reg", "dir", "lnk", "dangling", "pipe"};
    int kinds[5];
    assert(!mkdir("kinds", 0700) && !mkdir("kinds/dir", 0700));
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "kinds/reg", "x", 0));
    assert(!symlink("reg", "kinds/lnk") && !symlink("nothing", "kinds/dangling") && !mkfifo("kinds/pipe", 0600));
    /* The kind comes with the directory record: no stat of any entry. */
    reset_calls();
    assert(packed_entries(cap, "kinds", names, kinds) == 5);
    assert(kinds[0] == 1 && kinds[1] == 2 && kinds[2] == 3 && kinds[3] == 3 && kinds[4] == 0);
    assert(calls.fstatat == 0);
    /* A filesystem whose records carry no type costs one fstatat for each entry and answers the same kinds. */
    injection = UNKNOWN_TYPES;
    reset_calls();
    assert(packed_entries(cap, "kinds", names, kinds) == 5);
    assert(kinds[0] == 1 && kinds[1] == 2 && kinds[2] == 3 && kinds[3] == 3 && kinds[4] == 0);
    assert(calls.fstatat == 5);
    injection = NORMAL;
    /* The refusals are a listing's: a file is not a directory, a link to a directory is not entered, nothing is missing. */
    char message[4096];
    assert(failure_text(cap, CORE_DURABLE_LIST_ENTRIES, "kinds/reg", 0, message) == 2);
    assert(!strcmp(message, "directory listing 'kinds/reg': is not a directory"));
    assert(failure_text(cap, CORE_DURABLE_LIST_ENTRIES, "kinds/lnk", 0, message));
    assert(failure_text(cap, CORE_DURABLE_LIST_ENTRIES, "kinds/none", 0, message) == 3);
    assert(!strcmp(message, "directory listing 'kinds/none': the path does not exist"));
    myl_block *readonly = core_io_cap(2, 1, core_io_authority(cap)->provider, cap, NULL);
    assert(packed_entries(readonly, "kinds", names, kinds) == 5);
    myl_core_drop_owned(readonly);
    assert(!unlink("kinds/reg") && !unlink("kinds/lnk") && !unlink("kinds/dangling") && !unlink("kinds/pipe") && !rmdir("kinds/dir") && !rmdir("kinds"));
    myl_block *provider = core_io_provider(2, 1, 0, NULL);
    myl_block *memory = core_io_cap(2, 7, provider, NULL, NULL);
    /* A test's filesystem answers the same call, sorted, with the kinds of its own entries. */
    assert(!access_status(memory, CORE_DURABLE_ATOMIC, "reg", "x", 0));
    myl_block *path = text(""), *input = octets("");
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)memory, CORE_DURABLE_LIST_ENTRIES, path, input, 0);
    uint64_t *fields = (uint64_t *)block_data(result);
    assert(!fields[0]);
    myl_block *value = (myl_block *)(uintptr_t)fields[1];
    assert(value->len == 6 && entry_kind(block_data(value), 6, "reg") == 1);
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
    myl_core_drop_owned(memory);
    puts("a listing carries each entry's kind from the directory record, one fstatat only without a type");
}
static void kill_publication(myl_block *cap, unsigned kind, int phase, const char *expected) {
    assert(!access_status(cap, kind, "data", "old", 0));
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        injection = phase;
        (void)access_status(cap, kind, "data", "new", 0);
        _exit(1);
    }
    int status;
    assert(waitpid(child, &status, WUNTRACED) == child);
    assert(WIFSTOPPED(status));
    assert(!kill(child, SIGKILL));
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL);
    read_exact(cap, expected);
    assert(!access_status(cap, kind, "data", "recovered", 0));
    read_exact(cap, "recovered");
}
static void crashes(myl_block *cap) {
    kill_publication(cap, CORE_DURABLE_ATOMIC, STOP_BEFORE_RENAME, "old");
    kill_publication(cap, CORE_DURABLE_ATOMIC, STOP_AFTER_RENAME, "new");
    kill_publication(cap, CORE_DURABLE_REPLACE, STOP_BEFORE_RENAME, "old");
    kill_publication(cap, CORE_DURABLE_REPLACE, STOP_AFTER_RENAME, "new");
    kill_publication(cap, CORE_DURABLE_REPLACE_SYNCED, STOP_BEFORE_RENAME, "old");
    kill_publication(cap, CORE_DURABLE_REPLACE_SYNCED, STOP_AFTER_RENAME, "new");
    puts("actual SIGKILL before and after publication preserves complete old or new bytes and permits recovery");
}
/* The file `name` holds exactly `expected`. */
static void read_named(myl_block *cap, const char *name, const char *expected) {
    myl_block *path = text(name), *input = octets("");
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, CORE_DURABLE_READ, path, input, 64);
    uint64_t *fields = (uint64_t *)block_data(result);
    assert(!fields[0]);
    myl_block *value = (myl_block *)(uintptr_t)fields[1];
    assert((size_t)value->len == strlen(expected) && !memcmp(block_data(value), expected, strlen(expected)));
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
}
/* How many temporaries a publication left in the working directory. */
static unsigned leftover_temporaries(void) {
    DIR *directory = opendir(".");
    assert(directory);
    unsigned found = 0;
    for (struct dirent *entry; (entry = readdir(directory));) if (!strncmp(entry->d_name, ".myl-durable-", 13)) ++found;
    closedir(directory);
    return found;
}
/* The behaviour every replacement shares: whole publication through a temporary, the permissions, the refusals, the test's
 * filesystem. `plain` and `with_mode` are the pair under test and `file_syncs` how many files it forces to disk (0 for
 * `replace_file`, 1 for `replace_file_synced`); none of the pair syncs the directory, which only `atomic_write_file` does. */
static void replacement_behaviour(myl_block *cap, unsigned plain, unsigned with_mode, unsigned file_syncs) {
    struct stat info;
    reset_calls();
    assert(!access_status(cap, plain, "swap", "one", 0));
    assert(calls.fsync == file_syncs && calls.directory_fsync == 0);
    read_named(cap, "swap", "one");
    reset_calls();
    assert(!access_status(cap, with_mode, "swap", "two", 0644));
    assert(calls.fsync == file_syncs && calls.directory_fsync == 0);
    read_named(cap, "swap", "two");
    reset_calls();
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "swap", "three", 0));
    assert(calls.fsync == 2 && calls.directory_fsync == 1);
    read_named(cap, "swap", "three");
    /* The temporary is renamed over the destination or removed: nothing is left behind, on success or failure. */
    assert(leftover_temporaries() == 0);
    injection = ZERO_WRITE;
    assert(access_status(cap, plain, "swap", "never", 0));
    injection = NORMAL;
    read_named(cap, "swap", "three");
    assert(leftover_temporaries() == 0);
    injection = PARTIAL;
    assert(!access_status(cap, plain, "swap", "partial writes complete", 0));
    injection = NORMAL;
    assert(!stat("swap", &info) && info.st_size == (off_t)strlen("partial writes complete"));
    /* A storage error on the file's sync fails exactly the calls that sync the file, and then the old bytes stay and no
     * temporary does; an error on the directory's sync changes nothing, as neither of the pair syncs the directory. */
    injection = FILE_SYNC_ERROR;
    assert((access_status(cap, plain, "swap", "file sync", 0) != 0) == (file_syncs != 0));
    assert((access_status(cap, with_mode, "swap", "file sync", 0600) != 0) == (file_syncs != 0));
    assert(access_status(cap, CORE_DURABLE_ATOMIC, "swap", "file sync", 0));
    injection = NORMAL;
    read_named(cap, "swap", file_syncs ? "partial writes complete" : "file sync");
    assert(leftover_temporaries() == 0);
    injection = DIRECTORY_SYNC_ERROR;
    assert(!access_status(cap, plain, "swap", "no directory sync", 0));
    assert(!access_status(cap, with_mode, "swap", "no directory sync", 0600));
    read_named(cap, "swap", "no directory sync");
    assert(access_status(cap, CORE_DURABLE_ATOMIC, "swap", "directory sync", 0) == CORE_DURABLE_UNCERTAIN);
    injection = NORMAL;
    /* Permissions: 0600 by default, the given mode (the umask applying) for the mode form, none outside 0..0o7777. */
    mode_t before = umask(0);
    assert(!access_status(cap, plain, "private", "p", 0));
    assert(!stat("private", &info) && (info.st_mode & 07777) == 0600);
    assert(!access_status(cap, with_mode, "shared", "s", 0644));
    assert(!stat("shared", &info) && (info.st_mode & 07777) == 0644);
    assert(!access_status(cap, with_mode, "private", "q", 0755));
    assert(!stat("private", &info) && (info.st_mode & 07777) == 0755 && info.st_size == 1);
    umask(077);
    assert(!access_status(cap, with_mode, "masked", "m", 0666));
    assert(!stat("masked", &info) && (info.st_mode & 07777) == 0600);
    umask(before);
    assert(access_status(cap, with_mode, "bad", "b", -1) == 3);
    assert(access_status(cap, with_mode, "bad", "b", 010000) == 3);
    assert(access("bad", F_OK) != 0);
    /* The refusals are atomic_write_file's: a directory, a link, a path outside the grant, a read-only grant. */
    assert(!mkdir("replaced-directory", 0700));
    assert(access_status(cap, plain, "replaced-directory", "x", 0));
    assert(!symlink("swap", "replaced-link"));
    assert(access_status(cap, plain, "replaced-link", "x", 0));
    assert(access_status(cap, plain, "../escape", "x", 0) == 2);
    myl_block *readonly = core_io_cap(2, 1, core_io_authority(cap)->provider, cap, NULL);
    assert(access_status(readonly, plain, "swap", "x", 0) == 2);
    assert(access_status(readonly, with_mode, "swap", "x", 0644) == 2);
    myl_core_drop_owned(readonly);
    assert(leftover_temporaries() == 0);
    /* A test's filesystem publishes whole too, with the same permissions. */
    myl_block *provider = core_io_provider(2, 1, 0, NULL);
    myl_block *memory = core_io_cap(2, 7, provider, NULL, NULL);
    assert(!access_status(memory, plain, "swap", "one", 0));
    read_named(memory, "swap", "one");
    uint64_t words[STAT_WORDS];
    assert(!answer(memory, CORE_DURABLE_STAT, "swap", 0, NULL, words) && words[4] == 0600);
    assert(!access_status(memory, with_mode, "swap", "twelve", 0640));
    read_named(memory, "swap", "twelve");
    assert(!answer(memory, CORE_DURABLE_STAT, "swap", 0, NULL, words) && words[4] == 0640);
    assert(access_status(memory, with_mode, "swap", "x", 010000) == 3);
    myl_core_drop_owned(memory);
    assert(!unlink("swap") && !unlink("private") && !unlink("shared") && !unlink("masked") && !rmdir("replaced-directory") && !unlink("replaced-link"));
}
static void replacements(myl_block *cap) {
    replacement_behaviour(cap, CORE_DURABLE_REPLACE, CORE_DURABLE_REPLACE_MODE, 0);
    puts("replace_file publishes whole through a temporary and a rename, and forces nothing to disk");
}
static void synced_replacements(myl_block *cap) {
    replacement_behaviour(cap, CORE_DURABLE_REPLACE_SYNCED, CORE_DURABLE_REPLACE_SYNCED_MODE, 1);
    puts("replace_file_synced forces the file to disk before the rename and not the directory after it");
}
static void concurrent_writes(myl_block *cap) {
    int start[2];
    assert(!pipe(start));
    pid_t children[2];
    for (unsigned i = 0; i < 2; ++i) {
        children[i] = fork();
        assert(children[i] >= 0);
        if (!children[i]) {
            close(start[1]);
            char ready;
            assert(read(start[0], &ready, 1) == 1);
            char content[65537];
            memset(content, 'A' + i, sizeof content - 1);
            content[sizeof content - 1] = 0;
            for (unsigned attempt = 0; attempt < 12; ++attempt)
                assert(!access_status(cap, CORE_DURABLE_ATOMIC, "concurrent", content, 0));
            _exit(0);
        }
    }
    close(start[0]);
    assert(syscall(SYS_write, start[1], "RR", 2) == 2);
    close(start[1]);
    for (unsigned i = 0; i < 2; ++i) {
        int status;
        assert(waitpid(children[i], &status, 0) == children[i]);
        assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    }
    myl_block *path = text("concurrent"), *input = octets("");
    myl_block *result = myl_core_durable_access((int64_t)(intptr_t)cap, CORE_DURABLE_READ, path, input, 65536);
    uint64_t *fields = (uint64_t *)block_data(result);
    assert(!fields[0]);
    myl_block *value = (myl_block *)(uintptr_t)fields[1];
    assert(value->len == 65536);
    unsigned char *bytes = block_data(value);
    assert(bytes[0] == 'A' || bytes[0] == 'B');
    for (size_t i = 1; i < 65536; ++i) assert(bytes[i] == bytes[0]);
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
}
static void ownership(myl_block *cap) {
    int ready[2];
    assert(!pipe(ready));
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        close(ready[0]);
        myl_block *owner = acquire_lock(cap, 0);
        assert(owner);
        assert(syscall(SYS_write, ready[1], "R", 1) == 1);
        raise(SIGSTOP);
        _exit(1);
    }
    close(ready[1]);
    char byte;
    assert(read(ready[0], &byte, 1) == 1 && byte == 'R');
    close(ready[0]);
    assert(!acquire_lock(cap, CORE_DURABLE_BUSY));
    int status;
    assert(waitpid(child, &status, WUNTRACED) == child && WIFSTOPPED(status));
    assert(!kill(child, SIGKILL));
    assert(waitpid(child, &status, 0) == child && WIFSIGNALED(status));
    myl_block *owner = acquire_lock(cap, 0);
    assert(owner && core_io_live_handles() == 1);
    myl_core_drop_owned(owner);
    assert(core_io_live_handles() == 0);
    owner = acquire_lock(cap, 0);
    assert(!core_io_complete(owner));
    myl_core_drop_owned(owner);
    assert(core_io_live_handles() == 0);
    puts("competing process refused; SIGKILL, File drop and completion release directory ownership");
}
/* The failure text of one whole-file call (`myl_core_file_access`) into `out`: its status, zero when it succeeds. */
static int file_failure_text(myl_block *cap, uint32_t request, const char *name, const char *bytes, char *out) {
    myl_block *path = text(name), *input = octets(bytes);
    myl_block *result = myl_core_file_access((int64_t)(intptr_t)cap, request, path, input);
    uint64_t *fields = (uint64_t *)block_data(result);
    int status = (int)fields[0];
    out[0] = 0;
    if (status) {
        myl_block *message = (myl_block *)(uintptr_t)fields[2];
        snprintf(out, 4096, "%.*s", (int)message->len, (char *)block_data(message));
    }
    myl_core_drop_owned(result);
    myl_core_drop_owned(input);
    myl_core_drop_owned(path);
    return status;
}
/* Run `body` in a child that ends in a trap and return the detail line of the trap (what follows `error[R_FILE]: `) in `out`;
   `limited` first bounds the child's files to one octet with SIGXFSZ ignored. The status of the child is the return value. */
static int trap_text(void (*body)(myl_block *, const char *), myl_block *cap, const char *name, int limited, char *out) {
    int channel[2];
    assert(!pipe(channel));
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        close(channel[0]);
        assert(dup2(channel[1], STDERR_FILENO) == STDERR_FILENO);
        if (limited) {
            struct rlimit bound = {1, 1};
            assert(signal(SIGXFSZ, SIG_IGN) != SIG_ERR && !setrlimit(RLIMIT_FSIZE, &bound));
        }
        body(cap, name);
        _exit(0);
    }
    close(channel[1]);
    char all[4096];
    size_t used = 0;
    ssize_t got;
    while (used < sizeof all - 1 && (got = read(channel[0], all + used, sizeof all - 1 - used)) > 0) used += (size_t)got;
    all[used] = 0;
    close(channel[0]);
    int status;
    assert(waitpid(child, &status, 0) == child && WIFEXITED(status));
    const char *marker = strstr(all, "error[R_FILE]: ");
    out[0] = 0;
    if (marker) {
        marker += strlen("error[R_FILE]: ");
        snprintf(out, 4096, "%.*s", (int)strcspn(marker, "\n"), marker);
    }
    return WEXITSTATUS(status);
}
/* A file opened for writing and written once: the failure of the write is the trap. */
static void write_trap(myl_block *cap, const char *name) {
    myl_block *path = text(name), *input = octets("trapped bytes");
    myl_block *owner = myl_core_file_access((int64_t)(intptr_t)cap, 0u | ((unsigned)'w' << 8) | (1u << 17), path, NULL);
    (void)myl_core_file_method(owner, 3, 0, input);
}
/* A file closed and written again: the second use is the trap. */
static void closed_trap(myl_block *cap, const char *name) {
    myl_block *path = text(name), *input = octets("late");
    myl_block *owner = myl_core_file_access((int64_t)(intptr_t)cap, 0u | ((unsigned)'w' << 8) | (1u << 17), path, NULL);
    (void)myl_core_file_method(owner, 5, 0, NULL);
    (void)myl_core_file_method(owner, 3, 0, input);
}
/* A failed file operation says why, in the same words for the durable calls, the whole-file calls, the methods of an open file and
   the in-memory filesystem: the table of the system's errors, then each reason a program can provoke without privilege. */
static void reasons(myl_block *cap) {
    char message[4096];
    assert(!strcmp(core_io_errno_reason(ENOSPC), "no space left on the device") && !strcmp(core_io_errno_reason(EDQUOT), "disk quota exceeded"));
    assert(!strcmp(core_io_errno_reason(EFBIG), "the file is too large for the size limit or for the filesystem"));
    assert(!strcmp(core_io_errno_reason(EROFS), "the filesystem is read-only") && !strcmp(core_io_errno_reason(EACCES), "permission denied"));
    assert(!strcmp(core_io_errno_reason(EMFILE), "too many files are open") && !strcmp(core_io_errno_reason(ENFILE), "too many files are open"));
    assert(!strcmp(core_io_errno_reason(EIO), "input/output error") && !strcmp(core_io_errno_reason(EISDIR), "is a directory"));
    assert(!strcmp(core_io_errno_reason(ENAMETOOLONG), "the path, or a name in it, is too long") && !strcmp(core_io_errno_reason(ENOENT), "the path does not exist"));
    assert(!strcmp(core_io_errno_reason(EPROTO), "error 71: protocol error") && !core_io_errno_reason(0));
    /* The durable calls: the path exists and the failure is the system's. */
    char found[4096];
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "why-a", "kept", 0));
    injection = ZERO_WRITE;
    assert(failure_text_of(cap, CORE_DURABLE_ATOMIC, "why-a", "new", 0, message) == 3 && !strcmp(message, "atomic write 'why-a': no bytes could be written"));
    injection = FILE_SYNC_ERROR;
    assert(failure_text_of(cap, CORE_DURABLE_ATOMIC, "why-a", "new", 0, message) == 3 && !strcmp(message, "atomic write 'why-a': input/output error"));
    injection = NORMAL;
    assert(!answer(cap, CORE_DURABLE_READ, "why-a", 64, found, NULL) && !strcmp(found, "kept"));
    pid_t limited = fork();
    assert(limited >= 0);
    if (!limited) {
        struct rlimit bound = {1, 1};
        assert(signal(SIGXFSZ, SIG_IGN) != SIG_ERR && !setrlimit(RLIMIT_FSIZE, &bound));
        assert(failure_text_of(cap, CORE_DURABLE_ATOMIC, "why-a", "new", 0, message) == 3);
        assert(!strcmp(message, "atomic write 'why-a': the file is too large for the size limit or for the filesystem"));
        _exit(0);
    }
    int ended;
    assert(waitpid(limited, &ended, 0) == limited && WIFEXITED(ended) && WEXITSTATUS(ended) == 0);
    assert(failure_text_of(cap, CORE_DURABLE_ATOMIC, "why-none/x", "x", 0, message) == 3 && !strcmp(message, "atomic write 'why-none/x': a folder on the way does not exist"));
    assert(!mkdir("why-dir", 0700));
    assert(failure_text_of(cap, CORE_DURABLE_ATOMIC, "why-dir", "x", 0, message) == 2 && !strcmp(message, "atomic write 'why-dir': is a directory"));
    char longest[301];
    memset(longest, 'n', 300);
    longest[300] = 0;
    assert(failure_text_of(cap, CORE_DURABLE_ATOMIC, longest, "x", 0, message) == 3 && strstr(message, "': the path, or a name in it, is too long"));
    assert(failure_text(cap, CORE_DURABLE_READ, "why-none", 8, message) == 3 && !strcmp(message, "regular read 'why-none': the path does not exist"));
    assert(failure_text(cap, CORE_DURABLE_READ, "why-a", 2, message) == 3 && !strcmp(message, "regular read 'why-a': is larger than max_bytes"));
    /* A folder nobody may write into (not tried by a process that ignores permissions). */
    if (geteuid()) {
        assert(!mkdir("why-ro", 0500));
        assert(failure_text_of(cap, CORE_DURABLE_ATOMIC, "why-ro/x", "x", 0, message) == 2 && !strcmp(message, "atomic write 'why-ro/x': permission denied"));
        assert(file_failure_text(cap, 3, "why-ro/x", "bytes", message) == 3 && !strcmp(message, "write 'why-ro/x': permission denied"));
        assert(!chmod("why-ro", 0700));
    }
    /* The whole-file calls say the same: a missing folder, a full device, a size limit, a missing file. */
    assert(file_failure_text(cap, 3, "why-none/x", "bytes", message) == 3 && !strcmp(message, "write 'why-none/x': a folder on the way does not exist"));
    assert(file_failure_text(cap, 1, "why-none", "", message) == 3 && !strcmp(message, "read 'why-none': the path does not exist"));
    assert(file_failure_text(cap, 3, "why-dir", "bytes", message) == 2 && !strcmp(message, "write 'why-dir': is a directory"));
    limited = fork();
    assert(limited >= 0);
    if (!limited) {
        struct rlimit bound = {1, 1};
        assert(signal(SIGXFSZ, SIG_IGN) != SIG_ERR && !setrlimit(RLIMIT_FSIZE, &bound));
        assert(file_failure_text(cap, 3, "why-big", "more than one octet", message) == 3);
        assert(!strcmp(message, "write 'why-big': the file is too large for the size limit or for the filesystem"));
        _exit(0);
    }
    assert(waitpid(limited, &ended, 0) == limited && WIFEXITED(ended) && WEXITSTATUS(ended) == 0);
    /* The trap of a failed method of an open file names the path and the reason. */
    assert(trap_text(write_trap, cap, "why-trap", 1, message) == 1 && !strcmp(message, "write 'why-trap': the file is too large for the size limit or for the filesystem"));
    assert(trap_text(closed_trap, cap, "why-late", 0, message) == 1 && !strcmp(message, "write 'why-late': the file is already closed"));
    core_io_real.roots[0].direct = 1;
    assert(file_failure_text(cap, 3, "/dev/full", "bytes", message) == 3 && !strcmp(message, "write '/dev/full': no space left on the device"));
    assert(trap_text(write_trap, cap, "/dev/full", 0, message) == 1 && !strcmp(message, "write '/dev/full': no space left on the device"));
    core_io_real.roots[0].direct = 0;
    /* A test's filesystem gives the sentences it can produce. */
    myl_block *provider = core_io_provider(2, 1, 0, NULL);
    myl_block *memory = core_io_cap(2, 7, provider, NULL, NULL);
    assert(failure_text_of(memory, CORE_DURABLE_ATOMIC, "why-none/x", "x", 0, message) == 3 && !strcmp(message, "atomic write 'why-none/x': a folder on the way does not exist"));
    assert(failure_text(memory, CORE_DURABLE_READ, "why-none", 8, message) == 3 && !strcmp(message, "regular read 'why-none': the path does not exist"));
    assert(file_failure_text(memory, 3, "why-none/x", "bytes", message) == 3 && !strcmp(message, "write 'why-none/x': a folder on the way does not exist"));
    assert(file_failure_text(memory, 1, "why-none", "", message) == 3 && !strcmp(message, "read 'why-none': the path does not exist"));
    size_t big = 33u * 1024u * 1024u;
    char *bulk = malloc(big + 1);
    assert(bulk);
    memset(bulk, 'b', big);
    bulk[big] = 0;
    assert(!access_status(memory, CORE_DURABLE_ATOMIC, "why-first", bulk, 0));
    assert(failure_text_of(memory, CORE_DURABLE_ATOMIC, "why-second", bulk, 0, message) == 3 && !strcmp(message, "atomic write 'why-second': no space left on the device"));
    free(bulk);
    myl_core_drop_owned(memory);
    puts("a failed write says why: the table, the durable calls, the whole-file calls, the open-file traps and the in-memory filesystem");
}
/* Each phase has its own liveness ceiling. Slow fsync traffic in preceding
 * phases must not consume the crash/ownership tests' execution budget. */
static const char *phase_name;
static size_t phase_name_length;
static void phase_expired(int signal_number) {
    (void)signal_number;
    static const char prefix[] = "durable fixture phase timed out: ";
    (void)syscall(SYS_write, STDERR_FILENO, prefix, sizeof prefix - 1);
    (void)syscall(SYS_write, STDERR_FILENO, phase_name, phase_name_length);
    (void)syscall(SYS_write, STDERR_FILENO, "\n", 1);
    _exit(124);
}
static void phase(const char *name, void (*run)(myl_block *), myl_block *cap) {
    phase_name = name;
    phase_name_length = strlen(name);
    alarm(60);
    run(cap);
    alarm(0);
}
int main(int argc, char **argv) {
    assert(signal(SIGALRM, phase_expired) != SIG_ERR);
    myl_core_start();
    core_io_scoped_init(&core_io_real);
    assert(core_io_scoped_grant(&core_io_real, ".", 1));
    core_io_initialized = 1;
    myl_block *provider = core_io_provider(2, 0, 0, NULL);
    myl_block *cap = core_io_cap(2, 7, provider, NULL, NULL);
    assert(argc == 2);
    if (!strcmp(argv[1], "all")) {
        phase("basic", basic, cap);
        phase("failures", failures, cap);
        phase("scopes", scopes, cap);
        phase("metadata", metadata, cap);
        phase("space_and_windows", space_and_windows, cap);
        phase("links_and_owners", links_and_owners, cap);
        phase("hard_links_and_modes", hard_links_and_modes, cap);
        phase("replacements", replacements, cap);
        phase("synced_replacements", synced_replacements, cap);
        phase("stat_cost", stat_cost, cap);
        phase("entries", entries, cap);
        phase("listings", listings, cap);
        phase("crashes", crashes, cap);
        phase("concurrent_writes", concurrent_writes, cap);
        phase("ownership", ownership, cap);
        phase("reasons", reasons, cap);
    }
    else if (!strcmp(argv[1], "basic")) phase("basic", basic, cap);
    else if (!strcmp(argv[1], "failures")) phase("failures", failures, cap);
    else if (!strcmp(argv[1], "metadata")) phase("metadata", metadata, cap);
    else if (!strcmp(argv[1], "space_and_windows")) phase("space_and_windows", space_and_windows, cap);
    else if (!strcmp(argv[1], "links_and_owners")) phase("links_and_owners", links_and_owners, cap);
    else if (!strcmp(argv[1], "hard_links_and_modes")) phase("hard_links_and_modes", hard_links_and_modes, cap);
    else if (!strcmp(argv[1], "replacements")) phase("replacements", replacements, cap);
    else if (!strcmp(argv[1], "synced_replacements")) phase("synced_replacements", synced_replacements, cap);
    else if (!strcmp(argv[1], "stat_cost")) phase("stat_cost", stat_cost, cap);
    else if (!strcmp(argv[1], "entries")) phase("entries", entries, cap);
    else if (!strcmp(argv[1], "crashes")) phase("crashes", crashes, cap);
    else if (!strcmp(argv[1], "ownership")) phase("ownership", ownership, cap);
    else if (!strcmp(argv[1], "reasons")) phase("reasons", reasons, cap);
    else assert(0);
    myl_core_drop_owned(cap);
    assert(core_io_live_handles() == 0);
    return myl_core_exit(0);
}
