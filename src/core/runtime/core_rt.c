/* The new core's runtime (docs/design/new-core-ir.md §8, new-core-s1.md §5-§6).
 *
 * Blocks: a 32-byte header {u32 count, u32 kind, i64 len, i64 cap, i64 reserved}
 * followed by 32-byte-aligned data. `count` is the single saturating 32-bit
 * reference count of D4; every block starts with count 1, and the emitted code
 * counts inline and frees through `myl_core_free`. `reserved` holds the element
 * layout of a list or box whose elements hold blocks (null otherwise), so a free
 * releases the children. There is no collector and no memory budget in a program
 * (L3): an allocation the OS refuses ends the process with one message. A test
 * child alone may carry a byte ceiling (`--max-memory`, `heap_ceiling` below).
 *
 * Output: one buffer per standard stream, flushed when full, at exit and before a
 * trap report, so stdout keeps program order relative to a trap. */
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
/* XSI: the signal stack the stack-floor report runs on (`sigaltstack`, `SA_ONSTACK`). */
#define _XOPEN_SOURCE 700
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <elf.h>
#include <execinfo.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <malloc.h>
#include <pthread.h>
#include <stdatomic.h>
#include <signal.h>
#include <errno.h>
#include <sched.h>
#include <sys/syscall.h>
#include <linux/futex.h>

/* RUNTIME-THREADS-1: the executable owns TLS; no dynamic library can unload it. */
#define MYL_TLS _Thread_local __attribute__((tls_model("initial-exec")))
static _Atomic bool core_pool_started;
static _Atomic uint32_t core_fatal_winner;
static MYL_TLS bool core_fatal_owner, core_fatal_raw;
static pthread_mutex_t core_stream_mutex = PTHREAD_MUTEX_INITIALIZER;
typedef struct { uintptr_t submit, group; int64_t item; } core_task_context;
static MYL_TLS core_task_context core_running_task;
static bool core_parallel(void) { return atomic_load_explicit(&core_pool_started, memory_order_acquire); }

/* ---- platform layer (POSIX) ------------------------------------------------
 * Every operating-system call the runtime makes goes through these functions;
 * the rest of the file is portable C11. A Windows or macOS port replaces this
 * section (or moves it to a core_rt_<os>.c); arguments arrive through the
 * LLVM-emitted C `main`, and future clock, file, network and environment
 * access belongs here too. */

/* Write all of `len` bytes to a standard stream (1 or 2), as far as the OS allows;
   false when it refused some of them. */
static bool os_write(int fd, const unsigned char *bytes, size_t len) {
    size_t done = 0;
    while (done < len) {
        ssize_t wrote = write(fd, bytes + done, len - done);
        if (wrote <= 0) return false;
        done += (size_t)wrote;
    }
    return true;
}

/* End the process now, with no atexit handlers (a trap or a fatal error). */
static void core_io_cleanup(void);
static void core_host_cleanup(void);
static void core_fatal_begin(void);
static void core_task_report(void);
static void os_exit(int status) { if (core_parallel()) { core_fatal_begin(); core_task_report(); _exit(status ? 1 : 0); } core_task_report(); core_io_cleanup(); _exit(status); }

/* The return addresses on the stack, innermost first, walked through `.eh_frame`
   (glibc's `backtrace`, which is libgcc's `_Unwind_Backtrace`; no unwinder is
   linked into the program). */
static int os_stack(void **pcs, int capacity) { return core_fatal_raw ? 0 : backtrace(pcs, capacity); }

