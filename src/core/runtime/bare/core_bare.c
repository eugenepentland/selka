/* The runtime on a CPU with no operating system (-DMYL_BARE): the layer under the kept files.
 *
 * The bare runtime is one translation unit, as the hosted one is: core_rt.c, core_dict.c, core_unicode_data.h,
 * core_text.c, core_sort.c, core_number.c, core_sha256.c, core_bytes.c, core_values.c, core_owned_copy.c, then this
 * file, compiled with -DMYL_BARE and -Isrc/core/runtime/bare/include (myl_bare_libc.h: the C library they see).
 * This file is last, so it can define the statics the kept files declare and the left-out files (core_io.c,
 * core_tasks.c, core_test.c, ...) would have defined, and call the kept files' statics.
 *
 * What it gives:
 *  - memory: one heap between the linker symbols __heap_start and __heap_end. Every block is a multiple of 32 bytes
 *    with an 8-byte header {size of the block before, size | used} and 32-byte-aligned data; free blocks are on one
 *    first-fit list and a freed block merges with free neighbours. The runtime's small classes still carve their
 *    (4 KiB) chunks from it. The heap's size is the runtime's byte ceiling, so running out is `R_MEMORY_BUDGET`;
 *  - the C library the kept files call and the compiler runtime does not supply (memchr, memmem, strcmp, strstr, a
 *    small snprintf, abort into the trap path, getenv with one variable);
 *  - the hooks of the left-out files: tasks run inline, there is no I/O state to finalize, no frame counter;
 *  - the reset path: stack, data, zeroed data, vector table, heap, `main`, the exit report, the exit hook;
 *  - the two hooks a platform supplies, `myl_bare_write` and `myl_bare_exit`, with weak defaults.
 */

/* ---- the platform's hooks: weak defaults (a platform file links strong ones) ---- */

__attribute__((weak)) void myl_bare_write(int stream, const unsigned char *bytes, size_t length) {
    (void)stream; (void)bytes; (void)length;
}
__attribute__((weak, noreturn)) void myl_bare_exit(int status) {
    (void)status;
    for (;;) __asm__ volatile("wfi");
}

/* Called once at reset, after the data and zeroed data are in place and before the heap and `main` (a board arms its
   watchdog and opens its log here). */
__attribute__((weak)) void myl_bare_platform_start(void) {}

/* Each core's own with two cores (SELKA_CORE_LOCAL, core_rt.c). */
SELKA_CORE_LOCAL int myl_bare_errno;

#if defined(MYL_BARE_CORES)
/* core_bare_cores.c: the end of the program, once, whichever core ends it; the cores' start at reset; core 1 stopped. */
__attribute__((noreturn)) void myl_bare_finish(int status);
static void bare_cores_start(void);
static void bare_core1_stop(void);
static void bare_heap_ready(unsigned core);

/* ---- the heap: the C library's allocation in the calling core's arena (core_bare_heap.c) ---- */

extern unsigned char __heap_start[], __heap_end[];

void *malloc(size_t bytes) { return bare_arena_alloc(bare_arena_here(), bytes); }

#else
/* ---- the heap ---- */

extern unsigned char __heap_start[], __heap_end[];
typedef struct bare_chunk {
    uint32_t before;              /* size of the block just below this one (0: the first block) */
    uint32_t size;                /* this block's size in bytes, a multiple of 32; bit 0: in use */
    struct bare_chunk *next, *prev; /* free blocks only: the free list, in the first data bytes */
} bare_chunk;
enum { BARE_UNIT = 32, BARE_HEAD = 8, BARE_USED = 1 };
static bare_chunk *bare_first, *bare_end, *bare_free;
static uintptr_t bare_heap_base, bare_heap_top;

static uint32_t bare_size(const bare_chunk *c) { return c->size & ~(uint32_t)BARE_USED; }
static bare_chunk *bare_after(bare_chunk *c) { return (bare_chunk *)((unsigned char *)c + bare_size(c)); }
static void *bare_data(bare_chunk *c) { return (unsigned char *)c + BARE_HEAD; }
static bare_chunk *bare_chunk_of(void *data) { return (bare_chunk *)((unsigned char *)data - BARE_HEAD); }

static void bare_unlink(bare_chunk *c) {
    if (c->prev) c->prev->next = c->next; else bare_free = c->next;
    if (c->next) c->next->prev = c->prev;
}
static void bare_push(bare_chunk *c) {
    c->size &= ~(uint32_t)BARE_USED;
    c->prev = NULL;
    c->next = bare_free;
    if (bare_free) bare_free->prev = c;
    bare_free = c;
}

/* Data at a 32-byte boundary: a block starts 8 bytes before one, and every size is a multiple of 32. The top block
   (`bare_end`) is a used block of size 0 that ends every merge. */
static void bare_heap_init(void) {
    uintptr_t low = ((uintptr_t)__heap_start + BARE_HEAD + BARE_UNIT - 1) / BARE_UNIT * BARE_UNIT - BARE_HEAD;
    uintptr_t high = ((uintptr_t)__heap_end - BARE_HEAD) / BARE_UNIT * BARE_UNIT - BARE_HEAD;
    bare_first = (bare_chunk *)low;
    bare_end = (bare_chunk *)high;
    bare_first->before = 0;
    bare_first->size = (uint32_t)(high - low);
    bare_end->before = bare_first->size;
    bare_end->size = BARE_USED;
    bare_free = NULL;
    bare_push(bare_first);
    bare_heap_base = bare_heap_top = low;
    heap_ceiling = high - low;
}

/* Split `c` (in use) to `need` bytes when the rest makes a block, and free the rest. */
static void bare_trim(bare_chunk *c, uint32_t need) {
    uint32_t size = bare_size(c);
    if (size - need < BARE_UNIT) return;
    bare_chunk *rest = (bare_chunk *)((unsigned char *)c + need);
    rest->before = need;
    rest->size = size - need;
    bare_after(rest)->before = rest->size;
    c->size = need | BARE_USED;
    bare_push(rest);
}

