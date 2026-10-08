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
static void core_io_cleanup(void);
static void core_host_cleanup(void);
static void os_exit(int status) { core_io_cleanup(); _exit(status); }

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

enum { MYL_KIND_LIST = 0, MYL_KIND_STR = 1, MYL_KIND_BOX = 2, MYL_KIND_BYTES = 3, MYL_KIND_DICT = 4 };
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
/* Class 0xff marks a list `promote.zig` put in a stack frame (`emit_llvm.zig`
   `stackList`): nothing releases it and its pushes skip `myl_core_list_grow`, so no
   function here ever sees one. */

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

static inline void core_err_trace_record(int32_t site, int32_t mode) {
    if (mode == 0) {
        error_trace.origin = site;
        error_trace.count = 0;
        return;
    }
    error_trace.ring[error_trace.count++ % TRACE_RING] = site;
}

/* Ordinary C callers keep their ABI. Compiler-owned err_trace operations use
 * the register-preserving twin (ERROR-TRACE-6), with the same recording leaf. */
__attribute__((cold, noinline)) void myl_core_err_trace(int32_t site, int32_t mode) {
    core_err_trace_record(site, mode);
}

__attribute__((cold, noinline, preserve_most))
void myl_core_err_trace_origin_preserve_most(int32_t site) {
    core_err_trace_record(site, 0);
}

__attribute__((cold, noinline, preserve_most))
void myl_core_err_trace_append_preserve_most(int32_t site) {
    core_err_trace_record(site, 1);
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
        snprintf(detail, sizeof detail, " (cast: left %lld, width %d)", (long long)a, site->width);
        snprintf(record, sizeof record, "\036MYLANG-TRAP {\"version\":1,\"operation\":\"cast\",\"left\":%lld,\"width\":%d}\n", (long long)a, site->width);
        break;
    }
    if (record[0] == 0 && site->kind != TRAP_FACT) core_operation_record(record, sizeof record, site->operation);
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

static int32_t core_io_site=-1;
void myl_core_io_at(int32_t site){core_io_site=site;}
/* Runtime effects keep their checked call site; walk past C adapters before
   printing the guest callers, just as a generated trap keeps its site frame. */
__attribute__((cold,noinline)) static void core_io_failure(const char *code){
    stream_flush(&streams[0]);char text[1024];int length;
    if(core_io_site>=0){const myl_core_site *site=&myl_core_sites[core_io_site];length=snprintf(text,sizeof text,"%s:%d:%d: error[%s]: native execution failed\n  in %s at %s:%d:%d\n",myl_core_source_path,site->line,site->column,code,site->function,myl_core_source_path,site->line,site->column);}
    else length=snprintf(text,sizeof text,"error[%s]: native execution failed\n",code);
    stream_write(&streams[1],text,(size_t)(length<(int)sizeof text?length:(int)sizeof text-1));
    void *pcs[128];int count=os_stack(pcs,128),found=0;
    for(int i=2;i<count;++i){int frames=dwarf_frames((uintptr_t)pcs[i]-1,found?0:1);if(frames)found=1;else if(found)break;}
    flush_all();os_exit(strncmp(code,"R_",2)?2:1);
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

/* `main`'s result is the exit status, truncated to the low 8 bits. */
int32_t myl_core_exit(int64_t status) {
    flush_all();
    leak_report();
    core_io_cleanup();
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
void myl_core_assert_fail(int32_t index) {
    static const char *const codes[] = {"R_ASSERT", "R_REQUIRES", "R_ENSURES", "R_INVARIANT"};
    const myl_core_site *site = &myl_core_sites[index];
    const char *code = site->width >= 0 && site->width < 4 ? codes[site->width] : codes[0];
    stream_flush(&streams[0]);
    char text[2048];
    int len = snprintf(text, sizeof text, "%s:%d:%d: error[%s]: native execution failed%s%s\n  in %s at %s:%d:%d\n",
        myl_core_source_path, site->line, site->column, code, site->operation[0] ? ": " : "", site->operation,
        site->function, myl_core_source_path, site->line, site->column);
    stream_write(&streams[1], text, (size_t)(len < (int)sizeof text ? len : (int)sizeof text - 1));
    trap_frames();
    /* The record: {"version":1,"operation":"MESSAGE"} with the message JSON-escaped. */
    char record[2048];
    size_t used = core_operation_record(record, sizeof record, site->operation);
    stream_write(&streams[1], record, used);
    flush_all();
    os_exit(1);
}

/* Ordered hybrid dictionaries, independent of the Core operation vocabulary.
 * Entries keep their natural key/value layout. The index uses 16-byte SSE2
 * control groups and 32-bit entry numbers, at <= 1/2 occupancy including tombstones.
 * No mutable lookup hint is ever written. */
#include <emmintrin.h>

enum { DICT_EMPTY = 0x80, DICT_DELETED = 0xfe, DICT_SMALL = 8 };
typedef struct {
    uint32_t stride, value_offset, key_kind, key_size;
    myl_layout *layout;
    uint64_t (*hash)(const void *);
    bool (*same)(const void *, const void *);
} core_dict_descriptor;
typedef struct {
    uint32_t slots, used, elen, dead;
    unsigned char data[];
} core_dict_index;
typedef struct {
    const core_dict_descriptor *desc;
    core_dict_index *index;
    uint64_t *hashes;
    unsigned char *dead;
    uint64_t elen;
} core_dict_meta;

/* Published by the integrated text runtime. */
extern uint32_t myl_core_str_hash(const myl_block *);

void myl_core_s2_unsupported(int operation) {
    fprintf(stderr, "error[E_CORE_UNSUPPORTED]: S2 IR operation %d is not implemented\n", operation);
    os_exit(1);
}

static core_dict_meta *dict_meta(const myl_block *dict) { return (core_dict_meta *)(intptr_t)dict->reserved; }
static unsigned char *dict_entry(const myl_block *dict, uint64_t entry) {
    return (unsigned char *)dict + MYL_HEADER + entry * dict_meta(dict)->desc->stride;
}
static bool dict_live(const core_dict_meta *meta, uint64_t entry) {
    return !meta->dead || !(meta->dead[entry >> 3] & (1u << (entry & 7)));
}
static uint32_t *dict_numbers(core_dict_index *index) {
    return (uint32_t *)(index->data + ((index->slots + 15u + 15u) & ~15u));
}
static void dict_control(core_dict_index *index, uint32_t at, unsigned char tag) {
    index->data[at] = tag;
    if (at < 15) index->data[index->slots + at] = tag;
}
static uint64_t dict_hash_bits(uint64_t bits) {
    uint64_t mixed = bits * UINT64_C(0x9e3779b97f4a7c15);
    return mixed ^ (mixed >> 32);
}
static uint64_t dict_hash(const core_dict_descriptor *desc, const void *key) {
    if (desc->key_kind == 3) return desc->hash(key);
    if (desc->key_kind == 2) {
        myl_block *text;
        memcpy(&text, key, sizeof text);
        return dict_hash_bits(myl_core_str_hash(text));
    }
    uint64_t bits = 0;
    memcpy(&bits, key, desc->key_size);
    return dict_hash_bits(bits);
}
static bool dict_same(const core_dict_descriptor *desc, const void *left, const void *right) {
    if (desc->key_kind == 3) return desc->same(left, right);
    if (desc->key_kind != 2) return memcmp(left, right, desc->key_size) == 0;
    myl_block *a, *b;
    memcpy(&a, left, sizeof a);
    memcpy(&b, right, sizeof b);
    return myl_core_str_eq(a, b);
}
static uint32_t dict_home(uint64_t hash, uint32_t slots) { return (uint32_t)(hash >> (64 - __builtin_ctz(slots))); }

/* Empty slots, never deleted ones, are reused: a key deleted and reinserted
 * appends a new dense entry and keeps insertion order. */
static int64_t dict_probe_from(const myl_block *dict, const void *key, uint64_t hash, uint32_t start) {
    core_dict_meta *meta = dict_meta(dict);
    core_dict_index *index = meta->index;
    uint32_t pos = start, step = 0, mask = index->slots - 1;
    __m128i tags = _mm_set1_epi8((char)(hash & 0x7f));
    __m128i empty = _mm_set1_epi8((char)DICT_EMPTY);
    for (;;) {
        __m128i controls = _mm_loadu_si128((const __m128i *)(index->data + pos));
        unsigned candidates = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(controls, tags));
        while (candidates) {
            unsigned bit = (unsigned)__builtin_ctz(candidates);
            uint32_t slot = (pos + bit) & mask;
            uint32_t entry = dict_numbers(index)[slot];
            if (meta->hashes[entry] == hash && dict_same(meta->desc, dict_entry(dict, entry), key)) return entry;
            candidates &= candidates - 1;
        }
        unsigned holes = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(controls, empty));
        if (holes) return -(int64_t)(((pos + (unsigned)__builtin_ctz(holes)) & mask) + 1);
        step += 16;
        pos = (pos + step) & mask;
    }
}

/* Pure lookup: all visible table writes belong to consuming update operations. */
int64_t myl_core_dict_find(const myl_block *dict, const void *key, uint64_t hash) {
    core_dict_meta *meta = dict_meta(dict);
    if (meta->index) return dict_probe_from(dict, key, hash, dict_home(hash, meta->index->slots));
    for (uint64_t i = 0; i < meta->elen; ++i)
        if (dict_live(meta, i) && meta->hashes[i] == hash && dict_same(meta->desc, dict_entry(dict, i), key)) return (int64_t)i;
    return -1;
}

uint64_t myl_core_dict_hash(const myl_block *dict, const void *key) { return dict_hash(dict_meta(dict)->desc, key); }

static void dict_rebuild(myl_block *dict, uint32_t slots) {
    core_dict_meta *meta = dict_meta(dict);
    if (meta->dead) {
        uint64_t next = 0;
        for (uint64_t i = 0; i < meta->elen; ++i) {
            if (!dict_live(meta, i)) continue;
            if (next != i) {
                memmove(dict_entry(dict, next), dict_entry(dict, i), meta->desc->stride);
                meta->hashes[next] = meta->hashes[i];
            }
            ++next;
        }
        meta->elen = next;
        free(meta->dead);
        meta->dead = NULL;
    }
    free(meta->index);
    meta->index = NULL;
    if (dict->len <= DICT_SMALL) return;
    while (slots < 32 || slots < (uint64_t)dict->len * 2) slots = slots ? slots * 2 : 32;
    size_t controls = (slots + 30u) & ~15u;
    core_dict_index *index = malloc(sizeof *index + controls + (size_t)slots * 4);
    if (!index) out_of_memory();
    *index = (core_dict_index){slots, (uint32_t)meta->elen, (uint32_t)meta->elen, 0};
    memset(index->data, DICT_EMPTY, controls);
    meta->index = index;
    /* A rebuild needs only an empty slot: scalar probing avoids full key compares. */
    for (uint32_t entry = 0; entry < meta->elen; ++entry) {
        uint64_t hash = meta->hashes[entry];
        uint32_t slot = dict_home(hash, slots);
        uint32_t step = 0;
        for (;;) {
            uint32_t bit = 0;
            while (bit < 16 && index->data[(slot + bit) & (slots - 1)] != DICT_EMPTY) ++bit;
            if (bit < 16) { slot = (slot + bit) & (slots - 1); break; }
            step += 16;
            slot = (slot + step) & (slots - 1);
        }
        dict_control(index, slot, (unsigned char)(hash & 0x7f));
        dict_numbers(index)[slot] = entry;
    }
}

myl_block *myl_core_dict_new(uint64_t hint, const core_dict_descriptor *desc) {
    if (hint > UINT32_MAX / 2) out_of_memory();
    uint64_t cap = hint > 8 ? hint : 8;
    myl_block *dict = block_new(MYL_KIND_DICT, (int64_t)cap, desc->stride);
    core_dict_meta *meta = calloc(1, sizeof *meta);
    if (!meta) out_of_memory();
    meta->desc = desc;
    meta->hashes = malloc((size_t)cap * sizeof(uint64_t));
    if (!meta->hashes) out_of_memory();
    dict->reserved = (int64_t)(intptr_t)meta;
    return dict;
}

static myl_block *dict_room(myl_block *dict) {
    core_dict_meta *meta = dict_meta(dict);
    if (meta->elen < (uint64_t)dict->cap) return dict;
    uint64_t cap = (uint64_t)dict->cap * 2;
    if (cap > UINT32_MAX / 2) out_of_memory();
    myl_block *grown = block_new(MYL_KIND_DICT, (int64_t)cap, meta->desc->stride);
    grown->len = dict->len;
    grown->reserved = dict->reserved;
    memcpy(block_data(grown), block_data(dict), (size_t)meta->elen * meta->desc->stride);
    uint64_t *hashes = realloc(meta->hashes, (size_t)cap * 8);
    if (!hashes) out_of_memory();
    meta->hashes = hashes;
    if (meta->dead) {
        unsigned char *dead = realloc(meta->dead, (size_t)(cap + 7) / 8);
        if (!dead) out_of_memory();
        memset(dead + ((uint64_t)dict->cap + 7) / 8, 0, (size_t)((cap + 7) / 8 - ((uint64_t)dict->cap + 7) / 8));
        meta->dead = dead;
    }
    block_free(dict);
    return grown;
}

static void dict_release_part(const core_dict_descriptor *desc, unsigned char *entry, bool key, bool value) {
    myl_layout *layout = desc->layout;
    if (!layout) return;
    for (int32_t r = 0; r < layout[1]; ++r) {
        int32_t offset = layout[3 + 2 * r];
        if ((offset < (int32_t)desc->value_offset && !key) || (offset >= (int32_t)desc->value_offset && !value)) continue;
        myl_core_release(reference_at(layout, entry, r));
    }
}

myl_block *myl_core_dict_set(myl_block *dict, int64_t entry, const void *value) {
    core_dict_meta *meta = dict_meta(dict);
    unsigned char *data = dict_entry(dict, (uint64_t)entry);
    dict_release_part(meta->desc, data, false, true);
    memcpy(data + meta->desc->value_offset, value, meta->desc->stride - meta->desc->value_offset);
    return dict;
}

myl_block *myl_core_dict_insert(myl_block *dict, int64_t probe, const void *key, const void *value, bool verify) {
    core_dict_meta *meta = dict_meta(dict);
    uint64_t hash = dict_hash(meta->desc, key);
    if (verify && (probe >= 0 || dict->count != 1)) abort();
    if (!meta->index && dict->len >= DICT_SMALL) {
        /* Crossing the small-table boundary builds the first index after append. */
    } else if (meta->index && meta->index->used * 2 >= meta->index->slots) {
        uint32_t slots = meta->index->slots;
        if ((uint64_t)dict->len * 4 > slots) slots *= 2;
        dict_rebuild(dict, slots);
        probe = myl_core_dict_find(dict, key, hash);
    }
    dict = dict_room(dict);
    meta = dict_meta(dict);
    unsigned char *entry = dict_entry(dict, meta->elen);
    memset(entry, 0, meta->desc->stride);
    memcpy(entry, key, meta->desc->key_size);
    if (value) memcpy(entry + meta->desc->value_offset, value, meta->desc->stride - meta->desc->value_offset);
    meta->hashes[meta->elen] = hash;
    if (meta->index) {
        uint32_t slot = (uint32_t)(-probe - 1);
        if (verify && meta->index->data[slot] != DICT_EMPTY) abort();
        dict_control(meta->index, slot, (unsigned char)(hash & 0x7f));
        dict_numbers(meta->index)[slot] = (uint32_t)meta->elen;
        meta->index->used++;
        meta->index->elen++;
    }
    meta->elen++;
    dict->len++;
    if (!meta->index && dict->len > DICT_SMALL) {
        uint32_t slots = 32;
        while (slots < (uint64_t)dict->cap * 2) slots *= 2;
        dict_rebuild(dict, slots);
    }
    return dict;
}

myl_block *myl_core_dict_remove(myl_block *dict, int64_t entry) {
    core_dict_meta *meta = dict_meta(dict);
    if (!meta->dead) {
        meta->dead = calloc(((size_t)dict->cap + 7) / 8, 1);
        if (!meta->dead) out_of_memory();
    }
    if (meta->index) {
        /* The entry number already identifies the exact key; no equality or hash recomputation. */
        uint64_t hash = meta->hashes[entry];
        uint32_t slots = meta->index->slots, slot = dict_home(hash, slots), step = 0;
        for (;;) {
            __m128i group = _mm_loadu_si128((const __m128i *)(meta->index->data + slot));
            unsigned hits = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(group, _mm_set1_epi8((char)(hash & 0x7f))));
            bool removed = false;
            while (hits) {
                uint32_t at = (slot + (unsigned)__builtin_ctz(hits)) & (slots - 1);
                if (dict_numbers(meta->index)[at] == (uint32_t)entry) {
                    dict_control(meta->index, at, DICT_DELETED);
                    removed = true;
                    break;
                }
                hits &= hits - 1;
            }
            if (removed) break;
            step += 16;
            slot = (slot + step) & (slots - 1);
        }
        meta->index->dead++;
    }
    dict_release_part(meta->desc, dict_entry(dict, (uint64_t)entry), true, true);
    memset(dict_entry(dict, (uint64_t)entry), 0, meta->desc->stride);
    meta->dead[(uint64_t)entry >> 3] |= (unsigned char)(1u << (entry & 7));
    dict->len--;
    return dict;
}

uint64_t myl_core_dict_entries(const myl_block *dict) { return dict_meta(dict)->elen; }
bool myl_core_dict_live(const myl_block *dict, uint64_t entry) { return dict_live(dict_meta(dict), entry); }
int64_t myl_core_dict_ordinal(const myl_block *dict, uint64_t ordinal) {
    core_dict_meta *meta = dict_meta(dict);
    if (!meta->dead) return (int64_t)ordinal;
    for (uint64_t i = 0; i < meta->elen; ++i)
        if (dict_live(meta, i) && ordinal-- == 0) return (int64_t)i;
    abort();
}

myl_block *myl_core_dict_copy(const myl_block *dict) {
    core_dict_meta *meta = dict_meta(dict);
    myl_block *copy = myl_core_dict_new((uint64_t)dict->cap, meta->desc);
    core_dict_meta *other = dict_meta(copy);
    copy->len = dict->len;
    other->elen = meta->elen;
    memcpy(block_data(copy), (const unsigned char *)dict + MYL_HEADER, (size_t)meta->elen * meta->desc->stride);
    memcpy(other->hashes, meta->hashes, (size_t)meta->elen * 8);
    if (meta->dead) {
        size_t bytes = ((size_t)dict->cap + 7) / 8;
        other->dead = malloc(bytes);
        if (!other->dead) out_of_memory();
        memcpy(other->dead, meta->dead, bytes);
    }
    if (meta->index) {
        size_t bytes = sizeof(core_dict_index) + ((meta->index->slots + 30u) & ~15u) + (size_t)meta->index->slots * 4;
        other->index = malloc(bytes);
        if (!other->index) out_of_memory();
        memcpy(other->index, meta->index, bytes);
    }
    if (meta->desc->layout) for (uint64_t i = 0; i < meta->elen; ++i) {
        if (!dict_live(meta, i)) continue;
        for (int32_t r = 0; r < meta->desc->layout[1]; ++r) {
            myl_block *child = reference_at(meta->desc->layout, dict_entry(copy, i), r);
            if (child && child->count != MYL_SATURATED) ++child->count;
        }
    }
    return copy;
}

myl_block *myl_core_dict_clear(myl_block *dict) {
    core_dict_meta *meta = dict_meta(dict);
    for (uint64_t i = 0; i < meta->elen; ++i)
        if (dict_live(meta, i)) dict_release_part(meta->desc, dict_entry(dict, i), true, true);
    free(meta->dead);
    meta->dead = NULL;
    meta->elen = 0;
    dict->len = 0;
    if (meta->index) {
        memset(meta->index->data, DICT_EMPTY, (meta->index->slots + 30u) & ~15u);
        meta->index->used = meta->index->elen = meta->index->dead = 0;
    }
    return dict;
}

/* Join the existing iterative RC worklist; a dictionary of deeply nested
 * managed values uses no recursive teardown and frees its untracked index. */
static void core_dict_free_pending(myl_block *dict, myl_block **pending) {
    core_dict_meta *meta = dict_meta(dict);
    if (meta->desc->layout) for (uint64_t i = 0; i < meta->elen; ++i) {
        if (!dict_live(meta, i)) continue;
        for (int32_t r = 0; r < meta->desc->layout[1]; ++r) {
            myl_block *child = reference_at(meta->desc->layout, dict_entry(dict, i), r);
            if (!child || child->count == MYL_SATURATED) continue;
            if (child->count == 1) {
                child->cap = (int64_t)(intptr_t)*pending;
                *pending = child;
            } else --child->count;
        }
    }
    free(meta->index);
    free(meta->hashes);
    free(meta->dead);
    free(meta);
}

/* A borrowed text span hashes its octets on every use and never escapes. */
extern uint32_t myl_core_span_hash(const unsigned char *, uint64_t);
static bool dict_span_same(const myl_block *dict, uint64_t entry, const unsigned char *data, uint64_t length) {
    myl_block *text;
    memcpy(&text, dict_entry(dict, entry), sizeof text);
    return (uint64_t)text->len == length && memcmp(block_data(text), data, (size_t)length) == 0;
}
int64_t myl_core_dict_find_span(const myl_block *dict, const unsigned char *data, uint64_t length) {
    core_dict_meta *meta = dict_meta(dict);
    uint64_t hash = dict_hash_bits(myl_core_span_hash(data, length));
    if (!meta->index) {
        for (uint64_t entry = 0; entry < meta->elen; ++entry)
            if (dict_live(meta, entry) && meta->hashes[entry] == hash && dict_span_same(dict, entry, data, length)) return (int64_t)entry;
        return -1;
    }
    core_dict_index *index = meta->index;
    uint32_t pos = dict_home(hash, index->slots), step = 0, mask = index->slots - 1;
    for (;;) {
        __m128i controls = _mm_loadu_si128((const __m128i *)(index->data + pos));
        unsigned candidates = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(controls, _mm_set1_epi8((char)(hash & 0x7f))));
        while (candidates) {
            uint32_t slot = (pos + (unsigned)__builtin_ctz(candidates)) & mask;
            uint32_t entry = dict_numbers(index)[slot];
            if (meta->hashes[entry] == hash && dict_span_same(dict, entry, data, length)) return entry;
            candidates &= candidates - 1;
        }
        unsigned holes = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(controls, _mm_set1_epi8((char)DICT_EMPTY)));
        if (holes) return -(int64_t)(((pos + (unsigned)__builtin_ctz(holes)) & mask) + 1);
        step += 16;
        pos = (pos + step) & mask;
    }
}

/* Ported from native_unicode_data.h: static CPython3.14.4 / Unicode16.0.0 printability data.
 * Pinned oracle checks every valid scalar; printable = U+0020 or category
 * initial not C/Z. No build-time Python or host locale is consulted. */
#ifndef MYLANG_CORE_UNICODE_DATA_H
#define MYLANG_CORE_UNICODE_DATA_H
#include <stdint.h>
static const uint32_t core_nonprintable[][2] = {
    {0x0,0x1f},
    {0x7f,0xa0},
    {0xad,0xad},
    {0x378,0x379},
    {0x380,0x383},
    {0x38b,0x38b},
    {0x38d,0x38d},
    {0x3a2,0x3a2},
    {0x530,0x530},
    {0x557,0x558},
    {0x58b,0x58c},
    {0x590,0x590},
    {0x5c8,0x5cf},
    {0x5eb,0x5ee},
    {0x5f5,0x605},
    {0x61c,0x61c},
    {0x6dd,0x6dd},
    {0x70e,0x70f},
    {0x74b,0x74c},
    {0x7b2,0x7bf},
    {0x7fb,0x7fc},
    {0x82e,0x82f},
    {0x83f,0x83f},
    {0x85c,0x85d},
    {0x85f,0x85f},
    {0x86b,0x86f},
    {0x88f,0x896},
    {0x8e2,0x8e2},
    {0x984,0x984},
    {0x98d,0x98e},
    {0x991,0x992},
    {0x9a9,0x9a9},
    {0x9b1,0x9b1},
    {0x9b3,0x9b5},
    {0x9ba,0x9bb},
    {0x9c5,0x9c6},
    {0x9c9,0x9ca},
    {0x9cf,0x9d6},
    {0x9d8,0x9db},
    {0x9de,0x9de},
    {0x9e4,0x9e5},
    {0x9ff,0xa00},
    {0xa04,0xa04},
    {0xa0b,0xa0e},
    {0xa11,0xa12},
    {0xa29,0xa29},
    {0xa31,0xa31},
    {0xa34,0xa34},
    {0xa37,0xa37},
    {0xa3a,0xa3b},
    {0xa3d,0xa3d},
    {0xa43,0xa46},
    {0xa49,0xa4a},
    {0xa4e,0xa50},
    {0xa52,0xa58},
    {0xa5d,0xa5d},
    {0xa5f,0xa65},
    {0xa77,0xa80},
    {0xa84,0xa84},
    {0xa8e,0xa8e},
    {0xa92,0xa92},
    {0xaa9,0xaa9},
    {0xab1,0xab1},
    {0xab4,0xab4},
    {0xaba,0xabb},
    {0xac6,0xac6},
    {0xaca,0xaca},
    {0xace,0xacf},
    {0xad1,0xadf},
    {0xae4,0xae5},
    {0xaf2,0xaf8},
    {0xb00,0xb00},
    {0xb04,0xb04},
    {0xb0d,0xb0e},
    {0xb11,0xb12},
    {0xb29,0xb29},
    {0xb31,0xb31},
    {0xb34,0xb34},
    {0xb3a,0xb3b},
    {0xb45,0xb46},
    {0xb49,0xb4a},
    {0xb4e,0xb54},
    {0xb58,0xb5b},
    {0xb5e,0xb5e},
    {0xb64,0xb65},
    {0xb78,0xb81},
    {0xb84,0xb84},
    {0xb8b,0xb8d},
    {0xb91,0xb91},
    {0xb96,0xb98},
    {0xb9b,0xb9b},
    {0xb9d,0xb9d},
    {0xba0,0xba2},
    {0xba5,0xba7},
    {0xbab,0xbad},
    {0xbba,0xbbd},
    {0xbc3,0xbc5},
    {0xbc9,0xbc9},
    {0xbce,0xbcf},
    {0xbd1,0xbd6},
    {0xbd8,0xbe5},
    {0xbfb,0xbff},
    {0xc0d,0xc0d},
    {0xc11,0xc11},
    {0xc29,0xc29},
    {0xc3a,0xc3b},
    {0xc45,0xc45},
    {0xc49,0xc49},
    {0xc4e,0xc54},
    {0xc57,0xc57},
    {0xc5b,0xc5c},
    {0xc5e,0xc5f},
    {0xc64,0xc65},
    {0xc70,0xc76},
    {0xc8d,0xc8d},
    {0xc91,0xc91},
    {0xca9,0xca9},
    {0xcb4,0xcb4},
    {0xcba,0xcbb},
    {0xcc5,0xcc5},
    {0xcc9,0xcc9},
    {0xcce,0xcd4},
    {0xcd7,0xcdc},
    {0xcdf,0xcdf},
    {0xce4,0xce5},
    {0xcf0,0xcf0},
    {0xcf4,0xcff},
    {0xd0d,0xd0d},
    {0xd11,0xd11},
    {0xd45,0xd45},
    {0xd49,0xd49},
    {0xd50,0xd53},
    {0xd64,0xd65},
    {0xd80,0xd80},
    {0xd84,0xd84},
    {0xd97,0xd99},
    {0xdb2,0xdb2},
    {0xdbc,0xdbc},
    {0xdbe,0xdbf},
    {0xdc7,0xdc9},
    {0xdcb,0xdce},
    {0xdd5,0xdd5},
    {0xdd7,0xdd7},
    {0xde0,0xde5},
    {0xdf0,0xdf1},
    {0xdf5,0xe00},
    {0xe3b,0xe3e},
    {0xe5c,0xe80},
    {0xe83,0xe83},
    {0xe85,0xe85},
    {0xe8b,0xe8b},
    {0xea4,0xea4},
    {0xea6,0xea6},
    {0xebe,0xebf},
    {0xec5,0xec5},
    {0xec7,0xec7},
    {0xecf,0xecf},
    {0xeda,0xedb},
    {0xee0,0xeff},
    {0xf48,0xf48},
    {0xf6d,0xf70},
    {0xf98,0xf98},
    {0xfbd,0xfbd},
    {0xfcd,0xfcd},
    {0xfdb,0xfff},
    {0x10c6,0x10c6},
    {0x10c8,0x10cc},
    {0x10ce,0x10cf},
    {0x1249,0x1249},
    {0x124e,0x124f},
    {0x1257,0x1257},
    {0x1259,0x1259},
    {0x125e,0x125f},
    {0x1289,0x1289},
    {0x128e,0x128f},
    {0x12b1,0x12b1},
    {0x12b6,0x12b7},
    {0x12bf,0x12bf},
    {0x12c1,0x12c1},
    {0x12c6,0x12c7},
    {0x12d7,0x12d7},
    {0x1311,0x1311},
    {0x1316,0x1317},
    {0x135b,0x135c},
    {0x137d,0x137f},
    {0x139a,0x139f},
    {0x13f6,0x13f7},
    {0x13fe,0x13ff},
    {0x1680,0x1680},
    {0x169d,0x169f},
    {0x16f9,0x16ff},
    {0x1716,0x171e},
    {0x1737,0x173f},
    {0x1754,0x175f},
    {0x176d,0x176d},
    {0x1771,0x1771},
    {0x1774,0x177f},
    {0x17de,0x17df},
    {0x17ea,0x17ef},
    {0x17fa,0x17ff},
    {0x180e,0x180e},
    {0x181a,0x181f},
    {0x1879,0x187f},
    {0x18ab,0x18af},
    {0x18f6,0x18ff},
    {0x191f,0x191f},
    {0x192c,0x192f},
    {0x193c,0x193f},
    {0x1941,0x1943},
    {0x196e,0x196f},
    {0x1975,0x197f},
    {0x19ac,0x19af},
    {0x19ca,0x19cf},
    {0x19db,0x19dd},
    {0x1a1c,0x1a1d},
    {0x1a5f,0x1a5f},
    {0x1a7d,0x1a7e},
    {0x1a8a,0x1a8f},
    {0x1a9a,0x1a9f},
    {0x1aae,0x1aaf},
    {0x1acf,0x1aff},
    {0x1b4d,0x1b4d},
    {0x1bf4,0x1bfb},
    {0x1c38,0x1c3a},
    {0x1c4a,0x1c4c},
    {0x1c8b,0x1c8f},
    {0x1cbb,0x1cbc},
    {0x1cc8,0x1ccf},
    {0x1cfb,0x1cff},
    {0x1f16,0x1f17},
    {0x1f1e,0x1f1f},
    {0x1f46,0x1f47},
    {0x1f4e,0x1f4f},
    {0x1f58,0x1f58},
    {0x1f5a,0x1f5a},
    {0x1f5c,0x1f5c},
    {0x1f5e,0x1f5e},
    {0x1f7e,0x1f7f},
    {0x1fb5,0x1fb5},
    {0x1fc5,0x1fc5},
    {0x1fd4,0x1fd5},
    {0x1fdc,0x1fdc},
    {0x1ff0,0x1ff1},
    {0x1ff5,0x1ff5},
    {0x1fff,0x200f},
    {0x2028,0x202f},
    {0x205f,0x206f},
    {0x2072,0x2073},
    {0x208f,0x208f},
    {0x209d,0x209f},
    {0x20c1,0x20cf},
    {0x20f1,0x20ff},
    {0x218c,0x218f},
    {0x242a,0x243f},
    {0x244b,0x245f},
    {0x2b74,0x2b75},
    {0x2b96,0x2b96},
    {0x2cf4,0x2cf8},
    {0x2d26,0x2d26},
    {0x2d28,0x2d2c},
    {0x2d2e,0x2d2f},
    {0x2d68,0x2d6e},
    {0x2d71,0x2d7e},
    {0x2d97,0x2d9f},
    {0x2da7,0x2da7},
    {0x2daf,0x2daf},
    {0x2db7,0x2db7},
    {0x2dbf,0x2dbf},
    {0x2dc7,0x2dc7},
    {0x2dcf,0x2dcf},
    {0x2dd7,0x2dd7},
    {0x2ddf,0x2ddf},
    {0x2e5e,0x2e7f},
    {0x2e9a,0x2e9a},
    {0x2ef4,0x2eff},
    {0x2fd6,0x2fef},
    {0x3000,0x3000},
    {0x3040,0x3040},
    {0x3097,0x3098},
    {0x3100,0x3104},
    {0x3130,0x3130},
    {0x318f,0x318f},
    {0x31e6,0x31ee},
    {0x321f,0x321f},
    {0xa48d,0xa48f},
    {0xa4c7,0xa4cf},
    {0xa62c,0xa63f},
    {0xa6f8,0xa6ff},
    {0xa7ce,0xa7cf},
    {0xa7d2,0xa7d2},
    {0xa7d4,0xa7d4},
    {0xa7dd,0xa7f1},
    {0xa82d,0xa82f},
    {0xa83a,0xa83f},
    {0xa878,0xa87f},
    {0xa8c6,0xa8cd},
    {0xa8da,0xa8df},
    {0xa954,0xa95e},
    {0xa97d,0xa97f},
    {0xa9ce,0xa9ce},
    {0xa9da,0xa9dd},
    {0xa9ff,0xa9ff},
    {0xaa37,0xaa3f},
    {0xaa4e,0xaa4f},
    {0xaa5a,0xaa5b},
    {0xaac3,0xaada},
    {0xaaf7,0xab00},
    {0xab07,0xab08},
    {0xab0f,0xab10},
    {0xab17,0xab1f},
    {0xab27,0xab27},
    {0xab2f,0xab2f},
    {0xab6c,0xab6f},
    {0xabee,0xabef},
    {0xabfa,0xabff},
    {0xd7a4,0xd7af},
    {0xd7c7,0xd7ca},
    {0xd7fc,0xd7ff},
    {0xe000,0xf8ff},
    {0xfa6e,0xfa6f},
    {0xfada,0xfaff},
    {0xfb07,0xfb12},
    {0xfb18,0xfb1c},
    {0xfb37,0xfb37},
    {0xfb3d,0xfb3d},
    {0xfb3f,0xfb3f},
    {0xfb42,0xfb42},
    {0xfb45,0xfb45},
    {0xfbc3,0xfbd2},
    {0xfd90,0xfd91},
    {0xfdc8,0xfdce},
    {0xfdd0,0xfdef},
    {0xfe1a,0xfe1f},
    {0xfe53,0xfe53},
    {0xfe67,0xfe67},
    {0xfe6c,0xfe6f},
    {0xfe75,0xfe75},
    {0xfefd,0xff00},
    {0xffbf,0xffc1},
    {0xffc8,0xffc9},
    {0xffd0,0xffd1},
    {0xffd8,0xffd9},
    {0xffdd,0xffdf},
    {0xffe7,0xffe7},
    {0xffef,0xfffb},
    {0xfffe,0xffff},
    {0x1000c,0x1000c},
    {0x10027,0x10027},
    {0x1003b,0x1003b},
    {0x1003e,0x1003e},
    {0x1004e,0x1004f},
    {0x1005e,0x1007f},
    {0x100fb,0x100ff},
    {0x10103,0x10106},
    {0x10134,0x10136},
    {0x1018f,0x1018f},
    {0x1019d,0x1019f},
    {0x101a1,0x101cf},
    {0x101fe,0x1027f},
    {0x1029d,0x1029f},
    {0x102d1,0x102df},
    {0x102fc,0x102ff},
    {0x10324,0x1032c},
    {0x1034b,0x1034f},
    {0x1037b,0x1037f},
    {0x1039e,0x1039e},
    {0x103c4,0x103c7},
    {0x103d6,0x103ff},
    {0x1049e,0x1049f},
    {0x104aa,0x104af},
    {0x104d4,0x104d7},
    {0x104fc,0x104ff},
    {0x10528,0x1052f},
    {0x10564,0x1056e},
    {0x1057b,0x1057b},
    {0x1058b,0x1058b},
    {0x10593,0x10593},
    {0x10596,0x10596},
    {0x105a2,0x105a2},
    {0x105b2,0x105b2},
    {0x105ba,0x105ba},
    {0x105bd,0x105bf},
    {0x105f4,0x105ff},
    {0x10737,0x1073f},
    {0x10756,0x1075f},
    {0x10768,0x1077f},
    {0x10786,0x10786},
    {0x107b1,0x107b1},
    {0x107bb,0x107ff},
    {0x10806,0x10807},
    {0x10809,0x10809},
    {0x10836,0x10836},
    {0x10839,0x1083b},
    {0x1083d,0x1083e},
    {0x10856,0x10856},
    {0x1089f,0x108a6},
    {0x108b0,0x108df},
    {0x108f3,0x108f3},
    {0x108f6,0x108fa},
    {0x1091c,0x1091e},
    {0x1093a,0x1093e},
    {0x10940,0x1097f},
    {0x109b8,0x109bb},
    {0x109d0,0x109d1},
    {0x10a04,0x10a04},
    {0x10a07,0x10a0b},
    {0x10a14,0x10a14},
    {0x10a18,0x10a18},
    {0x10a36,0x10a37},
    {0x10a3b,0x10a3e},
    {0x10a49,0x10a4f},
    {0x10a59,0x10a5f},
    {0x10aa0,0x10abf},
    {0x10ae7,0x10aea},
    {0x10af7,0x10aff},
    {0x10b36,0x10b38},
    {0x10b56,0x10b57},
    {0x10b73,0x10b77},
    {0x10b92,0x10b98},
    {0x10b9d,0x10ba8},
    {0x10bb0,0x10bff},
    {0x10c49,0x10c7f},
    {0x10cb3,0x10cbf},
    {0x10cf3,0x10cf9},
    {0x10d28,0x10d2f},
    {0x10d3a,0x10d3f},
    {0x10d66,0x10d68},
    {0x10d86,0x10d8d},
    {0x10d90,0x10e5f},
    {0x10e7f,0x10e7f},
    {0x10eaa,0x10eaa},
    {0x10eae,0x10eaf},
    {0x10eb2,0x10ec1},
    {0x10ec5,0x10efb},
    {0x10f28,0x10f2f},
    {0x10f5a,0x10f6f},
    {0x10f8a,0x10faf},
    {0x10fcc,0x10fdf},
    {0x10ff7,0x10fff},
    {0x1104e,0x11051},
    {0x11076,0x1107e},
    {0x110bd,0x110bd},
    {0x110c3,0x110cf},
    {0x110e9,0x110ef},
    {0x110fa,0x110ff},
    {0x11135,0x11135},
    {0x11148,0x1114f},
    {0x11177,0x1117f},
    {0x111e0,0x111e0},
    {0x111f5,0x111ff},
    {0x11212,0x11212},
    {0x11242,0x1127f},
    {0x11287,0x11287},
    {0x11289,0x11289},
    {0x1128e,0x1128e},
    {0x1129e,0x1129e},
    {0x112aa,0x112af},
    {0x112eb,0x112ef},
    {0x112fa,0x112ff},
    {0x11304,0x11304},
    {0x1130d,0x1130e},
    {0x11311,0x11312},
    {0x11329,0x11329},
    {0x11331,0x11331},
    {0x11334,0x11334},
    {0x1133a,0x1133a},
    {0x11345,0x11346},
    {0x11349,0x1134a},
    {0x1134e,0x1134f},
    {0x11351,0x11356},
    {0x11358,0x1135c},
    {0x11364,0x11365},
    {0x1136d,0x1136f},
    {0x11375,0x1137f},
    {0x1138a,0x1138a},
    {0x1138c,0x1138d},
    {0x1138f,0x1138f},
    {0x113b6,0x113b6},
    {0x113c1,0x113c1},
    {0x113c3,0x113c4},
    {0x113c6,0x113c6},
    {0x113cb,0x113cb},
    {0x113d6,0x113d6},
    {0x113d9,0x113e0},
    {0x113e3,0x113ff},
    {0x1145c,0x1145c},
    {0x11462,0x1147f},
    {0x114c8,0x114cf},
    {0x114da,0x1157f},
    {0x115b6,0x115b7},
    {0x115de,0x115ff},
    {0x11645,0x1164f},
    {0x1165a,0x1165f},
    {0x1166d,0x1167f},
    {0x116ba,0x116bf},
    {0x116ca,0x116cf},
    {0x116e4,0x116ff},
    {0x1171b,0x1171c},
    {0x1172c,0x1172f},
    {0x11747,0x117ff},
    {0x1183c,0x1189f},
    {0x118f3,0x118fe},
    {0x11907,0x11908},
    {0x1190a,0x1190b},
    {0x11914,0x11914},
    {0x11917,0x11917},
    {0x11936,0x11936},
    {0x11939,0x1193a},
    {0x11947,0x1194f},
    {0x1195a,0x1199f},
    {0x119a8,0x119a9},
    {0x119d8,0x119d9},
    {0x119e5,0x119ff},
    {0x11a48,0x11a4f},
    {0x11aa3,0x11aaf},
    {0x11af9,0x11aff},
    {0x11b0a,0x11bbf},
    {0x11be2,0x11bef},
    {0x11bfa,0x11bff},
    {0x11c09,0x11c09},
    {0x11c37,0x11c37},
    {0x11c46,0x11c4f},
    {0x11c6d,0x11c6f},
    {0x11c90,0x11c91},
    {0x11ca8,0x11ca8},
    {0x11cb7,0x11cff},
    {0x11d07,0x11d07},
    {0x11d0a,0x11d0a},
    {0x11d37,0x11d39},
    {0x11d3b,0x11d3b},
    {0x11d3e,0x11d3e},
    {0x11d48,0x11d4f},
    {0x11d5a,0x11d5f},
    {0x11d66,0x11d66},
    {0x11d69,0x11d69},
    {0x11d8f,0x11d8f},
    {0x11d92,0x11d92},
    {0x11d99,0x11d9f},
    {0x11daa,0x11edf},
    {0x11ef9,0x11eff},
    {0x11f11,0x11f11},
    {0x11f3b,0x11f3d},
    {0x11f5b,0x11faf},
    {0x11fb1,0x11fbf},
    {0x11ff2,0x11ffe},
    {0x1239a,0x123ff},
    {0x1246f,0x1246f},
    {0x12475,0x1247f},
    {0x12544,0x12f8f},
    {0x12ff3,0x12fff},
    {0x13430,0x1343f},
    {0x13456,0x1345f},
    {0x143fb,0x143ff},
    {0x14647,0x160ff},
    {0x1613a,0x167ff},
    {0x16a39,0x16a3f},
    {0x16a5f,0x16a5f},
    {0x16a6a,0x16a6d},
    {0x16abf,0x16abf},
    {0x16aca,0x16acf},
    {0x16aee,0x16aef},
    {0x16af6,0x16aff},
    {0x16b46,0x16b4f},
    {0x16b5a,0x16b5a},
    {0x16b62,0x16b62},
    {0x16b78,0x16b7c},
    {0x16b90,0x16d3f},
    {0x16d7a,0x16e3f},
    {0x16e9b,0x16eff},
    {0x16f4b,0x16f4e},
    {0x16f88,0x16f8e},
    {0x16fa0,0x16fdf},
    {0x16fe5,0x16fef},
    {0x16ff2,0x16fff},
    {0x187f8,0x187ff},
    {0x18cd6,0x18cfe},
    {0x18d09,0x1afef},
    {0x1aff4,0x1aff4},
    {0x1affc,0x1affc},
    {0x1afff,0x1afff},
    {0x1b123,0x1b131},
    {0x1b133,0x1b14f},
    {0x1b153,0x1b154},
    {0x1b156,0x1b163},
    {0x1b168,0x1b16f},
    {0x1b2fc,0x1bbff},
    {0x1bc6b,0x1bc6f},
    {0x1bc7d,0x1bc7f},
    {0x1bc89,0x1bc8f},
    {0x1bc9a,0x1bc9b},
    {0x1bca0,0x1cbff},
    {0x1ccfa,0x1ccff},
    {0x1ceb4,0x1ceff},
    {0x1cf2e,0x1cf2f},
    {0x1cf47,0x1cf4f},
    {0x1cfc4,0x1cfff},
    {0x1d0f6,0x1d0ff},
    {0x1d127,0x1d128},
    {0x1d173,0x1d17a},
    {0x1d1eb,0x1d1ff},
    {0x1d246,0x1d2bf},
    {0x1d2d4,0x1d2df},
    {0x1d2f4,0x1d2ff},
    {0x1d357,0x1d35f},
    {0x1d379,0x1d3ff},
    {0x1d455,0x1d455},
    {0x1d49d,0x1d49d},
    {0x1d4a0,0x1d4a1},
    {0x1d4a3,0x1d4a4},
    {0x1d4a7,0x1d4a8},
    {0x1d4ad,0x1d4ad},
    {0x1d4ba,0x1d4ba},
    {0x1d4bc,0x1d4bc},
    {0x1d4c4,0x1d4c4},
    {0x1d506,0x1d506},
    {0x1d50b,0x1d50c},
    {0x1d515,0x1d515},
    {0x1d51d,0x1d51d},
    {0x1d53a,0x1d53a},
    {0x1d53f,0x1d53f},
    {0x1d545,0x1d545},
    {0x1d547,0x1d549},
    {0x1d551,0x1d551},
    {0x1d6a6,0x1d6a7},
    {0x1d7cc,0x1d7cd},
    {0x1da8c,0x1da9a},
    {0x1daa0,0x1daa0},
    {0x1dab0,0x1deff},
    {0x1df1f,0x1df24},
    {0x1df2b,0x1dfff},
    {0x1e007,0x1e007},
    {0x1e019,0x1e01a},
    {0x1e022,0x1e022},
    {0x1e025,0x1e025},
    {0x1e02b,0x1e02f},
    {0x1e06e,0x1e08e},
    {0x1e090,0x1e0ff},
    {0x1e12d,0x1e12f},
    {0x1e13e,0x1e13f},
    {0x1e14a,0x1e14d},
    {0x1e150,0x1e28f},
    {0x1e2af,0x1e2bf},
    {0x1e2fa,0x1e2fe},
    {0x1e300,0x1e4cf},
    {0x1e4fa,0x1e5cf},
    {0x1e5fb,0x1e5fe},
    {0x1e600,0x1e7df},
    {0x1e7e7,0x1e7e7},
    {0x1e7ec,0x1e7ec},
    {0x1e7ef,0x1e7ef},
    {0x1e7ff,0x1e7ff},
    {0x1e8c5,0x1e8c6},
    {0x1e8d7,0x1e8ff},
    {0x1e94c,0x1e94f},
    {0x1e95a,0x1e95d},
    {0x1e960,0x1ec70},
    {0x1ecb5,0x1ed00},
    {0x1ed3e,0x1edff},
    {0x1ee04,0x1ee04},
    {0x1ee20,0x1ee20},
    {0x1ee23,0x1ee23},
    {0x1ee25,0x1ee26},
    {0x1ee28,0x1ee28},
    {0x1ee33,0x1ee33},
    {0x1ee38,0x1ee38},
    {0x1ee3a,0x1ee3a},
    {0x1ee3c,0x1ee41},
    {0x1ee43,0x1ee46},
    {0x1ee48,0x1ee48},
    {0x1ee4a,0x1ee4a},
    {0x1ee4c,0x1ee4c},
    {0x1ee50,0x1ee50},
    {0x1ee53,0x1ee53},
    {0x1ee55,0x1ee56},
    {0x1ee58,0x1ee58},
    {0x1ee5a,0x1ee5a},
    {0x1ee5c,0x1ee5c},
    {0x1ee5e,0x1ee5e},
    {0x1ee60,0x1ee60},
    {0x1ee63,0x1ee63},
    {0x1ee65,0x1ee66},
    {0x1ee6b,0x1ee6b},
    {0x1ee73,0x1ee73},
    {0x1ee78,0x1ee78},
    {0x1ee7d,0x1ee7d},
    {0x1ee7f,0x1ee7f},
    {0x1ee8a,0x1ee8a},
    {0x1ee9c,0x1eea0},
    {0x1eea4,0x1eea4},
    {0x1eeaa,0x1eeaa},
    {0x1eebc,0x1eeef},
    {0x1eef2,0x1efff},
    {0x1f02c,0x1f02f},
    {0x1f094,0x1f09f},
    {0x1f0af,0x1f0b0},
    {0x1f0c0,0x1f0c0},
    {0x1f0d0,0x1f0d0},
    {0x1f0f6,0x1f0ff},
    {0x1f1ae,0x1f1e5},
    {0x1f203,0x1f20f},
    {0x1f23c,0x1f23f},
    {0x1f249,0x1f24f},
    {0x1f252,0x1f25f},
    {0x1f266,0x1f2ff},
    {0x1f6d8,0x1f6db},
    {0x1f6ed,0x1f6ef},
    {0x1f6fd,0x1f6ff},
    {0x1f777,0x1f77a},
    {0x1f7da,0x1f7df},
    {0x1f7ec,0x1f7ef},
    {0x1f7f1,0x1f7ff},
    {0x1f80c,0x1f80f},
    {0x1f848,0x1f84f},
    {0x1f85a,0x1f85f},
    {0x1f888,0x1f88f},
    {0x1f8ae,0x1f8af},
    {0x1f8bc,0x1f8bf},
    {0x1f8c2,0x1f8ff},
    {0x1fa54,0x1fa5f},
    {0x1fa6e,0x1fa6f},
    {0x1fa7d,0x1fa7f},
    {0x1fa8a,0x1fa8e},
    {0x1fac7,0x1facd},
    {0x1fadd,0x1fade},
    {0x1faea,0x1faef},
    {0x1faf9,0x1faff},
    {0x1fb93,0x1fb93},
    {0x1fbfa,0x1ffff},
    {0x2a6e0,0x2a6ff},
    {0x2b73a,0x2b73f},
    {0x2b81e,0x2b81f},
    {0x2cea2,0x2ceaf},
    {0x2ebe1,0x2ebef},
    {0x2ee5e,0x2f7ff},
    {0x2fa1e,0x2ffff},
    {0x3134b,0x3134f},
    {0x323b0,0xe00ff},
    {0xe01f0,0x10ffff},
};
#endif

