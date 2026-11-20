/* RUNTIME-HEAP-RETAIN-1: the heap policy the program's entry installs. RUNTIME-HEAP-RETURN-1: what an idle
 * poller wait gives back. The runtime is compiled into this file. */
/* The runtime's `malloc_trim` calls are counted: what a wait did is a count, what it gave back is resident memory. */
#define malloc_trim(pad) fixture_trim(pad)
#include "core_rt_all.c"
#undef malloc_trim
extern int malloc_trim(size_t pad);
static int trims;
int fixture_trim(size_t pad) {
    ++trims;
    return malloc_trim(pad);
}
#undef NDEBUG
#include <assert.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/resource.h>
#include <sys/socket.h>

myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }

static long minor_faults(void) {
    struct rusage usage;
    assert(!getrusage(RUSAGE_SELF, &usage));
    return usage.ru_minflt;
}

/* One request's worth of heap: `count` buffers of `size` bytes, held together, touched, and
   freed last in first out. glibc's own policy takes the heap top back on the last free of
   every cycle (the working set is above twice its largest adaptive threshold) or maps
   and unmaps each buffer; either way each cycle faults every page in again and the heap
   is resized again and again. Plain `malloc` keeps the layout of the heap top out of it. */
static void request_cycle(int count, size_t size) {
    unsigned char *held[8];
    assert(count <= 8);
    for (int i = 0; i < count; ++i) {
        held[i] = malloc(size);
        assert(held[i]);
        memset(held[i], 0x5a, size);
        __asm__ volatile("" : : "r"(held[i]) : "memory"); /* the optimizer must keep the touch */
    }
    for (int i = count - 1; i >= 0; --i) free(held[i]);
}

/* The same shape through the runtime's own large blocks: counted and refunded exactly. */
static void block_cycle(void) {
    myl_block *held[4];
    for (int i = 0; i < 4; ++i) {
        held[i] = block_new(MYL_KIND_BYTES, 65536, 1);
        held[i]->len = 65536;
        memset(block_data(held[i]), 0x5a, 65536);
    }
    assert(live_count() == 4);
    for (int i = 3; i >= 0; --i) myl_core_drop_owned(held[i]);
}

static int heap_mode(void) {
    myl_core_start();
    /* Eight 128 KiB buffers, then four 1 MiB ones: both stay in the heap, no page faults. */
    for (int i = 0; i < 60; ++i) request_cycle(8, 128 * 1024);
    long before = minor_faults();
    for (int i = 0; i < 400; ++i) request_cycle(8, 128 * 1024);
    long faults = minor_faults() - before;
    assert(faults < 100);
    for (int i = 0; i < 20; ++i) request_cycle(4, 1 << 20);
    before = minor_faults();
    for (int i = 0; i < 100; ++i) request_cycle(4, 1 << 20);
    faults = minor_faults() - before;
    assert(faults < 100);
    /* A block of 4 MiB or more is mapped on its own, so a big list can grow by `mremap`. */
    size_t mapped = mallinfo2().hblks;
    void *large = malloc(8 << 20);
    assert(large);
    __asm__ volatile("" : : "r"(large) : "memory");
    assert(mallinfo2().hblks == mapped + 1);
    free(large);
    assert(mallinfo2().hblks == mapped);
    heap_ceiling = 256u << 20;
    for (int i = 0; i < 100; ++i) block_cycle();
    assert(live_count() == 0);
    assert(atomic_load_explicit(&heap_held, memory_order_relaxed) == 0);
    /* Above the mmap threshold a block is still counted and returned exactly. */
    myl_block *big = block_new(MYL_KIND_BYTES, 40 << 20, 1);
    assert(live_count() == 1);
    assert(atomic_load_explicit(&heap_held, memory_order_relaxed) >= (40u << 20));
    myl_core_drop_owned(big);
    assert(live_count() == 0);
    assert(atomic_load_explicit(&heap_held, memory_order_relaxed) == 0);
    puts("heap: request-shaped cycles stay in the heap; budget and leak counts exact");
    return 0;
}

/* `blocks` large blocks of `size` bytes, written and then freed: free memory the C library holds and, from MYL_HEAP_TRIM_FREES
   blocks on, a look due. */
static void fill_and_drop(int blocks, size_t size) {
    static myl_block *held[2048];
    assert(blocks <= 2048);
    for (int i = 0; i < blocks; ++i) {
        held[i] = block_new(MYL_KIND_BYTES, (int64_t)size, 1);
        held[i]->len = (int64_t)size;
        memset(block_data(held[i]), 0x5a, size);
    }
    for (int i = 0; i < blocks; ++i) myl_core_drop_owned(held[i]);
}

/* The resident memory of this process, in KiB. */
static long resident_kb(void) {
    long pages = 0, resident = 0;
    FILE *file = fopen("/proc/self/statm", "r");
    assert(file && fscanf(file, "%ld %ld", &pages, &resident) == 2);
    fclose(file);
    return resident * (sysconf(_SC_PAGESIZE) / 1024);
}
static unsigned freed_since_look(void) { return atomic_load_explicit(&core_heap_freed, memory_order_relaxed); }
static unsigned wait_count(CorePoller *poller) { return core_poll_get(poller->response + 4); }