static uint32_t bare_need(size_t bytes) {
    if (bytes > (size_t)((uintptr_t)bare_end - (uintptr_t)bare_first)) return 0;
    uint32_t need = (uint32_t)((bytes + BARE_HEAD + BARE_UNIT - 1) / BARE_UNIT * BARE_UNIT);
    return need < BARE_UNIT ? BARE_UNIT : need;
}

static void bare_mark_top(bare_chunk *c) {
    uintptr_t top = (uintptr_t)c + bare_size(c);
    if (top > bare_heap_top) bare_heap_top = top;
}

void *malloc(size_t bytes) {
    uint32_t need = bare_need(bytes);
    if (!need) return NULL;
    for (bare_chunk *c = bare_free; c; c = c->next) {
        if (bare_size(c) < need) continue;
        bare_unlink(c);
        c->size |= BARE_USED;
        bare_trim(c, need);
        bare_mark_top(c);
        return bare_data(c);
    }
    return NULL;
}

#endif

void *aligned_alloc(size_t alignment, size_t bytes) { return alignment <= BARE_UNIT ? malloc(bytes) : NULL; }

void *calloc(size_t count, size_t size) {
    if (size && count > SIZE_MAX / size) return NULL;
    void *data = malloc(count * size);
    if (data) memset(data, 0, count * size);
    return data;
}

#if defined(MYL_BARE_CORES)
/* A block freed on the core that did not allocate it: the cores share no heap value, so this is a runtime defect. */
void free(void *data) {
    if (!bare_arena_free(bare_arena_here(), data)) abort();
}

size_t malloc_usable_size(void *data) { return bare_usable(data); }

void *realloc(void *data, size_t bytes) {
    if (data && !bare_arena_holds(bare_arena_here(), data)) abort();
    return bare_arena_realloc(bare_arena_here(), data, bytes);
}
#else
void free(void *data) {
    if (!data) return;
    bare_chunk *c = bare_chunk_of(data);
    c->size &= ~(uint32_t)BARE_USED;
    bare_chunk *next = bare_after(c);
    if (!(next->size & BARE_USED)) {
        bare_unlink(next);
        c->size += next->size;
    }
    if (c != bare_first) {
        bare_chunk *below = (bare_chunk *)((unsigned char *)c - c->before);
        if (!(below->size & BARE_USED)) {
            bare_unlink(below);
            below->size += c->size;
            c = below;
        }
    }
    bare_after(c)->before = c->size;
    bare_push(c);
}

size_t malloc_usable_size(void *data) { return data ? bare_size(bare_chunk_of(data)) - BARE_HEAD : 0; }

void *realloc(void *data, size_t bytes) {
    if (!data) return malloc(bytes);
    uint32_t need = bare_need(bytes);
    if (!need) return NULL;
    bare_chunk *c = bare_chunk_of(data);
    bare_chunk *next = bare_after(c);
    if (bare_size(c) < need && !(next->size & BARE_USED) && bare_size(c) + next->size >= need) {
        bare_unlink(next);
        c->size += next->size;
        bare_after(c)->before = bare_size(c);
    }
    if (bare_size(c) >= need) {
        bare_trim(c, need);
        bare_mark_top(c);
        return data;
    }
    void *moved = malloc(bytes);
    if (!moved) return NULL;
    memcpy(moved, data, bare_size(c) - BARE_HEAD);
    free(data);
    return moved;
}
#endif

/* ---- the C library ---- */

void *memchr(const void *bytes, int value, size_t length) {
    const unsigned char *at = bytes;
    for (size_t i = 0; i < length; ++i)
        if (at[i] == (unsigned char)value) return (void *)(at + i);
    return NULL;
}

void *memmem(const void *haystack, size_t haystack_length, const void *needle, size_t needle_length) {
    if (!needle_length) return (void *)haystack;
    const unsigned char *h = haystack, *n = needle;
    for (size_t i = 0; i + needle_length <= haystack_length; ++i)
        if (h[i] == n[0] && !memcmp(h + i, n, needle_length)) return (void *)(h + i);
    return NULL;
}

int strcmp(const char *left, const char *right) {
    while (*left && *left == *right) { ++left; ++right; }
    return (unsigned char)*left - (unsigned char)*right;
}

int strncmp(const char *left, const char *right, size_t length) {
    for (size_t i = 0; i < length; ++i) {
        if (left[i] != right[i] || !left[i]) return (unsigned char)left[i] - (unsigned char)right[i];
    }
    return 0;
}

char *strchr(const char *text, int value) {
    for (;; ++text) {
        if (*text == (char)value) return (char *)text;
        if (!*text) return NULL;
    }
}

char *strstr(const char *haystack, const char *needle) {
    return memmem(haystack, strlen(haystack), needle, strlen(needle));
}

char *strpbrk(const char *text, const char *accept) {
    for (; *text; ++text)
        if (strchr(accept, *text)) return (char *)text;
    return NULL;
}

/* SELKA_CORE_LEAKCHECK is always on: the exit path counts live blocks. */
char *getenv(const char *name) { return strcmp(name, "SELKA_CORE_LEAKCHECK") ? NULL : (char *)"1"; }

double strtod(const char *text, char **end) {
    if (end) *end = (char *)text;
    return 0.0;
}

/* snprintf for what the kept files format: %d %i %u %x %X %c %s %p %% with flags '-' and '0', a width, a precision
   ('.N', '.*') and the lengths hh h l ll z j t. A float conversion writes "<float>" (no float text on a bare CPU). */
