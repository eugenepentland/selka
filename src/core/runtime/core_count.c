/* ---- counting builds (NEW-CORE-COUNTERS-1..5) -------------------------------
 * Appended to the runtime only in a counting build (`mylang build --counters`);
 * core_count.h declares the hooks the patched runtime calls. The emitter puts
 * one record per emitted function in section `myl_count_fns` and one record per
 * counted site in `myl_count_sites` (`emit_count.zig`); the linker's
 * `__start_`/`__stop_` symbols bound both arrays. Each function's prologue makes
 * its record `myl_count_current`, so the runtime charges what it does to the
 * emitted function that called it; events with no current function (the C entry,
 * exit) go to `<outside>`. At exit, or when a trap ends the process, the counts
 * are written as one JSON document (`mylang-counters-v1`) to the path in
 * `MYLANG_COUNTERS`, else to `mylang-counters.json` in the working directory.
 * Nothing is printed on the program's own streams unless the file cannot be
 * written. Single-threaded, like the counts themselves. */

typedef struct myl_count_fn {
    const char *name;
    uint64_t c[MYL_COUNT_SLOTS];
} myl_count_fn;

/* Matches `emit_count.site_type`: 80 bytes, the counters at offsets 48, 56, 64, 72. */
typedef struct myl_count_site {
    myl_count_fn *function;
    const char *origin;
    const char *path;
    const char *detail;
    int32_t line, column, kind, pad;
    uint64_t c[4];
} myl_count_site;

_Static_assert(sizeof(myl_count_site) == 80, "counter site layout");
_Static_assert(offsetof(myl_count_site, c) == 48, "counter site counters");
_Static_assert(offsetof(myl_count_fn, c) == 8, "counter function slots");

extern myl_count_fn __start_myl_count_fns[] __attribute__((weak, visibility("hidden")));
extern myl_count_fn __stop_myl_count_fns[] __attribute__((weak, visibility("hidden")));
extern myl_count_site __start_myl_count_sites[] __attribute__((weak, visibility("hidden")));
extern myl_count_site __stop_myl_count_sites[] __attribute__((weak, visibility("hidden")));

/* The emitted function running now; set by each prologue, restored before each return. */
myl_count_fn *myl_count_current;
/* The site of the Core copy instruction whose runtime call comes next, or null. */
myl_count_site *myl_count_copy_site;
/* The list push whose reserve call is running, or null: a growth credits its moved bytes there. */
myl_count_site *myl_count_push_site;

static myl_count_fn myl_count_outside = { "<outside>", { 0 } };
static uint64_t myl_count_live, myl_count_peak;
static bool myl_count_written;

/* Site kinds, in `emit_count.Kind` order. */
static const char *const myl_count_kinds[] = {
    "retain", "release", "release_unique", "unique_test", "list_copy", "dict_copy",
    "buffer_copy", "text_copy", "record_copy", "list_push", "element_load", "element_store",
};
enum { MYL_COUNT_KINDS = sizeof myl_count_kinds / sizeof myl_count_kinds[0] };

/* Function slot names (core_count.h), one per used slot; null marks an unused one. */
static const char *const myl_count_slot_names[MYL_COUNT_SLOTS] = {
    "calls", NULL, "allocs", "alloc_bytes", "frees", "free_bytes",
    "list_grows", "list_grow_bytes", "reallocs", "realloc_added_bytes", "realloc_moves", "realloc_moved_bytes",
    "list_copies", "list_copy_bytes", "dict_copies", "dict_copy_bytes", "buffer_copies", "buffer_copy_bytes",
    "text_copies", "text_copy_bytes", "runtime_retains", NULL, "runtime_releases", NULL,
    "dict_grows", "dict_grow_bytes", "buffer_grows", "buffer_grow_bytes", "text_grows", "text_grow_bytes",
    "text_appends", "text_append_bytes", "buffer_pushes", NULL, "buffer_appends", "buffer_append_bytes",
};

static myl_count_fn *myl_count_function(void) {
    return myl_count_current ? myl_count_current : &myl_count_outside;
}

static void myl_count_event(int slot, size_t bytes) {
    myl_count_fn *fn = myl_count_function();
    fn->c[slot] += 1;
    fn->c[slot + 1] += bytes;
}

static void myl_count_copy(int slot, size_t bytes) {
    myl_count_event(slot, bytes);
    myl_count_site *site = myl_count_copy_site;
    myl_count_copy_site = NULL;
    if (!site) return;
    site->c[0] += 1;
    site->c[1] += bytes;
}

static void myl_count_list_grow(size_t bytes) {
    myl_count_event(MYL_COUNT_LIST_GROWS, bytes);
    if (myl_count_push_site) myl_count_push_site->c[2] += bytes;
}

static void myl_count_alloc(size_t bytes) {
    myl_count_event(MYL_COUNT_ALLOCS, bytes);
    myl_count_live += bytes;
    if (myl_count_live > myl_count_peak) myl_count_peak = myl_count_live;
}

static void myl_count_free(size_t bytes) {
    myl_count_event(MYL_COUNT_FREES, bytes);
    myl_count_live -= bytes < myl_count_live ? bytes : myl_count_live;
}

