/* TASK-SCHEDULER-1: lazy structured CPU tasks. The deque follows the C11
 * Chase-Lev algorithm of Lê et al., PPoPP 2013, figure 1. Old rings remain
 * allocated while thieves can still read them. Atomic slots prevent a late
 * thief's speculative read from racing an owner's wrapped slot reuse. */
enum { MYL_KIND_TASK = 9, MYL_KIND_GROUP = 10 };
typedef struct core_task core_task;
typedef struct {
    myl_block *tasks;
    _Atomic uint64_t pending;
    uintptr_t site;
    bool closed;
    /* P1F-7 (B2): the thread that opened the group; it alone may submit, take and close. */
    core_thread_record *owner;
} core_group;
/* E1 drop mask. The environment of a submitted task is a box whose layout names its managed references
   (reference r is layout[3 + 2r]). Bit r of `own` set: the environment owns reference r, so the task may take it
   (the thunk moves it out and clears the slot) and the environment drop releases whatever it still holds. Bit r
   clear: reference r is lent, borrowed from an owner that outlives the group's join. Before the environment drop,
   every lent reference is cleared to NULL, and the child walk skips null references (core_owned_child_inline), so
   a lent value is never released by the environment. A temporary passed to submit is owned (its bit set). The
   default mask, all bits set, is the behaviour of myl_core_task_submit before the mask existed. */
struct core_task {
    void *run;
    myl_block *env, *result;
    core_group *group;
    core_task_context site;
    _Atomic uint32_t state;
    uint64_t own;
};
typedef struct core_task_ring {
    uint64_t capacity;
    struct core_task_ring *previous;
    _Atomic(core_task *) slots[];
} core_task_ring;
typedef struct {
    _Alignas(64) _Atomic int64_t top;
    _Alignas(64) _Atomic int64_t bottom;
    _Atomic(core_task_ring *) ring;
} core_task_deque;
typedef struct {
    core_task_deque queue;
    uint32_t index, victim;
    pthread_t thread;
} core_task_worker;
static struct {
    core_task_worker *workers;
    uint32_t size;
    _Atomic uint64_t pending;
    _Atomic uint32_t epoch, ready;
    /* P1F-5: idle workers park on `idle_epoch`, which pushes move and wake one of them; result,
       group and quiescence waiters and the pool start park on `epoch`, which completions move
       and wake. `waiters` and `idle` count the parked threads of each word. */
    _Atomic uint32_t idle_epoch, idle, waiters;
} core_tasks;
static MYL_TLS core_task_worker *core_worker;
/* P1F-2: the configured thread count (0 until first asked) and the most threads a pool may start. */
static uint32_t core_task_configured, core_task_start_cap = 256;
enum { MYL_THREADS_MAX = 256 };
static const int32_t core_task_layout[] = {sizeof(core_task), 1, 0, offsetof(core_task, result), 0};
static const int32_t core_group_layout[] = {sizeof(core_group), 1, 0, offsetof(core_group, tasks), 0};
extern myl_block *myl_core_task_call(void *run, myl_block *env);

static core_task_ring *core_task_ring_new(uint64_t capacity, core_task_ring *previous) {
    if (capacity > (SIZE_MAX - sizeof(core_task_ring)) / sizeof(_Atomic(core_task *))) out_of_memory();
    core_task_ring *ring = malloc(sizeof *ring + (size_t)capacity * sizeof *ring->slots);
    if (!ring) out_of_memory();
    ring->capacity = capacity;
    ring->previous = previous;
    for (uint64_t i = 0; i < capacity; ++i) atomic_init(&ring->slots[i], NULL);
    return ring;
}
/* P1F-5: the kernel is entered only when a thread is parked. A parker registers before its futex
 * wait re-checks the word, and a waker changes the word before it reads the count (both
 * sequentially consistent), so either the waker sees the parked thread or the wait refuses to
 * block. Completions wake every waiter: the waiters of one group or task share the word, and a
 * single wake could be spent on a waiter that cannot run the completed work. */
