/* The Process capability: run one program to completion and capture its output (L1a). It follows the capability
 * runtime in core_io.c: the request is checked against the capability's family and authority, and every failure is
 * a status plus text for the caller's `Result`, never a trap. The request and the answer are the `binary` module's
 * octets (src/stdlib/binary.selka), packed and unpacked by src/stdlib/process.selka:
 *
 *   request: uvarint argc, argc x (uvarint length, octets)         the program and its arguments, no shell
 *            uvarint length, octets                                working directory ("" keeps the caller's)
 *            uvarint length, octets                                standard input, closed once written
 *            u8 mode (0 inherit, 1 explicit), then for mode 1:     the child's environment
 *            uvarint count, count x (uvarint length, "NAME=VALUE")
 *   answer:  u8 outcome (0 exited, 1 ended by a signal, 2 not started), varint code (status, signal or errno),
 *            uvarint length + octets of standard output, uvarint length + octets of standard error,
 *            u8 flags (bit 0: output cut at the limit, bit 1: error output cut)
 *
 * Output beyond the limit is drained and dropped, so a chatty child never blocks on a full pipe.
 *
 * A program can also be started without waiting (`process.start`, FR6): `process_control` operations 6 to 8 start one
 * with its output in files, signal it and wait for it with a time limit. Every started program that no wait has reaped
 * is in a table here, so a signal or a wait reaches only a program this program started and never a process number the
 * system has reused. Both kinds of child start under the address-space limit this program itself started with, not the
 * ceiling `selka run` gave it (F-32). */
#include <limits.h>
#include <poll.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/wait.h>

extern char **environ;

typedef struct { const unsigned char *at, *end; } CoreProcessCursor;

static int core_process_uvarint(CoreProcessCursor *cursor, uint64_t *out) {
    uint64_t value = 0;
    for (unsigned shift = 0; shift < 64; shift += 7) {
        if (cursor->at >= cursor->end) return 0;
        unsigned char octet = *cursor->at++;
        value |= (uint64_t)(octet & 127) << shift;
        if (octet < 128) { *out = value; return 1; }
    }
    return 0;
}

/* The next length-prefixed field, as a NUL-terminated copy the caller frees, or NULL when the request is damaged. */
static char *core_process_field(CoreProcessCursor *cursor, size_t *length) {
    uint64_t count;
    if (!core_process_uvarint(cursor, &count) || count > (uint64_t)(cursor->end - cursor->at)) return NULL;
    char *copy = malloc((size_t)count + 1);
    if (!copy) out_of_memory();
    memcpy(copy, cursor->at, (size_t)count);
    copy[count] = 0;
    cursor->at += count;
    if (length) *length = (size_t)count;
    return copy;
}

static void core_process_free_list(char **list, size_t count) {
    for (size_t i = 0; i < count; ++i) free(list[i]);
    free(list);
}

static void core_process_put_uvarint(CoreIoBytes *bytes, uint64_t value) {
    unsigned char octet;
    do {
        octet = value & 127;
        value >>= 7;
        if (value) octet |= 128;
        core_io_append(bytes, &octet, 1);
    } while (value);
}

static void core_process_put_varint(CoreIoBytes *bytes, int64_t value) {
    core_process_put_uvarint(bytes, value < 0 ? (((uint64_t)~value) << 1) | 1 : ((uint64_t)value) << 1);
}

/* One captured stream: kept octets up to the limit, then counted and dropped. */
typedef struct { CoreIoBytes kept; int descriptor; int cut; } CoreProcessStream;

static void core_process_drain(CoreProcessStream *stream, size_t limit) {
    unsigned char buffer[16384];
    for (;;) {
        ssize_t count = read(stream->descriptor, buffer, sizeof buffer);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return;
        if (count <= 0) { close(stream->descriptor); stream->descriptor = -1; return; }
        size_t room = limit > stream->kept.length ? limit - stream->kept.length : 0;
        size_t keep = (size_t)count < room ? (size_t)count : room;
        if (keep) core_io_append(&stream->kept, buffer, keep);
        if (keep < (size_t)count) stream->cut = 1;
    }
}

static myl_block *core_process_answer(int outcome, int64_t code, CoreProcessStream *out, CoreProcessStream *err) {
    CoreIoBytes answer = {0};
    unsigned char octet = (unsigned char)outcome;
    core_io_append(&answer, &octet, 1);
    core_process_put_varint(&answer, code);
    core_process_put_uvarint(&answer, out->kept.length);
    if (out->kept.length) core_io_append(&answer, out->kept.bytes, out->kept.length);
    core_process_put_uvarint(&answer, err->kept.length);
    if (err->kept.length) core_io_append(&answer, err->kept.bytes, err->kept.length);
    octet = (unsigned char)((out->cut ? 1 : 0) | (err->cut ? 2 : 0));
    core_io_append(&answer, &octet, 1);
    myl_block *block = core_io_string(answer.bytes, answer.length, 0);
    core_io_bytes_release(&answer);
    return block;
}

/* The runtime opens its own descriptors close-on-exec, but a socket from the network provider, or one a `--link`ed C
 * file opened, may not be; the child must see only its three standard descriptors. List every other descriptor that
 * would survive the exec, for the child to close. A descriptor opened by another thread after this list is made is not
 * covered. The list is the caller's to free. */
static int *core_process_inherited(size_t *count) {
    *count = 0;
    DIR *directory = opendir("/proc/self/fd");
    if (!directory) return NULL;
    int own = dirfd(directory);
    size_t room = 0;
    int *list = NULL;
    struct dirent *entry;
    while ((entry = readdir(directory))) {
        char *end;
        long descriptor = strtol(entry->d_name, &end, 10);
        if (*end || descriptor < 3 || descriptor == own) continue;
        int flags = fcntl((int)descriptor, F_GETFD);
        if (flags < 0 || (flags & FD_CLOEXEC)) continue;
        if (*count == room) {
            room = room ? room * 2 : 8;
            int *grown = realloc(list, room * sizeof *list);
            if (!grown) out_of_memory();
            list = grown;
        }
        list[(*count)++] = (int)descriptor;
    }
    closedir(directory);
    return list;
}