static void myl_count_realloc(size_t before, size_t after, int moved, size_t used) {
    myl_count_event(MYL_COUNT_REALLOCS, after > before ? after - before : 0);
    if (moved) myl_count_event(MYL_COUNT_REALLOC_MOVES, used);
    if (moved && myl_count_push_site) myl_count_push_site->c[2] += used;
    myl_count_live += after;
    myl_count_live -= before < myl_count_live ? before : myl_count_live;
    if (myl_count_live > myl_count_peak) myl_count_peak = myl_count_live;
}

static void myl_count_string(FILE *file, const char *text) {
    fputc('"', file);
    for (const unsigned char *at = (const unsigned char *)(text ? text : ""); *at; ++at) {
        if (*at == '"' || *at == '\\') fprintf(file, "\\%c", *at);
        else if (*at < 0x20) fprintf(file, "\\u%04x", *at);
        else fputc(*at, file);
    }
    fputc('"', file);
}

static bool myl_count_used(const myl_count_fn *fn) {
    for (int i = 0; i < MYL_COUNT_SLOTS; ++i) if (fn->c[i]) return true;
    return false;
}

static void myl_count_slots(FILE *file, const uint64_t *c) {
    bool first = true;
    for (int i = 0; i < MYL_COUNT_SLOTS; ++i) {
        if (!myl_count_slot_names[i]) continue;
        fprintf(file, "%s\"%s\":%llu", first ? "" : ",", myl_count_slot_names[i], (unsigned long long)c[i]);
        first = false;
    }
}

static void myl_count_function_row(FILE *file, const myl_count_fn *fn, bool *first) {
    if (!myl_count_used(fn)) return;
    fputs(*first ? "\n  {\"name\":" : ",\n  {\"name\":", file);
    *first = false;
    myl_count_string(file, fn->name);
    fputc(',', file);
    myl_count_slots(file, fn->c);
    fputc('}', file);
}

/* Write every counter once: at `myl_core_exit`, or from `os_exit` when a trap ends the process. */
static void myl_count_dump(void) {
    if (myl_count_written) return;
    myl_count_written = true;
    const char *path = getenv("MYLANG_COUNTERS");
    if (!path || !*path) path = "mylang-counters.json";
    FILE *file = fopen(path, "w");
    if (!file) {
        fprintf(stderr, "mylang-counters: cannot write %s\n", path);
        return;
    }
    uint64_t totals[MYL_COUNT_SLOTS] = { 0 };
    uint64_t kinds[MYL_COUNT_KINDS][3] = { { 0 } };
    const myl_count_fn *fns = __start_myl_count_fns, *fns_end = __stop_myl_count_fns;
    const myl_count_site *sites = __start_myl_count_sites, *sites_end = __stop_myl_count_sites;
    for (const myl_count_fn *fn = fns; fn && fn < fns_end; ++fn)
        for (int i = 0; i < MYL_COUNT_SLOTS; ++i) totals[i] += fn->c[i];
    for (int i = 0; i < MYL_COUNT_SLOTS; ++i) totals[i] += myl_count_outside.c[i];
    for (const myl_count_site *site = sites; site && site < sites_end; ++site) {
        if (site->kind < 0 || site->kind >= MYL_COUNT_KINDS) continue;
        for (int i = 0; i < 3; ++i) kinds[site->kind][i] += site->c[i];
    }
    fputs("{\"version\":\"mylang-counters-v1\",\"totals\":{", file);
    myl_count_slots(file, totals);
    fprintf(file, ",\"peak_live_bytes\":%llu,\"live_bytes_at_exit\":%llu}", (unsigned long long)myl_count_peak, (unsigned long long)myl_count_live);
    fputs(",\"kinds\":{", file);
    for (int k = 0; k < MYL_COUNT_KINDS; ++k) {
        fprintf(file, "%s\"%s\":{\"count\":%llu,\"bytes\":%llu,\"extra\":%llu}", k ? "," : "", myl_count_kinds[k],
                (unsigned long long)kinds[k][0], (unsigned long long)kinds[k][1], (unsigned long long)kinds[k][2]);
    }
    fputs("},\n\"functions\":[", file);
    bool first = true;
    myl_count_function_row(file, &myl_count_outside, &first);
    for (const myl_count_fn *fn = fns; fn && fn < fns_end; ++fn) myl_count_function_row(file, fn, &first);
    fputs("],\n\"sites\":[", file);
    first = true;
    for (const myl_count_site *site = sites; site && site < sites_end; ++site) {
        if (!site->c[0] || site->kind < 0 || site->kind >= MYL_COUNT_KINDS) continue;
        fputs(first ? "\n  {\"function\":" : ",\n  {\"function\":", file);
        first = false;
        myl_count_string(file, site->function ? site->function->name : NULL);
        fputs(",\"origin\":", file);
        myl_count_string(file, site->origin);
        fputs(",\"path\":", file);
        myl_count_string(file, site->path);
        fprintf(file, ",\"line\":%d,\"column\":%d,\"kind\":\"%s\",\"detail\":", site->line, site->column, myl_count_kinds[site->kind]);
        myl_count_string(file, site->detail);
        fprintf(file, ",\"count\":%llu,\"bytes\":%llu,\"extra\":%llu}", (unsigned long long)site->c[0], (unsigned long long)site->c[1], (unsigned long long)site->c[2]);
    }
    fputs("]}\n", file);
    if (fclose(file) != 0) fprintf(stderr, "mylang-counters: cannot write %s\n", path);
}