typedef struct { char *out; size_t room, used; } bare_sink;
static void bare_put(bare_sink *sink, char c) {
    if (sink->used + 1 < sink->room) sink->out[sink->used] = c;
    sink->used++;
}
static void bare_put_padded(bare_sink *sink, const char *text, size_t length, int width, bool left, char pad) {
    size_t fill = width > 0 && (size_t)width > length ? (size_t)width - length : 0;
    if (!left && pad == '0' && length && (*text == '-' || *text == '+')) { bare_put(sink, *text++); --length; }
    if (!left) while (fill--) bare_put(sink, pad);
    for (size_t i = 0; i < length; ++i) bare_put(sink, text[i]);
    if (left) while (fill--) bare_put(sink, ' ');
}

int vsnprintf(char *out, size_t room, const char *format, va_list arguments) {
    bare_sink sink = {out, room, 0};
    for (const char *f = format; *f; ++f) {
        if (*f != '%') { bare_put(&sink, *f); continue; }
        ++f;
        bool left = false;
        char pad = ' ';
        for (;; ++f) {
            if (*f == '-') left = true;
            else if (*f == '0') pad = '0';
            else if (*f != '+' && *f != ' ' && *f != '#') break;
        }
        int width = 0, precision = -1;
        if (*f == '*') { width = va_arg(arguments, int); ++f; }
        while (*f >= '0' && *f <= '9') width = width * 10 + (*f++ - '0');
        if (*f == '.') {
            ++f;
            precision = 0;
            if (*f == '*') { precision = va_arg(arguments, int); ++f; }
            while (*f >= '0' && *f <= '9') precision = precision * 10 + (*f++ - '0');
        }
        int longs = 0;
        bool word = false;
        for (;; ++f) {
            if (*f == 'l') ++longs;
            else if (*f == 'z' || *f == 't') word = true;
            else if (*f == 'j') longs = 2;
            else if (*f != 'h') break;
        }
        char digits[24];
        size_t n = 0;
        switch (*f) {
        case 'd': case 'i': case 'u': case 'x': case 'X': case 'p': {
            const bool is_signed = *f == 'd' || *f == 'i';
            uint64_t magnitude;
            bool negative = false;
            if (*f == 'p') magnitude = (uintptr_t)va_arg(arguments, void *);
            else if (longs >= 2) {
                uint64_t raw = va_arg(arguments, uint64_t);
                negative = is_signed && (int64_t)raw < 0;
                magnitude = negative ? 0 - raw : raw;
            } else {
                uint32_t raw = word || longs ? (uint32_t)va_arg(arguments, size_t) : va_arg(arguments, unsigned);
                negative = is_signed && (int32_t)raw < 0;
                magnitude = negative ? (uint64_t)(0 - raw) : raw;
            }
            const unsigned base = *f == 'x' || *f == 'X' || *f == 'p' ? 16 : 10;
            const char *alphabet = *f == 'X' ? "0123456789ABCDEF" : "0123456789abcdef";
            char reversed[24];
            size_t count = 0;
            do { reversed[count++] = alphabet[magnitude % base]; magnitude /= base; } while (magnitude);
            while (precision > 0 && count < (size_t)precision && count < sizeof reversed) reversed[count++] = '0';
            if (negative) digits[n++] = '-';
            while (count) digits[n++] = reversed[--count];
            bare_put_padded(&sink, digits, n, width, left, precision >= 0 ? ' ' : pad);
            break;
        }
        case 'c':
            digits[0] = (char)va_arg(arguments, int);
            bare_put_padded(&sink, digits, 1, width, left, ' ');
            break;
        case 's': {
            const char *text = va_arg(arguments, const char *);
            if (!text) text = "(null)";
            size_t length = 0;
            while ((precision < 0 || length < (size_t)precision) && text[length]) ++length;
            bare_put_padded(&sink, text, length, width, left, ' ');
            break;
        }
        case 'e': case 'f': case 'g': case 'E': case 'G':
            (void)va_arg(arguments, double);
            bare_put_padded(&sink, "<float>", 7, width, left, ' ');
            break;
        case '%': bare_put(&sink, '%'); break;
        default: if (!*f) --f; break;
        }
    }
    if (room) out[sink.used < room ? sink.used : room - 1] = 0;
    return (int)sink.used;
}

int snprintf(char *out, size_t room, const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(out, room, format, arguments);
    va_end(arguments);
    return length;
}

int fprintf(FILE *stream, const char *format, ...) {
    char text[256];
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(text, sizeof text, format, arguments);
    va_end(arguments);
    myl_bare_log_write((int)(uintptr_t)stream, (const unsigned char *)text, length < (int)sizeof text ? (size_t)length : sizeof text - 1);
    return length;
}

/* A runtime operation that cannot work on a bare CPU (float text, format specifications, BLAKE3: they come from a
   prebuilt x86 object on Linux) ends here: `error[R_BARE_UNSUPPORTED]: NAME is not available on a bare CPU`. */
__attribute__((noreturn, cold)) void myl_bare_unsupported(const char *name) {
#if defined(MYL_BARE_TERSE)
    (void)name;
#else
    static SELKA_CORE_LOCAL char text[128];
    snprintf(text, sizeof text, "%s is not available on a bare CPU", name);
    core_failure_detail = text;
#endif
    core_io_failure("R_BARE_UNSUPPORTED");
    for (;;) {}
}

/* An internal check of the runtime failed (hosted: SIGABRT). Through the trap path, status 1. */
__attribute__((noreturn)) void abort(void) {
    core_failure_detail = "runtime check failed (abort)";
    core_io_failure("R_ABORT");
    for (;;) {}
}

__attribute__((noreturn)) void exit(int status) {
    flush_all();
    myl_bare_finish(status);
}

/* ---- what the left-out files define ---- */

static void core_io_cleanup(void) {}
static void core_host_cleanup(void) {}
static void core_io_finalize(myl_block *block) { (void)block; }
static void core_task_finalize(myl_block *block) { (void)block; }
static void core_tasks_quiesce(void) {}
static int64_t core_io_live_handles(void) { return 0; }
static uint64_t core_test_frames_live(void) { return 0; }
static void core_thread_start_failure(void) { core_io_failure("R_THREAD_START"); }
/* Arguments are never given on a bare CPU (`main(0, NULL)`), so none is checked. */
static int core_io_utf8(const unsigned char *p, size_t n) { (void)p; (void)n; return 1; }
void myl_core_start(void) {}
/* `main(host: Host)` on a device (MCU-EXT): the token core_io.c's grant answers, given unconditionally (a device has no
   command line to say `--allow-host`); an `extern func` call checks it first, as on Linux, then calls the C symbol. */