/* This executable's bytes, mapped read-only (for its DWARF sections), or NULL. */
static const unsigned char *os_map_self(size_t *size) {
    int fd = open("/proc/self/exe", O_RDONLY);
    if (fd < 0) return NULL;
    struct stat info;
    void *bytes = MAP_FAILED;
    if (fstat(fd, &info) == 0) bytes = mmap(NULL, (size_t)info.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (bytes == MAP_FAILED) return NULL;
    *size = (size_t)info.st_size;
    return bytes;
}

/* ---- blocks ------------------------------------------------------------------ */

typedef struct {
    uint32_t count;
    uint32_t kind;
    int64_t len;
    int64_t cap;
    int64_t reserved;
} myl_block;

enum { MYL_KIND_LIST = 0, MYL_KIND_STR = 1, MYL_KIND_BOX = 2, MYL_KIND_BYTES = 3, MYL_KIND_DICT = 4 };
enum { MYL_HEADER = 32, MYL_ALIGN = 32 };
/* A saturated count (D4): the block is immortal, never written and never freed. */
#define MYL_SATURATED UINT32_MAX
#define MYL_SHARED UINT32_C(0x80000000)
#define MYL_PLAIN_MAX UINT32_C(0x7ffffffe)

/* SHARED-COUNTS-1: only unpublished/plain blocks may use non-atomic writes.
   A count read can race with shared retains/releases, even a uniqueness test.
   C's relaxed load is the weakest available atomic load; the LLVM emitter uses
   unordered so its loop-invariant uniqueness tests can still be hoisted. */
static uint32_t count_load(const myl_block *block) {
    return __atomic_load_n(&block->count, __ATOMIC_RELAXED);
}

static bool count_is_unique(const myl_block *block) { return count_load(block) == 1; }
static bool count_can_cache(const myl_block *block) { return count_load(block) < MYL_SHARED; }

/* CAS keeps immortality sticky even if a retain saturates while a release is
   in flight. An unconditional fetch-add/sub after testing for immortality
   could wrap or decrement the immortal sentinel. Both operations are cold. */
__attribute__((cold, noinline, preserve_most)) void myl_core_retain_slow(myl_block *block) {
    uint32_t count = count_load(block);
    if (count < MYL_SHARED) {
        block->count = MYL_SATURATED;
        return;
    }
    while (count != MYL_SATURATED) {
        if (__atomic_compare_exchange_n(&block->count, &count, count + 1, true,
                                        __ATOMIC_RELAXED, __ATOMIC_RELAXED)) return;
    }
}

/* Drop a shared owner; only the thread that removed the last one may free.
   Its acquire makes every prior owner's release visible to destruction. */
__attribute__((cold, noinline, preserve_most)) static bool count_release_shared(myl_block *block) {
    uint32_t count = count_load(block);
    while (count != MYL_SATURATED) {
        /* Acquire on the last-owner RMW is equivalent to the following acquire
           fence, and is visible to TSan's atomic synchronization model. */
        const int order = count == MYL_SHARED + 1 ? __ATOMIC_ACQ_REL : __ATOMIC_RELEASE;
        if (__atomic_compare_exchange_n(&block->count, &count, count - 1, true,
                                        order, __ATOMIC_RELAXED)) return count == MYL_SHARED + 1;
    }
    return false;
}

static void count_retain(myl_block *block) {
    if (!block) return;
    uint32_t count = count_load(block);
    if (count < MYL_PLAIN_MAX) block->count = count + 1;
    else if (count != MYL_SATURATED) myl_core_retain_slow(block);
}

/* Return last-owner status rather than recurse: the free walk enqueues children. */
static bool count_release(myl_block *block) {
    if (!block) return false;
    uint32_t count = count_load(block);
    if (count < MYL_SHARED) {
        if (count == 1) return true;
        block->count = count - 1;
        return false;
    }
    if (count == MYL_SATURATED) return false;
    return count_release_shared(block);
}

__attribute__((cold)) void myl_core_free_block(myl_block *block);
/* Keep an immortal release from paying the ordinary free call's register save.
   The last shared owner alone crosses this second preserve-most boundary. */
__attribute__((cold, noinline, preserve_most)) static void count_free_shared(myl_block *block) {
    myl_core_free_block(block);
}

__attribute__((cold, noinline, preserve_most)) void myl_core_release_slow(myl_block *block) {
    if (count_release_shared(block)) count_free_shared(block);
}

static unsigned char *block_data(myl_block *block) { return (unsigned char *)block + MYL_HEADER; }

static void out_of_memory(void);
/* Set by a test executable (`myl_core_test_open`): every trap writes a record. */
static bool core_trap_marks_all;
static void core_io_failure(const char *code);

/* A test child's byte ceiling (`mylang-core test --max-memory`, set by
   `myl_core_test_ceilings`; 0: none, the only state outside tests). Only the
   allocator's slow paths touch it: the 64 KiB chunks small blocks are carved
   from (never returned) and each large block's usable size while it lives, so
   the inline fast paths and every program built without a ceiling pay nothing.
   Exceeding it traps `R_MEMORY_BUDGET`, as the old core's managed heap does;
   the process's `RLIMIT_AS` at the ceiling plus 256 MiB backs everything else. */
static uint64_t heap_ceiling;
static _Atomic uint64_t heap_held;

__attribute__((cold, noinline)) static void heap_exhausted(void) {
    core_io_failure("R_MEMORY_BUDGET");
}

static void heap_charge(size_t bytes) {
    if (!heap_ceiling) return;
    uint64_t held = atomic_load_explicit(&heap_held, memory_order_relaxed);
    for (;;) {
        if (held > heap_ceiling || bytes > heap_ceiling - held) heap_exhausted();
        if (atomic_compare_exchange_weak_explicit(&heap_held, &held, held + bytes,
                memory_order_relaxed, memory_order_relaxed)) return;
    }
}

static void heap_refund(size_t bytes) {
    if (!heap_ceiling) return;
    uint64_t held = atomic_load_explicit(&heap_held, memory_order_relaxed);
    while (!atomic_compare_exchange_weak_explicit(&heap_held, &held, held - (bytes < held ? bytes : held),
            memory_order_relaxed, memory_order_relaxed)) {}
}

/* Blocks ever carved from chunks plus large blocks not yet freed. A small block is
   live exactly when it was carved and is not on a free list, so the
   MYL_CORE_LEAKCHECK=1 count (`live_count`) needs no counting on the fast paths. */
static _Atomic int64_t live_blocks;

/* ---- allocation ----------------------------------------------------------------
 * Blocks of up to MYL_SMALL bytes (header included) come from per-size-class free
 * lists, one class per 32-byte granule, carved from 64 KiB chunks that are never
 * returned; a freed small block goes back to its class's list. Larger blocks are
 * `malloc`ed, and a large list grows with `realloc`. The class sits in the high
 * byte of `kind` (0: large), so a free needs no size. A list's `cap` is all its
 * block holds, so a small list grows within its class without moving.
 * Free lists and chunk cursors belong to the current thread. The common cases (a small list from a free
 * list, a push with room, a free of a small block without children) are emitted
 * inline by `emit_llvm.zig` against `myl_core_free_lists`; these functions are
 * the rest. */
enum { MYL_GRANULE = 32, MYL_SMALL = 1024, MYL_CLASSES = MYL_SMALL / MYL_GRANULE, MYL_CHUNK = 1 << 16 };
#define MYL_KIND_MASK 0xffu
#define MYL_CLASS_SHIFT 24
/* Class 0xff marks a list `promote.zig` put in a stack frame (`emit_llvm.zig`
   `stackList`): nothing releases it and its pushes skip `myl_core_list_grow`, so no
   function here ever sees one. */

MYL_TLS void *myl_core_free_lists[MYL_CLASSES + 1];
#define free_lists myl_core_free_lists
static MYL_TLS unsigned char *chunk_next, *chunk_end;
static MYL_TLS uint64_t core_text_walked;

/* Keep thread allocator identities until exit. Pool workers live until process
   exit; the destructor also preserves free lists from short-lived native test
   threads, so a registry entry never points into retired TLS. Report readers
   hold this mutex and run only after task quiescence. */
typedef struct core_thread_record {
    void **lists;
    uint64_t *walked;
    void *retired_lists[MYL_CLASSES + 1];
    uint64_t retired_walked;
    struct core_thread_record *next;
} core_thread_record;
static core_thread_record *core_thread_records;
static pthread_mutex_t core_thread_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t core_thread_key_once = PTHREAD_ONCE_INIT;
static pthread_key_t core_thread_key;
static MYL_TLS core_thread_record *core_thread_registered;

static void core_thread_retire(void *pointer) {
    core_thread_record *record = pointer;
    pthread_mutex_lock(&core_thread_mutex);
    memcpy(record->retired_lists, record->lists, sizeof record->retired_lists);
    record->retired_walked = *record->walked;
    record->lists = record->retired_lists;
    record->walked = &record->retired_walked;
    pthread_mutex_unlock(&core_thread_mutex);
}

static void core_thread_key_initialize(void) {
    if (pthread_key_create(&core_thread_key, core_thread_retire)) out_of_memory();
}

static void core_thread_register(void) {
    if (core_thread_registered) return;
    core_thread_record *record = calloc(1, sizeof *record);
    if (!record) out_of_memory();
    record->lists = free_lists;
    record->walked = &core_text_walked;
    pthread_once(&core_thread_key_once, core_thread_key_initialize);
    if (pthread_setspecific(core_thread_key, record)) out_of_memory();
    pthread_mutex_lock(&core_thread_mutex);
    record->next = core_thread_records;
    core_thread_records = record;
    pthread_mutex_unlock(&core_thread_mutex);
    core_thread_registered = record;
}

static uint64_t core_thread_walk_total(void) {
    uint64_t total = 0;
    core_thread_register();
    pthread_mutex_lock(&core_thread_mutex);
    for (core_thread_record *at = core_thread_records; at; at = at->next) total += *at->walked;
    pthread_mutex_unlock(&core_thread_mutex);
    return total;
}

static uint32_t kind_of(const myl_block *block) { return block->kind & MYL_KIND_MASK; }
static uint32_t class_of(const myl_block *block) { return block->kind >> MYL_CLASS_SHIFT; }

/* A small block of `class` granules: from its free list, else carved from a chunk. */
static void *small_alloc(uint32_t class) {
    core_thread_register();
    void *block = free_lists[class];
    if (block) {
        free_lists[class] = *(void **)block;
        return block;
    }
    size_t bytes = (size_t)class * MYL_GRANULE;
    if ((size_t)(chunk_end - chunk_next) < bytes) {
        chunk_next = aligned_alloc(MYL_ALIGN, MYL_CHUNK);
        if (!chunk_next) out_of_memory();
        heap_charge(MYL_CHUNK);
        chunk_end = chunk_next + MYL_CHUNK;
    }
    block = chunk_next;
    chunk_next += bytes;
    atomic_fetch_add_explicit(&live_blocks, 1, memory_order_relaxed);
    return block;
}

/* A block for `data` bytes after the header; `*room` gets the data bytes it really holds. */
static myl_block *block_alloc(uint32_t kind, size_t data, size_t *room) {
    size_t bytes = MYL_HEADER + data;
    myl_block *block;
    uint32_t class = 0;
    if (bytes <= MYL_SMALL) {
        class = (uint32_t)((bytes + MYL_GRANULE - 1) / MYL_GRANULE);
        block = small_alloc(class);
        *room = (size_t)class * MYL_GRANULE - MYL_HEADER;
    } else {
        /* 32-byte alignment keeps element data on vector boundaries (measured:
           16-byte `malloc` alignment cost integer_math 4% and binary_search 10%). */
        block = aligned_alloc(MYL_ALIGN, (bytes + MYL_ALIGN - 1) & ~(size_t)(MYL_ALIGN - 1));
        if (!block) out_of_memory();
        if (heap_ceiling) heap_charge(malloc_usable_size(block));
        *room = data;
        atomic_fetch_add_explicit(&live_blocks, 1, memory_order_relaxed);
    }
    block->count = 1;
    block->kind = kind | (class << MYL_CLASS_SHIFT);
    block->len = 0;
    block->reserved = 0;
    return block;
}

/* A block of `kind` with room for `cap` elements of `element_size` bytes (a string
   also for its terminating NUL); a list's `cap` is everything the block holds. */
static myl_block *block_new(uint32_t kind, int64_t cap, int64_t element_size) {
    size_t wanted = (size_t)(cap > 0 ? cap : 0) * (size_t)element_size + (kind == MYL_KIND_STR);
    size_t room;
    myl_block *block = block_alloc(kind, wanted, &room);
    block->cap = kind == MYL_KIND_LIST && element_size > 0 ? (int64_t)(room / (size_t)element_size) : (cap > 0 ? cap : 0);
    return block;
}

/* Blocks allocated and not freed: carved and large ones, less those on free lists. */
static int64_t live_count(void) {
    int64_t live = atomic_load_explicit(&live_blocks, memory_order_relaxed);
    pthread_mutex_lock(&core_thread_mutex);
    for (core_thread_record *record = core_thread_records; record; record = record->next) {
        for (int class = 1; class <= MYL_CLASSES; ++class) {
            for (void *at = record->lists[class]; at; at = *(void **)at) --live;
        }
    }
    pthread_mutex_unlock(&core_thread_mutex);
    return live;
}

static void block_free(myl_block *block) {
    uint32_t class = class_of(block);
    core_thread_register();
    if (class == 0) {
        atomic_fetch_sub_explicit(&live_blocks, 1, memory_order_relaxed);
        if (heap_ceiling) heap_refund(malloc_usable_size(block));
        free(block);
        return;
    }
    *(void **)block = free_lists[class];
    free_lists[class] = block;
}

/* ---- element layouts ---------------------------------------------------------
 * Where the blocks inside one element (or a box's value) are, as the emitter
 * writes them (`@myl.layout.N`, an i32 array):
 *   [0] element size in bytes, [1] reference count R, [2] guard count G,
 *   then R pairs {offset, guard}: an 8-byte block pointer (null allowed) at
 *   `offset`, counted only when guard `guard` holds (0: always; else 1-based),
 *   then G triples {offset, value, parent}: the 8-byte union tag word at
 *   `offset` equals `value`, and guard `parent` holds too (0: none).
 * A union's payload references are guarded by its tag, so an integer in a
 * payload word is never taken for a pointer. */
typedef const int32_t myl_layout;

static myl_layout *layout_of(const myl_block *block) { return (myl_layout *)(intptr_t)block->reserved; }

static bool guard_holds(myl_layout *layout, const unsigned char *element, int32_t guard) {
    myl_layout *guards = layout + 3 + 2 * layout[1];
    while (guard != 0) {
        myl_layout *g = guards + 3 * (guard - 1);
        int64_t tag;
        memcpy(&tag, element + g[0], sizeof tag);
        if (tag != g[1]) return false;
        guard = g[2];
    }
    return true;
}

/* The block pointer of reference `r` in `element`, or null when its guard fails. */
static myl_block *reference_at(myl_layout *layout, const unsigned char *element, int32_t r) {
    myl_layout *ref = layout + 3 + 2 * r;
    if (!guard_holds(layout, element, ref[1])) return NULL;
    myl_block *child;
    memcpy(&child, element + ref[0], sizeof child);
    return child;
}

/* How many elements a block's layout covers: a list's length, a box's one value. */
static int64_t element_count(const myl_block *block) { return kind_of(block) == MYL_KIND_BOX ? 1 : block->len; }

/* ---- buffered streams ------------------------------------------------------- */

typedef struct {
    size_t used;
    unsigned char bytes[1 << 16];
} myl_stream;

/* Zero-initialized (in .bss, not 128 KiB of .data): stream i writes descriptor i + 1. */
static myl_stream streams[2];

static myl_stream *stream_for(int64_t fd) { return &streams[fd == 2 ? 1 : 0]; }

/* Standard output refused a write: the program's output is lost, so it fails with
   `R_OUTPUT` and status 1, as the old core's did (STREAM-BYTES-1, IO-6), instead of
   exiting with `main`'s status. Output is buffered, so the report has no location. */
static void output_refused(void);

/* A complete print/write is staged privately, including units larger than the
   ordinary 64 KiB stream buffer. The stream lock covers the complete append. */
typedef struct { unsigned char *bytes; size_t used, capacity, depth; } core_stage;
static MYL_TLS core_stage core_staging[2];

static void core_fatal_begin(void) {
    if (!core_parallel() || core_fatal_owner) return;
    uint32_t expected = 0;
    if (!atomic_compare_exchange_strong_explicit(&core_fatal_winner, &expected, 1,
            memory_order_acq_rel, memory_order_relaxed)) {
        for (;;) (void)syscall(SYS_futex, &core_fatal_winner, FUTEX_WAIT_PRIVATE, 1, NULL, NULL, 0);
    }
    core_fatal_owner = true;
    /* Never wait for a thread stopped inside a stream write, especially when
       this is a synchronous signal on the lock's own thread. */
    for (unsigned attempt = 0; attempt < 1024; ++attempt) {
        if (!pthread_mutex_trylock(&core_stream_mutex)) return;
    }
    core_fatal_raw = true;
}

static void stream_flush_unlocked(myl_stream *stream) {
    size_t used = stream->used;
    stream->used = 0;
    if (!os_write(stream == &streams[1] ? 2 : 1, stream->bytes, used) && stream == &streams[0]) output_refused();
}

static void stream_write_unlocked(myl_stream *stream, const void *data, size_t len) {
    const unsigned char *bytes = data;
    while (len > 0) {
        if (stream->used == sizeof stream->bytes) stream_flush_unlocked(stream);
        size_t room = sizeof stream->bytes - stream->used;
        size_t take = len < room ? len : room;
        memcpy(stream->bytes + stream->used, bytes, take);
        stream->used += take;
        bytes += take;
        len -= take;
    }
}

static void stream_commit(myl_stream *stream) {
    if (!core_parallel() || core_fatal_owner) return;
    core_stage *stage = &core_staging[stream == &streams[1]];
    if (!stage->used || stage->depth) return;
    pthread_mutex_lock(&core_stream_mutex);
    stream_write_unlocked(stream, stage->bytes, stage->used);
    stage->used = 0;
    if (stream == &streams[1]) stream_flush_unlocked(stream);
    pthread_mutex_unlock(&core_stream_mutex);
}

static void stream_flush(myl_stream *stream) {
    if (!core_parallel()) { stream_flush_unlocked(stream); return; }
    if (core_fatal_raw) return;
    if (core_fatal_owner) { stream_flush_unlocked(stream); return; }
    stream_commit(stream);
    pthread_mutex_lock(&core_stream_mutex);
    stream_flush_unlocked(stream);
    pthread_mutex_unlock(&core_stream_mutex);
}

static void output_refused(void) {
    core_fatal_begin();
    static const char text[] = "error[R_OUTPUT]: native execution failed\nstandard output refused a write\n";
    stream_flush(&streams[1]);
    os_write(2, (const unsigned char *)text, sizeof text - 1);
    os_exit(1);
}

static void stream_write(myl_stream *stream, const void *data, size_t len) {
    if (!core_parallel()) { stream_write_unlocked(stream, data, len); return; }
    if (core_fatal_raw) { os_write(2, data, len); return; }
    if (core_fatal_owner) { stream_write_unlocked(stream, data, len); return; }
    core_stage *stage = &core_staging[stream == &streams[1]];
    if (len > SIZE_MAX - stage->used) out_of_memory();
    size_t need = stage->used + len;
    if (need > stage->capacity) {
        size_t capacity = stage->capacity ? stage->capacity : 256;
        while (capacity < need && capacity <= SIZE_MAX / 2) capacity *= 2;
        if (capacity < need) capacity = need;
        unsigned char *grown = realloc(stage->bytes, capacity);
        if (!grown) out_of_memory();
        stage->bytes = grown;
        stage->capacity = capacity;
    }
    if (len) memcpy(stage->bytes + stage->used, data, len);
    stage->used += len;
}

static void flush_all(void) {
    stream_flush(&streams[0]);
    stream_flush(&streams[1]);
}

static void out_of_memory(void) {
    core_fatal_begin();
    flush_all();
    /* Under a test's byte ceiling the OS refusal is its `RLIMIT_AS` backstop: the same trap,
       reported without the frame walk, which may itself need memory. */
    static const char ceiling[] = "error[R_MEMORY_BUDGET]: memory budget exhausted; raise it with --max-memory=SIZE\n";
    static const char message[] = "fatal: out of memory\n";
    /* A test trial's trap record, so its runner reports the trap (NEW-CORE-S5-TRACE-1). */
    static const char record[] = "\036MYLANG-TRAP {\"version\":1,\"operation\":\"memory budget exhausted\"}\n";
    if (heap_ceiling) os_write(2, (const unsigned char *)ceiling, sizeof ceiling - 1);
    else os_write(2, (const unsigned char *)message, sizeof message - 1);
    if (heap_ceiling && core_trap_marks_all) os_write(2, (const unsigned char *)record, sizeof record - 1);
    os_exit(1);
}

/* Integer formatting is supplied by core_number.c after the text runtime. */
void myl_core_print_i64(int64_t fd, int64_t value);
void myl_core_print_u64(int64_t fd, uint64_t value);

void myl_core_print_bool(int64_t fd, bool value) {
    if (value) stream_write(stream_for(fd), "True", 4);
    else stream_write(stream_for(fd), "False", 5);
}

void myl_core_print_str(int64_t fd, myl_block *text) {
    stream_write(stream_for(fd), block_data(text), (size_t)text->len);
}

void myl_core_print_sep(int64_t fd) { stream_write(stream_for(fd), " ", 1); }

void myl_core_print_end(int64_t fd) {
    stream_write(stream_for(fd), "\n", 1);
    stream_commit(stream_for(fd));
    if (fd == 2) stream_flush(stream_for(fd));
}

/* A print with dynamic separator/terminator lowers to several write helpers.
   Nest those writes in one unit; arguments were evaluated before begin. */
void myl_core_output_begin(int64_t fd) {
    if (core_parallel()) ++core_staging[fd == 2].depth;
}
void myl_core_output_end(int64_t fd) {
    if (!core_parallel()) return;
    core_stage *stage = &core_staging[fd == 2];
    if (stage->depth) --stage->depth;
    stream_commit(stream_for(fd));
    if (fd == 2 && !stage->depth) stream_flush(stream_for(fd));
}

/* ---- lists and strings ------------------------------------------------------ */

/* A fresh list, when the emitted fast path finds no free block of its class. */
myl_block *myl_core_list_new_slow(int64_t cap, int64_t element_size) {
    return block_new(MYL_KIND_LIST, cap, element_size);
}

/* A block with room for one more element: `list` itself while it has room,
   else a grown copy. The caller's old value is dead after the push (the IR's
   uniqueness rule), so growing frees the old block. */
myl_block *myl_core_list_grow(myl_block *list, int64_t element_size) {
    if (list->len < list->cap) return list;
    int64_t cap = list->cap < 4 ? 8 : list->cap * 2;
    if (class_of(list) == 0) {
        /* A large block grows in place where the allocator can (one block either
           way), and moves to a fresh aligned block when `realloc` loses the alignment. */
        size_t bytes = MYL_HEADER + (size_t)cap * (size_t)element_size;
        if (heap_ceiling) heap_refund(malloc_usable_size(list));
        myl_block *moved = realloc(list, bytes);
        if (!moved) out_of_memory();
        if (((uintptr_t)moved & (MYL_ALIGN - 1)) != 0) {
            myl_block *aligned = aligned_alloc(MYL_ALIGN, (bytes + MYL_ALIGN - 1) & ~(size_t)(MYL_ALIGN - 1));
            if (!aligned) out_of_memory();
            memcpy(aligned, moved, MYL_HEADER + (size_t)moved->len * (size_t)element_size);
            free(moved);
            moved = aligned;
        }
        if (heap_ceiling) heap_charge(malloc_usable_size(moved));
        moved->cap = cap;
        return moved;
    }
    myl_block *grown = block_new(MYL_KIND_LIST, cap, element_size);
    memcpy(block_data(grown), block_data(list), (size_t)list->len * (size_t)element_size);
    grown->len = list->len;
    grown->reserved = list->reserved;
    block_free(list);
    return grown;
}

/* One more owner of `block` (D4: a count that reaches the saturated value stays there). */
static void retain_block(myl_block *block) {
    count_retain(block);
}

/* A fresh copy of `list` with room for one more element: the copy arm of a
   copy-on-write update (`own.zig`), so the original block stays intact. The
   copy is a second owner of every block the elements hold. */
myl_block *myl_core_list_copy(myl_block *list, int64_t element_size) {
    myl_block *copy = block_new(MYL_KIND_LIST, list->len + 1, element_size);
    memcpy(block_data(copy), block_data(list), (size_t)list->len * (size_t)element_size);
    copy->len = list->len;
    copy->reserved = list->reserved;
    myl_layout *layout = layout_of(list);
    if (layout) {
        for (int64_t i = 0; i < list->len; ++i) {
            const unsigned char *element = block_data(list) + i * (int64_t)layout[0];
            for (int32_t r = 0; r < layout[1]; ++r) {
                myl_block *child = reference_at(layout, element, r);
                if (child) retain_block(child);
            }
        }
    }
    return copy;
}

static void core_text_publish(myl_block *text);

static myl_block *str_from(const char *bytes, size_t len) {
    myl_block *text = block_new(MYL_KIND_STR, (int64_t)len, 1);
    memcpy(block_data(text), bytes, len);
    block_data(text)[len] = 0;
    text->len = (int64_t)len;
    core_text_publish(text);
    return text;
}

/* A box: an immutable block holding one value of `size` bytes at offset 32,
   which the emitted code stores right after this returns (`box_make`). */
myl_block *myl_core_box_new(int64_t size) {
    myl_block *box = block_new(MYL_KIND_BOX, size, 1);
    box->len = size;
    return box;
}

/* ---- one-count RC (docs/design/new-core-s1.md §6) ------------------------------
 * Retain and release are emitted inline: the count is a u32 at offset 0,
 * 0xFFFFFFFF is saturated (D4) and never changes. A release that drops the last
 * owner calls `myl_core_free` (emitted: a small block without children goes
 * straight back to its free list), else `myl_core_free_block`, which frees the block and releases the blocks its
 * elements hold, iteratively: a child whose last owner goes joins a pending
 * chain linked through its `cap` word (a dying block needs only `kind`, `len`
 * and `reserved`), so freeing a list of lists nested a million deep uses no
 * stack. The emitted release does not store the final 0, so a dying block is
 * recognized by the caller, never by its count. */
static void core_dict_free_pending(myl_block *dict, myl_block **pending);
static void core_io_finalize(myl_block *block);
static void core_text_walk_report(void);
static int64_t core_io_live_handles(void);

__attribute__((cold)) void myl_core_free_block(myl_block *block) {
    block->cap = 0;
    myl_block *pending = block;
    while (pending) {
        myl_block *dying = pending;
        pending = (myl_block *)(intptr_t)dying->cap;
        core_io_finalize(dying);
        myl_layout *layout = layout_of(dying);
        if (kind_of(dying) == MYL_KIND_DICT) {
            core_dict_free_pending(dying, &pending);
        } else if (layout && kind_of(dying) != MYL_KIND_STR && kind_of(dying) != MYL_KIND_BYTES) {
            int64_t count = element_count(dying);
            for (int64_t i = 0; i < count; ++i) {
                const unsigned char *element = block_data(dying) + i * (int64_t)layout[0];
                for (int32_t r = 0; r < layout[1]; ++r) {
                    myl_block *child = reference_at(layout, element, r);
                    if (count_release(child)) {
                        child->cap = (int64_t)(intptr_t)pending;
                        pending = child;
                    }
                }
            }
        }
        block_free(dying);
    }
}

/* Drop one owner of `block` out of line: the C entry's `args` and `main`'s error. */
void myl_core_release(myl_block *block) {
    if (count_release(block)) myl_core_free_block(block);
}

/* ---- error traces (ERROR-TRACE-1..5) -------------------------------------------
 * Called on Err paths only: mode 0 restarts the trace with `site` as its origin
 * (building an Err), mode 1 appends a site (a `?` that propagates one). Sites
 * point to immutable unit-local records whose operation names the action. The ring keeps the
 * last 32 appends (ERROR-TRACE-4); nothing is allocated. */
typedef struct {
    int32_t kind;
    int32_t line;
    int32_t column;
    int32_t width;
    const char *operation;
    const char *function;
    const char *path;
} myl_core_site;

/* The bit of an overflow, division or cast site's `width` that marks unsigned operands
   (`unsigned_site` in `emit_llvm.zig`). */
#define MYL_CORE_SITE_UNSIGNED 0x100


enum { TRACE_RING = 32 };
static MYL_TLS struct {
    const myl_core_site *origin;
    uint64_t count;
    const myl_core_site *ring[TRACE_RING];
} error_trace;

static inline void core_err_trace_record(const myl_core_site *site, int32_t mode) {
    if (mode == 0) {
        error_trace.origin = site;
        error_trace.count = 0;
        return;
    }
    error_trace.ring[error_trace.count++ % TRACE_RING] = site;
}

/* Ordinary C callers keep their ABI. Compiler-owned err_trace operations use
 * the register-preserving twin (ERROR-TRACE-6), with the same recording leaf. */
__attribute__((cold, noinline)) void myl_core_err_trace(const myl_core_site *site, int32_t mode) {
    core_err_trace_record(site, mode);
}

__attribute__((cold, noinline, preserve_most))
void myl_core_err_trace_origin_preserve_most(const myl_core_site *site) {
    core_err_trace_record(site, 0);
}

__attribute__((cold, noinline, preserve_most))
void myl_core_err_trace_append_preserve_most(const myl_core_site *site) {
    core_err_trace_record(site, 1);
}

/* `main`'s `args`: every command-line argument after the program name. */
/* The layout of a list whose elements are block pointers (`list[str]`). */
static const int32_t layout_blocks[] = {8, 1, 0, 0, 0};

static int core_io_utf8(const unsigned char *p, size_t n);
/* A guest argument that is not UTF-8 cannot become a `str`: refused before `main` runs,
   with the usage status, as the old core refuses it (ARGV-1). */
myl_block *myl_core_args(int32_t argc, char **argv) {
    for (int32_t i = 1; i < argc; ++i) {
        if (core_io_utf8((const unsigned char *)argv[i], strlen(argv[i]))) continue;
        static const char refused[] = "mylang: guest argument is not valid UTF-8\n";
        flush_all();
        os_write(2, (const unsigned char *)refused, sizeof refused - 1);
        os_exit(2);
    }
    int64_t count = argc > 1 ? argc - 1 : 0;
    myl_block *list = block_new(MYL_KIND_LIST, count, sizeof(void *));
    list->reserved = (int64_t)(intptr_t)layout_blocks;
    for (int64_t i = 0; i < count; ++i) ((myl_block **)block_data(list))[i] = str_from(argv[i + 1], strlen(argv[i + 1]));
    list->len = count;
    return list;
}

/* ---- traps and exit --------------------------------------------------------- */


enum { TRAP_OVERFLOW, TRAP_DIVISION_BY_ZERO, TRAP_LIST_BOUNDS, TRAP_FLOAT_CONVERSION, TRAP_CAST, TRAP_FACT, TRAP_LIST_EMPTY, TRAP_MISSING_KEY = 9, TRAP_ITERATION_MUTATION = 10, TRAP_TEXT_BOUNDS = 11, TRAP_TEXT_SEPARATOR = 12, TRAP_TEXT_STEP = 13, TRAP_BYTE_RANGE = 14, TRAP_TEXT_SCALAR = 15, TRAP_TEXT_SUBSTRING = 16, TRAP_INVALID_SHIFT = 17, TRAP_LIST_VALUE = 18, TRAP_LIST_POP_INDEX = 19 };



/* ---- trap frames (docs/design/new-core-s1.md §13 R-1) ----------------------------
 * A trap names the frame it happened in from the site table, then every caller:
 * the stack's return addresses, each mapped to the frames it stands for. A
 * `dwarf_lines` build carries DWARF 4 line tables and inline records (the
 * emitter's `!dbg`), read here from the executable file: per return address the
 * chain of subprogram and inlined-subroutine entries holding it gives one frame per
 * inlined call (§13 R-1 records why not labels after calls). */

typedef struct { const unsigned char *p, *end; } dw_cursor;

static uint64_t dw_fixed(dw_cursor *c, int n) {
    uint64_t v = 0;
    if (c->end - c->p < n) { c->p = c->end; return 0; }
    for (int i = 0; i < n; ++i) v |= (uint64_t)c->p[i] << (8 * i);
    c->p += n;
    return v;
}

static uint64_t dw_uleb(dw_cursor *c) {
    uint64_t v = 0;
    for (int shift = 0; c->p < c->end; shift += 7) {
        unsigned char byte = *c->p++;
        if (shift < 64) v |= (uint64_t)(byte & 0x7f) << shift;
        if (!(byte & 0x80)) break;
    }
    return v;
}

static int64_t dw_sleb(dw_cursor *c) {
    int64_t v = 0;
    int shift = 0;
    unsigned char byte = 0;
    while (c->p < c->end) {
        byte = *c->p++;
        if (shift < 64) v |= (int64_t)(byte & 0x7f) << shift;
        shift += 7;
        if (!(byte & 0x80)) break;
    }
    if (shift < 64 && (byte & 0x40)) v |= -((int64_t)1 << shift);
    return v;
}

static const char *dw_cstring(dw_cursor *c) {
    const char *text = (const char *)c->p;
    while (c->p < c->end && *c->p) ++c->p;
    if (c->p < c->end) ++c->p;
    return text;
}

typedef struct { const unsigned char *data; size_t size; } dw_section;

static struct {
    int state; /* 0 not loaded, 1 loaded, -1 unavailable */
    dw_section info, abbrev, line, str, ranges;
    intptr_t bias;
} dwarf;

extern const char __ehdr_start[] __attribute__((weak));

static void dwarf_load(void) {
    if (dwarf.state != 0) return;
    dwarf.state = -1;
    size_t size = 0;
    const unsigned char *file = os_map_self(&size);
    if (!file || size < sizeof(Elf64_Ehdr) || !__ehdr_start) return;
    const Elf64_Ehdr *header = (const Elf64_Ehdr *)file;
    if (header->e_shoff + (uint64_t)header->e_shnum * sizeof(Elf64_Shdr) > size || header->e_shstrndx >= header->e_shnum) return;
    const Elf64_Shdr *sections = (const Elf64_Shdr *)(file + header->e_shoff);
    const char *names = (const char *)file + sections[header->e_shstrndx].sh_offset;
    for (int i = 0; i < header->e_shnum; ++i) {
        const char *name = names + sections[i].sh_name;
        dw_section section = {file + sections[i].sh_offset, sections[i].sh_size};
        if (sections[i].sh_offset + sections[i].sh_size > size) continue;
        if (strcmp(name, ".debug_info") == 0) dwarf.info = section;
        else if (strcmp(name, ".debug_abbrev") == 0) dwarf.abbrev = section;
        else if (strcmp(name, ".debug_line") == 0) dwarf.line = section;
        else if (strcmp(name, ".debug_str") == 0) dwarf.str = section;
        else if (strcmp(name, ".debug_ranges") == 0) dwarf.ranges = section;
    }
    /* Run-time address = file address + bias (0 for a position-dependent executable). */
    const Elf64_Phdr *programs = (const Elf64_Phdr *)(file + header->e_phoff);
    for (int i = 0; i < header->e_phnum; ++i) {
        if (programs[i].p_type == PT_LOAD && programs[i].p_offset == 0) dwarf.bias = (intptr_t)__ehdr_start - (intptr_t)programs[i].p_vaddr;
    }
    if (dwarf.info.data && dwarf.abbrev.data && dwarf.line.data) dwarf.state = 1;
}

/* One debugging entry, with the attributes the frames need. */
typedef struct {
    uint64_t tag, low, high, ranges, origin, call_line, call_column, call_file, stmt_list;
    const char *name, *producer;
    bool children, has_low, high_offset, has_ranges, has_origin;
} dw_entry;

typedef struct { const unsigned char *unit, *abbrev; uint64_t base, stmt_list; int addr_size; } dw_unit;

static const unsigned char *dw_find_abbrev(const dw_unit *unit, uint64_t code) {
    dw_cursor c = {unit->abbrev, dwarf.abbrev.data + dwarf.abbrev.size};
    while (c.p < c.end) {
        uint64_t current = dw_uleb(&c);
        if (current == 0) return NULL;
        if (current == code) return c.p;
        dw_uleb(&c);
        ++c.p;
        for (;;) {
            uint64_t name = dw_uleb(&c), form = dw_uleb(&c);
            if (form == 0x21) dw_sleb(&c);
            if (name == 0 && form == 0) break;
        }
    }
    return NULL;
}

/* Read one attribute value of `form`; strings come back in `*text`. Returns false for a form it cannot size. */
static bool dw_value(dw_cursor *c, const dw_unit *unit, uint64_t form, uint64_t *value, const char **text) {
    *value = 0;
    switch (form) {
    case 0x01: *value = dw_fixed(c, unit->addr_size); return true;                       /* addr */
    case 0x0b: case 0x11: case 0x0c: *value = dw_fixed(c, 1); return true;                /* data1 ref1 flag */
    case 0x05: case 0x12: *value = dw_fixed(c, 2); return true;                           /* data2 ref2 */
    case 0x06: case 0x13: case 0x17: case 0x10: *value = dw_fixed(c, 4); return true;     /* data4 ref4 sec_offset ref_addr */
    case 0x07: case 0x14: case 0x20: *value = dw_fixed(c, 8); return true;                /* data8 ref8 ref_sig8 */
    case 0x0d: *value = (uint64_t)dw_sleb(c); return true;
    case 0x0f: case 0x15: *value = dw_uleb(c); return true;
    case 0x19: *value = 1; return true;                                                   /* flag_present */
    case 0x08: *text = dw_cstring(c); return true;                                        /* string */
    case 0x0e: {                                                                          /* strp */
        uint64_t at = dw_fixed(c, 4);
        if (dwarf.str.data && at < dwarf.str.size) *text = (const char *)dwarf.str.data + at;
        return true;
    }
    case 0x0a: c->p += dw_fixed(c, 1); return c->p <= c->end;                             /* block1 */
    case 0x03: c->p += dw_fixed(c, 2); return c->p <= c->end;                             /* block2 */
    case 0x04: c->p += dw_fixed(c, 4); return c->p <= c->end;                             /* block4 */
    case 0x09: case 0x18: { uint64_t n = dw_uleb(c); c->p += n; return c->p <= c->end; } /* block exprloc */
    default: return false;
    }
}

/* Parse the entry at `c` (which advances past it); false at a null entry or the end. */
static bool dw_read_entry(dw_cursor *c, const dw_unit *unit, dw_entry *entry, bool *null_entry) {
    *null_entry = false;
    memset(entry, 0, sizeof *entry);
    uint64_t code = dw_uleb(c);
    if (code == 0) { *null_entry = true; return c->p < c->end; }
    const unsigned char *spec = dw_find_abbrev(unit, code);
    if (!spec) return false;
    dw_cursor a = {spec, dwarf.abbrev.data + dwarf.abbrev.size};
    entry->tag = dw_uleb(&a);
    entry->children = *a.p++ != 0;
    for (;;) {
        uint64_t name = dw_uleb(&a), form = dw_uleb(&a);
        int64_t implicit = form == 0x21 ? dw_sleb(&a) : 0;
        if (name == 0 && form == 0) break;
        uint64_t value = (uint64_t)implicit;
        const char *text = NULL;
        if (form != 0x21 && !dw_value(c, unit, form, &value, &text)) return false;
        switch (name) {
        case 0x03: entry->name = text; break;                                             /* name */
        case 0x11: entry->low = value; entry->has_low = true; break;                      /* low_pc */
        case 0x12: entry->high = value; entry->high_offset = form != 0x01; break;         /* high_pc */
        case 0x55: entry->ranges = value; entry->has_ranges = true; break;                /* ranges */
        case 0x31: entry->origin = value; entry->has_origin = true; break;                /* abstract_origin */
        case 0x58: entry->call_file = value; break;                                       /* call_file */
        case 0x59: entry->call_line = value; break;                                       /* call_line */
        case 0x57: entry->call_column = value; break;                                     /* call_column */
        case 0x10: entry->stmt_list = value; break;                                       /* stmt_list */
        case 0x25: entry->producer = text; break;                                         /* producer */
        default: break;
        }
    }
    return true;
}

static bool dw_holds(const dw_unit *unit, const dw_entry *entry, uint64_t pc) {
    if (entry->has_low && !entry->has_ranges) {
        uint64_t high = entry->high_offset ? entry->low + entry->high : entry->high;
        return pc >= entry->low && pc < high;
    }
    if (!entry->has_ranges || !dwarf.ranges.data || entry->ranges >= dwarf.ranges.size) return false;
    dw_cursor c = {dwarf.ranges.data + entry->ranges, dwarf.ranges.data + dwarf.ranges.size};
    uint64_t base = unit->base;
    while (c.p < c.end) {
        uint64_t begin = dw_fixed(&c, unit->addr_size), end = dw_fixed(&c, unit->addr_size);
        if (begin == 0 && end == 0) break;
        if (begin == UINT64_MAX) { base = end; continue; }
        if (pc >= base + begin && pc < base + end) return true;
    }
    return false;
}

/* The name of an entry, through its abstract origin. */
static const char *dw_name(const dw_unit *unit, const dw_entry *entry) {
    dw_entry current = *entry;
    for (int hops = 0; hops < 4; ++hops) {
        if (current.name) return current.name;
        if (!current.has_origin) break;
        dw_cursor c = {unit->unit + current.origin, dwarf.info.data + dwarf.info.size};
        bool null_entry;
        if (!dw_read_entry(&c, unit, &current, &null_entry) || null_entry) break;
    }
    return "?";
}

/* The line and column the line program of `unit` gives `pc`; false when none covers it. */
static bool dw_line(const dw_unit *unit, uint64_t pc, uint64_t *line_out, uint64_t *column_out, uint64_t *file_out) {
    if (unit->stmt_list >= dwarf.line.size) return false;
    dw_cursor c = {dwarf.line.data + unit->stmt_list, dwarf.line.data + dwarf.line.size};
    uint64_t length = dw_fixed(&c, 4);
    const unsigned char *end = c.p + length;
    if (end > c.end) return false;
    c.end = end;
    uint64_t version = dw_fixed(&c, 2);
    if (version < 2 || version > 4) return false;
    uint64_t header_length = dw_fixed(&c, 4);
    const unsigned char *program = c.p + header_length;
    uint64_t min_length = dw_fixed(&c, 1);
    if (version >= 4) dw_fixed(&c, 1);
    dw_fixed(&c, 1);
    int line_base = (int8_t)dw_fixed(&c, 1);
    uint64_t line_range = dw_fixed(&c, 1);
    uint64_t opcode_base = dw_fixed(&c, 1);
    const unsigned char *lengths = c.p;
    if (line_range == 0 || program > end) return false;
    c.p = program;
    uint64_t address = 0, line = 1, column = 0, file = 1;
    bool found = false, have_previous = false;
    uint64_t previous_address = 0, previous_line = 0, previous_column = 0, previous_file = 1;
#define DW_ROW()                                                                                   \
    do {                                                                                           \
        if (have_previous && previous_address <= pc && pc < address) {                             \
            *line_out = previous_line; *column_out = previous_column; *file_out = previous_file; found = true;                \
        }                                                                                          \
        previous_address = address; previous_line = line; previous_column = column; previous_file = file; have_previous = true; \
    } while (0)
    while (c.p < c.end && !found) {
        uint64_t opcode = dw_fixed(&c, 1);
        if (opcode >= opcode_base) {
            uint64_t adjusted = opcode - opcode_base;
            address += (adjusted / line_range) * min_length;
            line += (uint64_t)(line_base + (int64_t)(adjusted % line_range));
            DW_ROW();
        } else if (opcode == 0) {
            uint64_t size = dw_uleb(&c);
            const unsigned char *next = c.p + size;
            uint64_t sub = dw_fixed(&c, 1);
            if (sub == 1) { /* end_sequence */
                DW_ROW();
                have_previous = false;
                address = 0; line = 1; column = 0; file = 1;
            } else if (sub == 2) address = dw_fixed(&c, (int)(size - 1));
            c.p = next;
        } else if (opcode == 1) DW_ROW();
        else if (opcode == 2) address += dw_uleb(&c) * min_length;
        else if (opcode == 3) line += (uint64_t)dw_sleb(&c);
        else if (opcode == 4) file = dw_uleb(&c);
        else if (opcode == 5) column = dw_uleb(&c);
        else if (opcode == 8) address += ((255 - opcode_base) / line_range) * min_length;
        else if (opcode == 9) address += dw_fixed(&c, 2);
        else for (uint64_t i = 0; i < lengths[opcode - 1]; ++i) dw_uleb(&c); /* file, negate_stmt, … */
    }
#undef DW_ROW
    return found;
}

enum { DW_MAX_DEPTH = 64 };

/* Resolve a DWARF 2–4 file-table index, including its directory. Our DIFile names
   are source paths; this also handles LLVM splitting a relative path into parts. */
static const char *dw_file(const dw_unit *unit, uint64_t index, char *out, size_t capacity) {
    if (unit->stmt_list >= dwarf.line.size) return "?";
    dw_cursor c = {dwarf.line.data + unit->stmt_list, dwarf.line.data + dwarf.line.size};
    dw_fixed(&c, 4);
    uint64_t version = dw_fixed(&c, 2);
    dw_fixed(&c, 4);
    dw_fixed(&c, 1);
    if (version >= 4) dw_fixed(&c, 1);
    dw_fixed(&c, 3);
    uint64_t opcodes = dw_fixed(&c, 1);
    if (opcodes == 0 || c.end - c.p < (ptrdiff_t)(opcodes - 1)) return "?";
    c.p += opcodes - 1;
    const unsigned char *directories = c.p;
    while (c.p < c.end && *c.p) dw_cstring(&c);
    if (c.p < c.end) ++c.p;
    for (uint64_t current = 1; c.p < c.end && *c.p; ++current) {
        const char *name = dw_cstring(&c);
        uint64_t directory = dw_uleb(&c);
        dw_uleb(&c); dw_uleb(&c);
        if (current != index) continue;
        if (directory == 0 || name[0] == '/') return name;
        dw_cursor dirs = {directories, c.end};
        const char *prefix = "";
        for (uint64_t i = 1; i <= directory && dirs.p < dirs.end && *dirs.p; ++i) prefix = dw_cstring(&dirs);
        snprintf(out, capacity, "%s/%s", prefix, name);
        return out;
    }
    return "?";
}

/* While set, frame lines are not written: the first one is kept here instead
   (`trap_caller`), so a report can name its caller before it lists its frames. */
static MYL_TLS char *trap_capture;
static MYL_TLS size_t trap_capture_size;
/* Frame lines a report may still print; negative: no limit. */
static MYL_TLS int trap_lines_left = -1;
static void trap_frame_line(const char *text, size_t length) {
    if (!trap_capture) {
        if (trap_lines_left == 0) return;
        if (trap_lines_left > 0) --trap_lines_left;
        stream_write(&streams[1], text, length);
        return;
    }
    if (trap_capture[0] || length >= trap_capture_size) return;
    memcpy(trap_capture, text, length);
    trap_capture[length] = 0;
}

/* The frames of return address `pc` (already less one, inside the call), innermost
   first, written as `  in f at path:line:column` lines; `skip` drops that many inner
   frames. Returns how many frames the address stands for (0: not this program's code). */
static int dwarf_frames(uint64_t pc, int skip) {
    dwarf_load();
    if (dwarf.state != 1) return 0;
    pc -= (uint64_t)dwarf.bias;
    dw_cursor units = {dwarf.info.data, dwarf.info.data + dwarf.info.size};
    while (units.p + 11 <= units.end) {
        const unsigned char *start = units.p;
        uint64_t length = dw_fixed(&units, 4);
        if (length >= 0xfffffff0 || units.p + length > units.end) return 0;
        const unsigned char *next = units.p + length;
        uint64_t version = dw_fixed(&units, 2);
        if (version != 4) { units.p = next; continue; }
        dw_unit unit = {start, dwarf.abbrev.data + dw_fixed(&units, 4), 0, 0, 0};
        unit.addr_size = (int)dw_fixed(&units, 1);
        dw_cursor c = {units.p, next};
        units.p = next;
        /* The compile unit: ours carries producer "mylang-core". */
        dw_entry cu;
        bool null_entry;
        if (!dw_read_entry(&c, &unit, &cu, &null_entry) || cu.tag != 0x11) continue;
        if (!cu.producer || strcmp(cu.producer, "mylang-core") != 0) continue;
        unit.stmt_list = cu.stmt_list;
        unit.base = cu.low;
        dw_entry chain[DW_MAX_DEPTH];
        bool holds[DW_MAX_DEPTH];
        int depth = 0, chain_length = 0;
        holds[0] = true;
        dw_entry entry;
        while (c.p < c.end && dw_read_entry(&c, &unit, &entry, &null_entry)) {
            if (null_entry) {
                if (depth == 0) break;
                --depth;
                continue;
            }
            bool inside = depth < DW_MAX_DEPTH - 1 && holds[depth] && (entry.tag == 0x2e || entry.tag == 0x1d) && dw_holds(&unit, &entry, pc);
            if (inside) {
                chain[depth] = entry;
                chain_length = depth + 1;
            }
            if (entry.children && depth < DW_MAX_DEPTH - 1) {
                ++depth;
                holds[depth] = inside;
            }
        }
        if (chain_length == 0) continue;
        /* chain[0..chain_length) from the subprogram inward; print innermost first. */
        uint64_t line = 0, column = 0, file = 1;
        dw_line(&unit, pc, &line, &column, &file);
        char text[1024], path[1024];
        int printed = 0;
        for (int k = chain_length - 1; k >= 0; --k, ++printed) {
            /* The C entry, into which `main` may be inlined, is no frame of the program. */
            if (strcmp(dw_name(&unit, &chain[k]), "myl.entry") == 0) break;
            if (printed < skip) {
                line = chain[k].call_line;
                column = chain[k].call_column;
                file = chain[k].call_file;
                continue;
            }
            int len = snprintf(text, sizeof text, "  in %s at %s:%llu:%llu\n", dw_name(&unit, &chain[k]), dw_file(&unit, file, path, sizeof path), (unsigned long long)line, (unsigned long long)column);
            trap_frame_line(text, (size_t)(len < (int)sizeof text ? len : (int)sizeof text - 1));
            line = chain[k].call_line;
            column = chain[k].call_column;
                file = chain[k].call_file;
        }
        return chain_length;
    }
    return 0;
}

/* Write the caller frames of a trap: every frame above the trapping function. */
__attribute__((noinline)) static void trap_frames(void) {
    void *pcs[128];
    int count = os_stack(pcs, 128);
    /* [0] here, [1] myl_core_trap, [2] the trapping function (named by its site), then its callers. */
    for (int i = 2; i < count; ++i) {
        if (dwarf_frames((uintptr_t)pcs[i] - 1, i == 2 ? 1 : 0) == 0) break;
    }
}


/* A trap lists at most its innermost sixteen frames, the site's own included, as the
   old core listed them; a test trial, which counts the frames it entered, then says
   how many deeper ones it left out (NEW-CORE-S5-TRACE-1). Set before a frame walk. */
enum { CORE_TRACE_FRAMES = 16 };
static uint64_t core_test_frames_live(void);
static void trap_omitted(void) {
    const uint64_t printed = (uint64_t)(CORE_TRACE_FRAMES - (trap_lines_left < 0 ? 0 : trap_lines_left));
    const uint64_t live = core_test_frames_live();
    trap_lines_left = -1;
    if (!core_trap_marks_all || live <= printed) return;
    char text[64];
    int length = snprintf(text, sizeof text, "  %llu frames omitted\n", (unsigned long long)(live - printed));
    stream_write(&streams[1], text, (size_t)length);
}

/* The version-1 operation marker, shared by plain traps and contract messages. */
static size_t core_operation_record(char *record, size_t capacity, const char *operation) {
    size_t used = (size_t)snprintf(record, capacity, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"");
    for (const unsigned char *byte = (const unsigned char *)operation; *byte && used + 8 < capacity; ++byte) {
        if (*byte == '"' || *byte == '\\') used += (size_t)snprintf(record + used, capacity - used, "\\%c", *byte);
        else if (*byte < 0x20) used += (size_t)snprintf(record + used, capacity - used, "\\u%04x", *byte);
        else record[used++] = (char)*byte;
    }
    used += (size_t)snprintf(record + used, capacity - used, "\"}\n");
    return used < capacity ? used : capacity - 1;
}

/* Report a failed check the way the old core does (code, detail, one `in f at …`
   line per frame and the `MYLANG-TRAP` record on stderr) and exit 1. The trapping
   frame comes from the site table, its callers from `trap_frames`. */
void myl_core_trap(const myl_core_site *site, int64_t a, int64_t b) {
    core_fatal_begin();
    char detail[256] = "";
    char record[256] = "";
    const char *code = "R_OVERFLOW";
    /* TRAP-UNSIGNED-1: an unsigned operation's operands print unsigned, and its record says so. */
    const int unsigned_operands = (site->width & MYL_CORE_SITE_UNSIGNED) != 0;
    const int width = site->width & ~MYL_CORE_SITE_UNSIGNED;
    switch (site->kind) {
    case TRAP_OVERFLOW:
        if (unsigned_operands) {
            snprintf(detail, sizeof detail, " (%s: left %llu, right %llu, width %d)", site->operation, (unsigned long long)a, (unsigned long long)b, width);
            snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"%s\",\"unsigned\":true,\"left\":%llu,\"right\":%llu,\"width\":%d}\n", site->operation, (unsigned long long)a, (unsigned long long)b, width);
            break;
        }
        snprintf(detail, sizeof detail, " (%s: left %lld, right %lld, width %d)", site->operation, (long long)a, (long long)b, width);
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"%s\",\"left\":%lld,\"right\":%lld,\"width\":%d}\n", site->operation, (long long)a, (long long)b, width);
        break;
    case TRAP_DIVISION_BY_ZERO:
        code = "R_DIVISION_BY_ZERO";
        if (unsigned_operands) {
            snprintf(detail, sizeof detail, " (%s: left %llu, right %llu)", site->operation, (unsigned long long)a, (unsigned long long)b);
            snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"%s\",\"unsigned\":true,\"left\":%llu,\"right\":%llu}\n", site->operation, (unsigned long long)a, (unsigned long long)b);
            break;
        }
        snprintf(detail, sizeof detail, " (%s: left %lld, right %lld)", site->operation, (long long)a, (long long)b);
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"%s\",\"left\":%lld,\"right\":%lld}\n", site->operation, (long long)a, (long long)b);
        break;
    case TRAP_TEXT_BOUNDS:
    case TRAP_LIST_BOUNDS:
        code = site->kind == TRAP_TEXT_BOUNDS ? "R_TEXT_BOUNDS" : "R_LIST_BOUNDS";
        snprintf(detail, sizeof detail, " (index %lld, length %lld)", (long long)a, (long long)b);
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"index\",\"index\":%lld,\"length\":%lld}\n", (long long)a, (long long)b);
        break;
    case TRAP_LIST_EMPTY:
        /* A pop of an empty list: the old core's code and `pop` detail (PY-COLLECTIONS-20). */
        code = "R_LIST_BOUNDS";
        snprintf(detail, sizeof detail, " (length %lld)", (long long)b);
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"pop\",\"length\":%lld}\n", (long long)b);
        break;
    case TRAP_LIST_POP_INDEX:
        /* myl_qbe_fail_pop_at_bounds: an indexed pop retains its pop operation. */
        code = "R_LIST_BOUNDS";
        snprintf(detail, sizeof detail, " (index %lld, length %lld)", (long long)a, (long long)b);
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"pop\",\"index\":%lld,\"length\":%lld}\n", (long long)a, (long long)b);
        break;
    case TRAP_LIST_VALUE: code = "R_LIST_VALUE"; break;
    case TRAP_ITERATION_MUTATION:
        code = "R_LIST_ITERATION_MUTATION";
        break;
    case TRAP_MISSING_KEY:
        code = "R_MISSING_KEY";
        break;
    case TRAP_FLOAT_CONVERSION:
        code = "R_FLOAT_CONVERSION";
        break;
    case TRAP_TEXT_SEPARATOR: code = "R_EMPTY_SEPARATOR"; break;
    case TRAP_TEXT_STEP: code = "R_SLICE_STEP"; break;
    case TRAP_BYTE_RANGE: code = "R_BYTE_RANGE"; break;
    case TRAP_TEXT_SCALAR: code = "R_TEXT_SCALAR"; break;
    case TRAP_TEXT_SUBSTRING: code = "R_SUBSTRING_NOT_FOUND"; break;
    case TRAP_INVALID_SHIFT: code = "R_INVALID_SHIFT"; break;
    case TRAP_FACT:
        /* Verify builds only: a fact the compiler relied on does not hold. */
        code = "R_CORE_FACT";
        snprintf(detail, sizeof detail, " (%s: value %lld, other %lld)", site->operation, (long long)a, (long long)b);
        break;
    default:
        if (unsigned_operands) {
            snprintf(detail, sizeof detail, " (cast: left %llu, width %d)", (unsigned long long)a, width);
            snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"cast\",\"unsigned\":true,\"left\":%llu,\"width\":%d}\n", (unsigned long long)a, width);
            break;
        }
        snprintf(detail, sizeof detail, " (cast: left %lld, width %d)", (long long)a, width);
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"cast\",\"left\":%lld,\"width\":%d}\n", (long long)a, width);
        break;
    }
    /* A program's trap without operands has no record, as in the old core; a test trial
       still marks every trap with one, which is how its runner tells a trap apart. */
    if (record[0] == 0 && site->kind != TRAP_FACT && core_trap_marks_all) core_operation_record(record, sizeof record, site->operation);
    stream_flush(&streams[0]);
    char text[1024];
    int len = snprintf(text, sizeof text, "%s:%d:%d: error[%s]: native execution failed%s\n  in %s at %s:%d:%d\n",
        site->path, site->line, site->column, code, detail, site->function, site->path, site->line, site->column);
    stream_write(&streams[1], text, (size_t)(len < (int)sizeof text ? len : (int)sizeof text - 1));
    trap_lines_left = CORE_TRACE_FRAMES - 1;
    trap_frames();
    trap_omitted();
    stream_write(&streams[1], record, strlen(record));
    flush_all();
    os_exit(1);
}

