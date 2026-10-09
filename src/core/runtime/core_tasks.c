/* TASK-SCHEDULER-1: lazy structured CPU tasks. The deque follows the C11
 * Chase-Lev algorithm of Lê et al., PPoPP 2013, figure 1. Old rings remain
 * allocated while thieves can still read them. Atomic slots prevent a late
 * thief's speculative read from racing an owner's wrapped slot reuse. */
enum { SELKA_KIND_TASK = 9, SELKA_KIND_GROUP = 10 };
typedef struct core_task core_task;
typedef struct {
    myl_block *tasks;
    _Atomic uint64_t pending;
    uintptr_t site;
    bool closed;
} core_group;
struct core_task {
    void *run;
    myl_block *env, *result;
    core_group *group;
    core_task_context site;
    _Atomic uint32_t state;
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
} core_tasks;
static SELKA_TLS core_task_worker *core_worker;
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
static void core_task_wake(void) {
    atomic_fetch_add_explicit(&core_tasks.epoch, 1, memory_order_release);
    syscall(SYS_futex, &core_tasks.epoch, FUTEX_WAKE_PRIVATE, INT32_MAX, NULL, NULL, 0);
}
static void core_task_park(uint32_t epoch) {
    syscall(SYS_futex, &core_tasks.epoch, FUTEX_WAIT_PRIVATE, epoch, NULL, NULL, 0);
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
    core_task_wake();
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
static void core_task_execute(core_task *task, bool parallel) {
    core_task_context saved = core_running_task;
    __typeof__(error_trace) saved_trace = error_trace;
    core_running_task = task->site;
    error_trace.origin = NULL;
    error_trace.count = 0;
    myl_block *result = myl_core_task_call(task->run, task->env);
    if (parallel) {
        myl_core_share(result);
        myl_core_release(task->env);
    }
    task->env = NULL;
    task->result = result;
    core_running_task = saved;
    error_trace = saved_trace;
    core_group *group = task->group;
    atomic_store_explicit(&task->state, 1, memory_order_release);
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
        uint32_t epoch = atomic_load_explicit(&core_tasks.epoch, memory_order_acquire);
        core_task *task = NULL;
        for (unsigned spin = 0; spin < 32 && !task; ++spin) task = core_task_find();
        if (task) core_task_execute(task, true);
        else core_task_park(epoch);
    }
    return NULL;
}
/* The embedding and emitted program have one submitting thread until this
 * function starts the pool. Afterwards the cached count is immutable. */