static void core_task_wake(void) {
    atomic_fetch_add_explicit(&core_tasks.epoch, 1, memory_order_seq_cst);
    if (atomic_load_explicit(&core_tasks.waiters, memory_order_seq_cst))
        syscall(SYS_futex, &core_tasks.epoch, FUTEX_WAKE_PRIVATE, INT32_MAX, NULL, NULL, 0);
}
static void core_task_park(uint32_t epoch) {
    atomic_fetch_add_explicit(&core_tasks.waiters, 1, memory_order_seq_cst);
    syscall(SYS_futex, &core_tasks.epoch, FUTEX_WAIT_PRIVATE, epoch, NULL, NULL, 0);
    atomic_fetch_sub_explicit(&core_tasks.waiters, 1, memory_order_seq_cst);
}
/* A push wakes one parked idle worker, and only when there is one. */
static void core_task_push_wake(void) {
    atomic_fetch_add_explicit(&core_tasks.idle_epoch, 1, memory_order_seq_cst);
    if (atomic_load_explicit(&core_tasks.idle, memory_order_seq_cst))
        syscall(SYS_futex, &core_tasks.idle_epoch, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
}
static void core_task_idle_park(uint32_t idle_epoch) {
    atomic_fetch_add_explicit(&core_tasks.idle, 1, memory_order_seq_cst);
    syscall(SYS_futex, &core_tasks.idle_epoch, FUTEX_WAIT_PRIVATE, idle_epoch, NULL, NULL, 0);
    atomic_fetch_sub_explicit(&core_tasks.idle, 1, memory_order_seq_cst);
}
static void core_task_push(core_task_deque *queue, core_task *task) {
    int64_t bottom = atomic_load_explicit(&queue->bottom, memory_order_relaxed);
    int64_t top = atomic_load_explicit(&queue->top, memory_order_acquire);
    if (bottom == INT64_MAX) out_of_memory();
    core_task_ring *ring = atomic_load_explicit(&queue->ring, memory_order_relaxed);
    if ((uint64_t)(bottom - top) >= ring->capacity - 1) {
        if (ring->capacity > UINT64_MAX / 2) out_of_memory();
        core_task_ring *grown = core_task_ring_new(ring->capacity * 2, ring);
        for (int64_t i = top; i < bottom; ++i)
            atomic_store_explicit(&grown->slots[(uint64_t)i & (grown->capacity - 1)],
                atomic_load_explicit(&ring->slots[(uint64_t)i & (ring->capacity - 1)], memory_order_relaxed), memory_order_relaxed);
        atomic_store_explicit(&queue->ring, grown, memory_order_release);
        ring = grown;
    }
    atomic_store_explicit(&ring->slots[(uint64_t)bottom & (ring->capacity - 1)], task, memory_order_relaxed);
    atomic_store_explicit(&queue->bottom, bottom + 1, memory_order_release);
    core_task_push_wake();
}
static core_task *core_task_pop(core_task_deque *queue) {
    int64_t bottom = atomic_load_explicit(&queue->bottom, memory_order_relaxed) - 1;
    core_task_ring *ring = atomic_load_explicit(&queue->ring, memory_order_relaxed);
    atomic_store_explicit(&queue->bottom, bottom, memory_order_relaxed);
    atomic_thread_fence(memory_order_seq_cst);
    int64_t top = atomic_load_explicit(&queue->top, memory_order_relaxed);
    if (top > bottom) {
        atomic_store_explicit(&queue->bottom, bottom + 1, memory_order_relaxed);
        return NULL;
    }
    core_task *task = atomic_load_explicit(&ring->slots[(uint64_t)bottom & (ring->capacity - 1)], memory_order_relaxed);
    if (top == bottom) {
        if (!atomic_compare_exchange_strong_explicit(&queue->top, &top, top + 1,
                memory_order_seq_cst, memory_order_relaxed)) task = NULL;
        atomic_store_explicit(&queue->bottom, bottom + 1, memory_order_relaxed);
    }
    return task;
}
static core_task *core_task_steal(core_task_deque *queue) {
    int64_t top = atomic_load_explicit(&queue->top, memory_order_acquire);
    atomic_thread_fence(memory_order_seq_cst);
    int64_t bottom = atomic_load_explicit(&queue->bottom, memory_order_acquire);
    if (top >= bottom) return NULL;
    core_task_ring *ring = atomic_load_explicit(&queue->ring, memory_order_acquire);
    core_task *task = atomic_load_explicit(&ring->slots[(uint64_t)top & (ring->capacity - 1)], memory_order_relaxed);
    if (!atomic_compare_exchange_strong_explicit(&queue->top, &top, top + 1,
            memory_order_seq_cst, memory_order_relaxed)) return NULL;
    return task;
}
static core_task *core_task_find(void) {
    core_task *task = core_task_pop(&core_worker->queue);
    if (task) return task;
    for (uint32_t i = 0; i < core_tasks.size; ++i) {
        uint32_t victim = core_worker->victim++;
        if (core_worker->victim == core_tasks.size) core_worker->victim = 0;
        if (victim == core_worker->index) continue;
        task = core_task_steal(&core_tasks.workers[victim].queue);
        if (task) return task;
    }
    return NULL;
}
/* E1 drop mask: clear every lent reference of a task environment (bit clear in `own`), so the environment's drop
   skips it. A reference beyond the mask's 64 bits is owned. An environment without a layout has no references. */
static void core_task_release_lent(myl_block *env, uint64_t own) {
    if (!env || kind_of(env) != MYL_KIND_BOX) return;
    myl_layout *layout = layout_of(env);
    if (!layout) return;
    for (int32_t r = 0; r < layout[1] && r < 64; ++r) {
        if (own & ((uint64_t)1 << r)) continue;
        myl_block *none = NULL;
        memcpy(block_data(env) + layout[3 + 2 * r], &none, sizeof none);
    }
}
static void core_task_execute(core_task *task, bool parallel) {
    core_task_context saved = core_running_task;
    __typeof__(error_trace) saved_trace = error_trace;
    core_running_task = task->site;
    error_trace.origin = NULL;
    error_trace.count = 0;
    myl_block *result = myl_core_task_call(task->run, task->env);
    /* The scoped group received this environment by move. The thunk borrows
       the lent references and takes the owned ones it consumes; the lent ones
       are cleared before the environment is released (E1 drop mask). */
    core_task_release_lent(task->env, task->own);
    myl_core_drop_owned(task->env);
    task->env = NULL;
    task->result = result;
    core_running_task = saved;
    error_trace = saved_trace;
    /* RUNTIME-THREADS-2: the environment this task freed may have been carved by another thread. */
    if (parallel) core_depot_donate();
    core_group *group = task->group;
    /* P1F-5: bit 0 is done and the upper bits count the result waiters parked on this task,
       so the completion wakes exactly those waiters, and only when there are some. */
    uint32_t state = atomic_fetch_or_explicit(&task->state, 1, memory_order_seq_cst);
    if (state >> 1) syscall(SYS_futex, &task->state, FUTEX_WAKE_PRIVATE, INT32_MAX, NULL, NULL, 0);
    atomic_fetch_sub_explicit(&group->pending, 1, memory_order_release);
    if (parallel) {
        atomic_fetch_sub_explicit(&core_tasks.pending, 1, memory_order_release);
        core_task_wake();
    }
}
static void *core_task_worker_main(void *argument) {
    core_worker = argument;
    core_worker_runtime_start();
    atomic_fetch_add_explicit(&core_tasks.ready, 1, memory_order_release);
    core_task_wake();
    for (;;) {
        uint32_t idle_epoch = atomic_load_explicit(&core_tasks.idle_epoch, memory_order_seq_cst);
        core_task *task = NULL;
        for (unsigned spin = 0; spin < 32 && !task; ++spin) task = core_task_find();
        if (task) core_task_execute(task, true);
        else core_task_idle_park(idle_epoch);
    }
    return NULL;
}
/* P1F-2: `R_THREAD_START`, with the requested count, the cap and the limits the start ran under. */
static void core_thread_start_failure(void) {
    core_thread_starting = false;
    char detail[256];
    const char *requested = getenv("SELKA_THREADS");
    char default_count[32];
    snprintf(default_count, sizeof default_count, "%u", core_task_configured);
    struct rlimit limit;
    unsigned long long address_space = !getrlimit(RLIMIT_AS, &limit) && limit.rlim_cur != RLIM_INFINITY ? (unsigned long long)limit.rlim_cur : 0;
    snprintf(detail, sizeof detail, "cannot start thread pool: requested %s, cap %u, memory limit %llu bytes, address space %llu bytes",
        requested ? requested : default_count, core_task_start_cap, (unsigned long long)heap_ceiling, address_space);
    core_failure_detail = detail;
    core_io_fail("R_THREAD_START");
}
/* The CPUs the process may run on (its affinity mask), at least 1, read at each call: `parallel.cpus()`, and the pool's default
 * size once capped. */
int64_t myl_core_cpus(void) {
    cpu_set_t cpus;
    CPU_ZERO(&cpus);
    int64_t count = sched_getaffinity(0, sizeof cpus, &cpus) ? 1 : (int64_t)CPU_COUNT(&cpus);
    return count > 0 ? count : 1;
}
/* The embedding and emitted program have one submitting thread until this
 * function starts the pool. Afterwards the cached count is immutable. P1F-2: a
 * value outside 1-256 is R_THREAD_START, and so is a start that cannot fit one worker. */
int64_t myl_core_threads(void) {
    if (core_task_configured) return core_task_configured;
    uint64_t count = 0;
    const char *text = getenv("SELKA_THREADS");
    if (text) {
        if (!*text) core_thread_start_failure();
        for (const char *p = text; *p; ++p) {
            if (*p < '0' || *p > '9' || count > (MYL_THREADS_MAX - (unsigned)(*p - '0')) / 10u) core_thread_start_failure();
            count = count * 10 + (unsigned)(*p - '0');
        }
        if (!count || count > MYL_THREADS_MAX) core_thread_start_failure();
    } else if (core_trap_marks_all) count = 1;
    else {
        count = (uint64_t)myl_core_cpus();
        if (count > MYL_THREADS_MAX) count = MYL_THREADS_MAX;
    }
    if (core_test_bounded || core_test_frame_limit) count = 1;
    core_task_configured = (uint32_t)count;
    return core_task_configured;
}
/* Generated range thunks update this before each item. Nested execution saves
 * and restores the complete context in core_task_execute. */
void myl_core_task_item(int64_t item) { core_running_task.item = item; }
int64_t myl_core_map_chunks(int64_t items) {
    if (items <= 0) return 0;
    int64_t threads = myl_core_threads();
    int64_t chunks = threads == 1 ? 1 : threads * 4;
    return items < chunks ? items : chunks;
}
/* P1F-2: the address space a pool of `requested` threads adds to the program's: each
 * worker's stack, guard page and signal stack. glibc gives every thread that allocates
 * its own arena (64 MiB of address space), so arenas are capped at one before any worker
 * exists. The soft `RLIMIT_AS` grows by the workers' reservation where the hard limit
 * allows; otherwise the pool is cut to the workers that fit, and a start that fits no
 * worker is R_THREAD_START. */
static uint32_t core_task_reserve(uint32_t requested, size_t stack, size_t page) {
    /* ASan replaces malloc and its mallopt interceptor always returns zero.
       It has no glibc arenas to cap; keep every reservation and limit below. */
    bool address_allocator = false;
#if defined(__has_feature)
    address_allocator = __has_feature(address_sanitizer);
#elif defined(__SANITIZE_ADDRESS__)
    address_allocator = true;
#endif
    if (!address_allocator && mallopt(M_ARENA_MAX, 1) != 1) core_thread_start_failure();
    struct rlimit limit;
    core_process_note_address_space();
    if (getrlimit(RLIMIT_AS, &limit)) core_thread_start_failure();
    if (limit.rlim_cur == RLIM_INFINITY) return requested;
    uint64_t reservation = (uint64_t)stack + page + CORE_FLOOR_STACK;
    if (requested - 1 > UINT64_MAX / reservation) core_thread_start_failure();
    uint64_t extra = reservation * (requested - 1);
    if (extra > UINT64_MAX - (uint64_t)limit.rlim_cur) core_thread_start_failure();
    rlim_t wanted = limit.rlim_cur + extra;
    if (limit.rlim_max != RLIM_INFINITY && wanted > limit.rlim_max) {
        /* The room is the hard limit less what the program maps now, the managed
           ceiling it may reach, and 32 MiB of runtime metadata; not the soft limit. */
        unsigned long long pages = 0;
        FILE *statm = fopen("/proc/self/statm", "r");
        bool read = statm && fscanf(statm, "%llu", &pages) == 1;
        if (statm) fclose(statm);
        if (!read) core_thread_start_failure();
        uint64_t base = (uint64_t)pages * page + heap_ceiling + (UINT64_C(32) << 20);
        uint64_t room = limit.rlim_max > base ? (uint64_t)(limit.rlim_max - base) : 0;
        uint64_t fit = 1 + room / reservation;
        core_task_start_cap = fit < MYL_THREADS_MAX ? (uint32_t)fit : MYL_THREADS_MAX;
        if (fit < 2) core_thread_start_failure();
        if (fit < requested) requested = (uint32_t)fit;
        wanted = limit.rlim_max;
    }
    limit.rlim_cur = wanted;
    if (setrlimit(RLIMIT_AS, &limit)) core_thread_start_failure();
    return requested;
}
static void core_task_pool_start(void) {
    if (core_parallel()) return;
    if (core_test_batch_parent) core_io_fail("R_TASK_FORK");
    uint32_t size = (uint32_t)myl_core_threads();
    if (size == 1) return;
    core_thread_starting = true;
    struct rlimit limit;
    if (getrlimit(RLIMIT_STACK, &limit)) core_thread_start_failure();
    size_t stack = limit.rlim_cur == RLIM_INFINITY ? (size_t)64 << 20 : (size_t)limit.rlim_cur;
    long page_size = sysconf(_SC_PAGESIZE);
    size_t page = page_size > 0 ? (size_t)page_size : 4096;
    if (stack < PTHREAD_STACK_MIN) stack = PTHREAD_STACK_MIN;
    if (stack > SIZE_MAX - 2 * page) core_thread_start_failure();
    stack = (stack + page - 1) / page * page;
    size = core_task_reserve(size, stack, page);
    core_task_configured = size;
    core_thread_register();
    core_io_initialize();
    (void)core_ascii_char(0);
    core_floor_install();
    size_t bytes = (size_t)size * sizeof(core_task_worker);
    core_tasks.workers = aligned_alloc(_Alignof(core_task_worker), bytes);
    if (!core_tasks.workers) core_thread_start_failure();
    memset(core_tasks.workers, 0, bytes);
    core_tasks.size = size;
    for (uint32_t i = 0; i < size; ++i) {
        core_task_worker *worker = &core_tasks.workers[i];
        worker->index = i;
        worker->victim = (i + 1) % size;
        atomic_init(&worker->queue.top, 0);
        atomic_init(&worker->queue.bottom, 0);
        atomic_init(&worker->queue.ring, core_task_ring_new(64, NULL));
    }
    core_worker = &core_tasks.workers[0];
    pthread_attr_t attributes;
    if (pthread_attr_init(&attributes) || pthread_attr_setstacksize(&attributes, stack) ||
        pthread_attr_setguardsize(&attributes, page)) core_thread_start_failure();
    sigset_t blocked, previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGALRM);
    if (pthread_sigmask(SIG_BLOCK, &blocked, &previous)) core_thread_start_failure();
    atomic_store_explicit(&core_pool_started, true, memory_order_release);
    for (uint32_t i = 1; i < size; ++i)
        if (pthread_create(&core_tasks.workers[i].thread, &attributes, core_task_worker_main, &core_tasks.workers[i])) core_thread_start_failure();
    pthread_attr_destroy(&attributes);
    if (pthread_sigmask(SIG_SETMASK, &previous, NULL)) core_thread_start_failure();
    core_thread_starting = false;
    while (atomic_load_explicit(&core_tasks.ready, memory_order_acquire) != size - 1) {
        uint32_t epoch = atomic_load_explicit(&core_tasks.epoch, memory_order_acquire);
        if (atomic_load_explicit(&core_tasks.ready, memory_order_acquire) != size - 1) core_task_park(epoch);
    }
}
/* P1F-7 (B2): a group belongs to the thread that opened it. A forged handle that reaches
   another thread traps R_TASK_ESCAPE instead of racing the group's task list; the
   checker's E_TASK_ESCAPE is the user-facing rule, this is its runtime backstop. */