/* The address-space limit this program started with (F-32). `selka run` starts a program under the caller's limit and
 * the runtime then lowers its own soft `RLIMIT_AS` to the run's byte ceiling plus 256 MiB (`myl_core_test_ceilings`),
 * and a thread pool raises it by the workers' stacks (`core_task_reserve`); both note the limit first. A program it
 * starts gets the noted limit back: the ceiling bounds this program, not the programs it starts. */
static struct rlimit core_process_started_limit;
static bool core_process_started_noted;

static void core_process_note_address_space(void) {
    if (core_process_started_noted) return;
    if (!getrlimit(RLIMIT_AS, &core_process_started_limit)) core_process_started_noted = true;
}

/* What a child starts with: its program and arguments, its environment (NULL: this program's), its working directory
 * (NULL: this program's), the descriptors that become its 0, 1 and 2, and whether it is killed when this program ends
 * (`orphan_kill`, for a started program; `process.run` waits for its child, so it sets none), and whether it leads a process
 * group of its own (`own_group`, for a program of a group: a signal to `-pid` then reaches what it started too). */
typedef struct {
    char **arguments;
    char **environment;
    const char *directory;
    int descriptors[3];
    bool orphan_kill;
    bool own_group;
} CoreProcessSpawn;

/* What the child of `vfork` reads, all of it prepared before the fork, and the errno it reports when it cannot exec. */
typedef struct {
    const CoreProcessSpawn *spawn;
    const int *closing;
    size_t closing_count;
    const char *search;
    struct rlimit limit, descriptors;
    bool limit_set, descriptors_set;
    pid_t parent;
    volatile int failure;
} CoreProcessExec;

__attribute__((noreturn)) static void core_process_child_fail(CoreProcessExec *exec, int code) {
    exec->failure = code ? code : EINVAL;
    _exit(127);
}

/* The child's side of `core_process_spawn`, between `vfork` and `exec`: it shares this program's memory, so it only
 * makes system calls and writes its own stack. It puts back the default action of every signal this program catches
 * (and of SIGPIPE), takes its descriptors, enters its directory, takes back the address space and the soft descriptor
 * limit this program started with (a poller raises the latter), becomes the leader of a process group of its own (a
 * program of a group), asks to be killed when its parent ends (a started program), unblocks every signal and runs the
 * program, searching the caller's PATH for a name without a slash as `posix_spawnp` does (no shell for a file that is
 * not a program). */
__attribute__((noreturn, noinline)) static void core_process_child(CoreProcessExec *exec) {
    const CoreProcessSpawn *spawn = exec->spawn;
    for (int number = 1; number < NSIG; ++number) {
        struct sigaction action;
        if (sigaction(number, NULL, &action)) continue;
        if (number != SIGPIPE && (action.sa_handler == SIG_IGN || action.sa_handler == SIG_DFL)) continue;
        struct sigaction plain;
        memset(&plain, 0, sizeof plain);
        plain.sa_handler = SIG_DFL;
        sigemptyset(&plain.sa_mask);
        (void)sigaction(number, &plain, NULL);
    }
    for (int target = 0; target < 3; ++target) {
        int source = spawn->descriptors[target];
        if (source == target) {
            int flags = fcntl(target, F_GETFD);
            if (flags >= 0) (void)fcntl(target, F_SETFD, flags & ~FD_CLOEXEC);
        } else if (dup2(source, target) < 0) core_process_child_fail(exec, errno);
    }
    for (size_t i = 0; i < exec->closing_count; ++i) (void)close(exec->closing[i]);
    if (spawn->directory && chdir(spawn->directory)) core_process_child_fail(exec, errno);
    if (spawn->own_group && setpgid(0, 0)) core_process_child_fail(exec, errno);
    if (exec->limit_set) (void)setrlimit(RLIMIT_AS, &exec->limit);
    if (exec->descriptors_set) (void)setrlimit(RLIMIT_NOFILE, &exec->descriptors);
    if (spawn->orphan_kill && (prctl(PR_SET_PDEATHSIG, SIGKILL) || getppid() != exec->parent)) _exit(127);
    sigset_t none;
    sigemptyset(&none);
    (void)sigprocmask(SIG_SETMASK, &none, NULL);
    char **environment = spawn->environment ? spawn->environment : environ;
    const char *name = spawn->arguments[0];
    if (!*name) core_process_child_fail(exec, ENOENT);
    if (strchr(name, '/')) {
        execve(name, spawn->arguments, environment);
        core_process_child_fail(exec, errno);
    }
    const char *search = exec->search && *exec->search ? exec->search : "/bin:/usr/bin";
    size_t name_length = strlen(name);
    bool denied = false;
    char path[PATH_MAX];
    for (const char *at = search;; ++at) {
        const char *end = strchr(at, ':');
        size_t length = end ? (size_t)(end - at) : strlen(at);
        if (length + 1 + name_length + 1 <= sizeof path) {
            size_t used = 0;
            if (length) { memcpy(path, at, length); used = length; path[used++] = '/'; }
            memcpy(path + used, name, name_length + 1);
            execve(path, spawn->arguments, environment);
            if (errno == EACCES) denied = true;
            else if (errno != ENOENT && errno != ESTALE && errno != ENOTDIR && errno != ENODEV && errno != ETIMEDOUT)
                core_process_child_fail(exec, errno);
        }
        if (!end) break;
        at = end;
    }
    core_process_child_fail(exec, denied ? EACCES : ENOENT);
}

/* Start `spawn` and answer 0 with the child's number in `*child`, or the errno that kept it from starting. Every signal
 * is blocked across the `vfork`, so no handler of this program runs in the child while it shares this program's memory;
 * `vfork` returns here once the child has run its program or failed to. */