int64_t myl_core_threads(void) {
    static uint32_t configured;
    if (configured) return configured;
    uint64_t count = 0;
    const char *text = getenv("SELKA_THREADS");
    if (text) {
        if (!*text) core_io_fail("R_THREAD_COUNT");
        for (const char *p = text; *p; ++p) {
            if (*p < '0' || *p > '9' || count > (INT32_MAX - (unsigned)(*p - '0')) / 10u) core_io_fail("R_THREAD_COUNT");
            count = count * 10 + (unsigned)(*p - '0');
        }
        if (!count) core_io_fail("R_THREAD_COUNT");
    } else if (core_trap_marks_all) count = 1;
    else {
        cpu_set_t cpus;
        CPU_ZERO(&cpus);
        count = sched_getaffinity(0, sizeof cpus, &cpus) ? 1 : (uint64_t)CPU_COUNT(&cpus);
        if (!count) count = 1;
    }
    if (core_test_bounded || core_test_frame_limit) count = 1;
    configured = (uint32_t)count;
    return configured;
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
static void core_task_pool_start(void) {
    if (core_parallel()) return;
    if (core_test_batch_parent) core_io_fail("R_TASK_FORK");
    uint32_t size = (uint32_t)myl_core_threads();
    if (size == 1) return;
    core_thread_register();
    core_io_initialize();
    (void)core_ascii_char(0);
    core_floor_install();
    size_t bytes = (size_t)size * sizeof(core_task_worker);
    core_tasks.workers = aligned_alloc(_Alignof(core_task_worker), bytes);
    if (!core_tasks.workers) out_of_memory();
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
    struct rlimit limit;
    if (getrlimit(RLIMIT_STACK, &limit)) out_of_memory();
    size_t stack = limit.rlim_cur == RLIM_INFINITY ? (size_t)64 << 20 : (size_t)limit.rlim_cur;
    long page_size = sysconf(_SC_PAGESIZE);
    size_t page = page_size > 0 ? (size_t)page_size : 4096;
    if (stack < PTHREAD_STACK_MIN) stack = PTHREAD_STACK_MIN;
    pthread_attr_t attributes;
    if (pthread_attr_init(&attributes) || pthread_attr_setstacksize(&attributes, stack) ||
        pthread_attr_setguardsize(&attributes, page)) out_of_memory();
    sigset_t blocked, previous;
    sigemptyset(&blocked);
    sigaddset(&blocked, SIGALRM);
    if (pthread_sigmask(SIG_BLOCK, &blocked, &previous)) out_of_memory();
    atomic_store_explicit(&core_pool_started, true, memory_order_release);
    for (uint32_t i = 1; i < size; ++i)
        if (pthread_create(&core_tasks.workers[i].thread, &attributes, core_task_worker_main, &core_tasks.workers[i])) out_of_memory();
    pthread_attr_destroy(&attributes);
    if (pthread_sigmask(SIG_SETMASK, &previous, NULL)) out_of_memory();
    while (atomic_load_explicit(&core_tasks.ready, memory_order_acquire) != size - 1) {
        uint32_t epoch = atomic_load_explicit(&core_tasks.epoch, memory_order_acquire);
        if (atomic_load_explicit(&core_tasks.ready, memory_order_acquire) != size - 1) core_task_park(epoch);
    }
}
__attribute__((noinline)) myl_block *myl_core_group_open(void) {
    myl_block *block = block_new(SELKA_KIND_GROUP, sizeof(core_group), 1);
    block->len = 1;
    block->reserved = (int64_t)(intptr_t)core_group_layout;
    core_group *group = (core_group *)block_data(block);
    memset(group, 0, sizeof *group);
    atomic_init(&group->pending, 0);
    group->site = (uintptr_t)__builtin_return_address(0);
    group->tasks = myl_core_list_new_slow(8, sizeof(myl_block *));
    group->tasks->reserved = (int64_t)(intptr_t)layout_blocks;
    return block;
}
__attribute__((noinline)) myl_block *myl_core_task_submit(myl_block *block, void *run, myl_block *env, int64_t item) {
    core_group *group = (core_group *)block_data(block);
    if (core_test_batch_parent) core_io_fail("R_TASK_FORK");
    if (group->closed) core_io_fail("R_TASK_GROUP");
    core_task_pool_start();
    myl_block *handle = block_new(SELKA_KIND_TASK, sizeof(core_task), 1);
    handle->len = 1;
    handle->reserved = (int64_t)(intptr_t)core_task_layout;
    core_task *task = (core_task *)block_data(handle);
    task->run = run;
    task->env = env;
    task->result = NULL;
    task->group = group;
    task->site = (core_task_context){(uintptr_t)__builtin_return_address(0), group->site, item};
    atomic_init(&task->state, 0);
    bool parallel = core_parallel();
    if (parallel) {
        myl_core_share(env);
        count_retain(env);
        myl_core_share(handle);
    }
    count_retain(handle);
    group->tasks = myl_core_list_grow(group->tasks, sizeof(myl_block *));
    ((myl_block **)block_data(group->tasks))[group->tasks->len++] = handle;
    atomic_fetch_add_explicit(&group->pending, 1, memory_order_relaxed);
    if (parallel) {
        atomic_fetch_add_explicit(&core_tasks.pending, 1, memory_order_relaxed);
        core_task_push(&core_worker->queue, task);
    } else core_task_execute(task, false);
    return handle;
}
/* Capture the epoch before testing completion or searching, closing the lost
 * wake-up window between an empty search and the kernel's futex wait. */
static void core_group_wait(core_group *group) {
    while (atomic_load_explicit(&group->pending, memory_order_acquire)) {
        uint32_t epoch = atomic_load_explicit(&core_tasks.epoch, memory_order_acquire);
        if (!atomic_load_explicit(&group->pending, memory_order_acquire)) break;
        core_task *task = core_task_find();
        if (task) core_task_execute(task, true);
        else core_task_park(epoch);
    }
}
myl_block *myl_core_task_result(myl_block *handle) {
    core_task *wanted = (core_task *)block_data(handle);
    while (!atomic_load_explicit(&wanted->state, memory_order_acquire)) {
        uint32_t epoch = atomic_load_explicit(&core_tasks.epoch, memory_order_acquire);
        if (atomic_load_explicit(&wanted->state, memory_order_acquire)) break;
        core_task *task = core_task_find();
        if (task) core_task_execute(task, true);
        else core_task_park(epoch);
    }
    count_retain(wanted->result);
    return wanted->result;
}
void myl_core_group_close(myl_block *block) {
    core_group *group = (core_group *)block_data(block);
    core_group_wait(group);
    if (group->closed) return;
    group->closed = true;
    myl_core_release(group->tasks);
    group->tasks = NULL;
}
/* A dropped group still owns queued tasks: join before the shared child
 * iterator releases its handle list. Source lowering normally closes first. */
static void core_task_finalize(myl_block *block) {
    if (kind_of(block) == SELKA_KIND_GROUP) core_group_wait((core_group *)block_data(block));
}
static void core_tasks_quiesce(void) {
    if (!core_parallel()) return;
    while (atomic_load_explicit(&core_tasks.pending, memory_order_acquire)) {
        uint32_t epoch = atomic_load_explicit(&core_tasks.epoch, memory_order_acquire);
        if (!atomic_load_explicit(&core_tasks.pending, memory_order_acquire)) break;
        core_task *task = core_task_find();
        if (task) core_task_execute(task, true);
        else core_task_park(epoch);
    }
}
