/* Deterministic stand-in capabilities: a simulated clock, a seeded entropy
   stream, an in-memory filesystem, a fixed environment and a denied network.
   Each lives in a registry owned by one execution context. A stand-in's word
   (or, for a filesystem or network, the registry index inside its resource
   authority) is disjoint from every host-granted word, and no function here
   reads a host provider, the process environment or the real filesystem, so a
   stand-in can never reach a real resource. */
#include "qbe_runtime.h"
#include "native_providers.h"
#include "native_text.h"
#include "native_collections.h"
#include <stdlib.h>
#include <string.h>

/* Bounds shared with the host-granted surface. */
#define NAME_LIMIT 128u
#define VALUE_LIMIT 16384u
#define NAMES_LIMIT 64u
#define MEMORY_HANDLES 256u
#define MEMORY_BYTES (64u * 1024u * 1024u)
#define PATH_LIMIT 4094u
#define SNAPSHOT_BYTES (64u * 1024u)
#define SNAPSHOT_ENTRIES 256u

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
typedef struct { int live; MemoryEntry *entry; unsigned char *snapshot; size_t length, position; unsigned char mode; } MemoryHandle;
typedef struct {
    MemoryEntry **entries;
    size_t count, capacity, bytes;
    MemoryHandle handles[MEMORY_HANDLES];
} MemoryFs;
/* One stand-in. `value` is a clock reading or an entropy state; `pairs` holds
   an environment's `NAME\0VALUE\0...` bytes and `scope` the `NAME\0...` names
   an `env.only(...)` narrowed it to (NULL for the unnarrowed root). */
typedef struct {
    unsigned kind;
    int64_t value;
    MemoryFs *memory;
    MylangResourceProvider provider;
    unsigned char *pairs, *scope;
    size_t pairs_length, scope_length;
} StandIn;
typedef struct { StandIn **items; size_t count, capacity; } Registry;

static void memory_free(MemoryFs *memory);
static void release_all(void *context) {
    MylQbeContext *ctx = context;
    Registry *registry = ctx->stand_ins;
    if (!registry) return;
    for (size_t i = 0; i < registry->count; ++i) {
        StandIn *entry = registry->items[i];
        if (entry->memory) memory_free(entry->memory);
        free(entry->pairs);
        free(entry->scope);
        free(entry);
    }
    free(registry->items);
    free(registry);
    ctx->stand_ins = NULL;
    ctx->stand_in_cleanup = NULL;
}
/* Append one zeroed stand-in and return its 0-based index, or trap. */
static StandIn *append(MylQbeContext *ctx, unsigned kind, size_t *index) {
    Registry *registry = ctx->stand_ins;
    if (!registry) {
        registry = calloc(1, sizeof *registry);
        if (!registry) { myl_qbe_fail_allocation(ctx); return NULL; }
        ctx->stand_ins = registry;
        ctx->stand_in_cleanup = release_all;
    }
    if (registry->count == MYL_QBE_STAND_IN_LIMIT) { myl_qbe_fail(ctx, "CapacityLimit"); return NULL; }
    if (registry->count == registry->capacity) {
        size_t grown = registry->capacity ? registry->capacity * 2 : 8;
        StandIn **items = realloc(registry->items, grown * sizeof *items);
        if (!items) { myl_qbe_fail_allocation(ctx); return NULL; }
        registry->items = items;
        registry->capacity = grown;
    }
    StandIn *entry = calloc(1, sizeof *entry);
    if (!entry) { myl_qbe_fail_allocation(ctx); return NULL; }
    entry->kind = kind;
    *index = registry->count;
    registry->items[registry->count++] = entry;
    return entry;
}
/* The registry entry of `index` when it is a stand-in of `kind`, else NULL. */
static StandIn *lookup(void *context, uint64_t index, unsigned kind) {
    MylQbeContext *ctx = context;
    Registry *registry = ctx->stand_ins;
    if (!registry || index >= registry->count) return NULL;
    StandIn *entry = registry->items[index];
    return entry->kind == kind ? entry : NULL;
}
static StandIn *word_lookup(void *context, uint64_t word, unsigned kind) {
    if (!MYL_QBE_IS_STAND_IN(word)) return NULL;
    return lookup(context, word - MYL_QBE_STAND_IN_BASE, kind);
}
/* The resource authority of a registry index, matching qbe_resources.c:
   `-16 - (stand_in*2048 + scope*16 + kind*8 + permissions)` with scope 0. */