/* R5: resolve captured return PCs through the ordinary guest DWARF lookup.
   The raw fallback cannot enter shared debug-section initialization. */
static const char *core_task_location(uintptr_t pc, char *text, size_t capacity) {
    if (!pc || core_fatal_raw) return "<unknown>";
    text[0] = 0;
    trap_capture = text;
    trap_capture_size = capacity;
    (void)dwarf_frames(pc - 1, 0);
    trap_capture = NULL;
    char *where = strstr(text, " at ");
    if (!where) return "<unknown>";
    char *newline = strchr(where, '\n');
    if (newline) *newline = 0;
    return where + 4;
}

static void core_task_report(void) {
    if (!core_running_task.submit) return;
    char submit[1024], group[1024], text[2304];
    const char *site = core_task_location(core_running_task.submit, submit, sizeof submit);
    int length;
    if (core_running_task.item < 0) length = snprintf(text, sizeof text, "in task submitted at %s\n", site);
    else if (!strcmp(site, "<unknown>")) length = snprintf(text, sizeof text, "in task submitted at <unknown> (item %lld)\n", (long long)core_running_task.item);
    else length = snprintf(text, sizeof text, "in parallel.map item %lld at %s\n", (long long)core_running_task.item, site);
    os_write(2, (const unsigned char *)text, (size_t)length);
    if (core_running_task.group) {
        site = core_task_location(core_running_task.group, group, sizeof group);
        length = snprintf(text, sizeof text, "  group opened at %s\n", site);
        os_write(2, (const unsigned char *)text, (size_t)length);
    }
}

