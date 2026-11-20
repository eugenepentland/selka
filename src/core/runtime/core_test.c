/* Core-owned property trial transport. The old generation/counting/shrinking
 * algorithms stay in Zig. Fork gives a fatal Core trap a bounded copied-value
 * trial boundary without skipping reference-count cleanup on a longjmp. */
#include <sys/wait.h>
#include <sys/resource.h>
#include <sys/time.h>
#include <signal.h>
#include <errno.h>
#include <ucontext.h>
#if defined(__linux__)
#include <sys/prctl.h>
#endif
static FILE *core_test_input, *core_test_output, *core_test_values;
static char *core_test_path;
static uint64_t core_test_trials;
static uint64_t core_test_steps;
static uint64_t core_test_executed;
static bool core_test_bounded;
static bool core_test_batch_parent;
/* A trial's work, written beside the batch's response file: the executed blocks of
 * program functions (the count the step ceiling charges, NEW-CORE-TEST-WORK-1) and
 * the peak managed bytes (`core_heap_test_peak`). `<response>.work.<trial>` holds
 * both as little-endian u64 words, so the runner reads them after the process
 * exits and no test stream is touched. A trial that traps ends its process before
 * the write, so it carries no counts. */
static void core_test_work_write(uint64_t trial, uint64_t executed, uint64_t peak) {
    if (!core_test_path) return;
    char path[4096];
    int written = snprintf(path, sizeof path, "%s.work.%llu", core_test_path, (unsigned long long)trial);
    if (written <= 0 || (size_t)written >= sizeof path) return;
    uint64_t words[2] = { executed, peak };
    unsigned char bytes[sizeof words];
    for (unsigned i = 0; i < sizeof words; ++i) bytes[i] = (unsigned char)(words[i / 8] >> (8 * (i % 8)));
    int descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (descriptor < 0) return;
    ssize_t ignored = write(descriptor, bytes, sizeof bytes);
    (void)ignored;
    close(descriptor);
}
/* Compatible additive helpers; existing runtime signatures and layouts stay fixed. */
/* Whether this process counts executed blocks (`selka test` always does; `selka
 * run` only with `--max-steps`), so `testing` can refuse a count it cannot read. */
static bool core_test_accounting;
/* A trial's wall-clock limit is exact to the millisecond: the trials of a batch
 * (NEW-CORE-TEST-BATCH-1) are each held to `--timeout-ms`, as a test alone is. The
 * same reset starts the trial's work: its executed-block count from zero and its
 * peak managed bytes from what the process already holds. */
void myl_core_test_limits(uint64_t steps, uint32_t timeout_ms) {
    core_test_steps=steps;core_test_bounded=steps!=0;core_test_executed=0;
    core_test_accounting=true;
    core_heap_test_begin();
    struct itimerval timer={{0,0},{(time_t)(timeout_ms/1000),(suseconds_t)(timeout_ms%1000)*1000}};
    (void)setitimer(ITIMER_REAL,&timer,NULL);
}
void myl_core_test_tick(uint64_t cost) {
    core_test_executed+=cost;
    if(!core_test_bounded)return;
    if(cost>core_test_steps)core_io_fail("R_STEP_LIMIT");
    core_test_steps-=cost;
}
/* The executed blocks of this test child so far (B5). The `testing` module reads it
 * twice around one workload; a process that carries no tick instrumentation has
 * nothing to read and traps `R_NO_STEP_ACCOUNTING`. */
int64_t myl_core_test_blocks(void) {
    if(!core_test_accounting)core_io_fail("R_NO_STEP_ACCOUNTING");
    return (int64_t)core_test_executed;
}
/* The managed blocks this test child has allocated so far, counting only while `on`
 * is true (B5). The caller reads the total before the workload, turns counting on,
 * then reads it again after the workload and turns counting off, so the measured
 * window is exactly `work(n)` and an ordinary test never updates the count. */
int64_t myl_core_test_allocations(bool on) {
    if(!core_test_accounting)core_io_fail("R_NO_STEP_ACCOUNTING");
    atomic_store_explicit(&test_count_allocations,on,memory_order_relaxed);
    return (int64_t)atomic_load_explicit(&test_allocations,memory_order_relaxed);
}
/* Call-depth and byte ceilings (`--max-frames`, `--max-memory`), installed by the
 * test entry before its first trial. Every call of an original function enters one
 * frame and leaves it before returning; the trial runs on a stack mapped for the
 * whole budget, 32 KiB per frame plus 8 MiB, as the old core maps it, so a budget
 * that is honest about depth is never cut short by the native stack. */
