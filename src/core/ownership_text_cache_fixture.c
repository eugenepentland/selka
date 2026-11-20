/* OWNERSHIP-TEXT-READONLY-1 (restated for P1F-6): after pool startup a published text's data bytes, kind and
   length are never written; its facts are written only atomically, into self-validated words; a static-storage
   text is never written; a text hashed before startup keeps its hash word unwritten. Each text here keeps its
   data page read-only while its header page stays writable, so a write to data faults the fixture. */
#include "core_rt_all.c"
#undef NDEBUG
#include <assert.h>

myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
static myl_block *texts[4];
static void *regions[4];
static uint32_t expected_hash;
static size_t page_size;

static uint64_t expected_offset(uint64_t scalar) {
    return scalar / 2 * 5 + scalar % 2 * 2;
}

static void check_text(const myl_block *text) {
    assert(myl_core_str_hash(text) == expected_hash);
    assert(myl_core_str_chars(text) == 512);
    for (uint64_t scalar = 0; scalar <= 512; ++scalar)
        assert(myl_core_str_offset(text, scalar) == expected_offset(scalar));
    for (uint64_t scalar = 512; scalar; --scalar)
        assert(myl_core_str_offset(text, scalar - 1) == expected_offset(scalar - 1));
}

/* One text: its header sits at the end of a writable page and its data fills the next page, which is made
   read-only once published. Returns the header; `region` gets the mapping for the cleanup. */