static unsigned short listener_port(int listener) {
    struct sockaddr_in at;
    socklen_t length = sizeof at;
    assert(!getsockname(listener, (struct sockaddr *)&at, &length));
    return ntohs(at.sin_port);
}

static void connect_to(unsigned short port) {
    int client = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in at = {.sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    assert(client >= 0 && !connect(client, (struct sockaddr *)&at, sizeof at));
    close(client);
}

static void *connect_later(void *port) {
    usleep(150000);
    connect_to((unsigned short)(uintptr_t)port);
    return NULL;
}

/* The poller's wait gives free memory back only when it is about to block in an idle loop, and only when enough has been freed. */
static int trim_mode(void) {
    myl_core_start();
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in at = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    assert(listener >= 0 && !bind(listener, (struct sockaddr *)&at, sizeof at) && !listen(listener, 8));
    unsigned short port = listener_port(listener);
    CorePoller *poller = core_poll_create(listener);
    assert(poller);
    long base = resident_kb();
    /* A heap that holds little is looked at, not trimmed, and the count starts again. */
    fill_and_drop(300, 1100);
    assert(freed_since_look() >= MYL_HEAP_TRIM_FREES);
    poller->quiet_ms = core_poll_now_ms() - 5000;
    core_poll_wait(poller, 20, 10);
    assert(freed_since_look() == 0 && trims == 0);
    /* Fewer frees than a look wants: nothing is looked at, however long and idle the wait. */
    fill_and_drop(100, 4096);
    poller->quiet_ms = core_poll_now_ms() - 5000;
    core_poll_wait(poller, 20, 10);
    assert(freed_since_look() == 100 && trims == 0);
    /* 2,000 blocks of 4 KiB: 8 MB the C library keeps (RUNTIME-HEAP-RETAIN-1), and a look is due. */
    fill_and_drop(2000, 4096);
    assert(freed_since_look() >= MYL_HEAP_TRIM_FREES && resident_kb() > base + 7000);
    /* A wait that cannot block, and short waits of a loop that has not been quiet for a second, leave it. */
    poller->quiet_ms = 0;
    core_poll_wait(poller, 0, 10);
    core_poll_wait(poller, 20, 10);
    core_poll_wait(poller, 20, 10);
    assert(freed_since_look() >= MYL_HEAP_TRIM_FREES && trims == 0 && resident_kb() > base + 7000);
    /* A busy loop is left, whatever its history: the event is there, so the wait never blocks. */
    connect_to(port);
    poller->quiet_ms = core_poll_now_ms() - 5000;
    core_poll_wait(poller, UINT32_MAX, 10);
    assert(wait_count(poller) == 1 && poller->quiet_ms == 0);
    assert(freed_since_look() >= MYL_HEAP_TRIM_FREES && trims == 0 && resident_kb() > base + 7000);
    int accepted = accept(listener, NULL, NULL);
    assert(accepted >= 0);
    close(accepted);
    /* A loop whose waits found nothing for a second is idle: its next short wait trims first, once. */
    poller->quiet_ms = core_poll_now_ms() - 1500;
    atomic_store_explicit(&core_heap_resume_us, 0, memory_order_relaxed);
    core_poll_wait(poller, 20, 10);
    assert(wait_count(poller) == 0 && freed_since_look() == 0 && trims == 1 && resident_kb() < base + 2000);
    /* What a look and a trim took keeps the next one away for a hundred times as long: an idle loop that frees again is left. */
    assert(atomic_load_explicit(&core_heap_resume_us, memory_order_relaxed) > 0);
    fill_and_drop(2000, 4096);
    atomic_store_explicit(&core_heap_resume_us, core_heap_now_us() + 60000000, memory_order_relaxed);
    poller->quiet_ms = core_poll_now_ms() - 1500;
    core_poll_wait(poller, 20, 10);
    assert(freed_since_look() >= MYL_HEAP_TRIM_FREES && trims == 1 && resident_kb() > base + 7000);
    atomic_store_explicit(&core_heap_resume_us, 0, memory_order_relaxed);
    core_poll_wait(poller, 20, 10);
    assert(freed_since_look() == 0 && trims == 2 && resident_kb() < base + 2000);
    /* A wait that will block for a second or more trims before it blocks, and an event still ends it at once. */
    fill_and_drop(2000, 4096);
    assert(resident_kb() > base + 7000);
    atomic_store_explicit(&core_heap_resume_us, 0, memory_order_relaxed);
    poller->quiet_ms = 0;
    pthread_t thread;
    assert(!pthread_create(&thread, NULL, connect_later, (void *)(uintptr_t)port));
    int64_t began = core_poll_now_ms();
    core_poll_wait(poller, 20000, 10);
    assert(core_poll_now_ms() - began < 10000 && wait_count(poller) == 1);
    assert(freed_since_look() == 0 && trims == 3 && resident_kb() < base + 2000);
    pthread_join(thread, NULL);
    accepted = accept(listener, NULL, NULL);
    assert(accepted >= 0);
    close(accepted);
    assert(live_count() == 0);
    puts("trim: an idle poller wait gives free memory back once; a busy or short one leaves it");
    return 0;
}

int main(int argc, char **argv) {
    alarm(60);
    if (argc > 1 && !strcmp(argv[1], "heap")) return heap_mode();
    if (argc > 1 && !strcmp(argv[1], "trim")) return trim_mode();
    return 2;
}
