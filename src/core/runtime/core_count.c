/* ---- counting builds (NEW-CORE-COUNTERS-1..7) -------------------------------
 * Appended to the runtime only in a counting build (`selka build --counters`);
 * core_count.h declares the hooks the patched runtime calls. The emitter puts
 * one record per emitted function in section `myl_count_fns` and one record per
 * counted site in `myl_count_sites` (`emit_count.zig`); the linker's
 * `__start_`/`__stop_` symbols bound both arrays. Each function's prologue makes
 * its record `myl_count_current`, so the runtime charges what it does to the
 * emitted function that called it; events with no current function (the C entry,
 * exit) go to `<outside>`. At exit, or when a trap ends the process, the counts
 * are written as one JSON document (`selka-counters-v1`) to the path in
 * `SELKA_COUNTERS`, else to `selka-counters.json` in the working directory.
 * Nothing is printed on the program's own streams unless the file cannot be
 * written. Thread-local slots are combined after task quiescence. */

typedef struct myl_count_fn {
    const char *name;
    uint64_t c[SELKA_COUNT_SLOTS];
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
SELKA_TLS myl_count_fn *myl_count_current;
/* The site of the Core copy instruction whose runtime call comes next, or null. */
SELKA_TLS myl_count_site *myl_count_copy_site;
/* The list push whose reserve call is running, or null: a growth credits its moved bytes there. */
SELKA_TLS myl_count_site *myl_count_push_site;

static myl_count_fn myl_count_outside = { "<outside>", { 0 } };
static _Atomic uint64_t myl_count_live, myl_count_peak;
static bool myl_count_written;

/* Linker records are immutable identities; each native thread owns copies of
   their slots. Records survive thread retirement for the one quiescent dump. */
typedef struct myl_count_thread {
    myl_count_fn *functions;
    myl_count_site *sites;
    myl_count_fn outside;
    struct myl_count_thread *next;
} myl_count_thread;
static pthread_mutex_t myl_count_mutex = PTHREAD_MUTEX_INITIALIZER;
static myl_count_thread *myl_count_threads;
static SELKA_TLS myl_count_thread *myl_count_local;

static size_t myl_count_functions_size(void) {
    return __start_myl_count_fns ? (size_t)(__stop_myl_count_fns - __start_myl_count_fns) : 0;
}
static size_t myl_count_sites_size(void) {
    return __start_myl_count_sites ? (size_t)(__stop_myl_count_sites - __start_myl_count_sites) : 0;
}
static myl_count_thread *myl_count_thread_get(void) {
    if (myl_count_local) return myl_count_local;
    myl_count_thread *local = calloc(1, sizeof *local);
    if (!local) out_of_memory();
    size_t functions = myl_count_functions_size(), sites = myl_count_sites_size();
    local->functions = calloc(functions ? functions : 1, sizeof *local->functions);
    local->sites = calloc(sites ? sites : 1, sizeof *local->sites);
    if (!local->functions || !local->sites) out_of_memory();
    if (functions) memcpy(local->functions, __start_myl_count_fns, functions * sizeof *local->functions);
    if (sites) memcpy(local->sites, __start_myl_count_sites, sites * sizeof *local->sites);
    local->outside.name = "<outside>";
    pthread_mutex_lock(&myl_count_mutex);
    local->next = myl_count_threads;
    myl_count_threads = local;
    pthread_mutex_unlock(&myl_count_mutex);
    myl_count_local = local;
    return local;
}

myl_count_fn *myl_count_function_local(const myl_count_fn *identity) {
    return &myl_count_thread_get()->functions[identity - __start_myl_count_fns];
}
myl_count_site *myl_count_site_local(const myl_count_site *identity) {
    return &myl_count_thread_get()->sites[identity - __start_myl_count_sites];
}

static void myl_count_add_live(size_t bytes) {
    uint64_t live = atomic_fetch_add_explicit(&myl_count_live, bytes, memory_order_relaxed) + bytes;
    uint64_t peak = atomic_load_explicit(&myl_count_peak, memory_order_relaxed);
    while (peak < live && !atomic_compare_exchange_weak_explicit(&myl_count_peak, &peak, live,
            memory_order_relaxed, memory_order_relaxed)) {}
}
static void myl_count_sub_live(size_t bytes) {
    uint64_t live = atomic_load_explicit(&myl_count_live, memory_order_relaxed);
    while (!atomic_compare_exchange_weak_explicit(&myl_count_live, &live, live - (bytes < live ? bytes : live),
            memory_order_relaxed, memory_order_relaxed)) {}
}

/* Site kinds, in `emit_count.Kind` order. */
static const char *const myl_count_kinds[] = {
    "retain", "release", "release_unique", "unique_test", "list_copy", "dict_copy",
    "buffer_copy", "text_copy", "record_copy", "list_push", "element_load", "element_store",
    "bounds_check", "overflow_check", "division_check", "shift_check", "other_check",
};
enum { SELKA_COUNT_KINDS = sizeof myl_count_kinds / sizeof myl_count_kinds[0] };

/* Function slot names (core_count.h), one per used slot; null marks an unused one. */
static const char *const myl_count_slot_names[SELKA_COUNT_SLOTS] = {
    "calls", NULL, "allocs", "alloc_bytes", "frees", "free_bytes",
    "list_grows", "list_grow_bytes", "reallocs", "realloc_added_bytes", "realloc_moves", "realloc_moved_bytes",
    "list_copies", "list_copy_bytes", "dict_copies", "dict_copy_bytes", "buffer_copies", "buffer_copy_bytes",
    "text_copies", "text_copy_bytes", "runtime_retains", NULL, "runtime_releases", NULL,
    "dict_grows", "dict_grow_bytes", "buffer_grows", "buffer_grow_bytes", "text_grows", "text_grow_bytes",
    "text_appends", "text_append_bytes", "buffer_pushes", NULL, "buffer_appends", "buffer_append_bytes",
    "shared_retains", NULL, "shared_releases", NULL, "share_marks", "share_bytes",
};

static myl_count_fn *myl_count_function(void) {
    return myl_count_current ? myl_count_current : &myl_count_thread_get()->outside;
}

static void myl_count_event(int slot, size_t bytes) {
    myl_count_fn *fn = myl_count_function();
    fn->c[slot] += 1;
    fn->c[slot + 1] += bytes;
}

static void myl_count_copy(int slot, size_t bytes) {
    myl_count_event(slot, bytes);
    myl_count_site *site = myl_count_copy_site ? myl_count_site_local(myl_count_copy_site) : NULL;
    myl_count_copy_site = NULL;
    if (!site) return;
    site->c[0] += 1;
    site->c[1] += bytes;
}

static void myl_count_list_grow(size_t bytes) {
    myl_count_event(SELKA_COUNT_LIST_GROWS, bytes);
    if (myl_count_push_site) myl_count_site_local(myl_count_push_site)->c[2] += bytes;
}

static void myl_count_alloc(size_t bytes) {
    myl_count_event(SELKA_COUNT_ALLOCS, bytes);
    myl_count_add_live(bytes);
}

static void myl_count_free(size_t bytes) {
    myl_count_event(SELKA_COUNT_FREES, bytes);
    myl_count_sub_live(bytes);
}

static void myl_count_realloc(size_t before, size_t after, int moved, size_t used) {
    myl_count_event(SELKA_COUNT_REALLOCS, after > before ? after - before : 0);
    if (moved) myl_count_event(SELKA_COUNT_REALLOC_MOVES, used);
    if (moved && myl_count_push_site) myl_count_site_local(myl_count_push_site)->c[2] += used;
    if (after >= before) myl_count_add_live(after - before);
    else myl_count_sub_live(before - after);
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
    for (int i = 0; i < SELKA_COUNT_SLOTS; ++i) if (fn->c[i]) return true;
    return false;
}

static void myl_count_slots(FILE *file, const uint64_t *c) {
    bool first = true;
    for (int i = 0; i < SELKA_COUNT_SLOTS; ++i) {
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

/* No thread mutates a slot after the scheduler's quiescence barrier. Copy the
   immutable metadata, then sum the private slots into report-owned storage. */
static bool myl_count_aggregate(myl_count_fn **functions, myl_count_site **sites) {
    size_t nf = myl_count_functions_size(), ns = myl_count_sites_size();
    *functions = calloc(nf ? nf : 1, sizeof **functions);
    *sites = calloc(ns ? ns : 1, sizeof **sites);
    if (!*functions || !*sites) { free(*functions); free(*sites); return false; }
    if (nf) memcpy(*functions, __start_myl_count_fns, nf * sizeof **functions);
    if (ns) memcpy(*sites, __start_myl_count_sites, ns * sizeof **sites);
    pthread_mutex_lock(&myl_count_mutex);
    for (myl_count_thread *thread = myl_count_threads; thread; thread = thread->next) {
        for (size_t f = 0; f < nf; ++f)
            for (int c = 0; c < SELKA_COUNT_SLOTS; ++c) (*functions)[f].c[c] += thread->functions[f].c[c];
        for (size_t site = 0; site < ns; ++site)
            for (int c = 0; c < 4; ++c) (*sites)[site].c[c] += thread->sites[site].c[c];
        for (int c = 0; c < SELKA_COUNT_SLOTS; ++c) myl_count_outside.c[c] += thread->outside.c[c];
    }
    pthread_mutex_unlock(&myl_count_mutex);
    return true;
}

/* Write every counter once: at `myl_core_exit`, or from `os_exit` when a trap ends the process. */
static void myl_count_dump(void) {
    if (myl_count_written) return;
    myl_count_written = true;
    const char *path = getenv("SELKA_COUNTERS");
    if (!path || !*path) path = "selka-counters.json";
    FILE *file = fopen(path, "w");
    if (!file) {
        fprintf(stderr, "selka-counters: cannot write %s\n", path);
        return;
    }
    uint64_t totals[SELKA_COUNT_SLOTS] = { 0 };
    uint64_t kinds[SELKA_COUNT_KINDS][3] = { { 0 } };
    myl_count_fn *fns;
    myl_count_site *sites;
    if (!myl_count_aggregate(&fns, &sites)) { fclose(file); return; }
    const myl_count_fn *fns_end = fns + myl_count_functions_size();
    const myl_count_site *sites_end = sites + myl_count_sites_size();
    for (const myl_count_fn *fn = fns; fn && fn < fns_end; ++fn)
        for (int i = 0; i < SELKA_COUNT_SLOTS; ++i) totals[i] += fn->c[i];
    for (int i = 0; i < SELKA_COUNT_SLOTS; ++i) totals[i] += myl_count_outside.c[i];
    for (const myl_count_site *site = sites; site && site < sites_end; ++site) {
        if (site->kind < 0 || site->kind >= SELKA_COUNT_KINDS) continue;
        for (int i = 0; i < 3; ++i) kinds[site->kind][i] += site->c[i];
    }
    fputs("{\"version\":\"selka-counters-v1\",\"totals\":{", file);
    myl_count_slots(file, totals);
    fprintf(file, ",\"peak_live_bytes\":%llu,\"live_bytes_at_exit\":%llu}", (unsigned long long)myl_count_peak, (unsigned long long)myl_count_live);
    fputs(",\"kinds\":{", file);
    for (int k = 0; k < SELKA_COUNT_KINDS; ++k) {
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
        if (!site->c[0] || site->kind < 0 || site->kind >= SELKA_COUNT_KINDS) continue;
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
    free(fns);
    free(sites);
    if (fclose(file) != 0) fprintf(stderr, "selka-counters: cannot write %s\n", path);
}