static int core_process_spawn(const CoreProcessSpawn *spawn, pid_t *child) {
    CoreProcessExec exec;
    memset(&exec, 0, sizeof exec);
    exec.spawn = spawn;
    int *closing = core_process_inherited(&exec.closing_count);
    exec.closing = closing;
    exec.search = getenv("PATH");
    exec.parent = getpid();
    struct rlimit now;
    if (core_process_started_noted && !getrlimit(RLIMIT_AS, &now)) {
        exec.limit.rlim_max = now.rlim_max;
        exec.limit.rlim_cur = core_process_started_limit.rlim_cur;
        if (now.rlim_max != RLIM_INFINITY && exec.limit.rlim_cur > now.rlim_max) exec.limit.rlim_cur = now.rlim_max;
        exec.limit_set = exec.limit.rlim_cur != now.rlim_cur;
    }
    /* The soft descriptor limit a poller raised goes back to what this program started with (core_poll.c). */
    if (core_poll_started_noted && !getrlimit(RLIMIT_NOFILE, &now)) {
        exec.descriptors.rlim_max = now.rlim_max;
        exec.descriptors.rlim_cur = core_poll_started_descriptors.rlim_cur;
        if (now.rlim_max != RLIM_INFINITY && exec.descriptors.rlim_cur > now.rlim_max) exec.descriptors.rlim_cur = now.rlim_max;
        exec.descriptors_set = exec.descriptors.rlim_cur != now.rlim_cur;
    }
    sigset_t all, previous;
    sigfillset(&all);
    pthread_sigmask(SIG_SETMASK, &all, &previous);
    pid_t started = vfork();
    if (started == 0) core_process_child(&exec);
    int code = started < 0 ? errno : 0;
    pthread_sigmask(SIG_SETMASK, &previous, NULL);
    free(closing);
    if (started < 0) return code ? code : EAGAIN;
    if (exec.failure) {
        int status;
        while (waitpid(started, &status, 0) < 0 && errno == EINTR) {}
        return exec.failure;
    }
    *child = started;
    return 0;
}

/* A process request read from its octets: the program and its arguments, the working directory ("" keeps the caller's),
 * the standard input, and the explicit environment (`environment` NULL: the caller's). */
typedef struct {
    char **arguments, **environment, *directory, *input;
    size_t argument_count, environment_count, directory_length, input_length;
} CoreProcessRequest;

static void core_process_request_free(CoreProcessRequest *request) {
    core_process_free_list(request->arguments, request->argument_count);
    core_process_free_list(request->environment, request->environment_count);
    free(request->directory);
    free(request->input);
}

/* Read one request at `cursor`, leaving the cursor after it. 0 when the octets are not a request the stdlib built; the
 * caller frees `request` either way. */
static int core_process_request(CoreProcessCursor *cursor, CoreProcessRequest *request) {
    uint64_t argc = 0, count = 0;
    memset(request, 0, sizeof *request);
    if (!core_process_uvarint(cursor, &argc) || argc == 0 || argc > 65536) return 0;
    request->arguments = calloc((size_t)argc + 1, sizeof *request->arguments);
    if (!request->arguments) out_of_memory();
    for (; request->argument_count < argc; ++request->argument_count)
        if (!(request->arguments[request->argument_count] = core_process_field(cursor, NULL))) return 0;
    if (!(request->directory = core_process_field(cursor, &request->directory_length))) return 0;
    if (!(request->input = core_process_field(cursor, &request->input_length))) return 0;
    if (cursor->at >= cursor->end) return 0;
    unsigned mode = *cursor->at++;
    if (mode == 1) {
        if (!core_process_uvarint(cursor, &count) || count > 65536) return 0;
        request->environment = calloc((size_t)count + 1, sizeof *request->environment);
        if (!request->environment) out_of_memory();
        for (; request->environment_count < count; ++request->environment_count)
            if (!(request->environment[request->environment_count] = core_process_field(cursor, NULL))) return 0;
    } else if (mode != 0) return 0;
    return 1;
}

/* Spawn the program and feed, drain and reap it. Returns 0 with `*answer` set, or a provider status with a reason in
 * `*reason` (a request the stdlib did not build, a limit the runtime refuses, or no pipe to give the child). */
static int core_process_run(const unsigned char *bytes, size_t request_length, int64_t limit_value,
                            myl_block **answer, const char **reason) {
    CoreProcessCursor cursor = {bytes, bytes + request_length};
    CoreProcessRequest request;
    memset(&request, 0, sizeof request);
    int status = 3;
    *reason = "the process request is damaged";
    if (limit_value < 0 || !core_process_request(&cursor, &request) || cursor.at != cursor.end) goto done;

    int to_child[2] = {-1, -1}, from_out[2] = {-1, -1}, from_err[2] = {-1, -1};
    *reason = "no pipe could be made for the child";
    if (pipe2(to_child, O_CLOEXEC) || pipe2(from_out, O_CLOEXEC) || pipe2(from_err, O_CLOEXEC)) goto pipes;
    CoreProcessSpawn spawn = {request.arguments, request.environment, request.directory_length ? request.directory : NULL,
                              {to_child[0], from_out[1], from_err[1]}, false, false};
    pid_t child = 0;
    int spawned = core_process_spawn(&spawn, &child);
    close(to_child[0]);
    close(from_out[1]);
    close(from_err[1]);
    CoreProcessStream out = {{0}, from_out[0], 0}, err = {{0}, from_err[0], 0};
    if (spawned) {
        close(to_child[1]);
        close(from_out[0]);
        close(from_err[0]);
        *answer = core_process_answer(2, spawned, &out, &err);
        status = 0;
        goto cleanup;
    }
    core_flush_before_wait();
    /* A write to a child that no longer reads must not kill the guest: block SIGPIPE here for the exchange. */
    sigset_t blocked, previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGPIPE);
    pthread_sigmask(SIG_BLOCK, &blocked, &previous);
    for (int descriptor = 0; descriptor < 3; ++descriptor) {
        int fd = descriptor == 0 ? to_child[1] : descriptor == 1 ? out.descriptor : err.descriptor;
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
    }
    int writing = to_child[1];
    size_t written = 0;
    if (!request.input_length) { close(writing); writing = -1; }
    size_t limit = (size_t)limit_value;
    while (out.descriptor >= 0 || err.descriptor >= 0 || writing >= 0) {
        struct pollfd watched[3];
        nfds_t watching = 0;
        int which[3];
        if (writing >= 0) { watched[watching] = (struct pollfd){writing, POLLOUT, 0}; which[watching++] = 0; }
        if (out.descriptor >= 0) { watched[watching] = (struct pollfd){out.descriptor, POLLIN, 0}; which[watching++] = 1; }
        if (err.descriptor >= 0) { watched[watching] = (struct pollfd){err.descriptor, POLLIN, 0}; which[watching++] = 2; }
        if (poll(watched, watching, -1) < 0) { if (errno == EINTR) continue; break; }
        for (nfds_t i = 0; i < watching; ++i) {
            if (!watched[i].revents) continue;
            if (which[i] == 1) core_process_drain(&out, limit);
            else if (which[i] == 2) core_process_drain(&err, limit);
            else {
                ssize_t sent = write(writing, request.input + written, request.input_length - written);
                if (sent > 0) written += (size_t)sent;
                bool finished = written == request.input_length;
                if ((sent < 0 && errno != EAGAIN && errno != EINTR) || finished) { close(writing); writing = -1; }
            }
        }
    }
    if (writing >= 0) close(writing);
    if (out.descriptor >= 0) close(out.descriptor);
    if (err.descriptor >= 0) close(err.descriptor);
    int wait_status = 0;
    while (waitpid(child, &wait_status, 0) < 0 && errno == EINTR) {}
    /* Take back a SIGPIPE this thread raised, so unblocking does not deliver it. */
    struct timespec instant = {0, 0};
    while (sigtimedwait(&blocked, NULL, &instant) == SIGPIPE) {}
    pthread_sigmask(SIG_SETMASK, &previous, NULL);
    *answer = WIFEXITED(wait_status) ? core_process_answer(0, WEXITSTATUS(wait_status), &out, &err)
                                     : core_process_answer(1, WIFSIGNALED(wait_status) ? WTERMSIG(wait_status) : 0, &out, &err);
    status = 0;
