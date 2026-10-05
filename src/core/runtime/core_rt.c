/* The new core's runtime (docs/design/new-core-ir.md §8, new-core-s1.md §5-§6).
 *
 * Blocks: a 32-byte header {u32 count, u32 kind, i64 len, i64 cap, i64 reserved}
 * followed by 32-byte-aligned data. `count` is the single saturating 32-bit
 * reference count of D4; every block starts with count 1, and the emitted code
 * counts inline and frees through `myl_core_free`. `reserved` holds the element
 * layout of a list or box whose elements hold blocks (null otherwise), so a free
 * releases the children. There is no collector and no memory budget (L3): an
 * allocation the OS refuses ends the process with one message.
 *
 * Output: one buffer per standard stream, flushed when full, at exit and before a
 * trap report, so stdout keeps program order relative to a trap. */
#define _POSIX_C_SOURCE 200809L
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ---- platform layer (POSIX) ------------------------------------------------
 * Every operating-system call the runtime makes goes through these functions;
 * the rest of the file is portable C11. A Windows or macOS port replaces this
 * section (or moves it to a core_rt_<os>.c); arguments arrive through the
 * LLVM-emitted C `main`, and future clock, file, network and environment
 * access belongs here too. */

/* Write all of `len` bytes to a standard stream (1 or 2), as far as the OS allows. */
static void os_write(int fd, const unsigned char *bytes, size_t len) {
    size_t done = 0;
    while (done < len) {
        ssize_t wrote = write(fd, bytes + done, len - done);
        if (wrote <= 0) break;
        done += (size_t)wrote;
    }
}

/* End the process now, with no atexit handlers (a trap or a fatal error). */
static void os_exit(int status) { _exit(status); }

/* ---- blocks ------------------------------------------------------------------ */

typedef struct {
    uint32_t count;
    uint32_t kind;
    int64_t len;
    int64_t cap;
    int64_t reserved;
} myl_block;

enum { MYL_KIND_LIST = 0, MYL_KIND_STR = 1, MYL_KIND_BOX = 2 };
enum { MYL_HEADER = 32, MYL_ALIGN = 32 };
/* A saturated count (D4): the block is immortal, never written and never freed. */
#define MYL_SATURATED UINT32_MAX

static unsigned char *block_data(myl_block *block) { return (unsigned char *)block + MYL_HEADER; }

static void out_of_memory(void);

/* Blocks allocated and not yet freed: the MYL_CORE_LEAKCHECK=1 report at exit. */
static int64_t live_blocks;

static myl_block *block_new(uint32_t kind, int64_t cap, int64_t element_size) {
    size_t bytes = MYL_HEADER + (size_t)(cap > 0 ? cap : 0) * (size_t)element_size + 1;
    bytes = (bytes + MYL_ALIGN - 1) & ~(size_t)(MYL_ALIGN - 1);
    myl_block *block = aligned_alloc(MYL_ALIGN, bytes);
    if (!block) out_of_memory();
    block->count = 1;
    block->kind = kind;
    block->len = 0;
    block->cap = cap > 0 ? cap : 0;
    block->reserved = 0;
    ++live_blocks;
    return block;
}

static void block_free(myl_block *block) {
    --live_blocks;
    free(block);
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
static int64_t element_count(const myl_block *block) { return block->kind == MYL_KIND_BOX ? 1 : block->len; }

/* ---- buffered streams ------------------------------------------------------- */

typedef struct {
    size_t used;
    unsigned char bytes[1 << 16];
} myl_stream;

/* Zero-initialized (in .bss, not 128 KiB of .data): stream i writes descriptor i + 1. */
static myl_stream streams[2];

static myl_stream *stream_for(int64_t fd) { return &streams[fd == 2 ? 1 : 0]; }

static void stream_flush(myl_stream *stream) {
    os_write(stream == &streams[1] ? 2 : 1, stream->bytes, stream->used);
    stream->used = 0;
}

static void stream_write(myl_stream *stream, const void *data, size_t len) {
    const unsigned char *bytes = data;
    while (len > 0) {
        if (stream->used == sizeof stream->bytes) stream_flush(stream);
        size_t room = sizeof stream->bytes - stream->used;
        size_t take = len < room ? len : room;
        memcpy(stream->bytes + stream->used, bytes, take);
        stream->used += take;
        bytes += take;
        len -= take;
    }
}

static void flush_all(void) {
    stream_flush(&streams[0]);
    stream_flush(&streams[1]);
}

static void out_of_memory(void) {
    flush_all();
    static const char message[] = "fatal: out of memory\n";
    os_write(2, (const unsigned char *)message, sizeof message - 1);
    os_exit(1);
}

void myl_core_print_i64(int64_t fd, int64_t value) {
    char text[32];
    int len = snprintf(text, sizeof text, "%lld", (long long)value);
    stream_write(stream_for(fd), text, (size_t)len);
}

void myl_core_print_u64(int64_t fd, uint64_t value) {
    char text[32];
    int len = snprintf(text, sizeof text, "%llu", (unsigned long long)value);
    stream_write(stream_for(fd), text, (size_t)len);
}

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
    if (fd == 2) stream_flush(stream_for(fd));
}