enum { CORE_TEST_FRAME_STACK = 32768, CORE_TEST_STACK_SLACK = 8 << 20 };
static uint64_t core_test_frame_limit, core_test_depth;
void myl_core_test_ceilings(uint32_t frames, uint64_t memory) {
    core_test_frame_limit = frames;
    core_heap_test_account();
    core_process_note_address_space();
    if (!memory) return;
    heap_ceiling = memory;
    /* The kernel's backstop: the address space at the ceiling plus 256 MiB, never loosened. */
    const uint64_t headroom = 256u << 20;
    struct rlimit limit;
    if (memory > UINT64_MAX - headroom || getrlimit(RLIMIT_AS, &limit)) return;
    rlim_t wanted = (rlim_t)(memory + headroom);
    if (limit.rlim_max != RLIM_INFINITY && wanted > limit.rlim_max) wanted = limit.rlim_max;
    if (limit.rlim_cur != RLIM_INFINITY && limit.rlim_cur <= wanted) return;
    limit.rlim_cur = wanted;
    (void)setrlimit(RLIMIT_AS, &limit);
}
/* `selka run`'s budgets (NEW-CORE-S5-RUN-1), installed once by the program's entry:
 * steps and frames as a test's, the byte ceiling with its `RLIMIT_AS` backstop, and a
 * wall-clock limit that ends the process as the old core's `--timeout` does. */
static void core_run_timed_out(int signal_number) {
    (void)signal_number;
    /* TASK-FATAL-1: a timer may interrupt the winner's CAS/owner interval or
       another fatal thread. It must never enter locks, unwinding, or parking. */
    static const char message[] = "R_TIMEOUT: wall-clock budget exhausted; raise it with --timeout=SECONDS\n";
    ssize_t ignored = write(STDERR_FILENO, message, sizeof message - 1);
    (void)ignored;
    _exit(1);
}
static void core_run_arm(uint64_t timeout_seconds) {
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_handler = core_run_timed_out;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGALRM, &action, NULL)) {
        static const char refused[] = "selka: cannot arm the --timeout wall-clock guard\n";
        ssize_t ignored = write(STDERR_FILENO, refused, sizeof refused - 1);
        (void)ignored;
        _exit(2);
    }
    alarm((unsigned)(timeout_seconds > UINT32_MAX ? UINT32_MAX : timeout_seconds));
}
/* One release of hints for the variables a program read before the rename (decision GH-D4): the old option and memory-limit names
   carried `--restrict` and the grants, and the byte ceiling. A program that ignored them would run with more rights than its user asked
   for, so one set (not empty) while its `SELKA_` spelling is not ends the process with status 2, before `main` runs. */
static void core_refuse_old_names(void) {
    const char *options = getenv("MYLANG_OPTIONS"), *limit = getenv("MYLANG_MEMORY_LIMIT"); /* rename: keep */
    if (options && *options && !getenv("SELKA_OPTIONS"))
        core_io_option_error("selka: MYLANG_OPTIONS is set and SELKA_OPTIONS is not: the variable is named SELKA_OPTIONS now, and this program ignores the old name\n%s", ""); /* rename: keep */
    if (limit && *limit && !getenv("SELKA_MEMORY_LIMIT"))
        core_io_option_error("selka: MYLANG_MEMORY_LIMIT is set and SELKA_MEMORY_LIMIT is not: the variable is named SELKA_MEMORY_LIMIT now, and this program ignores the old name\n%s", ""); /* rename: keep */
}
void myl_core_run_controls(uint64_t steps, uint32_t frames, uint64_t memory, uint32_t timeout_seconds) {
    static bool installed;
    if (installed) return;
    installed = true;
    core_refuse_old_names();
    core_test_steps = steps;
    core_test_bounded = steps != 0;
    /* `selka run` emits its tick only for a bounded run, so only then is there a
     * block count for `testing` to read. */
    core_test_accounting = steps != 0;
    myl_core_test_ceilings(frames, memory);
    if (timeout_seconds) core_run_arm(timeout_seconds);
}

/* Harness-only builds use identical instrumentation with a fresh startup ceiling.
 * Ordinary run/build entry points never call this helper or inspect this variable.
 * Missing, malformed and overflowing values fail closed; zero is unbounded. */
void myl_core_harness_run_controls(uint64_t unused, uint32_t frames, uint64_t memory, uint32_t timeout_seconds) {
    static bool installed;
    if (installed) return;
    installed = true;
    (void)unused;
    const char *text = getenv("SELKA_TEST_MAX_STEPS");
    uint64_t steps = 0;
    if (!text || !*text) core_io_option_error("selka: missing harness step ceiling%s\n", "");
    for (const char *digit = text; *digit; ++digit) {
        if (*digit < '0' || *digit > '9' || steps > (UINT64_MAX - (uint64_t)(*digit - '0')) / 10)
            core_io_option_error("selka: invalid harness step ceiling %s\n", text);
        steps = steps * 10 + (uint64_t)(*digit - '0');
    }
    myl_core_run_controls(steps, frames, memory, timeout_seconds);
}

