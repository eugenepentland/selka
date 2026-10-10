#include "core_rt_all.c"
#undef NDEBUG
#include <assert.h>
myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }
static const int32_t dict_layout[] = {16, 2, 0, 0, 0, 8, 0};
static const core_dict_descriptor desc = {16, 8, 2, 8, dict_layout, NULL, NULL};
static myl_block *root;
static myl_block *make_text(int seed, size_t extra) {
    /* non-ASCII, >= 256 octets */
    char buf[2048]; size_t n = 0;
    for (int i = 0; i < 300; ++i) { buf[n++] = (char)0xc3; buf[n++] = (char)(0xa0 + (i + seed) % 16); }
    myl_block *t = block_new(MYL_KIND_STR, (int64_t)(n + extra), 1);
    memcpy(block_data(t), buf, n); block_data(t)[n] = 0; t->len = (int64_t)n; core_text_publish(t);
    return t;
}
static void *worker(void *arg) {
    long id = (long)arg;
    myl_block *l = root;
    count_retain(l);
    myl_block **items = (myl_block **)block_data(l);
    for (int it = 0; it < 2000; ++it) {
        myl_block *t = items[it % 3];
        (void)myl_core_str_chars(t);
        (void)myl_core_str_offset(t, (uint64_t)((it * 7 + id) % 300));
        (void)myl_core_str_hash(t);
        myl_block *d = items[3];
        char k = (char)('a' + (it % 12));
        myl_block *key = str_from(&k, 1);
        uint64_t h = myl_core_dict_hash(d, &key);
        int64_t at = myl_core_dict_find(d, &key, h);
        (void)at;
        myl_core_release(key);
        myl_block *copy = myl_core_list_copy(l, 8);
        myl_core_release(copy);
        myl_block *dc = myl_core_dict_copy(d);
        myl_core_release(dc);
    }
    myl_core_release(l);
    return NULL;
}
int main(void) {
    myl_block *l = myl_core_list_new_slow(4, 8);
    l->reserved = (int64_t)(intptr_t)layout_blocks;
    myl_block **items = (myl_block **)block_data(l);
    items[0] = make_text(0, 0); items[1] = make_text(1, 64); items[2] = make_text(2, 3);
    myl_block *d = myl_core_dict_new(16, &desc);
    myl_block *v = make_text(5, 0);
    for (int i = 0; i < 12; ++i) {
        char k = (char)('a' + i);
        myl_block *key = str_from(&k, 1);
        count_retain(v);
        uint64_t h = myl_core_dict_hash(d, &key);
        int64_t probe = myl_core_dict_find(d, &key, h);
        d = myl_core_dict_insert(d, probe, &key, &v, true);
    }
    myl_core_release(v);
    items[3] = d; l->len = 4;
    myl_core_share(l);
    root = l;
    pthread_t th[8];
    for (long i = 0; i < 8; ++i) assert(!pthread_create(&th[i], NULL, worker, (void *)i));
    myl_core_release(l);
    for (int i = 0; i < 8; ++i) assert(!pthread_join(th[i], NULL));
    printf("live=%lld\n", (long long)live_count());
    return 0;
}
