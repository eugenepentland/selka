#include "core_rt.c"
#undef NDEBUG
#include <assert.h>
static pthread_barrier_t gate;
static myl_block *transferred[8];
static myl_block *clock_cap;
static const myl_core_site locations[8];
static void *thread_body(void *input) {
    intptr_t id = (intptr_t)input;
    core_worker_runtime_start();
    sigset_t mask;
    assert(!pthread_sigmask(SIG_SETMASK, NULL, &mask));
    assert(sigismember(&mask, SIGALRM) == 1);
    stack_t alternate;
    assert(!sigaltstack(NULL, &alternate));
    assert(!(alternate.ss_flags & SS_DISABLE));
    assert(core_stack_top && core_stack_bytes);
    error_trace.origin = &locations[id];
    core_io_site = &locations[id];
    transferred[id] = myl_core_list_new_slow(10, 8);
    core_text_walked += (uint64_t)id + 1;
    for (int i = 0; i < 1000; ++i) assert(!myl_core_clock_advance(clock_cap, 1));
    pthread_barrier_wait(&gate);
    assert(error_trace.origin == &locations[id]);
    assert(core_io_site == &locations[id]);
    myl_core_release(transferred[(id + 1) % 8]);
    myl_block *text = block_new(MYL_KIND_STR, 70000, 1);
    memset(block_data(text), 'a' + (int)id, 70000);
    text->len = 70000;
    myl_core_print_str(1, text);
    myl_core_print_end(1);
    myl_core_output_begin(1);
    text->len = 35000;
    myl_core_stream_write(1, text);
    sched_yield(); /* another writer must not split this composite print */
    myl_core_stream_write(1, text);
    myl_core_print_end(1);
    myl_core_output_end(1);
    myl_core_release(text);
    return NULL;
}
static const myl_core_site fatal_site = {TRAP_DIVISION_BY_ZERO, 7, 3, 64, "//", "task", "thread-probe.my"};
static void *fatal_body(void *input) {
    core_worker_runtime_start();
    core_running_task = (core_task_context){(uintptr_t)fatal_body, (uintptr_t)thread_body, (int64_t)(intptr_t)input};
    pthread_barrier_wait(&gate);
    myl_core_trap(&fatal_site, 1, 0);
    return NULL;
}
static volatile unsigned stop_depth;
__attribute__((noinline, disable_tail_calls)) static unsigned exhaust_stack(unsigned depth) {
    volatile unsigned char frame[32768];
    frame[0] = (unsigned char)depth;
    if (depth == stop_depth) return frame[0];
    unsigned value = exhaust_stack(depth + 1);
    return value + frame[0];
}
static void *floor_body(void *unused) {
    (void)unused;
    core_worker_runtime_start();
    core_running_task = (core_task_context){(uintptr_t)floor_body, 0, 19};
    return (void *)(uintptr_t)exhaust_stack(1);
}
static int fatal_mode(const char *mode) {
    pthread_mutex_lock(&core_io_mutex); /* fatal exit must never enter cleanup */
    if (!strcmp(mode, "locked")) pthread_mutex_lock(&core_stream_mutex);
    if (!strcmp(mode, "floor")) {
        pthread_attr_t attributes;
        assert(!pthread_attr_init(&attributes));
        assert(!pthread_attr_setstacksize(&attributes, 2 << 20));
        assert(!pthread_attr_setguardsize(&attributes, 4096));
        pthread_t worker;
        assert(!pthread_create(&worker, &attributes, floor_body, NULL));
        assert(!pthread_join(worker, NULL));
    } else {
        assert(!pthread_barrier_init(&gate, NULL, 8));
        pthread_t workers[8];
        for (intptr_t i = 0; i < 8; ++i) assert(!pthread_create(&workers[i], NULL, fatal_body, (void *)i));
        for (unsigned i = 0; i < 8; ++i) assert(!pthread_join(workers[i], NULL));
    }
    return 90; /* a fatal worker must exit the process, never return here */
}
int main(int argc, char **argv) {
    alarm(10);
    myl_core_start();
    stack_t original_stack, unchanged_stack;
    assert(!sigaltstack(NULL, &original_stack));
    uintptr_t original_top = core_stack_top;
    core_floor_install();
    assert(!sigaltstack(NULL, &unchanged_stack));
    assert(original_stack.ss_sp == unchanged_stack.ss_sp && core_stack_top == original_top);
    core_io_initialize();
    (void)core_ascii_char(0);
    core_thread_register();
    clock_cap = myl_core_stand_in(0, 0);
    atomic_store_explicit(&core_pool_started, true, memory_order_release);
    if (argc > 1 && strcmp(argv[1], "normal")) return fatal_mode(argv[1]);
    assert(!pthread_barrier_init(&gate, NULL, 8));
    pthread_t threads[8];
    for (intptr_t id = 0; id < 8; ++id) assert(!pthread_create(&threads[id], NULL, thread_body, (void *)id));
    for (int id = 0; id < 8; ++id) assert(!pthread_join(threads[id], NULL));
    assert(core_io_state(clock_cap)->value == 8000);
    myl_core_release(clock_cap);
    assert(core_thread_walk_total() == 36);
    assert(live_count() == 0);
    flush_all();
    return myl_core_exit(0);
}
