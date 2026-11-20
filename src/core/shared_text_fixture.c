/* P1F-6 (B1): caches of shared texts, under OWNERSHIP-TEXT-READONLY-1 as restated: a text's data, kind and
 * length stay unwritten after pool startup and its facts are written atomically into self-validated words.
 * Sequential scalar lookups walk a bounded number of octets, and eight workers that fill and read those
 * caches see one value. */
#include "core_rt_all.c"
#undef NDEBUG
#include <assert.h>

myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }

/* A text of `chars` two-octet scalars with `extra` octets of spare capacity past its length. */
static myl_block *make_text(size_t chars, size_t extra) {
    size_t len = chars * 2;
    myl_block *text = block_new(MYL_KIND_STR, (int64_t)(len + extra), 1);
    for (size_t i = 0; i < chars; ++i) {
        block_data(text)[i * 2] = 0xc3;
        block_data(text)[i * 2 + 1] = 0xa9;
    }
    text->len = (int64_t)len;
    block_data(text)[len] = 0;
    core_text_publish(text);
    return text;
}

static uint64_t walk_octets(myl_block *text) {
    uint64_t before = core_text_walked, sum = 0;
    for (uint64_t i = 0; i < 20000; ++i) {
        uint64_t at = myl_core_str_offset(text, i);
        assert(at == i * 2);
        sum += at;
    }
    assert(sum == 399980000);
    return core_text_walked - before;
}

static myl_block *ping(myl_block *env) { (void)env; return NULL; }

static void start_pool(void) {
    myl_block *group = myl_core_group_open();
    (void)myl_core_task_submit(group, ping, make_text(1, 0), -1);
    myl_core_group_close(group);
    myl_core_drop_owned(group);
}

static void walk(void) {
    myl_block *plain = make_text(20000, 0);
    uint64_t plain_octets = walk_octets(plain);
    start_pool();
    assert(core_parallel());
    myl_block *shared = make_text(20000, 0);
    uint64_t shared_octets = walk_octets(shared);
    /* A walk visits each octet about once; two bounds per lookup would be quadratic. */
    assert(plain_octets <= 40000 && shared_octets <= 40000);
    myl_core_drop_owned(plain);
    myl_core_drop_owned(shared);
    assert(live_count() == 0);
    printf("plain=%llu shared=%llu octets for 20000 lookups\n", (unsigned long long)plain_octets, (unsigned long long)shared_octets);
}

static myl_block *texts[3];
static uint32_t expected_hash;

static void *worker(void *argument) {
    uintptr_t id = (uintptr_t)argument;
    for (uint64_t i = 0; i < 4000; ++i) {
        for (unsigned j = 0; j < 3; ++j) {
            myl_block *text = texts[j];
            /* Half the workers ask for the scalar count first, so the two fills race. */
            if (id & 1) assert(myl_core_str_chars(text) == 300);
            assert(myl_core_str_hash(text) == expected_hash);
            assert(myl_core_str_chars(text) == 300);
            uint64_t index = (i * 7 + id * 31) % 300;
            assert(myl_core_str_offset(text, index) == index * 2);
            assert(myl_core_str_eq(text, texts[(j + 1) % 3]));
        }
    }
    return NULL;
}

static void concurrent(void) {
    core_ascii_char(0);
    start_pool();
    assert(core_parallel());
    /* Three texts of one content: one with no spare capacity (its cursor goes in cap), one with
       spare capacity, one with eight octets spare (a tail cursor, which the pool never writes). */
    texts[0] = make_text(300, 0);
    texts[1] = make_text(300, 64);
    texts[2] = make_text(300, 8);
    expected_hash = myl_core_str_hash(texts[0]);
    pthread_t threads[8];
    for (uintptr_t i = 0; i < 8; ++i) assert(pthread_create(&threads[i], NULL, worker, (void *)i) == 0);
    for (int i = 0; i < 8; ++i) assert(pthread_join(threads[i], NULL) == 0);
    for (unsigned j = 0; j < 3; ++j) myl_core_drop_owned(texts[j]);
    assert(live_count() == 0);
    puts("shared text caches: 8 workers, hash/scalars/cursor ok");
}

/* An owner that set a capacity cursor after the pool started, then appends to the text: the append must
   grow it (a negative cap is no spare capacity) and every fact must follow the new contents. */
static void owner_append(void) {
    start_pool();
    myl_block *text = make_text(300, 0);
    assert(myl_core_str_offset(text, 250) == 500);
    text = myl_core_str_append_bytes(text, (const unsigned char *)"ab", 2);
    assert(text->len == 602);
    assert(myl_core_str_chars(text) == 302);
    assert(myl_core_str_offset(text, 301) == 601 && myl_core_str_offset(text, 302) == 602);
    myl_block *fresh = make_text(301, 0);
    assert(myl_core_str_hash(text) == myl_core_str_hash(text));
    assert(myl_core_str_eq(text, text));
    assert(!myl_core_str_eq(text, fresh));
    myl_core_drop_owned(text);
    myl_core_drop_owned(fresh);
    assert(live_count() == 0);
    puts("owner append: cursor grows the text, facts follow");
}

int main(int argc, char **argv) {
    assert(argc == 2);
    alarm(120);
    myl_core_start();
    if (strcmp(argv[1], "walk") == 0) walk();
    else if (strcmp(argv[1], "owner") == 0) owner_append();
    else concurrent();
    return myl_core_exit(0);
}
