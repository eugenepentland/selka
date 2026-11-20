/* The bare runtime on a CPU with two cores (MCU-CORE1; docs/tooling/native-build.md, "The second core").
 *
 * `registers.start_core1(reg, entry)` starts the second core (an RP2040's core 1) running `entry`, a top-level
 * `func(Registers) -> int`, beside `main`. The two cores share no heap value, and each keeps the runtime's state for
 * itself:
 *  - each core allocates and frees in its own arena (core_bare_heap.c), chosen by the core's number, which the platform's
 *    register answers (the RP2040's SIO CPUID);
 *  - the runtime's per-thread state (`MYL_TLS`: the free lists, the chunk being carved, a trap's detail) and the state the
 *    hosted runtime shares between threads (`SELKA_CORE_LOCAL`: the live-block count, the byte ceiling, the output
 *    buffers) are thread-local variables compiled with emulated TLS (-femulated-tls, the program's units too): each
 *    access asks `__emutls_get_address` below, which answers the calling core's copy, made in that core's arena the
 *    first time the core touches the variable;
 *  - the platform's log write is serialised with a hardware spinlock (`myl_bare_log_write`), and each line core 1
 *    writes begins "core 1: ";
 *  - the end of the program runs once (`myl_bare_finish`): `main` returning, a trap or a fault on either core ends the
 *    program on both and calls the platform's `myl_bare_exit` once; a core that arrives second waits to be stopped.
 * Core 1's memory is half of the largest free block of core 0's arena at the call: its stack (BARE_CORE1_STACK) at the
 * top and its arena below. When `entry` returns, core 1 writes its report ("core 1: returned N, live blocks ..."), checks
 * its stack and waits; a trap on core 1 writes its lines (each beginning "core 1: ") and ends the program.
 *
 * A platform with two cores supplies the hooks below (bringup/selka-ram/platform.c in selka-rp); the weak defaults
 * describe one core, so on QEMU's platform `start_core1` answers False and the locks do nothing.
 *
 * The entry is called through a C function pointer: the compiler's internal functions use LLVM's `fastcc`, which on an
 * AAPCS target without VFP registers (thumbv6m-none-eabi, the only bare target) is the AAPCS convention itself.
 *
 * Only the two-core flavour of the runtime has this file's code (-DMYL_BARE_CORES): the driver chooses it for a program
 * that calls `registers.start_core1` (`driver.bareCores`), so an image that never starts the second core pays nothing
 * for it, neither the emulated TLS nor the second arena nor the locked log. */
#if defined(MYL_BARE_CORES)

/* ---- the platform's hooks for a second core (weak defaults: one core) ---- */

/* The address of a register that reads the calling core's number (0 or 1), or NULL on a platform with one core. */
__attribute__((weak)) const volatile uint32_t *myl_bare_core_register(void) { return NULL; }

/* Start core 1 with its vector table, stack and entry (the RP2040's launch sequence over the SIO FIFO, datasheet
   2.8.2); false when it cannot be started. */
__attribute__((weak)) bool myl_bare_core1_launch(const void *vectors, void *stack_top, void (*entry)(void)) {
    (void)vectors; (void)stack_top; (void)entry;
    return false;
}

/* Stop core `core` where it is (the RP2040's platform holds core 1 in reset through its power-on state machine, and
   leaves core 0 to the reset of its exit). */
__attribute__((weak)) void myl_bare_core_stop(unsigned core) { (void)core; }

/* Take and give back the runtime's lock `lock` (0: the log, 1: the runtime's own state), a hardware spinlock. */
__attribute__((weak)) void myl_bare_lock(unsigned lock) { (void)lock; }
__attribute__((weak)) void myl_bare_unlock(unsigned lock) { (void)lock; }

enum { BARE_LOCK_LOG = 0, BARE_LOCK_RUNTIME = 1 };

/* ---- which core runs ---- */

static const uint32_t bare_core_zero;
static const volatile uint32_t *bare_core_at = &bare_core_zero;

static unsigned bare_core(void) { return *bare_core_at & 1u; }

/* At reset, after the platform's start: where the core's number is read. */
static void bare_cores_start(void) {
    const volatile uint32_t *at = myl_bare_core_register();
    if (at) bare_core_at = at;
}

static void bare_barrier(void) { __asm__ volatile("dmb" ::: "memory"); }

/* A core with nothing left to do: the other core ends the program, or has stopped this one. */
__attribute__((noreturn)) static void bare_park(void) {
    for (;;) __asm__ volatile("wfi");
}

/* ---- the log, one core at a time ---- */

/* The core holding the log lock (-1: none) and how many times it took it: a trap while the core writes takes it again. */
static volatile int bare_log_owner = -1;
static unsigned bare_log_depth;
static bool bare_core1_mid_line;

static void bare_log_lock(void) {
    const int core = (int)bare_core();
    if (bare_log_owner == core) { ++bare_log_depth; return; }
    myl_bare_lock(BARE_LOCK_LOG);
    bare_log_owner = core;
    bare_log_depth = 1;
}