/* S2 text ABI: shared str/bytes leaf blocks; header flags and cache are §3.1. */
enum { MYL_TEXT_ASCII = 1u << 8, MYL_TEXT_HASHED = 2u << 8,
       MYL_TEXT_SCALARS = 4u << 8, MYL_TEXT_CURSOR = 8u << 8 };

static bool core_text_ascii(const unsigned char *bytes, uint64_t len) {
    uint64_t at = 0;
    for (; at + 8 <= len; at += 8) {
        uint64_t word;
        memcpy(&word, bytes + at, 8);
        if (word & UINT64_C(0x8080808080808080)) return false;
    }
    for (; at < len; ++at) if (bytes[at] & 0x80) return false;
    return true;
}

static void core_text_publish(myl_block *text) {
    text->kind &= ~(MYL_TEXT_ASCII | MYL_TEXT_HASHED | MYL_TEXT_SCALARS | MYL_TEXT_CURSOR);
    text->reserved = 0;
    if (core_text_ascii(block_data(text), (uint64_t)text->len)) text->kind |= MYL_TEXT_ASCII;
}

static uint64_t core_text_fold(uint64_t a, uint64_t b) {
    __uint128_t product = (__uint128_t)a * b;
    return (uint64_t)product ^ (uint64_t)(product >> 64);
}

/* Same deterministic word-at-a-time octet hash as the oracle; no old runtime link. */
uint32_t myl_core_span_hash(const unsigned char *bytes, uint64_t length) {
    size_t len = (size_t)length;
    const uint64_t word_key = UINT64_C(0xa0761d6478bd642f), state_key = UINT64_C(0xe7037ed1a0b428db);
    uint64_t state = UINT64_C(0x243f6a8885a308d3) ^ len, hash;
    if (len <= 8) {
        uint64_t low = 0, high = 0;
        if (len >= 4) {
            uint32_t first, last;
            memcpy(&first, bytes, 4); memcpy(&last, bytes + len - 4, 4);
            low = first; high = last;
        } else if (len) low = (uint64_t)bytes[0] << 16 | (uint64_t)bytes[len >> 1] << 8 | bytes[len - 1];
        hash = core_text_fold(low ^ word_key, high ^ state ^ state_key);
    } else {
        uint64_t word;
        for (size_t at = 0; at + 8 < len; at += 8) {
            memcpy(&word, bytes + at, 8);
            state = core_text_fold(word ^ word_key, state ^ state_key);
        }
        memcpy(&word, bytes + len - 8, 8);
        hash = core_text_fold(word ^ word_key, state ^ state_key);
    }
    return (uint32_t)(hash ^ (hash >> 32));
}

uint32_t myl_core_str_hash(const myl_block *text) {
    if (text->kind & MYL_TEXT_HASHED) return (uint32_t)text->reserved;
    uint32_t folded = myl_core_span_hash((const unsigned char *)text + MYL_HEADER, (uint64_t)text->len);
    if (text->count != MYL_SATURATED) {
        myl_block *mutable = (myl_block *)text;
        mutable->reserved = (int64_t)(((uint64_t)text->reserved & UINT64_C(0xffffffff00000000)) | folded);
        mutable->kind |= MYL_TEXT_HASHED;
    }
    return folded;
}

/* Equal lengths, then the bytes. Texts of one length that differ usually differ near
   an end, so a pair past 256 bytes compares its first and last eight bytes before the
   bulk compare, which a mismatch at the end would otherwise pay for in full (the old
   runtime's `myl_native_text_equal`). Shorter pairs go straight to `memcmp`: an extra
   path for them costs more than it saves. */
bool myl_core_str_eq(const myl_block *a, const myl_block *b) {
    if (a == b) return true;
    if (a->len != b->len) return false;
    if ((a->kind & b->kind & MYL_TEXT_HASHED) && (uint32_t)a->reserved != (uint32_t)b->reserved) return false;
    const size_t count = (size_t)a->len;
    const unsigned char *left = (const unsigned char *)a + MYL_HEADER, *right = (const unsigned char *)b + MYL_HEADER;
    if (count > 256) {
        uint64_t first_a, first_b, last_a, last_b;
        memcpy(&first_a, left, 8); memcpy(&first_b, right, 8);
        memcpy(&last_a, left + count - 8, 8); memcpy(&last_b, right + count - 8, 8);
        if ((first_a ^ first_b) | (last_a ^ last_b)) return false;
    }
    return memcmp(left, right, count) == 0;
}

uint64_t myl_core_str_chars(const myl_block *text) {
    if (text->kind & MYL_TEXT_ASCII) return (uint64_t)text->len;
    if (text->kind & MYL_TEXT_SCALARS) return (uint64_t)text->reserved >> 32;
    const unsigned char *bytes = (const unsigned char *)text + MYL_HEADER;
    uint64_t scalars = 0;
    for (int64_t i = 0; i < text->len; ++i) scalars += (bytes[i] & 0xc0) != 0x80;
    if (text->count != MYL_SATURATED && scalars <= UINT32_MAX) {
        myl_block *mutable = (myl_block *)text;
        mutable->reserved = (int64_t)((scalars << 32) | (uint32_t)text->reserved);
        mutable->kind |= MYL_TEXT_SCALARS;
    }
    return scalars;
}

uint64_t myl_core_str_offset(const myl_block *text, uint64_t scalar) {
    if (text->kind & MYL_TEXT_ASCII) return scalar < (uint64_t)text->len ? scalar : (uint64_t)text->len;
    const unsigned char *bytes = (const unsigned char *)text + MYL_HEADER;
    uint64_t at = 0, index = 0;
    if ((text->kind & MYL_TEXT_CURSOR) && scalar <= UINT32_MAX) {
        uint64_t cursor = (uint64_t)text->cap;
        if ((uint32_t)(cursor >> 32) <= scalar) { index = cursor >> 32; at = (uint32_t)cursor; }
    }
    while (at + 32 <= (uint64_t)text->len) {
        uint64_t count = 0;
        for (unsigned word_at = 0; word_at < 32; word_at += 8) {
            uint64_t word;
            memcpy(&word, bytes + at + word_at, 8);
            uint64_t continuation = (word & ~(word << 1)) & UINT64_C(0x8080808080808080);
            count += 8 - (uint64_t)__builtin_popcountll(continuation);
        }
        if (index + count >= scalar) break;
        index += count; at += 32;
        while (at < (uint64_t)text->len && (bytes[at] & 0xc0) == 0x80) ++at;
    }
    while (at < (uint64_t)text->len && index < scalar) { ++at; while (at < (uint64_t)text->len && (bytes[at] & 0xc0) == 0x80) ++at; ++index; }
    if (text->count != MYL_SATURATED && text->len >= 256 && text->len <= UINT32_MAX && scalar <= UINT32_MAX && ((text->kind & MYL_TEXT_CURSOR) || text->cap == text->len)) {
        ((myl_block *)text)->cap = (int64_t)((scalar << 32) | at);
        ((myl_block *)text)->kind |= MYL_TEXT_CURSOR;
    }
    return at;
}

uint64_t myl_core_ir_str_width(myl_block *text, uint64_t offset) {
    if (offset >= (uint64_t)text->len) myl_core_s2_unsupported(-1);
    unsigned char c = block_data(text)[offset];
    return c < 0x80 ? 1 : c < 0xe0 ? 2 : c < 0xf0 ? 3 : 4;
}

uint32_t myl_core_ir_str_code(myl_block *text, uint64_t offset) {
    uint64_t width = myl_core_ir_str_width(text, offset);
    const unsigned char *bytes = block_data(text) + offset;
    uint32_t point = bytes[0] & (width == 1 ? 0x7f : width == 2 ? 0x1f : width == 3 ? 0xf : 7);
    for (uint64_t i = 1; i < width; ++i) point = (point << 6) | (bytes[i] & 0x3f);
    return point;
}

/* Runtime table of immortal one-byte scalars. Initialized before its first use. */
static struct { myl_block header; unsigned char data[32]; } core_ascii[128];
static bool core_ascii_ready;
static myl_block *core_ascii_char(unsigned char ch) {
    if (!core_ascii_ready) {
        for (unsigned i = 0; i < 128; ++i) {
            core_ascii[i].header = (myl_block){MYL_SATURATED, MYL_KIND_STR | MYL_TEXT_ASCII | MYL_TEXT_SCALARS, 1, 1, INT64_C(1) << 32};
            core_ascii[i].data[0] = (unsigned char)i;
            core_ascii[i].header.reserved |= myl_core_str_hash(&core_ascii[i].header);
            core_ascii[i].header.kind |= MYL_TEXT_HASHED;
        }
        core_ascii_ready = true;
    }
    return &core_ascii[ch].header;
}

myl_block *myl_core_ir_str_char(myl_block *text, uint64_t offset) {
    uint64_t width = myl_core_ir_str_width(text, offset);
    if (width == 1) return core_ascii_char(block_data(text)[offset]);
    return str_from((const char *)block_data(text) + offset, (size_t)width);
}

myl_block *myl_core_ir_str_from_view(const unsigned char *data, uint64_t len) { return str_from((const char *)data, (size_t)len); }
myl_block *myl_core_ir_span_materialize(const unsigned char *data, uint64_t len) { return myl_core_ir_str_from_view(data, len); }

static myl_block *str_new(int64_t len) {
    myl_block *text = block_new(MYL_KIND_STR, len, 1);
    text->len = len;
    block_data(text)[len] = 0;
    return text;
}

myl_block *myl_core_str_concat(const myl_block *a, const myl_block *b) {
    myl_block *text = str_new(a->len + b->len);
    memcpy(block_data(text), (const unsigned char *)a + MYL_HEADER, (size_t)a->len);
    memcpy(block_data(text) + a->len, (const unsigned char *)b + MYL_HEADER, (size_t)b->len);
    core_text_publish(text);
    return text;
}

static inline void core_text_copy_short(unsigned char *output, const unsigned char *input, size_t count) {
    if (count>=8) {
        uint64_t first,last;
        memcpy(&first,input,8); memcpy(&last,input+count-8,8);
        memcpy(output,&first,8); memcpy(output+count-8,&last,8);
    } else if (count>=4) {
        uint32_t first,last;
        memcpy(&first,input,4); memcpy(&last,input+count-4,4);
        memcpy(output,&first,4); memcpy(output+count-4,&last,4);
    } else if (count>=2) {
        uint16_t first,last;
        memcpy(&first,input,2); memcpy(&last,input+count-2,2);
        memcpy(output,&first,2); memcpy(output+count-2,&last,2);
    } else if (count) output[0]=input[0];
}

static inline myl_block *core_text_append_bytes(myl_block *a, const unsigned char *bytes, int64_t count, bool ascii) {
    int64_t len = a->len + count;
    if (a->count != 1) myl_core_s2_unsupported(-1);
    if (a->kind & MYL_TEXT_CURSOR) { a->cap = a->len; a->kind &= ~MYL_TEXT_CURSOR; }
    if (len > a->cap) {
        int64_t cap = a->cap > 0 ? a->cap * 2 : 16;
        if (cap < len) cap = len;
        size_t room;
        myl_block *grown = block_alloc(MYL_KIND_STR, (size_t)cap + 1, &room);
        grown->cap = (int64_t)room - 1;
        grown->len = a->len;
        memcpy(block_data(grown), block_data(a), (size_t)a->len);
        if (count <= 16) core_text_copy_short(block_data(grown) + a->len, bytes, (size_t)count);
        else memcpy(block_data(grown) + a->len, bytes, (size_t)count);
        block_free(a);
        a = grown;
    } else if (count <= 16) core_text_copy_short(block_data(a) + a->len, bytes, (size_t)count);
    else memmove(block_data(a) + a->len, bytes, (size_t)count);
    a->len = len;
    block_data(a)[len] = 0;
    a->kind &= ~(MYL_TEXT_ASCII | MYL_TEXT_HASHED | MYL_TEXT_SCALARS | MYL_TEXT_CURSOR);
    if (ascii) a->kind |= MYL_TEXT_ASCII;
    a->reserved = 0;
    return a;
}

myl_block *myl_core_ir_str_append(myl_block *a, const myl_block *b) {
    bool ascii = (a->kind & b->kind & MYL_TEXT_ASCII) != 0;
    return core_text_append_bytes(a, (const unsigned char *)b + MYL_HEADER, b->len, ascii);
}

myl_block *myl_core_ir_str_append_char(myl_block *a, myl_block *text, uint64_t offset) {
    uint64_t width = myl_core_ir_str_width(text, offset);
    unsigned char bytes[4];
    /* Capture the complete scalar before a cursor reset, growth or alias free.
     * The bounded copy reads exactly width bytes, including three-byte UTF-8. */
    core_text_copy_short(bytes, block_data(text) + offset, (size_t)width);
    bool ascii = width == 1 && (a->kind & MYL_TEXT_ASCII) != 0;
    return core_text_append_bytes(a, bytes, (int64_t)width, ascii);
}

static int64_t core_text_clamp(int64_t index, int64_t len) {
    if (index < 0) index += len;
    return index < 0 ? 0 : index > len ? len : index;
}

myl_block *myl_core_ir_str_slice(myl_block *text, int64_t start, int64_t end) {
    int64_t len = (int64_t)myl_core_str_chars(text);
    start = core_text_clamp(start, len); end = core_text_clamp(end, len);
    uint64_t a = myl_core_str_offset(text, (uint64_t)start), b = end > start ? myl_core_str_offset(text, (uint64_t)end) : a;
    return str_from((const char *)block_data(text) + a, (size_t)(b - a));
}

static inline void core_text_copy(unsigned char *output, const unsigned char *input, size_t count) {
    if (count>16) { memcpy(output,input,count); return; }
    core_text_copy_short(output,input,count);
}
/* The sizing pass proves every copy in this leaf is at most sixteen octets.
 * Choose the separator's bounded word width once, then keep its endpoints in
 * registers while the output cursor advances. Only bounded fixed-size copies
 * appear in this leaf, and no input aliases the fresh output.
 * The two overlapping stores cover any separator in the chosen size band. */
#define CORE_JOIN_SHORT_WORDS(Word) do { \
    Word first,last; \
    memcpy(&first,between,sizeof first); \
    memcpy(&last,between+width-sizeof last,sizeof last); \
    for (size_t i=0;i<length;i++) { \
        if (i) { \
            memcpy(output,&first,sizeof first); \
            memcpy(output+width-sizeof last,&last,sizeof last); \
            output+=width; \
        } \
        const myl_block *part=items[i]; \
        const size_t bytes=part->len; \
        if (bytes) core_text_copy_short(output,(const unsigned char *)part + MYL_HEADER,bytes); \
        output+=bytes; \
    } \
    return; \
} while (0)
static __attribute__((noinline)) void core_text_join_short(unsigned char *output, myl_block *const *items, size_t length,
                                                const unsigned char *between, size_t width) {
    if (!length) return;
    if (width>=8) CORE_JOIN_SHORT_WORDS(uint64_t);
    if (width>=4) CORE_JOIN_SHORT_WORDS(uint32_t);
    if (width>=2) CORE_JOIN_SHORT_WORDS(uint16_t);
    if (width) CORE_JOIN_SHORT_WORDS(unsigned char);
    for (size_t i=0;i<length;i++) {
        const myl_block *part=items[i];
        const size_t bytes=part->len;
        if (bytes) core_text_copy_short(output,(const unsigned char *)part + MYL_HEADER,bytes);
        output+=bytes;
    }
}
#undef CORE_JOIN_SHORT_WORDS
myl_block *myl_core_str_join(const myl_block *separator, myl_block *parts) {
    myl_block **items = (myl_block **)block_data(parts);
    int64_t total = parts->len > 1 ? separator->len * (parts->len - 1) : 0;
    bool short_copies = separator->len <= 16;
    bool ascii = parts->len < 2 || (separator->kind & MYL_TEXT_ASCII);
    for (int64_t i = 0; i < parts->len; ++i) { total += items[i]->len; ascii = ascii && (items[i]->kind & MYL_TEXT_ASCII); short_copies = short_copies && items[i]->len <= 16; }
    myl_block *text = str_new(total);
    unsigned char *at = block_data(text);
    if (short_copies) core_text_join_short(at, items, (size_t)parts->len, (const unsigned char *)separator + MYL_HEADER, (size_t)separator->len);
    else for (int64_t i = 0; i < parts->len; ++i) {
        if (i) { core_text_copy(at, (const unsigned char *)separator + MYL_HEADER, (size_t)separator->len); at += separator->len; }
        core_text_copy(at, (const unsigned char *)items[i] + MYL_HEADER, (size_t)items[i]->len); at += items[i]->len;
    }
    if (ascii) text->kind |= MYL_TEXT_ASCII;
    return text;
}

/* Bytewise search keeps UTF-8 boundaries because both needle and haystack are valid. */
static int64_t core_text_find_bytes(const myl_block *text, const myl_block *needle, int64_t start) {
    if (!needle->len) return start;
    const unsigned char *data = (const unsigned char *)text + MYL_HEADER;
    const unsigned char *wanted = (const unsigned char *)needle + MYL_HEADER;
    if (needle->len > text->len - start) return -1;
    for (unsigned tried = 0; tried < 8; ++tried) {
        const unsigned char *hit = memchr(data + start, wanted[0], (size_t)(text->len - needle->len - start + 1));
        if (!hit) return -1;
        start = hit - data;
        /* The rest of a candidate is short in every search here: a loop that stops at
           the first difference costs less than a `memcmp` call per candidate. */
        int64_t same = 1;
        while (same < needle->len && hit[same] == wanted[same]) ++same;
        if (same == needle->len) return start;
        ++start;
        if (start > text->len - needle->len) return -1;
    }
    /* libc's bounded linear search handles repeated first bytes after a few cheap candidates. */
    extern void *memmem(const void *, size_t, const void *, size_t);
    const unsigned char *hit = memmem(data + start, (size_t)(text->len - start), wanted, (size_t)needle->len);
    if (hit) return hit - data;
    return -1;
}

/* Scalars that start in bytes [from, to): every byte that is not a UTF-8 continuation. */
static uint64_t core_text_starts(const unsigned char *bytes, uint64_t from, uint64_t to) {
    uint64_t count = 0;
    for (uint64_t i = from; i < to; ++i) count += (bytes[i] & 0xc0) != 0x80;
    return count;
}

/* The scalar index of a match is counted from the nearer end: a match near the end
   of a long text is the cached scalar count less the few scalars after it (the old
   runtime's `index_walk`). */
int64_t myl_core_str_find(myl_block *text, myl_block *needle) {
    int64_t hit = core_text_find_bytes(text, needle, 0);
    if (hit < 0 || (text->kind & MYL_TEXT_ASCII)) return hit;
    const unsigned char *bytes = block_data(text);
    const uint64_t at = (uint64_t)hit, length = (uint64_t)text->len;
    if (at <= length - at) return (int64_t)core_text_starts(bytes, 0, at);
    return (int64_t)(myl_core_str_chars(text) - core_text_starts(bytes, at, length));
}

bool myl_core_str_contains(myl_block *text, myl_block *needle) { return core_text_find_bytes(text, needle, 0) >= 0; }
bool myl_core_str_starts(myl_block *text, myl_block *needle) { return needle->len <= text->len && memcmp(block_data(text), block_data(needle), (size_t)needle->len) == 0; }
bool myl_core_str_ends(myl_block *text, myl_block *needle) { return needle->len <= text->len && memcmp(block_data(text) + text->len - needle->len, block_data(needle), (size_t)needle->len) == 0; }

static const int32_t core_text_list_layout[] = {8, 1, 0, 0, 0};
myl_block *myl_core_str_split(myl_block *text, myl_block *separator) {
    if (!separator->len) myl_core_s2_unsupported(-1);
    myl_block *list = myl_core_list_new_slow(0, 8);
    list->reserved = (int64_t)(intptr_t)core_text_list_layout;
    int64_t at = 0;
    for (;;) {
        int64_t hit = core_text_find_bytes(text, separator, at);
        int64_t end = hit < 0 ? text->len : hit;
        myl_block *piece = str_from((const char *)block_data(text) + at, (size_t)(end - at));
        if (list->len == list->cap) list = myl_core_list_grow(list, 8);
        ((myl_block **)block_data(list))[list->len++] = piece;
        if (hit < 0) break;
        at = hit + separator->len;
    }
    return list;
}

bool myl_core_bytes_valid_list(myl_block *list) {
    const int64_t *values = (const int64_t *)block_data(list);
    for (int64_t i = 0; i < list->len; ++i) if (values[i] < 0 || values[i] > 255) return false;
    return true;
}