/* ---- A built program's runtime options (NATIVE-ARGV-1) -------------------------- */

/* One positive decimal budget `prefix`VALUE into `slot`; zero, a non-number or a repeat
   ends the process with status 2. Whether `arg` spells this budget at all. */
static bool core_start_budget(const char *arg, const char *prefix, uint64_t *slot) {
    size_t width = strlen(prefix);
    if (strncmp(arg, prefix, width)) return false;
    if (*slot) core_io_option_error("selka: SELKA_OPTIONS names %s twice\n", prefix);
    uint64_t value = 0;
    const char *digit = arg + width;
    if (!*digit) core_io_option_error("selka: SELKA_OPTIONS names %s, which is not a positive budget\n", arg);
    for (; *digit; ++digit) {
        if (*digit < '0' || *digit > '9' || value > (UINT64_MAX - (uint64_t)(*digit - '0')) / 10)
            core_io_option_error("selka: SELKA_OPTIONS names %s, which is not a positive budget\n", arg);
        value = value * 10 + (uint64_t)(*digit - '0');
    }
    if (!value) core_io_option_error("selka: SELKA_OPTIONS names %s, which is not a positive budget\n", arg);
    *slot = value;
    return true;
}
/* A byte size into `bytes`: digits and an optional K, M or G (either case), as `selka run` reads
   `--max-memory` and `SELKA_MEMORY_LIMIT` (`memory_budget.parse`). False when `text` is not one or
   overflows. */
static bool core_start_size(const char *text, uint64_t *bytes) {
    uint64_t value = 0, scale = 1;
    const char *at = text;
    for (; *at >= '0' && *at <= '9'; ++at) {
        if (value > (UINT64_MAX - (uint64_t)(*at - '0')) / 10) return false;
        value = value * 10 + (uint64_t)(*at - '0');
    }
    if (at == text) return false;
    if (*at == 'K' || *at == 'k') scale = 1u << 10;
    else if (*at == 'M' || *at == 'm') scale = 1u << 20;
    else if (*at == 'G' || *at == 'g') scale = 1u << 30;
    else if (*at) return false;
    if (*at && at[1]) return false;
    if (value > UINT64_MAX / scale) return false;
    *bytes = value * scale;
    return true;
}
/* `SELKA_MEMORY_LIMIT` in bytes, or 0 (no ceiling) when it is unset or empty. Text that is not a
   byte size ends the process with status 2, as `selka run` refuses it (BIN-CEILING). */
static uint64_t core_start_memory_limit(void) {
    const char *text = getenv("SELKA_MEMORY_LIMIT");
    uint64_t bytes = 0;
    if (!text || !*text) return 0;
    if (!core_start_size(text, &bytes)) core_io_option_error("selka: SELKA_MEMORY_LIMIT names %s, which is not a byte size\n", text);
    return bytes;
}
/* A frame budget reserves 32 KiB of native stack per frame plus 8 MiB and two guard
   pages, as the old core maps it. One the address space cannot back (the process's
   `RLIMIT_AS`, or the byte ceiling `budget` plus 256 MiB of headroom) is reported with the
   reservation and the limit, and ends the process with status 2 (RUN-FRAME-BUDGET-1). */
static void core_start_frame_reservation(uint64_t frames, uint64_t budget) {
    long page_size = sysconf(_SC_PAGESIZE);
    uint64_t page = page_size > 0 ? (uint64_t)page_size : 4096;
    uint64_t fixed = (uint64_t)CORE_TEST_STACK_SLACK + 3 * page;
    bool addressable = frames <= (UINT64_MAX - fixed) / CORE_TEST_FRAME_STACK;
    uint64_t need = addressable ? ((frames * CORE_TEST_FRAME_STACK + CORE_TEST_STACK_SLACK + page - 1) / page + 2) * page : UINT64_MAX;
    uint64_t limit = UINT64_MAX;
    struct rlimit current;
    if (!getrlimit(RLIMIT_AS, &current) && current.rlim_cur != RLIM_INFINITY) limit = (uint64_t)current.rlim_cur;
    const uint64_t headroom = 256u << 20;
    if (budget && budget <= UINT64_MAX - headroom && budget + headroom < limit) limit = budget + headroom;
    if (limit == UINT64_MAX || need <= limit) return;
    char reserved[64];
    if (addressable) snprintf(reserved, sizeof reserved, "%.1f GiB of native stack", (double)need / 1073741824.0);
    else snprintf(reserved, sizeof reserved, "more native stack than can be addressed");
    flush_all();
    fprintf(stderr, "selka: a call-depth budget of %llu frames (--max-frames) reserves %s (32 KiB per frame), but this process may map only %.1f GiB; "
        "raise --max-memory (and SELKA_HOST_MEMORY_LIMIT, which a guest inherits) or lower --max-frames\n", (unsigned long long)frames, reserved, (double)limit / 1073741824.0);
    fflush(stderr);
    os_exit(2);
}
/* A budget this build cannot enforce: the old core's report and record, status 1. */
static void core_start_refuse(const char *code, const char *description, const char *advice) {
    char text[512];
    int length = snprintf(text, sizeof text, "error[%s]: %s: %s\n", code, description, advice);
    stream_write(&streams[1], text, (size_t)(length < (int)sizeof text ? length : (int)sizeof text - 1));
    char record[512];
    stream_write(&streams[1], record, core_operation_record(record, sizeof record, advice));
    flush_all();
    os_exit(1);
}
/* ---- The native stack's floor (QBE-FRAMEMAP-1) ------------------------------------
 * A program without a frame budget recurses until the stack's guard page. The fault is
 * reported as the old core's stack-floor guard reports it: `R_FRAME_LIMIT` located at the
 * innermost call site, with at most 16 frames, exit status 1. Any other fault keeps
 * its default action. The report runs on its own signal stack. */
