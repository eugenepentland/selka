#include "core_rt_all.c"
#undef NDEBUG
#include <assert.h>

myl_block *myl_core_task_call(void *run, myl_block *env) {
    return ((myl_block *(*)(myl_block *))run)(env);
}
static _Atomic bool winner_ready;
static void *blocked_winner(void *unused) {
    (void)unused;
    core_worker_runtime_start();
    core_fatal_begin();
    atomic_store_explicit(&winner_ready, true, memory_order_release);
    for (;;) pause();
}
static myl_block *nothing(myl_block *env) { (void)env; return NULL; }
static void *locked_writer(void *unused) {
    (void)unused;
    core_worker_runtime_start();
    core_stream_lock();
    atomic_store_explicit(&winner_ready, true, memory_order_release);
    for (;;) pause();
}
static void reentry_signal(int signal_number) {
    (void)signal_number;
    core_fatal_begin();
    _exit(core_fatal_raw ? 0 : 91);
}
static void reentry_wait(void) {
    pthread_t writer;
    assert(!pthread_create(&writer, NULL, locked_writer, NULL));
    while (!atomic_load_explicit(&winner_ready, memory_order_acquire)) sched_yield();
    struct sigaction action = {0};
    action.sa_handler = reentry_signal;
    sigemptyset(&action.sa_mask);
    assert(!sigaction(SIGUSR1, &action, NULL));
    atomic_store(&core_fatal_winner, core_current_thread());
    core_fatal_owner = true;
    assert(!raise(SIGUSR1));
    _exit(92);
}
static void start_pool(void) {
    myl_block *group = myl_core_group_open();
    (void)myl_core_task_submit(group, nothing, NULL, -1);
    myl_core_group_close(group);
    myl_core_drop_owned(group);
}
static void alarm_mode(const char *mode) {
    if (!strcmp(mode, "alarm-worker")) {
        pthread_t worker;
        assert(!pthread_create(&worker, NULL, blocked_winner, NULL));
        while (!atomic_load_explicit(&winner_ready, memory_order_acquire)) sched_yield();
    } else {
        /* Interrupt the winner after its CAS, before its TLS owner flag. */
        atomic_store(&core_fatal_winner, (uint32_t)syscall(SYS_gettid));
    }
    core_run_arm(1);
    for (;;) pause();
}
static unsigned char output[1 << 20];
static void *pipe_writer(void *unused) {
    (void)unused;
    core_worker_runtime_start();
    memset(output, 'x', sizeof output);
    myl_core_output_begin(1);
    stream_write(&streams[0], output, sizeof output);
    myl_core_output_end(1);
    return NULL;
}
static void slow_pipe(void) {
    int descriptors[2];
    assert(!pipe(descriptors));
    int original = dup(STDOUT_FILENO);
    assert(original >= 0);
    /* Fork before starting any worker. This independent reader drains the pipe
       after the fatal parent's exit, so every byte has a deterministic oracle. */
    pid_t reader = fork();
    assert(reader >= 0);
    if (!reader) {
        close(descriptors[1]);
        unsigned char bytes[8192];
        ssize_t size = read(descriptors[0], bytes, 1);
        assert(size == 1);
        usleep(15000);
        assert(os_write(original, bytes, 1));
        while ((size = read(descriptors[0], bytes, sizeof bytes)) > 0)
            assert(os_write(original, bytes, (size_t)size));
        _exit(size == 0 ? 0 : 99);
    }
    close(descriptors[0]);
    assert(dup2(descriptors[1], STDOUT_FILENO) == STDOUT_FILENO);
    close(descriptors[1]);
    close(original);
    atomic_store(&core_pool_started, true);
    pthread_t writer;
    assert(!pthread_create(&writer, NULL, pipe_writer, NULL));
    while (!pthread_mutex_trylock(&core_stream_mutex)) {
        pthread_mutex_unlock(&core_stream_mutex);
        sched_yield();
    }
    core_running_task = (core_task_context){(uintptr_t)slow_pipe, 0, 37};
    static const myl_core_site site = {TRAP_DIVISION_BY_ZERO, 7, 3, 64, "//", "task", "fatal-task.selka"};
    myl_core_trap(&site, 1, 0);
}
int main(int argc, char **argv) {
    assert(argc == 2);
    myl_core_start();
    core_run_arm(5);
    const char *mode = argv[1];
    if (!strcmp(mode, "slow-pipe")) slow_pipe();
    start_pool();
    if (!strcmp(mode, "reentry-wait")) reentry_wait();
    if (!strcmp(mode, "exit")) core_io_fail("InvalidCapability");
    if (!strcmp(mode, "reentry")) {
        atomic_store(&core_fatal_winner, (uint32_t)syscall(SYS_gettid));
        core_fatal_begin();
        assert(core_fatal_owner);
        _exit(0);
    }
    alarm_mode(mode);
    return 98;
}
