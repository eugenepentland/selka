/* The bare runtime's heap (-DMYL_BARE): one arena for each core of the CPU (MCU-CORE1).
 *
 * An arena is a range of memory with its own blocks. Every block is a multiple of 32 bytes with an 8-byte header {size of
 * the block before, size | used} and 32-byte-aligned data; free blocks are on the arena's first-fit list and a freed
 * block merges with free neighbours. Core 0's arena is the image's heap (__heap_start to __heap_end, core_bare.c); core
 * 1's is the part of a block of core 0's arena that `registers.start_core1` gives it below its stack
 * (core_bare_cores.c). `malloc`, `free` and the rest (core_bare.c) work in the arena of the core that calls them
 * (`bare_arena_here`), so the two cores never touch each other's blocks or lists and need no lock: the two cores share
 * no heap value (a value lives in the arena of the core that made it). Freeing a block that is not in the calling core's
 * arena is a runtime defect, which `bare_arena_free` reports instead of corrupting the other core's list.
 *
 * The file depends on nothing but <stdint.h>, <stddef.h>, `memcpy` and `bare_core` (the calling core's number, defined by
 * core_bare_cores.c), so a host test compiles it alone (src/core/bare_heap_test.zig, which defines MYL_BARE_CORES).
 *
 * Only the two-core flavour of the runtime has it (-DMYL_BARE_CORES, `driver.bareCores`): a program that never starts
 * the second core keeps core_bare.c's one heap. */
#if defined(MYL_BARE_CORES)

typedef struct bare_chunk {
    uint32_t before;              /* size of the block just below this one (0: the first block) */
    uint32_t size;                /* this block's size in bytes, a multiple of 32; bit 0: in use */
    struct bare_chunk *next, *prev; /* free blocks only: the free list, in the first data bytes */
} bare_chunk;
enum { BARE_UNIT = 32, BARE_HEAD = 8, BARE_USED = 1, BARE_CORES = 2 };

/* One arena: its first block, its top block (a used block of size 0 that ends every merge), its free list, and the
   lowest and highest address a block has reached (the exit report's high-water mark). */
typedef struct {
    bare_chunk *first, *end, *free;
    uintptr_t base, top;
} bare_arena;

static bare_arena bare_arenas[BARE_CORES];

/* The calling core: 0 or 1 (core_bare_cores.c; a test defines its own). */
static unsigned bare_core(void);

/* The arena of the calling core: the one `malloc` and `free` use. */
static bare_arena *bare_arena_here(void) { return &bare_arenas[bare_core()]; }

static uint32_t bare_size(const bare_chunk *c) { return c->size & ~(uint32_t)BARE_USED; }
static bare_chunk *bare_after(bare_chunk *c) { return (bare_chunk *)((unsigned char *)c + bare_size(c)); }
static void *bare_data(bare_chunk *c) { return (unsigned char *)c + BARE_HEAD; }
static bare_chunk *bare_chunk_of(void *data) { return (bare_chunk *)((unsigned char *)data - BARE_HEAD); }

static void bare_unlink(bare_arena *a, bare_chunk *c) {
    if (c->prev) c->prev->next = c->next; else a->free = c->next;
    if (c->next) c->next->prev = c->prev;
}
static void bare_push(bare_arena *a, bare_chunk *c) {
    c->size &= ~(uint32_t)BARE_USED;
    c->prev = NULL;
    c->next = a->free;
    if (a->free) a->free->prev = c;
    a->free = c;
}

/* Make `a` the memory from `low` to `high` and answer how many bytes it holds (the core's byte ceiling). Data at a
   32-byte boundary: a block starts 8 bytes before one, and every size is a multiple of 32. */
static uint64_t bare_arena_init(bare_arena *a, uintptr_t low, uintptr_t high) {
    low = (low + BARE_HEAD + BARE_UNIT - 1) / BARE_UNIT * BARE_UNIT - BARE_HEAD;
    high = (high - BARE_HEAD) / BARE_UNIT * BARE_UNIT - BARE_HEAD;
    a->first = (bare_chunk *)low;
    a->end = (bare_chunk *)high;
    a->first->before = 0;
    a->first->size = (uint32_t)(high - low);
    a->end->before = a->first->size;
    a->end->size = BARE_USED;
    a->free = NULL;
    bare_push(a, a->first);
    a->base = a->top = low;
    return high - low;
}