myl_block *myl_core_bytes_from_list(myl_block *list) {
    myl_block *bytes = str_new(list->len);
    int64_t *values = (int64_t *)block_data(list);
    for (int64_t i = 0; i < list->len; ++i) block_data(bytes)[i] = (unsigned char)values[i];
    bytes->kind = (bytes->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return bytes;
}

myl_block *myl_core_bytes_concat(const myl_block *a, const myl_block *b) { myl_block *out = myl_core_str_concat(a, b); out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES; return out; }
myl_block *myl_core_bytes_slice(myl_block *text, int64_t start, int64_t end) {
    start = core_text_clamp(start, text->len); end = core_text_clamp(end, text->len);
    myl_block *out = str_from((const char *)block_data(text) + start, (size_t)(end > start ? end - start : 0));
    out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return out;
}

myl_block *myl_core_text_encode(myl_block *text) { retain_block(text); return text; }
int64_t myl_core_bytes_find(myl_block *text, myl_block *needle) { return core_text_find_bytes(text, needle, 0); }

uint64_t myl_core_str_index_offset(myl_block *text, int64_t index) {
    if (index < 0) index += (int64_t)myl_core_str_chars(text);
    return index < 0 ? (uint64_t)text->len : myl_core_str_offset(text, (uint64_t)index);
}
uint64_t myl_core_bytes_index_offset(myl_block *text, int64_t index) {
    if (index < 0) index += text->len;
    return (uint64_t)index;
}

static int64_t core_text_step_bound(int64_t value, int64_t len, int64_t step, bool stop) {
    if ((!stop && value == INT64_MIN) || (stop && value == INT64_MAX)) return step < 0 ? (stop ? -1 : len - 1) : (stop ? len : 0);
    if (value < 0) value += len;
    if (step < 0) return value < 0 ? -1 : value >= len ? len - 1 : value;
    return value < 0 ? 0 : value > len ? len : value;
}

static myl_block *core_text_slice_step(myl_block *text, int64_t start, int64_t end, int64_t step, bool unicode) {
    int64_t len = unicode ? (int64_t)myl_core_str_chars(text) : text->len;
    start = core_text_step_bound(start, len, step, false); end = core_text_step_bound(end, len, step, true);
    myl_block *out = str_new(text->len);
    out->len = 0;
    for (int64_t i = start; step > 0 ? i < end : i > end;) {
        uint64_t at = unicode ? myl_core_str_offset(text, (uint64_t)i) : (uint64_t)i;
        uint64_t width = unicode ? myl_core_ir_str_width(text, at) : 1;
        memcpy(block_data(out) + out->len, block_data(text) + at, (size_t)width);
        out->len += (int64_t)width;
        if ((step > 0 && i > INT64_MAX - step) || (step < 0 && i < INT64_MIN - step)) break;
        i += step;
    }
    block_data(out)[out->len] = 0;
    core_text_publish(out);
    if (!unicode) out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return out;
}

myl_block *myl_core_str_slice_step(myl_block *text, int64_t start, int64_t end, int64_t step) { return core_text_slice_step(text, start, end, step, true); }
myl_block *myl_core_bytes_slice_step(myl_block *text, int64_t start, int64_t end, int64_t step) { return core_text_slice_step(text, start, end, step, false); }

static bool core_text_space(unsigned char ch) { return ch == ' ' || (ch >= 9 && ch <= 13); }
/* Private split-loop cursors use the same six whitespace octets as the list form.
   Out-of-range offsets return unchanged; non-ASCII UTF-8 is never a separator. */
int64_t myl_core_split_ws_start(myl_block *text, int64_t at) {
    if (at < 0) return at;
    while (at < text->len && core_text_space(block_data(text)[at])) ++at;
    return at;
}
int64_t myl_core_split_ws_end(myl_block *text, int64_t at) {
    if (at < 0) return at;
    while (at < text->len && !core_text_space(block_data(text)[at])) ++at;
    return at;
}
myl_block *myl_core_str_split_whitespace(myl_block *text) {
    myl_block *list = myl_core_list_new_slow(0, 8);
    list->reserved = (int64_t)(intptr_t)core_text_list_layout;
    int64_t at = 0;
    while (at < text->len) {
        while (at < text->len && core_text_space(block_data(text)[at])) ++at;
        int64_t start = at;
        while (at < text->len && !core_text_space(block_data(text)[at])) ++at;
        if (start == at) break;
        myl_block *piece = str_from((const char *)block_data(text) + start, (size_t)(at - start));
        if (list->len == list->cap) list = myl_core_list_grow(list, 8);
        ((myl_block **)block_data(list))[list->len++] = piece;
    }
    return list;
}

myl_block *myl_core_bytes_to_list(myl_block *bytes) {
    myl_block *list = myl_core_list_new_slow(bytes->len, 8);
    list->len = bytes->len;
    for (int64_t i = 0; i < bytes->len; ++i) ((int64_t *)block_data(list))[i] = block_data(bytes)[i];
    return list;
}

bool myl_core_bytes_contains_value(myl_block *bytes, int64_t value) {
    return value >= 0 && value <= 255 && memchr(block_data(bytes), (unsigned char)value, (size_t)bytes->len) != NULL;
}

/* S3 helpers port native_text_methods.c/native_search.c/native_trim.c/native_repr.c
 * into independent one-count blocks. Inputs borrow, outputs own a fresh block. */
static uint32_t core_unicode_next(const unsigned char *data, size_t *at) {
    uint32_t point = data[(*at)++];
    if (point < 0x80) return point;
    unsigned count = point < 0xe0 ? 1 : point < 0xf0 ? 2 : 3;
    point &= count == 1 ? 0x1f : count == 2 ? 0x0f : 0x07;
    while (count--) point = (point << 6) | (data[(*at)++] & 0x3f);
    return point;
}

static size_t core_unicode_previous(const unsigned char *data, size_t at) {
    at--;
    while ((data[at] & 0xc0) == 0x80) at--;
    return at;
}

static bool core_unicode_space(uint32_t point) {
    if (point < 128) return (point >= 9 && point <= 13) || (point >= 28 && point <= 32);
    if (point >= 0x2000 && point <= 0x200a) return true;
    switch (point) {
    case 0x85: case 0xa0: case 0x1680: case 0x2028: case 0x2029:
    case 0x202f: case 0x205f: case 0x3000: return true;
    default: return false;
    }
}

static void core_text_family(myl_block *result, const myl_block *source) {
    core_text_publish(result);
    if (kind_of(source) == MYL_KIND_BYTES) result->kind = (result->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
}

int64_t myl_core_text_bound(uint64_t value) { return value > INT64_MAX ? INT64_MAX : (int64_t)value; }

myl_block *myl_core_text_case(myl_block *input, bool upper) {
    myl_block *result = str_new(input->len);
    memcpy(block_data(result), block_data(input), (size_t)input->len);
    for (int64_t i = 0; i < input->len; i++) {
        unsigned char *value = block_data(result) + i;
        if (upper && *value >= 'a' && *value <= 'z') *value -= 32;
        else if (!upper && *value >= 'A' && *value <= 'Z') *value += 32;
    }
    core_text_family(result, input);
    return result;
}

bool myl_core_text_every(myl_block *input, int32_t property) {
    if (!input->len) return false;
    for (int64_t i = 0; i < input->len; i++) {
        unsigned char value = block_data(input)[i];
        bool good = property == 0 ? value >= '0' && value <= '9' :
                    property == 1 ? (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z') : core_text_space(value);
        if (!good) return false;
    }
    return true;
}

bool myl_core_text_scalar_valid(uint64_t code) {
    return code <= 0x10ffff && (code < 0xd800 || code > 0xdfff);
}

static size_t core_unicode_encode(unsigned char *out, uint32_t point) {
    if (point < 0x80) { out[0] = (unsigned char)point; return 1; }
    if (point < 0x800) {
        out[0] = (unsigned char)(0xc0 | (point >> 6)); out[1] = (unsigned char)(0x80 | (point & 63)); return 2;
    }
    if (point < 0x10000) {
        out[0] = (unsigned char)(0xe0 | (point >> 12)); out[1] = (unsigned char)(0x80 | ((point >> 6) & 63));
        out[2] = (unsigned char)(0x80 | (point & 63)); return 3;
    }
    out[0] = (unsigned char)(0xf0 | (point >> 18)); out[1] = (unsigned char)(0x80 | ((point >> 12) & 63));
    out[2] = (unsigned char)(0x80 | ((point >> 6) & 63)); out[3] = (unsigned char)(0x80 | (point & 63)); return 4;
}

myl_block *myl_core_text_chr(uint64_t code) {
    if (code < 128) return core_ascii_char((unsigned char)code);
    unsigned char raw[4];
    size_t width = core_unicode_encode(raw, (uint32_t)code);
    return str_from((const char *)raw, width);
}

int64_t myl_core_text_ord(myl_block *text) {
    size_t at = 0;
    return (int64_t)core_unicode_next(block_data(text), &at);
}

/* Native search's constant-space two-way reverse matching, including periodic misses. */
typedef struct { const unsigned char *data; size_t length; bool reverse; } core_octets;
typedef struct { size_t first, last; bool valid; } core_search_window;
typedef struct { size_t cut, period; } core_factorization;
static unsigned char core_octet_at(core_octets text, size_t index) {
    return text.data[text.reverse ? text.length - 1 - index : index];
}

static core_factorization core_maximal_suffix(core_octets needle, bool order) {
    size_t suffix = SIZE_MAX, candidate = 0, offset = 1, period = 1;
    while (offset < needle.length - candidate) {
        unsigned char a = core_octet_at(needle, suffix + offset), b = core_octet_at(needle, candidate + offset);
        if (a == b) {
            if (offset == period) { candidate += period; offset = 1; }
            else offset++;
        } else if (order ? a > b : a < b) { candidate += offset; offset = 1; period = candidate - suffix; }
        else { suffix = candidate++; offset = period = 1; }
    }
    return (core_factorization){suffix + 1, period};
}

static size_t core_periodic_memory(core_octets needle, core_factorization *split) {
    for (size_t i = 0; i < split->cut; i++) {
        if (core_octet_at(needle, i) != core_octet_at(needle, i + split->period)) {
            size_t right = needle.length - split->cut, left = split->cut ? split->cut - 1 : 0;
            split->period = (left > right ? left : right) + 1;
            return 0;
        }
    }
    return needle.length - split->period;
}

static size_t core_reverse_find(core_octets haystack, core_octets needle) {
    core_factorization a = core_maximal_suffix(needle, false), b = core_maximal_suffix(needle, true);
    core_factorization split = a.cut > b.cut ? a : b;
    size_t memory_after = core_periodic_memory(needle, &split), memory = 0, at = 0;
    while (at <= haystack.length - needle.length) {
        size_t i = split.cut > memory ? split.cut : memory;
        while (i < needle.length && core_octet_at(needle, i) == core_octet_at(haystack, at + i)) i++;
        if (i < needle.length) { at += i - split.cut + 1; memory = 0; continue; }
        i = split.cut;
        while (i > memory && core_octet_at(needle, i - 1) == core_octet_at(haystack, at + i - 1)) i--;
        if (i <= memory) return haystack.length - needle.length - at;
        at += split.period; memory = memory_after;
    }
    return SIZE_MAX;
}

static size_t core_search_endpoint(size_t length, int64_t value, bool start) {
    if (value >= 0) return start || (uint64_t)value <= length ? (size_t)value : length;
    uint64_t distance = (uint64_t)(-(value + 1)) + 1;
    return distance > length ? 0 : length - (size_t)distance;
}

static core_search_window core_window(size_t length, int64_t start, int64_t end) {
    size_t first = core_search_endpoint(length, start, true), last = core_search_endpoint(length, end, false);
    return (core_search_window){first, last, first <= last && first <= length};
}

enum { CORE_FIND, CORE_RFIND, CORE_INDEX, CORE_RINDEX, CORE_COUNT, CORE_PREFIX, CORE_SUFFIX };
static int64_t core_empty_answer(core_search_window bounds, int mode) {
    if (!bounds.valid) return mode == CORE_COUNT || mode >= CORE_PREFIX ? 0 : -1;
    if (mode == CORE_COUNT) return (int64_t)(bounds.last - bounds.first) + 1;
    if (mode >= CORE_PREFIX) return 1;
    return (int64_t)(mode == CORE_RFIND || mode == CORE_RINDEX ? bounds.last : bounds.first);
}

static int64_t core_search_octets(core_octets input, core_octets needle, int mode) {
    if (needle.length > input.length) return mode >= CORE_COUNT ? 0 : -1;
    if (mode == CORE_COUNT) {
        int64_t count = 0;
        size_t at = 0;
        extern void *memmem(const void *, size_t, const void *, size_t);
        while (at <= input.length - needle.length) {
            const unsigned char *hit = memmem(input.data + at, input.length - at, needle.data, needle.length);
            if (!hit) break;
            count++; at = (size_t)(hit - input.data) + needle.length;
        }
        return count;
    }
    if (mode >= CORE_PREFIX) {
        size_t at = mode == CORE_PREFIX ? 0 : input.length - needle.length;
        return memcmp(input.data + at, needle.data, needle.length) == 0;
    }
    size_t found;
    if (mode == CORE_RFIND || mode == CORE_RINDEX) {
        input.reverse = needle.reverse = true; found = core_reverse_find(input, needle);
    } else {
        extern void *memmem(const void *, size_t, const void *, size_t);
        const unsigned char *hit = memmem(input.data, input.length, needle.data, needle.length);
        found = hit ? (size_t)(hit - input.data) : SIZE_MAX;
    }
    return found == SIZE_MAX ? -1 : (int64_t)found;
}

int64_t myl_core_text_search(myl_block *input, myl_block *needle, int64_t start, int64_t end, int32_t mode) {
    core_search_window bounds = core_window((size_t)myl_core_str_chars(input), start, end);
    if (!needle->len) return core_empty_answer(bounds, mode);
    if (!bounds.valid) return mode >= CORE_COUNT ? 0 : -1;
    size_t first = (size_t)myl_core_str_offset(input, bounds.first), last = (size_t)myl_core_str_offset(input, bounds.last);
    int64_t found = core_search_octets((core_octets){block_data(input) + first, last - first, false}, (core_octets){block_data(needle), (size_t)needle->len, false}, mode);
    if (found < 0 || mode >= CORE_COUNT) return found;
    return (int64_t)core_text_starts(block_data(input), 0, first + (size_t)found);
}

int64_t myl_core_bytes_search(myl_block *input, myl_block *needle, int64_t start, int64_t end, int32_t mode) {
    core_search_window bounds = core_window((size_t)input->len, start, end);
    if (!needle->len) return core_empty_answer(bounds, mode);
    if (!bounds.valid) return mode >= CORE_COUNT ? 0 : -1;
    int64_t found = core_search_octets((core_octets){block_data(input) + bounds.first, bounds.last - bounds.first, false}, (core_octets){block_data(needle), (size_t)needle->len, false}, mode);
    return found < 0 || mode >= CORE_COUNT ? found : found + (int64_t)bounds.first;
}

/* Deterministic direct scalar membership, as native_trim.c; temporary wide bits
 * belong to this call, and are freed before any counted result is published. */
enum { CORE_SMALL_POINTS = 32, CORE_UNICODE_WORDS = 0x110000 / 64 };
typedef struct { uint64_t ascii[4]; uint32_t small[CORE_SMALL_POINTS]; size_t count; uint64_t *wide; } core_scalar_set;
static bool core_set_contains(const core_scalar_set *set, uint32_t point) {
    if (point < 256) return (set->ascii[point / 64] >> (point % 64)) & 1;
    if (set->wide) return (set->wide[point / 64] >> (point % 64)) & 1;
    for (size_t i = 0; i < set->count; i++) if (set->small[i] == point) return true;
    return false;
}
static void core_set_add(core_scalar_set *set, uint32_t point) {
    if (point < 256) { set->ascii[point / 64] |= UINT64_C(1) << (point % 64); return; }
    if (core_set_contains(set, point)) return;
    if (!set->wide && set->count == CORE_SMALL_POINTS) {
        set->wide = calloc(CORE_UNICODE_WORDS, sizeof(uint64_t));
        if (!set->wide) out_of_memory();
        for (size_t i = 0; i < set->count; i++) set->wide[set->small[i] / 64] |= UINT64_C(1) << (set->small[i] % 64);
    }
    if (set->wide) set->wide[point / 64] |= UINT64_C(1) << (point % 64);
    else set->small[set->count++] = point;
}

myl_block *myl_core_text_trim(myl_block *input, myl_block *chars, int32_t ends, bool explicit_chars) {
    core_scalar_set set = {0};
    if (explicit_chars) for (size_t at = 0; at < (size_t)chars->len;) core_set_add(&set, core_unicode_next(block_data(chars), &at));
    size_t low = 0, high = (size_t)input->len;
    if (ends != 2) while (low < high) {
        size_t next = low;
        uint32_t point = core_unicode_next(block_data(input), &next);
        if (!(explicit_chars ? core_set_contains(&set, point) : core_unicode_space(point))) break;
        low = next;
    }
    if (ends != 1) while (high > low) {
        size_t next = core_unicode_previous(block_data(input), high), cursor = next;
        uint32_t point = core_unicode_next(block_data(input), &cursor);
        if (!(explicit_chars ? core_set_contains(&set, point) : core_unicode_space(point))) break;
        high = next;
    }
    free(set.wide);
    return str_from((const char *)block_data(input) + low, high - low);
}

myl_block *myl_core_bytes_trim(myl_block *input, myl_block *chars, int32_t ends, bool explicit_chars) {
    uint64_t set[4] = {0};
    if (explicit_chars) for (int64_t i = 0; i < chars->len; i++) {
        unsigned char value = block_data(chars)[i]; set[value / 64] |= UINT64_C(1) << (value % 64);
    } else for (unsigned point = 0; point < 128; point++) if (core_text_space((unsigned char)point)) set[point / 64] |= UINT64_C(1) << (point % 64);
    int64_t first = 0, last = input->len;
    if (ends != 2) while (first < last) {
        unsigned char value = block_data(input)[first];
        if (!((set[value / 64] >> (value % 64)) & 1)) break;
        first++;
    }
    if (ends != 1) while (last > first) {
        unsigned char value = block_data(input)[last - 1];
        if (!((set[value / 64] >> (value % 64)) & 1)) break;
        last--;
    }
    return myl_core_bytes_slice(input, first, last);
}

myl_block *myl_core_text_replace(myl_block *input, myl_block *needle, myl_block *insert) {
    int64_t hits = myl_core_bytes_search(input, needle, 0, INT64_MAX, CORE_COUNT);
    uint64_t kept = (uint64_t)(input->len - hits * needle->len);
    if (insert->len && (uint64_t)hits > (uint64_t)INT64_MAX / (uint64_t)insert->len) out_of_memory();
    uint64_t added = (uint64_t)hits * (uint64_t)insert->len;
    if (added > (uint64_t)INT64_MAX - kept) out_of_memory();
    myl_block *result = str_new((int64_t)(kept + added));
    int64_t at = 0, cursor = 0;
    for (int64_t left = hits; left; left--) {
        int64_t hit = core_text_find_bytes(input, needle, cursor);
        memcpy(block_data(result) + at, block_data(input) + cursor, (size_t)(hit - cursor));
        at += hit - cursor;
        memcpy(block_data(result) + at, block_data(insert), (size_t)insert->len);
        at += insert->len; cursor = hit + needle->len;
    }
    memcpy(block_data(result) + at, block_data(input) + cursor, (size_t)(input->len - cursor));
    core_text_family(result, input);
    return result;
}

static myl_block *core_append_line(myl_block *list, myl_block *input, size_t start, size_t end) {
    myl_block *piece = str_from((const char *)block_data(input) + start, end - start);
    core_text_family(piece, input);
    if (list->len == list->cap) list = myl_core_list_grow(list, 8);
    ((myl_block **)block_data(list))[list->len++] = piece;
    return list;
}

myl_block *myl_core_text_splitlines(myl_block *input) {
    myl_block *list = myl_core_list_new_slow(0, 8);
    list->reserved = (int64_t)(intptr_t)core_text_list_layout;
    size_t start = 0, cursor = 0;
    while (cursor < (size_t)input->len) {
        unsigned char octet = block_data(input)[cursor];
        if (octet != '\n' && octet != '\r') { cursor++; continue; }
        list = core_append_line(list, input, start, cursor);
        cursor++;
        if (octet == '\r' && cursor < (size_t)input->len && block_data(input)[cursor] == '\n') cursor++;
        start = cursor;
    }
    if (start < (size_t)input->len) list = core_append_line(list, input, start, (size_t)input->len);
    return list;
}

myl_block *myl_core_text_zfill(myl_block *input, int64_t width) {
    uint64_t length = kind_of(input) == MYL_KIND_BYTES ? (uint64_t)input->len : myl_core_str_chars(input);
    uint64_t target = width <= 0 ? 0 : (uint64_t)width > UINT32_MAX ? UINT32_MAX : (uint64_t)width;
    uint64_t pad = target > length ? target - length : 0;
    myl_block *result = str_new(input->len + (int64_t)pad);
    size_t keep = input->len && (block_data(input)[0] == '+' || block_data(input)[0] == '-') ? 1 : 0;
    if (keep) block_data(result)[0] = block_data(input)[0];
    memset(block_data(result) + keep, '0', (size_t)pad);
    memcpy(block_data(result) + keep + pad, block_data(input) + keep, (size_t)input->len - keep);
    core_text_family(result, input);
    return result;
}

int64_t myl_core_bytes_find_any(myl_block *input, myl_block *values, int64_t start) {
    size_t length=input->len;
    size_t at = start<0 ? 0 : ((uint64_t)start>length ? length : (size_t)start);
    if (at>=length || !values->len) return -1;
    const unsigned char *bytes=block_data(input);
    const unsigned char *set=block_data(values);
    if (values->len==1) {
        const unsigned char *found=memchr(bytes+at,set[0],length-at);
        return found ? (int64_t)(found-bytes) : -1;
    }
    if (values->len==2 && set[0]!=set[1]) {
        /* A window at a time, doubling from 64 octets, and the second octet only
           up to the first's hit: a search stops within twice the distance to its
           answer, so a loop of searches over input missing one octet stays
           linear instead of rescanning to the end on every call. */
        size_t window=64;
        while (at<length) {
            size_t span=length-at<window ? length-at : window;
            const unsigned char *first=memchr(bytes+at,set[0],span);
            size_t bound=first ? (size_t)(first-(bytes+at)) : span;
            const unsigned char *second=bound ? memchr(bytes+at,set[1],bound) : NULL;
            if (second) return (int64_t)(second-bytes);
            if (first) return (int64_t)(first-bytes);
            at+=span;
            if (window<=SIZE_MAX/2) window*=2;
        }
        return -1;
    }
    uint64_t members[4]={0,0,0,0};
    for (size_t i=0;i<values->len;i++) members[set[i]>>6]|=(uint64_t)1<<(set[i]&63);
    for (size_t i=at;i<length;i++) if (members[bytes[i]>>6]>>(bytes[i]&63)&1) return (int64_t)i;
    return -1;
}

/* Validation/count ported from native_bytes.c, with -1 the invalid marker. */
int64_t myl_core_span_utf8_count(const unsigned char *bytes, uint64_t length) {
    uint64_t at = 0;
    int64_t count = 0;
    while (at < length) {
        while (at + 8 <= length) {
            uint64_t word;
            memcpy(&word, bytes + at, 8);
            if (word & UINT64_C(0x8080808080808080)) break;
            at += 8; count += 8;
        }
        if (at < length && bytes[at] < 0x80) { at++; count++; continue; }
        if (at == length) break;
        unsigned char first = bytes[at];
        unsigned remaining;
        uint32_t minimum;
        if (first >= 0xc2 && first <= 0xdf) { remaining = 1; minimum = 0x80; }
        else if (first >= 0xe0 && first <= 0xef) { remaining = 2; minimum = 0x800; }
        else if (first >= 0xf0 && first <= 0xf4) { remaining = 3; minimum = 0x10000; }
        else return -1;
        if (remaining > length - at - 1) return -1;
        uint32_t point = first & ((1u << (6 - remaining)) - 1u);
        for (unsigned index = 0; index < remaining; index++) {
            unsigned char next = bytes[at + 1 + index];
            if ((next & 0xc0) != 0x80) return -1;
            point = (point << 6) | (next & 63u);
        }
        if (point < minimum || point > 0x10ffff || (point >= 0xd800 && point <= 0xdfff)) return -1;
        at += remaining + 1; count++;
    }
    return count;
}

int64_t myl_core_bytes_utf8_count(myl_block *bytes) { return myl_core_span_utf8_count(block_data(bytes), (uint64_t)bytes->len); }
int64_t myl_core_bytes_utf8_count_range(myl_block *bytes, int64_t start, int64_t end) {
    size_t first = core_search_endpoint((size_t)bytes->len, start, false), last = core_search_endpoint((size_t)bytes->len, end, false);
    return myl_core_span_utf8_count(block_data(bytes) + first, last > first ? last - first : 0);
}
myl_block *myl_core_bytes_decode_text(myl_block *bytes) { return str_from((const char *)block_data(bytes), (size_t)bytes->len); }
myl_block *myl_core_bytes_utf8_error(void) { return str_from("invalid UTF-8 in byte string", sizeof("invalid UTF-8 in byte string") - 1); }

/* Packed PY-FSTRING-SPEC-1 text layout, ported from format_spec.zig.
 * Only fields accepted by its text resolver reach this entry. */
myl_block *myl_core_text_format(myl_block *input, uint64_t spec) {
    uint32_t fill = (uint32_t)(spec & 0x1fffff);
    unsigned alignment = (unsigned)((spec >> 21) & 7);
    uint64_t width = (spec >> 49) & 0xfff;
    uint64_t scalars = myl_core_str_chars(input);
    if ((spec >> 36) & 1) {
        uint64_t precision = (spec >> 37) & 0xfff;
        if (scalars > precision) scalars = precision;
    }
    uint64_t bytes = myl_core_str_offset(input, scalars), pad = width > scalars ? width - scalars : 0;
    uint64_t left = alignment == 2 ? pad : alignment == 3 ? pad / 2 : 0;
    unsigned char raw[4];
    size_t fill_bytes = core_unicode_encode(raw, fill);
    myl_block *result = str_new((int64_t)(bytes + pad * fill_bytes));
    unsigned char *out = block_data(result);
    for (uint64_t i = 0; i < left; i++) { memcpy(out, raw, fill_bytes); out += fill_bytes; }
    memcpy(out, block_data(input), (size_t)bytes); out += bytes;
    for (uint64_t i = left; i < pad; i++) { memcpy(out, raw, fill_bytes); out += fill_bytes; }
    core_text_publish(result);
    return result;
}

/* Scalar repr ports native_repr.c's quote/escape/Unicode16 printability rules. */
typedef struct { const unsigned char *data; size_t length; bool bytes; unsigned char quote; } core_repr_input;
typedef struct { unsigned char *data; size_t octets; } core_repr_output;
static bool core_printable(uint32_t point) {
    size_t low = 0, high = sizeof core_nonprintable / sizeof core_nonprintable[0];
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (point < core_nonprintable[middle][0]) high = middle;
        else if (point > core_nonprintable[middle][1]) low = middle + 1;
        else return false;
    }
    return true;
}
static void core_repr_bytes(core_repr_output *out, const unsigned char *data, size_t length) {
    if (length > SIZE_MAX - out->octets) out_of_memory();
    if (out->data) memcpy(out->data + out->octets, data, length);
    out->octets += length;
}
static void core_repr_escape(core_repr_output *out, uint32_t point, unsigned digits) {
    static const unsigned char hex[] = "0123456789abcdef";
    unsigned char escaped[10] = {'\\', digits == 2 ? 'x' : digits == 4 ? 'u' : 'U'};
    for (unsigned i = 0; i < digits; i++) escaped[2 + i] = hex[(point >> (4 * (digits - 1 - i))) & 15];
    core_repr_bytes(out, escaped, digits + 2);
}
static void core_repr_point(core_repr_output *out, core_repr_input input, uint32_t point, size_t first, size_t last) {
    unsigned char escaped[2] = {'\\', 0};
    if (point == '\t') escaped[1] = 't';
    else if (point == '\n') escaped[1] = 'n';
    else if (point == '\r') escaped[1] = 'r';
    else if (point == '\\' || point == input.quote) escaped[1] = (unsigned char)point;
    if (escaped[1]) { core_repr_bytes(out, escaped, 2); return; }
    if (!(input.bytes ? point >= 32 && point < 127 : core_printable(point))) {
        core_repr_escape(out, point, point < 256 ? 2 : point < 65536 ? 4 : 8); return;
    }
    core_repr_bytes(out, input.data + first, last - first);
}
static void core_repr_render(core_repr_input input, core_repr_output *out) {
    if (input.bytes) core_repr_bytes(out, (const unsigned char *)"b", 1);
    core_repr_bytes(out, &input.quote, 1);
    for (size_t at = 0; at < input.length;) {
        size_t first = at;
        uint32_t point = input.bytes ? input.data[at++] : core_unicode_next(input.data, &at);
        core_repr_point(out, input, point, first, at);
    }
    core_repr_bytes(out, &input.quote, 1);
}
myl_block *myl_core_text_repr(myl_block *source, bool bytes) {
    core_repr_input input = {block_data(source), (size_t)source->len, bytes, '\''};
    if (memchr(input.data, '\'', input.length) && !memchr(input.data, '"', input.length)) input.quote = '"';
    core_repr_output measured = {0};
    core_repr_render(input, &measured);
    if (measured.octets > INT64_MAX) out_of_memory();
    myl_block *result = str_new((int64_t)measured.octets);
    core_repr_output output = {block_data(result), 0};
    core_repr_render(input, &output);
    core_text_publish(result);
    return result;
}

/* S2-F: port of native_collections.c's stable powersort and decorated sort.
   This runtime is independent of the old core; only the algorithm is shared. */
#include <math.h>
typedef struct { size_t size; } s2_sort_element;
typedef struct { size_t length, capacity; uint64_t generation; void *storage; const s2_sort_element *element; } s2_sort_list;
static int s2_sort_block_compare(const myl_block *a, const myl_block *b) {
    size_t n = (size_t)(a->len < b->len ? a->len : b->len);
    int order = memcmp((const unsigned char *)a+MYL_HEADER, (const unsigned char *)b+MYL_HEADER, n);
    return order ? order : a->len < b->len ? -1 : a->len > b->len;
}
static int s2_compare_signed(const unsigned char *a, const unsigned char *b, size_t size) {
    int64_t x, y;
    switch (size) {
    case 1: { int8_t l,r; memcpy(&l,a,1); memcpy(&r,b,1); x=l; y=r; break; }
    case 2: { int16_t l,r; memcpy(&l,a,2); memcpy(&r,b,2); x=l; y=r; break; }
    case 4: { int32_t l,r; memcpy(&l,a,4); memcpy(&r,b,4); x=l; y=r; break; }
    default: memcpy(&x,a,8); memcpy(&y,b,8); break;
    }
    return x<y ? -1 : x>y;
}
static int s2_compare_unsigned(const unsigned char *a, const unsigned char *b, size_t size) {
    uint64_t x=0,y=0; memcpy(&x,a,size); memcpy(&y,b,size); return x<y ? -1 : x>y;
}
static void s2_copy_element(void *to, const void *from, size_t size) { memcpy(to,from,size); }
/* `list.sort()` is an adaptive stable merge sort, the shape of CPython's
   listsort without galloping. The list is cut into natural runs; a strictly
   descending run is reversed, and a run shorter than `minrun` is extended by
   insertion sort. Runs are merged in the order the powersort rule picks, so
   the merge tree stays balanced over any mix of run lengths, through one
   scratch buffer of at most half the list: a merge copies the shorter run out
   and merges forward or backward into the space it left.

   Equal elements never pass each other. A reversed run is strictly
   descending, insertion stops at the first element not greater than the one
   it places, a merge first skips the left elements not greater than the right
   run's head and the right elements not less than the left run's tail, and it
   takes the left element on a tie. The order itself is the one the language
   documents: integers by value, binary64 values with every NaN after every
   ordered value and signed zeros tied, text by Unicode scalar value.

   The algorithm is written once, over a `s2_sort_kind`. Each entry point passes a
   constant kind, so after inlining every comparison and move is compiled for
   that element type: merging 64-bit integers or floats is a compare and a few
   conditional selects per element, with no branch to mispredict. The narrower
   integer widths share one generic entry that keeps a per-comparison switch on
   the width. Sorting calls no guest code and allocates nothing managed, so no
   collection can run while text pointers sit in the scratch buffer. */
enum { SORT_I64, SORT_U64, SORT_F64, SORT_TEXT, SORT_GENERIC, SORT_BYTES };
typedef struct { unsigned kind, order; size_t size; unsigned reverse; } s2_sort_kind;
typedef struct { size_t start, length; int power; } s2_sort_run;
/* Runs below this length are extended by insertion sort; `s2_sort_minrun` picks
   a value in [SORT_MINRUN_LIMIT / 2, SORT_MINRUN_LIMIT] that splits the list
   into close to a power of two runs. */
#define SORT_MINRUN_LIMIT 32
/* The powers on the stack strictly increase, so a 64-bit length needs at most
   65 pending runs, the bound CPython's listsort uses; the rest is margin, and
   a full stack would merge its top pair first. */
#define SORT_STACK 96
#define SORT_INLINE static inline __attribute__((always_inline))
SORT_INLINE size_t s2_sort_size(s2_sort_kind kind) {
    return kind.kind == SORT_GENERIC ? kind.size : 8;
}
/* Move one element of a sortable width: 1, 2, 4 or 8 bytes. */
SORT_INLINE void s2_sort_copy(unsigned char *to, const unsigned char *from, size_t size) {
    switch (size) {
    case 1: memcpy(to, from, 1); return;
    case 2: memcpy(to, from, 2); return;
    case 4: memcpy(to, from, 4); return;
    default: memcpy(to, from, 8); return;
    }
}
SORT_INLINE int s2_sort_less(const unsigned char *left, const unsigned char *right, s2_sort_kind kind) {
    if (kind.reverse) { const unsigned char *held=left; left=right; right=held; }
    switch (kind.kind) {
    case SORT_I64: { int64_t a, b; memcpy(&a, left, 8); memcpy(&b, right, 8); return a < b; }
    case SORT_U64: { uint64_t a, b; memcpy(&a, left, 8); memcpy(&b, right, 8); return a < b; }
    case SORT_F64: { double a, b; memcpy(&a, left, 8); memcpy(&b, right, 8); return a < b || (isnan(b) && !isnan(a)); }
    case SORT_TEXT: {
        myl_block *a, *b;
        memcpy(&a, left, sizeof a);
        memcpy(&b, right, sizeof b);
        return s2_sort_block_compare(a, b) < 0;
    }
    case SORT_BYTES: {
        myl_block *a, *b;
        memcpy(&a, left, sizeof a);
        memcpy(&b, right, sizeof b);
        return s2_sort_block_compare(a, b) < 0;
    }
    default: return (kind.order == 0 ? s2_compare_signed(left, right, kind.size) : s2_compare_unsigned(left, right, kind.size)) < 0;
    }
}
/* Length of the natural run that starts at `start`, left ascending: a strictly
   descending run is reversed in place, which cannot reorder equal elements
   because it holds none. */
SORT_INLINE size_t s2_sort_natural_run(unsigned char *base, size_t start, size_t end, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind), last = start + 1;
    if (last == end) return 1;
    if (s2_sort_less(base + last * size, base + start * size, kind)) {
        while (last + 1 < end && s2_sort_less(base + (last + 1) * size, base + last * size, kind)) last++;
        unsigned char held[8];
        for (size_t low = start, high = last; low < high; low++, high--) {
            s2_sort_copy(held, base + low * size, size);
            s2_sort_copy(base + low * size, base + high * size, size);
            s2_sort_copy(base + high * size, held, size);
        }
    } else {
        while (last + 1 < end && !s2_sort_less(base + (last + 1) * size, base + last * size, kind)) last++;
    }
    return last - start + 1;
}
/* Extend the ascending run [start, sorted) to [start, end) by stable
   insertion: each element moves left only past elements greater than it. */
SORT_INLINE void s2_sort_insertion(unsigned char *base, size_t start, size_t sorted, size_t end, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind);
    unsigned char held[8];
    for (size_t i = sorted; i < end; i++) {
        if (!s2_sort_less(base + i * size, base + (i - 1) * size, kind)) continue;
        s2_sort_copy(held, base + i * size, size);
        size_t j = i;
        do {
            s2_sort_copy(base + j * size, base + (j - 1) * size, size);
            j--;
        } while (j > start && s2_sort_less(held, base + (j - 1) * size, kind));
        s2_sort_copy(base + j * size, held, size);
    }
}
/* How many leading elements of the ascending `run` are not greater than
   `value`: the place a stable merge gives `value` when it comes from the right. */
SORT_INLINE size_t s2_sort_upper_bound(const unsigned char *run, size_t count, const unsigned char *value, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind), low = 0, high = count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (s2_sort_less(value, run + middle * size, kind)) high = middle;
        else low = middle + 1;
    }
    return low;
}
/* How many leading elements of the ascending `run` are less than `value`: the
   place a stable merge gives `value` when it comes from the left. */
SORT_INLINE size_t s2_sort_lower_bound(const unsigned char *run, size_t count, const unsigned char *value, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind), low = 0, high = count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (s2_sort_less(run + middle * size, value, kind)) low = middle + 1;
        else high = middle;
    }
    return low;
}
/* One comparison of two 8-byte elements held in registers. */
SORT_INLINE int s2_sort_less_words(uint64_t left, uint64_t right, s2_sort_kind kind) {
    unsigned char a[8], b[8];
    memcpy(a, &left, 8);
    memcpy(b, &right, 8);
    return s2_sort_less(a, b, kind);
}
/* Merge the adjacent ascending runs [first, middle) and [middle, last). Only
   the stretch the two runs actually interleave over moves; the shorter side of
   it goes to `scratch`, which holds at least half the list.

   For 8-byte elements the bulk of the merge runs while both sides still hold
   two elements: the element after each side's head is loaded before the
   comparison that picks one, so advancing is a pair of selects rather than a
   load that has to wait for the comparison. The element loop finishes the
   last few elements and serves the narrower widths. */
SORT_INLINE void s2_sort_merge(unsigned char *base, size_t first, size_t middle, size_t last, unsigned char *scratch, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind);
    first += s2_sort_upper_bound(base + first * size, middle - first, base + middle * size, kind);
    if (first == middle) return;
    last = middle + s2_sort_lower_bound(base + middle * size, last - middle, base + (middle - 1) * size, kind);
    size_t left = middle - first, right = last - middle;
    /* The first remaining left value exceeds the first right value. The
       last left value is at least as large, so the lower trim retains that
       first right value; both runs are nonempty here. */
    /* Strictly separated runs need only exchange their positions. Keep each
       run's order, and buffer the shorter side in the same reserved scratch.
       Equality must retain the ordinary stable merge: rotating equal boundary
       values would put right-run ties before their earlier left-run peers. */
    if (s2_sort_less(base + (last - 1) * size, base + first * size, kind)) {
        if (left <= right) {
            memcpy(scratch, base + first * size, left * size);
            memmove(base + first * size, base + middle * size, right * size);
            memcpy(base + (first + right) * size, scratch, left * size);
        } else {
            memcpy(scratch, base + middle * size, right * size);
            memmove(base + (first + right) * size, base + first * size, left * size);
            memcpy(base + first * size, scratch, right * size);
        }
        return;
    }
    if (left <= right) {
        /* Forward: the left run waits in scratch, the output never overtakes
           the unread right elements, and whatever of the right run is left
           over is already in place. */
        memcpy(scratch, base + first * size, left * size);
        const unsigned char *a = scratch, *a_end = scratch + left * size;
        const unsigned char *b = base + middle * size, *b_end = base + last * size;
        unsigned char *out = base + first * size;
        while (kind.kind != SORT_GENERIC) {
            size_t a_left = (size_t)(a_end - a) / 8, b_left = (size_t)(b_end - b) / 8;
            size_t steps = a_left < b_left ? a_left : b_left;
            if (steps < 2) break;
            uint64_t x, y;
            memcpy(&x, a, 8);
            memcpy(&y, b, 8);
            for (steps--; steps; steps--) {
                int take_right = s2_sort_less_words(y, x, kind);
                uint64_t chosen = take_right ? y : x, x_next, y_next;
                memcpy(out, &chosen, 8);
                out += 8;
                memcpy(&x_next, a + 8, 8);
                memcpy(&y_next, b + 8, 8);
                a += take_right ? 0 : 8;
                b += take_right ? 8 : 0;
                x = take_right ? x : x_next;
                y = take_right ? y_next : y;
            }
        }
        while (a < a_end && b < b_end) {
            int take_right = s2_sort_less(b, a, kind);
            s2_sort_copy(out, take_right ? b : a, size);
            out += size;
            b += take_right ? size : 0;
            a += take_right ? 0 : size;
        }
        if (a < a_end) memcpy(out, a, (size_t)(a_end - a));
    } else {
        /* Backward: the right run waits in scratch and the larger element of
           each pair goes last, the right one on a tie; whatever of the left
           run is left over is already in place. */
        memcpy(scratch, base + middle * size, right * size);
        const unsigned char *a = base + middle * size, *a_begin = base + first * size;
        const unsigned char *b = scratch + right * size;
        unsigned char *out = base + last * size;
        while (kind.kind != SORT_GENERIC) {
            size_t a_left = (size_t)(a - a_begin) / 8, b_left = (size_t)(b - scratch) / 8;
            size_t steps = a_left < b_left ? a_left : b_left;
            if (steps < 2) break;
            uint64_t x, y;
            memcpy(&x, a - 8, 8);
            memcpy(&y, b - 8, 8);
            for (steps--; steps; steps--) {
                int take_left = s2_sort_less_words(y, x, kind);
                uint64_t chosen = take_left ? x : y, x_next, y_next;
                out -= 8;
                memcpy(out, &chosen, 8);
                memcpy(&x_next, a - 16, 8);
                memcpy(&y_next, b - 16, 8);
                a -= take_left ? 8 : 0;
                b -= take_left ? 0 : 8;
                x = take_left ? x_next : x;
                y = take_left ? y : y_next;
            }
        }
        while (a > a_begin && b > scratch) {
            int take_left = s2_sort_less(b - size, a - size, kind);
            out -= size;
            s2_sort_copy(out, take_left ? a - size : b - size, size);
            a -= take_left ? size : 0;
            b -= take_left ? 0 : size;
        }
        if (b > scratch) memcpy(out - (b - scratch), scratch, (size_t)(b - scratch));
    }
}
/* A run length in [SORT_MINRUN_LIMIT / 2, SORT_MINRUN_LIMIT] such that
   `count / minrun` is a power of two or just under one, as in listsort. */