static void bare_log_unlock(void) {
    if (--bare_log_depth) return;
    bare_log_owner = -1;
    bare_barrier();
    myl_bare_unlock(BARE_LOCK_LOG);
}

/* Write to the platform's log, one core at a time; every line core 1 writes begins "core 1: ". */
void myl_bare_log_write(int stream, const unsigned char *bytes, size_t length) {
    bare_log_lock();
    if (bare_core() == 0) {
        myl_bare_write(stream, bytes, length);
    } else {
        size_t from = 0;
        for (size_t i = 0; i < length; ++i) {
            if (!bare_core1_mid_line) {
                myl_bare_write(stream, (const unsigned char *)"core 1: ", 8);
                bare_core1_mid_line = true;
            }
            if (bytes[i] != '\n') continue;
            myl_bare_write(stream, bytes + from, i + 1 - from);
            from = i + 1;
            bare_core1_mid_line = false;
        }
        if (from < length) myl_bare_write(stream, bytes + from, length - from);
    }
    bare_log_unlock();
}

static void bare_log_text(const char *text) { myl_bare_log_write(2, (const unsigned char *)text, strlen(text)); }

/* ---- the end of the program, once ---- */

enum { BARE_CORE1_IDLE, BARE_CORE1_RUNNING, BARE_CORE1_STOPPED };
static volatile int bare_core1_state;
static volatile bool bare_finishing;

/* Stop core 1 if it runs (from core 0): between its log writes and outside the runtime's lock, so it holds neither. */
static void bare_core1_stop(void) {
    myl_bare_lock(BARE_LOCK_RUNTIME);
    if (bare_core1_state == BARE_CORE1_RUNNING) {
        bare_log_lock();
        myl_bare_core_stop(1);
        bare_core1_state = BARE_CORE1_STOPPED;
        bare_log_unlock();
    }
    myl_bare_unlock(BARE_LOCK_RUNTIME);
}

/* The end of the program, from `main`'s return, `exit`, or a trap or a fault on either core: the first core to arrive
   stops the other and calls the platform's exit; a core that arrives second waits to be stopped. Core 0 stops core 1
   where it is. Core 1 asks the platform to stop core 0 (the RP2040's platform does not: a core 0 held in reset would
   stay so through the reset into the bootloader) and keeps the log: core 0 writes nothing more, and runs at most until
   the platform's exit resets the chip. */
__attribute__((noreturn)) void myl_bare_finish(int status) {
    myl_bare_lock(BARE_LOCK_RUNTIME);
    const bool first = !bare_finishing;
    bare_finishing = true;
    myl_bare_unlock(BARE_LOCK_RUNTIME);
    if (!first) bare_park();
    if (bare_core() == 0) {
        bare_core1_stop();
    } else {
        bare_log_lock();
        bare_log_text("the program ends here\n");
        myl_bare_core_stop(0);
    }
    myl_bare_exit(status);
}

/* A failure where the runtime's own state cannot be used (it is what failed): the line, then the end. */
__attribute__((noreturn, cold, noinline)) static void bare_halt(const char *line) {
    bare_log_text(line);
    myl_bare_finish(1);
}

/* ---- a once both cores may reach ---- */

/* 0: not run; 1: running on one core; 2: done. A core that finds it running waits for 2. */
void myl_bare_once(int *once, void (*run)(void)) {
    volatile int *state = once;
    if (*state == 2) return;
    myl_bare_lock(BARE_LOCK_RUNTIME);
    const int found = *state;
    if (!found) *state = 1;
    myl_bare_unlock(BARE_LOCK_RUNTIME);
    if (!found) {
        run();
        bare_barrier();
        *state = 2;
        return;
    }
    while (*state != 2) {}
    bare_barrier();
}

/* ---- each core's copy of the runtime's state: emulated TLS ---- */

/* LLVM's control record of one thread-local variable (`__emutls_v.NAME`): its size, alignment, a word the runtime keeps
   (here the variable's pair of copies, one per core) and its initial value (NULL: zeros). */
typedef struct {
    size_t size, align;
    void **copies;
    const void *value;
} bare_tls_control;

/* One pair for each thread-local variable of the runtime and the program; the runtime has about 40. */
enum { BARE_TLS_VARIABLES = 96 };
static void *bare_tls_pairs[BARE_TLS_VARIABLES][BARE_CORES];
static unsigned bare_tls_used;

/* ---- each core's arena ---- */

/* What core 0 hands core 1: written before the launch, read by core 1 only. */
static struct {
    int64_t (*entry)(int64_t);
    int64_t reg;
    uintptr_t low, stack_low, top;
} bare_core1;

static uint64_t bare_arena_bytes[BARE_CORES];

