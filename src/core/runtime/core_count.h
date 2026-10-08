/* Counting builds only (`mylang build --counters`, NEW-CORE-COUNTERS-1..5).
 * `count_runtime.zig` inserts this text after the runtime's includes and calls to
 * these hooks at fixed places of the runtime; `core_count.c`, appended after the
 * runtime, defines them. An ordinary build compiles none of it.
 *
 * Per-function counters, in pairs (events, bytes) except where noted. The slot
 * names are `myl_count_slot_names` in core_count.c; the emitter increments
 * MYL_COUNT_CALLS in each function's prologue (`emit_count.function_calls`). */
enum {
    MYL_COUNT_CALLS = 0,            /* calls of the function (slot 1 unused) */
    MYL_COUNT_ALLOCS = 2,           /* blocks allocated, bytes */
    MYL_COUNT_FREES = 4,            /* blocks freed, bytes */
    MYL_COUNT_LIST_GROWS = 6,       /* small lists grown into a new block, bytes copied */
    MYL_COUNT_REALLOCS = 8,         /* large lists grown with realloc, bytes added */
    MYL_COUNT_REALLOC_MOVES = 10,   /* of those, the block moved; bytes in use when it moved */
    MYL_COUNT_LIST_COPIES = 12,     /* list_copy, element bytes */
    MYL_COUNT_DICT_COPIES = 14,     /* dict_copy, entry and hash bytes */
    MYL_COUNT_BUFFER_COPIES = 16,   /* buffer_copy, bytes */
    MYL_COUNT_TEXT_COPIES = 18,     /* str_from_view, bytes */
    MYL_COUNT_RUNTIME_RETAINS = 20, /* retains done by the runtime (a copy's children) */
    MYL_COUNT_RUNTIME_RELEASES = 22, /* releases done by the runtime (a free's children) */
    MYL_COUNT_DICT_GROWS = 24,      /* dictionaries grown, entry and hash bytes copied */
    MYL_COUNT_BUFFER_GROWS = 26,    /* byte buffers grown, bytes copied */
    MYL_COUNT_TEXT_GROWS = 28,      /* text appends that moved the text, bytes copied */
    MYL_COUNT_TEXT_APPENDS = 30,    /* out-of-line text appends, bytes appended */
    MYL_COUNT_BUFFER_PUSHES = 32,   /* out-of-line byte pushes, bytes */
    MYL_COUNT_BUFFER_APPENDS = 34,  /* out-of-line byte appends (`append_range`, numbers), bytes */
    MYL_COUNT_SHARED_RETAINS = 36,
    MYL_COUNT_SHARED_RELEASES = 38,
    MYL_COUNT_SHARE_MARKS = 40,     /* marked blocks and their allocated bytes */
    MYL_COUNT_SLOTS = 42
};

static void myl_count_alloc(size_t bytes);
static void myl_count_free(size_t bytes);
static void myl_count_realloc(size_t before, size_t after, int moved, size_t used);
static void myl_count_event(int slot, size_t bytes);
static void myl_count_list_grow(size_t bytes);
static void myl_count_copy(int slot, size_t bytes);
static void myl_count_dump(void);