static uint64_t resource_word(size_t index, unsigned kind) {
    int64_t encoded = (int64_t)(index + 1) * 2048 + (int64_t)kind * 8 + 7;
    return (uint64_t)(INT64_C(-16) - encoded);
}

/* ---- in-memory filesystem ------------------------------------------------ */

/* The scoped-root path rule: relative, no empty, `.` or `..` component, no NUL
   or backslash. An empty path names the root and only metadata/listing take it. */
static int valid_path(const unsigned char *path, size_t length, unsigned char mode) {
    if (!length) return mode == 'm' || mode == 'l';
    if (length > PATH_LIMIT || memchr(path, '\\', length) || memchr(path, 0, length)) return 0;
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
static MemoryEntry *find(MemoryFs *memory, const unsigned char *path, size_t length) {
    for (size_t i = 0; i < memory->count; ++i) {
        MemoryEntry *entry = memory->entries[i];
        if (entry->length == length && !memcmp(entry->path, path, length)) return entry;
    }
    return NULL;
}
/* Whether every ancestor of `path` is an existing directory: OK, FAILED for a
   missing one, DENIED for one that is a file (POSIX ENOENT and ENOTDIR). */
static MylangProviderStatus parents(MemoryFs *memory, const unsigned char *path, size_t length) {
    for (size_t i = 0; i < length; ++i) {
        if (path[i] != '/') continue;
        MemoryEntry *ancestor = find(memory, path, i);
        if (!ancestor) return MYLANG_PROVIDER_FAILED;
        if (!ancestor->directory) return MYLANG_PROVIDER_DENIED;
    }
    return MYLANG_PROVIDER_OK;
}
static MemoryEntry *create(MemoryFs *memory, const unsigned char *path, size_t length, int directory) {
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
static void entry_free(MemoryEntry *entry) {
    free(entry->path);
    free(entry->bytes);
    free(entry);
}
static void unlink_entry(MemoryFs *memory, MemoryEntry *entry) {
    for (size_t i = 0; i < memory->count; ++i) {
        if (memory->entries[i] != entry) continue;
        memory->entries[i] = memory->entries[--memory->count];
        break;
    }
    memory->bytes -= entry->size;
    if (entry->open) entry->unlinked = 1;
    else entry_free(entry);
}
static int has_children(MemoryFs *memory, const MemoryEntry *directory) {
    for (size_t i = 0; i < memory->count; ++i) {
        const MemoryEntry *entry = memory->entries[i];
        if (entry->length > directory->length && entry->path[directory->length] == '/' && !memcmp(entry->path, directory->path, directory->length)) return 1;
    }
    return 0;
}
static size_t free_handle(const MemoryFs *memory) {
    for (size_t i = 0; i < MEMORY_HANDLES; ++i) if (!memory->handles[i].live) return i;
    return SIZE_MAX;
}
/* The final component of an entry's path, which is how a listing names it. */
static const char *leaf(const MemoryEntry *entry, size_t *width) {
    const char *slash = NULL;
    for (size_t i = 0; i < entry->length; ++i) if (entry->path[i] == '/') slash = entry->path + i;
    const char *start = slash ? slash + 1 : entry->path;
    *width = entry->length - (size_t)(start - entry->path);
    return start;
}
static int in_directory(const MemoryEntry *entry, const unsigned char *path, size_t length) {
    if (!length) return !memchr(entry->path, '/', entry->length);
    if (entry->length <= length + 1 || entry->path[length] != '/' || memcmp(entry->path, path, length)) return 0;
    return !memchr(entry->path + length + 1, '/', entry->length - length - 1);
}
static int leaf_order(const void *a, const void *b) {
    size_t left_width, right_width;
    const char *left = leaf(*(MemoryEntry *const *)a, &left_width), *right = leaf(*(MemoryEntry *const *)b, &right_width);
    size_t shortest = left_width < right_width ? left_width : right_width;
    int order = shortest ? memcmp(left, right, shortest) : 0;
    if (order) return order;
    return left_width < right_width ? -1 : left_width > right_width ? 1 : 0;
}
/* The same snapshot the scoped provider publishes: a leading 1, then a kind
   byte, a little-endian u16 name length and the name per entry. Entries are
   sorted by name, so a listing never depends on insertion order. */
static unsigned char *listing(MemoryFs *memory, const unsigned char *path, size_t length, size_t *size, MylangProviderStatus *status) {
    if (length) {
        MemoryEntry *directory = find(memory, path, length);
        if (!directory) { *status = MYLANG_PROVIDER_FAILED; return NULL; }
        if (!directory->directory) { *status = MYLANG_PROVIDER_DENIED; return NULL; }
    }
    MemoryEntry **children = malloc((memory->count ? memory->count : 1) * sizeof *children);
    if (!children) { *status = MYLANG_PROVIDER_OUT_OF_MEMORY; return NULL; }
    size_t count = 0, bytes = 1;
    for (size_t i = 0; i < memory->count; ++i) {
        if (!in_directory(memory->entries[i], path, length)) continue;
        size_t width;
        (void)leaf(memory->entries[i], &width);
        children[count++] = memory->entries[i];
        bytes += width + 3;
    }
    if (count > SNAPSHOT_ENTRIES || bytes > SNAPSHOT_BYTES) { free(children); *status = MYLANG_PROVIDER_DENIED; return NULL; }
    qsort(children, count, sizeof *children, leaf_order);
    unsigned char *snapshot = malloc(bytes);
    if (!snapshot) { free(children); *status = MYLANG_PROVIDER_OUT_OF_MEMORY; return NULL; }
    size_t used = 0;
    snapshot[used++] = 1;
    for (size_t i = 0; i < count; ++i) {
        size_t width;
        const char *name = leaf(children[i], &width);
        snapshot[used++] = children[i]->directory ? 2 : 1;
        snapshot[used++] = (unsigned char)(width & 0xff);
        snapshot[used++] = (unsigned char)((width >> 8) & 0xff);
        memcpy(snapshot + used, name, width);
        used += width;
    }
    free(children);
    *status = MYLANG_PROVIDER_OK;
    *size = used;
    return snapshot;
}
/* Metadata (`m`), `mkdir` (`k`) and `remove` (`x`) as one acknowledged snapshot. */
static unsigned char *change(MemoryFs *memory, const unsigned char *path, size_t length, unsigned char mode, size_t *size, MylangProviderStatus *status) {
    MemoryEntry *entry = length ? find(memory, path, length) : NULL;
    *status = MYLANG_PROVIDER_OK;
    if (mode == 'm') {
        if (length && !entry) { *status = parents(memory, path, length) == MYLANG_PROVIDER_DENIED ? MYLANG_PROVIDER_DENIED : MYLANG_PROVIDER_FAILED; return NULL; }
        unsigned char *bytes = malloc(10);
        if (!bytes) { *status = MYLANG_PROVIDER_OUT_OF_MEMORY; return NULL; }
        bytes[0] = 1;
        bytes[1] = !entry || entry->directory ? 2 : 1;
        uint64_t width = entry ? entry->size : 0;
        for (unsigned i = 0; i < 8; ++i) bytes[2 + i] = (unsigned char)((width >> (8 * i)) & 0xff);
        *size = 10;
        return bytes;
    }
    if (!length) { *status = MYLANG_PROVIDER_DENIED; return NULL; }
    if (mode == 'k') {
        MylangProviderStatus chain = parents(memory, path, length);
        if (chain != MYLANG_PROVIDER_OK) { *status = chain; return NULL; }
        if (entry) { *status = MYLANG_PROVIDER_FAILED; return NULL; }
        if (!create(memory, path, length, 1)) { *status = MYLANG_PROVIDER_OUT_OF_MEMORY; return NULL; }
    } else {
        if (!entry) { *status = parents(memory, path, length) == MYLANG_PROVIDER_DENIED ? MYLANG_PROVIDER_DENIED : MYLANG_PROVIDER_FAILED; return NULL; }
        if (entry->directory && has_children(memory, entry)) { *status = MYLANG_PROVIDER_FAILED; return NULL; }
        unlink_entry(memory, entry);
    }
    unsigned char *bytes = malloc(1);
    if (!bytes) { *status = MYLANG_PROVIDER_OUT_OF_MEMORY; return NULL; }
    bytes[0] = 1;
    *size = 1;
    return bytes;
}
/* Open a file entry for `r`, `c` (exclusive create), `t` (truncate an existing
   file) or `a` (append, creating it), with the POSIX outcome of each. */
static MemoryEntry *open_file(MemoryFs *memory, const unsigned char *path, size_t length, unsigned char mode, MylangProviderStatus *status) {
    MylangProviderStatus chain = parents(memory, path, length);
    if (chain != MYLANG_PROVIDER_OK) { *status = chain; return NULL; }
    MemoryEntry *entry = find(memory, path, length);
    if (entry && entry->directory) { *status = MYLANG_PROVIDER_DENIED; return NULL; }
    if (mode == 'c' && entry) { *status = MYLANG_PROVIDER_FAILED; return NULL; }
    if ((mode == 'r' || mode == 't') && !entry) { *status = MYLANG_PROVIDER_FAILED; return NULL; }
    if (!entry) {
        entry = create(memory, path, length, 0);
        if (!entry) { *status = MYLANG_PROVIDER_OUT_OF_MEMORY; return NULL; }
    }
    if (mode == 't') { memory->bytes -= entry->size; entry->size = 0; }
    *status = MYLANG_PROVIDER_OK;
    return entry;
}
static MylangResourceResult memory_acquire(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    MemoryFs *memory = context;
    MylangResourceResult result = {MYLANG_PROVIDER_DENIED, 0};
    if (length < 2 || length > PATH_LIMIT + 2 || request[1] != ':') return result;
    unsigned char mode = request[0];
    int reading = mode == 'r' || mode == 'm' || mode == 'l';
    int writing = mode == 'c' || mode == 't' || mode == 'a' || mode == 'k' || mode == 'x';
    if ((!reading && !writing) || !(permissions & (reading ? 1u : 2u))) return result;
    const unsigned char *path = request + 2;
    size_t width = length - 2;
    if (!valid_path(path, width, mode)) return result;
    size_t slot = free_handle(memory);
    if (slot == SIZE_MAX) return result;
    MemoryHandle *handle = &memory->handles[slot];
    if (mode == 'm' || mode == 'l' || mode == 'k' || mode == 'x') {
        size_t size = 0;
        unsigned char *snapshot = mode == 'l' ? listing(memory, path, width, &size, &result.status) : change(memory, path, width, mode, &size, &result.status);
        if (!snapshot) return result;
        *handle = (MemoryHandle){1, NULL, snapshot, size, 0, mode};
        result.handle = slot;
        return result;
    }
    MemoryEntry *entry = open_file(memory, path, width, mode, &result.status);
    if (!entry) return result;
    entry->open++;
    *handle = (MemoryHandle){1, entry, NULL, 0, 0, mode};
    result.handle = slot;
    return result;
}
static MemoryHandle *live(MemoryFs *memory, uint64_t id) {
    if (id >= MEMORY_HANDLES || !memory->handles[id].live) return NULL;
    return &memory->handles[id];
}
static void shut(MemoryHandle *handle) {
    if (handle->entry) {
        handle->entry->open--;
        if (handle->entry->unlinked && !handle->entry->open) entry_free(handle->entry);
    }
    free(handle->snapshot);
    *handle = (MemoryHandle){0, NULL, NULL, 0, 0, 0};
}
static MylangProviderStatus memory_complete(void *context, uint64_t id) {
    MemoryHandle *handle = live(context, id);
    if (!handle) return MYLANG_PROVIDER_FAILED;
    shut(handle);
    return MYLANG_PROVIDER_OK;
}
static void memory_release(void *context, uint64_t id) {
    MemoryHandle *handle = live(context, id);
    if (handle) shut(handle);
}
static MylangResourceRead memory_read(void *context, uint64_t id, uint8_t *output, size_t capacity) {
    MylangResourceRead result = {MYLANG_PROVIDER_FAILED, 0, 0};
    MemoryHandle *handle = live(context, id);
    if (!handle) return result;
    if (!capacity) { result.status = MYLANG_PROVIDER_OK; return result; }
    const unsigned char *bytes = handle->snapshot;
    size_t total = handle->length;
    if (handle->entry) {
        if (handle->mode != 'r') { result.status = handle->mode == 'a' ? MYLANG_PROVIDER_DENIED : MYLANG_PROVIDER_FAILED; return result; }
        bytes = handle->entry->bytes;
        total = handle->entry->size;
    }
    size_t available = handle->position < total ? total - handle->position : 0;
    size_t width = available < capacity ? available : capacity;
    if (width) memcpy(output, bytes + handle->position, width);
    handle->position += width;
    result.status = MYLANG_PROVIDER_OK;
    result.length = width;
    result.eof = handle->position >= total;
    return result;
}
static MylangResourceWrite memory_write(void *context, uint64_t id, const uint8_t *input, size_t length) {
    MemoryFs *memory = context;
    MylangResourceWrite result = {MYLANG_PROVIDER_FAILED, 0};
    MemoryHandle *handle = live(memory, id);
    if (!handle || !handle->entry) { result.status = handle ? MYLANG_PROVIDER_DENIED : MYLANG_PROVIDER_FAILED; return result; }
    if (handle->mode == 'r') return result;
    MemoryEntry *entry = handle->entry;
    size_t at = handle->mode == 'a' ? entry->size : handle->position;
    if (at > entry->size || length > MEMORY_BYTES - memory->bytes || at + length > MEMORY_BYTES) return result;
    size_t end = at + length;
    if (end > entry->capacity) {
        size_t grown = entry->capacity ? entry->capacity : 64;
        while (grown < end) grown *= 2;
        unsigned char *bytes = realloc(entry->bytes, grown);
        if (!bytes) { result.status = MYLANG_PROVIDER_OUT_OF_MEMORY; return result; }
        entry->bytes = bytes;
        entry->capacity = grown;
    }
    if (length) memcpy(entry->bytes + at, input, length);
    if (end > entry->size) {
        if (!entry->unlinked) memory->bytes += end - entry->size;
        entry->size = end;
    }
    handle->position = end;
    result.status = MYLANG_PROVIDER_OK;
    result.length = length;
    return result;
}
static void memory_free(MemoryFs *memory) {
    for (size_t i = 0; i < MEMORY_HANDLES; ++i) if (memory->handles[i].live) shut(&memory->handles[i]);
    for (size_t i = 0; i < memory->count; ++i) entry_free(memory->entries[i]);
    free(memory->entries);
    free(memory);
}
/* A stand-in `Network` has no endpoint to reach; qbe_resources.c answers every
   acquisition with MYL_QBE_STAND_IN_DENIED before this would run. */
static MylangResourceResult network_acquire(void *context, const uint8_t *request, size_t length, unsigned permissions) {
    (void)context; (void)request; (void)length; (void)permissions;
    MylangResourceResult result = {MYLANG_PROVIDER_DENIED, 0};
    return result;
}
static MylangProviderStatus network_complete(void *context, uint64_t id) { (void)context; (void)id; return MYLANG_PROVIDER_FAILED; }
static void network_release(void *context, uint64_t id) { (void)context; (void)id; }

/* ---- environment ---------------------------------------------------------- */

/* Walk one NUL-terminated field of a blob; returns its length or SIZE_MAX. */
static size_t field(const unsigned char *blob, size_t length, size_t cursor) {
    const unsigned char *end = memchr(blob + cursor, 0, length - cursor);
    return end ? (size_t)(end - blob) - cursor : SIZE_MAX;
}
static int valid_name(const unsigned char *name, size_t width) {
    return width && width <= NAME_LIMIT && !memchr(name, '=', width) && myl_native_text_valid_utf8(name, width);
}
/* Validate `NAME\0VALUE\0...`: bounded, unique, nonempty names without `=`. */
static int valid_pairs(const unsigned char *blob, size_t length) {
    size_t cursor = 0, count = 0;
    while (cursor < length) {
        size_t name = field(blob, length, cursor);
        if (name == SIZE_MAX || !valid_name(blob + cursor, name)) return 0;
        size_t value_at = cursor + name + 1;
        size_t value = value_at < length ? field(blob, length, value_at) : SIZE_MAX;
        if (value == SIZE_MAX || value > VALUE_LIMIT || ++count > NAMES_LIMIT) return 0;
        for (size_t other = 0; other < cursor;) {
            size_t width = field(blob, length, other);
            if (width == name && !memcmp(blob + other, blob + cursor, name)) return 0;
            other += width + 1;
            other += field(blob, length, other) + 1;
        }
        cursor = value_at + value + 1;
    }
    return 1;
}
static int blob_has(const unsigned char *blob, size_t length, const unsigned char *key, size_t width) {
    for (size_t cursor = 0; cursor < length;) {
        size_t name = field(blob, length, cursor);
        if (name == width && !memcmp(blob + cursor, key, width)) return 1;
        cursor += name + 1;
    }
    return 0;
}

/* ---- public entry points --------------------------------------------------- */

uint64_t myl_qbe_stand_in(void *context, uint64_t kind, uint64_t operand) {
    MylQbeContext *ctx = context;
    if (kind > 4) { myl_qbe_fail(ctx, "InvalidCapability"); return 0; }
    unsigned char *pairs = NULL;
    size_t pairs_length = 0;
    if (kind == 4 && operand) {
        const myl_native_text *text = (const myl_native_text *)(uintptr_t)operand;
        pairs_length = myl_native_text_utf8(text, NULL, 0);
        if (pairs_length == SIZE_MAX) { myl_qbe_fail_allocation(ctx); return 0; }
        pairs = malloc(pairs_length ? pairs_length : 1);
        if (!pairs) { myl_qbe_fail_allocation(ctx); return 0; }
        myl_native_text_utf8(text, pairs, pairs_length);
        if (!valid_pairs(pairs, pairs_length)) { free(pairs); myl_qbe_fail(ctx, "R_ENVIRONMENT"); return 0; }
    }
    MemoryFs *memory = NULL;
    if (kind == 2) {
        memory = calloc(1, sizeof *memory);
        if (!memory) { free(pairs); myl_qbe_fail_allocation(ctx); return 0; }
    }
    size_t index = 0;
    StandIn *entry = append(ctx, (unsigned)kind, &index);
    if (!entry) { free(pairs); free(memory); return 0; }
    entry->value = (int64_t)operand;
    entry->pairs = pairs;
    entry->pairs_length = pairs_length;
    if (kind == 2) {
        entry->memory = memory;
        entry->provider = (MylangResourceProvider){memory, 7u, memory_acquire, memory_complete, memory_release, memory_read, memory_write};
    }
    if (kind == 3) entry->provider = (MylangResourceProvider){entry, 7u, network_acquire, network_complete, network_release, NULL, NULL};
    if (kind == 2 || kind == 3) return resource_word(index, kind - 2);
    return MYL_QBE_STAND_IN_BASE + index;
}
uint64_t myl_qbe_clock_advance(void *context, uint64_t authority, uint64_t nanoseconds) {
    if (authority == UINT64_MAX) return 1;
    StandIn *entry = word_lookup(context, authority, 0);
    if (!entry) { myl_qbe_fail_capability(context); return 0; }
    int64_t delta;
    memcpy(&delta, &nanoseconds, sizeof delta);
    if ((delta > 0 && entry->value > INT64_MAX - delta) || (delta < 0 && entry->value < INT64_MIN - delta)) return 2;
    entry->value += delta;
    return 0;
}
int myl_qbe_stand_in_read(void *context, uint64_t authority, unsigned kind, uint64_t *output) {
    StandIn *entry = word_lookup(context, authority, kind);
    if (!entry || kind > 1) { myl_qbe_fail_capability(context); return -1; }
    if (kind == 0) { memcpy(output, &entry->value, 8); return 0; }
    /* The SplitMix64 step the host-granted `--allow-random=SEED` stream uses. */
    uint64_t state = (uint64_t)entry->value + UINT64_C(0x9e3779b97f4a7c15);
    entry->value = (int64_t)state;
    uint64_t value = (state ^ (state >> 30)) * UINT64_C(0xbf58476d1ce4e5b9);
    value = (value ^ (value >> 27)) * UINT64_C(0x94d049bb133111eb);
    *output = value ^ (value >> 31);
    return 0;
}
int myl_qbe_stand_in_environment(void *context, uint64_t authority, const unsigned char *key, size_t length, const unsigned char **value, size_t *value_length) {
    StandIn *entry = word_lookup(context, authority, 4);
    if (!entry || (entry->scope && !blob_has(entry->scope, entry->scope_length, key, length))) { myl_qbe_fail_capability(context); return -1; }
    for (size_t cursor = 0; cursor < entry->pairs_length;) {
        size_t name = field(entry->pairs, entry->pairs_length, cursor);
        size_t value_at = cursor + name + 1;
        size_t width = field(entry->pairs, entry->pairs_length, value_at);
        if (name == length && !memcmp(entry->pairs + cursor, key, length)) {
            *value = entry->pairs + value_at;
            *value_length = width;
            return 1;
        }
        cursor = value_at + width + 1;
    }
    return 0;
}
uint64_t myl_qbe_stand_in_environment_only(void *context, uint64_t authority, const unsigned char *names, size_t length) {
    MylQbeContext *ctx = context;
    StandIn *entry = word_lookup(context, authority, 4);
    if (!entry || entry->scope) { myl_qbe_fail_capability(context); return 0; }
    if (!length || names[length - 1] != 0) { myl_qbe_fail(context, "InvalidCapability"); return 0; }
    unsigned char *scope = malloc(length), *pairs = malloc(entry->pairs_length ? entry->pairs_length : 1);
    if (!scope || !pairs) { free(scope); free(pairs); myl_qbe_fail_allocation(ctx); return 0; }
    memcpy(scope, names, length);
    if (entry->pairs_length) memcpy(pairs, entry->pairs, entry->pairs_length);
    size_t pairs_length = entry->pairs_length, index = 0;
    StandIn *narrowed = append(ctx, 4, &index);
    if (!narrowed) { free(scope); free(pairs); return 0; }
    narrowed->pairs = pairs;
    narrowed->pairs_length = pairs_length;
    narrowed->scope = scope;
    narrowed->scope_length = length;
    return MYL_QBE_STAND_IN_BASE + index;
}
/* One visible name borrowed from a stand-in's pairs or scope. */
typedef struct { const unsigned char *bytes; size_t length; } Name;
static int blob_has_name(const Name *names, size_t count, const unsigned char *bytes, size_t length) {
    for (size_t i = 0; i < count; ++i) if (names[i].length == length && !memcmp(names[i].bytes, bytes, length)) return 1;
    return 0;
}
static int name_order(const void *a, const void *b) {
    const Name *left = a, *right = b;
    size_t shortest = left->length < right->length ? left->length : right->length;
    int order = shortest ? memcmp(left->bytes, right->bytes, shortest) : 0;
    if (order) return order;
    return left->length < right->length ? -1 : left->length > right->length ? 1 : 0;
}
void *myl_qbe_stand_in_environment_names(void *context, uint64_t authority) {
    StandIn *entry = word_lookup(context, authority, 4);
    if (!entry) { myl_qbe_fail_capability(context); return NULL; }
    Name names[NAMES_LIMIT];
    size_t count = 0;
    const unsigned char *blob = entry->scope ? entry->scope : entry->pairs;
    size_t length = entry->scope ? entry->scope_length : entry->pairs_length;
    for (size_t cursor = 0; cursor < length && count < NAMES_LIMIT;) {
        size_t width = field(blob, length, cursor);
        if (width && !blob_has_name(names, count, blob + cursor, width)) names[count++] = (Name){blob + cursor, width};
        cursor += width + 1;
        if (!entry->scope) cursor += field(blob, length, cursor) + 1;
    }
    qsort(names, count, sizeof *names, name_order);
    static const myl_native_type pointer_type = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER};
    myl_native_heap *heap = myl_qbe_heap(context);
    myl_native_list *list = myl_native_list_new(heap, &pointer_type, count);
    if (!list) { myl_qbe_fail_allocation(context); return NULL; }
    myl_native_root root;
    myl_native_root_push(heap, &root, &list, &pointer_type);
    int failed = 0;
    for (size_t i = 0; i < count; ++i) {
        myl_native_text *text = myl_native_text_from_utf8(heap, names[i].bytes, names[i].length);
        int appended = text && myl_native_list_append(heap, list, &text);
        if (myl_rc_enabled(heap)) {
            if (appended) myl_rc_owner_release(heap, text);
            else myl_rc_construction_abort(heap, text);
        }
        if (!appended) { failed = 1; break; }
    }
    myl_native_root_pop(heap, &root);
    if (failed) {
        if (myl_rc_enabled(heap)) myl_rc_construction_abort(heap, list);
        myl_qbe_fail_allocation(context);
        return NULL;
    }
    return list;
}
const void *myl_qbe_stand_in_provider(void *context, uint64_t index, unsigned kind) {
    StandIn *entry = lookup(context, index, kind + 2);
    return entry ? &entry->provider : NULL;
}