enum { CORE_FLOOR_FRAMES = 16 };
static MYL_TLS uintptr_t core_stack_top;
static MYL_TLS size_t core_stack_bytes;
/* The report's signal stack is mapped at start, not a 256 KiB .bss array: a static array
   that large moves where the program's heap begins, which made allocation-heavy rows run
   slower or faster from one run to the next. */
enum { CORE_FLOOR_STACK = 256 << 10 };
/* The advice for the floor: no frame budget is in force here, and a built binary carries no budget
   code, so `--max-frames` is not what it can take. The stack limit is: the main thread's stack grows
   to `ulimit -s`; under `selka run`, `--max-frames=N` instead runs the program on a mapped stack. */
static const char *core_floor_hint(void) {
    return "call-depth limit reached: the native stack is full (a built binary has no --max-frames budget); "
           "raise the stack with `ulimit -s KBYTES` before starting it, or run it under `selka run --max-frames=N` "
           "(each frame reserves 32 KiB of stack, so --max-memory must cover N x 32 KiB)";
}
static void core_floor_default(int signal_number) {
    signal(signal_number, SIG_DFL);
}
static void core_floor_fault(int signal_number, siginfo_t *info, void *context) {
    (void)context;
    uintptr_t at = (uintptr_t)info->si_addr;
    const uintptr_t slack = 1u << 20;
    bool overflow = core_stack_top && core_stack_bytes && at <= core_stack_top &&
        core_stack_top - at + slack >= core_stack_bytes && core_stack_top - at <= core_stack_bytes + slack;
    if (!overflow) {
        core_floor_default(signal_number);
        return;
    }
    core_fatal_begin();
    void *pcs[160];
    int count = os_stack(pcs, 160);
    /* The interrupted instruction follows the signal frame: a `call` that could not push
       its return address is the caller's own call site; anything else is the prologue of
       the frame it would have entered, which is not reported. */
    char caller[1024] = "";
    trap_capture = caller;
    trap_capture_size = sizeof caller;
    int first = 0;
    while (first < count && dwarf_frames((uintptr_t)pcs[first], 0) == 0) ++first;
    bool calling = first < count && *(const unsigned char *)pcs[first] == 0xe8;
    if (first < count && !calling) {
        caller[0] = 0;
        ++first;
        if (first < count) dwarf_frames((uintptr_t)pcs[first] - 1, 0);
    }
    trap_capture = NULL;
    const char *where = strstr(caller, " at ");
    size_t named = strlen(caller);
    char text[1400];
    int length = where && named > 1 ? snprintf(text, sizeof text, "%.*s: error[R_FRAME_LIMIT]: %s\n", (int)(caller + named - 1 - (where + 4)), where + 4, core_floor_hint())
                                    : snprintf(text, sizeof text, "error[R_FRAME_LIMIT]: %s\n", core_floor_hint());
    stream_flush(&streams[0]);
    stream_write(&streams[1], text, (size_t)(length < (int)sizeof text ? length : (int)sizeof text - 1));
    trap_lines_left = CORE_FLOOR_FRAMES;
    for (int i = first; i < count && trap_lines_left != 0; ++i) {
        uintptr_t pc = (uintptr_t)pcs[i] - (i == first && calling ? 0 : 1);
        if (dwarf_frames(pc, 0) == 0) break;
    }
    flush_all();
    core_task_report();
    _exit(1);
}
static void core_floor_thread_install(bool worker) {
    unsigned char here;
    core_stack_top = (uintptr_t)&here;
    struct rlimit limit;
    core_stack_bytes = !getrlimit(RLIMIT_STACK, &limit) && limit.rlim_cur != RLIM_INFINITY ? (size_t)limit.rlim_cur : 0;
    if (worker) {
        pthread_attr_t attributes;
        if (pthread_getattr_np(pthread_self(), &attributes)) out_of_memory();
        void *base; size_t size;
        if (pthread_attr_getstack(&attributes, &base, &size)) out_of_memory();
        core_stack_top = (uintptr_t)base + size;
        core_stack_bytes = size;
        pthread_attr_destroy(&attributes);
    }
    void *floor_stack = mmap(NULL, CORE_FLOOR_STACK, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (floor_stack == MAP_FAILED) { if (worker) out_of_memory(); return; }
    stack_t alternate = { .ss_sp = floor_stack, .ss_size = CORE_FLOOR_STACK, .ss_flags = 0 };
    if (sigaltstack(&alternate, NULL)) { if (worker) out_of_memory(); return; }
}
/* Installed by the submitting thread before worker publication. Reinstalling
   deeper in that thread would move its recorded stack top and leak the old
   alternate stack; workers install only their own per-thread metadata. */
static bool core_floor_ready;
static void core_floor_install(void) {
    if (core_floor_ready) return;
    core_floor_thread_install(false);
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_sigaction = core_floor_fault;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK;
    sigemptyset(&action.sa_mask);
    (void)sigaction(SIGSEGV, &action, NULL);
    core_floor_ready = true;
}
static void core_worker_runtime_start(void) {
    sigset_t blocked;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGALRM);
    if (pthread_sigmask(SIG_BLOCK, &blocked, NULL)) out_of_memory();
    core_thread_register();
    core_floor_thread_install(true);
}
/* Read a built program's runtime options before `main` runs, as the old core read them
   (NATIVE-ARGV-1): grants and `--print-result` are their readers' (`core_io_initialize`,
   `myl_core_exit`), `--timeout=SECONDS` arms the wall-clock guard, and an unknown option
   or an unterminated quote ends the process with status 2. A built program carries no
   step or frame accounting (`selka run` compiles a budget in instead), so
   `--max-steps`/`--max-frames` are refused rather than ignored: `R_NO_STEP_ACCOUNTING`,
   `R_NO_FRAME_ACCOUNTING`, after a frame reservation the address space cannot back.

   The byte ceiling (BIN-CEILING) is `--max-memory=SIZE` in `SELKA_OPTIONS`, else
   `SELKA_MEMORY_LIMIT`, else none; `0` is none, and text that is not a size ends the process
   with status 2. It is installed as `selka run` installs its own (`myl_core_test_ceilings`):
   the same accounting, `R_MEMORY_BUDGET` past it and `RLIMIT_AS` lowered to it plus 256 MiB.
   `from_environment` is false for the entry of a program that carries a compiled-in budget
   (`myl_core_start_budgeted`): `myl_core_run_controls` installs that one, in the order the
   run settled, so the environment's ceiling is neither applied twice nor ahead of it. */