int64_t myl_core_host_grant(void) { return -6; }
void myl_core_host_check(int64_t token) { if (token != -6) core_io_failure("R_CAPABILITY"); }
/* `main(host: Host?)`: always `Some`, the one family a device grants this way (the build refuses every other one,
   E_TARGET_CAPABILITY, and the check refuses `Registers?`, E_MAIN). */
int64_t myl_core_cap_offer(uint32_t family) { return family == 6 ? myl_core_host_grant() : 0; }
/* `debug(...)` in a plain build writes its line here (core_io.c's definition is left out): forwarded to the platform's
   write hook (with two cores through the serialised log write, so their lines do not interleave). Weak, so a platform
   file that still defines it (as the board's did before MCU-EXT) links, and its own definition wins. */
__attribute__((weak)) void myl_core_span_stream_write(int64_t fd, const unsigned char *data, uint64_t length) {
    myl_bare_log_write((int)fd, data, (size_t)length);
}
/* parallel.map runs its items inline (one CPU); the item number is kept for a trap's task report, as core_tasks.c does. */
void myl_core_task_item(int64_t item) { core_running_task.item = item; }
/* The compiler's thunk that runs a task's (or a map chunk's) function on its environment. */
extern myl_block *myl_core_task_call(void *run, myl_block *env);
/* A group (`parallel.group`, and the one a map opens for its loans) on one CPU: a one-element list whose element is
   the list of its tasks' results by submit index, made at the first submit. Both use `layout_blocks`, so the group's
   drop frees every result no `result()` took. A task runs when it is submitted (core_tasks.c with one thread). */
myl_block *myl_core_group_open(void) {
    myl_block *group = myl_core_list_new_slow(1, sizeof(myl_block *));
    group->reserved = (int64_t)(intptr_t)layout_blocks;
    ((myl_block **)block_data(group))[0] = NULL;
    group->len = 1;
    return group;
}
void myl_core_owned_group_end(myl_block *group) { myl_core_drop_owned(group); }
/* E1b (lowered submit): the environment's references are all owned; the result is the task's index in the group. */
int64_t myl_core_owned_task_submit_indexed(myl_block *group, void *run, myl_block *env, int64_t item) {
    core_task_context saved = core_running_task;
    __typeof__(error_trace) saved_trace = error_trace;
    core_running_task.item = item;
    error_trace.origin = NULL;
    error_trace.count = 0;
    myl_block *result = myl_core_task_call(run, env);
    myl_core_drop_owned(env);
    core_running_task = saved;
    error_trace = saved_trace;
    myl_block **slot = (myl_block **)block_data(group);
    if (!*slot) {
        *slot = myl_core_list_new_slow(2, sizeof(myl_block *));
        (*slot)->reserved = (int64_t)(intptr_t)layout_blocks;
    }
    if ((*slot)->len == (*slot)->cap) *slot = myl_core_list_grow(*slot, sizeof(myl_block *));
    ((myl_block **)block_data(*slot))[(*slot)->len++] = result;
    return (*slot)->len - 1;
}
/* `handle.result()`: the result of the task at `index`, taken once; its slot reads NULL after. */
myl_block *myl_core_owned_group_take(myl_block *group, int64_t index) {
    myl_block *results = ((myl_block **)block_data(group))[0];
    if (!results || index < 0 || index >= results->len) core_io_failure("R_TASK_GROUP");
    myl_block *result = ((myl_block **)block_data(results))[index];
    if (!result) core_io_failure("R_TASK_GROUP");
    ((myl_block **)block_data(results))[index] = NULL;
    return result;
}
/* parallel.map (core_tasks.c's myl_core_owned_map with one thread): one chunk of every item, run here. The chunk's
   environment is a copy of the capture with its start and count; it owns nothing, so its drop frees only itself. */
myl_block *myl_core_owned_map(myl_block *capture, uint64_t capture_size, uint64_t length, void *run,
        uint64_t start_offset, uint64_t count_offset, myl_block *out, uint64_t output_size) {
    if (!length) return out;
    const int64_t start = 0, count = (int64_t)length;
    myl_block *env = block_new(MYL_KIND_BYTES, (int64_t)capture_size, 1);
    env->len = (int64_t)capture_size;
    memcpy(block_data(env), block_data(capture), capture_size);
    memcpy(block_data(env) + start_offset, &start, sizeof start);
    memcpy(block_data(env) + count_offset, &count, sizeof count);
    myl_block *result = myl_core_task_call(run, env);
    myl_core_drop_owned(env);
    memcpy(block_data(out) + (size_t)out->len * output_size, block_data(result), (size_t)result->len * output_size);
    out->len += result->len;
    block_free(result);
    return out;
}

/* ---- the sorts ---- */

/* core_sort.c's paths are tuned for speed on a desktop (16 KB of code for the in-place sort alone). Here every sort is one
 * stable merge sort of positions under one comparison, then the elements move into that order: the in-place sort compares
 * the elements as a one-field key, a keyed sort its key rows field by field. A stable sort's result is fixed by its order,
 * and the order is core_sort.c's: integers by value; binary64 values with signed zeros tied and every NaN after every
 * ordered value (all NaNs tied); text and bytes by their octets; `reverse` swaps the two sides of each comparison, so it
 * is the descending order with ties still in input order. Running out of memory for the positions is `R_SORT_FAILED`. */
typedef struct {
    const unsigned char *rows; /* the elements (in place) or the key rows (keyed), position i at rows + i * stride */
    size_t stride;
    unsigned reverse;
    const s2_key_shape *shape;
} bare_sort_by;