cleanup:
    core_io_bytes_release(&out.kept);
    core_io_bytes_release(&err.kept);
    goto done;
pipes:
    for (int i = 0; i < 2; ++i) {
        if (to_child[i] >= 0) close(to_child[i]);
        if (from_out[i] >= 0) close(from_out[i]);
        if (from_err[i] >= 0) close(from_err[i]);
    }
done:
    core_process_request_free(&request);
    return status;
}

/* ---- started programs (FR6) ----------------------------------------------------------------------------------------
 * `process.start` starts a program and returns at once; `process.signal` and `process.wait_within` reach it by its
 * number. The table holds every started program no wait has reaped, so a signal goes only to a program this program
 * started and is still its child (a zombie at worst), never to a number the system has given to another process: a
 * wait sees the end without reaping (`WNOWAIT`), then reaps and forgets the child under the table's lock, the lock a
 * signal holds while it sends. */
static pthread_mutex_t core_process_table_lock = PTHREAD_MUTEX_INITIALIZER;
static pid_t *core_process_table;
static size_t core_process_table_count, core_process_table_room;

static void core_process_remember(pid_t child) {
    pthread_mutex_lock(&core_process_table_lock);
    if (core_process_table_count == core_process_table_room) {
        core_process_table_room = core_process_table_room ? core_process_table_room * 2 : 8;
        pid_t *grown = realloc(core_process_table, core_process_table_room * sizeof *grown);
        if (!grown) out_of_memory();
        core_process_table = grown;
    }
    core_process_table[core_process_table_count++] = child;
    pthread_mutex_unlock(&core_process_table_lock);
}

/* The table's slot of `child`, or the count when this program started no such child or has reaped it. Under the lock. */
static size_t core_process_slot(pid_t child) {
    size_t slot = 0;
    while (slot < core_process_table_count && core_process_table[slot] != child) ++slot;
    return slot;
}

static const char core_process_unknown[] = "no program this program started has that process number, or a wait already saw it end";

/* An answer's varint fields: an outcome octet and a number. */
static myl_block *core_process_pair(int outcome, int64_t code) {
    CoreIoBytes answer = {0};
    unsigned char octet = (unsigned char)outcome;
    core_io_append(&answer, &octet, 1);
    core_process_put_varint(&answer, code);
    myl_block *block = core_io_string(answer.bytes, answer.length, 0);
    core_io_bytes_release(&answer);
    return block;
}

static int core_process_varints(const unsigned char *data, size_t length, int64_t *first, int64_t *second) {
    CoreProcessCursor cursor = {data, data + length};
    uint64_t a, b;
    if (!core_process_uvarint(&cursor, &a) || !core_process_uvarint(&cursor, &b) || cursor.at != cursor.end) return 0;
    *first = (a & 1) ? (int64_t)~(a >> 1) : (int64_t)(a >> 1);
    *second = (b & 1) ? (int64_t)~(b >> 1) : (int64_t)(b >> 1);
    return 1;
}

/* An output file of a started program: emptied when it is opened, and written at its end, so the program's standard
 * output and standard error may share one file the way `>LOG 2>&1` shares it. Without a path the program writes to
 * /dev/null, so nothing this program holds (its own pipes, say) stays open in a program that outlives a wait. */
static int core_process_output(const char *path) {
    if (!path) return open("/dev/null", O_WRONLY | O_CLOEXEC);
    return open(path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND | O_CLOEXEC, 0666);
}

/* A destination after the request: u8 0 (/dev/null), u8 1 and the path of a file, or u8 2 (this program's own standard
 * output or standard error, which `*caller` says). */
static int core_process_path(CoreProcessCursor *cursor, char **path, bool *caller) {
    *path = NULL;
    *caller = false;
    if (cursor->at >= cursor->end) return 0;
    unsigned present = *cursor->at++;
    if (present == 0) return 1;
    if (present == 2) { *caller = true; return 1; }
    if (present != 1) return 0;
    return (*path = core_process_field(cursor, NULL)) != NULL;
}

/* `process_control` operations 6 and 9: start the request with its standard input /dev/null and its output in the given files
 * (or /dev/null, or this program's own standard output and standard error). The answer is u8 0 and the process number,
 * u8 2 and the errno of a program that did not start, or u8 3, the errno and the path of an output file that could not
 * be opened. A program that writes to this program's own streams starts after what this program has buffered for them
 * is flushed, so what it printed first comes first. Operation 9 (`own_group`) also makes the program the leader of a process
 * group of its own, which is how a program of a `process` group is started. */