static size_t s2_sort_minrun(size_t count) {
    size_t low_bits = 0;
    while (count >= SORT_MINRUN_LIMIT) {
        low_bits |= count & 1;
        count >>= 1;
    }
    return count + low_bits;
}
/* The powersort depth of the boundary between the adjacent runs
   [start, start + left) and [start + left, start + left + right) of a list of
   `total` elements: the first bit at which the two runs' midpoints, as
   fractions of the list, differ. */
static int s2_sort_power(size_t start, size_t left, size_t right, size_t total) {
    int power = 0;
    size_t a = 2 * start + left, b = a + left + right;
    for (;;) {
        ++power;
        if (a >= total) {
            a -= total;
            b -= total;
        } else if (b >= total) {
            break;
        }
        a <<= 1;
        b <<= 1;
    }
    return power;
}
SORT_INLINE int s2_sort_elements(unsigned char *base, size_t count, s2_sort_kind kind) {
    size_t size = s2_sort_size(kind), minrun = s2_sort_minrun(count);
    unsigned char *scratch = NULL;
    if (count > minrun) {
        scratch = malloc(count / 2 * size);
        if (!scratch) return 0;
    }
    s2_sort_run stack[SORT_STACK];
    size_t depth = 0, start = 0;
    for (;;) {
        /* Power 0 once the input is exhausted, which merges everything left. */
        int power = 0;
        size_t length = 0;
        if (start < count) {
            length = s2_sort_natural_run(base, start, count, kind);
            if (length < minrun) {
                size_t end = count - start < minrun ? count : start + minrun;
                s2_sort_insertion(base, start, start + length, end, kind);
                length = end - start;
            }
            if (depth) power = s2_sort_power(stack[depth - 1].start, stack[depth - 1].length, length, count);
        }
        while (depth > 1 && (stack[depth - 2].power > power || depth == SORT_STACK)) {
            s2_sort_run *left = &stack[depth - 2], *right = &stack[depth - 1];
            s2_sort_merge(base, left->start, right->start, right->start + right->length, scratch, kind);
            left->length += right->length;
            depth--;
        }
        if (start >= count) break;
        if (depth) stack[depth - 1].power = power;
        stack[depth++] = (s2_sort_run){ .start = start, .length = length, .power = 0 };
        start += length;
    }
    free(scratch);
    return 1;
}
static int s2_sort_i64(unsigned char *base, size_t count) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_I64, .order = 0, .size = 8 });
}
static int s2_sort_u64(unsigned char *base, size_t count) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_U64, .order = 1, .size = 8 });
}
static int s2_sort_f64(unsigned char *base, size_t count) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_F64, .order = 2, .size = 8 });
}
static int s2_sort_text(unsigned char *base, size_t count) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_TEXT, .order = 3, .size = 8 });
}
static int s2_sort_bytes(unsigned char *base, size_t count) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_BYTES, .order = 4, .size = 8 });
}
static int s2_sort_generic(unsigned char *base, size_t count, unsigned order, size_t size) {
    return s2_sort_elements(base, count, (s2_sort_kind){ .kind = SORT_GENERIC, .order = order, .size = size });
}

/* `values.sort(key=..., reverse=...)` after the guest has computed every key
   once, in input order, into `keys`: a decorated sort. The keys decide an
   order of positions. When `values` is `source`, one pass of cycle-following
   moves the elements into that order, so the list is sorted in place and
   keeps its identity, length, capacity and generation. Otherwise `values` is
   an empty list with room for them all, and the elements of `source` are
   gathered into it in order: `sorted(xs, key=...)` builds its copy already
   sorted, with no copy to permute afterwards.

   A key is one scalar or a flat tuple of them. Field `i` of `shape` is the
   four bits at `4 + 4 * i`: the low two bits are its kind (signed, unsigned,
   binary64 or text) and the high two its width (8, 4, 2 or 1 bytes); the low
   four bits of `shape` are the field count. Byte `i` of `offsets` is field
   `i`'s offset inside one key.

   A numeric key becomes one order-preserving 64-bit word: a signed integer
   with its sign bit flipped, an unsigned one as it is, and a binary64 value
   with its bits reflected, signed zeros made one and every NaN the largest
   word, so NaNs sort after every ordered value. `reverse` complements the
   word, so the order is the descending one while ties still come in input
   order: reverse is not sort-then-reverse. When every word minus the
   smallest fits above the position bits, the word and its position are packed
   into one integer and sorted by the integer engine; this is the common case
   and it reuses the key list's own storage for the packed words. Keys spread
   wider take two such sorts, 32 bits each. Text keys and tuples sort
   (key, position) entries with a stable merge that compares fields in order.

   Nothing here calls guest code or allocates managed memory, so no collection
   runs while elements sit in the temporary. On an allocation failure it
   returns 0 before any element has moved; the key list may by then hold
   packed words, which the guest never reads again. */
enum { KEY_SIGNED, KEY_UNSIGNED, KEY_FLOAT, KEY_TEXT, KEY_BYTES };
typedef struct { unsigned count; unsigned char kind[8], size[8], offset[8]; } s2_key_shape;
static int s2_key_shape_decode(uint64_t shape, uint64_t offsets, size_t stride, s2_key_shape *out) {
    static const unsigned char widths[4] = { 8, 4, 2, 1 };
    out->count = (unsigned)(shape & 15);
    if (out->count == 0 || out->count > 8) return 0;
    for (unsigned i = 0; i < out->count; i++) {
        unsigned field = (unsigned)(shape >> (4 + 4 * i)) & 15;
        /* Nibble 7 used to be invalid text/width4. Preserve every old code. */
        out->kind[i] = field == 7 ? KEY_BYTES : (unsigned char)(field & 3);
        out->size[i] = field == 7 ? 8 : widths[field >> 2];
        out->offset[i] = (unsigned char)(offsets >> (8 * i));
        if ((out->kind[i] == KEY_FLOAT || out->kind[i] == KEY_TEXT) && out->size[i] != 8) return 0;
        if ((size_t)out->offset[i] + out->size[i] > stride) return 0;
    }
    return 1;
}
/* One numeric key field as a word whose unsigned order is the key order. */
static inline uint64_t s2_key_word(const unsigned char *at, unsigned kind, unsigned size) {
    if (kind == KEY_FLOAT) {
        double value;
        memcpy(&value, at, 8);
        if (isnan(value)) return UINT64_MAX;
        if (value == 0) value = 0;
        uint64_t bits;
        memcpy(&bits, &value, 8);
        return bits >> 63 ? ~bits : bits | (UINT64_C(1) << 63);
    }
    if (kind == KEY_SIGNED) {
        int64_t value;
        switch (size) {
        case 1: { int8_t x; memcpy(&x, at, 1); value = x; break; }
        case 2: { int16_t x; memcpy(&x, at, 2); value = x; break; }
        case 4: { int32_t x; memcpy(&x, at, 4); value = x; break; }
        default: memcpy(&value, at, 8); break;
        }
        return (uint64_t)value ^ (UINT64_C(1) << 63);
    }
    switch (size) {
    case 1: { uint8_t x; memcpy(&x, at, 1); return x; }
    case 2: { uint16_t x; memcpy(&x, at, 2); return x; }
    case 4: { uint32_t x; memcpy(&x, at, 4); return x; }
    default: { uint64_t x; memcpy(&x, at, 8); return x; }
    }
}
/* Three-way comparison of key field `field` of two keys. */
static inline int s2_key_field_compare(const unsigned char *left, const unsigned char *right, const s2_key_shape *shape, unsigned field) {
    const unsigned char *a = left + shape->offset[field], *b = right + shape->offset[field];
    if (shape->kind[field] == KEY_TEXT) {
        myl_block *x, *y;
        memcpy(&x, a, sizeof x);
        memcpy(&y, b, sizeof y);
        int order = s2_sort_block_compare(x, y);
        return order < 0 ? -1 : order > 0;
    }
    if (shape->kind[field] == KEY_BYTES) {
        myl_block *x, *y;
        memcpy(&x, a, sizeof x);
        memcpy(&y, b, sizeof y);
        return s2_sort_block_compare(x, y);
    }
    uint64_t x = s2_key_word(a, shape->kind[field], shape->size[field]);
    uint64_t y = s2_key_word(b, shape->kind[field], shape->size[field]);
    return x < y ? -1 : x > y;
}
/* How far ahead along a cycle the permutation prefetches the element it will
   move next. */
#define KEYED_LOOKAHEAD 8
/* Move every element into the slot `order` names for it: slot `i` receives
   the element at `order[i]`. Each cycle is followed once and marked done by
   setting `order[j] = j`, through one element-sized temporary.

   Following a cycle is a chain of dependent loads, so it runs at memory
   latency unless the next elements are already on their way. The positions
   are first narrowed to 32 bits in place, which halves the table the chain
   walks and keeps more of it in cache, and a second cursor runs
   KEYED_LOOKAHEAD steps ahead on the same cycle, prefetching the element each
   step will read. */
static void s2_keyed_permute(s2_sort_list *values, uint64_t *wide, size_t count, unsigned char *held) {
    size_t size = values->element->size;
    unsigned char *base = values->storage;
    if (size == 0) return;
    uint32_t *order = (uint32_t *)wide;
    if (count <= UINT32_MAX) {
        /* Entry `i` is read at byte 8i before it is written at byte 4i. */
        for (size_t i = 0; i < count; i++) order[i] = (uint32_t)wide[i];
    }
    for (size_t i = 0; i < count; i++) {
        size_t first = count <= UINT32_MAX ? order[i] : (size_t)wide[i];
        if (first == i) continue;
        s2_copy_element(held, base + i * size, size);
        size_t j = i, ahead = i;
        for (int step = 0; step < KEYED_LOOKAHEAD && (step == 0 || ahead != i); step++) {
            ahead = count <= UINT32_MAX ? order[ahead] : (size_t)wide[ahead];
            __builtin_prefetch(base + ahead * size);
        }
        for (;;) {
            size_t k;
            if (count <= UINT32_MAX) {
                k = order[j];
                order[j] = (uint32_t)j;
            } else {
                k = (size_t)wide[j];
                wide[j] = j;
            }
            if (k == i) {
                s2_copy_element(base + j * size, held, size);
                break;
            }
            if (ahead != i) {
                ahead = count <= UINT32_MAX ? order[ahead] : (size_t)wide[ahead];
                __builtin_prefetch(base + ahead * size);
            }
            s2_copy_element(base + j * size, base + k * size, size);
            j = k;
        }
    }
}
/* Where the ordered elements go: back into `source` itself along the
   permutation's cycles (an in-place sort, through `held`), or gathered in
   order from `source` into the empty list `values` (a sorted copy). */
typedef struct { s2_sort_list *values; const s2_sort_list *source; unsigned char *held; } s2_keyed_target;
static void s2_keyed_place(const s2_keyed_target *target, uint64_t *order, size_t count) {
    if (target->values == target->source) {
        s2_keyed_permute(target->values, order, count, target->held);
        return;
    }
    size_t size = target->source->element->size;
    unsigned char *out = target->values->storage;
    const unsigned char *in = target->source->storage;
    for (size_t i = 0; i < count; i++) s2_copy_element(out + i * size, in + (size_t)order[i] * size, size);
    target->values->length = count;
    target->values->generation++;
}
/* Move every element to the slot `dest` names for it: the element at `i`
   goes to `dest[i]`. In place this follows each cycle once, carrying one
   element in `held` and marking each handled position `dest[p] = p`, with the
   same narrowed table and lookahead prefetch as s2_keyed_permute; for a copy it
   scatters the elements into the empty target. */
static void s2_keyed_place_dest(const s2_keyed_target *target, uint64_t *wide, size_t count) {
    size_t size = target->source->element->size;
    if (target->values != target->source) {
        unsigned char *out = target->values->storage;
        const unsigned char *in = target->source->storage;
        for (size_t i = 0; i < count; i++) s2_copy_element(out + (size_t)wide[i] * size, in + i * size, size);
        target->values->length = count;
        target->values->generation++;
        return;
    }
    unsigned char *base = target->values->storage, *held = target->held;
    if (size == 0) return;
    /* count <= UINT32_MAX here: the counting path requires it. */
    uint32_t *dest = (uint32_t *)wide;
    for (size_t i = 0; i < count; i++) dest[i] = (uint32_t)wide[i];
    unsigned char *swap = held + size;
    for (size_t i = 0; i < count; i++) {
        if (dest[i] == i) continue;
        s2_copy_element(held, base + i * size, size);
        size_t p = i, ahead = i;
        for (int step = 0; step < KEYED_LOOKAHEAD && (step == 0 || ahead != i); step++) {
            ahead = dest[ahead];
            __builtin_prefetch(base + ahead * size);
        }
        for (;;) {
            size_t d = dest[p];
            dest[p] = (uint32_t)p;
            if (d == i) {
                s2_copy_element(base + i * size, held, size);
                break;
            }
            if (ahead != i) {
                ahead = dest[ahead];
                __builtin_prefetch(base + ahead * size);
            }
            s2_copy_element(swap, base + d * size, size);
            s2_copy_element(base + d * size, held, size);
            s2_copy_element(held, swap, size);
            p = d;
        }
    }
}
/* A single numeric key whose words span fewer values than there are
   elements: a stable counting sort. One pass counts each key, a prefix sum
   turns the counts into first slots, and a second pass gives each element,
   in input order, the next slot of its key — so equal keys keep input order
   without any comparison. */
static int s2_keyed_count(const s2_keyed_target *target, s2_sort_list *keys, const s2_key_shape *shape, uint64_t flip, uint64_t low, uint64_t span) {
    size_t count = target->source->length, stride = keys->element->size;
    const unsigned char *rows = keys->storage;
    unsigned kind = shape->kind[0], size = shape->size[0], offset = shape->offset[0];
    uint32_t *slots = calloc((size_t)span + 1, sizeof *slots);
    if (!slots) return 0;
    for (size_t i = 0; i < count; i++) slots[(s2_key_word(rows + i * stride + offset, kind, size) ^ flip) - low]++;
    uint32_t next = 0;
    for (uint64_t b = 0; b <= span; b++) {
        uint32_t here = slots[b];
        slots[b] = next;
        next += here;
    }
    int own = stride == 8 && offset == 0 && keys != target->values && keys != target->source;
    uint64_t *dest = own ? (uint64_t *)keys->storage : malloc(count * 8);
    if (!dest) {
        free(slots);
        return 0;
    }
    for (size_t i = 0; i < count; i++) dest[i] = slots[(s2_key_word(rows + i * stride + offset, kind, size) ^ flip) - low]++;
    free(slots);
    s2_keyed_place_dest(target, dest, count);
    if (!own) free(dest);
    return 1;
}
typedef struct { uint64_t word; uint64_t position; } s2_keyed_entry;
typedef struct { const unsigned char *keys; size_t stride; const s2_key_shape *shape; unsigned reverse; } s2_keyed_order;
/* Whether entry `a` goes strictly before entry `b`. A single text key is
   carried in the entry itself; any other key is read from its row. */
static inline int s2_keyed_less(const s2_keyed_entry *a, const s2_keyed_entry *b, const s2_keyed_order *by) {
    const s2_keyed_entry *x = by->reverse ? b : a, *y = by->reverse ? a : b;
    if (by->shape->count == 1 && by->shape->kind[0] == KEY_TEXT) {
        myl_block *p, *q;
        memcpy(&p, &x->word, sizeof p);
        memcpy(&q, &y->word, sizeof q);
        return s2_sort_block_compare(p, q) < 0;
    }
    if (by->shape->count == 1 && by->shape->kind[0] == KEY_BYTES) {
        myl_block *p, *q;
        memcpy(&p, &x->word, sizeof p);
        memcpy(&q, &y->word, sizeof q);
        return s2_sort_block_compare(p, q) < 0;
    }
    const unsigned char *left = by->keys + (size_t)x->position * by->stride;
    const unsigned char *right = by->keys + (size_t)y->position * by->stride;
    for (unsigned field = 0; field < by->shape->count; field++) {
        int order = s2_key_field_compare(left, right, by->shape, field);
        if (order) return order < 0;
    }
    return 0;
}
/* Stable bottom-up merge of entries: insertion-sorted blocks of 16, then
   passes that merge adjacent blocks between `entries` and `spare`, taking
   the left entry on a tie. Returns the array holding the result. */
static s2_keyed_entry *s2_keyed_merge_sort(s2_keyed_entry *entries, s2_keyed_entry *spare, size_t count, const s2_keyed_order *by) {
    for (size_t start = 0; start < count; start += 16) {
        size_t end = count - start < 16 ? count : start + 16;
        for (size_t i = start + 1; i < end; i++) {
            s2_keyed_entry held = entries[i];
            size_t j = i;
            while (j > start && s2_keyed_less(&held, &entries[j - 1], by)) {
                entries[j] = entries[j - 1];
                j--;
            }
            entries[j] = held;
        }
    }
    s2_keyed_entry *from = entries, *to = spare;
    for (size_t width = 16; width < count; width *= 2) {
        for (size_t start = 0; start < count; start += 2 * width) {
            size_t middle = count - start < width ? count : start + width;
            size_t end = count - middle < width ? count : middle + width;
            size_t a = start, b = middle, out = start;
            while (a < middle && b < end) to[out++] = s2_keyed_less(&from[b], &from[a], by) ? from[b++] : from[a++];
            while (a < middle) to[out++] = from[a++];
            while (b < end) to[out++] = from[b++];
        }
        s2_keyed_entry *swap = from;
        from = to;
        to = swap;
    }
    return from;
}
static int s2_keyed_sort_entries(const s2_keyed_target *target, const s2_sort_list *keys, const s2_key_shape *shape, unsigned reverse) {
    size_t count = target->source->length, stride = keys->element->size;
    if (count > SIZE_MAX / (2 * sizeof(s2_keyed_entry))) return 0;
    s2_keyed_entry *entries = malloc(2 * count * sizeof *entries);
    if (!entries) return 0;
    const unsigned char *rows = keys->storage;
    for (size_t i = 0; i < count; i++) {
        entries[i].position = i;
        entries[i].word = 0;
        if (shape->count == 1 && (shape->kind[0] == KEY_TEXT || shape->kind[0] == KEY_BYTES)) memcpy(&entries[i].word, rows + i * stride + shape->offset[0], 8);
    }
    s2_keyed_order by = { .keys = rows, .stride = stride, .shape = shape, .reverse = reverse };
    s2_keyed_entry *sorted = s2_keyed_merge_sort(entries, entries + count, count, &by);
    uint64_t *order = (uint64_t *)entries;
    /* Entry `i` is 16 bytes and position `i` is 8, so compacting forward
       never overwrites an entry not yet read, whichever half holds them. */
    for (size_t i = 0; i < count; i++) order[i] = sorted[i].position;
    s2_keyed_place(target, order, count);
    free(entries);
    return 1;
}
/* One numeric key: pack `(word - low) << bits | position` into one integer
   per element when that fits, else sort by the low 32 bits of the word and
   then, stably, by the high 32 bits. */
static int s2_keyed_sort_words(const s2_keyed_target *target, s2_sort_list *keys, const s2_key_shape *shape, unsigned reverse) {
    size_t count = target->source->length, stride = keys->element->size;
    const unsigned char *rows = keys->storage;
    unsigned kind = shape->kind[0], size = shape->size[0], offset = shape->offset[0];
    uint64_t flip = reverse ? UINT64_MAX : 0, low = UINT64_MAX, high = 0;
    for (size_t i = 0; i < count; i++) {
        uint64_t word = s2_key_word(rows + i * stride + offset, kind, size) ^ flip;
        low = word < low ? word : low;
        high = word > high ? word : high;
    }
    if (count <= UINT32_MAX && high - low < count) return s2_keyed_count(target, keys, shape, flip, low, high - low);
    unsigned bits = 1;
    while (bits < 63 && ((uint64_t)1 << bits) < count) bits++;
    uint64_t mask = ((uint64_t)1 << bits) - 1;
    if (((high - low) >> (64 - bits)) == 0) {
        /* The words replace the keys one for one, so they are written into
           the key list's storage when it has 8-byte keys of its own, not the
           elements themselves. */
        int own = stride == 8 && offset == 0 && keys != target->values && keys != target->source;
        uint64_t *words = own ? (uint64_t *)keys->storage : malloc(count * 8);
        if (!words) return 0;
        for (size_t i = 0; i < count; i++) words[i] = ((s2_key_word(rows + i * stride + offset, kind, size) ^ flip) - low) << bits | i;
        if (!s2_sort_u64((unsigned char *)words, count)) {
            if (!own) free(words);
            return 0;
        }
        for (size_t i = 0; i < count; i++) words[i] &= mask;
        s2_keyed_place(target, words, count);
        if (!own) free(words);
        return 1;
    }
    if (bits > 32) return s2_keyed_sort_entries(target, keys, shape, reverse);
    uint64_t *by_low = malloc(count * 8), *by_high = malloc(count * 8);
    if (!by_low || !by_high) {
        free(by_low);
        free(by_high);
        return 0;
    }
    for (size_t i = 0; i < count; i++) by_low[i] = ((s2_key_word(rows + i * stride + offset, kind, size) ^ flip) & UINT32_MAX) << bits | i;
    int sorted = s2_sort_u64((unsigned char *)by_low, count);
    for (size_t rank = 0; sorted && rank < count; rank++) {
        uint64_t word = s2_key_word(rows + (by_low[rank] & mask) * stride + offset, kind, size) ^ flip;
        by_high[rank] = (word >> 32) << bits | rank;
    }
    if (sorted) sorted = s2_sort_u64((unsigned char *)by_high, count);
    if (sorted) {
        for (size_t i = 0; i < count; i++) by_high[i] = by_low[by_high[i] & mask] & mask;
        s2_keyed_place(target, by_high, count);
    }
    free(by_low);
    free(by_high);
    return sorted;
}
static int s2_sort_list_sort_keyed(s2_sort_list *values, s2_sort_list *source, s2_sort_list *keys, uint64_t shape, uint64_t offsets, uint64_t reverse) {
    s2_key_shape decoded;
    if (!source || !keys || keys->length != source->length) return 0;
    size_t count = source->length, size = source->element->size;
    /* A sorted copy gathers into an empty list with room for every element. */
    if (values != source && (values->length != 0 || values->capacity < count || values->element->size != size)) return 0;
    if (!s2_key_shape_decode(shape, offsets, keys->element->size, &decoded)) return 0;
    if (count < 2) {
        uint64_t first = 0;
        if (values != source && count) s2_keyed_place(&(s2_keyed_target){ .values = values, .source = source }, &first, 1);
        return 1;
    }
    /* Two element-sized temporaries: the one carried along a cycle, and the
       one it is exchanged through. */
    unsigned char inline_held[128];
    unsigned char *held = values != source || 2 * size <= sizeof inline_held ? inline_held : malloc(2 * size);
    if (!held) return 0;
    s2_keyed_target target = { .values = values, .source = source, .held = held };
    int done = decoded.count == 1 && decoded.kind[0] != KEY_TEXT && decoded.kind[0] != KEY_BYTES
        ? s2_keyed_sort_words(&target, keys, &decoded, reverse != 0)
        : s2_keyed_sort_entries(&target, keys, &decoded, reverse != 0);
    if (held != inline_held) free(held);
    return done;
}
/* Consumes the unique list chosen by own.zig; no count traffic while sorting. */
myl_block *myl_core_s2_sort_in_place(myl_block *list, uint64_t code, bool reverse) {
    size_t size=code>>8, count=(size_t)list->len;
    unsigned order=(unsigned)(code&255);
    int ok;
    unsigned char *base=block_data(list);
    if (reverse) {
        unsigned type=order==2 ? SORT_F64 : order==3 ? SORT_TEXT : order==4 ? SORT_BYTES : size==8 ? (order==0 ? SORT_I64 : SORT_U64) : SORT_GENERIC;
        ok=s2_sort_elements(base,count,(s2_sort_kind){ .kind=type,.order=order,.size=size,.reverse=1 });
    } else if (order==2) ok=s2_sort_f64(base,count);
    else if (order==3) ok=s2_sort_text(base,count);
    else if (order==4) ok=s2_sort_bytes(base,count);
    else if (size==8) ok=order==0 ? s2_sort_i64(base,count) : s2_sort_u64(base,count);
    else ok=s2_sort_generic(base,count,order,size);
    if (!ok) _Exit(1);
    return list;
}

/* Borrow source and keys, return one sorted owning copy. Never mutate borrowed keys. */
myl_block *myl_core_s2_sort_keyed(myl_block *source, myl_block *keys, uint64_t shape, uint64_t offsets, bool reverse, uint64_t strides) {
    size_t size=(size_t)(strides&UINT32_MAX), key_size=(size_t)(strides>>32);
    myl_block *values=myl_core_list_copy(source,(int64_t)size);
    myl_block *key_copy=myl_core_list_copy(keys,(int64_t)key_size);
    s2_sort_element element={size}, key_element={key_size};
    /* The clone already owns exactly the source's reference multiset. Gather
       its permutation straight from source; cycle moves would copy records
       repeatedly and needlessly reserve two element temporaries. */
    s2_sort_list v={ 0,(size_t)values->cap,0,block_data(values),&element };
    s2_sort_list s={ (size_t)source->len,(size_t)source->cap,0,block_data(source),&element };
    s2_sort_list k={ (size_t)key_copy->len,(size_t)key_copy->cap,0,block_data(key_copy),&key_element };
    int ok=s2_sort_list_sort_keyed(&v,&s,&k,shape,offsets,reverse);
    /* The numeric engine overwrites keys with packed words: release their
       original managed references only on the untouched text/tuple path. */
    myl_core_release(key_copy);
    if (!ok) _Exit(1);
    return values;
}

/* Number/text support, concatenated after the block and text runtimes.
   The inline LLVM fast path admits only plain digits up to eight places;
   this fallback preserves the full pinned whitespace/sign/underscore grammar. */