/* Whether `data` is the data of a block of `a`. */
static int bare_arena_holds(const bare_arena *a, const void *data) {
    const uintptr_t at = (uintptr_t)data;
    return at >= (uintptr_t)a->first + BARE_HEAD && at < (uintptr_t)a->end;
}

/* Split `c` (in use) to `need` bytes when the rest makes a block, and free the rest. */
static void bare_trim(bare_arena *a, bare_chunk *c, uint32_t need) {
    uint32_t size = bare_size(c);
    if (size - need < BARE_UNIT) return;
    bare_chunk *rest = (bare_chunk *)((unsigned char *)c + need);
    rest->before = need;
    rest->size = size - need;
    bare_after(rest)->before = rest->size;
    c->size = need | BARE_USED;
    bare_push(a, rest);
}

static uint32_t bare_need(const bare_arena *a, size_t bytes) {
    if (bytes > (size_t)((uintptr_t)a->end - (uintptr_t)a->first)) return 0;
    uint32_t need = (uint32_t)((bytes + BARE_HEAD + BARE_UNIT - 1) / BARE_UNIT * BARE_UNIT);
    return need < BARE_UNIT ? BARE_UNIT : need;
}

static void bare_mark_top(bare_arena *a, bare_chunk *c) {
    uintptr_t top = (uintptr_t)c + bare_size(c);
    if (top > a->top) a->top = top;
}

/* `bytes` from `a`, or NULL when no free block is large enough (or `a` was never made). */
static void *bare_arena_alloc(bare_arena *a, size_t bytes) {
    if (!a->first) return NULL;
    uint32_t need = bare_need(a, bytes);
    if (!need) return NULL;
    for (bare_chunk *c = a->free; c; c = c->next) {
        if (bare_size(c) < need) continue;
        bare_unlink(a, c);
        c->size |= BARE_USED;
        bare_trim(a, c, need);
        bare_mark_top(a, c);
        return bare_data(c);
    }
    return NULL;
}

/* Free `data`, a block of `a`; 0 (and nothing changed) when it is not one. */
static int bare_arena_free(bare_arena *a, void *data) {
    if (!data) return 1;
    if (!bare_arena_holds(a, data)) return 0;
    bare_chunk *c = bare_chunk_of(data);
    c->size &= ~(uint32_t)BARE_USED;
    bare_chunk *next = bare_after(c);
    if (!(next->size & BARE_USED)) {
        bare_unlink(a, next);
        c->size += next->size;
    }
    if (c != a->first) {
        bare_chunk *below = (bare_chunk *)((unsigned char *)c - c->before);
        if (!(below->size & BARE_USED)) {
            bare_unlink(a, below);
            below->size += c->size;
            c = below;
        }
    }
    bare_after(c)->before = c->size;
    bare_push(a, c);
    return 1;
}

static size_t bare_usable(void *data) { return data ? bare_size(bare_chunk_of(data)) - BARE_HEAD : 0; }

/* `data` (a block of `a`, or NULL) resized to `bytes`: in place when it or its free neighbour above has room, else moved.
   NULL when no block is large enough (and `data` is unchanged). */
static void *bare_arena_realloc(bare_arena *a, void *data, size_t bytes) {
    if (!data) return bare_arena_alloc(a, bytes);
    uint32_t need = bare_need(a, bytes);
    if (!need) return NULL;
    bare_chunk *c = bare_chunk_of(data);
    bare_chunk *next = bare_after(c);
    if (bare_size(c) < need && !(next->size & BARE_USED) && bare_size(c) + next->size >= need) {
        bare_unlink(a, next);
        c->size += next->size;
        bare_after(c)->before = bare_size(c);
    }
    if (bare_size(c) >= need) {
        bare_trim(a, c, need);
        bare_mark_top(a, c);
        return data;
    }
    void *moved = bare_arena_alloc(a, bytes);
    if (!moved) return NULL;
    memcpy(moved, data, bare_size(c) - BARE_HEAD);
    bare_arena_free(a, data);
    return moved;
}

/* The size of the largest free block of `a`, header included (what one allocation could take, plus 8). */
static uint32_t bare_arena_largest(const bare_arena *a) {
    uint32_t largest = 0;
    for (const bare_chunk *c = a->free; c; c = c->next)
        if (bare_size(c) > largest) largest = bare_size(c);
    return largest;
}
#endif /* MYL_BARE_CORES */