static int core_process_start(const unsigned char *data, size_t length, bool own_group, myl_block **answer,
                              const char **reason) {
    CoreProcessCursor cursor = {data, data + length};
    CoreProcessRequest request;
    char *paths[2] = {NULL, NULL};
    bool caller[2] = {false, false};
    int descriptors[3] = {-1, -1, -1};
    int status = 3;
    *reason = "the process request is damaged";
    if (!core_process_request(&cursor, &request) || request.input_length || !core_process_path(&cursor, &paths[0], &caller[0]) ||
        !core_process_path(&cursor, &paths[1], &caller[1]) || cursor.at != cursor.end) goto done;
    status = 0;
    if ((descriptors[0] = open("/dev/null", O_RDONLY | O_CLOEXEC)) < 0) {
        *answer = core_process_pair(2, errno);
        goto done;
    }
    if (caller[0] || caller[1]) flush_all();
    for (int stream = 0; stream < 2; ++stream) {
        bool shared = stream == 1 && paths[0] && paths[1] && !strcmp(paths[0], paths[1]);
        if (caller[stream]) descriptors[stream + 1] = fcntl(stream + 1, F_DUPFD_CLOEXEC, 3);
        else descriptors[stream + 1] = shared ? dup(descriptors[1]) : core_process_output(paths[stream]);
        if (shared && descriptors[2] >= 0) (void)fcntl(descriptors[2], F_SETFD, FD_CLOEXEC);
        if (descriptors[stream + 1] >= 0) continue;
        CoreIoBytes failed = {0};
        unsigned char octet = 3;
        core_io_append(&failed, &octet, 1);
        core_process_put_varint(&failed, errno);
        const char *named = caller[stream] ? (stream ? "this program's standard error" : "this program's standard output")
                                           : paths[stream] ? paths[stream] : "/dev/null";
        core_process_put_uvarint(&failed, strlen(named));
        core_io_append(&failed, (const unsigned char *)named, strlen(named));
        *answer = core_io_string(failed.bytes, failed.length, 0);
        core_io_bytes_release(&failed);
        goto done;
    }
    CoreProcessSpawn spawn = {request.arguments, request.environment, request.directory_length ? request.directory : NULL,
                              {descriptors[0], descriptors[1], descriptors[2]}, true, own_group};
    pid_t child = 0;
    int spawned = core_process_spawn(&spawn, &child);
    if (!spawned) core_process_remember(child);
    *answer = spawned ? core_process_pair(2, spawned) : core_process_pair(0, child);
done:
    for (int i = 0; i < 3; ++i) if (descriptors[i] >= 0) close(descriptors[i]);
    free(paths[0]);
    free(paths[1]);
    core_process_request_free(&request);
    return status;
}

/* `process_control` operation 7: send signal `number` to the started program `child`. */
static int core_process_signal(const unsigned char *data, size_t length, myl_block **answer, const char **reason) {
    int64_t child, number;
    *reason = "the signal request is damaged";
    if (!core_process_varints(data, length, &child, &number) || child <= 0 || child > INT_MAX) return 3;
    if (number < 1 || number >= NSIG) { *reason = "a signal number is 1 to 64"; return 3; }
    pthread_mutex_lock(&core_process_table_lock);
    bool known = core_process_slot((pid_t)child) < core_process_table_count;
    int sent = known ? kill((pid_t)child, (int)number) : 0;
    int code = errno;
    pthread_mutex_unlock(&core_process_table_lock);
    if (!known) { *reason = core_process_unknown; return 2; }
    if (sent) { *reason = code == EINVAL ? "the system has no such signal" : "the system refused to send the signal"; return 3; }
    *answer = core_io_string("", 0, 0);
    return 0;
}