#include <stddef.h>
static bool ascii_space(unsigned char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'; }

/* The independent Zig formatter allocates only through this Core-block adapter. */
myl_block *myl_core_number_text_new(size_t length) {
    if (length > INT64_MAX) out_of_memory();
    myl_block *text = str_new((int64_t)length);
    text->kind |= 1u << 8;
    return text;
}

/* Invalid packed formats or impossible bounded-frame failures are internal errors. */
_Noreturn void myl_core_number_text_invalid(void) { abort(); }

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


static const char core_number_pairs[] =
    "00010203040506070809" "10111213141516171819"
    "20212223242526272829" "30313233343536373839"
    "40414243444546474849" "50515253545556575859"
    "60616263646566676869" "70717273747576777879"
    "80818283848586878889" "90919293949596979899";

static const uint64_t core_number_powers[] = {
    1ULL, 10ULL, 100ULL, 1000ULL, 10000ULL, 100000ULL,
    1000000ULL, 10000000ULL, 100000000ULL, 1000000000ULL,
    10000000000ULL, 100000000000ULL, 1000000000000ULL,
    10000000000000ULL, 100000000000000ULL, 1000000000000000ULL,
    10000000000000000ULL, 100000000000000000ULL,
    1000000000000000000ULL, 10000000000000000000ULL
};

static unsigned core_number_length(uint64_t value) {
    if (!value) return 1;
    unsigned estimate = ((64u - (unsigned)__builtin_clzll(value)) * 1233u) >> 12;
    return estimate + (value >= core_number_powers[estimate]);
}

/* Two digits per division, backwards into an exactly sized destination. */
static void core_number_write(unsigned char *end, uint64_t value) {
    while (value >= 100) {
        unsigned pair = (unsigned)(value % 100);
        value /= 100;
        end -= 2;
        memcpy(end, core_number_pairs + pair * 2, 2);
    }
    if (value >= 10) {
        end -= 2;
        memcpy(end, core_number_pairs + value * 2, 2);
    } else *--end = (unsigned char)('0' + value);
}

myl_block *myl_core_str_from_i64(int64_t value) {
    bool negative = value < 0;
    uint64_t magnitude = negative ? -(uint64_t)value : (uint64_t)value;
    unsigned length = core_number_length(magnitude) + negative;
    myl_block *text = str_new(length);
    text->kind |= 1u << 8; /* published ASCII flag */
    unsigned char *data = block_data(text);
    core_number_write(data + length, magnitude);
    if (negative) data[0] = '-';
    return text;
}

myl_block *myl_core_str_from_u64(uint64_t value) {
    unsigned length = core_number_length(value);
    myl_block *text = str_new(length);
    text->kind |= 1u << 8;
    core_number_write(block_data(text) + length, value);
    return text;
}

void myl_core_print_i64(int64_t fd, int64_t value) {
    unsigned char buffer[32];
    bool negative = value < 0;
    uint64_t magnitude = negative ? -(uint64_t)value : (uint64_t)value;
    unsigned length = core_number_length(magnitude) + negative;
    core_number_write(buffer + length, magnitude);
    if (negative) buffer[0] = '-';
    stream_write(stream_for(fd), buffer, length);
}

void myl_core_print_u64(int64_t fd, uint64_t value) {
    unsigned char buffer[32];
    unsigned length = core_number_length(value);
    core_number_write(buffer + length, value);
    stream_write(stream_for(fd), buffer, length);
}

/* Port of native_bytes' clamped byte-range parsing; no temporary decoded text. */
static int64_t core_number_endpoint(int64_t index, int64_t length) {
    if (index < 0) index += length;
    return index < 0 ? 0 : index > length ? length : index;
}
static bool core_parse_int_range(myl_block *source, int64_t start, int64_t end, int64_t *out) {
    start = core_number_endpoint(start, source->len);
    end = core_number_endpoint(end, source->len);
    if (end < start) end = start;
    /* Parse directly through a span helper, keeping the published source immutable. */
    const unsigned char *s = block_data(source) + start;
    size_t lower = 0, upper = (size_t)(end - start);
    while (lower < upper && ascii_space(s[lower])) ++lower;
    while (upper > lower && ascii_space(s[upper - 1])) --upper;
    bool negative = false;
    if (lower < upper && (s[lower] == '+' || s[lower] == '-')) negative = s[lower++] == '-';
    if (lower == upper) return false;
    uint64_t magnitude = 0, bound = (uint64_t)INT64_MAX + negative;
    bool digit_before = false;
    for (size_t i = lower; i < upper; ++i) {
        unsigned char c = s[i];
        if (c == '_') { if (!digit_before || i + 1 == upper) return false; digit_before = false; continue; }
        if (c < '0' || c > '9') return false;
        uint64_t digit = c - '0';
        if (magnitude > bound / 10 || (magnitude == bound / 10 && digit > bound % 10)) return false;
        magnitude = magnitude * 10 + digit;
        digit_before = true;
    }
    if (!digit_before) return false;
    int64_t value = negative ? (magnitude == (uint64_t)INT64_MAX + 1 ? INT64_MIN : -(int64_t)magnitude) : (int64_t)magnitude;
    *out = value;
    return true;
}

/* Core's scalar Option uses the low byte of the SysV integer result register;
   the second result register carries the scalar. Full-word C tags are 0 or 1. */
typedef struct { uint64_t tag; int64_t value; } myl_core_parsed_int;
_Static_assert(sizeof(myl_core_parsed_int) == 16, "Core scalar Option size");
_Static_assert(offsetof(myl_core_parsed_int, value) == 8, "Core scalar Option payload");
myl_core_parsed_int myl_core_parse_int_range(myl_block *source, int64_t start, int64_t end) {
    myl_core_parsed_int result = { 0, 0 };
    result.tag = core_parse_int_range(source, start, end, &result.value);
    return result;
}

/* Width-specific saturation uses a wider intermediate, including unsigned 64-bit
   multiplication whose full product exceeds signed 128-bit range. */
uint64_t myl_core_saturating_integer(uint64_t left, uint64_t right, uint32_t width, uint32_t mode) {
    if (mode & 1) {
        /* The caller sign-extends signed operands before the bit-preserving ABI. */
        __int128 a = (int64_t)left, b = (int64_t)right;
        __int128 value = (mode & 2) ? a * b : a - b;
        __int128 upper = ((__int128)1 << (width - 1)) - 1, lower = -upper - 1;
        return (uint64_t)(value > upper ? upper : value < lower ? lower : value);
    }
    uint64_t upper = width == 64 ? UINT64_MAX : (UINT64_C(1) << width) - 1;
    if (!(mode & 2)) return left < right ? 0 : left - right;
    __uint128_t product = (__uint128_t)left * right;
    return product > upper ? upper : (uint64_t)product;
}

static int core_io_utf8(const unsigned char *p,size_t n);
/* Core capability/provider/resource runtime. Algorithms ported from
 * native_scoped.c and qbe_stand_ins.c; no old runtime object or header is linked.
 * Authority and provider state use Core counted blocks; handles stay weakly
 * registered until closed, dropped or fatal process cleanup. */
#include <time.h>
typedef enum {
    CORE_IO_PROVIDER_OK = 0,
    CORE_IO_PROVIDER_UNAVAILABLE = 1,
    CORE_IO_PROVIDER_DENIED = 2,
    CORE_IO_PROVIDER_FAILED = 3,
    CORE_IO_PROVIDER_OUT_OF_MEMORY = 4,
    CORE_IO_PROVIDER_NO_CAPACITY = 5
} CoreIoProviderStatus;
/* The value member is meaningful only when status is CORE_IO_PROVIDER_OK. */
typedef struct { CoreIoProviderStatus status; int64_t value; } CoreIoClockResult;
typedef struct { CoreIoProviderStatus status; uint64_t value; } CoreIoRandomResult;
/* On success, present is 0 or 1; a present length fits the output capacity.
   Absent lengths and failed-result length/presence fields are ignored.
   Empty present values differ from absent values. Never report truncated success. */
typedef struct { CoreIoProviderStatus status; size_t length; int present; } CoreIoEnvironmentResult;
/* Acquisition success owns a handle; failure owns none. Completion success
   consumes it; completion failure keeps it core_io_scoped_live. Release never implies completion
   and must return without allocation, failure, or guest reentry. */
typedef struct { CoreIoProviderStatus status; uint64_t handle; } CoreIoResourceResult;
/* Transfers keep the handle core_io_scoped_live, including on errors. Success counts fit the
   borrowed buffer; read EOF is 0 or 1. Error count/EOF members are ignored. */
typedef struct { CoreIoProviderStatus status; size_t length; int eof; } CoreIoResourceRead;
typedef struct { CoreIoProviderStatus status; size_t length; } CoreIoResourceWrite;
typedef struct {
    void *context;
    unsigned permissions; /* read=1, write=2, core_io_scoped_complete=4; intersection only */
    CoreIoResourceResult (*acquire)(void *, const uint8_t *, size_t, unsigned);
    CoreIoProviderStatus (*complete)(void *, uint64_t);
    void (*release)(void *, uint64_t);
    CoreIoResourceRead (*read)(void *, uint64_t, uint8_t *, size_t);
    CoreIoResourceWrite (*write)(void *, uint64_t, const uint8_t *, size_t);
} CoreIoResourceProvider;

/* Copied preorder values. Nodes never contain guest addresses. Nominal names are
   exact compiler names; records/arrays have bits=0, variants have a tag in bits,
   domains have one backing-value child. Scalars have no children. */
typedef struct { const char *type; uint64_t bits; size_t children; } CoreIoHostNode;
typedef struct {
    const CoreIoHostNode *arguments;
    size_t argument_nodes;
    CoreIoHostNode *output;
    size_t capacity, output_nodes;
    uint64_t work_remaining;
    int exhausted;
} CoreIoHostCall;
/* Charge before effects. Failed charge is sticky even if a callback returns success. */
static inline int core_io_host_charge(CoreIoHostCall *call, uint64_t work) {
    if (call->exhausted || work > call->work_remaining) { call->exhausted=1;return 0; }
    call->work_remaining-=work;return 1;
}
/* Packed calls are an opt-in fast path for integers, padding-free fixed u8
   arrays and whole immutable `bytes` payloads. Every value points into
   runtime-owned scratch; callbacks may neither retain these copies nor reenter
   the generated program. Payloads have byte alignment only: use memcpy, never
   scalar pointer casts, to access integers.
   A fixed-shape output is runtime-owned scratch that starts zeroed and must
   keep its pointer and size; on success set output_written to exactly
   output.size. A `bytes` result is the one exception: the runtime hands over an
   empty output and the callback publishes its own read-only octets by setting
   output.bytes, output.size and an equal output_written. Those octets are
   copied into a fresh guest byte string before the runtime returns, so they
   need only outlive the callback, and the runtime never writes through them.
   A `bytes` argument arrives as a runtime-owned copy of the guest's octets
   whose size is that byte string's exact length. Return NULL or a static error
   name. */
typedef struct { void *bytes; size_t size; } CoreIoHostPackedValue;
typedef struct {
    const CoreIoHostPackedValue *arguments;
    size_t argument_count;
    CoreIoHostPackedValue output;
    size_t output_written;
    uint64_t work_remaining;
    int exhausted;
} CoreIoHostPackedCall;
static inline int core_io_host_packed_charge(CoreIoHostPackedCall *call, uint64_t work) {
    if (call->exhausted || work > call->work_remaining) { call->exhausted=1;return 0; }
    call->work_remaining-=work;return 1;
}
typedef struct {
    const char *name;
    const char *const *parameters;
    size_t parameter_count;
    const char *result;
    unsigned effects, grants;
    void *context;
    /* Return NULL on success or a static error name. Output nodes borrow this
       call's storage; type strings remain valid until copying completes. The
       callback must not retain call buffers or reenter the generated program. */
    const char *(*invoke)(void *, CoreIoHostCall *);
    /* Optional packed-copy callback. The runtime uses it only after validating
       an all-scalar/fixed-u8-array/`bytes` schema and equivalent node/depth
       quotas; a declaration naming `bytes` has no node-bridge fallback. */
    const char *(*invoke_packed)(void *, CoreIoHostPackedCall *);
} CoreIoHostBinding;
typedef struct {
    const CoreIoHostBinding *bindings;
    size_t count;
    /* Zero selects 10000 calls, 1000000 work, 65536 nodes, 64 levels. */
    uint64_t max_calls, max_work;
    size_t max_values, max_depth;
    /* Ceiling on one copied `bytes` argument or published `bytes` result, in
       octets. Zero selects 1 MiB; above 64 MiB the registry is rejected. */
    size_t max_payload;
} CoreIoHostRegistry;

typedef struct {
    void *clock_context;CoreIoClockResult (*clock_now)(void *);
    void *random_context;CoreIoRandomResult (*random_u64)(void *);
    void *environment_context;CoreIoEnvironmentResult (*environment_get)(void *,const uint8_t *,size_t,uint8_t *,size_t);
    CoreIoResourceProvider filesystem,network;CoreIoHostRegistry host;
} CoreIoNativeProviders;
extern CoreIoNativeProviders mylang_native_providers_v7(void) __attribute__((weak));
static CoreIoNativeProviders core_io_native;
static int core_io_embedding;

/* Directory-relative filesystem provider for native executables, mirroring
   src/scoped_providers.zig: a request is `<mode>:<path>` with mode `r`, `w`,
   `c` (exclusive create), `t` (truncate existing), `a`, `m` (metadata),
   `l` (core_io_scoped_listing), `k` (create directory) or `x` (remove entry). A relative path
   is tried against each granted root in order and the first success wins.
   These grants are an authority boundary for guest source, not a sandbox. */
#define CORE_IO_SCOPED_ROOTS 8
#define CORE_IO_SCOPED_HANDLES 256
#define CORE_IO_SCOPED_ENDPOINTS 8
/* A direct root applies the whole path at once and follows symlinks, so a
   relative path resolves against that directory and an absolute path names
   itself; every other root walks the path component by component. */
typedef struct { int fd; int writable, direct; } CoreIoScopedRoot;
/* An open file, an append-mode file, or one immutable copied snapshot. */
typedef struct { int fd; unsigned char *snapshot; size_t length, position; unsigned char mode; } CoreIoScopedHandle;
/* One granted literal `IP:PORT` endpoint, or `*` for every literal peer. */
typedef struct { char *name; size_t length; } CoreIoScopedEndpoint;
typedef struct {
    CoreIoScopedRoot roots[CORE_IO_SCOPED_ROOTS];
    size_t count;
    CoreIoScopedHandle handles[CORE_IO_SCOPED_HANDLES];
    CoreIoScopedEndpoint endpoints[CORE_IO_SCOPED_ENDPOINTS];
    size_t endpoint_count;
} CoreIoScoped;
/* Reset every root, handle slot and endpoint before the first core_io_scoped_grant. */
void core_io_scoped_init(CoreIoScoped *scoped);
/* Open one granted directory. Returns zero when it cannot be opened or when
   the core_io_scoped_grant limit is already reached; no guest file is acquired here. */
int core_io_scoped_grant(CoreIoScoped *scoped, const char *path, int writable);
/* Grant the working directory directly, the way an ordinary process sees it. */
int core_io_scoped_working_directory(CoreIoScoped *scoped);
/* Record one literal `IP:PORT` endpoint (or `*`), rejecting a malformed or
   repeated value. Returns zero when the core_io_scoped_grant cannot be recorded. */
int core_io_scoped_endpoint(CoreIoScoped *scoped, const char *name);
/* Close every remaining handle and every granted directory. */
void core_io_scoped_close(CoreIoScoped *scoped);
/* Borrow this stable context as a resource provider with those permissions. */
CoreIoResourceProvider core_io_scoped_provider(CoreIoScoped *scoped, unsigned permissions);
/* Borrow the same context as a TCP provider that dials only the granted
   literal endpoints; reads and writes reuse the filesystem handle slots. */
CoreIoResourceProvider core_io_scoped_network_provider(CoreIoScoped *scoped, unsigned permissions);

/* Directory-relative filesystem provider, mirroring src/scoped_providers.zig
   and src/scoped_directory.zig: validated relative requests, per-root write
   authority, and bounded copied metadata and core_io_scoped_listing snapshots. */
#define CORE_IO_SCOPED__POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#define CORE_IO_SCOPED_TRANSFER_LIMIT (64u * 1024u)
#define CORE_IO_SCOPED_SNAPSHOT_BYTES (64u * 1024u)
#define CORE_IO_SCOPED_SNAPSHOT_ENTRIES 256u
#define CORE_IO_SCOPED_NAME_LIMIT 4094u
static CoreIoProviderStatus core_io_scoped_from_errno(void) {
    switch (errno) {
        case ENOMEM: return CORE_IO_PROVIDER_OUT_OF_MEMORY;
        case EACCES: case EPERM: case ELOOP: case ENOTDIR: return CORE_IO_PROVIDER_DENIED;
        default: return CORE_IO_PROVIDER_FAILED;
    }
}
static int core_io_scoped_writing_mode(unsigned char mode) {
    return mode == 'w' || mode == 'a' || mode == 'c' || mode == 't' || mode == 'k' || mode == 'x';
}
/* Reject traversal before anything is opened, created or truncated. */
static int core_io_scoped_valid_path(const char *path, size_t length, unsigned char mode) {
    if (!length) return mode == 'm' || mode == 'l';
    if (memchr(path, '\\', length) || memchr(path, 0, length)) return 0;
    size_t start = 0;
    for (size_t i = 0; i <= length; ++i) {
        if (i != length && path[i] != '/') continue;
        size_t part = i - start;
        if (!part || (part == 1 && path[start] == '.')) return 0;
        if (part == 2 && path[start] == '.' && path[start + 1] == '.') return 0;
        start = i + 1;
    }
    return 1;
}
static size_t core_io_scoped_free_slot(const CoreIoScoped *scoped) {
    for (size_t i = 0; i < CORE_IO_SCOPED_HANDLES; ++i)
        if (scoped->handles[i].fd < 0 && !scoped->handles[i].snapshot) return i;
    return SIZE_MAX;
}
/* Open the parent directory of the final component without following links.
   Returns the root itself for a single-component path; the caller closes any
   other descriptor. */
static int core_io_scoped_walk(int root, const char *path, size_t length, size_t *last) {
    int parent = root;
    size_t start = 0;
    for (size_t i = 0; i < length; ++i) {
        if (path[i] != '/') continue;
        char name[CORE_IO_SCOPED_NAME_LIMIT + 1];
        size_t part = i - start;
        if (part > CORE_IO_SCOPED_NAME_LIMIT) { errno = ENAMETOOLONG; goto failure; }
        memcpy(name, path + start, part);
        name[part] = 0;
        int child = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (parent != root) close(parent);
        if (child < 0) return -1;
        parent = child;
        start = i + 1;
    }
    *last = start;
    return parent;
failure:
    if (parent != root) close(parent);
    return -1;
}
/* A scoped root opens its leaf without blocking, so a FIFO it is about to
   refuse cannot stall the guest waiting for a writer; the flag is cleared
   again once the leaf is known to be a regular file. The direct root blocks
   exactly as an ordinary `open` does. */
static int core_io_scoped_open_leaf(int parent, const char *name, unsigned char mode, int follow) {
    int waiting = follow ? 0 : O_NONBLOCK;
    if (mode == 'c') return openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | waiting, 0666);
    if (mode == 'a') return openat(parent, name, O_WRONLY | O_CREAT | O_CLOEXEC | waiting, 0666);
    int flags = mode == 'r' ? O_RDONLY : O_WRONLY;
    return openat(parent, name, flags | (follow ? 0 : O_NOFOLLOW) | O_CLOEXEC | waiting);
}
/* Whether a root may use the file `fd` opened. A scoped `--restrict` root serves
   regular files only. The default direct root carries the whole process's
   authority, so like C's `fopen` it also reads and writes a FIFO, a character
   device such as `/dev/null`, or a shell's process substitution `/dev/fd/N`; a
   directory is still refused there because it has no bytes to transfer. */
static int core_io_scoped_usable(CoreIoScopedRoot entry, int fd, const struct stat *info) {
    if (!entry.direct) return S_ISREG(info->st_mode) && fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK) == 0;
    return !S_ISDIR(info->st_mode);
}
static unsigned char core_io_scoped_kind_of(mode_t value) {
    if (S_ISREG(value)) return 1;
    if (S_ISDIR(value)) return 2;
    if (S_ISLNK(value)) return 3;
    return 0;
}
/* Copy one directory's entries into a bounded snapshot: a leading 1, then a
   kind byte, a little-endian u16 name length and the name for each entry. */
static unsigned char *core_io_scoped_listing(int parent, const char *name, size_t *length, CoreIoProviderStatus *status) {
    int fd = openat(parent, *name ? name : ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) { *status = core_io_scoped_from_errno(); return NULL; }
    DIR *directory = fdopendir(fd);
    if (!directory) { *status = core_io_scoped_from_errno(); close(fd); return NULL; }
    size_t capacity = 1024, used = 1, count = 0;
    unsigned char *bytes = malloc(capacity);
    *status = CORE_IO_PROVIDER_OUT_OF_MEMORY;
    if (bytes) bytes[0] = 1;
    struct dirent *entry;
    while (bytes && (errno = 0, entry = readdir(directory))) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        size_t width = strlen(entry->d_name);
        if (count >= CORE_IO_SCOPED_SNAPSHOT_ENTRIES || !width || width > CORE_IO_SCOPED_NAME_LIMIT) { *status = CORE_IO_PROVIDER_DENIED; free(bytes); bytes = NULL; break; }
        if (used > CORE_IO_SCOPED_SNAPSHOT_BYTES || width + 3 > CORE_IO_SCOPED_SNAPSHOT_BYTES - used) { *status = CORE_IO_PROVIDER_DENIED; free(bytes); bytes = NULL; break; }
        while (used + width + 3 > capacity) {
            unsigned char *grown = realloc(bytes, capacity * 2);
            if (!grown) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; free(bytes); bytes = NULL; break; }
            bytes = grown;
            capacity *= 2;
        }
        if (!bytes) break;
        struct stat info;
        unsigned char kind = 0;
        if (!fstatat(dirfd(directory), entry->d_name, &info, AT_SYMLINK_NOFOLLOW)) kind = core_io_scoped_kind_of(info.st_mode);
        bytes[used++] = kind;
        bytes[used++] = (unsigned char)(width & 0xff);
        bytes[used++] = (unsigned char)((width >> 8) & 0xff);
        memcpy(bytes + used, entry->d_name, width);
        used += width;
        count++;
    }
    closedir(directory);
    if (!bytes) return NULL;
    *status = CORE_IO_PROVIDER_OK;
    *length = used;
    return bytes;
}
/* One acknowledged core_io_scoped_change or metadata read, published as an immutable snapshot. */
static unsigned char *core_io_scoped_change(int parent, const char *name, unsigned char mode, size_t *length, CoreIoProviderStatus *status) {
    struct stat info;
    if (mode == 'm') {
        int failed = *name ? fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) : fstat(parent, &info);
        if (failed) { *status = core_io_scoped_from_errno(); return NULL; }
        unsigned char *bytes = malloc(10);
        if (!bytes) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
        bytes[0] = 1;
        bytes[1] = core_io_scoped_kind_of(info.st_mode);
        for (unsigned i = 0; i < 8; ++i) bytes[2 + i] = (unsigned char)(((uint64_t)info.st_size >> (8 * i)) & 0xff);
        *status = CORE_IO_PROVIDER_OK;
        *length = 10;
        return bytes;
    }
    if (!*name) { *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    if (mode == 'k') {
        if (mkdirat(parent, name, 0777)) { *status = core_io_scoped_from_errno(); return NULL; }
    } else if (unlinkat(parent, name, 0)) {
        if (errno != EISDIR && errno != EPERM) { *status = core_io_scoped_from_errno(); return NULL; }
        if (unlinkat(parent, name, AT_REMOVEDIR)) { *status = core_io_scoped_from_errno(); return NULL; }
    }
    unsigned char *bytes = malloc(1);
    if (!bytes) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    bytes[0] = 1;
    *status = CORE_IO_PROVIDER_OK;
    *length = 1;
    return bytes;
}
static CoreIoResourceResult core_io_scoped_acquire_in(CoreIoScoped *scoped, CoreIoScopedRoot entry, unsigned char mode, const char *path, size_t length) {
    CoreIoResourceResult result = {CORE_IO_PROVIDER_FAILED, 0};
    int root = entry.fd;
    size_t slot = core_io_scoped_free_slot(scoped);
    if (slot == SIZE_MAX) { result.status = CORE_IO_PROVIDER_DENIED; return result; }
    size_t last = 0;
    /* A direct root hands the whole path to one operation, the way an ordinary
       process resolves it; a scoped root opens each component without symlinks. */
    int parent = entry.direct ? root : core_io_scoped_walk(root, path, length, &last);
    if (parent < 0) { result.status = core_io_scoped_from_errno(); return result; }
    char name[CORE_IO_SCOPED_NAME_LIMIT + 1];
    size_t width = length - last;
    if (width > CORE_IO_SCOPED_NAME_LIMIT) { if (parent != root) close(parent); result.status = CORE_IO_PROVIDER_DENIED; return result; }
    memcpy(name, path + last, width);
    name[width] = 0;
    if (mode == 'm' || mode == 'l' || mode == 'k' || mode == 'x') {
        size_t bytes = 0;
        unsigned char *snapshot = mode == 'l' ? core_io_scoped_listing(parent, name, &bytes, &result.status) : core_io_scoped_change(parent, name, mode, &bytes, &result.status);
        if (parent != root) close(parent);
        if (!snapshot) return result;
        scoped->handles[slot] = (CoreIoScopedHandle){-1, snapshot, bytes, 0, mode};
        result.handle = slot;
        return result;
    }
    int fd = core_io_scoped_open_leaf(parent, name, mode, entry.direct);
    if (parent != root) close(parent);
    if (fd < 0) { result.status = core_io_scoped_from_errno(); return result; }
    struct stat info;
    if (fstat(fd, &info)) { result.status = core_io_scoped_from_errno(); close(fd); return result; }
    if (!core_io_scoped_usable(entry, fd, &info)) { result.status = CORE_IO_PROVIDER_DENIED; close(fd); return result; }
    /* Only a regular file has contents to truncate; a FIFO or device has none. */
    if (mode == 't' && S_ISREG(info.st_mode) && ftruncate(fd, 0)) { result.status = core_io_scoped_from_errno(); close(fd); return result; }
    scoped->handles[slot] = (CoreIoScopedHandle){fd, NULL, 0, 0, mode};
    result.status = CORE_IO_PROVIDER_OK;
    result.handle = slot;
    return result;
}
static CoreIoResourceResult core_io_scoped_acquire(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    CoreIoScoped *scoped = context;
    CoreIoResourceResult result = {CORE_IO_PROVIDER_DENIED, 0};
    if (!scoped->count) { result.status = CORE_IO_PROVIDER_UNAVAILABLE; return result; }
    if (length < 2 || length > 4096 || request[1] != ':') return result;
    unsigned char mode = request[0];
    int reading = mode == 'r' || mode == 'm' || mode == 'l';
    if (!reading && !core_io_scoped_writing_mode(mode)) return result;
    if (!(permissions & (reading ? 1u : 2u))) return result;
    const char *path = (const char *)request + 2;
    size_t width = length - 2;
    CoreIoProviderStatus failure = CORE_IO_PROVIDER_DENIED;
    for (size_t i = 0; i < scoped->count; ++i) {
        if (core_io_scoped_writing_mode(mode) && !scoped->roots[i].writable) continue;
        if (!scoped->roots[i].direct && !core_io_scoped_valid_path(path, width, mode)) continue;
        CoreIoResourceResult attempt = core_io_scoped_acquire_in(scoped, scoped->roots[i], mode, path, width);
        if (attempt.status == CORE_IO_PROVIDER_OK || attempt.status == CORE_IO_PROVIDER_OUT_OF_MEMORY) return attempt;
        failure = attempt.status;
    }
    result.status = failure;
    return result;
}
static void core_io_scoped_shut(CoreIoScopedHandle *handle) {
    if (handle->fd >= 0) close(handle->fd);
    free(handle->snapshot);
    *handle = (CoreIoScopedHandle){-1, NULL, 0, 0, 0};
}
static CoreIoScopedHandle *core_io_scoped_live(CoreIoScoped *scoped, uint64_t id) {
    if (id >= CORE_IO_SCOPED_HANDLES) return NULL;
    CoreIoScopedHandle *handle = &scoped->handles[id];
    return handle->fd >= 0 || handle->snapshot ? handle : NULL;
}
static CoreIoProviderStatus core_io_scoped_complete(void *context, uint64_t id) {
    CoreIoScopedHandle *handle = core_io_scoped_live(context, id);
    if (!handle) return CORE_IO_PROVIDER_FAILED;
    core_io_scoped_shut(handle);
    return CORE_IO_PROVIDER_OK;
}
static void core_io_scoped_release(void *context, uint64_t id) {
    CoreIoScopedHandle *handle = core_io_scoped_live(context, id);
    if (handle) core_io_scoped_shut(handle);
}
static CoreIoResourceRead core_io_scoped_read_handle(void *context, uint64_t id, uint8_t *output, size_t capacity) {
    CoreIoResourceRead result = {CORE_IO_PROVIDER_FAILED, 0, 0};
    CoreIoScopedHandle *handle = core_io_scoped_live(context, id);
    if (!handle) return result;
    /* A zero-size callback does not probe EOF, including immutable snapshots. */
    if (!capacity) { result.status = CORE_IO_PROVIDER_OK; return result; }
    if (capacity > CORE_IO_SCOPED_TRANSFER_LIMIT) capacity = CORE_IO_SCOPED_TRANSFER_LIMIT;
    if (handle->snapshot) {
        size_t available = handle->length - handle->position;
        size_t width = available < capacity ? available : capacity;
        memcpy(output, handle->snapshot + handle->position, width);
        handle->position += width;
        result.status = CORE_IO_PROVIDER_OK;
        result.length = width;
        result.eof = handle->position == handle->length;
        return result;
    }
    if (handle->mode == 'a') { result.status = CORE_IO_PROVIDER_DENIED; return result; }
    ssize_t width = read(handle->fd, output, capacity);
    if (width < 0) { result.status = core_io_scoped_from_errno(); return result; }
    result.status = CORE_IO_PROVIDER_OK;
    result.length = (size_t)width;
    result.eof = width == 0;
    return result;
}
static CoreIoResourceWrite core_io_scoped_write_handle(void *context, uint64_t id, const uint8_t *input, size_t length) {
    CoreIoResourceWrite result = {CORE_IO_PROVIDER_FAILED, 0};
    CoreIoScopedHandle *handle = core_io_scoped_live(context, id);
    if (!handle || handle->snapshot) { result.status = handle ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return result; }
    if (length > CORE_IO_SCOPED_TRANSFER_LIMIT) length = CORE_IO_SCOPED_TRANSFER_LIMIT;
    ssize_t width;
    if (handle->mode == 'a') {
        off_t end = lseek(handle->fd, 0, SEEK_END);
        if (end < 0) { result.status = core_io_scoped_from_errno(); return result; }
        width = pwrite(handle->fd, input, length, end);
    } else width = write(handle->fd, input, length);
    if (width < 0) { result.status = core_io_scoped_from_errno(); return result; }
    result.status = CORE_IO_PROVIDER_OK;
    result.length = (size_t)width;
    return result;
}
/* Parse one literal `IP:PORT` into a numeric address. No name resolution or
   redirect following occurs, so the core_io_scoped_grant and the connect name the same peer. */
static int core_io_scoped_endpoint_address(const char *name, struct sockaddr_in *address) {
    const char *colon = strrchr(name, ':');
    if (!colon || colon == name) return 0;
    char host[64];
    size_t width = (size_t)(colon - name);
    if (width >= sizeof host) return 0;
    memcpy(host, name, width);
    host[width] = 0;
    unsigned long port = strtoul(colon + 1, NULL, 10);
    if (!port || port > 65535) return 0;
    struct sockaddr_in parsed;
    memset(&parsed, 0, sizeof parsed);
    parsed.sin_family = AF_INET;
    parsed.sin_port = htons((unsigned short)port);
    if (inet_pton(AF_INET, host, &parsed.sin_addr) != 1) return 0;
    *address = parsed;
    return 1;
}
/* An allowlist entry is matched verbatim; `*` names every literal peer. */
static int core_io_scoped_endpoint_allowed(const CoreIoScoped *scoped, const char *name, size_t length) {
    for (size_t i = 0; i < scoped->endpoint_count; ++i) {
        const CoreIoScopedEndpoint *entry = &scoped->endpoints[i];
        if (entry->length == 1 && entry->name[0] == '*') return 1;
        if (entry->length == length && !memcmp(entry->name, name, length)) return 1;
    }
    return 0;
}
static int core_io_scoped_dial(const char *name) {
    struct sockaddr_in address;
    if (!core_io_scoped_endpoint_address(name, &address)) return -1;
    int handle = socket(AF_INET, SOCK_STREAM, 0);
    if (handle < 0) return -1;
    if (connect(handle, (struct sockaddr *)&address, sizeof address)) { close(handle); return -1; }
    return handle;
}
/* A narrowed Network substitutes its scoped endpoint for the guest request, so
   core_io_scoped_acquire sees exactly the literals the command line granted. */
static CoreIoResourceResult core_io_scoped_acquire_network(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    CoreIoScoped *scoped = context;
    CoreIoResourceResult result = {CORE_IO_PROVIDER_DENIED, 0};
    if (!scoped->endpoint_count) { result.status = CORE_IO_PROVIDER_UNAVAILABLE; return result; }
    if (!(permissions & (1u | 2u))) return result;
    char name[128];
    if (length >= sizeof name) return result;
    memcpy(name, request, length);
    name[length] = 0;
    if (!core_io_scoped_endpoint_allowed(scoped, name, length)) return result;
    size_t slot = core_io_scoped_free_slot(scoped);
    if (slot == SIZE_MAX) { result.status = CORE_IO_PROVIDER_DENIED; return result; }
    int handle = core_io_scoped_dial(name);
    if (handle < 0) { result.status = CORE_IO_PROVIDER_FAILED; return result; }
    scoped->handles[slot] = (CoreIoScopedHandle){handle, NULL, 0, 0, 0};
    result.status = CORE_IO_PROVIDER_OK;
    result.handle = slot;
    return result;
}
/* Record one literal endpoint (or `*`) before the first acquisition. */
int core_io_scoped_endpoint(CoreIoScoped *scoped, const char *name) {
    size_t length = strlen(name);
    if (!length || length > 4096 || scoped->endpoint_count >= CORE_IO_SCOPED_ENDPOINTS) return 0;
    if (!(length == 1 && name[0] == '*')) {
        struct sockaddr_in address;
        if (!core_io_scoped_endpoint_address(name, &address)) return 0;
    }
    for (size_t i = 0; i < scoped->endpoint_count; ++i) {
        const CoreIoScopedEndpoint *entry = &scoped->endpoints[i];
        if (entry->length == length && !memcmp(entry->name, name, length)) return 0;
    }
    char *copy = malloc(length + 1);
    if (!copy) return 0;
    memcpy(copy, name, length);
    copy[length] = 0;
    scoped->endpoints[scoped->endpoint_count].name = copy;
    scoped->endpoints[scoped->endpoint_count].length = length;
    scoped->endpoint_count++;
    return 1;
}
CoreIoResourceProvider core_io_scoped_network_provider(CoreIoScoped *scoped, unsigned permissions) {

    CoreIoResourceProvider provider = {0};
    provider.context = scoped;
    provider.permissions = permissions;
    provider.acquire = core_io_scoped_acquire_network;
    provider.complete = core_io_scoped_complete;
    provider.release = core_io_scoped_release;
    provider.read = core_io_scoped_read_handle;
    provider.write = core_io_scoped_write_handle;
    return provider;
}
void core_io_scoped_init(CoreIoScoped *scoped) {
    memset(scoped, 0, sizeof *scoped);
    for (size_t i = 0; i < CORE_IO_SCOPED_HANDLES; ++i) scoped->handles[i].fd = -1;
}
static int core_io_scoped_grant_impl(CoreIoScoped *scoped, const char *path, int writable, int direct) {
    if (scoped->count >= CORE_IO_SCOPED_ROOTS) return 0;
    int fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return 0;
    scoped->roots[scoped->count++] = (CoreIoScopedRoot){fd, writable, direct};
    return 1;
}
int core_io_scoped_grant(CoreIoScoped *scoped, const char *path, int writable) {
    return core_io_scoped_grant_impl(scoped, path, writable, 0);
}
int core_io_scoped_working_directory(CoreIoScoped *scoped) {
    return core_io_scoped_grant_impl(scoped, ".", 1, 1);
}
void core_io_scoped_close(CoreIoScoped *scoped) {
    for (size_t i = 0; i < CORE_IO_SCOPED_HANDLES; ++i)
        if (scoped->handles[i].fd >= 0 || scoped->handles[i].snapshot) core_io_scoped_shut(&scoped->handles[i]);
    for (size_t i = 0; i < scoped->count; ++i) close(scoped->roots[i].fd);
    scoped->count = 0;
    for (size_t i = 0; i < scoped->endpoint_count; ++i) free(scoped->endpoints[i].name);
    scoped->endpoint_count = 0;
}
CoreIoResourceProvider core_io_scoped_provider(CoreIoScoped *scoped, unsigned permissions) {

    CoreIoResourceProvider provider = {0};
    provider.context = scoped;
    provider.permissions = permissions;
    provider.acquire = core_io_scoped_acquire;
    provider.complete = core_io_scoped_complete;
    provider.release = core_io_scoped_release;
    provider.read = core_io_scoped_read_handle;
    provider.write = core_io_scoped_write_handle;
    return provider;
}

/* Bounds shared with the host-granted surface. */
#define CORE_IO_MEMORY_NAME_LIMIT 128u
#define CORE_IO_MEMORY_VALUE_LIMIT 16384u
#define CORE_IO_MEMORY_NAMES_LIMIT 64u
#define CORE_IO_MEMORY_MEMORY_HANDLES 256u
#define CORE_IO_MEMORY_MEMORY_BYTES (64u * 1024u * 1024u)
#define CORE_IO_MEMORY_PATH_LIMIT 4094u
#define CORE_IO_MEMORY_SNAPSHOT_BYTES (64u * 1024u)
#define CORE_IO_MEMORY_SNAPSHOT_ENTRIES 256u

/* One file or directory of an in-memory filesystem, named by its full
   relative path. An entry removed while a handle holds it stays allocated
   until that handle is released, as an unlinked POSIX file does. */
typedef struct MemoryEntry {
    char *path;
    size_t length;
    int directory, unlinked;
    unsigned char *bytes;
    size_t size, capacity;
    unsigned open;
} MemoryEntry;
/* An open file (entry, position, mode) or one immutable copied snapshot. */
typedef struct { int core_io_memory_live; MemoryEntry *entry; unsigned char *snapshot; size_t length, position; unsigned char mode; } MemoryHandle;
typedef struct {
    MemoryEntry **entries;
    size_t count, capacity, bytes;
    MemoryHandle handles[CORE_IO_MEMORY_MEMORY_HANDLES];
} MemoryFs;

/* ---- in-memory filesystem ------------------------------------------------ */

/* The scoped-root path rule: relative, no empty, `.` or `..` component, no NUL
   or backslash. An empty path names the root and only metadata/core_io_memory_listing take it. */
static int core_io_memory_valid_path(const unsigned char *path, size_t length, unsigned char mode) {
    if (!length) return mode == 'm' || mode == 'l';
    if (length > CORE_IO_MEMORY_PATH_LIMIT || memchr(path, '\\', length) || memchr(path, 0, length)) return 0;
    size_t start = 0;
    for (size_t i = 0; i <= length; ++i) {
        if (i != length && path[i] != '/') continue;
        size_t part = i - start;
        if (!part || (part == 1 && path[start] == '.')) return 0;
        if (part == 2 && path[start] == '.' && path[start + 1] == '.') return 0;
        start = i + 1;
    }
    return 1;
}
static MemoryEntry *core_io_memory_find(MemoryFs *memory, const unsigned char *path, size_t length) {
    for (size_t i = 0; i < memory->count; ++i) {
        MemoryEntry *entry = memory->entries[i];
        if (entry->length == length && !memcmp(entry->path, path, length)) return entry;
    }
    return NULL;
}
/* Whether every ancestor of `path` is an existing directory: OK, FAILED for a
   missing one, DENIED for one that is a file (POSIX ENOENT and ENOTDIR). */
static CoreIoProviderStatus core_io_memory_parents(MemoryFs *memory, const unsigned char *path, size_t length) {
    for (size_t i = 0; i < length; ++i) {
        if (path[i] != '/') continue;
        MemoryEntry *ancestor = core_io_memory_find(memory, path, i);
        if (!ancestor) return CORE_IO_PROVIDER_FAILED;
        if (!ancestor->directory) return CORE_IO_PROVIDER_DENIED;
    }
    return CORE_IO_PROVIDER_OK;
}
static MemoryEntry *core_io_memory_create(MemoryFs *memory, const unsigned char *path, size_t length, int directory) {
    if (memory->count == memory->capacity) {
        size_t grown = memory->capacity ? memory->capacity * 2 : 16;
        MemoryEntry **entries = realloc(memory->entries, grown * sizeof *entries);
        if (!entries) return NULL;
        memory->entries = entries;
        memory->capacity = grown;
    }
    MemoryEntry *entry = calloc(1, sizeof *entry);
    char *copy = malloc(length + 1);
    if (!entry || !copy) { free(entry); free(copy); return NULL; }
    memcpy(copy, path, length);
    copy[length] = 0;
    entry->path = copy;
    entry->length = length;
    entry->directory = directory;
    memory->entries[memory->count++] = entry;
    return entry;
}
static void core_io_memory_entry_free(MemoryEntry *entry) {
    free(entry->path);
    free(entry->bytes);
    free(entry);
}
static void core_io_memory_unlink_entry(MemoryFs *memory, MemoryEntry *entry) {
    for (size_t i = 0; i < memory->count; ++i) {
        if (memory->entries[i] != entry) continue;
        memory->entries[i] = memory->entries[--memory->count];
        break;
    }
    memory->bytes -= entry->size;
    if (entry->open) entry->unlinked = 1;
    else core_io_memory_entry_free(entry);
}
static int core_io_memory_has_children(MemoryFs *memory, const MemoryEntry *directory) {
    for (size_t i = 0; i < memory->count; ++i) {
        const MemoryEntry *entry = memory->entries[i];
        if (entry->length > directory->length && entry->path[directory->length] == '/' && !memcmp(entry->path, directory->path, directory->length)) return 1;
    }
    return 0;
}
static size_t core_io_memory_free_handle(const MemoryFs *memory) {
    for (size_t i = 0; i < CORE_IO_MEMORY_MEMORY_HANDLES; ++i) if (!memory->handles[i].core_io_memory_live) return i;
    return SIZE_MAX;
}
/* The final component of an entry's path, which is how a core_io_memory_listing names it. */
static const char *core_io_memory_leaf(const MemoryEntry *entry, size_t *width) {
    const char *slash = NULL;
    for (size_t i = 0; i < entry->length; ++i) if (entry->path[i] == '/') slash = entry->path + i;
    const char *start = slash ? slash + 1 : entry->path;
    *width = entry->length - (size_t)(start - entry->path);
    return start;
}
static int core_io_memory_in_directory(const MemoryEntry *entry, const unsigned char *path, size_t length) {
    if (!length) return !memchr(entry->path, '/', entry->length);
    if (entry->length <= length + 1 || entry->path[length] != '/' || memcmp(entry->path, path, length)) return 0;
    return !memchr(entry->path + length + 1, '/', entry->length - length - 1);
}
static int core_io_memory_leaf_order(const void *a, const void *b) {
    size_t left_width, right_width;
    const char *left = core_io_memory_leaf(*(MemoryEntry *const *)a, &left_width), *right = core_io_memory_leaf(*(MemoryEntry *const *)b, &right_width);
    size_t shortest = left_width < right_width ? left_width : right_width;
    int order = shortest ? memcmp(left, right, shortest) : 0;
    if (order) return order;
    return left_width < right_width ? -1 : left_width > right_width ? 1 : 0;
}
/* The same snapshot the scoped provider publishes: a leading 1, then a kind
   byte, a little-endian u16 name length and the name per entry. Entries are
   sorted by name, so a core_io_memory_listing never depends on insertion order. */