static void core_start_options(bool from_environment) {
    core_refuse_old_names();
    core_heap_tune();
    core_floor_install();
    /* FR-020: a write to a peer that has gone (a socket, a pipe) fails with EPIPE and is returned to the
       program as an error result, as the event loop's MSG_NOSIGNAL sends already are. A closed standard
       output or standard error ends the program quietly with status 141 (PIPE-1), not by the signal. Forked
       test trials inherit the disposition; the runtime never execs a program. */
    (void)signal(SIGPIPE, SIG_IGN);
    const char *options = getenv("SELKA_OPTIONS");
    uint64_t steps = 0, frames = 0, timeout = 0, memory = 0;
    bool sized = false;
    if (options && *options) {
        char *copy = strdup(options);
        if (!copy) out_of_memory();
        char *cursor = copy, *arg;
        while ((arg = core_io_next_option(&cursor))) {
            if (!strcmp(arg, "--print-result") || !strcmp(arg, "--restrict") || !strncmp(arg, "--allow-", 8)) continue;
            if (core_start_budget(arg, "--max-steps=", &steps) || core_start_budget(arg, "--max-frames=", &frames) || core_start_budget(arg, "--timeout=", &timeout)) continue;
            if (!strncmp(arg, "--max-memory=", 13)) {
                if (sized) core_io_option_error("selka: SELKA_OPTIONS names %s twice\n", "--max-memory=");
                if (!core_start_size(arg + 13, &memory)) core_io_option_error("selka: SELKA_OPTIONS names %s, which is not a byte size\n", arg);
                sized = true;
                continue;
            }
            core_io_option_error("selka: SELKA_OPTIONS names %s, which is not a runtime option\n", arg);
        }
        free(copy);
    }
    if (!from_environment) memory = 0;
    else if (!sized) memory = core_start_memory_limit();
    if (frames) core_start_frame_reservation(frames, memory);
    if (steps) core_start_refuse("R_NO_STEP_ACCOUNTING", "this build omits instruction-budget accounting", "run it under `selka run --max-steps=N`");
    if (frames) core_start_refuse("R_NO_FRAME_ACCOUNTING", "this build omits call-depth accounting", "run it under `selka run --max-frames=N`");
    if (memory) myl_core_test_ceilings(0, memory);
    if (timeout) core_run_arm(timeout);
}
/* The entry of a program from `selka build -o`: its options and the environment's byte ceiling. */
void myl_core_start(void) { core_start_options(true); }
/* The entry of a program whose `main` installs a compiled-in budget (`selka run`, `build --run`, a harness build;
   `run_budget.installs`): its options, and the byte ceiling left to `myl_core_run_controls`. */
