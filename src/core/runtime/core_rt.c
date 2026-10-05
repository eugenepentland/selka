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
#include <elf.h>
#include <execinfo.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>

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

/* The return addresses on the stack, innermost first, walked through `.eh_frame`
   (glibc's `backtrace`, which is libgcc's `_Unwind_Backtrace`; no unwinder is
   linked into the program). */
static int os_stack(void **pcs, int capacity) { return backtrace(pcs, capacity); }

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

enum { MYL_KIND_LIST = 0, MYL_KIND_STR = 1, MYL_KIND_BOX = 2 };
enum { MYL_HEADER = 32, MYL_ALIGN = 32 };
/* A saturated count (D4): the block is immortal, never written and never freed. */
#define MYL_SATURATED UINT32_MAX

static unsigned char *block_data(myl_block *block) { return (unsigned char *)block + MYL_HEADER; }

static void out_of_memory(void);

/* Blocks ever carved from chunks plus large blocks not yet freed. A small block is
   live exactly when it was carved and is not on a free list, so the
   MYL_CORE_LEAKCHECK=1 count (`live_count`) needs no counting on the fast paths. */
static int64_t live_blocks;

/* ---- allocation ----------------------------------------------------------------
 * Blocks of up to MYL_SMALL bytes (header included) come from per-size-class free
 * lists, one class per 32-byte granule, carved from 64 KiB chunks that are never
 * returned; a freed small block goes back to its class's list. Larger blocks are
 * `malloc`ed, and a large list grows with `realloc`. The class sits in the high
 * byte of `kind` (0: large), so a free needs no size. A list's `cap` is all its
 * block holds, so a small list grows within its class without moving.
 * Single-threaded, like the counts. The common cases (a small list from a free
 * list, a push with room, a free of a small block without children) are emitted
 * inline by `emit_llvm.zig` against `myl_core_free_lists`; these functions are
 * the rest. */
enum { MYL_GRANULE = 32, MYL_SMALL = 1024, MYL_CLASSES = MYL_SMALL / MYL_GRANULE, MYL_CHUNK = 1 << 16 };
#define MYL_KIND_MASK 0xffu
#define MYL_CLASS_SHIFT 24

void *myl_core_free_lists[MYL_CLASSES + 1];
#define free_lists myl_core_free_lists
static unsigned char *chunk_next, *chunk_end;

static uint32_t kind_of(const myl_block *block) { return block->kind & MYL_KIND_MASK; }
static uint32_t class_of(const myl_block *block) { return block->kind >> MYL_CLASS_SHIFT; }

/* A small block of `class` granules: from its free list, else carved from a chunk. */
static void *small_alloc(uint32_t class) {
    void *block = free_lists[class];
    if (block) {
        free_lists[class] = *(void **)block;
        return block;
    }
    size_t bytes = (size_t)class * MYL_GRANULE;
    if ((size_t)(chunk_end - chunk_next) < bytes) {
        chunk_next = aligned_alloc(MYL_ALIGN, MYL_CHUNK);
        if (!chunk_next) out_of_memory();
        chunk_end = chunk_next + MYL_CHUNK;
    }
    block = chunk_next;
    chunk_next += bytes;
    ++live_blocks;
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
        *room = data;
        ++live_blocks;
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
    int64_t live = live_blocks;
    for (int class = 1; class <= MYL_CLASSES; ++class) {
        for (void *at = free_lists[class]; at; at = *(void **)at) --live;
    }
    return live;
}