/* The old core's description of a budget's trap, with its advice (docs/tooling/runtime-budgets.md). */
static const char *core_budget_hint(const char *code){
    if(!strcmp(code,"R_STEP_LIMIT"))return "instruction budget exhausted; raise it with --max-steps=N";
    if(!strcmp(code,"R_FRAME_LIMIT"))return "call-depth budget exhausted; raise it with --max-frames=N (each frame reserves 32 KiB of stack, so --max-memory must cover N x 32 KiB)";
    if(!strcmp(code,"R_MEMORY_BUDGET"))return "memory budget exhausted; raise it with --max-memory=SIZE";
    return NULL;
}
static MYL_TLS const myl_core_site *core_io_site;
void myl_core_io_at(const myl_core_site *site){core_io_site=site;}
/* Runtime effects keep their checked call site; walk past C adapters before
   printing the guest callers, just as a generated trap keeps its site frame. */
__attribute__((cold,noinline)) static void core_io_failure(const char *code){
    core_fatal_begin();
    stream_flush(&streams[0]);char text[1024];int length;
    /* A budget's trap is described as the old core describes it (BUDGET-HINT-1). It
       names no site: a budget is charged anywhere, and the last I/O site may be stale,
       so its frames start at the innermost program frame (NEW-CORE-S5-TRACE-1). */
    const char *hint=core_budget_hint(code),*described=hint?hint:"native execution failed";
    const myl_core_site *site=hint?NULL:core_io_site;
    if(site)length=snprintf(text,sizeof text,"%s:%d:%d: error[%s]: %s\n  in %s at %s:%d:%d\n",site->path,site->line,site->column,code,described,site->function,site->path,site->line,site->column);
    else length=snprintf(text,sizeof text,"error[%s]: %s\n",code,described);
    stream_write(&streams[1],text,(size_t)(length<(int)sizeof text?length:(int)sizeof text-1));
    trap_lines_left=site?CORE_TRACE_FRAMES-1:CORE_TRACE_FRAMES;
    void *pcs[128];int count=os_stack(pcs,128),found=0;
    /* A frame budget traps on entering a frame it cannot hold: the frames start at the call. */
    const bool skip=site||!strcmp(code,"R_FRAME_LIMIT");
    for(int i=2;i<count;++i){int frames=dwarf_frames((uintptr_t)pcs[i]-1,found||!skip?0:1);if(frames)found=1;else if(found)break;}
    trap_omitted();
    /* A test trial's trap is told apart from a crash by its record. */
    const bool trapped=!strncmp(code,"R_",2);
    if(trapped&&core_trap_marks_all){char record[512];size_t used=core_operation_record(record,sizeof record,described);stream_write(&streams[1],record,used);}
    flush_all();os_exit(trapped?1:2);
}

