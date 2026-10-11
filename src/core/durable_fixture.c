#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#define _XOPEN_SOURCE 700
#include <stdio.h>
#include <unistd.h>
#include <dirent.h>
ssize_t durable_fixture_write(int fd, const void *bytes, size_t length);
int durable_fixture_fsync(int fd);
int durable_fixture_renameat(int oldfd, const char *old, int newfd, const char *name);
struct dirent *durable_fixture_readdir(DIR *directory);
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
#undef NDEBUG
#include <assert.h>
#include <sys/wait.h>
#include <sys/resource.h>

myl_block *myl_core_task_call(void *run, myl_block *env) {
    return ((myl_block *(*)(myl_block *))run)(env);
}

enum { NORMAL, PARTIAL, ZERO_WRITE, FILE_SYNC_ERROR, DIRECTORY_SYNC_ERROR,
       STOP_BEFORE_RENAME, STOP_AFTER_RENAME, DIRECTORY_READ_ERROR };
static int injection;
static unsigned directory_reads;

ssize_t durable_fixture_write(int fd, const void *bytes, size_t length) {
    if (injection == ZERO_WRITE) return 0;
    if (injection == PARTIAL && length > 2) length = 2;
    return syscall(SYS_write, fd, bytes, length);
}
int durable_fixture_fsync(int fd) {
    struct stat info;
    assert(!fstat(fd, &info));
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
struct dirent *durable_fixture_readdir(DIR *directory) {
    if (injection == DIRECTORY_READ_ERROR && ++directory_reads > 3) {
        errno = EIO;
        return NULL;
    }
    return readdir(directory);
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
    myl_block *result = myl_core_durable_access(cap, kind, path, input, limit);
    int status = (int)((uint64_t *)block_data(result))[0];
    myl_core_release(result);
    myl_core_release(input);
    myl_core_release(path);
    return status;
}
static void read_exact(myl_block *cap, const char *expected) {
    myl_block *path = text("data"), *input = octets("");
    myl_block *result = myl_core_durable_access(cap, CORE_DURABLE_READ, path, input, 64);
    uint64_t *fields = (uint64_t *)block_data(result);
    assert(!fields[0]);
    myl_block *value = (myl_block *)(uintptr_t)fields[1];
    assert((size_t)value->len == strlen(expected));
    assert(!memcmp(block_data(value), expected, strlen(expected)));
    myl_core_release(result);
    myl_core_release(input);
    myl_core_release(path);
}
static myl_block *acquire_lock(myl_block *cap, int expected) {
    myl_block *path = text(""), *input = octets("");
    myl_block *result = myl_core_durable_access(cap, CORE_DURABLE_LOCK, path, input, 0);
    uint64_t *fields = (uint64_t *)block_data(result);
    assert((int)fields[0] == expected);
    myl_block *owner = expected ? NULL : (myl_block *)(uintptr_t)fields[1];
    if (owner) core_io_retain(owner);
    myl_core_release(result);
    myl_core_release(input);
    myl_core_release(path);
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
    myl_core_release(readonly);
    myl_block *provider = core_io_provider(2, 1, 0, NULL);
    myl_block *memory = core_io_cap(2, 7, provider, NULL, NULL);
    myl_core_release(provider);
    assert(access_status(memory, CORE_DURABLE_ATOMIC, "data", "x", 0) == 1);
    assert(access_status(memory, CORE_DURABLE_READ, "data", "", 64) == 1);
    myl_core_release(memory);
    puts("partial writes, exact bounded reads, permission and stand-in refusal");
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
    myl_core_release(scope);
    assert(!access_status(narrowed, CORE_DURABLE_ATOMIC, "data", "scoped", 0));
    read_exact(narrowed, "scoped");
    read_exact(cap, "new");
    assert(access_status(narrowed, CORE_DURABLE_READ, "../data", "", 64) == 2);
    char absolute[4095];
    assert(getcwd(absolute, sizeof absolute));
    assert(strlen(absolute) + 6 < sizeof absolute);
    strcat(absolute, "/data");
    assert(access_status(cap, CORE_DURABLE_READ, absolute, "", 64) == 2);
    core_io_real.roots[0].direct = 1;
    assert(!access_status(cap, CORE_DURABLE_READ, absolute, "", 64));
    assert(access_status(narrowed, CORE_DURABLE_READ, absolute, "", 64) == 2);
    core_io_real.roots[0].direct = 0;
    myl_core_release(narrowed);
    core_io_embedding = 1;
    assert(access_status(cap, CORE_DURABLE_ATOMIC, "data", "x", 0) == 1);
    core_io_embedding = 0;
    myl_block *path = text("data"), *input = octets("x");
    input->len = CORE_DURABLE_LIMIT + 1;
    myl_block *result = myl_core_durable_access(cap, CORE_DURABLE_ATOMIC, path, input, 0);
    assert(((uint64_t *)block_data(result))[0] == 3);
    input->len = 1;
    myl_core_release(result);
    myl_core_release(input);
    myl_core_release(path);
    read_exact(cap, "new");
    assert(!mkdir("later", 0700));
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "later/other", "later root", 0));
    assert(core_io_scoped_grant(&core_io_real, "later", 1));
    assert(!access_status(cap, CORE_DURABLE_READ, "other", "", 64));
    assert(!acquire_lock(cap, 2));
    core_io_real.roots[1].writable = 0;
    assert(!acquire_lock(cap, 2));
    close(core_io_real.roots[1].fd);
    core_io_real.count = 1;
    assert(core_io_scoped_grant(&core_io_real, ".", 0));
    myl_block *owner = acquire_lock(cap, 0);
    assert(owner);
    myl_core_release(owner);
    close(core_io_real.roots[1].fd);
    core_io_real.count = 1;
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
    assert(access_status(cap, CORE_DURABLE_LIST, "", "", 4097));
    assert(access_status(cap, CORE_DURABLE_LIST, "alias", "", 4096));
    myl_block *path = text(""), *input = octets("");
    myl_block *result = myl_core_durable_access(cap, CORE_DURABLE_LIST, path, input, 4096);
    uint64_t *fields = (uint64_t *)block_data(result);
    assert(!fields[0]);
    myl_block *list = (myl_block *)(uintptr_t)fields[1];
    assert(list->len > 300 && list->len < 4096);
    myl_block **items = (myl_block **)block_data(list);
    bool hidden = false;
    for (int64_t i = 0; i < list->len; ++i)
        if (items[i]->len == 7 && !memcmp(block_data(items[i]), ".hidden", 7)) hidden = true;
    assert(hidden);
    myl_core_release(result);
    myl_core_release(input);
    myl_core_release(path);
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
    puts("complete bounded directory snapshot includes hidden entries beyond 256 and refuses partial readdir");
}
static void kill_publication(myl_block *cap, int phase, const char *expected) {
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "data", "old", 0));
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        injection = phase;
        (void)access_status(cap, CORE_DURABLE_ATOMIC, "data", "new", 0);
        _exit(1);
    }
    int status;
    assert(waitpid(child, &status, WUNTRACED) == child);
    assert(WIFSTOPPED(status));
    assert(!kill(child, SIGKILL));
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL);
    read_exact(cap, expected);
    assert(!access_status(cap, CORE_DURABLE_ATOMIC, "data", "recovered", 0));
    read_exact(cap, "recovered");
}
static void crashes(myl_block *cap) {
    kill_publication(cap, STOP_BEFORE_RENAME, "old");
    kill_publication(cap, STOP_AFTER_RENAME, "new");
    puts("actual SIGKILL before and after publication preserves complete old or new bytes and permits recovery");
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
    myl_block *result = myl_core_durable_access(cap, CORE_DURABLE_READ, path, input, 65536);
    uint64_t *fields = (uint64_t *)block_data(result);
    assert(!fields[0]);
    myl_block *value = (myl_block *)(uintptr_t)fields[1];
    assert(value->len == 65536);
    unsigned char *bytes = block_data(value);
    assert(bytes[0] == 'A' || bytes[0] == 'B');
    for (size_t i = 1; i < 65536; ++i) assert(bytes[i] == bytes[0]);
    myl_core_release(result);
    myl_core_release(input);
    myl_core_release(path);
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
    assert(!acquire_lock(cap, 3));
    int status;
    assert(waitpid(child, &status, WUNTRACED) == child && WIFSTOPPED(status));
    assert(!kill(child, SIGKILL));
    assert(waitpid(child, &status, 0) == child && WIFSIGNALED(status));
    myl_block *owner = acquire_lock(cap, 0);
    assert(owner && core_io_live_handles() == 1);
    myl_core_release(owner);
    assert(core_io_live_handles() == 0);
    owner = acquire_lock(cap, 0);
    assert(!core_io_complete(owner));
    myl_core_release(owner);
    assert(core_io_live_handles() == 0);
    puts("competing process refused; SIGKILL, File drop and completion release directory ownership");
}
int main(int argc, char **argv) {
    alarm(15);
    myl_core_start();
    core_io_scoped_init(&core_io_real);
    assert(core_io_scoped_grant(&core_io_real, ".", 1));
    core_io_initialized = 1;
    myl_block *provider = core_io_provider(2, 0, 0, NULL);
    myl_block *cap = core_io_cap(2, 7, provider, NULL, NULL);
    myl_core_release(provider);
    assert(argc == 2);
    if (!strcmp(argv[1], "all")) {
        basic(cap);
        failures(cap);
        scopes(cap);
        listings(cap);
        crashes(cap);
        concurrent_writes(cap);
        ownership(cap);
    }
    else if (!strcmp(argv[1], "basic")) basic(cap);
    else if (!strcmp(argv[1], "failures")) failures(cap);
    else if (!strcmp(argv[1], "crashes")) crashes(cap);
    else if (!strcmp(argv[1], "ownership")) ownership(cap);
    else assert(0);
    myl_core_release(cap);
    assert(core_io_live_handles() == 0);
    return myl_core_exit(0);
}