static void block_free(myl_block *block) {
    uint32_t class = class_of(block);
    if (class == 0) {
        --live_blocks;
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
        myl_block *moved = realloc(list, bytes);
        if (!moved) out_of_memory();
        if (((uintptr_t)moved & (MYL_ALIGN - 1)) != 0) {
            myl_block *aligned = aligned_alloc(MYL_ALIGN, (bytes + MYL_ALIGN - 1) & ~(size_t)(MYL_ALIGN - 1));
            if (!aligned) out_of_memory();
            memcpy(aligned, moved, MYL_HEADER + (size_t)moved->len * (size_t)element_size);
            free(moved);
            moved = aligned;
        }
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
 * owner calls `myl_core_free` (emitted: a small block without children goes
 * straight back to its free list), else `myl_core_free_block`, which frees the block and releases the blocks its
 * elements hold, iteratively: a child whose last owner goes joins a pending
 * chain linked through its `cap` word (a dying block needs only `kind`, `len`
 * and `reserved`), so freeing a list of lists nested a million deep uses no
 * stack. The emitted release does not store the final 0, so a dying block is
 * recognized by the caller, never by its count. */
__attribute__((cold)) void myl_core_free_block(myl_block *block) {
    block->cap = 0;
    myl_block *pending = block;
    while (pending) {
        myl_block *dying = pending;
        pending = (myl_block *)(intptr_t)dying->cap;
        myl_layout *layout = layout_of(dying);
        if (layout && kind_of(dying) != MYL_KIND_STR) {
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
    if (block->count == 1) myl_core_free_block(block);
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
    uint64_t tag, low, high, ranges, origin, call_line, call_column, stmt_list;
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
static bool dw_line(const dw_unit *unit, uint64_t pc, uint64_t *line_out, uint64_t *column_out) {
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
    uint64_t address = 0, line = 1, column = 0;
    bool found = false, have_previous = false;
    uint64_t previous_address = 0, previous_line = 0, previous_column = 0;
#define DW_ROW()                                                                                   \
    do {                                                                                           \
        if (have_previous && previous_address <= pc && pc < address) {                             \
            *line_out = previous_line; *column_out = previous_column; found = true;                \
        }                                                                                          \
        previous_address = address; previous_line = line; previous_column = column; have_previous = true; \
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
                address = 0; line = 1; column = 0;
            } else if (sub == 2) address = dw_fixed(&c, (int)(size - 1));
            c.p = next;
        } else if (opcode == 1) DW_ROW();
        else if (opcode == 2) address += dw_uleb(&c) * min_length;
        else if (opcode == 3) line += (uint64_t)dw_sleb(&c);
        else if (opcode == 5) column = dw_uleb(&c);
        else if (opcode == 8) address += ((255 - opcode_base) / line_range) * min_length;
        else if (opcode == 9) address += dw_fixed(&c, 2);
        else for (uint64_t i = 0; i < lengths[opcode - 1]; ++i) dw_uleb(&c); /* file, negate_stmt, … */
    }
#undef DW_ROW
    return found;
}

enum { DW_MAX_DEPTH = 64 };

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
        if (chain_length == 0) return 0;
        /* chain[0..chain_length) from the subprogram inward; print innermost first. */
        uint64_t line = 0, column = 0;
        dw_line(&unit, pc, &line, &column);
        char text[1024];
        int printed = 0;
        for (int k = chain_length - 1; k >= 0; --k, ++printed) {
            /* The C entry, into which `main` may be inlined, is no frame of the program. */
            if (strcmp(dw_name(&unit, &chain[k]), "myl.entry") == 0) break;
            if (printed < skip) {
                line = chain[k].call_line;
                column = chain[k].call_column;
                continue;
            }
            int len = snprintf(text, sizeof text, "  in %s at %s:%llu:%llu\n", dw_name(&unit, &chain[k]), myl_core_source_path, (unsigned long long)line, (unsigned long long)column);
            stream_write(&streams[1], text, (size_t)(len < (int)sizeof text ? len : (int)sizeof text - 1));
            line = chain[k].call_line;
            column = chain[k].call_column;
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

/* Report a failed check the way the old core does (code, detail, one `in f at …`
   line per frame and the `MYLANG-TRAP` record on stderr) and exit 1. The trapping
   frame comes from the site table, its callers from `trap_frames`. */
void myl_core_trap(int32_t index, int64_t a, int64_t b) {
    const myl_core_site *site = &myl_core_sites[index];
    char detail[256] = "";
    char record[256] = "";
    const char *code = "R_OVERFLOW";
    switch (site->kind) {
    case TRAP_OVERFLOW:
        snprintf(detail, sizeof detail, " (%s: left %lld, right %lld, width %d)", site->operation, (long long)a, (long long)b, site->width);
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"%s\",\"left\":%lld,\"right\":%lld,\"width\":%d}\n", site->operation, (long long)a, (long long)b, site->width);
        break;
    case TRAP_DIVISION_BY_ZERO:
        code = "R_DIVISION_BY_ZERO";
        snprintf(detail, sizeof detail, " (%s: left %lld, right %lld)", site->operation, (long long)a, (long long)b);
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"%s\",\"left\":%lld,\"right\":%lld}\n", site->operation, (long long)a, (long long)b);
        break;
    case TRAP_LIST_BOUNDS:
        code = "R_LIST_BOUNDS";
        snprintf(detail, sizeof detail, " (index %lld, length %lld)", (long long)a, (long long)b);
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"index\",\"index\":%lld,\"length\":%lld}\n", (long long)a, (long long)b);
        break;
    case TRAP_LIST_EMPTY:
        /* A pop of an empty list: the old core's code and `pop` detail (PY-COLLECTIONS-20). */
        code = "R_LIST_BOUNDS";
        snprintf(detail, sizeof detail, " (length %lld)", (long long)b);
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"pop\",\"length\":%lld}\n", (long long)b);
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
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"cast\",\"left\":%lld,\"width\":%d}\n", (long long)a, site->width);
        break;
    }
    stream_flush(&streams[0]);
    char text[1024];
    int len = snprintf(text, sizeof text, "%s:%d:%d: error[%s]: native execution failed%s\n  in %s at %s:%d:%d\n",
        myl_core_source_path, site->line, site->column, code, detail, site->function, myl_core_source_path, site->line, site->column);
    stream_write(&streams[1], text, (size_t)(len < (int)sizeof text ? len : (int)sizeof text - 1));
    trap_frames();
    stream_write(&streams[1], record, strlen(record));
    flush_all();
    os_exit(1);
}

/* With MYL_CORE_LEAKCHECK=1, a program that ends with blocks still allocated says
   how many on stderr (the exit status is unchanged). Every path that returns from
   `main` releases what it owns, so a nonzero count is an ownership bug; a trap
   runs no releases (RC-TRAP-TEARDOWN-1) and is not checked. */
static void leak_report(void) {
    const char *flag = getenv("MYL_CORE_LEAKCHECK");
    if (!flag || strcmp(flag, "1") != 0) return;
    int64_t live = live_count();
    if (live == 0) return;
    char text[96];
    int len = snprintf(text, sizeof text, "myl-core leakcheck: %lld blocks live at exit\n", (long long)live);
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