/* With MYL_CORE_LEAKCHECK=1, a program that ends with blocks still allocated says
   how many on stderr (the exit status is unchanged). Every path that returns from
   `main` releases what it owns, so a nonzero count is an ownership bug; a trap
   runs no releases (RC-TRAP-TEARDOWN-1) and is not checked. */
static void leak_report(void) {
    const char *flag = getenv("MYL_CORE_LEAKCHECK");
    if (!flag || strcmp(flag, "1") != 0) return;
    int64_t handles = core_io_live_handles();
    if (handles) {
        char message[96];
        int width = snprintf(message, sizeof message, "myl-core leakcheck: %lld handles live at exit\n", (long long)handles);
        os_write(2, (const unsigned char *)message, (size_t)width);
    }
    int64_t live = live_count();
    if (live == 0) return;
    char text[96];
    int len = snprintf(text, sizeof text, "myl-core leakcheck: %lld blocks live at exit\n", (long long)live);
    os_write(2, (const unsigned char *)text, (size_t)len);
}

/* Whether `MYLANG_OPTIONS` names `--print-result`, bare or quoted, as `mylang run
   --print-result` sets it (NEW-CORE-S5-RUN-1). Reads the variable only at exit. */
static bool print_result_requested(void) {
    const char *text = getenv("MYLANG_OPTIONS");
    static const char wanted[] = "--print-result";
    while (text && *text) {
        while (*text == ' ' || *text == '\t' || *text == '\n' || *text == '\r') ++text;
        const char *start = text;
        while (*text && *text != ' ' && *text != '\t' && *text != '\n' && *text != '\r') ++text;
        size_t length = (size_t)(text - start);
        if (length >= 2 && start[0] == '"' && start[length - 1] == '"') { ++start; length -= 2; }
        if (length == sizeof wanted - 1 && !memcmp(start, wanted, length)) return true;
    }
    return false;
}