static void core_task_group_confine(const core_group *group) {
    if (group->owner == core_thread_registered) return;
    core_failure_detail = "a task group cannot be shared with a task";
    core_io_fail("R_TASK_ESCAPE");
}
__attribute__((noinline)) myl_block *myl_core_group_open(void) {
    myl_block *block = block_new(MYL_KIND_GROUP, sizeof(core_group), 1);
    block->len = 1;
    block->reserved = (int64_t)(intptr_t)core_group_layout;
    core_group *group = (core_group *)block_data(block);
    memset(group, 0, sizeof *group);
    core_thread_register();
    group->owner = core_thread_registered;
    atomic_init(&group->pending, 0);
    group->site = (uintptr_t)__builtin_return_address(0);
    group->tasks = myl_core_list_new_slow(8, sizeof(myl_block *));
    group->tasks->reserved = (int64_t)(intptr_t)layout_blocks;
    return block;
}
static myl_block *core_task_submit_masked(myl_block *block, void *run, myl_block *env, int64_t item, uint64_t own) {
    core_group *group = (core_group *)block_data(block);
    if (core_test_batch_parent) core_io_fail("R_TASK_FORK");
    core_task_group_confine(group);
    if (group->closed) core_io_fail("R_TASK_GROUP");
    core_task_pool_start();
    myl_block *handle = block_new(MYL_KIND_TASK, sizeof(core_task), 1);
    handle->len = 1;
    handle->reserved = (int64_t)(intptr_t)core_task_layout;
    core_task *task = (core_task *)block_data(handle);
    task->run = run;
    task->env = env;
    task->result = NULL;
    task->group = group;
    task->own = own;
    task->site = (core_task_context){(uintptr_t)__builtin_return_address(0), group->site, item};
    atomic_init(&task->state, 0);
    bool parallel = core_parallel();
    group->tasks = myl_core_list_grow(group->tasks, sizeof(myl_block *));
    ((myl_block **)block_data(group->tasks))[group->tasks->len++] = handle;
    atomic_fetch_add_explicit(&group->pending, 1, memory_order_relaxed);
    if (parallel) {
        atomic_fetch_add_explicit(&core_tasks.pending, 1, memory_order_relaxed);
        core_task_push(&core_worker->queue, task);
    } else core_task_execute(task, false);
    return handle;
}
__attribute__((noinline)) myl_block *myl_core_task_submit(myl_block *block, void *run, myl_block *env, int64_t item) {
    return core_task_submit_masked(block, run, env, item, UINT64_MAX);
}
/* E1 drop mask entry point: `own` is the mask described at struct core_task. */
__attribute__((noinline)) myl_block *myl_core_owned_task_submit_masked(myl_block *block, void *run, myl_block *env, int64_t item, uint64_t own) {
    return core_task_submit_masked(block, run, env, item, own);
}
/* E1b (lowered submit): the environment's references are all owned (the default mask), and the result is the task's
   index in the group's task list, which `myl_core_owned_group_take` reads back. A task runs inline when the pool is
   not parallel, so the index is read after the submit returns. */