static myl_block *readonly_text(bool spare, bool warm, void **region) {
    unsigned char *base = mmap(NULL, 2 * page_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(base != MAP_FAILED);
    myl_block *text = (myl_block *)(base + page_size - MYL_HEADER);
    text->kind = MYL_KIND_STR;
    text->len = 1280;
    text->cap = text->len + (spare ? 16 : 0);
    for (size_t index = 0; index < 256; ++index)
        memcpy(block_data(text) + index * 5, "\xcf\x80\xe4\xb8\xad", 5);
    block_data(text)[text->len] = 0;
    expected_hash = myl_core_span_hash(block_data(text), (uint64_t)text->len);
    if (warm) check_text(text);
    assert(!mprotect(base + page_size, page_size, PROT_READ));
    *region = base;
    return text;
}

/* A static-storage text on a fully read-only page: never written, read by every worker. */
static myl_block *static_page_text(void **region) {
    unsigned char *base = mmap(NULL, page_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(base != MAP_FAILED);
    myl_block *text = (myl_block *)base;
    text->kind = MYL_KIND_STR | MYL_STATIC_STORAGE;
    text->len = 1280;
    text->cap = text->len;
    for (size_t index = 0; index < 256; ++index)
        memcpy(block_data(text) + index * 5, "\xcf\x80\xe4\xb8\xad", 5);
    block_data(text)[text->len] = 0;
    assert(!mprotect(base, page_size, PROT_READ));
    *region = base;
    return text;
}

/* What must not change while the workers run: the data bytes, the kind and the length of every text, and
   the whole reserved word of a text that was hashed before startup. */
static unsigned char *snapshot[4];
static uint32_t snapshot_kind[4];
static int64_t snapshot_len[4];
static uint64_t snapshot_reserved[4];
static bool hashed_before[4];
static bool frozen[4];
static void take_snapshot(void) {
    for (unsigned index = 0; index < 4; ++index) {
        myl_block *text = texts[index];
        snapshot[index] = malloc((size_t)text->len + 1);
        assert(snapshot[index]);
        memcpy(snapshot[index], block_data(text), (size_t)text->len + 1);
        snapshot_kind[index] = text->kind;
        snapshot_len[index] = text->len;
        snapshot_reserved[index] = (uint64_t)text->reserved;
        hashed_before[index] = (text->kind & MYL_TEXT_HASHED) != 0;
        frozen[index] = hashed_before[index] || (text->kind & MYL_STATIC_STORAGE) != 0;
    }
}
static void verify_snapshot(void) {
    for (unsigned index = 0; index < 4; ++index) {
        myl_block *text = texts[index];
        assert(text->kind == snapshot_kind[index]);
        assert(text->len == snapshot_len[index]);
        assert(memcmp(block_data(text), snapshot[index], (size_t)text->len + 1) == 0);
        if (frozen[index]) assert((uint64_t)text->reserved == snapshot_reserved[index]);
        check_text(text);
    }
}

static void *read_worker(void *unused) {
    (void)unused;
    core_worker_runtime_start();
    assert(core_parallel());
    for (unsigned repeat = 0; repeat < 4; ++repeat)
        for (unsigned index = 0; index < 4; ++index) check_text(texts[index]);
    return NULL;
}

/* The generated-layout pointer list and a deliberately guarded general layout
   must visit the same owned leaves, including static and absent children. */
static void drop_pointer(const unsigned char *element, void *context) {
    myl_block *child;
    memcpy(&child, element, sizeof child);
    myl_core_drop_child_pending(child, context);
}
static const struct {
    int32_t words[5];
    core_layout_drop drop;
} pointer_layout = {{sizeof(myl_block *), 1, -1, 0, 0}, drop_pointer};
static const int32_t general_layout[] = {sizeof(myl_block *), 1, 0, 0, 0};
typedef struct { int64_t tag; myl_block *child; } guarded_element;
static const int32_t guarded_layout[] = {sizeof(guarded_element), 1, 1,
    offsetof(guarded_element, child), 1, offsetof(guarded_element, tag), 1, 0};
static myl_block static_leaf = {MYL_KIND_STR | MYL_STATIC_STORAGE, 0, 0, 0};
static myl_block static_buffer = {5u | MYL_STATIC_STORAGE, 0, 0, 0};

static myl_block *drop_tree(bool generated, unsigned depth) {
    myl_block *root = NULL;
    for (unsigned level = 0; level < depth; ++level) {
        myl_block *list = block_new(MYL_KIND_LIST, 10, sizeof(myl_block *));
        list->reserved = (int64_t)(intptr_t)(generated ? (const void *)&pointer_layout : (const void *)general_layout);
        myl_block *small = str_from("leaf", 4);
        myl_block *large = block_new(MYL_KIND_BYTES, 2048, 1);
        large->len = 2048;
        myl_block *empty_buffer = myl_core_buffer_new(0);
        myl_block *tiny_buffer = myl_core_buffer_new(1);
        myl_block *small_buffer = myl_core_buffer_new(31);
        myl_block *large_buffer = myl_core_buffer_new(2048);
        assert(!empty_buffer->reserved && !tiny_buffer->reserved &&
               !small_buffer->reserved && !large_buffer->reserved);
        myl_block *children[] = {root, small, large, &static_leaf, NULL,
            empty_buffer, tiny_buffer, small_buffer, large_buffer, &static_buffer};
        memcpy(block_data(list), children, sizeof children);
        list->len = 10;
        root = list;
    }
    return root;
}

static void drop_shapes(void) {
    for (unsigned generated = 0; generated < 2; ++generated) {
        myl_core_drop_owned(drop_tree(generated, 20000));
        assert(live_count() == 0);
    }
    /* Inactive children are poison: enumerating an inactive arm would fail. */
    myl_block *guarded = block_new(MYL_KIND_LIST, 2, sizeof(guarded_element));
    guarded->reserved = (int64_t)(intptr_t)guarded_layout;
    guarded_element values[] = {{0, (myl_block *)(uintptr_t)1}, {1, str_from("guarded", 7)}};
    memcpy(block_data(guarded), values, sizeof values);
    guarded->len = 2;
    myl_core_drop_owned(guarded);
    assert(live_count() == 0);
}

static myl_block *drop_transferred[8];
static pthread_barrier_t drop_gate;
static void *drop_worker(void *argument) {
    size_t index = (size_t)(uintptr_t)argument;
    core_worker_runtime_start();
    drop_transferred[index] = drop_tree(index & 1, 256);
    pthread_barrier_wait(&drop_gate);
    myl_core_drop_owned(drop_transferred[(index + 1) % 8]);
    return NULL;
}
static void drop_parallel(void) {
    atomic_store_explicit(&core_pool_started, true, memory_order_release);
    assert(!pthread_barrier_init(&drop_gate, NULL, 8));
    pthread_t workers[8];
    for (size_t index = 0; index < 8; ++index)
        assert(!pthread_create(&workers[index], NULL, drop_worker, (void *)(uintptr_t)index));
    for (size_t index = 0; index < 8; ++index)
        assert(!pthread_join(workers[index], NULL));
    assert(!pthread_barrier_destroy(&drop_gate));
    assert(live_count() == 0);
}

int main(int argc, char **argv) {
    alarm(30);
    myl_core_start();
    if (argc > 1 && (!strcmp(argv[1], "budget") || !strcmp(argv[1], "buffer-budget"))) {
        heap_ceiling = 1024;
        if (!strcmp(argv[1], "buffer-budget")) (void)myl_core_buffer_new(4096);
        else (void)block_new(MYL_KIND_BYTES, 4096, 1);
        return 90;
    }
    if (argc > 1 && !strcmp(argv[1], "drop")) {
        heap_ceiling = 128 << 20;
        for (unsigned repeat = 0; repeat < 100; ++repeat) {
            myl_core_drop_owned(block_new(MYL_KIND_BYTES, 4096, 1));
            myl_core_drop_owned(myl_core_buffer_new(4096));
            assert(atomic_load_explicit(&heap_held, memory_order_relaxed) == 0);
        }
        drop_shapes();
        drop_parallel();
        puts("owned drop: generated and general shapes, deep walk and eight transfers");
        return myl_core_exit(0);
    }
    page_size = (size_t)sysconf(_SC_PAGESIZE);
    assert(page_size >= MYL_HEADER + 1297);
    texts[0] = readonly_text(false, false, &regions[0]);
    texts[1] = readonly_text(true, false, &regions[1]);
    texts[2] = readonly_text(true, true, &regions[2]);
    texts[3] = static_page_text(&regions[3]);
    take_snapshot();
    /* The scheduler publishes this before creating workers. Published data is read-only; the header pages
       stay writable for the facts (hash, count, cursor), which must follow the rule of OWNERSHIP-TEXT-READONLY-1. */
    atomic_store_explicit(&core_pool_started, true, memory_order_release);
    pthread_t workers[8];
    for (unsigned index = 0; index < 8; ++index)
        assert(!pthread_create(&workers[index], NULL, read_worker, NULL));
    for (unsigned index = 0; index < 8; ++index)
        assert(!pthread_join(workers[index], NULL));
    verify_snapshot();
    for (unsigned index = 0; index < 4; ++index) {
        free(snapshot[index]);
        assert(!munmap(regions[index], index == 3 ? page_size : 2 * page_size));
    }
    assert(live_count() == 0);
    puts("text cache: eight readers, cold and warm read-only pages, facts unchanged");
    return myl_core_exit(0);
}