static int64_t core_process_now_ms(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

/* Whether the started program `child` has ended, without reaping it: 1 ended, 0 running, -1 the wait failed. */
static int core_process_ended(pid_t child, bool block) {
    for (;;) {
        siginfo_t info;
        memset(&info, 0, sizeof info);
        if (waitid(P_PID, (id_t)child, &info, WEXITED | WNOWAIT | (block ? 0 : WNOHANG)) == 0) return info.si_pid != 0;
        if (errno != EINTR) return -1;
    }
}

/* Reap the started program `child`, which a wait has seen end, and forget it. Answers 1 with its wait status, or 0. The
 * table's lock is held across the reap and the forgetting, so a signal never meets a number the system has reused. */
static int core_process_reap(pid_t child, int *wait_status) {
    pthread_mutex_lock(&core_process_table_lock);
    pid_t reaped;
    while ((reaped = waitpid(child, wait_status, WNOHANG)) < 0 && errno == EINTR) {}
    size_t slot = core_process_slot(child);
    if (reaped == child && slot < core_process_table_count)
        core_process_table[slot] = core_process_table[--core_process_table_count];
    pthread_mutex_unlock(&core_process_table_lock);
    return reaped == child;
}

/* `process_control` operation 8: wait up to `millis` milliseconds (negative: without limit) for the started program
 * `child` to end. The answer is u8 0 (still running) and 0, u8 1 and its exit status, or u8 2 and the signal that ended
 * it. A child that ended is reaped and leaves the table. The wait is a pidfd poll where the kernel has one, else a poll
 * of the child every 10 ms. */
static int core_process_await(const unsigned char *data, size_t length, myl_block **answer, const char **reason) {
    int64_t child, millis;
    *reason = "the wait request is damaged";
    if (!core_process_varints(data, length, &child, &millis) || child <= 0 || child > INT_MAX) return 3;
    pthread_mutex_lock(&core_process_table_lock);
    bool known = core_process_slot((pid_t)child) < core_process_table_count;
    pthread_mutex_unlock(&core_process_table_lock);
    if (!known) { *reason = core_process_unknown; return 2; }
    if (millis != 0) core_flush_before_wait();
    int ended = core_process_ended((pid_t)child, millis < 0);
    if (ended == 0 && millis > 0) {
        int handle = (int)syscall(SYS_pidfd_open, (pid_t)child, 0);
        int64_t deadline = core_process_now_ms() + millis;
        while (ended == 0) {
            int64_t left = deadline - core_process_now_ms();
            if (left <= 0) break;
            if (handle >= 0) {
                struct pollfd watched = {handle, POLLIN, 0};
                if (poll(&watched, 1, left > INT_MAX ? INT_MAX : (int)left) < 0 && errno != EINTR) break;
            } else {
                struct timespec pause = {0, (left < 10 ? left : 10) * 1000000};
                nanosleep(&pause, NULL);
            }
            ended = core_process_ended((pid_t)child, false);
        }
        if (handle >= 0) close(handle);
    }
    *reason = "waiting for the program failed";
    if (ended < 0) return 3;
    if (ended == 0) { *answer = core_process_pair(0, 0); return 0; }
    int wait_status = 0;
    if (!core_process_reap((pid_t)child, &wait_status)) return 3;
    *answer = WIFEXITED(wait_status) ? core_process_pair(1, WEXITSTATUS(wait_status))
                                     : core_process_pair(2, WIFSIGNALED(wait_status) ? WTERMSIG(wait_status) : 0);
    return 0;
}

/* ---- programs of a group ------------------------------------------------------------------------------------------
 * A `process` group is kept by the Selka module (its programs' numbers and keys); the runtime keeps the same table of
 * started programs and starts each program of a group as the leader of a process group of its own, so `kill(-pid)` reaches
 * what the program started too. The group's operations take the numbers of the programs they concern: 9 starts one (as 6,
 * in a process group of its own), 10 signals one and what it started, 11 waits for the first of several to end and 12 ends
 * several (SIGTERM, a grace, SIGKILL, a wait). Each number must be a started program no wait has reaped. */

/* The varint (zigzag) at the cursor. */
static int core_process_varint(CoreProcessCursor *cursor, int64_t *out) {
    uint64_t raw;
    if (!core_process_uvarint(cursor, &raw)) return 0;
    *out = (raw & 1) ? (int64_t)~(raw >> 1) : (int64_t)(raw >> 1);
    return 1;
}

/* A request of operation 11 or 12: a varint (the time limit or the grace), a count and that many process numbers. On
 * success `*pids` is a list the caller frees, every number a started program no wait has reaped, and the count is at least
 * 1. */
static int core_process_pids(const unsigned char *data, size_t length, int64_t *first, pid_t **pids, size_t *count,
                             const char **reason) {
    CoreProcessCursor cursor = {data, data + length};
    uint64_t wanted;
    *pids = NULL;
    *reason = "the request is damaged";
    if (!core_process_varint(&cursor, first) || !core_process_uvarint(&cursor, &wanted) || wanted < 1 ||
        wanted > (uint64_t)(cursor.end - cursor.at))
        return 0;
    pid_t *found = malloc((size_t)wanted * sizeof *found);
    if (!found) out_of_memory();
    for (size_t i = 0; i < (size_t)wanted; ++i) {
        int64_t number;
        if (!core_process_varint(&cursor, &number) || number <= 1 || number > INT_MAX) { free(found); return 0; }
        found[i] = (pid_t)number;
    }
    if (cursor.at != cursor.end) { free(found); return 0; }
    pthread_mutex_lock(&core_process_table_lock);
    bool known = true;
    for (size_t i = 0; i < (size_t)wanted && known; ++i) known = core_process_slot(found[i]) < core_process_table_count;
    pthread_mutex_unlock(&core_process_table_lock);
    if (!known) { free(found); *reason = core_process_unknown; return 0; }
    *pids = found;
    *count = (size_t)wanted;
    return 1;
}

/* Wait until `need` of the started programs `children` have ended (none is reaped), or `millis` milliseconds have passed
 * (negative: no limit; 0: look once). Answers how many have ended, or -1 when a wait failed, and in `*first` the position
 * of the first of them in the list (the count when none). The wait is one `poll` of every program's pidfd, so it sleeps
 * until a program ends and then looks again; only a program whose pidfd could not be opened (a kernel before Linux 5.3,
 * or no descriptor to spare) is looked at every 10 ms instead. */
static ssize_t core_process_wait_set(const pid_t *children, size_t count, int64_t millis, size_t need, size_t *first) {
    int *handles = malloc(count * sizeof *handles);
    struct pollfd *watched = malloc(count * sizeof *watched);
    bool *over = malloc(count * sizeof *over);
    if (!handles || !watched || !over) out_of_memory();
    bool opened = false;
    if (millis > ((int64_t)1 << 50)) millis = -1;
    int64_t deadline = millis > 0 ? core_process_now_ms() + millis : 0;
    ssize_t result = -1;
    for (;;) {
        size_t ended = 0;
        *first = count;
        for (size_t i = 0; i < count; ++i) {
            int state = core_process_ended(children[i], false);
            if (state < 0) goto done;
            over[i] = state != 0;
            if (state) {
                if (*first == count) *first = i;
                ++ended;
            }
        }
        result = (ssize_t)ended;
        if (ended >= need || millis == 0) break;
        int64_t left = millis < 0 ? -1 : deadline - core_process_now_ms();
        if (millis > 0 && left <= 0) break;
        if (!opened) {
            for (size_t i = 0; i < count; ++i) handles[i] = (int)syscall(SYS_pidfd_open, children[i], 0);
            opened = true;
        }
        size_t unwatched = 0;
        for (size_t i = 0; i < count; ++i) {
            watched[i] = (struct pollfd){over[i] || handles[i] < 0 ? -1 : handles[i], POLLIN, 0};
            if (!over[i] && handles[i] < 0) ++unwatched;
        }
        int timeout = left < 0 ? -1 : left > INT_MAX ? INT_MAX : (int)left;
        if (unwatched && (timeout < 0 || timeout > 10)) timeout = 10;
        if (poll(watched, (nfds_t)count, timeout) < 0 && errno != EINTR) { result = -1; break; }
    }
done:
    if (opened) for (size_t i = 0; i < count; ++i) if (handles[i] >= 0) close(handles[i]);
    free(handles);
    free(watched);
    free(over);
    return result;
}

/* `kill` for every program of the list and what each started: signal `number` to the process group of each. A group that
 * is already empty is not an error. */
static void core_process_kill_groups(const pid_t *children, size_t count, int number) {
    pthread_mutex_lock(&core_process_table_lock);
    for (size_t i = 0; i < count; ++i) if (core_process_slot(children[i]) < core_process_table_count) (void)kill(-children[i], number);
    pthread_mutex_unlock(&core_process_table_lock);
}

/* `process_control` operation 10: send signal `number` to the process group of the started program `child`. */
static int core_process_signal_group(const unsigned char *data, size_t length, myl_block **answer, const char **reason) {
    int64_t child, number;
    *reason = "the signal request is damaged";
    if (!core_process_varints(data, length, &child, &number) || child <= 1 || child > INT_MAX) return 3;
    if (number < 1 || number >= NSIG) { *reason = "a signal number is 1 to 64"; return 3; }
    pthread_mutex_lock(&core_process_table_lock);
    bool known = core_process_slot((pid_t)child) < core_process_table_count;
    int sent = known ? kill(-(pid_t)child, (int)number) : 0;
    int code = errno;
    pthread_mutex_unlock(&core_process_table_lock);
    if (!known) { *reason = core_process_unknown; return 2; }
    if (sent && code != ESRCH) { *reason = code == EINVAL ? "the system has no such signal" : "the system refused to send the signal"; return 3; }
    *answer = core_io_string("", 0, 0);
    return 0;
}

/* The answer of operation 11 or 12 for one reaped program: u8 1 (exited) or 2 (ended by a signal) and its status or signal. */
static void core_process_put_ended(CoreIoBytes *bytes, int wait_status) {
    unsigned char outcome = WIFEXITED(wait_status) ? 1 : 2;
    core_io_append(bytes, &outcome, 1);
    core_process_put_varint(bytes, WIFEXITED(wait_status) ? WEXITSTATUS(wait_status) : WIFSIGNALED(wait_status) ? WTERMSIG(wait_status) : 0);
}

/* `process_control` operation 11: wait up to `millis` milliseconds (negative: without limit) for the first of the listed
 * started programs to end, the first in the list when several have. The answer is u8 0 (none ended in time), or u8 1, the
 * program's position in the list (varint), then u8 1 and its exit status or u8 2 and the signal that ended it. The
 * program that is answered is reaped and leaves the table; the others are not touched. */
static int core_process_await_any(const unsigned char *data, size_t length, myl_block **answer, const char **reason) {
    int64_t millis;
    pid_t *children;
    size_t count, first;
    if (!core_process_pids(data, length, &millis, &children, &count, reason)) return 3;
    if (millis != 0) core_flush_before_wait();
    ssize_t ended = core_process_wait_set(children, count, millis, 1, &first);
    int status = 3;
    *reason = "waiting for the programs failed";
    CoreIoBytes bytes = {0};
    int wait_status = 0;
    if (ended < 0) goto done;
    if (ended == 0) {
        unsigned char none = 0;
        core_io_append(&bytes, &none, 1);
    } else {
        if (!core_process_reap(children[first], &wait_status)) goto done;
        unsigned char found = 1;
        core_io_append(&bytes, &found, 1);
        core_process_put_varint(&bytes, (int64_t)first);
        core_process_put_ended(&bytes, wait_status);
    }
    *answer = core_io_string(bytes.bytes, bytes.length, 0);
    status = 0;
done:
    core_io_bytes_release(&bytes);
    free(children);
    return status;
}

/* `process_control` operation 12: end the listed started programs and everything they started. They are sent SIGTERM (to
 * their process groups), given `grace` milliseconds (negative: none) to end, sent SIGKILL (to every process group, those of
 * programs that ended too, so nothing that ignored SIGTERM stays behind) and waited for. The answer is, for each program in
 * the list's order, u8 1 and its exit status or u8 2 and the signal that ended it; every one is reaped. */
static int core_process_stop_group(const unsigned char *data, size_t length, myl_block **answer, const char **reason) {
    int64_t grace;
    pid_t *children;
    size_t count, first;
    if (!core_process_pids(data, length, &grace, &children, &count, reason)) return 3;
    core_flush_before_wait();
    core_process_kill_groups(children, count, SIGTERM);
    int status = 3;
    *reason = "waiting for the programs failed";
    CoreIoBytes bytes = {0};
    if (core_process_wait_set(children, count, grace < 0 ? 0 : grace, count, &first) < 0) goto done;
    core_process_kill_groups(children, count, SIGKILL);
    if (core_process_wait_set(children, count, -1, count, &first) < 0) goto done;
    for (size_t i = 0; i < count; ++i) {
        int wait_status = 0;
        if (!core_process_reap(children[i], &wait_status)) goto done;
        core_process_put_ended(&bytes, wait_status);
    }
    *answer = core_io_string(bytes.bytes, bytes.length, 0);
    status = 0;
done:
    core_io_bytes_release(&bytes);
    free(children);
    return status;
}

/* ---- the scripted Process ----------------------------------------------------------------------------------------
 * A test's `Process` (`process.scripted`, or the `proc` parameter a test is handed) starts nothing. It keeps a script, the
 * packed rules the `process` module builds, and a log, the packed requests it was asked to run. The module reads and writes
 * both through `process_control`, so matching a request against the rules is Selka code and the runtime only holds the
 * two byte strings; the same state is as deterministic as the program text that built it. `op` selects the operation:
 *   0 script       the script (a real Process fails: the module then starts the program)
 *   1 set script   replace the script with `data`
 *   2 calls        the log
 *   3 log          append `data` to the log
 *   4 executable   the running program's absolute path (`/proc/self/exe`; a real Process only)
 *   5 expect       append `data` to the script
 * and, on a real Process only, the started programs above:
 *   6 start        start the request in `data` without waiting (`core_process_start`)
 *   7 signal       send a signal to a started program (`core_process_signal`)
 *   8 wait         wait for a started program within a limit (`core_process_await`)
 * and the programs of a group (see "programs of a group" above):
 *   9 group start  start as 6, in a process group of its own
 *   10 group signal send a signal to the process group of a started program (`core_process_signal_group`)
 *   11 wait any    wait for the first of several started programs to end (`core_process_await_any`)
 *   12 stop group  end several started programs and what they started (`core_process_stop_group`)
 */
static void core_process_set(unsigned char **target, size_t *length, const unsigned char *data, size_t size) {
    unsigned char *copy = malloc(size ? size : 1);
    if (!copy) out_of_memory();
    if (size) memcpy(copy, data, size);
    free(*target);
    *target = copy;
    *length = size;
}

static void core_process_add(unsigned char **target, size_t *length, const unsigned char *data, size_t size) {
    unsigned char *grown = realloc(*target, *length + size ? *length + size : 1);
    if (!grown) out_of_memory();
    if (size) memcpy(grown + *length, data, size);
    *target = grown;
    *length += size;
}

static myl_block *core_process_control_entry(myl_block *cap, const unsigned char *data, size_t length, int64_t op) {
    CoreIoAuthority *authority = core_io_authority(cap);
    if (authority->family != 7) core_io_fail("InvalidCapability");
    CoreIoState *state = core_io_state(cap);
    myl_block *answer = NULL;
    const char *reason = "";
    int status = 0;
    if (op == 4) {
        char path[4096];
        ssize_t size = state->test ? -1 : readlink("/proc/self/exe", path, sizeof path);
        if (state->test) { status = 2; reason = "a scripted Process runs no program"; }
        else if (size <= 0 || size >= (ssize_t)sizeof path) { status = 3; reason = "the running program's path could not be read"; }
        else answer = core_io_string(path, (size_t)size, 0);
    } else if (op >= 6 && op <= 12) {
        if (state->test) { status = 2; reason = "a scripted Process starts, signals and waits for no program"; }
        else {
            core_io_os_reason = NULL;
            status = op == 6    ? core_process_start(data, length, false, &answer, &reason)
                     : op == 7  ? core_process_signal(data, length, &answer, &reason)
                     : op == 8  ? core_process_await(data, length, &answer, &reason)
                     : op == 9  ? core_process_start(data, length, true, &answer, &reason)
                     : op == 10 ? core_process_signal_group(data, length, &answer, &reason)
                     : op == 11 ? core_process_await_any(data, length, &answer, &reason)
                                : core_process_stop_group(data, length, &answer, &reason);
        }
    } else if (!state->test) {
        status = 2;
        reason = "this Process is not a scripted Process";
    } else if (op == 0) answer = core_io_string(state->script, state->script_length, 0);
    else if (op == 2) answer = core_io_string(state->calls, state->calls_length, 0);
    else if (op == 1 || op == 3 || op == 5) {
        if (op == 1) core_process_set(&state->script, &state->script_length, data, length);
        else if (op == 3) core_process_add(&state->calls, &state->calls_length, data, length);
        else core_process_add(&state->script, &state->script_length, data, length);
        answer = core_io_string("", 0, 0);
    } else { status = 3; reason = "unknown scripted Process operation"; }
    myl_block *error = NULL;
    if (status) {
        const char *prefix = op == 4                 ? "executable path: "
                             : op == 6 || op == 9    ? "start: "
                             : op == 7 || op == 10   ? "signal: "
                             : op == 8 || op == 11   ? "wait: "
                             : op == 12              ? "stop: "
                                                     : "process_control: ";
        size_t size = strlen(prefix) + strlen(reason);
        char *text = malloc(size + 1);
        if (!text) out_of_memory();
        memcpy(text, prefix, strlen(prefix));
        memcpy(text + strlen(prefix), reason, strlen(reason) + 1);
        error = core_io_string(text, size, 1);
        free(text);
    }
    return core_io_result(status, (uint64_t)(uintptr_t)answer, error, 1);
}

myl_block *myl_core_process_control(int64_t cap, myl_block *data, int64_t op) {
    CORE_IO_GUARD;
    return core_process_control_entry(core_io_handle(cap), block_data(data), (size_t)data->len, op);
}

/* The span form (C9): a borrowed `bytes` operand is read in place. */
myl_block *myl_core_span_process_control(int64_t cap, const unsigned char *data, uint64_t length, int64_t op) {
    CORE_IO_GUARD;
    return core_process_control_entry(core_io_handle(cap), data, (size_t)length, op);
}

/* `process.scripted`: a stand-in Process holding the packed rules `script`. A test's `proc` parameter is the same stand-in
 * with an empty script (`myl_core_stand_in`). */
static int64_t core_process_scripted(const unsigned char *script, size_t length) {
    myl_block *provider = core_io_provider(7, 1, 0, NULL);
    CoreIoState *state = (CoreIoState *)block_data(provider);
    core_process_set(&state->script, &state->script_length, script, length);
    return core_io_publish(core_io_cap(7, 7, provider, NULL, NULL));
}

int64_t myl_core_process_scripted(myl_block *script) {
    CORE_IO_GUARD;
    return core_process_scripted(block_data(script), (size_t)script->len);
}

int64_t myl_core_span_process_scripted(const unsigned char *script, uint64_t length) {
    CORE_IO_GUARD;
    return core_process_scripted(script, (size_t)length);
}

/* `run_process(proc, request, limit)`: the capability is checked, the program runs to completion, and the answer
 * (or the reason it could not run) goes back as a result box like every other capability call. */
static myl_block *core_process_entry(myl_block *cap, const unsigned char *request, size_t length, int64_t limit) {
    CoreIoAuthority *authority = core_io_authority(cap);
    if (authority->family != 7) core_io_fail("InvalidCapability");
    myl_block *answer = NULL;
    const char *reason = "";
    int status;
    if (core_io_state(cap)->test) {
        status = 2;
        reason = "this Process is a stand-in that starts nothing";
    } else {
        core_io_os_reason = NULL;
        status = core_process_run(request, length, limit, &answer, &reason);
    }
    myl_block *error = NULL;
    if (status) {
        static const char prefix[] = "run_process: ";
        size_t size = sizeof prefix - 1 + strlen(reason);
        char *text = malloc(size + 1);
        if (!text) out_of_memory();
        memcpy(text, prefix, sizeof prefix - 1);
        memcpy(text + sizeof prefix - 1, reason, strlen(reason) + 1);
        error = core_io_string(text, size, 1);
        free(text);
    }
    return core_io_result(status, (uint64_t)(uintptr_t)answer, error, 1);
}

myl_block *myl_core_process_run(int64_t cap, myl_block *request, int64_t limit) {
    CORE_IO_GUARD;
    return core_process_entry(core_io_handle(cap), block_data(request), (size_t)request->len, limit);
}

/* The span form (C9): a borrowed `bytes` request is read in place. */
myl_block *myl_core_span_process_run(int64_t cap, const unsigned char *request, uint64_t request_length, int64_t limit) {
    CORE_IO_GUARD;
    return core_process_entry(core_io_handle(cap), request, (size_t)request_length, limit);
}
