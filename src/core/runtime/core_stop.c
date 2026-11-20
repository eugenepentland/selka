/* Hearing a stop: the `Stop` capability (FR5b, F-14; experiments/audit-work-20261111/FR5B.md, D-FR5B-1).
 *
 * A program whose `main` declares `stop: Stop` calls `myl_core_stop_listen` before main's first statement. It opens one
 * wake-up descriptor (an eventfd, close-on-exec) and installs a handler for SIGTERM and SIGINT; a signal that was ignored
 * when the program started stays ignored. A program that declares no `Stop` never calls it: no handler, no descriptor,
 * and the system's default action, so SIGTERM ends it with status 143 as before.
 *
 * The real `Stop` is handle 0. The handler counts the first stop: it sets `core_stop_heard` and writes the descriptor,
 * which every poller watches, so `network.wait` returns at once whichever thread took the signal. A second signal ends
 * the program (FR5-Q4), except the same signal from the same sender within CORE_STOP_COPY_NS of the first, however many
 * arrive, direct or forwarded: that is the same stop. `timeout` and other senders signal a process and then its group
 * back to back, and `selka run` passes its copy on (`src/wiring/run_signals.zig`, which marks it with CORE_STOP_MARK and
 * the original sender), so one stop can arrive two or three times and must not end the program before its goodbye. The
 * cost: a script's `kill; kill` from one process with no pause does not force; a different sender, a different signal,
 * Ctrl-C twice (the kernel's signal is never a copy) or half a second later does. For the second stop the default
 * action is put back and the signal raised again, so the program dies of it. (A rule that dropped only one forwarded
 * copy per direct signal was tried and withdrawn: under `timeout` it lost the goodbye in 4 of 20 runs.) The handler only uses atomics,
 * clock_gettime, write, sigaction and raise, all async-signal-safe; no thread is started.
 *
 * A stop that the program has not yet read through `process.stop_requested` is pending. While it is, the next wait of each
 * poller and the program's next sleep on the real clock end early, once each (core_poll.c, core_stop_sleep); every other
 * wait, and every wait once the stop is read, lasts as long as it asks. So a loop on `stop_requested` hears the stop at
 * once, a goodbye can wait for its clients, and a program that never reads its stop does not spin.
 *
 * A stand-in (`process.simulated_stop`, a test's `Stop` parameter) is a cell of its own, named by its address; no signal
 * reaches it and requesting it wakes nothing. Its cell lives until the process, or the test trial, ends. */
#include <limits.h>
#include <poll.h>
#include <sys/eventfd.h>

/* Two deliveries of one signal number from one sender closer than this are one stop (D-FR5B-1). */
#define CORE_STOP_COPY_NS 500000000LL
/* The high half of the value `selka run` forwards a signal with (`run_signals.zig`); the low half is the sender. */
#define CORE_STOP_MARK 0x4d594c53u

static atomic_int core_stop_listening;
static atomic_int core_stop_heard;
static atomic_int core_stop_seen;
static atomic_int core_stop_signalled;
/* Whether a sleep has already ended early for the pending stop. */
static atomic_int core_stop_slept;
static int core_stop_fd = -1;
static atomic_int core_stop_last_number;
static atomic_int core_stop_last_origin;
static atomic_llong core_stop_last_ns;
static atomic_flag core_stop_lock = ATOMIC_FLAG_INIT;

/* Whether this program declared a `Stop` and so has the handler. */
static inline int core_stop_installed(void) { return atomic_load_explicit(&core_stop_listening, memory_order_relaxed); }
/* Whether a stop has been heard on the real `Stop` that the program has not yet read: the waits end early on it. */
static inline int core_stop_pending(void) {
    return core_stop_installed() && atomic_load(&core_stop_heard) && !atomic_load(&core_stop_seen);
}
/* The wake-up descriptor while the program has not read its stop, or -1. */
static inline int core_stop_wake_descriptor(void) { return core_stop_installed() && !atomic_load(&core_stop_seen) ? core_stop_fd : -1; }

/* The real stop is set: the flag, and one write to the descriptor every waiting poller watches. */
static void core_stop_notify(void) {
    atomic_store(&core_stop_heard, 1);
    if (core_stop_fd >= 0) {
        uint64_t one = 1;
        ssize_t written = write(core_stop_fd, &one, sizeof one);
        (void)written;
    }
}

static long long core_stop_now_ns(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (long long)now.tv_sec * 1000000000LL + now.tv_nsec;
}