__attribute__((noinline)) int64_t myl_core_owned_task_submit_indexed(myl_block *block, void *run, myl_block *env, int64_t item) {
    (void)core_task_submit_masked(block, run, env, item, UINT64_MAX);
    core_group *group = (core_group *)block_data(block);
    return group->tasks->len - 1;
}
/* E1b (lowered thunk): the block a task environment holds at byte `offset`, taken out so the slot reads NULL. The
   thunk then owns it, and the environment's drop skips the empty slot. */
myl_block *myl_core_task_take(myl_block *env, uint64_t offset) {
    myl_block *taken;
    memcpy(&taken, block_data(env) + offset, sizeof taken);
    myl_block *none = NULL;
    memcpy(block_data(env) + offset, &none, sizeof none);
    return taken;
}
/* Capture the epoch before testing completion or searching, closing the lost
 * wake-up window between an empty search and the kernel's futex wait. P1F-4: a
 * waiter runs only its own unstolen tasks; only idle workers steal (core_task_find). */
static void core_group_wait(core_group *group) {
    while (atomic_load_explicit(&group->pending, memory_order_acquire)) {
        uint32_t epoch = atomic_load_explicit(&core_tasks.epoch, memory_order_acquire);
        if (!atomic_load_explicit(&group->pending, memory_order_acquire)) break;
        core_task *task = core_task_pop(&core_worker->queue);
        if (task) core_task_execute(task, true);
        else core_task_park(epoch);
    }
}
myl_block *myl_core_task_result(myl_block *handle) {
    core_task *wanted = (core_task *)block_data(handle);
    while (!(atomic_load_explicit(&wanted->state, memory_order_acquire) & 1)) {
        core_task *task = core_task_pop(&core_worker->queue);
        if (task) { core_task_execute(task, true); continue; }
        /* Register on this task's own state word, then sleep only while it is still unfinished:
           the completion's fetch_or either precedes the registration (the CAS fails) or sees
           the count and wakes this waiter. */
        uint32_t state = atomic_load_explicit(&wanted->state, memory_order_relaxed);
        while (!(state & 1)) {
            if (state > UINT32_MAX - 2) core_io_fail("R_INTERNAL");
            if (atomic_compare_exchange_weak_explicit(&wanted->state, &state, state + 2,
                    memory_order_seq_cst, memory_order_relaxed)) {
                if (!(atomic_load_explicit(&wanted->state, memory_order_seq_cst) & 1))
                    syscall(SYS_futex, &wanted->state, FUTEX_WAIT_PRIVATE, state + 2, NULL, NULL, 0);
                atomic_fetch_sub_explicit(&wanted->state, 2, memory_order_seq_cst);
                break;
            }
        }
    }
    myl_block *result = wanted->result;
    if (!result) core_io_fail("R_TASK_GROUP");
    wanted->result = NULL;
    return result;
}
void myl_core_group_close(myl_block *block) {
    core_group *group = (core_group *)block_data(block);
    core_task_group_confine(group);
    core_group_wait(group);
    core_depot_donate();
    if (group->closed) return;
    group->closed = true;
    myl_core_drop_owned(group->tasks);
    group->tasks = NULL;
}
/* NEW-CORE-ZERO-RC-TASKS-1: handles never escape their group. Submit transfers
   one capture box, take transfers one completed result, and end joins before
   destroying untaken results. The legacy borrowed capture ABI is not admitted. */