static unsigned char *core_io_memory_listing(MemoryFs *memory, const unsigned char *path, size_t length, size_t *size, CoreIoProviderStatus *status) {
    if (length) {
        MemoryEntry *directory = core_io_memory_find(memory, path, length);
        if (!directory) { *status = CORE_IO_PROVIDER_FAILED; return NULL; }
        if (!directory->directory) { *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    }
    MemoryEntry **children = malloc((memory->count ? memory->count : 1) * sizeof *children);
    if (!children) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    size_t count = 0, bytes = 1;
    for (size_t i = 0; i < memory->count; ++i) {
        if (!core_io_memory_in_directory(memory->entries[i], path, length)) continue;
        size_t width;
        (void)core_io_memory_leaf(memory->entries[i], &width);
        children[count++] = memory->entries[i];
        bytes += width + 3;
    }
    if (count > CORE_IO_MEMORY_SNAPSHOT_ENTRIES || bytes > CORE_IO_MEMORY_SNAPSHOT_BYTES) { free(children); *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    qsort(children, count, sizeof *children, core_io_memory_leaf_order);
    unsigned char *snapshot = malloc(bytes);
    if (!snapshot) { free(children); *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    size_t used = 0;
    snapshot[used++] = 1;
    for (size_t i = 0; i < count; ++i) {
        size_t width;
        const char *name = core_io_memory_leaf(children[i], &width);
        snapshot[used++] = children[i]->directory ? 2 : 1;
        snapshot[used++] = (unsigned char)(width & 0xff);
        snapshot[used++] = (unsigned char)((width >> 8) & 0xff);
        memcpy(snapshot + used, name, width);
        used += width;
    }
    free(children);
    *status = CORE_IO_PROVIDER_OK;
    *size = used;
    return snapshot;
}
/* Metadata (`m`), `mkdir` (`k`) and `remove` (`x`) as one acknowledged snapshot. */
static unsigned char *core_io_memory_change(MemoryFs *memory, const unsigned char *path, size_t length, unsigned char mode, size_t *size, CoreIoProviderStatus *status) {
    MemoryEntry *entry = length ? core_io_memory_find(memory, path, length) : NULL;
    *status = CORE_IO_PROVIDER_OK;
    if (mode == 'm') {
        if (length && !entry) { *status = core_io_memory_parents(memory, path, length) == CORE_IO_PROVIDER_DENIED ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return NULL; }
        unsigned char *bytes = malloc(10);
        if (!bytes) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
        bytes[0] = 1;
        bytes[1] = !entry || entry->directory ? 2 : 1;
        uint64_t width = entry ? entry->size : 0;
        for (unsigned i = 0; i < 8; ++i) bytes[2 + i] = (unsigned char)((width >> (8 * i)) & 0xff);
        *size = 10;
        return bytes;
    }
    if (!length) { *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    if (mode == 'k') {
        CoreIoProviderStatus chain = core_io_memory_parents(memory, path, length);
        if (chain != CORE_IO_PROVIDER_OK) { *status = chain; return NULL; }
        if (entry) { *status = CORE_IO_PROVIDER_FAILED; return NULL; }
        if (!core_io_memory_create(memory, path, length, 1)) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    } else {
        if (!entry) { *status = core_io_memory_parents(memory, path, length) == CORE_IO_PROVIDER_DENIED ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return NULL; }
        if (entry->directory && core_io_memory_has_children(memory, entry)) { *status = CORE_IO_PROVIDER_FAILED; return NULL; }
        core_io_memory_unlink_entry(memory, entry);
    }
    unsigned char *bytes = malloc(1);
    if (!bytes) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    bytes[0] = 1;
    *size = 1;
    return bytes;
}
/* Open a file entry for `r`, `c` (exclusive core_io_memory_create), `t` (truncate an existing
   file) or `a` (append, creating it), with the POSIX outcome of each. */
static MemoryEntry *core_io_memory_open_file(MemoryFs *memory, const unsigned char *path, size_t length, unsigned char mode, CoreIoProviderStatus *status) {
    CoreIoProviderStatus chain = core_io_memory_parents(memory, path, length);
    if (chain != CORE_IO_PROVIDER_OK) { *status = chain; return NULL; }
    MemoryEntry *entry = core_io_memory_find(memory, path, length);
    if (entry && entry->directory) { *status = CORE_IO_PROVIDER_DENIED; return NULL; }
    if (mode == 'c' && entry) { *status = CORE_IO_PROVIDER_FAILED; return NULL; }
    if ((mode == 'r' || mode == 't') && !entry) { *status = CORE_IO_PROVIDER_FAILED; return NULL; }
    if (!entry) {
        entry = core_io_memory_create(memory, path, length, 0);
        if (!entry) { *status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return NULL; }
    }
    if (mode == 't') { memory->bytes -= entry->size; entry->size = 0; }
    *status = CORE_IO_PROVIDER_OK;
    return entry;
}
static CoreIoResourceResult core_io_memory_acquire(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    MemoryFs *memory = context;
    CoreIoResourceResult result = {CORE_IO_PROVIDER_DENIED, 0};
    if (length < 2 || length > CORE_IO_MEMORY_PATH_LIMIT + 2 || request[1] != ':') return result;
    unsigned char mode = request[0];
    int reading = mode == 'r' || mode == 'm' || mode == 'l';
    int writing = mode == 'c' || mode == 't' || mode == 'a' || mode == 'k' || mode == 'x';
    if ((!reading && !writing) || !(permissions & (reading ? 1u : 2u))) return result;
    const unsigned char *path = request + 2;
    size_t width = length - 2;
    if (!core_io_memory_valid_path(path, width, mode)) return result;
    size_t slot = core_io_memory_free_handle(memory);
    if (slot == SIZE_MAX) return result;
    MemoryHandle *handle = &memory->handles[slot];
    if (mode == 'm' || mode == 'l' || mode == 'k' || mode == 'x') {
        size_t size = 0;
        unsigned char *snapshot = mode == 'l' ? core_io_memory_listing(memory, path, width, &size, &result.status) : core_io_memory_change(memory, path, width, mode, &size, &result.status);
        if (!snapshot) return result;
        *handle = (MemoryHandle){1, NULL, snapshot, size, 0, mode};
        result.handle = slot;
        return result;
    }
    MemoryEntry *entry = core_io_memory_open_file(memory, path, width, mode, &result.status);
    if (!entry) return result;
    entry->open++;
    *handle = (MemoryHandle){1, entry, NULL, 0, 0, mode};
    result.handle = slot;
    return result;
}
static MemoryHandle *core_io_memory_live(MemoryFs *memory, uint64_t id) {
    if (id >= CORE_IO_MEMORY_MEMORY_HANDLES || !memory->handles[id].core_io_memory_live) return NULL;
    return &memory->handles[id];
}
static void core_io_memory_shut(MemoryHandle *handle) {
    if (handle->entry) {
        handle->entry->open--;
        if (handle->entry->unlinked && !handle->entry->open) core_io_memory_entry_free(handle->entry);
    }
    free(handle->snapshot);
    *handle = (MemoryHandle){0, NULL, NULL, 0, 0, 0};
}
static CoreIoProviderStatus core_io_memory_complete(void *context, uint64_t id) {
    MemoryHandle *handle = core_io_memory_live(context, id);
    if (!handle) return CORE_IO_PROVIDER_FAILED;
    core_io_memory_shut(handle);
    return CORE_IO_PROVIDER_OK;
}
static void core_io_memory_release(void *context, uint64_t id) {
    MemoryHandle *handle = core_io_memory_live(context, id);
    if (handle) core_io_memory_shut(handle);
}
static CoreIoResourceRead core_io_memory_read(void *context, uint64_t id, uint8_t *output, size_t capacity) {
    CoreIoResourceRead result = {CORE_IO_PROVIDER_FAILED, 0, 0};
    MemoryHandle *handle = core_io_memory_live(context, id);
    if (!handle) return result;
    if (!capacity) { result.status = CORE_IO_PROVIDER_OK; return result; }
    const unsigned char *bytes = handle->snapshot;
    size_t total = handle->length;
    if (handle->entry) {
        if (handle->mode != 'r') { result.status = handle->mode == 'a' ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return result; }
        bytes = handle->entry->bytes;
        total = handle->entry->size;
    }
    size_t available = handle->position < total ? total - handle->position : 0;
    size_t width = available < capacity ? available : capacity;
    if (width) memcpy(output, bytes + handle->position, width);
    handle->position += width;
    result.status = CORE_IO_PROVIDER_OK;
    result.length = width;
    result.eof = handle->position >= total;
    return result;
}
static CoreIoResourceWrite core_io_memory_write(void *context, uint64_t id, const uint8_t *input, size_t length) {
    MemoryFs *memory = context;
    CoreIoResourceWrite result = {CORE_IO_PROVIDER_FAILED, 0};
    MemoryHandle *handle = core_io_memory_live(memory, id);
    if (!handle || !handle->entry) { result.status = handle ? CORE_IO_PROVIDER_DENIED : CORE_IO_PROVIDER_FAILED; return result; }
    if (handle->mode == 'r') return result;
    MemoryEntry *entry = handle->entry;
    size_t at = handle->mode == 'a' ? entry->size : handle->position;
    if (at > entry->size || length > CORE_IO_MEMORY_MEMORY_BYTES - memory->bytes || at + length > CORE_IO_MEMORY_MEMORY_BYTES) return result;
    size_t end = at + length;
    if (end > entry->capacity) {
        size_t grown = entry->capacity ? entry->capacity : 64;
        while (grown < end) grown *= 2;
        unsigned char *bytes = realloc(entry->bytes, grown);
        if (!bytes) { result.status = CORE_IO_PROVIDER_OUT_OF_MEMORY; return result; }
        entry->bytes = bytes;
        entry->capacity = grown;
    }
    if (length) memcpy(entry->bytes + at, input, length);
    if (end > entry->size) {
        if (!entry->unlinked) memory->bytes += end - entry->size;
        entry->size = end;
    }
    handle->position = end;
    result.status = CORE_IO_PROVIDER_OK;
    result.length = length;
    return result;
}
static void core_io_memory_free(MemoryFs *memory) {
    for (size_t i = 0; i < CORE_IO_MEMORY_MEMORY_HANDLES; ++i) if (memory->handles[i].core_io_memory_live) core_io_memory_shut(&memory->handles[i]);
    for (size_t i = 0; i < memory->count; ++i) core_io_memory_entry_free(memory->entries[i]);
    free(memory->entries);
    free(memory);
}
/* A stand-in `Network` has no endpoint to reach; qbe_resources.c answers every
   acquisition with MYL_QBE_STAND_IN_DENIED before this would run. */
static CoreIoResourceResult core_io_memory_network_acquire(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    (void)context; (void)request; (void)length; (void)permissions;
    CoreIoResourceResult result = {CORE_IO_PROVIDER_DENIED, 0};
    return result;
}
static CoreIoProviderStatus core_io_memory_network_complete(void *context, uint64_t id) { (void)context; (void)id; return CORE_IO_PROVIDER_FAILED; }
static void core_io_memory_network_release(void *context, uint64_t id) { (void)context; (void)id; }

/* ---- environment ---------------------------------------------------------- */

/* Walk one NUL-terminated core_io_memory_field of a blob; returns its length or SIZE_MAX. */
static size_t core_io_memory_field(const unsigned char *blob, size_t length, size_t cursor) {
    const unsigned char *end = memchr(blob + cursor, 0, length - cursor);
    return end ? (size_t)(end - blob) - cursor : SIZE_MAX;
}
static int core_io_memory_valid_name(const unsigned char *name, size_t width) {
    return width && width <= CORE_IO_MEMORY_NAME_LIMIT && !memchr(name, '=', width) && core_io_utf8(name, width);
}
/* Validate `NAME\0VALUE\0...`: bounded, unique, nonempty names without `=`. */
static int core_io_memory_valid_pairs(const unsigned char *blob, size_t length) {
    size_t cursor = 0, count = 0;
    while (cursor < length) {
        size_t name = core_io_memory_field(blob, length, cursor);
        if (name == SIZE_MAX || !core_io_memory_valid_name(blob + cursor, name)) return 0;
        size_t value_at = cursor + name + 1;
        size_t value = value_at < length ? core_io_memory_field(blob, length, value_at) : SIZE_MAX;
        if (value == SIZE_MAX || value > CORE_IO_MEMORY_VALUE_LIMIT || ++count > CORE_IO_MEMORY_NAMES_LIMIT) return 0;
        for (size_t other = 0; other < cursor;) {
            size_t width = core_io_memory_field(blob, length, other);
            if (width == name && !memcmp(blob + other, blob + cursor, name)) return 0;
            other += width + 1;
            other += core_io_memory_field(blob, length, other) + 1;
        }
        cursor = value_at + value + 1;
    }
    return 1;
}
static int core_io_memory_blob_has(const unsigned char *blob, size_t length, const unsigned char *key, size_t width) {
    for (size_t cursor = 0; cursor < length;) {
        size_t name = core_io_memory_field(blob, length, cursor);
        if (name == width && !memcmp(blob + cursor, key, width)) return 1;
        cursor += name + 1;
    }
    return 0;
}



/* Raw validation follows native_text_utf8, without a legacy text object. */
static int core_io_utf8(const unsigned char *p,size_t n) {
    for (size_t i=0;i<n;) {
        unsigned a=p[i++];
        if(a<128) continue;
        unsigned need=a>=0xc2&&a<=0xdf?1:a>=0xe0&&a<=0xef?2:a>=0xf0&&a<=0xf4?3:99;
        if(need>n-i) return 0;
        unsigned b=p[i];
        if((a==0xe0&&b<0xa0)||(a==0xed&&b>=0xa0)||(a==0xf0&&b<0x90)||(a==0xf4&&b>=0x90))return 0;
        while(need--)if((p[i++]&0xc0)!=0x80)return 0;
    }
    return 1;
}
static myl_block *core_io_string(const void *bytes,size_t len,int text) {
    myl_block *value=block_new(text?MYL_KIND_STR:MYL_KIND_BYTES,(int64_t)len,1);
    value->len=(int64_t)len;
    if(len)memcpy(block_data(value),bytes,len);
    if(text){block_data(value)[len]=0;core_text_publish(value);}
    return value;
}
static void core_io_retain(myl_block *block) { if(block&&block->count!=MYL_SATURATED)++block->count; }
static const int32_t core_io_cap_layout[]={32,3,0,8,0,16,0,24,0};
static const int32_t core_io_resource_layout[]={64,1,0,0,0};
static const int32_t core_io_provider_layout[]={1,0,0};
static const int32_t core_io_result_pointer_layout[]={24,2,0,8,0,16,0};
static const int32_t core_io_result_scalar_layout[]={24,1,0,16,0};
static const int32_t core_io_list_layout[]={8,1,0,0,0};
typedef struct { unsigned family,rights;myl_block *provider,*parent,*scope; } CoreIoAuthority;
typedef struct { unsigned family,test;int64_t value;MemoryFs *memory;myl_block *pairs;CoreIoResourceProvider adapter; } CoreIoState;
typedef struct CoreIoResource { myl_block *authority;uint64_t handle;unsigned family,rights,open,text;struct CoreIoResource *previous,*next;myl_block *block; } CoreIoResource;
static CoreIoResource *core_io_tail;
static int64_t core_io_open_count;static unsigned core_io_family_open[2];
static CoreIoScoped core_io_real;
static int core_io_initialized,core_io_restricted,core_io_clock,core_io_entropy,core_io_environment,core_io_host;
static char *core_io_options;
static const char *core_io_names="";
static const char *core_io_enumerated_names="";
static uint64_t core_io_seed;
static CoreIoAuthority *core_io_authority(myl_block *block) { return (CoreIoAuthority *)block_data(block); }
static CoreIoState *core_io_state(myl_block *authority) { return (CoreIoState *)block_data(core_io_authority(authority)->provider); }
static void core_io_fail(const char *code) { core_io_failure(code); }

static myl_block *core_io_provider(unsigned family,int test,int64_t value,myl_block *pairs) {
    myl_block *block=block_new(8,(int64_t)sizeof(CoreIoState),1);block->len=1;block->reserved=(int64_t)(intptr_t)core_io_provider_layout;
    CoreIoState *state=(CoreIoState *)block_data(block);memset(state,0,sizeof *state);
    state->family=family;state->test=(unsigned)test;state->value=value;state->pairs=pairs;core_io_retain(pairs);
    if(family==2){
        if(!test&&core_io_embedding)state->adapter=core_io_native.filesystem;
        else if(test){state->memory=calloc(1,sizeof(MemoryFs));if(!state->memory)out_of_memory();state->adapter=(CoreIoResourceProvider){state->memory,7,core_io_memory_acquire,core_io_memory_complete,core_io_memory_release,core_io_memory_read,core_io_memory_write};}
        else state->adapter=core_io_scoped_provider(&core_io_real,7);
    } else if(family==3) state->adapter=!test&&core_io_embedding?core_io_native.network:test?(CoreIoResourceProvider){state,7,core_io_memory_network_acquire,core_io_memory_network_complete,core_io_memory_network_release,NULL,NULL}:core_io_scoped_network_provider(&core_io_real,7);
    return block;
}
static myl_block *core_io_cap(unsigned family,unsigned rights,myl_block *provider,myl_block *parent,myl_block *scope) {
    myl_block *block=block_new(6,sizeof(CoreIoAuthority),1);block->len=1;block->reserved=(int64_t)(intptr_t)core_io_cap_layout;
    *(CoreIoAuthority *)block_data(block)=(CoreIoAuthority){family,rights,provider,parent,scope};
    core_io_retain(provider);core_io_retain(parent);core_io_retain(scope);return block;
}
typedef struct CoreIoScratch {struct CoreIoScratch *next;unsigned char data[];} CoreIoScratch;
static CoreIoScratch *core_io_scratch_head;
static unsigned char *core_io_copy(const unsigned char *source,size_t length){CoreIoScratch *copy=malloc(sizeof(*copy)+(length?length:1));if(!copy)out_of_memory();copy->next=core_io_scratch_head;core_io_scratch_head=copy;if(source&&length)memcpy(copy->data,source,length);return copy->data;}
static void core_io_copy_free(unsigned char *bytes){CoreIoScratch **at=&core_io_scratch_head;while(*at&&(*at)->data!=bytes)at=&(*at)->next;if(!*at)core_io_fail("InvalidProvider");CoreIoScratch *copy=*at;*at=copy->next;free(copy);}
static void core_io_unlink(CoreIoResource *resource) {
    if(resource->previous)resource->previous->next=resource->next;
    if(resource->next)resource->next->previous=resource->previous;else core_io_tail=resource->previous;
    resource->previous=resource->next=NULL;--core_io_open_count;--core_io_family_open[resource->family-2];
}
static void core_io_close(CoreIoResource *resource) {
    if(!resource->open)return;
    CoreIoState *state=core_io_state(resource->authority);
    resource->open=0;core_io_unlink(resource);state->adapter.release(state->adapter.context,resource->handle);
}
static int64_t core_io_live_handles(void){return core_io_open_count;}
static void core_io_cleanup(void) {
    for(unsigned family=3;family>=2;--family){CoreIoResource *resource=core_io_tail;while(resource){CoreIoResource *previous=resource->previous;if(resource->family==family)core_io_close(resource);resource=previous;}}
    while(core_io_scratch_head){CoreIoScratch *copy=core_io_scratch_head;core_io_scratch_head=copy->next;free(copy);}
    if(core_io_initialized){core_io_scoped_close(&core_io_real);core_io_initialized=0;}
    free(core_io_options);core_io_options=NULL;core_host_cleanup();
}
static void core_io_finalize(myl_block *block) {
    if(kind_of(block)==7)core_io_close((CoreIoResource *)block_data(block));
    if(kind_of(block)==8){CoreIoState *state=(CoreIoState *)block_data(block);if(state->memory)core_io_memory_free(state->memory);myl_core_release(state->pairs);}
}
/* Three fields in an explicit result slot. Pointer/scalar helpers choose the
   matching child descriptor, never scanning a status or numeric word. */
static myl_block *core_io_result(int status,uint64_t value,myl_block *error,int pointer) {
    myl_block *box=block_new(MYL_KIND_BOX,24,1);box->len=1;
    box->reserved=(int64_t)(intptr_t)(pointer?core_io_result_pointer_layout:core_io_result_scalar_layout);
    uint64_t *data=(uint64_t *)block_data(box);data[0]=(uint64_t)status;data[1]=value;data[2]=(uint64_t)(uintptr_t)error;
    return box;
}
typedef struct {const char *path;int writable;} CoreIoGrant;
static CoreIoGrant core_io_grants[8];static size_t core_io_grant_count;
static const char *core_io_option_argument;
static void core_io_option_error(const char *format,const char *argument){char text[1024];int length=snprintf(text,sizeof text,format,argument);flush_all();os_write(2,(const unsigned char *)text,(size_t)(length<(int)sizeof text?length:(int)sizeof text-1));os_exit(2);}
static void core_io_bad_grant(void){core_io_option_error("mylang: the option %s is not a usable capability grant\n",core_io_option_argument);}
static void core_io_missing_grant(const char *flag){core_io_option_error("mylang: --restrict is active and this command line did not grant a capability the entry point requests; pass %s, or drop --restrict to grant every capability\n",flag);}
static void core_io_grant_request(const char *path,int writable){if(!*path||core_io_grant_count==8)core_io_bad_grant();for(size_t i=0;i<core_io_grant_count;++i)if(core_io_grants[i].writable==writable&&!strcmp(core_io_grants[i].path,path))core_io_bad_grant();core_io_grants[core_io_grant_count++]=(CoreIoGrant){path,writable};}
/* Core entry uses the same MYLANG_OPTIONS grant grammar as qbe_grants.c. */
static void core_io_initialize(void) {
    if(core_io_initialized)return;
    core_io_initialized=1;core_io_scoped_init(&core_io_real);
    if(mylang_native_providers_v7){core_io_native=mylang_native_providers_v7();core_io_embedding=1;}
    const char *options=getenv("MYLANG_OPTIONS");
    core_io_options=strdup(options?options:"");if(!core_io_options)out_of_memory();
    char *read=core_io_options,*write=read;
    while(*read){
        while(*read&&strchr(" \t\n\r",*read))++read;if(!*read)break;
        char *arg=write;int quoted=0;
        while(*read&&(quoted||!strchr(" \t\n\r",*read))){if(*read=='"'){quoted=!quoted;++read;}else if(quoted&&*read=='\\'&&read[1]){++read;*write++=*read++;}else *write++=*read++;}
        if(quoted)core_io_option_error("mylang: MYLANG_OPTIONS has an unterminated quote\n%s","");if(*read)++read;*write++=0;core_io_option_argument=arg;
        if(!strcmp(arg,"--restrict")){if(core_io_restricted)core_io_bad_grant();core_io_restricted=1;}
        else if(!strncmp(arg,"--allow-read=",13)){core_io_grant_request(arg+13,0);}
        else if(!strncmp(arg,"--allow-write=",14)){core_io_grant_request(arg+14,1);}
        else if(!strncmp(arg,"--allow-endpoint=",17)){if(!core_io_scoped_endpoint(&core_io_real,arg+17))core_io_bad_grant();}
        else if(!strcmp(arg,"--allow-clock")){if(core_io_clock)core_io_bad_grant();core_io_clock=1;}
        else if(!strcmp(arg,"--allow-host")){if(core_io_host)core_io_bad_grant();core_io_host=1;}
        else if(!strncmp(arg,"--allow-random",14)&&(arg[14]==0||arg[14]=='=')){if(core_io_entropy||(arg[14]&&!arg[15]))core_io_bad_grant();core_io_entropy=1;core_io_seed=arg[14]?strtoull(arg+15,NULL,10):0;}
        else if(!strncmp(arg,"--allow-env",11)&&(arg[11]==0||arg[11]=='=')){if(core_io_environment||(arg[11]&&!arg[12]))core_io_bad_grant();core_io_environment=1;core_io_names=arg[11]?arg+12:"";}
        else if(!strcmp(arg,"--allow-all")){if(core_io_clock||core_io_entropy||core_io_environment||core_io_host||core_io_grant_count||core_io_real.endpoint_count)core_io_bad_grant();core_io_clock=core_io_entropy=core_io_environment=core_io_host=1;core_io_grant_request(".",1);core_io_scoped_endpoint(&core_io_real,"*");}
        else if(!strncmp(arg,"--allow-",8)||!strncmp(arg,"--restrict",10))core_io_bad_grant();
        else core_io_option_error("mylang: MYLANG_OPTIONS names %s, which is not a runtime option\n",arg);
    }
    core_io_enumerated_names=core_io_names;
    if(core_io_restricted){core_io_embedding=0;for(size_t i=0;i<core_io_grant_count;++i)if(!core_io_scoped_grant(&core_io_real,core_io_grants[i].path,core_io_grants[i].writable))core_io_option_error("mylang: a requested directory grant could not be opened\n%s","");}
    if(!core_io_restricted){core_io_scoped_close(&core_io_real);core_io_scoped_init(&core_io_real);if(!core_io_embedding){if(!core_io_scoped_working_directory(&core_io_real))core_io_option_error("mylang: a requested directory grant could not be opened\n%s","");core_io_scoped_endpoint(&core_io_real,"*");}core_io_clock=core_io_environment=core_io_host=1;if(!core_io_entropy&&!core_io_embedding){struct timespec now={0};clock_gettime(CLOCK_REALTIME,&now);core_io_seed=(uint64_t)now.tv_sec*1000000000+(uint64_t)now.tv_nsec;}core_io_entropy=1;}
}
myl_block *myl_core_cap_grant(uint32_t family) {
    core_io_initialize();
    int available=core_io_embedding?(family==0?core_io_native.clock_now!=NULL:family==1?core_io_native.random_u64!=NULL:family==2?(core_io_native.filesystem.acquire&&core_io_native.filesystem.complete&&core_io_native.filesystem.release):family==3?(core_io_native.network.acquire&&core_io_native.network.complete&&core_io_native.network.release):core_io_native.environment_get!=NULL):family==0?core_io_clock:family==1?core_io_entropy:family==2?core_io_real.count!=0:family==3?core_io_real.endpoint_count!=0:core_io_environment;
    if(!available){const char *flag=family==0?"--allow-clock":family==1?"--allow-random":family==2?"--allow-read=DIR":family==3?"--allow-endpoint=IP:PORT":"--allow-env";core_io_missing_grant(flag);}
    unsigned rights=7;if(family==2&&core_io_restricted){rights=5;for(size_t i=0;i<core_io_real.count;++i)if(core_io_real.roots[i].writable)rights=7;}
    myl_block *provider=core_io_provider(family,0,(int64_t)core_io_seed,NULL);if(family==2||family==3){unsigned permissions=((CoreIoState *)block_data(provider))->adapter.permissions;if(permissions&~7u)core_io_fail("InvalidCapability");rights&=permissions;}myl_block *cap=core_io_cap(family,rights,provider,NULL,NULL);myl_core_release(provider);return cap;
}
int64_t myl_core_host_grant(void){core_io_initialize();if(!core_io_host)core_io_missing_grant("--allow-host");return -6;}
void myl_core_host_check(int64_t token){core_io_initialize();if(token!=-6||!core_io_host)core_io_fail("R_CAPABILITY");}
myl_block *myl_core_stand_in(uint32_t family,int64_t value){myl_block *state=core_io_provider(family,1,value,NULL);myl_block *cap=core_io_cap(family,7,state,NULL,NULL);myl_core_release(state);return cap;}
myl_block *myl_core_environment_fixed(myl_block *pairs){if(!core_io_memory_valid_pairs(block_data(pairs),(size_t)pairs->len))core_io_fail("R_ENVIRONMENT");myl_block *state=core_io_provider(4,1,0,pairs);myl_block *cap=core_io_cap(4,7,state,NULL,NULL);myl_core_release(state);return cap;}
int64_t myl_core_clock_advance(myl_block *clock,int64_t delta){CoreIoState *state=core_io_state(clock);if(state->family!=0)core_io_fail("InvalidCapability");if(!state->test)return 1;if((delta>0&&state->value>INT64_MAX-delta)||(delta<0&&state->value<INT64_MIN-delta))return 2;state->value+=delta;return 0;}
myl_block *myl_core_external_read(myl_block *cap,uint32_t family){CoreIoState *state=core_io_state(cap);if(state->family!=family||family>1)core_io_fail("InvalidCapability");uint64_t value=0;int status=0;if(family==0){if(state->test)value=(uint64_t)state->value;else if(core_io_embedding){CoreIoClockResult result=core_io_native.clock_now(core_io_native.clock_context);status=(int)result.status;value=(uint64_t)result.value;}else{struct timespec now={0};status=clock_gettime(CLOCK_REALTIME,&now)||now.tv_sec>(INT64_MAX-now.tv_nsec)/1000000000?3:0;value=status?0:(uint64_t)now.tv_sec*1000000000+(uint64_t)now.tv_nsec;}}else if(!state->test&&core_io_embedding){CoreIoRandomResult result=core_io_native.random_u64(core_io_native.random_context);status=(int)result.status;value=result.value;}else{state->value=(int64_t)((uint64_t)state->value+UINT64_C(0x9e3779b97f4a7c15));value=(uint64_t)state->value;value=(value^(value>>30))*UINT64_C(0xbf58476d1ce4e5b9);value=(value^(value>>27))*UINT64_C(0x94d049bb133111eb);value^=value>>31;}if(status==4)out_of_memory();if(status<0||status>3)core_io_fail("InvalidProviderResult");return core_io_result(status,status?0:value,NULL,0);}
myl_block *myl_core_cap_restrict(myl_block *cap,uint32_t rights){CoreIoAuthority *a=core_io_authority(cap);return core_io_cap(a->family,a->rights&rights,a->provider,cap,a->scope);}
static myl_block *core_io_scope(myl_block *cap,myl_block *scope,unsigned family,int append){CoreIoAuthority *a=core_io_authority(cap);if(a->family!=family)core_io_fail("InvalidCapability");myl_block *joined=scope;if(append&&a->scope&&a->scope->len){size_t length=(size_t)(a->scope->len+scope->len+(scope->len!=0));unsigned char *bytes=malloc(length);if(!bytes)out_of_memory();memcpy(bytes,block_data(a->scope),(size_t)a->scope->len);if(scope->len){bytes[a->scope->len]='/';memcpy(bytes+a->scope->len+1,block_data(scope),(size_t)scope->len);}joined=core_io_string(bytes,length,1);free(bytes);}else core_io_retain(joined);myl_block *out=core_io_cap(family,a->rights,a->provider,cap,joined);myl_core_release(joined);return out;}
myl_block *myl_core_cap_dir(myl_block *cap,myl_block *path){if(path->len&&!core_io_memory_valid_path(block_data(path),(size_t)path->len,'m'))core_io_fail("InvalidCapability");return core_io_scope(cap,path,2,1);}
myl_block *myl_core_cap_host(myl_block *cap,myl_block *name){CoreIoAuthority *a=core_io_authority(cap);if(!name->len||name->len>4096||memchr(block_data(name),0,(size_t)name->len))core_io_fail("InvalidCapability");if(a->scope&&!myl_core_str_eq(a->scope,name))core_io_fail("InvalidCapability");return core_io_scope(cap,name,3,0);}
myl_block *myl_core_environment_only(myl_block *cap,myl_block *names){CoreIoAuthority *a=core_io_authority(cap);if(a->family!=4||a->scope)core_io_fail("R_CAPABILITY");if(!names->len||block_data(names)[names->len-1]!=0)core_io_fail("InvalidCapability");return core_io_scope(cap,names,4,0);}

static int core_io_resource_acquire(myl_block *cap,const unsigned char *request,size_t length,myl_block **output) {
    CoreIoAuthority *authority=core_io_authority(cap);CoreIoState *state=core_io_state(cap);
    if(authority->family!=2&&authority->family!=3)core_io_fail("InvalidCapability");
    if(authority->family==3&&state->test)return 6;
    unsigned char joined[8192];const unsigned char *input=request;size_t width=length;
    if(authority->scope){size_t scope=(size_t)authority->scope->len;if(authority->family==2){if(length<2||request[1]!=':'||!core_io_memory_valid_path(request+2,length-2,request[0]))return 2;if(scope+length+1>sizeof joined)return 2;joined[0]=request[0];joined[1]=':';memcpy(joined+2,block_data(authority->scope),scope);size_t at=scope+2;if(length>2){if(scope)joined[at++]='/';memcpy(joined+at,request+2,length-2);at+=length-2;}width=at;}else{if(scope>sizeof joined)return 2;memcpy(joined,block_data(authority->scope),scope);width=scope;}input=joined;}
    if(!state->adapter.acquire)return 1;
    if(core_io_family_open[authority->family-2]>=1024)return 4;
    /* Allocate bookkeeping before acquiring, so registration cannot fail. */
    myl_block *block=block_new(7,sizeof(CoreIoResource),1);block->len=1;block->reserved=(int64_t)(intptr_t)core_io_resource_layout;
    memset(block_data(block),0,sizeof(CoreIoResource));
    unsigned char *request_copy=core_io_copy(input,width);CoreIoResourceResult result=state->adapter.acquire(state->adapter.context,request_copy,width,authority->rights&state->adapter.permissions);core_io_copy_free(request_copy);
    if(result.status==CORE_IO_PROVIDER_OUT_OF_MEMORY){block->reserved=0;block_free(block);out_of_memory();}
    if(result.status>3){block->reserved=0;block_free(block);core_io_fail("InvalidProvider");}
    if(result.status){block->reserved=0;block_free(block);return (int)result.status;}
    CoreIoResource *resource=(CoreIoResource *)block_data(block);*resource=(CoreIoResource){cap,result.handle,authority->family,authority->rights&state->adapter.permissions,1,0,core_io_tail,NULL,block};core_io_retain(cap);
    if(core_io_tail)core_io_tail->next=resource;core_io_tail=resource;++core_io_open_count;++core_io_family_open[authority->family-2];*output=block;return 0;
}
static CoreIoResource *core_io_resource(myl_block *owner){if(!owner||kind_of(owner)!=7)core_io_fail("InvalidOwner");return (CoreIoResource *)block_data(owner);}
static int core_io_complete(myl_block *owner){CoreIoResource *resource=core_io_resource(owner);if(!resource->open)return 3;if(!(resource->rights&4))return 2;CoreIoState *state=core_io_state(resource->authority);int status=(int)state->adapter.complete(state->adapter.context,resource->handle);if(status==4)out_of_memory();if(status<0||status>3)core_io_fail("InvalidProvider");if(!status){resource->open=0;core_io_unlink(resource);}return status;}
void myl_core_file_scope_close(myl_block *owner){if(!owner)return;CoreIoResource *resource=core_io_resource(owner);if(!resource->open)return;if(core_io_complete(owner))core_io_fail("R_FILE");}
static int core_io_read(myl_block *owner,unsigned char *out,size_t cap,size_t *written,int *eof){
    CoreIoResource *resource=core_io_resource(owner);*written=0;*eof=0;if(!resource->open)core_io_fail("InvalidOwner");if(!(resource->rights&1))return 2;CoreIoState *state=core_io_state(resource->authority);if(!state->adapter.read)return 1;
    unsigned char *copy=core_io_copy(NULL,cap);CoreIoResourceRead result=state->adapter.read(state->adapter.context,resource->handle,copy,cap);
    if(result.status==4)out_of_memory();if(result.status>3)core_io_fail("InvalidProvider");
    if(!result.status){if(result.length>cap||(result.eof!=0&&result.eof!=1))core_io_fail("InvalidProvider");if(result.length)memcpy(out,copy,result.length);*written=result.length;*eof=result.eof;}
    core_io_copy_free(copy);if(cap>*written)memset(out+*written,0,cap-*written);return (int)result.status;
}
static int core_io_write(myl_block *owner,const unsigned char *data,size_t len,size_t *written){
    CoreIoResource *resource=core_io_resource(owner);*written=0;if(!resource->open)core_io_fail("InvalidOwner");if(!(resource->rights&2))return 2;CoreIoState *state=core_io_state(resource->authority);if(!state->adapter.write)return 1;
    unsigned char *copy=core_io_copy(data,len);CoreIoResourceWrite result=state->adapter.write(state->adapter.context,resource->handle,copy,len);
    if(result.status==4)out_of_memory();if(result.status>3)core_io_fail("InvalidProvider");if(!result.status){if(result.length>len)core_io_fail("InvalidProvider");*written=result.length;}core_io_copy_free(copy);return (int)result.status;
}

myl_block *myl_core_resource_acquire(myl_block *cap,myl_block *request){myl_block *resource=NULL;int status=core_io_resource_acquire(cap,block_data(request),(size_t)request->len,&resource);return core_io_result(status,(uint64_t)(uintptr_t)resource,NULL,1);}
int64_t myl_core_resource_complete(myl_block *owner){return core_io_complete(owner);}
static const char *core_io_reason(int status){if(status==1)return "no filesystem authority is available";if(status==2)return "denied: outside the granted directories, or the mode needs a write grant";if(status==4)return "too many files are open";if(status==5)return "the bytes read are not valid UTF-8 text";return "failed: the path does not exist or could not be used";}
static myl_block *core_io_file_error(unsigned kind,myl_block *path,int status){static const char *verbs[]={"open","read","read","write","write","stat","listdir","mkdir","remove"};const char *verb=verbs[kind],*reason=core_io_reason(status);size_t length=strlen(verb)+strlen(reason)+(size_t)path->len+5;char *message=malloc(length+1);if(!message)out_of_memory();size_t at=(size_t)sprintf(message,"%s '",verb);memcpy(message+at,block_data(path),(size_t)path->len);at+=(size_t)path->len;at+=(size_t)sprintf(message+at,"': %s",reason);myl_block *text=core_io_string(message,at,1);free(message);return text;}
typedef struct {unsigned char *bytes;size_t length,capacity;} CoreIoBytes;
static void core_io_append(CoreIoBytes *bytes,const unsigned char *data,size_t length){if(bytes->length+length>64u*1024u*1024u)core_io_fail("R_FILE");if(bytes->length+length>bytes->capacity){size_t cap=bytes->capacity?bytes->capacity:128;while(cap<bytes->length+length)cap*=2;unsigned char *grown=realloc(bytes->bytes,cap);if(!grown)out_of_memory();bytes->bytes=grown;bytes->capacity=cap;}if(length)memcpy(bytes->bytes+bytes->length,data,length);bytes->length+=length;}
static int core_io_read_all(myl_block *resource,size_t limit,int line,CoreIoBytes *out){unsigned char data[16384];while(out->length<limit){size_t take=line?1:sizeof data;if(take>limit-out->length)take=limit-out->length;size_t read;int eof;int status=core_io_read(resource,data,take,&read,&eof);if(status)return status;core_io_append(out,data,read);if(!read||eof||(line&&data[0]=='\n'))break;}return 0;}
static int core_io_write_all(myl_block *resource,myl_block *input,size_t *out){*out=0;while(*out<(size_t)input->len){size_t written;size_t remaining=(size_t)input->len-*out;int status=core_io_write(resource,block_data(input)+*out,remaining<65536?remaining:65536,&written);if(status)return status;if(!written)return 3;*out+=written;}return 0;}
static myl_block *core_io_sequence(CoreIoBytes *bytes,int text,int *status){if(text&&!core_io_utf8(bytes->bytes,bytes->length)){*status=5;return NULL;}return core_io_string(bytes->bytes,bytes->length,text);}
static myl_block *core_io_list_new(size_t capacity){myl_block *list=block_new(MYL_KIND_LIST,(int64_t)capacity,8);list->reserved=(int64_t)(intptr_t)core_io_list_layout;return list;}
static void core_io_list_add(myl_block **list,myl_block *item){*list=myl_core_list_grow(*list,8);myl_block **data=(myl_block **)block_data(*list);data[(*list)->len++]=item;}
static myl_block *core_io_listing(CoreIoBytes *raw,int *status){myl_block *list=core_io_list_new(0);if(!raw->length||raw->bytes[0]!=1){*status=3;return list;}size_t at=1;while(at<raw->length){if(at+3>raw->length){*status=3;break;}size_t width=(size_t)raw->bytes[at+1]|((size_t)raw->bytes[at+2]<<8);at+=3;if(at+width>raw->length||!core_io_utf8(raw->bytes+at,width)){*status=5;break;}core_io_list_add(&list,core_io_string(raw->bytes+at,width,1));at+=width;}return list;}
/* request packs Access, open mode and text bit, as qbe_files.c. */
myl_block *myl_core_file_access(myl_block *cap,uint32_t request,myl_block *path,myl_block *input){unsigned kind=request&255,mode=(request>>8)&255;int text=(request>>16)&1;static const unsigned char letters[]={0,'r','r','w','w','m','l','k','x'};if(kind>8)core_io_fail("R_FILE");unsigned char frame[4096];int status=0;myl_block *owner=NULL;uint64_t value=0;if(path->len>4094)status=2;else{frame[0]=kind?letters[kind]:(unsigned char)mode;frame[1]=':';if(path->len)memcpy(frame+2,block_data(path),(size_t)path->len);if(frame[0]=='w'){frame[0]='c';status=core_io_resource_acquire(cap,frame,(size_t)path->len+2,&owner);if(status>0){frame[0]='t';status=core_io_resource_acquire(cap,frame,(size_t)path->len+2,&owner);}}else status=core_io_resource_acquire(cap,frame,(size_t)path->len+2,&owner);}
    if(!status){CoreIoBytes raw={0};if(kind==0){core_io_resource(owner)->text=(unsigned)text;return (request&(1u<<17))?owner:core_io_result(0,(uint64_t)(uintptr_t)owner,NULL,1);}if(kind==1||kind==2||kind==5||kind==6){status=core_io_read_all(owner,64u*1024u*1024u,0,&raw);if(!status){if(kind==5)value=1;else if(kind==6)value=(uint64_t)(uintptr_t)core_io_listing(&raw,&status);else value=(uint64_t)(uintptr_t)core_io_sequence(&raw,kind==2,&status);}}else if(kind==3||kind==4){size_t written;status=core_io_write_all(owner,input,&written);}(void)core_io_complete(owner);free(raw.bytes);myl_core_release(owner);}
    if(kind==0&&(request&(1u<<17)))core_io_fail("R_FILE");
    if(kind==5)return core_io_result(0,status?0:value,NULL,0);
    int pointer=kind==0||kind==1||kind==2||kind==6;if(status&&pointer&&value){myl_core_release((myl_block *)(uintptr_t)value);value=0;}
    return core_io_result(status,value,status?core_io_file_error(kind,path,status):NULL,pointer);
}
myl_block *myl_core_file_method(myl_block *owner,uint32_t request,int64_t count,myl_block *input){unsigned kind=request&255;int text=(request>>16)&1;CoreIoResource *resource=core_io_resource(owner);if(!resource->open)core_io_fail("R_FILE");int status=0;uint64_t value=0;int pointer=kind<=2;CoreIoBytes raw={0};if(kind==0||kind==1){status=core_io_read_all(owner,count<0?64u*1024u*1024u:(size_t)count,kind==1,&raw);if(!status)value=(uint64_t)(uintptr_t)core_io_sequence(&raw,text,&status);}else if(kind==2){myl_block *list=core_io_list_new(0);for(;;){CoreIoBytes line={0};status=core_io_read_all(owner,64u*1024u*1024u,1,&line);if(status||!line.length){free(line.bytes);break;}myl_block *part=core_io_sequence(&line,text,&status);free(line.bytes);if(status)break;core_io_list_add(&list,part);}value=(uint64_t)(uintptr_t)list;}else if(kind==3){size_t written;status=core_io_write_all(owner,input,&written);value=(uint64_t)written;}else if(kind==5)status=core_io_complete(owner);else if(kind!=4)core_io_fail("R_FILE");free(raw.bytes);if(status){if(pointer&&value)myl_core_release((myl_block *)(uintptr_t)value);core_io_fail("R_FILE");}return core_io_result(0,value,NULL,pointer);}
static int core_io_allowed(const char *names,const unsigned char *name,size_t length){if(!*names)return 1;for(const char *p=names;*p;){const char *comma=strchr(p,',');size_t width=comma?(size_t)(comma-p):strlen(p);if(width==length&&!memcmp(p,name,length))return 1;if(!comma)break;p=comma+1;}return 0;}
static int core_io_environment_read(myl_block *cap,myl_block *name,unsigned char *output,size_t capacity,size_t *written,int *present){
    CoreIoAuthority *a=core_io_authority(cap);CoreIoState *state=core_io_state(cap);*written=0;*present=0;
    if(a->family!=4)core_io_fail("R_CAPABILITY");
    if(a->scope&&!core_io_memory_blob_has(block_data(a->scope),(size_t)a->scope->len,block_data(name),(size_t)name->len))core_io_fail("R_CAPABILITY");
    if(state->test){myl_block *pairs=state->pairs;if(!pairs)return 0;for(size_t at=0;at<(size_t)pairs->len;){size_t key=core_io_memory_field(block_data(pairs),(size_t)pairs->len,at),value=at+key+1,width=core_io_memory_field(block_data(pairs),(size_t)pairs->len,value);if(key==(size_t)name->len&&!memcmp(block_data(pairs)+at,block_data(name),key)){if(width>capacity)return 4;if(width)memcpy(output,block_data(pairs)+value,width);*written=width;*present=1;break;}at=value+width+1;}return 0;}
    if(core_io_embedding){unsigned char *key_copy=core_io_copy(block_data(name),(size_t)name->len),*copy=core_io_copy(NULL,capacity);CoreIoEnvironmentResult result=core_io_native.environment_get(core_io_native.environment_context,key_copy,(size_t)name->len,copy,capacity);core_io_copy_free(key_copy);if(result.status==4)out_of_memory();if(result.status){if(result.status>5)core_io_fail("InvalidProvider");core_io_copy_free(copy);return result.status==5?4:(int)result.status;}if((result.present!=0&&result.present!=1)||(result.present&&result.length>capacity))core_io_fail("InvalidProvider");*written=result.present?result.length:0;*present=result.present;if(*written)memcpy(output,copy,*written);core_io_copy_free(copy);return 0;}
    if(!core_io_allowed(core_io_names,block_data(name),(size_t)name->len))return 2;
    if((size_t)name->len>255)return 2;
    char key[256];memcpy(key,block_data(name),(size_t)name->len);key[name->len]=0;const char *value=getenv(key);if(!value)return 0;
    size_t length=strlen(value);if(length>capacity)return 4;if(length)memcpy(output,value,length);*written=length;*present=1;return 0;
}
myl_block *myl_core_environment_text(myl_block *cap,myl_block *name){unsigned char output[16384];size_t length;int present;int status=core_io_environment_read(cap,name,output,sizeof output,&length,&present);if(status)core_io_fail("R_CAPABILITY");if(!present)return NULL;if(!core_io_utf8(output,length))core_io_fail("R_ENVIRONMENT");return core_io_string(output,length,1);}

typedef struct { const unsigned char *bytes;size_t length; } CoreIoName;
static int core_io_name_order(const void *left,const void *right){const CoreIoName *a=left,*b=right;size_t width=a->length<b->length?a->length:b->length;int order=memcmp(a->bytes,b->bytes,width);return order?order:a->length<b->length?-1:a->length>b->length;}
/* Collect at most 64 raw names before filtering UTF-8, matching the old boundary. */
static void core_io_name_add(CoreIoName *names,unsigned *count,const unsigned char *name,size_t width){
    if(!width||width>128||*count==64)return;
    for(unsigned i=0;i<*count;++i)if(names[i].length==width&&!memcmp(names[i].bytes,name,width))return;
    names[(*count)++]=(CoreIoName){name,width};
}
myl_block *myl_core_environment_names(myl_block *cap){
    CoreIoAuthority *a=core_io_authority(cap);CoreIoState *state=core_io_state(cap);
    if(a->family!=4)core_io_fail("InvalidCapability");
    myl_block *list=core_io_list_new(0),*blob=a->scope?a->scope:state->pairs;
    CoreIoName names[64];unsigned count=0;
    if(blob){
        for(size_t at=0;at<(size_t)blob->len;){
            size_t width=core_io_memory_field(block_data(blob),(size_t)blob->len,at);
            if(state->test||core_io_allowed(core_io_enumerated_names,block_data(blob)+at,width))core_io_name_add(names,&count,block_data(blob)+at,width);
            at+=width+1;if(!a->scope)at+=core_io_memory_field(block_data(blob),(size_t)blob->len,at)+1;
        }
    }else if(!state->test){
        if(*core_io_enumerated_names){
            const char *name=core_io_enumerated_names;
            while(*name){const char *comma=strchr(name,',');size_t width=comma?(size_t)(comma-name):strlen(name);core_io_name_add(names,&count,(const unsigned char *)name,width);if(!comma)break;name=comma+1;}
        }else{
            extern char **environ;
            for(char **entry=environ;entry&&*entry;++entry){char *equal=strchr(*entry,'=');size_t width=equal?(size_t)(equal-*entry):strlen(*entry);core_io_name_add(names,&count,(const unsigned char *)*entry,width);}
        }
    }
    qsort(names,count,sizeof(CoreIoName),core_io_name_order);
    for(unsigned i=0;i<count;++i)if(core_io_utf8(names[i].bytes,names[i].length))core_io_list_add(&list,core_io_string(names[i].bytes,names[i].length,1));
    return list;
}
void myl_core_stream_write(int64_t fd,myl_block *text){myl_core_print_str(fd,text);}
int64_t myl_core_s3_token_roundtrip(int64_t token){return token;}

myl_block *myl_core_io_bytes_from_u8_list(myl_block *list){return core_io_string(block_data(list),(size_t)list->len,0);}

/* Fixed provider payloads carry a padded byte block plus count/flag. The
   builder copies octets into its checked fixed array and owns this box normally. */
static const int32_t core_io_raw_layout[]={32,1,0,8,0};
static myl_block *core_io_raw_result(int status,myl_block *bytes,uint64_t length,int flag){
    myl_block *box=block_new(MYL_KIND_BOX,32,1);box->len=1;box->reserved=(int64_t)(intptr_t)core_io_raw_layout;
    uint64_t *data=(uint64_t *)block_data(box);data[0]=(uint64_t)status;data[1]=(uint64_t)(uintptr_t)bytes;data[2]=length;data[3]=(uint64_t)flag;return box;
}
static myl_block *core_io_padded(size_t capacity){
    if(capacity>64u*1024u*1024u)out_of_memory();
    myl_block *bytes=block_new(MYL_KIND_BYTES,(int64_t)capacity+1,1);bytes->len=(int64_t)capacity;memset(block_data(bytes),0,capacity+1);return bytes;
}
myl_block *myl_core_resource_read(myl_block *owner,uint64_t capacity){
    myl_block *bytes=core_io_padded((size_t)capacity);size_t written;int eof;
    int status=core_io_read(owner,block_data(bytes),(size_t)capacity,&written,&eof);
    return core_io_raw_result(status,bytes,status?0:written,status?0:eof);
}
myl_block *myl_core_resource_write(myl_block *owner,myl_block *input){
    size_t written;int status=core_io_write(owner,block_data(input),(size_t)input->len,&written);
    return core_io_result(status,status?0:written,NULL,0);
}
myl_block *myl_core_environment_raw(myl_block *cap,myl_block *name,uint64_t capacity){
    myl_block *bytes=core_io_padded((size_t)capacity);size_t length;int present;int status=core_io_environment_read(cap,name,block_data(bytes),(size_t)capacity,&length,&present);
    if(status)memset(block_data(bytes),0,(size_t)capacity);else if(capacity>length)memset(block_data(bytes)+length,0,(size_t)capacity-length);
    return core_io_raw_result(status,bytes,status?0:length,status?0:present);
}

#include <stddef.h>
/* Copied-node and packed-copy Host algorithms ported from qbe_host_runtime.c.
 * Core boxes own guest results. Scratch and compiler metadata caches are retired
 * on normal exit or trap; no old context, heap, runtime or byte-string ABI remains. */
typedef struct CoreHostScratch {struct CoreHostScratch *next;max_align_t alignment;unsigned char data[];} CoreHostScratch;
static CoreHostScratch *core_host_scratch_head;
static void *core_host_scratch(size_t bytes){CoreHostScratch *item=malloc(sizeof(*item)+bytes);if(!item)out_of_memory();item->next=core_host_scratch_head;core_host_scratch_head=item;return item->data;}
static void core_host_scratch_free(void *bytes){CoreHostScratch **at=&core_host_scratch_head;while(*at&&(*at)->data!=bytes)at=&(*at)->next;if(!*at)core_io_fail("R_HOST_CONTRACT");CoreHostScratch *item=*at;*at=item->next;free(item);}
static void core_host_fail(const char *code){if(!strcmp(code,"OutOfMemory"))out_of_memory();core_io_fail(code);}
typedef struct {
    const char *name;
    size_t size,count,stride;
    unsigned kind,bits,is_signed;
    const size_t *children,*offsets;
} CoreHostType;
typedef struct {
    const char *name;
    const size_t *parameters;
    size_t count,result;
    unsigned effects;
} CoreHostDeclaration;
typedef struct {
    const CoreIoHostRegistry *registry;
    uint64_t calls,work,call_limit;
    size_t value_limit,depth_limit,payload_limit;
    int initialized,invoking;
    const CoreIoHostBinding **bound;
} CoreHostState;
static const CoreHostType *core_host_types;
static const CoreHostDeclaration *core_host_declarations;
static const CoreIoHostBinding *core_host_binding(void *ctx,CoreHostState *state,const CoreHostDeclaration *declaration) {
    const CoreIoHostBinding *found=NULL;
    for (size_t i=0;i<state->registry->count;i++) {
        const CoreIoHostBinding *binding=&state->registry->bindings[i];
        if (!binding->name || strcmp(binding->name,declaration->name)) continue;
        if (found) { core_host_fail("HostDuplicateRegistration"); return NULL; }
        found=binding;
    }
    if (!found || !found->invoke) { core_host_fail("HostMissingRegistration"); return NULL; }
    if (!found->result || strcmp(found->result,core_host_types[declaration->result].name) || found->parameter_count!=declaration->count || found->effects!=declaration->effects || (found->parameter_count && !found->parameters)) {
        core_host_fail("HostSignatureMismatch"); return NULL;
    }
    for (size_t i=0;i<declaration->count;i++) if (!found->parameters[i] || strcmp(found->parameters[i],core_host_types[declaration->parameters[i]].name)) {
        core_host_fail("HostSignatureMismatch"); return NULL;
    }
    if (declaration->effects & ~found->grants) { core_host_fail("HostCapabilityDenied"); return NULL; }
    return found;
}
static int core_host_error(void *ctx,const char *code) {
    if (!strcmp(code,"OutOfMemory")) core_host_fail(code);
    else if (!strcmp(code,"HostCallLimit") || !strcmp(code,"HostWorkLimit") || !strcmp(code,"ValueCountLimit") || !strcmp(code,"ValueDepthLimit")) core_host_fail("R_HOST_LIMIT");
    else if (!strcmp(code,"HostFailure")) core_host_fail("R_HOST_FAILURE");
    else core_host_fail("R_HOST_CONTRACT");
    return 0;
}
static uint64_t core_host_word(const void *input,const CoreHostType *type) {
    uint64_t bits=0;
    memcpy(&bits,input,type->size);
    if (type->is_signed && type->bits<64 && (bits&(UINT64_C(1)<<(type->bits-1)))) bits|=UINT64_MAX<<type->bits;
    return bits;
}
static int core_host_valid(const CoreHostType *type,uint64_t bits) {
    if (type->bits==64) return 1;
    uint64_t maximum=(UINT64_C(1)<<(type->bits-type->is_signed))-1;
    return bits<=maximum || (type->is_signed && bits>=~maximum);
}
static int core_host_write(void *ctx,CoreHostState *state,size_t index,const void *input,CoreIoHostNode *nodes,size_t *cursor,size_t depth) {
    if (depth>state->depth_limit) return core_host_error(ctx,"ValueDepthLimit");
    if (*cursor==state->value_limit) return core_host_error(ctx,"ValueCountLimit");
    const CoreHostType *type=&core_host_types[index];
    CoreIoHostNode node={type->name,0,type->count};
    size_t child=SIZE_MAX;
    if (type->kind==1) { node.bits=core_host_word(input,type); node.children=0; }
    else if (type->kind==4) {
        uint32_t tag; memcpy(&tag,input,4); node.bits=tag;
        if (tag>=type->count) return core_host_error(ctx,"InvalidDataValue");
        child=type->children[tag]; node.children=child!=SIZE_MAX;
    } else if (type->kind!=2 && type->kind!=3 && type->kind!=5) return core_host_error(ctx,"NotDataType");
    if (nodes) nodes[*cursor]=node;
    (*cursor)++;
    size_t backing=*cursor;
    for (size_t i=0;i<node.children;i++) {
        size_t field=type->kind==3?0:type->kind==4?(size_t)node.bits:i;
        size_t next=type->kind==4?child:type->children[field];
        size_t offset=type->kind==3?i*type->stride:type->offsets[field];
        if (!core_host_write(ctx,state,next,(const unsigned char *)input+offset,nodes,cursor,depth+1)) return 0;
    }
    /* FLOAT-NAN-OBSERVED-6: a binary64 domain (the one domain with a width) is
       a host-visible bit pattern, so any NaN crosses as the canonical quiet NaN
       whatever payload and sign guest arithmetic gave it. */
    if (nodes && type->kind==5 && type->bits==64 && backing<*cursor) {
        uint64_t bits=nodes[backing].bits;
        if ((bits&UINT64_C(0x7ff0000000000000))==UINT64_C(0x7ff0000000000000) && (bits&UINT64_C(0x000fffffffffffff)))
            nodes[backing].bits=UINT64_C(0x7ff8000000000000);
    }
    return 1;
}
static int core_host_read(void *ctx,CoreHostState *state,size_t index,void *output,const CoreIoHostNode *nodes,size_t count,size_t *cursor,size_t depth) {
    if (depth>state->depth_limit) return core_host_error(ctx,"ValueDepthLimit");
    if (*cursor==count) return core_host_error(ctx,"InvalidDataValue");
    const CoreHostType *type=&core_host_types[index];
    const CoreIoHostNode *node=&nodes[(*cursor)++];
    if (!node->type || strcmp(node->type,type->name)) return core_host_error(ctx,"ValueTypeMismatch");
    if (type->kind==1) {
        if (node->children || !core_host_valid(type,node->bits)) return core_host_error(ctx,"InvalidDataValue");
        memcpy(output,&node->bits,type->size); return 1;
    }
    size_t children=type->count,child=SIZE_MAX;
    if (type->kind==4) {
        if (node->bits>=type->count) return core_host_error(ctx,"InvalidDataValue");
        child=type->children[node->bits]; children=child!=SIZE_MAX;
        uint32_t tag=(uint32_t)node->bits; memcpy(output,&tag,4);
    } else if ((type->kind!=2 && type->kind!=3 && type->kind!=5) || node->bits) return core_host_error(ctx,"InvalidDataValue");
    if (node->children!=children) return core_host_error(ctx,"InvalidDataValue");
    for (size_t i=0;i<children;i++) {
        size_t field=type->kind==3?0:type->kind==4?(size_t)node->bits:i;
        size_t next=type->kind==4?child:type->children[field];
        size_t offset=type->kind==3?i*type->stride:type->offsets[field];
        if (!core_host_read(ctx,state,next,(unsigned char *)output+offset,nodes,count,cursor,depth+1)) return 0;
    }
    return 1;
}
static size_t core_host_nodes(size_t index,size_t depth,size_t limit,size_t depth_limit) {
    if (!limit || depth>depth_limit) return limit;
    const CoreHostType *type=&core_host_types[index];
    if (type->kind==1) return 1;
    size_t total=1;
    if (type->kind==4) {
        size_t largest=0;
        for (size_t i=0;i<type->count;i++) if (type->children[i]!=SIZE_MAX) {
            size_t child=core_host_nodes(type->children[i],depth+1,limit-1,depth_limit);
            if (child>largest) largest=child;
        }
        return 1+largest;
    }
    if (type->kind==3) {
        size_t child=core_host_nodes(type->children[0],depth+1,limit-1,depth_limit);
        if (child && type->count>(limit-1)/child) return limit;
        return 1+type->count*child;
    }
    for (size_t i=0;i<type->count;i++) {
        total+=core_host_nodes(type->children[i],depth+1,limit-total,depth_limit);
        if (total==limit) return limit;
    }
    return total;
}
static int core_host_scalar_call(const CoreHostState *state,const CoreHostDeclaration *declaration) {
    if (state->depth_limit<1 || declaration->count>=state->value_limit || declaration->count>=8 || core_host_types[declaration->result].kind!=1) return 0;
    for (size_t i=0;i<declaration->count;i++) if (core_host_types[declaration->parameters[i]].kind!=1) return 0;
    return 1;
}
/* Kind 6 is the immutable `bytes` byte string: one owned payload the runtime
   copies in both directions. Its guest value is a single managed pointer word,
   so the schema carries no octet count and the payload ceiling bounds it. */
static int core_host_payload_type(size_t index) {
    return core_host_types[index].kind==6;
}
static int core_host_packed_type(size_t index,size_t *nodes,size_t depth,size_t depth_limit) {
    const CoreHostType *type=&core_host_types[index];
    if (depth>depth_limit) return 0;
    if (type->kind==6) {
        if (type->size!=sizeof(myl_block *)) return 0;
        *nodes=1; return 1;
    }
    if (type->kind==1) {
        if ((type->bits!=8 && type->bits!=16 && type->bits!=32 && type->bits!=64) || type->size!=type->bits/8) return 0;
        *nodes=1; return 1;
    }
    if (type->kind!=3 || type->stride!=1 || type->size!=type->count ||
        !type->children || !type->offsets || type->offsets[0]!=0) return 0;
    const CoreHostType *element=&core_host_types[type->children[0]];
    if (element->kind!=1 || element->size!=1 || element->bits!=8 || element->is_signed) return 0;
    if (depth+1>depth_limit || type->count==SIZE_MAX) return 0;
    *nodes=1+type->count;
    return 1;
}
static int core_host_packed_call(CoreHostState *state,const CoreHostDeclaration *declaration,const CoreIoHostBinding *binding,size_t *bytes) {
    if (!binding->invoke_packed) return 0;
    size_t nodes=0,total=0;
    for (size_t i=0;i<declaration->count;i++) {
        if (!core_host_packed_type(declaration->parameters[i],&nodes,1,state->depth_limit) ||
            nodes>state->value_limit-total) return 0;
        total+=nodes;
        size_t size=core_host_payload_type(declaration->parameters[i])?0:core_host_types[declaration->parameters[i]].size;
        if (size>SIZE_MAX-*bytes) return 0;
        *bytes+=size;
    }
    if (!core_host_packed_type(declaration->result,&nodes,1,state->depth_limit) ||
        nodes>state->value_limit-total) return 0;
    size_t size=core_host_payload_type(declaration->result)?0:core_host_types[declaration->result].size;
    if (size>SIZE_MAX-*bytes) return 0;
    *bytes+=size;
    /* Only the fixed part of the scratch is bounded here; a `bytes` payload is
       measured at call time against the registry's payload ceiling. */
    if (*bytes>1024u*1024u) return 0;
    return 1;
}
/* One argument's copied payload: a fixed shape's own storage, or the octets an
   immutable byte string currently holds. */
typedef struct { const unsigned char *octets; size_t size; } CoreHostPayload;
static int core_host_payload_of(void *ctx,CoreHostState *state,size_t index,const void *argument,CoreHostPayload *payload) {
    if (!core_host_payload_type(index)) {
        payload->octets=argument; payload->size=core_host_types[index].size; return 1;
    }
    myl_block *value=NULL;
    memcpy(&value,argument,sizeof value);
    if (!value) return core_host_error(ctx,"InvalidDataValue");
    size_t length=(size_t)value->len;
    payload->octets=block_data(value);
    if (length>state->payload_limit) return core_host_error(ctx,"ValueCountLimit");
    payload->size=length;
    return 1;
}
/* Copy a callback's published octets into a fresh guest byte string. Those
   octets belong to the callback, so the runtime only reads them, and a sticky
   trap or a refused allocation publishes no value. */
static void core_host_publish_payload(void *ctx,CoreHostState *state,const CoreIoHostPackedCall *call,void *output) {
    if (call->output.size!=call->output_written || (!call->output.bytes && call->output.size)) { core_host_error(ctx,"InvalidDataValue"); return; }
    if (call->output.size>state->payload_limit) { core_host_error(ctx,"ValueCountLimit"); return; }
    
    myl_block *value=core_io_string(call->output.bytes,call->output.size,0);
    if (!value) out_of_memory();
    memcpy(output,&value,sizeof value);
}
static void core_host_invoke_packed(void *ctx,CoreHostState *state,const CoreHostDeclaration *declaration,const CoreIoHostBinding *binding,const void *const *arguments,void *output) {
    if (declaration->count==SIZE_MAX) { core_host_error(ctx,"OutOfMemory"); return; }
    size_t value_count=declaration->count+1;
    if (value_count>SIZE_MAX/sizeof(CoreIoHostPackedValue)) { core_host_error(ctx,"OutOfMemory"); return; }
    size_t headers=value_count*sizeof(CoreIoHostPackedValue);
    /* Measure every argument before copying one, so an oversized byte string is
       refused before the callback can observe any of them. */
    size_t bytes=0;
    for (size_t i=0;i<declaration->count;i++) {
        CoreHostPayload payload;
        if (!core_host_payload_of(ctx,state,declaration->parameters[i],arguments[i],&payload)) return;
        if (payload.size>SIZE_MAX-bytes) { core_host_error(ctx,"OutOfMemory"); return; }
        bytes+=payload.size;
    }
    size_t output_size=core_host_payload_type(declaration->result)?0:core_host_types[declaration->result].size;
    if (output_size>SIZE_MAX-bytes) { core_host_error(ctx,"OutOfMemory"); return; }
    bytes+=output_size;
    if (bytes>SIZE_MAX-headers) { core_host_error(ctx,"OutOfMemory"); return; }
    union { max_align_t alignment; unsigned char bytes[1024]; } local;
    int owned=headers+bytes>sizeof local.bytes;
    unsigned char *scratch=owned?core_host_scratch(headers+bytes):local.bytes;
    if (!scratch) return;
    memset(scratch,0,headers);
    CoreIoHostPackedValue *values=(CoreIoHostPackedValue *)scratch;
    unsigned char *cursor=scratch+headers;
    for (size_t i=0;i<declaration->count;i++) {
        CoreHostPayload payload={NULL,0};
        (void)core_host_payload_of(ctx,state,declaration->parameters[i],arguments[i],&payload);
        values[i]=(CoreIoHostPackedValue){cursor,payload.size};
        if (payload.size) memcpy(cursor,payload.octets,payload.size);
        cursor+=payload.size;
    }
    /* A `bytes` result starts as an empty output the callback replaces with its
       own octets; every other shape keeps the zeroed scratch it is given. */
    void *expected_output=output_size?cursor:NULL;
    if (output_size) memset(cursor,0,output_size);
    values[declaration->count]=(CoreIoHostPackedValue){expected_output,output_size};
    state->calls++; state->work--;
    CoreIoHostPackedCall call={values,declaration->count,values[declaration->count],0,state->work,0};
    state->invoking=1;
    const char *failure=binding->invoke_packed(binding->context,&call);
    state->invoking=0;
    if (call.exhausted || call.work_remaining>state->work) core_host_error(ctx,"HostWorkLimit");
    else {
        state->work=call.work_remaining;
        if (failure) core_host_error(ctx,failure);
        else if (core_host_payload_type(declaration->result)) core_host_publish_payload(ctx,state,&call,output);
        else if (call.output.bytes!=expected_output || call.output.size!=output_size || call.output_written!=output_size) core_host_error(ctx,"InvalidDataValue");
        else if (output_size) memcpy(output,call.output.bytes,output_size);
    }
    if (owned) core_host_scratch_free(scratch);
}
static void core_host_invoke_scalar(void *ctx,CoreHostState *state,const CoreHostDeclaration *declaration,const CoreIoHostBinding *binding,const void *const *arguments,void *output) {
    CoreIoHostNode nodes[8]={0};
    for (size_t i=0;i<declaration->count;i++) {
        const CoreHostType *type=&core_host_types[declaration->parameters[i]];
        nodes[i]=(CoreIoHostNode){type->name,core_host_word(arguments[i],type),0};
    }
    state->calls++; state->work--;
    CoreIoHostCall call={nodes,declaration->count,nodes+declaration->count,1,0,state->work,0};
    state->invoking=1;
    const char *failure=binding->invoke(binding->context,&call);
    state->invoking=0;
    if (call.exhausted || call.work_remaining>state->work) core_host_error(ctx,"HostWorkLimit");
    else {
        state->work=call.work_remaining;
        if (failure) core_host_error(ctx,failure);
        else if (call.output_nodes>1) core_host_error(ctx,"ValueCountLimit");
        else if (call.output_nodes!=1) core_host_error(ctx,"InvalidDataValue");
        else {
            const CoreHostType *type=&core_host_types[declaration->result];
            const CoreIoHostNode *node=&nodes[declaration->count];
            if (!node->type || strcmp(node->type,type->name)) core_host_error(ctx,"ValueTypeMismatch");
            else if (node->children || !core_host_valid(type,node->bits)) core_host_error(ctx,"InvalidDataValue");
            else memcpy(output,&node->bits,type->size);
        }
    }
}
static void core_host_invoke_adapter(CoreHostState *state,const void *const *arguments,void *output) {
    void *ctx=NULL;
    size_t declaration_index=0;
    const CoreHostDeclaration *declaration=&core_host_declarations[declaration_index];
    const CoreIoHostBinding *binding=state->bound[declaration_index];
    if (state->invoking) { core_host_error(ctx,"HostReentry"); return; }
    if (state->calls==state->call_limit) { core_host_error(ctx,"HostCallLimit"); return; }
    if (!state->work) { core_host_error(ctx,"HostWorkLimit"); return; }
    size_t packed_bytes=0;
    if (core_host_packed_call(state,declaration,binding,&packed_bytes)) {
        core_host_invoke_packed(ctx,state,declaration,binding,arguments,output);
        return;
    }
    if (core_host_scalar_call(state,declaration)) {
        core_host_invoke_scalar(ctx,state,declaration,binding,arguments,output);
        return;
    }
    size_t count=0;
    for (size_t i=0;i<declaration->count;i++) if (!core_host_write(ctx,state,declaration->parameters[i],arguments[i],NULL,&count,1)) return;
    size_t capacity=core_host_nodes(declaration->result,1,state->value_limit-count,state->depth_limit);
    if (capacity>SIZE_MAX-count) { core_host_error(ctx,"OutOfMemory"); return; }
    size_t needed=count+capacity?count+capacity:1;
    if (needed>SIZE_MAX/sizeof(CoreIoHostNode)) { core_host_error(ctx,"OutOfMemory"); return; }
    CoreIoHostNode local_nodes[8]={0};
    /* The context retires frame scratch even when a contract failure jumps
       out of this C adapter before its ordinary epilogue. */
    CoreIoHostNode *nodes=needed<=8?local_nodes:core_host_scratch(needed*sizeof(*nodes));
    if (!nodes) { core_host_error(ctx,"OutOfMemory"); return; }
    size_t cursor=0;
    for (size_t i=0;i<declaration->count;i++) if (!core_host_write(ctx,state,declaration->parameters[i],arguments[i],nodes,&cursor,1)) {
        if (nodes!=local_nodes) core_host_scratch_free(nodes);
        return;
    }
    state->calls++; state->work--;
    CoreIoHostCall call={nodes,count,nodes+count,capacity,0,state->work,0};
    state->invoking=1;
    const char *failure=binding->invoke(binding->context,&call);
    state->invoking=0;
    if (call.exhausted || call.work_remaining>state->work) core_host_error(ctx,"HostWorkLimit");
    else {
        state->work=call.work_remaining;
        if (failure) core_host_error(ctx,failure);
        else if (call.output_nodes>capacity) core_host_error(ctx,"ValueCountLimit");
        else {
            cursor=0;
            if (core_host_read(ctx,state,declaration->result,output,nodes+count,call.output_nodes,&cursor,1) && cursor!=call.output_nodes) core_host_error(ctx,"InvalidDataValue");
        }
    }
    if (nodes!=local_nodes) core_host_scratch_free(nodes);
}
/* Compiler schemas use the exact nominal identities and Core byte offsets.
   Text and arrays below are private copies, cached by immortal metadata block. */
typedef struct CoreHostCache {
    struct CoreHostCache *next;myl_block *key;char *text;char **known;size_t known_count;
    CoreHostType *types;size_t type_count;CoreHostDeclaration declaration;CoreHostState state;
    const CoreIoHostBinding *bound;int32_t layout[5];
} CoreHostCache;
static CoreHostCache *core_host_cache;
static char *core_host_line(char **cursor){char *line=*cursor,*end=strchr(line,'\n');if(!end)core_io_fail("R_HOST_CONTRACT");*end=0;*cursor=end+1;return line;}
static size_t core_host_number(char **cursor){char *end;unsigned long long value=strtoull(*cursor,&end,10);if(end==*cursor)core_io_fail("R_HOST_CONTRACT");*cursor=end;while(**cursor==' '||**cursor=='\n')++*cursor;return(size_t)value;}
static CoreHostCache *core_host_schema(myl_block *metadata){
    for(CoreHostCache *item=core_host_cache;item;item=item->next)if(item->key==metadata)return item;
    CoreHostCache *item=calloc(1,sizeof(*item));if(!item)out_of_memory();item->next=core_host_cache;core_host_cache=item;item->key=metadata;
    item->text=malloc((size_t)metadata->len+1);if(!item->text)out_of_memory();memcpy(item->text,block_data(metadata),(size_t)metadata->len);item->text[metadata->len]=0;
    char *cursor=item->text;item->declaration.name=core_host_line(&cursor);
    item->declaration.count=core_host_number(&cursor);item->declaration.result=core_host_number(&cursor);item->declaration.effects=(unsigned)core_host_number(&cursor);
    (void)core_host_number(&cursor);size_t type_count=core_host_number(&cursor);item->type_count=type_count;item->known_count=core_host_number(&cursor);
    if(type_count>100000||item->declaration.count>100000)core_io_fail("R_HOST_CONTRACT");
    size_t *parameters=calloc(item->declaration.count?item->declaration.count:1,sizeof(size_t)*2);if(!parameters)out_of_memory();item->declaration.parameters=parameters;
    for(size_t i=0;i<item->declaration.count;++i){parameters[i]=core_host_number(&cursor);parameters[item->declaration.count+i]=core_host_number(&cursor);}
    item->known=calloc(item->known_count?item->known_count:1,sizeof(char *));if(!item->known)out_of_memory();for(size_t i=0;i<item->known_count;++i)item->known[i]=core_host_line(&cursor);
    item->types=calloc(type_count?type_count:1,sizeof(*item->types));if(!item->types)out_of_memory();
    for(size_t i=0;i<type_count;++i){CoreHostType *type=&item->types[i];type->name=core_host_line(&cursor);type->kind=(unsigned)core_host_number(&cursor);type->size=core_host_number(&cursor);type->count=core_host_number(&cursor);type->stride=core_host_number(&cursor);type->bits=(unsigned)core_host_number(&cursor);type->is_signed=(unsigned)core_host_number(&cursor);size_t count=type->kind==3?1:type->count;if(count){size_t *parts=calloc(count*2,sizeof(size_t));if(!parts)out_of_memory();type->children=parts;type->offsets=parts+count;for(size_t child=0;child<count;++child){parts[child]=core_host_number(&cursor);parts[count+child]=core_host_number(&cursor);}}}
    core_host_types=item->types;core_host_declarations=&item->declaration;
    CoreHostState *state=&item->state;state->registry=&core_io_native.host;const CoreIoHostRegistry *registry=state->registry;
    if(registry->count&&!registry->bindings)core_io_fail("R_HOST_CONTRACT");
    state->call_limit=registry->max_calls?registry->max_calls:10000;state->work=registry->max_work?registry->max_work:1000000;
    state->value_limit=registry->max_values?registry->max_values:65536;state->depth_limit=registry->max_depth?registry->max_depth:64;state->payload_limit=registry->max_payload?registry->max_payload:1024u*1024u;
    if(state->value_limit>100000||state->depth_limit>128||state->payload_limit>64u*1024u*1024u)core_io_fail("R_HOST_CONTRACT");
    for(size_t i=0;i<registry->count;++i){int known=0;for(size_t j=0;j<item->known_count;++j)if(registry->bindings[i].name&&!strcmp(registry->bindings[i].name,item->known[j]))known=1;if(!known)core_host_fail("HostUnknownFunction");}
    item->bound=core_host_binding(NULL,state,&item->declaration);state->bound=&item->bound;state->initialized=1;
    const CoreHostType *result=&item->types[item->declaration.result];item->layout[0]=(int32_t)result->size;item->layout[1]=result->kind==6?1:0;item->layout[2]=0;item->layout[3]=0;item->layout[4]=0;
    return item;
}
static uint64_t core_host_calls,core_host_work;static int core_host_budget_initialized,core_host_invoking;
myl_block *myl_core_host_invoke(myl_block *metadata,myl_block *arguments){
    core_io_initialize();if(core_host_invoking)core_io_fail("R_HOST_CONTRACT");CoreHostCache *schema=core_host_schema(metadata);
    if(!core_host_budget_initialized){core_host_budget_initialized=1;core_host_work=schema->state.work;}schema->state.calls=core_host_calls;schema->state.work=core_host_work;core_host_types=schema->types;core_host_declarations=&schema->declaration;
    const CoreHostType *result=&schema->types[schema->declaration.result];
    myl_block *box=block_new(MYL_KIND_BOX,(int64_t)result->size,1);box->len=1;box->reserved=(int64_t)(intptr_t)schema->layout;memset(block_data(box),0,result->size);
    size_t count=schema->declaration.count;const void **values=core_host_scratch((count?count:1)*sizeof(void *));
    for(size_t i=0;i<count;++i)values[i]=block_data(arguments)+schema->declaration.parameters[count+i];
    core_host_invoking=1;core_host_invoke_adapter(&schema->state,values,block_data(box));core_host_invoking=0;core_host_calls=schema->state.calls;core_host_work=schema->state.work;core_host_scratch_free(values);return box;
}
static void core_host_cleanup(void){
    while(core_host_scratch_head){CoreHostScratch *item=core_host_scratch_head;core_host_scratch_head=item->next;free(item);}
    while(core_host_cache){CoreHostCache *item=core_host_cache;core_host_cache=item->next;for(size_t i=0;i<item->type_count;++i)free((void *)item->types[i].children);free((void *)item->declaration.parameters);free(item->known);free(item->types);free(item->text);free(item);}
    core_host_types=NULL;core_host_declarations=NULL;
}

/* S3 port of native_bytes.c: octet algorithms adapted to the Core leaf header.
   kind 5 is mutable bytes, reserved=0; immutable snapshots own independent data. */
#define MYL_KIND_BUFFER 5u

myl_block *myl_core_buffer_new(uint64_t capacity) {
    if (capacity > INT64_MAX) out_of_memory();
    return block_new(MYL_KIND_BUFFER, (int64_t)capacity, 1);
}
myl_block *myl_core_buffer_copy(myl_block *source) {
    myl_block *out = myl_core_buffer_new((uint64_t)source->cap);
    out->len = source->len;
    memcpy(block_data(out), block_data(source), (size_t)source->len);
    return out;
}
static myl_block *core_buffer_grow(myl_block *buffer, int64_t needed) {
    if (needed <= buffer->cap) return buffer;
    int64_t capacity = buffer->cap < 8 ? 8 : buffer->cap;
    while (capacity < needed) {
        if (capacity > INT64_MAX / 2) { capacity = needed; break; }
        capacity *= 2;
    }
    myl_block *out = myl_core_buffer_new((uint64_t)capacity);
    out->len = buffer->len;
    memcpy(block_data(out), block_data(buffer), (size_t)buffer->len);
    block_free(buffer);
    return out;
}
myl_block *myl_core_buffer_push(myl_block *buffer, uint8_t value) {
    if (buffer->len == INT64_MAX) out_of_memory();
    buffer = core_buffer_grow(buffer, buffer->len + 1);
    block_data(buffer)[buffer->len++] = value;
    return buffer;
}
myl_block *myl_core_buffer_set(myl_block *buffer, uint64_t index, uint8_t value) {
    block_data(buffer)[index] = value;
    return buffer;
}
myl_block *myl_core_buffer_pop(myl_block *buffer) { --buffer->len; return buffer; }
uint64_t myl_core_buffer_capacity(myl_block *buffer) { return (uint64_t)buffer->cap; }
myl_block *myl_core_buffer_from_bytes(myl_block *source) {
    myl_block *out = myl_core_buffer_new((uint64_t)source->len);
    out->len = source->len;
    memcpy(block_data(out), block_data(source), (size_t)source->len);
    return out;
}
myl_block *myl_core_buffer_from_list(myl_block *source) {
    myl_block *out = myl_core_buffer_new((uint64_t)source->len);
    const int64_t *values = (const int64_t *)block_data(source);
    for (int64_t i = 0; i < source->len; ++i) block_data(out)[i] = (uint8_t)values[i];
    out->len = source->len;
    return out;
}
myl_block *myl_core_buffer_snapshot(myl_block *source) {
    myl_block *out = str_new(source->len);
    out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    memcpy(block_data(out), block_data(source), (size_t)source->len);
    return out;
}
bool myl_core_buffer_range_valid(myl_block *source, int64_t start, int64_t end) {
    return start >= 0 && end >= start && end <= source->len;
}
bool myl_core_buffer_reserve_valid(myl_block *source, int64_t extra) {
    return extra >= 0 && extra <= INT64_MAX - source->len;
}
myl_block *myl_core_buffer_reserved(myl_block *source, int64_t extra) {
    myl_block *out = myl_core_buffer_copy(source);
    return core_buffer_grow(out, out->len + extra);
}
myl_block *myl_core_buffer_reverse(myl_block *source) {
    myl_block *out = myl_core_buffer_copy(source);
    for (int64_t i = 0; i < out->len / 2; ++i) {
        unsigned char c = block_data(out)[i];
        block_data(out)[i] = block_data(out)[out->len - 1 - i];
        block_data(out)[out->len - 1 - i] = c;
    }
    return out;
}
/* Port of myl_native_bytes_hex: two lowercase ASCII digits per octet. */
myl_block *myl_core_bytes_hex(myl_block *source) {
    static const unsigned char digits[] = "0123456789abcdef";
    if (source->len > INT64_MAX / 2) out_of_memory();
    myl_block *out = str_new(source->len * 2);
    out->kind |= 1u << 8;
    for (int64_t i = 0; i < source->len; ++i) {
        block_data(out)[i * 2] = digits[block_data(source)[i] >> 4];
        block_data(out)[i * 2 + 1] = digits[block_data(source)[i] & 15];
    }
    return out;
}
static int core_hex_digit(unsigned char value) {
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    if (value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}
bool myl_core_from_hex_valid(myl_block *source) {
    if (source->len % 2) return false;
    for (int64_t i = 0; i < source->len; ++i) if (core_hex_digit(block_data(source)[i]) < 0) return false;
    return true;
}
myl_block *myl_core_from_hex(myl_block *source) {
    myl_block *out = str_new(source->len / 2);
    out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    for (int64_t i = 0; i < out->len; ++i) block_data(out)[i] = (unsigned char)(core_hex_digit(block_data(source)[i * 2]) * 16 + core_hex_digit(block_data(source)[i * 2 + 1]));
    return out;
}

/* Core aggregate adapters; comparisons use UTF-8's order-preserving octets. */
#include <inttypes.h>
int64_t myl_core_octets_compare(const myl_block *a, const myl_block *b) {
    size_t n = (size_t)(a->len < b->len ? a->len : b->len);
    int order = memcmp((const unsigned char *)a + MYL_HEADER, (const unsigned char *)b + MYL_HEADER, n);
    return order ? (order > 0 ? 1 : -1) : (a->len > b->len) - (a->len < b->len);
}

myl_block *myl_core_octets_repeat_unsigned(const myl_block *source, uint64_t count) {
    if (source->len && count > (uint64_t)INT64_MAX / (uint64_t)source->len) out_of_memory();
    size_t n = (size_t)((uint64_t)source->len * count);
    myl_block *result = block_new(MYL_KIND_STR, (int64_t)n + 1, 1);
    result->len = (int64_t)n;
    unsigned char *data = block_data(result);
    for (size_t at = 0; at < n; at += (size_t)source->len) memcpy(data + at, (const unsigned char *)source + MYL_HEADER, (size_t)source->len);
    data[n] = 0;
    return result;
}

myl_block *myl_core_octets_repeat_signed(const myl_block *source, int64_t count) {
    return myl_core_octets_repeat_unsigned(source, count > 0 ? (uint64_t)count : 0);
}

/* Descriptor graph is generated per concrete type. Tags precede payload reads,
 * padding never participates and boxes/list elements are traversed iteratively. */
typedef struct core_value_shape core_value_shape;
struct core_value_shape {
    uint32_t kind, size, count, aux;
    const core_value_shape *const *children;
    const uint32_t *offsets;
    const char *const *names;
};
typedef struct { const core_value_shape *shape; const void *left, *right; uint64_t hash; } core_value_memo_entry;
typedef struct { core_value_memo_entry *entries; size_t count, capacity; } core_value_memo;

static uint64_t value_mix(uint64_t bits) { return bits * UINT64_C(0x9e3779b97f4a7c15); }
static size_t value_memo_slot(const core_value_shape *shape, const void *left, const void *right, size_t capacity) {
    return (size_t)(value_mix((uintptr_t)shape) ^ value_mix((uintptr_t)left) ^ value_mix((uintptr_t)right >> 3)) & (capacity - 1);
}
static void value_memo_grow(core_value_memo *memo) {
    size_t capacity = memo->capacity ? memo->capacity * 2 : 64;
    if (capacity < memo->capacity || capacity > SIZE_MAX / sizeof *memo->entries) out_of_memory();
    core_value_memo_entry *entries = calloc(capacity, sizeof *entries);
    if (!entries) out_of_memory();
    for (size_t i = 0; i < memo->capacity; ++i) {
        core_value_memo_entry entry = memo->entries[i];
        if (!entry.shape) continue;
        size_t slot = value_memo_slot(entry.shape, entry.left, entry.right, capacity);
        while (entries[slot].shape) slot = (slot + 1) & (capacity - 1);
        entries[slot] = entry;
    }
    free(memo->entries);
    memo->entries = entries;
    memo->capacity = capacity;
}
static core_value_memo_entry *value_memo(core_value_memo *memo, const core_value_shape *shape, const void *left, const void *right, bool insert) {
    if (!memo->capacity || (insert && memo->count >= memo->capacity / 2)) value_memo_grow(memo);
    size_t slot = value_memo_slot(shape, left, right, memo->capacity);
    while (memo->entries[slot].shape) {
        core_value_memo_entry *entry = &memo->entries[slot];
        if (entry->shape == shape && entry->left == left && entry->right == right) return entry;
        slot = (slot + 1) & (memo->capacity - 1);
    }
    if (!insert) return NULL;
    ++memo->count;
    memo->entries[slot] = (core_value_memo_entry){shape, left, right, 0};
    return &memo->entries[slot];
}
static const myl_block *value_block(const void *at) {
    const myl_block *block;
    memcpy(&block, at, sizeof block);
    return block;
}
static uint64_t value_tag(const core_value_shape *shape, const void *at) {
    if (shape->aux) return value_block(at) ? 2 - shape->aux : shape->aux - 1;
    uint64_t tag;
    memcpy(&tag, at, sizeof tag);
    return tag;
}
static const unsigned char *value_payload(const core_value_shape *shape, const void *at) {
    return (const unsigned char *)at + (shape->aux ? 0 : 8);
}

typedef struct { const core_value_shape *shape; const unsigned char *left, *right; } core_equal_work;
typedef struct { core_equal_work *items; size_t count, capacity; } core_equal_stack;
static void value_equal_push(core_equal_stack *stack, const core_value_shape *shape, const void *left, const void *right) {
    if (stack->count == stack->capacity) {
        size_t capacity = stack->capacity ? stack->capacity * 2 : 64;
        if (capacity < stack->capacity || capacity > SIZE_MAX / sizeof *stack->items) out_of_memory();
        core_equal_work *items = realloc(stack->items, capacity * sizeof *items);
        if (!items) out_of_memory();
        stack->items = items;
        stack->capacity = capacity;
    }
    stack->items[stack->count++] = (core_equal_work){shape, left, right};
}

bool myl_core_values_equal(const core_value_shape *root, const void *left, const void *right) {
    core_equal_stack stack = {0};
    core_value_memo memo = {0};
    bool same = true;
    value_equal_push(&stack, root, left, right);
    while (same && stack.count) {
        core_equal_work work = stack.items[--stack.count];
        const core_value_shape *shape = work.shape;
        switch (shape->kind) {
        case 0: break;
        case 1: case 10: same = memcmp(work.left, work.right, shape->size) == 0; break;
        case 2: {
            double a, b;
            memcpy(&a, work.left, 8); memcpy(&b, work.right, 8);
            same = a == b;
            break;
        }
        case 3: same = myl_core_str_eq(value_block(work.left), value_block(work.right)); break;
        case 4:
            for (uint32_t i = 0; i < shape->count; ++i)
                value_equal_push(&stack, shape->children[i], work.left + shape->offsets[i], work.right + shape->offsets[i]);
            break;
        case 5: {
            uint64_t tag = value_tag(shape, work.left);
            same = tag == value_tag(shape, work.right);
            if (same && tag < shape->count) value_equal_push(&stack, shape->children[tag], value_payload(shape, work.left), value_payload(shape, work.right));
            else if (tag >= shape->count) abort();
            break;
        }
        case 6: case 7: case 9: {
            const myl_block *a = value_block(work.left), *b = value_block(work.right);
            if (shape->kind != 6 && a->len != b->len) { same = false; break; }
            /* A repeated pair's children are already scheduled or checked. This
             * never treats identical pointers as equal: an embedded NaN is checked. */
            if (value_memo(&memo, shape, a, b, false)) break;
            (void)value_memo(&memo, shape, a, b, true);
            if (shape->kind == 6) {
                value_equal_push(&stack, shape->children[0], (const unsigned char *)a + MYL_HEADER, (const unsigned char *)b + MYL_HEADER);
            } else if (shape->kind == 7) {
                uint32_t stride = shape->children[0]->size;
                for (int64_t i = 0; i < a->len; ++i)
                    value_equal_push(&stack, shape->children[0], (const unsigned char *)a + MYL_HEADER + (size_t)i * stride, (const unsigned char *)b + MYL_HEADER + (size_t)i * stride);
            } else {
                core_dict_meta *ma = dict_meta(a), *mb = dict_meta(b);
                for (uint64_t i = 0; same && i < ma->elen; ++i) {
                    if (!dict_live(ma, i)) continue;
                    unsigned char *entry = dict_entry(a, i);
                    uint64_t hash = dict_hash(mb->desc, entry);
                    int64_t found = myl_core_dict_find(b, entry, hash);
                    if (found < 0) { same = false; break; }
                    value_equal_push(&stack, shape->children[1], entry + ma->desc->value_offset, dict_entry(b, (uint64_t)found) + mb->desc->value_offset);
                }
            }
            break;
        }
        case 8:
            for (uint32_t i = 0; i < shape->count; ++i)
                value_equal_push(&stack, shape->children[0], work.left + (size_t)i * shape->children[0]->size, work.right + (size_t)i * shape->children[0]->size);
            break;
        default: abort();
        }
    }
    free(stack.items);
    free(memo.entries);
    return same;
}

typedef struct { const core_value_shape *shape; const unsigned char *at; uint64_t index, hash; const void *memo; } core_hash_work;
typedef struct { core_hash_work *items; size_t count, capacity; } core_hash_stack;
static void value_hash_push(core_hash_stack *stack, const core_value_shape *shape, const void *at) {
    if (stack->count == stack->capacity) {
        size_t capacity = stack->capacity ? stack->capacity * 2 : 64;
        if (capacity < stack->capacity || capacity > SIZE_MAX / sizeof *stack->items) out_of_memory();
        core_hash_work *items = realloc(stack->items, capacity * sizeof *items);
        if (!items) out_of_memory();
        stack->items = items;
        stack->capacity = capacity;
    }
    stack->items[stack->count++] = (core_hash_work){shape, at, UINT64_MAX, 0, NULL};
}
static uint64_t value_scalar_hash(const core_value_shape *shape, const void *at) {
    uint64_t bits = 0;
    if (shape->kind == 3) bits = myl_core_str_hash(value_block(at));
    else if (shape->kind == 2) {
        double value;
        memcpy(&value, at, 8);
        if (value == 0.0) bits = 0;
        else if (value != value) bits = UINT64_C(0x7ff8000000000000);
        else memcpy(&bits, at, 8);
    } else memcpy(&bits, at, shape->size);
    uint64_t mixed = value_mix(bits);
    return mixed ^ (mixed >> 32);
}

uint64_t myl_core_values_hash(const core_value_shape *root, const void *at) {
    core_hash_stack stack = {0};
    core_value_memo memo = {0};
    uint64_t returned = 0;
    value_hash_push(&stack, root, at);
    while (stack.count) {
        core_hash_work *work = &stack.items[stack.count - 1];
        const core_value_shape *shape = work->shape;
        if (shape->kind <= 3 || shape->kind == 10) {
            returned = shape->kind ? value_scalar_hash(shape, work->at) : 0;
            --stack.count;
            continue;
        }
        if (work->index == UINT64_MAX) {
            work->index = 0;
            if (shape->kind == 6 || shape->kind == 7 || shape->kind == 9) {
                const myl_block *block = value_block(work->at);
                core_value_memo_entry *known = value_memo(&memo, shape, block, NULL, false);
                if (known) { returned = known->hash; --stack.count; continue; }
                work->memo = block;
                work->at = (const unsigned char *)block + MYL_HEADER;
            }
            if (shape->kind == 5) work->hash = value_mix(value_tag(shape, work->at));
        } else if (work->index) {
            work->hash = value_mix(work->hash) ^ returned;
        }
        const core_value_shape *child = NULL;
        const unsigned char *part = NULL;
        uint64_t index = work->index++;
        switch (shape->kind) {
        case 4:
            if (index < shape->count) { child = shape->children[index]; part = work->at + shape->offsets[index]; }
            break;
        case 5:
            if (index == 0) {
                uint64_t tag = value_tag(shape, work->at);
                if (tag >= shape->count) abort();
                child = shape->children[tag]; part = value_payload(shape, work->at);
            }
            break;
        case 6:
            if (index == 0) { child = shape->children[0]; part = work->at; }
            break;
        case 7: {
            const myl_block *block = work->memo;
            if (index < (uint64_t)block->len) { child = shape->children[0]; part = work->at + index * child->size; }
            break;
        }
        case 8:
            if (index < shape->count) { child = shape->children[0]; part = work->at + index * child->size; }
            break;
        case 9: abort(); /* Mutable tables are not accepted as dictionary keys. */
        default: abort();
        }
        if (child) {
            value_hash_push(&stack, child, part);
        } else {
            returned = work->hash;
            if (work->memo) value_memo(&memo, shape, work->memo, NULL, true)->hash = returned;
            --stack.count;
        }
    }
    free(stack.items);
    free(memo.entries);
    return returned;
}

bool myl_core_same_block(const myl_block *left, const myl_block *right) { return left == right; }

/* The old print/str spelling from io_render.zig and native_render.zig.
 * Source rendering descriptors retain unit payload presence in union offsets,
 * dictionary/set identity in aux and domain names in kind 11. Their child sizes
 * remain physical strides, including one-byte unit placeholders.
 * Depth is bounded at 24, and
 * transparent boxes do not consume depth. The graph traversal above remains
 * iterative for equality/hashing, where no rendering depth cap applies. */
typedef struct { char *data; size_t count, capacity; } core_render_buffer;
static void value_render_bytes(core_render_buffer *output, const void *bytes, size_t count) {
    if (count > SIZE_MAX - output->count) out_of_memory();
    size_t wanted = output->count + count;
    if (wanted > output->capacity) {
        size_t capacity = output->capacity ? output->capacity : 64;
        while (capacity < wanted) {
            if (capacity > SIZE_MAX / 2) out_of_memory();
            capacity *= 2;
        }
        char *data = realloc(output->data, capacity);
        if (!data) out_of_memory();
        output->data = data;
        output->capacity = capacity;
    }
    if (count) memcpy(output->data + output->count, bytes, count);
    output->count = wanted;
}
static void value_render_text(core_render_buffer *output, const char *text) {
    value_render_bytes(output, text, strlen(text));
}
static void value_render_octets(core_render_buffer *output, const myl_block *block, bool bytes, unsigned depth) {
    bool quoted = bytes || depth != 0;
    if (bytes) value_render_text(output, "b");
    if (quoted) value_render_text(output, "'");
    const unsigned char *data = (const unsigned char *)block + MYL_HEADER;
    for (int64_t i = 0; i < block->len; ++i) {
        unsigned char byte = data[i];
        if (quoted && (byte == '\'' || byte == '\\')) {
            value_render_text(output, "\\");
            value_render_bytes(output, &byte, 1);
        } else if (quoted && (byte == '\n' || byte == '\r' || byte == '\t')) {
            char escape[2] = {'\\', byte == '\n' ? 'n' : byte == '\r' ? 'r' : 't'};
            value_render_bytes(output, escape, 2);
        } else if (bytes && (byte < 0x20 || byte >= 0x7f)) {
            const char hex[] = "0123456789abcdef";
            char escape[4] = {'\\', 'x', hex[byte >> 4], hex[byte & 15]};
            value_render_bytes(output, escape, 4);
        } else value_render_bytes(output, &byte, 1);
    }
    if (quoted) value_render_text(output, "'");
}
extern myl_block *myl_core_str_from_f64(double value) __attribute__((weak));
static void value_render(core_render_buffer *output, const core_value_shape *shape, const unsigned char *at, unsigned depth) {
    if (depth > 24) { value_render_text(output, "..."); return; }
    switch (shape->kind) {
    case 0: value_render_text(output, "None"); break;
    case 1: {
        uint64_t bits = 0;
        memcpy(&bits, at, shape->size);
        if (shape->aux == 1) { value_render_text(output, bits ? "True" : "False"); break; }
        char number[32];
        if (shape->aux == 2) {
            unsigned width = shape->size * 8;
            if (width < 64 && (bits & (UINT64_C(1) << (width - 1)))) bits |= UINT64_MAX << width;
            int64_t signed_value;
            memcpy(&signed_value, &bits, 8);
            snprintf(number, sizeof number, "%" PRId64, signed_value);
        } else snprintf(number, sizeof number, "%" PRIu64, bits);
        value_render_text(output, number);
        break;
    }
    case 2: {
        if (!myl_core_str_from_f64) abort();
        double value;
        memcpy(&value, at, 8);
        myl_block *text = myl_core_str_from_f64(value);
        value_render_bytes(output, block_data(text), (size_t)text->len);
        myl_core_release(text);
        break;
    }
    case 3: value_render_octets(output, value_block(at), shape->aux != 0, depth); break;
    case 4:
        if (!shape->names) abort();
        if (!shape->aux) value_render_text(output, shape->names[0]);
        value_render_text(output, "(");
        for (uint32_t i = 0; i < shape->count; ++i) {
            if (i) value_render_text(output, ", ");
            if (!shape->aux) { value_render_text(output, shape->names[i + 1]); value_render_text(output, "="); }
            value_render(output, shape->children[i], at + shape->offsets[i], depth + 1);
        }
        value_render_text(output, ")");
        break;
    case 5: {
        uint64_t tag = value_tag(shape, at);
        if (tag >= shape->count || !shape->names) abort();
        value_render_text(output, shape->names[tag]);
        if (shape->offsets ? shape->offsets[tag] != 0 : shape->children[tag]->kind != 0) {
            value_render_text(output, "(");
            value_render(output, shape->children[tag], value_payload(shape, at), depth + 1);
            value_render_text(output, ")");
        }
        break;
    }
    case 6:
        value_render(output, shape->children[0], (const unsigned char *)value_block(at) + MYL_HEADER, depth);
        break;
    case 7: case 8: {
        const unsigned char *data = at;
        uint64_t count = shape->count;
        if (shape->kind == 7) {
            const myl_block *block = value_block(at);
            data = (const unsigned char *)block + MYL_HEADER;
            count = (uint64_t)block->len;
        }
        value_render_text(output, "[");
        for (uint64_t i = 0; i < count; ++i) {
            if (i) value_render_text(output, ", ");
            value_render(output, shape->children[0], data + i * shape->children[0]->size, depth + 1);
        }
        value_render_text(output, "]");
        break;
    }
    case 9: {
        const myl_block *dict = value_block(at);
        bool set = shape->aux ? shape->aux == 1 : shape->children[1]->kind == 0;
        if (set && !dict->len) { value_render_text(output, "set()"); break; }
        core_dict_meta *meta = dict_meta(dict);
        value_render_text(output, "{");
        bool first = true;
        for (uint64_t i = 0; i < meta->elen; ++i) {
            if (!dict_live(meta, i)) continue;
            if (!first) value_render_text(output, ", ");
            first = false;
            unsigned char *entry = dict_entry(dict, i);
            value_render(output, shape->children[0], entry, depth + 1);
            if (!set) {
                value_render_text(output, ": ");
                value_render(output, shape->children[1], entry + meta->desc->value_offset, depth + 1);
            }
        }
        value_render_text(output, "}");
        break;
    }
    case 11:
        value_render_text(output, shape->names[0]);
        value_render_text(output, "(");
        value_render(output, shape->children[0], at, depth + 1);
        value_render_text(output, ")");
        break;
    default: abort();
    }
}
myl_block *myl_core_values_render(const core_value_shape *shape, const void *at) {
    core_render_buffer output = {0};
    value_render(&output, shape, at, 0);
    myl_block *text = str_from(output.data, output.count);
    free(output.data);
    return text;
}
myl_block *myl_core_none_text(void) { return str_from("None", 4); }

/* Core-owned property trial transport. The old generation/counting/shrinking
 * algorithms stay in Zig. Fork gives a fatal Core trap a bounded copied-value
 * trial boundary without skipping reference-count cleanup on a longjmp. */
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>
#if defined(__linux__)
#include <sys/prctl.h>
#endif
static FILE *core_test_input, *core_test_output, *core_test_values;
static char *core_test_path;
static uint64_t core_test_trials;
static uint64_t core_test_steps;
static bool core_test_bounded;
/* Compatible additive helpers; existing runtime signatures and layouts stay fixed. */
void myl_core_test_limits(uint64_t steps, uint32_t timeout_ms) {
    core_test_steps=steps;core_test_bounded=steps!=0;
    alarm((unsigned)((uint64_t)timeout_ms+999)/1000);
}
void myl_core_test_tick(uint64_t cost) {
    if(!core_test_bounded)return;
    if(cost>core_test_steps)core_io_fail("R_STEP_LIMIT");
    core_test_steps-=cost;
}
static uint64_t core_test_word(FILE *file) {
    unsigned char bytes[8];
    if (!file || fread(bytes, 1, 8, file) != 8) _exit(70);
    uint64_t word = 0;
    for (unsigned i = 0; i < 8; ++i) word |= (uint64_t)bytes[i] << (8 * i);
    return word;
}
static void core_test_put(FILE *file, uint64_t word) {
    unsigned char bytes[8];
    for (unsigned i = 0; i < 8; ++i) bytes[i] = (unsigned char)(word >> (8 * i));
    if (!file || fwrite(bytes, 1, 8, file) != 8) _exit(70);
}
uint64_t myl_core_test_read(void) { return core_test_word(core_test_input); }
void myl_core_test_write(uint64_t word) { core_test_put(core_test_values, word); }
bool myl_core_test_read_bool(void){uint64_t bits=myl_core_test_read();(void)myl_core_test_read();return bits!=0;}
void myl_core_test_write_bool(bool value){myl_core_test_write(value?1:0);myl_core_test_write(0);}
double myl_core_test_read_float(void) {
    uint64_t bits = myl_core_test_read(); (void)myl_core_test_read();
    double value; memcpy(&value, &bits, 8); return value;
}
void myl_core_test_write_float(double value) {
    uint64_t bits; memcpy(&bits, &value, 8);
    myl_core_test_write(bits); myl_core_test_write(0);
}
static unsigned core_test_scalar(unsigned char *out, uint32_t point) {
    if (point < 0x80) {out[0]=(unsigned char)point; return 1;}
    if (point < 0x800) {out[0]=(unsigned char)(0xc0|(point>>6));out[1]=(unsigned char)(0x80|(point&63));return 2;}
    if (point < 0x10000 && !(point>=0xd800 && point<=0xdfff)) {
        out[0]=(unsigned char)(0xe0|(point>>12));out[1]=(unsigned char)(0x80|((point>>6)&63));out[2]=(unsigned char)(0x80|(point&63));return 3;
    }
    if (point<=0x10ffff) {
        out[0]=(unsigned char)(0xf0|(point>>18));out[1]=(unsigned char)(0x80|((point>>12)&63));out[2]=(unsigned char)(0x80|((point>>6)&63));out[3]=(unsigned char)(0x80|(point&63));return 4;
    }
    _exit(70);
}
static myl_block *core_test_read_octets(bool bytes) {
    (void)myl_core_test_read(); uint64_t count=myl_core_test_read();
    if (count>4096) _exit(70);
    size_t capacity=(size_t)count*(bytes?1:4);
    myl_block *text=block_new(bytes?MYL_KIND_BYTES:MYL_KIND_STR,(int64_t)capacity+1,1);
    size_t used=0;
    for(uint64_t i=0;i<count;++i){
        uint64_t point=myl_core_test_read(); (void)myl_core_test_read();
        if(bytes){if(point>255)_exit(70);block_data(text)[used++]=(unsigned char)point;}
        else used+=core_test_scalar(block_data(text)+used,(uint32_t)point);
    }
    text->len=(int64_t)used;block_data(text)[used]=0;
    if(!bytes)core_text_publish(text);
    return text;
}
myl_block *myl_core_test_read_text(void){return core_test_read_octets(false);}
myl_block *myl_core_test_read_bytes(void){return core_test_read_octets(true);}
void myl_core_test_write_text(myl_block *text,uint32_t bytes){
    const unsigned char *p=block_data(text);size_t n=(size_t)text->len;
    uint64_t count=0;
    if(bytes)count=n;else for(size_t i=0;i<n;++i)if((p[i]&0xc0)!=0x80)++count;
    myl_core_test_write(0);myl_core_test_write(count);
    for(size_t i=0;i<n;){
        uint32_t point=p[i++];
        if(!bytes&&point>=0xc0){
            unsigned tails=point<0xe0?1:point<0xf0?2:3;
            point&=tails==1?31:tails==2?15:7;
            for(unsigned j=0;j<tails;++j){if(i>=n)_exit(70);point=(point<<6)|(p[i++]&63);}
        }
        myl_core_test_write(point);myl_core_test_write(0);
    }
}
static char *core_test_named(const char *suffix){
    size_t a=strlen(core_test_path),b=strlen(suffix);char *path=malloc(a+b+1);
    if(!path)out_of_memory();memcpy(path,core_test_path,a);memcpy(path+a,suffix,b+1);return path;
}
static void core_test_copy(FILE *target,FILE *source){
    if(fflush(source)||fseek(source,0,SEEK_END))_exit(70);
    long size=ftell(source);if(size<0||fseek(source,0,SEEK_SET))_exit(70);
    core_test_put(target,(uint64_t)size);
    unsigned char bytes[4096];size_t count;
    while((count=fread(bytes,1,sizeof bytes,source)))if(fwrite(bytes,1,count,target)!=count)_exit(70);
}
static void core_test_capture(const char *suffix,int descriptor){
    char *path=core_test_named(suffix);int fd=open(path,O_RDWR|O_CREAT|O_TRUNC,0600);free(path);
    if(fd<0||dup2(fd,descriptor)<0)_exit(70);close(fd);
}
static void core_test_file(FILE *target,const char *suffix){
    char *path=core_test_named(suffix);FILE *file=fopen(path,"rb");free(path);
    if(!file){core_test_put(target,0);return;}core_test_copy(target,file);fclose(file);
}
static void core_test_record(uint64_t status,FILE *values){
    core_test_put(core_test_output,status);
    if(values)core_test_copy(core_test_output,values);else core_test_put(core_test_output,0);
    core_test_file(core_test_output,".out");core_test_file(core_test_output,".err");core_test_file(core_test_output,".trace");
    if(fflush(core_test_output))_exit(70);
}
static bool core_test_trapped(void){
    char *path=core_test_named(".err");FILE *file=fopen(path,"rb");free(path);
    if(!file)return false;
    static const unsigned char marker[]="\036MYLANG-TRAP ";
    unsigned matched=0;int byte;bool found=false;
    while((byte=fgetc(file))!=EOF){
        if(byte==marker[matched]){
            if(marker[++matched]==0){found=true;break;}
        }else matched=byte==marker[0]?1:0;
    }
    fclose(file);return found;
}
static void core_test_stderr(void){
    char *path=core_test_named(".err");FILE *file=fopen(path,"rb");free(path);
    if(!file)return;
    unsigned char bytes[4096];size_t count;
    while((count=fread(bytes,1,sizeof bytes,file)))if(fwrite(bytes,1,count,stderr)!=count)_exit(70);
    fclose(file);if(fflush(stderr))_exit(70);
}
/* Source traces are kept apart from arbitrary stderr output. */
void myl_core_test_trace(void){
    stream_flush(&streams[1]);int saved=dup(2);core_test_capture(".trace",2);
    trace_write();stream_flush(&streams[1]);if(dup2(saved,2)<0)_exit(70);close(saved);
}
bool myl_core_test_open(myl_block *input,myl_block *output){
    core_test_input=fopen((const char *)block_data(input),"rb");
    core_test_output=fopen((const char *)block_data(output),"wb");
    core_test_path=strdup((const char *)block_data(output));
    if(!core_test_input||!core_test_output||!core_test_path)return false;
    core_test_trials=core_test_word(core_test_input);return true;
}
int64_t myl_core_test_run(void (*trial)(void)){
    for(uint64_t i=0;i<core_test_trials;++i){
        uint64_t words=core_test_word(core_test_input);long start=ftell(core_test_input);
        if(words>1000000||start<0)_exit(70);
        const char *suffixes[]={".out",".err",".trace"};
        for(unsigned j=0;j<3;++j){char *path=core_test_named(suffixes[j]);FILE *empty=fopen(path,"wb");free(path);if(empty)fclose(empty);}
        flush_all();if(fflush(NULL))_exit(70);
        int64_t baseline=live_count();pid_t parent=getpid();pid_t child=fork();if(child<0)_exit(70);
        if(child==0){
#if defined(__linux__)
            if(prctl(PR_SET_PDEATHSIG,SIGKILL)<0||getppid()!=parent)_exit(70);
#else
            (void)parent;
#endif
            core_test_values=tmpfile();if(!core_test_values)_exit(70);
            core_test_capture(".out",1);core_test_capture(".err",2);
            alarm(60);error_trace.origin=-1;error_trace.count=0;trial();alarm(0);flush_all();
            core_io_cleanup();
            const char *check=getenv("MYL_CORE_LEAKCHECK");
            if(check&&strcmp(check,"0")&&live_count()!=baseline){
                fprintf(stderr,"myl-core leakcheck: %lld blocks remain after trial\n",(long long)(live_count()-baseline));fflush(stderr);
                core_test_record(4,core_test_values);_exit(0);
            }
            core_test_record(0,core_test_values);_exit(0);
        }
        int status;while(waitpid(child,&status,0)<0){if(errno!=EINTR)_exit(70);}
        if(WIFSIGNALED(status)){
            /* A signal cuts off the batch exactly like the old harness. Its
             * completed prefix is durable; the Zig search retries this input
             * alone before classifying it or adopting a shrink candidate. */
            int caught=WTERMSIG(status);core_test_stderr();fclose(core_test_input);fclose(core_test_output);
            signal(caught,SIG_DFL);raise(caught);_exit(70);
        }
        if(WEXITSTATUS(status)!=0){
            if(core_test_trapped())core_test_record(1,NULL);
            else {
                /* An arbitrary native exit did not answer this trial. Keep
                 * its status and the completed prefix for old retry grading. */
                int code=WEXITSTATUS(status);core_test_stderr();fclose(core_test_input);fclose(core_test_output);_exit(code);
            }
        }
        if(fseek(core_test_input,start+(long)(words*8),SEEK_SET))_exit(70);
    }
    fclose(core_test_input);fclose(core_test_output);free(core_test_path);
    core_test_input=NULL;core_test_output=NULL;core_test_path=NULL;return 0;
}