/* One numeric field as a word whose unsigned order is the field's order (core_sort.c's s2_key_word, the binary64 case on
   the bits, so no floating-point code is linked). */
static uint64_t bare_sort_word(const unsigned char *at, unsigned kind, unsigned size) {
    uint64_t word = 0;
    memcpy(&word, at, size);
    const uint64_t sign = UINT64_C(1) << 63;
    if (kind == KEY_FLOAT) {
        if ((word & ~sign) > UINT64_C(0x7ff0000000000000)) return UINT64_MAX;
        if ((word & ~sign) == 0) word = 0;
        return word >> 63 ? ~word : word | sign;
    }
    if (kind == KEY_SIGNED && size < 8 && (word >> (8 * size - 1)) & 1) word |= UINT64_MAX << (8 * size);
    return kind == KEY_SIGNED ? word ^ sign : word;
}

static int bare_sort_less(const bare_sort_by *by, uint32_t left, uint32_t right) {
    if (by->reverse) { uint32_t held = left; left = right; right = held; }
    const unsigned char *a = by->rows + (size_t)left * by->stride, *b = by->rows + (size_t)right * by->stride;
    for (size_t field = 0; field < by->shape->count; field++) {
        const unsigned kind = s2_key_kind(by->shape, field), size = s2_key_size(by->shape, field);
        const size_t offset = s2_key_offset(by->shape, field);
        int order;
        if (kind >= KEY_TEXT) {
            myl_block *x, *y;
            memcpy(&x, a + offset, sizeof x);
            memcpy(&y, b + offset, sizeof y);
            order = s2_sort_block_compare(x, y);
        } else {
            const uint64_t x = bare_sort_word(a + offset, kind, size), y = bare_sort_word(b + offset, kind, size);
            order = x < y ? -1 : x > y;
        }
        if (order) return order < 0;
    }
    return 0;
}

/* The positions 0 .. count-1 in sorted order (count >= 2): merges of runs of 1, 2, 4, ... between two halves of one
   allocation, the left position on a tie. The caller frees it. */
static uint32_t *bare_sort_order(size_t count, const bare_sort_by *by) {
    uint32_t *order = count <= UINT32_MAX / 8 ? malloc(2 * count * sizeof *order) : NULL;
    if (!order) S2_SORT_FAILED();
    uint32_t *from = order, *to = order + count;
    for (size_t i = 0; i < count; i++) from[i] = (uint32_t)i;
    for (size_t width = 1; width < count; width *= 2) {
        for (size_t start = 0; start < count; start += 2 * width) {
            const size_t middle = count - start < width ? count : start + width;
            const size_t end = count - middle < width ? count : middle + width;
            size_t a = start, b = middle;
            for (size_t out = start; out < end; out++)
                to[out] = b < end && (a == middle || bare_sort_less(by, from[b], from[a])) ? from[b++] : from[a++];
        }
        uint32_t *held = from; from = to; to = held;
    }
    if (from != order) memcpy(order, from, count * sizeof *order);
    return order;
}

/* Slot i receives the element at order[i], following each cycle once through one element-sized temporary. */
static void bare_sort_permute(unsigned char *base, size_t size, uint32_t *order, size_t count) {
    unsigned char inline_held[32];
    unsigned char *held = size <= sizeof inline_held ? inline_held : malloc(size);
    if (!held) S2_SORT_FAILED();
    for (size_t i = 0; i < count; i++) {
        size_t j = i;
        if (order[i] == i) continue;
        memcpy(held, base + i * size, size);
        for (;;) {
            size_t k = order[j];
            order[j] = (uint32_t)j;
            if (k == i) break;
            memcpy(base + j * size, base + k * size, size);
            j = k;
        }
        memcpy(base + j * size, held, size);
    }
    if (held != inline_held) free(held);
}

/* The sorted order of a keyed sort's positions, or NULL when there are fewer than two. */
static uint32_t *bare_sort_keyed_order(size_t count, myl_block *keys, uint64_t shape, uint64_t offsets, bool reverse, size_t key_size) {
    s2_key_shape decoded;
    if (!keys || (size_t)keys->len != count || !s2_key_shape_decode(shape, offsets, key_size, &decoded)) S2_SORT_FAILED();
    if (count < 2) return NULL;
    bare_sort_by by = { block_data(keys), key_size, reverse, &decoded };
    return bare_sort_order(count, &by);
}

/* Consumes the unique list chosen by own.zig. The order code's low byte is the element's kind (0 signed, 1 unsigned, 2
   binary64, 3 text, 4 bytes, the key kinds' numbering; any other is unsigned) and the rest its width. */
myl_block *myl_core_s2_sort_in_place(myl_block *list, uint64_t code, bool reverse) {
    const size_t count = (size_t)list->len;
    const unsigned order = (unsigned)(code & 255);
    if (count < 2) return list;
    s2_key_shape shape = { .count = 1, .descriptor = NULL };
    shape.kind[0] = (unsigned char)(order <= KEY_BYTES ? order : KEY_UNSIGNED);
    shape.size[0] = (unsigned char)(order >= KEY_TEXT && order <= KEY_BYTES ? sizeof(myl_block *) : order == KEY_FLOAT ? 8 : code >> 8);
    bare_sort_by by = { block_data(list), shape.size[0], reverse, &shape };
    uint32_t *sorted = bare_sort_order(count, &by);
    bare_sort_permute(block_data(list), shape.size[0], sorted, count);
    free(sorted);
    return list;
}

/* Borrow source and keys, return one sorted owning copy, gathered from source in order. */
myl_block *myl_core_s2_sort_keyed(myl_block *source, myl_block *keys, uint64_t shape, uint64_t offsets, bool reverse, uint64_t strides) {
    const size_t size = (size_t)(strides & UINT32_MAX), count = (size_t)source->len;
    myl_block *values = myl_core_list_copy(source, (int64_t)size);
    uint32_t *sorted = bare_sort_keyed_order(count, keys, shape, offsets, reverse, (size_t)(strides >> 32));
    if (!sorted) return values;
    for (size_t i = 0; i < count; i++) memcpy(block_data(values) + i * size, block_data(source) + (size_t)sorted[i] * size, size);
    free(sorted);
    return values;
}