/* `main`'s result is the exit status, truncated to the low 8 bits; `--print-result`
   also prints the whole value on its own line. */
int32_t myl_core_exit(int64_t status) {
    if (print_result_requested()) {
        char line[32];
        int length = snprintf(line, sizeof line, "%lld\n", (long long)status);
        stream_write(&streams[0], line, (size_t)length);
    }
    flush_all();
    leak_report();
    core_text_walk_report();
    core_io_cleanup();
    return (int32_t)(status & 0xFF);
}

/* ---- `main` returning Err (RESULT-MAIN-1/2, ERROR-TRACE-2) ---------------------- */

static int trace_where(const myl_core_site *site, char *out, size_t size) {
    return snprintf(out, size, "%s:%d:%d", site->path, site->line, site->column);
}

/* A `returned` site on the line of the site before it, in the same function, is folded into it. */
static bool trace_folds(const myl_core_site *previous, const myl_core_site *site) {
    return strcmp(site->operation, "returned") == 0 && strcmp(previous->function, site->function) == 0 && previous->line == site->line && strcmp(previous->path, site->path) == 0;
}

/* The trace, origin first: one `  path:line:column  function  action` line per
   site with the columns aligned, and a `... N more entries dropped ...` line
   where the ring overwrote appends. */
static void trace_write(void) {
    const myl_core_site *listed[1 + TRACE_RING];
    size_t count = 0, gap = 0;
    if (error_trace.origin) listed[count++] = error_trace.origin;
    gap = count;
    uint64_t kept = error_trace.count < TRACE_RING ? error_trace.count : TRACE_RING;
    uint64_t dropped = error_trace.count - kept;
    for (uint64_t i = error_trace.count - kept; i < error_trace.count; ++i) {
        const myl_core_site *site = error_trace.ring[i % TRACE_RING];
        if (count && trace_folds(listed[count - 1], site)) continue;
        listed[count++] = site;
    }
    int width = 0, name_width = 0;
    char where[1024];
    for (size_t i = 0; i < count; ++i) {
        int len = trace_where(listed[i], where, sizeof where);
        int name = (int)strlen(listed[i]->function);
        if (len > width) width = len;
        if (name > name_width) name_width = name;
    }
    char line[2048];
    for (size_t i = 0; i <= count; ++i) {
        if (i == gap && dropped) {
            int len = snprintf(line, sizeof line, "  ... %llu more %s dropped ...\n", (unsigned long long)dropped, dropped == 1 ? "entry" : "entries");
            stream_write(&streams[1], line, (size_t)len);
        }
        if (i == count) break;
        trace_where(listed[i], where, sizeof where);
        int len = snprintf(line, sizeof line, "  %-*s  %-*s  %s\n", width, where, name_width, listed[i]->function, listed[i]->operation);
        stream_write(&streams[1], line, (size_t)(len < (int)sizeof line ? len : (int)sizeof line - 1));
    }
}