void myl_core_start_budgeted(void) { core_start_options(false); }
void myl_core_test_enter(void) {
    if (++core_test_depth > core_test_frame_limit && core_test_frame_limit) core_io_fail("R_FRAME_LIMIT");
}
void myl_core_test_leave(void) { --core_test_depth; }
/* The program frames live now, when a frame budget counts them; else 0. */
static uint64_t core_test_frames_live(void) {
    if (!core_test_frame_limit) return 0;
    return core_test_depth > core_test_frame_limit ? core_test_frame_limit : core_test_depth;
}
static void (*core_test_body)(void);
static void core_test_launch(void) { core_test_body(); }
/* Run `trial` on the budget's stack, with one guard page below it. A mapping the
 * address space cannot hold is refused the way the old runtime refuses it. */
static void core_test_on_stack(void (*trial)(void)) {
    if (!core_test_frame_limit) { trial(); return; }
    long page_size = sysconf(_SC_PAGESIZE);
    size_t page = page_size > 0 ? (size_t)page_size : 4096;
    size_t usable = ((size_t)core_test_frame_limit * CORE_TEST_FRAME_STACK + CORE_TEST_STACK_SLACK + page - 1) / page * page;
    unsigned char *mapping = aligned_alloc(page, usable + page);
    ucontext_t caller, callee;
    if (!mapping || mprotect(mapping, page, PROT_NONE) || getcontext(&callee)) {
        flush_all();
        fprintf(stderr, "selka: a call-depth budget of %llu frames (--max-frames) reserves %.1f GiB of native stack (32 KiB per frame), "
            "but the test's address space cannot hold it; raise --max-memory or lower --max-frames\n", (unsigned long long)core_test_frame_limit, (double)usable / 1073741824.0);
        fflush(stderr);
        _exit(1);
    }
    callee.uc_stack.ss_sp = mapping + page;
    callee.uc_stack.ss_size = usable;
    callee.uc_stack.ss_flags = 0;
    callee.uc_link = &caller;
    core_test_body = trial;
    makecontext(&callee, core_test_launch, 0);
    if (swapcontext(&caller, &callee)) _exit(70);
    /* The child exits after its trial; the mapping is never reused or freed. */
}
static uint64_t core_test_word(FILE *file) {
    unsigned char bytes[8];
    if (!file || fread(bytes, 1, 8, file) != 8) _exit(70);
    uint64_t word = 0;
    for (unsigned i = 0; i < 8; ++i) word |= (uint64_t)bytes[i] << (8 * i);
    return word;
}
static void core_test_put(FILE *file, uint64_t word) {
    unsigned char bytes[8];
    for (unsigned i = 0; i < 8; ++i) bytes[i] = (unsigned char)(word >> (8 * i));
    if (!file || fwrite(bytes, 1, 8, file) != 8) _exit(70);
}
uint64_t myl_core_test_read(void) { return core_test_word(core_test_input); }
void myl_core_test_write(uint64_t word) { core_test_put(core_test_values, word); }
bool myl_core_test_read_bool(void){uint64_t bits=myl_core_test_read();(void)myl_core_test_read();return bits!=0;}
void myl_core_test_write_bool(bool value){myl_core_test_write(value?1:0);myl_core_test_write(0);}
double myl_core_test_read_float(void) {
    uint64_t bits = myl_core_test_read(); (void)myl_core_test_read();
    double value; memcpy(&value, &bits, 8); return value;
}
void myl_core_test_write_float(double value) {
    uint64_t bits; memcpy(&bits, &value, 8);
    myl_core_test_write(bits); myl_core_test_write(0);
}
static unsigned core_test_scalar(unsigned char *out, uint32_t point) {
    if (point < 0x80) {out[0]=(unsigned char)point; return 1;}
    if (point < 0x800) {out[0]=(unsigned char)(0xc0|(point>>6));out[1]=(unsigned char)(0x80|(point&63));return 2;}
    if (point < 0x10000 && !(point>=0xd800 && point<=0xdfff)) {
        out[0]=(unsigned char)(0xe0|(point>>12));out[1]=(unsigned char)(0x80|((point>>6)&63));out[2]=(unsigned char)(0x80|(point&63));return 3;
    }
    if (point<=0x10ffff) {
        out[0]=(unsigned char)(0xf0|(point>>18));out[1]=(unsigned char)(0x80|((point>>12)&63));out[2]=(unsigned char)(0x80|((point>>6)&63));out[3]=(unsigned char)(0x80|(point&63));return 4;
    }
    _exit(70);
}
static myl_block *core_test_read_octets(bool bytes) {
    (void)myl_core_test_read(); uint64_t count=myl_core_test_read();
    if (count>4096) _exit(70);
    size_t capacity=(size_t)count*(bytes?1:4);
    myl_block *text=block_new(bytes?MYL_KIND_BYTES:MYL_KIND_STR,(int64_t)capacity+1,1);
    size_t used=0;
    for(uint64_t i=0;i<count;++i){
        uint64_t point=myl_core_test_read(); (void)myl_core_test_read();
        if(bytes){if(point>255)_exit(70);block_data(text)[used++]=(unsigned char)point;}
        else used+=core_test_scalar(block_data(text)+used,(uint32_t)point);
    }
    text->len=(int64_t)used;block_data(text)[used]=0;
    if(!bytes)core_text_publish(text);
    return text;
}
myl_block *myl_core_test_read_text(void){return core_test_read_octets(false);}
myl_block *myl_core_test_read_bytes(void){return core_test_read_octets(true);}
void myl_core_test_write_text(myl_block *text,uint32_t bytes){
    const unsigned char *p=block_data(text);size_t n=(size_t)text->len;
    uint64_t count=0;
    if(bytes)count=n;else for(size_t i=0;i<n;++i)if((p[i]&0xc0)!=0x80)++count;
    myl_core_test_write(0);myl_core_test_write(count);
    for(size_t i=0;i<n;){
        uint32_t point=p[i++];
        if(!bytes&&point>=0xc0){
            unsigned tails=point<0xe0?1:point<0xf0?2:3;
            point&=tails==1?31:tails==2?15:7;
            for(unsigned j=0;j<tails;++j){if(i>=n)_exit(70);point=(point<<6)|(p[i++]&63);}
        }
        myl_core_test_write(point);myl_core_test_write(0);
    }
}
static char *core_test_named(const char *suffix){
    size_t a=strlen(core_test_path),b=strlen(suffix);char *path=malloc(a+b+1);
    if(!path)out_of_memory();memcpy(path,core_test_path,a);memcpy(path+a,suffix,b+1);return path;
}
static void core_test_copy(FILE *target,FILE *source){
    if(fflush(source)||fseek(source,0,SEEK_END))_exit(70);
    long size=ftell(source);if(size<0||fseek(source,0,SEEK_SET))_exit(70);
    core_test_put(target,(uint64_t)size);
    unsigned char bytes[4096];size_t count;
    while((count=fread(bytes,1,sizeof bytes,source)))if(fwrite(bytes,1,count,target)!=count)_exit(70);
}
static void core_test_capture(const char *suffix,int descriptor){
    char *path=core_test_named(suffix);int fd=open(path,O_RDWR|O_CREAT|O_TRUNC,0600);free(path);
    if(fd<0||dup2(fd,descriptor)<0)_exit(70);close(fd);
}
static void core_test_file(FILE *target,const char *suffix){
    char *path=core_test_named(suffix);FILE *file=fopen(path,"rb");free(path);
    if(!file){core_test_put(target,0);return;}core_test_copy(target,file);fclose(file);
}
static void core_test_record(uint64_t status,FILE *values){
    core_test_put(core_test_output,status);
    if(values)core_test_copy(core_test_output,values);else core_test_put(core_test_output,0);
    core_test_file(core_test_output,".out");core_test_file(core_test_output,".err");core_test_file(core_test_output,".trace");
    if(fflush(core_test_output))_exit(70);
}
static bool core_test_trapped(void){
    char *path=core_test_named(".err");FILE *file=fopen(path,"rb");free(path);
    if(!file)return false;
    static const unsigned char marker[]="\036SELKA-TRAP ";
    unsigned matched=0;int byte;bool found=false;
    while((byte=fgetc(file))!=EOF){
        if(byte==marker[matched]){
            if(marker[++matched]==0){found=true;break;}
        }else matched=byte==marker[0]?1:0;
    }
    fclose(file);return found;
}
static void core_test_stderr(void){
    char *path=core_test_named(".err");FILE *file=fopen(path,"rb");free(path);
    if(!file)return;
    unsigned char bytes[4096];size_t count;
    while((count=fread(bytes,1,sizeof bytes,file)))if(fwrite(bytes,1,count,stderr)!=count)_exit(70);
    fclose(file);if(fflush(stderr))_exit(70);
}
/* Source traces are kept apart from arbitrary stderr output. */
void myl_core_test_trace(void){
    stream_flush(&streams[1]);int saved=dup(2);core_test_capture(".trace",2);
    trace_write();stream_flush(&streams[1]);if(dup2(saved,2)<0)_exit(70);close(saved);
}
/* A bool test that returned false (the trial wrapper calls this on that path only): the operands and place of the comparison it
   returned, when it left them (`compared_write`), go to the same trace file. */