/* Both arguments are compiler-created owners: the values are sorted in place and the keys dropped. */
myl_block *myl_core_owned_sort_keyed(myl_block *values, myl_block *keys, uint64_t shape, uint64_t offsets, bool reverse, uint64_t strides) {
    const size_t size = (size_t)(strides & UINT32_MAX), count = (size_t)values->len;
    uint32_t *sorted = bare_sort_keyed_order(count, keys, shape, offsets, reverse, (size_t)(strides >> 32));
    if (sorted) bare_sort_permute(block_data(values), size, sorted, count);
    free(sorted);
    myl_core_drop_owned(keys);
    return values;
}

/* ---- numbers as text, and the terse traps ---- */

/* `value` in decimal on `stream`, without snprintf or a division (powers of ten subtracted). */
static void bare_decimal(int stream, uint32_t value) {
    static const uint32_t tens[] = { 1000000000u, 100000000u, 10000000u, 1000000u, 100000u, 10000u, 1000u, 100u, 10u, 1u };
    char text[10];
    size_t used = 0;
    for (size_t i = 0; i < sizeof tens / sizeof *tens; i++) {
        char digit = '0';
        while (value >= tens[i]) { value -= tens[i]; ++digit; }
        if (used || digit != '0' || tens[i] == 1) text[used++] = digit;
    }
    myl_bare_log_write(stream, (const unsigned char *)text, used);
}

static void bare_text(int stream, const char *text) { myl_bare_log_write(stream, (const unsigned char *)text, strlen(text)); }

/* core_rt.c's leak report, the same lines: the handles still open (none on a bare CPU) and the blocks still live. */
static void leak_report(void) {
    const int64_t live = live_count();
    if (exit_live_handles) {
        bare_text(2, "myl-core leakcheck: ");
        bare_decimal(2, (uint32_t)exit_live_handles);
        bare_text(2, " handles live at exit\n");
    }
    if (!live) return;
    bare_text(2, "myl-core leakcheck: ");
    bare_decimal(2, (uint32_t)live);
    bare_text(2, " blocks live at exit\n");
}

#if defined(MYL_BARE_TERSE)
/* A `--release` device build reports a trap as its code and its place only: `error[R_LIST_BOUNDS] PATH:LINE` (no place
 * for a trap the runtime raises outside a site), after the program's printed output, then status 1. No formatting code,
 * no detail text and no frame walk are linked. The site records the compiler emits still carry the operation and the
 * function, which this never prints. */
__attribute__((noreturn, cold, noinline)) static void bare_terse_trap(const char *code, const myl_core_site *site) {
    flush_all();
    bare_text(2, "error[");
    bare_text(2, code);
    bare_text(2, "]");
    if (site) {
        bare_text(2, " ");
        bare_text(2, site->path);
        bare_text(2, ":");
        bare_decimal(2, (uint32_t)site->line);
    }
    bare_text(2, "\n");
    myl_bare_finish(1);
}

/* Each trap kind's code, as myl_core_trap names it (a kind without one is an overflow or a cast: R_OVERFLOW). */
static const char *const bare_trap_codes[] = {
    [TRAP_DIVISION_BY_ZERO] = "R_DIVISION_BY_ZERO", [TRAP_LIST_BOUNDS] = "R_LIST_BOUNDS",
    [TRAP_FLOAT_CONVERSION] = "R_FLOAT_CONVERSION", [TRAP_FACT] = "R_CORE_FACT", [TRAP_LIST_EMPTY] = "R_LIST_BOUNDS",
    [TRAP_MISSING_KEY] = "R_MISSING_KEY", [TRAP_ITERATION_MUTATION] = "R_LIST_ITERATION_MUTATION",
    [TRAP_TEXT_BOUNDS] = "R_TEXT_BOUNDS", [TRAP_TEXT_SEPARATOR] = "R_EMPTY_SEPARATOR", [TRAP_TEXT_STEP] = "R_SLICE_STEP",
    [TRAP_BYTE_RANGE] = "R_BYTE_RANGE", [TRAP_TEXT_SCALAR] = "R_TEXT_SCALAR", [TRAP_TEXT_SUBSTRING] = "R_SUBSTRING_NOT_FOUND",
    [TRAP_INVALID_SHIFT] = "R_INVALID_SHIFT", [TRAP_LIST_VALUE] = "R_LIST_VALUE", [TRAP_LIST_POP_INDEX] = "R_LIST_BOUNDS",
    [TRAP_TEXT_BOUNDARY] = "R_TEXT_BOUNDARY", [TRAP_TYPED_HOLE] = "R_TYPED_HOLE", [TRAP_FOREIGN_RESULT] = "R_FOREIGN_RESULT",
    [TRAP_FOREIGN_TARGET] = "R_FOREIGN_TARGET",
};

void myl_core_trap(const myl_core_site *site, int64_t a, int64_t b) {
    (void)a; (void)b;
    const unsigned kind = (unsigned)site->kind;
    const char *code = kind < sizeof bare_trap_codes / sizeof *bare_trap_codes ? bare_trap_codes[kind] : NULL;
    bare_terse_trap(code ? code : "R_OVERFLOW", site);
}

void myl_core_assert_fail(const myl_core_site *site) {
    static const char *const codes[] = { "R_ASSERT", "R_REQUIRES", "R_ENSURES", "R_INVARIANT" };
    bare_terse_trap(codes[site->width >= 0 && site->width < 4 ? site->width : 0], site);
}

/* A budget names no site (core_rt.c); on a bare CPU the one budget is memory. */
static void core_io_failure(const char *code) {
    bare_terse_trap(code, strcmp(code, "R_MEMORY_BUDGET") ? core_io_site : NULL);
}