/* The handler for SIGTERM and SIGINT: the first stop, a copy of it (dropped), or the second stop (the default action). */
static void core_stop_handler(int number, siginfo_t *info, void *context) {
    (void)context;
    int saved = errno;
    /* The sender, or -1 for the kernel's own signal; a copy `selka run` forwarded names the sender it heard. */
    int origin = info->si_code == SI_KERNEL ? -1 : (int)info->si_pid;
    uint64_t value = (uint64_t)(uintptr_t)info->si_value.sival_ptr;
    if (info->si_code == SI_QUEUE && (uint32_t)(value >> 32) == CORE_STOP_MARK && info->si_pid == getppid()) origin = (int)(uint32_t)value;
    long long now = core_stop_now_ns();
    while (atomic_flag_test_and_set(&core_stop_lock)) {}
    if (!atomic_load(&core_stop_signalled)) {
        atomic_store(&core_stop_last_number, number);
        atomic_store(&core_stop_last_origin, origin);
        atomic_store(&core_stop_last_ns, now);
        atomic_store(&core_stop_signalled, 1);
        core_stop_notify();
    } else if (origin < 0 || origin != atomic_load(&core_stop_last_origin) || number != atomic_load(&core_stop_last_number) ||
               now - atomic_load(&core_stop_last_ns) >= CORE_STOP_COPY_NS) {
        struct sigaction plain;
        memset(&plain, 0, sizeof plain);
        plain.sa_handler = SIG_DFL;
        sigemptyset(&plain.sa_mask);
        (void)sigaction(number, &plain, NULL);
        /* Pending on this thread, which blocks it while the handler runs: delivered, by the default action, on return. */
        (void)raise(number);
    }
    atomic_flag_clear(&core_stop_lock);
    errno = saved;
}

/* `main(..., stop: Stop)`: hear SIGTERM and SIGINT from here on, and answer the real `Stop`, handle 0. */
int64_t myl_core_stop_listen(void) {
    if (core_stop_installed()) return 0;
    core_stop_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_sigaction = core_stop_handler;
    action.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&action.sa_mask);
    sigaddset(&action.sa_mask, SIGTERM);
    sigaddset(&action.sa_mask, SIGINT);
    const int heard[] = {SIGTERM, SIGINT};
    for (size_t i = 0; i < sizeof heard / sizeof heard[0]; ++i) {
        struct sigaction before;
        if (sigaction(heard[i], NULL, &before) == 0 && !(before.sa_flags & SA_SIGINFO) && before.sa_handler == SIG_IGN) continue;
        (void)sigaction(heard[i], &action, NULL);
    }
    atomic_store(&core_stop_listening, 1);
    return 0;
}

/* `process.simulated_stop()` and a test's `Stop` parameter: a stand-in no signal reaches, not yet requested. */
int64_t myl_core_stop_simulated(int64_t reserved) {
    (void)reserved;
    atomic_int *cell = calloc(1, sizeof *cell);
    if (!cell) out_of_memory();
    return (int64_t)(uintptr_t)cell;
}

/* `stop_control(stop, op)`: op 0 answers whether a stop was heard or requested (on the real `Stop`, reading it ends the
   pending state), op 1 requests one (on the real `Stop` that wakes the waits but is not a signal, so it does not arm the
   second-signal rule). */
bool myl_core_stop_control(int64_t handle, int64_t op) {
    if (handle == 0) {
        if (op == 1) { core_stop_notify(); return true; }
        int heard = atomic_load(&core_stop_heard);
        if (heard) atomic_store(&core_stop_seen, 1);
        return heard != 0;
    }
    atomic_int *cell = (atomic_int *)(uintptr_t)handle;
    if (op == 1) { atomic_store(cell, 1); return true; }
    return atomic_load(cell) != 0;
}

/* A sleep on the real clock in a program that declared a `Stop`: `nanoseconds` long, or until a pending stop, which ends
   the program's sleeps early once. It waits in ppoll on the wake-up descriptor, so a stop that arrives just before the
   wait still ends it; once a sleep has ended early, or the program has read its stop, the descriptor is not watched and a
   sleep lasts its whole length. An interruption measures the rest again. */
static void core_stop_sleep(int64_t nanoseconds) {
    long long deadline = core_stop_now_ns();
    deadline = deadline > LLONG_MAX - nanoseconds ? LLONG_MAX : deadline + nanoseconds;
    for (;;) {
        int wakes = !atomic_load(&core_stop_slept);
        if (wakes && core_stop_pending()) { atomic_store(&core_stop_slept, 1); return; }
        long long left = deadline - core_stop_now_ns();
        if (left <= 0) return;
        struct timespec wait = {.tv_sec = left / 1000000000LL, .tv_nsec = left % 1000000000LL};
        struct pollfd watched = {.fd = wakes ? core_stop_wake_descriptor() : -1, .events = POLLIN, .revents = 0};
        (void)ppoll(&watched, watched.fd >= 0 ? 1 : 0, &wait, NULL);
    }
}
