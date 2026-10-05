/* The new core's S0 runtime (docs/design/new-core-ir.md §8).
 *
 * Blocks: a 32-byte header {u32 count, u32 kind, i64 len, i64 cap, i64 reserved}
 * followed by 32-byte-aligned data. `count` is the single saturating 32-bit
 * reference count of D4; S0 creates every block with count 1 and frees none (the
 * ownership pass that releases them is S1). There is no collector and no memory
 * budget (L3): an allocation the OS refuses ends the process with one message.
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

enum { MYL_KIND_LIST = 0, MYL_KIND_STR = 1 };
enum { MYL_HEADER = 32, MYL_ALIGN = 32 };

static unsigned char *block_data(myl_block *block) { return (unsigned char *)block + MYL_HEADER; }

static void out_of_memory(void);

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
    return block;
}

/* ---- buffered streams ------------------------------------------------------- */

typedef struct {
    int fd;
    size_t used;
    unsigned char bytes[1 << 16];
} myl_stream;

static myl_stream streams[2] = {{.fd = 1}, {.fd = 2}};

static myl_stream *stream_for(int64_t fd) { return &streams[fd == 2 ? 1 : 0]; }

static void stream_flush(myl_stream *stream) {
    os_write(stream->fd, stream->bytes, stream->used);
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
    free(list);
    return grown;
}

/* A fresh copy of `list` with room for one more element: what a push appends to
   when the list may be shared (`own.zig`), so the original block stays intact. */
myl_block *myl_core_list_copy(myl_block *list, int64_t element_size) {
    myl_block *copy = block_new(MYL_KIND_LIST, list->len + 1, element_size);
    memcpy(block_data(copy), block_data(list), (size_t)list->len * (size_t)element_size);
    copy->len = list->len;
    return copy;
}

static myl_block *str_from(const char *bytes, size_t len) {
    myl_block *text = block_new(MYL_KIND_STR, (int64_t)len, 1);
    memcpy(block_data(text), bytes, len);
    block_data(text)[len] = 0;
    text->len = (int64_t)len;
    return text;
}

/* `main`'s `args`: every command-line argument after the program name. */
myl_block *myl_core_args(int32_t argc, char **argv) {
    int64_t count = argc > 1 ? argc - 1 : 0;
    myl_block *list = block_new(MYL_KIND_LIST, count, sizeof(void *));
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

enum { TRAP_OVERFLOW, TRAP_DIVISION_BY_ZERO, TRAP_LIST_BOUNDS, TRAP_FLOAT_CONVERSION, TRAP_CAST, TRAP_FACT };

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

/* `main`'s result is the exit status, truncated to the low 8 bits. */
int32_t myl_core_exit(int64_t status) {
    flush_all();
    return (int32_t)(status & 0xFF);
}