static void out_of_memory(void) { bare_terse_trap("R_MEMORY_BUDGET", NULL); }
#endif

/* ---- the reset path ---- */

extern unsigned char __data_start[], __data_end[], __data_load[], __bss_start[], __bss_end[];
extern unsigned char __stack_top[], __stack_limit[];
extern int main(int argc, char **argv);
enum { BARE_STACK_PAINT = 0x5354434bu }; /* "STCK" */

#if defined(MYL_BARE_CORES)
/* A core's stack: its reserve runs from `low` up to `top` (core 0's from the linker script, core 1's from the memory
   `registers.start_core1` gives it, core_bare_cores.c). */
typedef struct { uint32_t *low, *top; } bare_stack;

/* The stack reserve below the running frame is painted, so the core's report can say how deep the stack went. */
__attribute__((noinline)) static void bare_paint_stack(bare_stack stack) {
    uint32_t *low = stack.low, *here = (uint32_t *)__builtin_frame_address(0) - 64;
    while (low < here) *low++ = BARE_STACK_PAINT;
}
static size_t bare_stack_used(bare_stack stack) {
    const uint32_t *low = stack.low;
    while (low < stack.top && *low == BARE_STACK_PAINT) ++low;
    return (size_t)((uintptr_t)stack.top - (uintptr_t)low);
}

/* Every number of the report fits 32 bits on a 32-bit CPU. */
static void bare_say(const char *label, uint32_t value) {
    bare_text(2, label);
    bare_decimal(2, value);
}

/* A core's report (kept out of its caller: a thread-local variable's address may be asked for anywhere in the function
   that uses it, and `myl_bare_boot` must touch none before its data are in place), one line on stream 2 that the harness reads (`label` then the status, live blocks that must be 0 for
   the leak check, the core's heap and its stack), then the stack check: the lowest painted word is gone when the stack
   ran past its reserve into the heap, so the result cannot be trusted. */
__attribute__((noinline)) static void bare_core_report(const char *label, int status, bare_stack stack) {
    const bare_arena *arena = bare_arena_here();
    bare_say(label, (uint32_t)status);
    bare_say(", live blocks ", (uint32_t)live_count());
    bare_say(", heap high-water ", (uint32_t)(arena->top - arena->base));
    bare_say(" of ", (uint32_t)heap_ceiling);
    bare_say(", stack ", (uint32_t)bare_stack_used(stack));
    bare_say(" of ", (uint32_t)((uintptr_t)stack.top - (uintptr_t)stack.low));
    bare_text(2, "\n");
    if (*stack.low != BARE_STACK_PAINT) {
        core_failure_detail = "the stack ran past its reserve (the heap below it may be damaged)";
        core_io_failure("R_BARE_STACK");
    }
}

__attribute__((noreturn, used)) void myl_bare_boot(void) {
    if (__data_load != __data_start) memcpy(__data_start, __data_load, (size_t)(__data_end - __data_start));
    memset(__bss_start, 0, (size_t)(__bss_end - __bss_start));
    extern const void *const myl_bare_vectors[];
    *(volatile uint32_t *)0xE000ED08u = (uint32_t)(uintptr_t)myl_bare_vectors; /* SCB VTOR */
    myl_bare_platform_start();
    bare_cores_start();
    const bare_stack stack = { (uint32_t *)__stack_limit, (uint32_t *)__stack_top };
    bare_paint_stack(stack);
    bare_heap_ready(0);
    int status = main(0, NULL);
    /* `main` returned: core 1 stops before the report, so the log ends with core 0's line. */
    bare_core1_stop();
    bare_core_report("myl-bare: status ", status, stack);
    myl_bare_finish(status);
}
#else
/* The stack reserve below the running frame is painted, so the exit report can say how deep the stack went. */
__attribute__((noinline)) static void bare_paint_stack(void) {
    uint32_t *low = (uint32_t *)__stack_limit, *here = (uint32_t *)__builtin_frame_address(0) - 64;
    while (low < here) *low++ = BARE_STACK_PAINT;
}
static size_t bare_stack_used(void) {
    const uint32_t *low = (const uint32_t *)__stack_limit;
    while (low < (const uint32_t *)__stack_top && *low == BARE_STACK_PAINT) ++low;
    return (size_t)((uintptr_t)__stack_top - (uintptr_t)low);
}

/* Every number of the report fits 32 bits on a 32-bit CPU. */
static void bare_say(const char *label, uint32_t value) {
    bare_text(2, label);
    bare_decimal(2, value);
}

__attribute__((noreturn, used)) void myl_bare_boot(void) {
    if (__data_load != __data_start) memcpy(__data_start, __data_load, (size_t)(__data_end - __data_start));
    memset(__bss_start, 0, (size_t)(__bss_end - __bss_start));
    extern const void *const myl_bare_vectors[];
    *(volatile uint32_t *)0xE000ED08u = (uint32_t)(uintptr_t)myl_bare_vectors; /* SCB VTOR */
    myl_bare_platform_start();
    bare_paint_stack();
    bare_heap_init();
    int status = main(0, NULL);
    /* The exit report, one line on stream 2 that the harness reads: live blocks must be 0 (the leak check). */
    bare_say("myl-bare: status ", (uint64_t)status);
    bare_say(", live blocks ", (uint64_t)live_count());
    bare_say(", heap high-water ", bare_heap_top - bare_heap_base);
    bare_say(" of ", (uint64_t)heap_ceiling);
    bare_say(", stack ", bare_stack_used());
    bare_say(" of ", (uint64_t)(__stack_top - __stack_limit));
    myl_bare_write(2, (const unsigned char *)"\n", 1);
    /* The lowest painted word is gone: the stack ran past its reserve into the heap, so the result cannot be trusted. */
    if (*(const uint32_t *)__stack_limit != BARE_STACK_PAINT) {
        core_failure_detail = "the stack ran past its reserve (the heap below it may be damaged)";
        core_io_failure("R_BARE_STACK");
    }
    myl_bare_exit(status);
}
#endif