static void error_begin(void) {
    stream_flush(&streams[0]);
    stream_write(&streams[1], "error: ", 7);
}

static void error_end(void) {
    stream_write(&streams[1], "\n", 1);
    trace_write();
    stream_flush(&streams[1]);
}

/* `main` returned `Err(value)`: `error: VALUE` and the trace on stderr. */
void myl_core_main_error_i64(int64_t value) {
    error_begin();
    myl_core_print_i64(2, value);
    error_end();
}

void myl_core_main_error_u64(uint64_t value) {
    error_begin();
    myl_core_print_u64(2, value);
    error_end();
}

void myl_core_main_error_bool(bool value) {
    error_begin();
    myl_core_print_bool(2, value);
    error_end();
}

void myl_core_main_error_str(myl_block *text) {
    error_begin();
    myl_core_print_str(2, text);
    error_end();
}

/* ---- lane V helpers (checkpoint V-2) ---------------------------------------------
 * Appended for the builder's `assert`, `str ==`, `len(str)` and the text builders; the rest of the file is lane O's. */


/* `str(b)` of a boolean: `True` or `False`. */
myl_block *myl_core_str_from_bool(bool value) {
    return value ? str_from("True", 4) : str_from("False", 5);
}

bool myl_core_str_eq(const myl_block *, const myl_block *);