void myl_core_test_compared(void){
    stream_flush(&streams[1]);int saved=dup(2);core_test_capture(".trace",2);
    compared_write();stream_flush(&streams[1]);if(dup2(saved,2)<0)_exit(70);close(saved);
}
/* The executable's dispatch table (NEW-CORE-TEST-BATCH-1): its entry registers every
 * selected test's trial wrapper in table order before serving one request, and each
 * trial of the request names the row it calls, so one process answers several tests. */
static void (**core_test_table)(void);
static uint64_t core_test_rows,core_test_capacity;
void myl_core_test_register(void (*trial)(void)){
    if(core_test_rows==core_test_capacity){
        uint64_t capacity=core_test_capacity?core_test_capacity*2:64;
        void (**grown)(void)=realloc(core_test_table,(size_t)capacity*sizeof *grown);
        if(!grown)out_of_memory();
        core_test_table=grown;core_test_capacity=capacity;
    }
    core_test_table[core_test_rows++]=trial;
}
bool myl_core_test_open(myl_block *input,myl_block *output){
    if (core_parallel()) core_io_fail("R_TASK_FORK");
    core_test_batch_parent = true;
    core_test_input=fopen((const char *)block_data(input),"rb");
    core_test_output=fopen((const char *)block_data(output),"wb");
    core_test_path=strdup((const char *)block_data(output));
    core_trap_marks_all=true;
    if(!core_test_input||!core_test_output||!core_test_path)return false;
    core_test_trials=core_test_word(core_test_input);return true;
}
int64_t myl_core_test_run(void){
    if (core_parallel()) core_io_fail("R_TASK_FORK");
    for(uint64_t i=0;i<core_test_trials;++i){
        uint64_t row=core_test_word(core_test_input);
        if(row>=core_test_rows)_exit(70);
        void (*trial)(void)=core_test_table[row];
        uint64_t words=core_test_word(core_test_input);long start=ftell(core_test_input);
        if(words>1000000||start<0)_exit(70);
        const char *suffixes[]={".out",".err",".trace"};
        for(unsigned j=0;j<3;++j){char *path=core_test_named(suffixes[j]);FILE *empty=fopen(path,"wb");free(path);if(empty)fclose(empty);}
        flush_all();if(fflush(NULL))_exit(70);
        int64_t baseline=live_count();pid_t parent=getpid();pid_t child=fork();if(child<0)_exit(70);
        if(child==0){
            core_test_batch_parent = false;
#if defined(__linux__)
            if(prctl(PR_SET_PDEATHSIG,SIGKILL)<0||getppid()!=parent)_exit(70);
#else
            (void)parent;
#endif
            core_test_values=tmpfile();if(!core_test_values)_exit(70);
            core_test_capture(".out",1);core_test_capture(".err",2);
            alarm(60);error_trace.origin=NULL;error_trace.count=0;core_test_on_stack(trial);core_tasks_quiesce();alarm(0);
            /* The trial's work before anything this child does for the report. */
            const uint64_t executed=core_test_executed, peak=core_heap_test_peak();
            flush_all();
            core_test_work_write(i,executed,peak);
            core_io_cleanup();
            const char *check=getenv("SELKA_CORE_LEAKCHECK");
            if(check&&strcmp(check,"0")&&live_count()!=baseline){
                fprintf(stderr,"myl-core leakcheck: %lld blocks remain after trial\n",(long long)(live_count()-baseline));fflush(stderr);
                core_test_record(4,core_test_values);_exit(0);
            }
            core_test_record(0,core_test_values);_exit(0);
        }
        int status;while(waitpid(child,&status,0)<0){if(errno!=EINTR)_exit(70);}
        if(WIFSIGNALED(status)){
            /* A signal cuts off the batch exactly like the old harness. Its
             * completed prefix is durable; the Zig search retries this input
             * alone before classifying it or adopting a shrink candidate. */
            int caught=WTERMSIG(status);core_test_stderr();fclose(core_test_input);fclose(core_test_output);
            signal(caught,SIG_DFL);raise(caught);_exit(70);
        }
        if(WEXITSTATUS(status)!=0){
            if(core_test_trapped())core_test_record(1,NULL);
            else {
                /* An arbitrary native exit did not answer this trial. Keep
                 * its status and the completed prefix for old retry grading. */
                int code=WEXITSTATUS(status);core_test_stderr();fclose(core_test_input);fclose(core_test_output);_exit(code);
            }
        }
        if(fseek(core_test_input,start+(long)(words*8),SEEK_SET))_exit(70);
    }
    fclose(core_test_input);fclose(core_test_output);free(core_test_path);
    core_test_input=NULL;core_test_output=NULL;core_test_path=NULL;return 0;
}