/* Reset: the stack first (a start through `exec` may not have set it), then C. */
__attribute__((naked, noreturn, used)) void myl_bare_reset(void) {
    __asm__ volatile("ldr r0, =__stack_top\n mov sp, r0\n bl myl_bare_boot\n .ltorg");
}

#if defined(MYL_BARE_FREESTANDING)
/* The fault decoder, linked only into an image whose program has a freestanding fault site (-DMYL_BARE_FREESTANDING,
   chosen by the driver, `driver.bareFlavour`): every other image has the plain handler below, and not this table of code
   names or the code that reads the stacked registers. */
/* A failed check of a `@freestanding` function (`src/core/freestanding_emitted.zig`) is `udf #83` with its code in r0, its
   source path in r1 and its line in r2: the fault reports it in the terse form of a `--release` device build's trap,
   `error[R_LIST_BOUNDS] PATH:LINE`, in every build mode. The code's low byte is the trap kind (`TRAP_*`); an assertion's
   clause is the next byte. A foreign call's checks fault too: a null `@address` target (`TRAP_FOREIGN_TARGET`) and a
   `Host` token that is not the live one, compared inline (kind 24, `BARE_FAULT_CAPABILITY`, which only a fault uses). */
enum { BARE_FREESTANDING_UDF = 0xDE00u | 83u, BARE_TRAP_ASSERTION = 8, BARE_FAULT_CAPABILITY = 24 };
static const char *bare_fault_code(uint32_t code) {
    static const char *const kinds[] = {
        [TRAP_OVERFLOW] = "R_OVERFLOW", [TRAP_DIVISION_BY_ZERO] = "R_DIVISION_BY_ZERO", [TRAP_LIST_BOUNDS] = "R_LIST_BOUNDS",
        [TRAP_FLOAT_CONVERSION] = "R_FLOAT_CONVERSION", [TRAP_CAST] = "R_OVERFLOW", [TRAP_FACT] = "R_CORE_FACT",
        [TRAP_LIST_EMPTY] = "R_LIST_BOUNDS", [TRAP_INVALID_SHIFT] = "R_INVALID_SHIFT", [TRAP_TYPED_HOLE] = "R_TYPED_HOLE",
        [TRAP_FOREIGN_TARGET] = "R_FOREIGN_TARGET", [BARE_FAULT_CAPABILITY] = "R_CAPABILITY",
    };
    static const char *const clauses[] = { "R_ASSERT", "R_REQUIRES", "R_ENSURES", "R_INVARIANT" };
    const uint32_t kind = code & 0xffu, clause = (code >> 8) & 0xffu;
    if (kind == BARE_TRAP_ASSERTION) return clause < 4 ? clauses[clause] : "R_ASSERT";
    return kind < sizeof kinds / sizeof *kinds && kinds[kind] ? kinds[kind] : "R_OVERFLOW";
}

/* Whether `pc` may be read: inside the image's own memory, so a fault at a bad address does not fault again here. */
static int bare_code_address(uint32_t pc) {
    extern void myl_bare_fault_frame(const uint32_t *frame);
    const uint32_t here = (uint32_t)(uintptr_t)myl_bare_fault_frame, region = here & 0xF0000000u;
    const uint32_t top = ((uint32_t)(uintptr_t)__stack_top & 0xF0000000u) == region ? (uint32_t)(uintptr_t)__stack_top : region + 0x01000000u;
    return (pc & 1u) == 0 && pc >= region && pc + 2 <= top;
}

/* The fault handler's C half: `frame` is the stacked r0-r3, r12, lr, pc, xPSR of the faulting code. */
__attribute__((used, noreturn)) void myl_bare_fault_frame(const uint32_t *frame) {
    const uint32_t pc = frame[6];
    if (bare_code_address(pc) && *(const volatile uint16_t *)(uintptr_t)pc == BARE_FREESTANDING_UDF) {
        flush_all();
        bare_text(2, "error[");
        bare_text(2, bare_fault_code(frame[0]));
        bare_text(2, "] ");
        bare_text(2, (const char *)(uintptr_t)frame[1]);
        bare_text(2, ":");
        bare_decimal(2, frame[2]);
        bare_text(2, "\n");
        myl_bare_finish(1); /* the program's one end: on either core when it also starts the second */
    }
    core_failure_detail = "the CPU faulted (bad address or instruction)";
    core_io_failure("R_BARE_FAULT");
    for (;;) {}
}

/* A fault (a bad address, an undefined instruction): the trap path with its own code, status 1. The stacked frame is on
   the stack the faulting code used (bit 2 of the exception return value). */
__attribute__((naked, used)) void myl_bare_fault(void) {
    __asm__ volatile("movs r0, #4\n mov r1, lr\n tst r0, r1\n beq 1f\n mrs r0, psp\n b 2f\n1: mrs r0, msp\n2: ldr r1, =myl_bare_fault_frame\n bx r1\n .ltorg");
}
#else
/* A fault (a bad address, an undefined instruction): the trap path with its own code, status 1. */
__attribute__((used)) void myl_bare_fault(void) {
    core_failure_detail = "the CPU faulted (bad address or instruction)";
    core_io_failure("R_BARE_FAULT");
}
#endif

/* The vector table: initial stack, reset, then every exception into the fault report. */
__attribute__((section(".vectors"), used)) const void *const myl_bare_vectors[16] = {
    __stack_top, (const void *)myl_bare_reset,
    (const void *)myl_bare_fault, (const void *)myl_bare_fault, (const void *)myl_bare_fault,
    (const void *)myl_bare_fault, (const void *)myl_bare_fault, 0, 0, 0, 0,
    (const void *)myl_bare_fault, (const void *)myl_bare_fault, 0,
    (const void *)myl_bare_fault, (const void *)myl_bare_fault,
};