/* ---- lists and strings ------------------------------------------------------ */

myl_block *myl_core_list_new(int64_t cap, int64_t element_size) {
    return block_new(MYL_KIND_LIST, cap, element_size);
}

/* A block with room for one more element: `list` itself while it has room,
   else a grown copy. The caller's old value is dead after the push (the IR's
   uniqueness rule), so growing frees the old block. */
myl_block *myl_core_list_reserve(myl_block *list, int64_t element_size) {
    if (list->len < list->cap) return list;
    int64_t cap = list->cap < 4 ? 8 : list->cap * 2;
    myl_block *grown = block_new(MYL_KIND_LIST, cap, element_size);
    memcpy(block_data(grown), block_data(list), (size_t)list->len * (size_t)element_size);
    grown->len = list->len;
    grown->reserved = list->reserved;
    block_free(list);
    return grown;
}

/* One more owner of `block` (D4: a count that reaches the saturated value stays there). */
static void retain_block(myl_block *block) {
    if (block->count != MYL_SATURATED) ++block->count;
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

static myl_block *str_from(const char *bytes, size_t len) {
    myl_block *text = block_new(MYL_KIND_STR, (int64_t)len, 1);
    memcpy(block_data(text), bytes, len);
    block_data(text)[len] = 0;
    text->len = (int64_t)len;
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
 * owner calls `myl_core_free`, which frees the block and releases the blocks its
 * elements hold, iteratively: a child whose last owner goes joins a pending
 * chain linked through its `cap` word (a dying block needs only `kind`, `len`
 * and `reserved`), so freeing a list of lists nested a million deep uses no
 * stack. The emitted release does not store the final 0, so a dying block is
 * recognized by the caller, never by its count. */
__attribute__((cold)) void myl_core_free(myl_block *block) {
    block->cap = 0;
    myl_block *pending = block;
    while (pending) {
        myl_block *dying = pending;
        pending = (myl_block *)(intptr_t)dying->cap;
        myl_layout *layout = layout_of(dying);
        if (layout && dying->kind != MYL_KIND_STR) {
            int64_t count = element_count(dying);
            for (int64_t i = 0; i < count; ++i) {
                const unsigned char *element = block_data(dying) + i * (int64_t)layout[0];
                for (int32_t r = 0; r < layout[1]; ++r) {
                    myl_block *child = reference_at(layout, element, r);
                    if (!child || child->count == MYL_SATURATED) continue;
                    if (child->count == 1) {
                        child->cap = (int64_t)(intptr_t)pending;
                        pending = child;
                    } else --child->count;
                }
            }
        }
        block_free(dying);
    }
}

/* Drop one owner of `block` out of line: the C entry's `args` and `main`'s error. */
void myl_core_release(myl_block *block) {
    if (!block || block->count == MYL_SATURATED) return;
    if (block->count == 1) myl_core_free(block);
    else --block->count;
}

/* ---- error traces (ERROR-TRACE-1..5) -------------------------------------------
 * Called on Err paths only: mode 0 restarts the trace with `site` as its origin
 * (building an Err), mode 1 appends a site (a `?` that propagates one). Sites
 * index `myl_core_sites`, whose operation names the action. The ring keeps the
 * last 32 appends (ERROR-TRACE-4); nothing is allocated. */
enum { TRACE_RING = 32 };
static struct {
    int32_t origin;
    uint64_t count;
    int32_t ring[TRACE_RING];
} error_trace = {.origin = -1};

__attribute__((cold, noinline)) void myl_core_err_trace(int32_t site, int32_t mode) {
    if (mode == 0) {
        error_trace.origin = site;
        error_trace.count = 0;
        return;
    }
    error_trace.ring[error_trace.count++ % TRACE_RING] = site;
}

/* `main`'s `args`: every command-line argument after the program name. */
/* The layout of a list whose elements are block pointers (`list[str]`). */
static const int32_t layout_blocks[] = {8, 1, 0, 0, 0};

myl_block *myl_core_args(int32_t argc, char **argv) {
    int64_t count = argc > 1 ? argc - 1 : 0;
    myl_block *list = block_new(MYL_KIND_LIST, count, sizeof(void *));
    list->reserved = (int64_t)(intptr_t)layout_blocks;
    for (int64_t i = 0; i < count; ++i) ((myl_block **)block_data(list))[i] = str_from(argv[i + 1], strlen(argv[i + 1]));
    list->len = count;
    return list;
}

static bool ascii_space(unsigned char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'; }

/* `int(text)` with the pinned grammar (docs/bytes.md): surrounding ASCII
   whitespace, one optional sign, decimal digits with single `_` separators
   between digits. An overflowing value is None. */
bool myl_core_str_parse_int(myl_block *text, int64_t *out) {
    const unsigned char *s = block_data(text);
    size_t start = 0, end = (size_t)text->len;
    while (start < end && ascii_space(s[start])) ++start;
    while (end > start && ascii_space(s[end - 1])) --end;
    bool negative = false;
    if (start < end && (s[start] == '+' || s[start] == '-')) negative = s[start++] == '-';
    if (start == end) return false;
    uint64_t magnitude = 0;
    bool previous_digit = false;
    for (size_t i = start; i < end; ++i) {
        unsigned char c = s[i];
        if (c == '_') {
            if (!previous_digit || i + 1 == end) return false;
            previous_digit = false;
            continue;
        }
        if (c < '0' || c > '9') return false;
        if (magnitude > (UINT64_MAX - (uint64_t)(c - '0')) / 10) return false;
        magnitude = magnitude * 10 + (uint64_t)(c - '0');
        previous_digit = true;
    }
    if (!previous_digit) return false;
    if (negative) {
        if (magnitude > (uint64_t)INT64_MAX + 1) return false;
        *out = magnitude == (uint64_t)INT64_MAX + 1 ? INT64_MIN : -(int64_t)magnitude;
    } else {
        if (magnitude > (uint64_t)INT64_MAX) return false;
        *out = (int64_t)magnitude;
    }
    return true;
}

/* ---- traps and exit --------------------------------------------------------- */

typedef struct {
    int32_t kind;
    int32_t line;
    int32_t column;
    int32_t width;
    const char *operation;
    const char *function;
} myl_core_site;

extern const myl_core_site myl_core_sites[];
extern const char myl_core_source_path[];

enum { TRAP_OVERFLOW, TRAP_DIVISION_BY_ZERO, TRAP_LIST_BOUNDS, TRAP_FLOAT_CONVERSION, TRAP_CAST, TRAP_FACT, TRAP_LIST_EMPTY };

static const char *unqualified(const char *name) {
    const char *at = strrchr(name, ':');
    return at ? at + 1 : name;
}

/* Report a failed check the way the old core does (code, detail and the
   `MYLANG-TRAP` record on stderr) and exit 1. Only the innermost frame is named
   in S0; the PC-table trace is S1 work. */
void myl_core_trap(int32_t index, int64_t a, int64_t b) {
    const myl_core_site *site = &myl_core_sites[index];
    char detail[256] = "";
    char record[256] = "";
    const char *code = "R_OVERFLOW";
    switch (site->kind) {
    case TRAP_OVERFLOW:
        snprintf(detail, sizeof detail, " (%s: left %lld, right %lld, width %d)", site->operation, (long long)a, (long long)b, site->width);
        snprintf(record, sizeof record, "MYLANG-TRAP {\"version\":1,\"operation\":\"%s\",\"left\":%lld,\"right\":%lld,\"width\":%d}\n", site->operation, (long long)a, (long long)b, site->width);
        break;
    case TRAP_DIVISION_BY_ZERO:
        code = "R_DIVISION_BY_ZERO";
        snprintf(detail, sizeof detail, " (%s: left %lld, right %lld)", site->operation, (long long)a, (long long)b);
        snprintf(record, sizeof record, "MYLANG-TRAP {\"version\":1,\"operation\":\"%s\",\"left\":%lld,\"right\":%lld}\n", site->operation, (long long)a, (long long)b);
        break;
    case TRAP_LIST_BOUNDS:
        code = "R_LIST_BOUNDS";
        snprintf(detail, sizeof detail, " (index %lld, length %lld)", (long long)a, (long long)b);
        snprintf(record, sizeof record, "MYLANG-TRAP {\"version\":1,\"operation\":\"index\",\"index\":%lld,\"length\":%lld}\n", (long long)a, (long long)b);
        break;
    case TRAP_LIST_EMPTY:
        /* A pop of an empty list: the old core's code and `pop` detail (PY-COLLECTIONS-20). */
        code = "R_LIST_BOUNDS";
        snprintf(detail, sizeof detail, " (length %lld)", (long long)b);
        snprintf(record, sizeof record, "MYLANG-TRAP {\"version\":1,\"operation\":\"pop\",\"length\":%lld}\n", (long long)b);
        break;
    case TRAP_FLOAT_CONVERSION:
        code = "R_FLOAT_CONVERSION";
        break;
    case TRAP_FACT:
        /* Verify builds only: a fact the compiler relied on does not hold. */
        code = "R_CORE_FACT";
        snprintf(detail, sizeof detail, " (%s: value %lld, other %lld)", site->operation, (long long)a, (long long)b);
        break;
    default:
        snprintf(detail, sizeof detail, " (cast: left %lld, width %d)", (long long)a, site->width);
        snprintf(record, sizeof record, "MYLANG-TRAP {\"version\":1,\"operation\":\"cast\",\"left\":%lld,\"width\":%d}\n", (long long)a, site->width);
        break;
    }
    stream_flush(&streams[0]);
    char text[1024];
    int len = snprintf(text, sizeof text, "%s:%d:%d: error[%s]: native execution failed%s\n  in %s at %s:%d:%d\n%s",
        myl_core_source_path, site->line, site->column, code, detail, unqualified(site->function), myl_core_source_path, site->line, site->column, record);
    stream_write(&streams[1], text, (size_t)(len < (int)sizeof text ? len : (int)sizeof text - 1));
    flush_all();
    os_exit(1);
}

/* With MYL_CORE_LEAKCHECK=1, a program that ends with blocks still allocated says
   how many on stderr (the exit status is unchanged). Every path that returns from
   `main` releases what it owns, so a nonzero count is an ownership bug; a trap
   runs no releases (RC-TRAP-TEARDOWN-1) and is not checked. */
static void leak_report(void) {
    const char *flag = getenv("MYL_CORE_LEAKCHECK");
    if (!flag || strcmp(flag, "1") != 0 || live_blocks == 0) return;
    char text[96];
    int len = snprintf(text, sizeof text, "myl-core leakcheck: %lld blocks live at exit\n", (long long)live_blocks);
    os_write(2, (const unsigned char *)text, (size_t)len);
}

/* `main`'s result is the exit status, truncated to the low 8 bits. */
int32_t myl_core_exit(int64_t status) {
    flush_all();
    leak_report();
    return (int32_t)(status & 0xFF);
}

/* ---- `main` returning Err (RESULT-MAIN-1/2, ERROR-TRACE-2) ---------------------- */

static int trace_where(const myl_core_site *site, char *out, size_t size) {
    return snprintf(out, size, "%s:%d:%d", myl_core_source_path, site->line, site->column);
}

/* A `returned` site on the line of the site before it, in the same function, is folded into it. */
static bool trace_folds(const myl_core_site *previous, const myl_core_site *site) {
    return strcmp(site->operation, "returned") == 0 && strcmp(previous->function, site->function) == 0 && previous->line == site->line;
}

/* The trace, origin first: one `  path:line:column  function  action` line per
   site with the columns aligned, and a `... N more entries dropped ...` line
   where the ring overwrote appends. */
static void trace_write(void) {
    const myl_core_site *listed[1 + TRACE_RING];
    size_t count = 0, gap = 0;
    if (error_trace.origin >= 0) listed[count++] = &myl_core_sites[error_trace.origin];
    gap = count;
    uint64_t kept = error_trace.count < TRACE_RING ? error_trace.count : TRACE_RING;
    uint64_t dropped = error_trace.count - kept;
    for (uint64_t i = error_trace.count - kept; i < error_trace.count; ++i) {
        const myl_core_site *site = &myl_core_sites[error_trace.ring[i % TRACE_RING]];
        if (count && trace_folds(listed[count - 1], site)) continue;
        listed[count++] = site;
    }
    int width = 0, name_width = 0;
    char where[1024];
    for (size_t i = 0; i < count; ++i) {
        int len = trace_where(listed[i], where, sizeof where);
        int name = (int)strlen(unqualified(listed[i]->function));
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
        int len = snprintf(line, sizeof line, "  %-*s  %-*s  %s\n", width, where, name_width, unqualified(listed[i]->function), listed[i]->operation);
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