/* ---- sort: a stable merge sort over the element kinds ----
 * `list.sort()` and `sorted(list)` give a new list (the caller's value is replaced, as every
 * update is a value) holding the elements in the order the language documents: integers by
 * value, `float` with every NaN after every ordered value and the signed zeros tied, text by
 * Unicode scalar value (UTF-8 byte order). Equal elements keep their order, so the result is the
 * one the old core's merge sort (src/native_collections.c) gives. Insertion-sorted blocks of 16,
 * then bottom-up merges through one scratch buffer. */
#define SORT_BLOCK 16
#define DEFINE_SORT(NAME, T, LESS) \
static void NAME(T *a, T *scratch, size_t n) { \
    for (size_t lo = 0; lo < n; lo += SORT_BLOCK) { \
        size_t hi = lo + SORT_BLOCK < n ? lo + SORT_BLOCK : n; \
        for (size_t i = lo + 1; i < hi; ++i) { \
            T v = a[i]; \
            size_t j = i; \
            while (j > lo && LESS(v, a[j - 1])) { a[j] = a[j - 1]; --j; } \
            a[j] = v; \
        } \
    } \
    T *from = a, *to = scratch; \
    for (size_t width = SORT_BLOCK; width < n; width *= 2) { \
        for (size_t lo = 0; lo < n; lo += 2 * width) { \
            size_t mid = lo + width < n ? lo + width : n; \
            size_t hi = lo + 2 * width < n ? lo + 2 * width : n; \
            size_t i = lo, j = mid, k = lo; \
            while (i < mid && j < hi) to[k++] = LESS(from[j], from[i]) ? from[j++] : from[i++]; \
            while (i < mid) to[k++] = from[i++]; \
            while (j < hi) to[k++] = from[j++]; \
        } \
        T *swap = from; from = to; to = swap; \
    } \
    if (from != a) memcpy(a, from, n * sizeof(T)); \
}
#define SORT_LT(x, y) ((x) < (y))
#define SORT_FLOAT_LT(x, y) ((x) < (y) || ((y) != (y) && (x) == (x)))
static bool sort_text_lt(const myl_block *x, const myl_block *y) {
    int64_t common = x->len < y->len ? x->len : y->len;
    int order = memcmp((const unsigned char *)x + MYL_HEADER, (const unsigned char *)y + MYL_HEADER, (size_t)common);
    return order != 0 ? order < 0 : x->len < y->len;
}
#define SORT_TEXT_LT(x, y) sort_text_lt((x), (y))
DEFINE_SORT(sort_i8, int8_t, SORT_LT)
DEFINE_SORT(sort_i16, int16_t, SORT_LT)
DEFINE_SORT(sort_i32, int32_t, SORT_LT)
DEFINE_SORT(sort_i64, int64_t, SORT_LT)
DEFINE_SORT(sort_u8, uint8_t, SORT_LT)
DEFINE_SORT(sort_u16, uint16_t, SORT_LT)
DEFINE_SORT(sort_u32, uint32_t, SORT_LT)
DEFINE_SORT(sort_u64, uint64_t, SORT_LT)
DEFINE_SORT(sort_f64, double, SORT_FLOAT_LT)
typedef myl_block *text_ptr;
DEFINE_SORT(sort_text, text_ptr, SORT_TEXT_LT)

/* A sorted copy of `list`. `kind` is the element kind (0 signed integer, 1 unsigned integer or
   bool, 2 `float`, 3 text) with the element size in bytes above its low byte. */
myl_block *myl_core_list_sort(myl_block *list, int64_t kind) {
    int64_t size = kind >> 8;
    myl_block *sorted = myl_core_list_copy(list, size);
    size_t n = (size_t)sorted->len;
    if (n < 2) return sorted;
    void *scratch = malloc(n * (size_t)size);
    if (!scratch) out_of_memory();
    void *data = block_data(sorted);
    switch (kind & 0xff) {
    case 0:
        switch (size) {
        case 1: sort_i8(data, scratch, n); break;
        case 2: sort_i16(data, scratch, n); break;
        case 4: sort_i32(data, scratch, n); break;
        default: sort_i64(data, scratch, n); break;
        }
        break;
    case 1:
        switch (size) {
        case 1: sort_u8(data, scratch, n); break;
        case 2: sort_u16(data, scratch, n); break;
        case 4: sort_u32(data, scratch, n); break;
        default: sort_u64(data, scratch, n); break;
        }
        break;
    case 2: sort_f64(data, scratch, n); break;
    default: sort_text(data, scratch, n); break;
    }
    free(scratch);
    return sorted;
}

/* A failed `assert`, `@requires`, `@ensures` or `@invariant`: the old core's report. The site's
   `width` is the clause kind (0 `assert` .. 3 `invariant`) and its `operation` the message; the
   first line, the `in f at` frames and the `MYLANG-TRAP` record are those of any trap, the record
   carrying only the message. Exit status 1. */
void myl_core_assert_fail(const myl_core_site *site) {
    core_fatal_begin();
    static const char *const codes[] = {"R_ASSERT", "R_REQUIRES", "R_ENSURES", "R_INVARIANT"};
    /* The old core's description of each (NEW-CORE-S5-CONTRACT-1). */
    static const char *const described[] = {"native execution failed", "precondition violated", "postcondition violated", "invariant violated"};
    const int kind = site->width >= 0 && site->width < 4 ? site->width : 0;
    const char *code = codes[kind];
    stream_flush(&streams[0]);
    /* A broken precondition is its caller's fault: name the next frame out (CONTRACT-REQUIRES-1). */
    char caller[1024] = "";
    if (kind == 1) {
        trap_capture = caller;
        trap_capture_size = sizeof caller;
        trap_frames();
        trap_capture = NULL;
    }
    char blame[1100] = "";
    size_t named = strlen(caller);
    if (named > 6 && caller[named - 1] == '\n') snprintf(blame, sizeof blame, "; broken by the caller %.*s", (int)(named - 6), caller + 5);
    char text[3200];
    int len = snprintf(text, sizeof text, "%s:%d:%d: error[%s]: %s%s%s%s\n  in %s at %s:%d:%d\n",
        site->path, site->line, site->column, code, described[kind], site->operation[0] ? ": " : "", site->operation, blame,
        site->function, site->path, site->line, site->column);
    stream_write(&streams[1], text, (size_t)(len < (int)sizeof text ? len : (int)sizeof text - 1));
    trap_lines_left = CORE_TRACE_FRAMES - 1;
    trap_frames();
    trap_omitted();
    /* The record: {"version":1,"operation":"MESSAGE"} with the message JSON-escaped. */
    char record[2048];
    size_t used = core_operation_record(record, sizeof record, site->operation);
    stream_write(&streams[1], record, used);
    flush_all();
    os_exit(1);
}