/* Make core `core`'s arena if it is not made yet: core 0's is the image's heap, core 1's the memory below its stack. */
static void bare_arena_ready(unsigned core) {
    bare_arena *arena = &bare_arenas[core];
    if (arena->first) return;
    bare_arena_bytes[core] = core ? bare_arena_init(arena, bare_core1.low, bare_core1.stack_low)
                                  : bare_arena_init(arena, (uintptr_t)__heap_start, (uintptr_t)__heap_end);
}

/* A core's heap before its program runs: its arena, whose size is the core's byte ceiling, so running out is
   `R_MEMORY_BUDGET`. A thread-local variable's address may be asked for before any statement of the function that uses
   it (the compiler treats it as a constant of the thread), so the first touch makes the arena too (`bare_tls_make`), and
   this function is kept apart from its caller. */
__attribute__((noinline)) static void bare_heap_ready(unsigned core) {
    bare_arena_ready(core);
    heap_ceiling = bare_arena_bytes[core];
}

/* The calling core's first touch of a variable: its copy, made in the core's own arena from the initial value. */
__attribute__((cold, noinline)) static void *bare_tls_make(bare_tls_control *control, unsigned core) {
    bare_arena_ready(core);
    myl_bare_lock(BARE_LOCK_RUNTIME);
    void **copies = control->copies;
    if (!copies && bare_tls_used < BARE_TLS_VARIABLES) copies = control->copies = bare_tls_pairs[bare_tls_used++];
    myl_bare_unlock(BARE_LOCK_RUNTIME);
    if (!copies) bare_halt("error[R_ABORT]: the runtime has room for 96 thread-local variables\n");
    void *copy = control->align <= BARE_UNIT ? bare_arena_alloc(bare_arena_here(), control->size) : NULL;
    if (!copy) bare_halt("error[R_MEMORY_BUDGET]: no memory for the runtime's state of a core\n");
    if (control->value) memcpy(copy, control->value, control->size);
    else memset(copy, 0, control->size);
    copies[core] = copy;
    return copy;
}

/* The calling core's copy of the thread-local variable `control` describes (every access of one calls this). */
void *__emutls_get_address(bare_tls_control *control) {
    const unsigned core = bare_core();
    void **copies = control->copies;
    if (__builtin_expect(copies != NULL, 1)) {
        void *copy = copies[core];
        if (__builtin_expect(copy != NULL, 1)) return copy;
    }
    return bare_tls_make(control, core);
}

/* ---- core 1 ---- */

enum { BARE_CORE1_STACK = 8 * 1024, BARE_CORE1_LEAST_HEAP = 8 * 1024 };

/* Core 1's start (its stack pointer at `bare_core1.top`): its stack painted, its arena made, `entry`, then its report. */
__attribute__((noreturn)) static void bare_core1_main(void) {
    const bare_stack stack = { (uint32_t *)bare_core1.stack_low, (uint32_t *)bare_core1.top };
    bare_paint_stack(stack);
    bare_heap_ready(1);
    const int64_t status = bare_core1.entry(bare_core1.reg);
    flush_all();
    bare_core_report("returned ", (int)status, stack);
    bare_park();
}

/* Core 0's byte ceiling less what it gave core 1 (apart, as `bare_heap_ready` is). */
__attribute__((noinline)) static void bare_heap_less(uint32_t bytes) { heap_ceiling -= bytes; }

/* `registers.start_core1(reg, entry)`: true when core 1 now runs `entry`; false on a platform with one core, when core
   1 was started already, when this is core 1, when core 0's arena has too little room, or when the launch failed. */
bool myl_core_registers_start_core1(int64_t reg, int64_t (*entry)(int64_t)) {
    if (bare_core_at == &bare_core_zero || bare_core() != 0 || bare_core1_state != BARE_CORE1_IDLE) return false;
    const uint32_t half = bare_arena_largest(&bare_arenas[0]) / 2 / BARE_UNIT * BARE_UNIT;
    if (half < BARE_CORE1_STACK + BARE_CORE1_LEAST_HEAP + 2 * BARE_UNIT) return false;
    unsigned char *region = bare_arena_alloc(&bare_arenas[0], half - BARE_HEAD);
    if (!region) return false;
    bare_core1.entry = entry;
    bare_core1.reg = reg;
    bare_core1.low = (uintptr_t)region;
    bare_core1.top = ((uintptr_t)region + bare_usable(region)) & ~(uintptr_t)7;
    bare_core1.stack_low = bare_core1.top - BARE_CORE1_STACK;
    extern const void *const myl_bare_vectors[];
    /* Running before the launch: a trap on core 1 at once must find it so, and stop nothing that is not there. */
    bare_core1_state = BARE_CORE1_RUNNING;
    bare_barrier();
    if (!myl_bare_core1_launch(myl_bare_vectors, (void *)bare_core1.top, bare_core1_main)) {
        bare_core1_state = BARE_CORE1_IDLE;
        bare_arena_free(&bare_arenas[0], region);
        return false;
    }
    bare_heap_less(half);
    return true;
}
#endif /* MYL_BARE_CORES */