void myl_core_owned_task_submit(myl_block *group, void *run, myl_block *env, int64_t item) {
    (void)myl_core_task_submit(group, run, env, item);
}
myl_block *myl_core_owned_group_take(myl_block *block, int64_t index) {
    core_group *group = (core_group *)block_data(block);
    core_task_group_confine(group);
    if (group->closed || index < 0 || index >= group->tasks->len) core_io_fail("R_TASK_GROUP");
    return myl_core_task_result(((myl_block **)block_data(group->tasks))[index]);
}
void myl_core_owned_group_end(myl_block *block) {
    myl_core_group_close(block);
    myl_core_drop_owned(block);
}
/* NEW-CORE-ZERO-RC-TASKS-2: source elements remain borrowed through join.
   Each thunk returns a separately owned contiguous result list.
   Scheduling storage is bounded by the worker count, not the input length.
   FR59: `capture` is a box of the map's capture record, read for the call: the input (a list view, read in place, or a
   list), the callback, room for a chunk's start and count, and the trailing arguments (E1b, E1c), whose loans the map's
   group joins after this returns. Each chunk's environment is a copy of the record's bytes with its own start and
   count; it owns nothing, so its drop frees only itself. `length` is the input's length. Every chunk joins first. */
myl_block *myl_core_owned_map_with(myl_block *capture, uint64_t capture_size, uint64_t length, void *run,
        uint64_t start_offset, uint64_t count_offset, myl_block *out, uint64_t output_size) {
    if (!length) return out;
    int64_t chunks = myl_core_map_chunks((int64_t)length);
    int64_t quotient = (int64_t)length / chunks, remainder = (int64_t)length % chunks;
    myl_block *group = myl_core_group_open();
    int64_t start = 0;
    for (int64_t i = 0; i < chunks; ++i) {
        int64_t count = quotient + (i < remainder);
        myl_block *env = block_new(MYL_KIND_BYTES, capture_size, 1);
        env->len = (int64_t)capture_size;
        memcpy(block_data(env), block_data(capture), capture_size);
        memcpy(block_data(env) + start_offset, &start, sizeof start);
        memcpy(block_data(env) + count_offset, &count, sizeof count);
        myl_core_owned_task_submit(group, run, env, start);
        start += count;
    }
    for (int64_t i = 0; i < chunks; ++i) {
        myl_block *result = myl_core_owned_group_take(group, i);
        memcpy(block_data(out) + (size_t)out->len * output_size,
            block_data(result), (size_t)result->len * output_size);
        out->len += result->len;
        /* Transfer every element into the output; free only the list shell. */
        block_free(result);
    }
    myl_core_owned_group_end(group);
    return out;
}
/* The compiler calls this entry for every map (FR59): the trailing arguments ride in the capture. */
myl_block *myl_core_owned_map(myl_block *capture, uint64_t capture_size, uint64_t length, void *run,
        uint64_t start_offset, uint64_t count_offset, myl_block *out, uint64_t output_size) {
    return myl_core_owned_map_with(capture, capture_size, length, run, start_offset, count_offset, out, output_size);
}
/* A dropped group still owns queued tasks: join before the shared child
 * iterator releases its handle list. Source lowering normally closes first. */
static void core_task_finalize(myl_block *block) {
    if (kind_of(block) == MYL_KIND_GROUP) core_group_wait((core_group *)block_data(block));
}
static void core_tasks_quiesce(void) {
    if (!core_parallel()) return;
    while (atomic_load_explicit(&core_tasks.pending, memory_order_acquire)) {
        uint32_t epoch = atomic_load_explicit(&core_tasks.epoch, memory_order_acquire);
        if (!atomic_load_explicit(&core_tasks.pending, memory_order_acquire)) break;
        core_task *task = core_task_pop(&core_worker->queue);
        if (task) core_task_execute(task, true);
        else core_task_park(epoch);
    }
}
