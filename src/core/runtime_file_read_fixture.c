/* NEW-CORE-FILE-READ-1: a whole-file read's allocation, copies and `read` calls. The
 * runtime is compiled into this file, so every `read` it makes is the one defined below. */
#include "core_rt_all.c"
#undef NDEBUG
#include <assert.h>
#include <sys/wait.h>

myl_block *myl_core_task_call(void *run, myl_block *env) { return ((myl_block *(*)(myl_block *))run)(env); }

static unsigned long reads_seen;
ssize_t read(int fd, void *buffer, size_t count) {
    ++reads_seen;
    return syscall(SYS_read, fd, buffer, count);
}

static char directory[1024];
static char *path_of(const char *name, char *buffer, size_t size) {
    snprintf(buffer, size, "%s/%s", directory, name);
    return buffer;
}
static void write_file(const char *name, const unsigned char *data, size_t length) {
    char path[1200];
    FILE *file = fopen(path_of(name, path, sizeof path), "wb");
    assert(file);
    assert(fwrite(data, 1, length, file) == length);
    assert(!fclose(file));
}
static void append_file(const char *name, const unsigned char *data, size_t length) {
    char path[1200];
    FILE *file = fopen(path_of(name, path, sizeof path), "ab");
    assert(file);
    assert(fwrite(data, 1, length, file) == length);
    assert(!fclose(file));
}
static unsigned char pattern(size_t at) { return (unsigned char)(at * 7 + 3); }
static void fill(unsigned char *data, size_t length) {
    for (size_t at = 0; at < length; ++at) data[at] = pattern(at);
}

/* A result box {status, value, error}: the value is taken out, the rest dropped. */
static myl_block *unbox(myl_block *box, int *status) {
    uint64_t *fields = (uint64_t *)block_data(box);
    *status = (int)fields[0];
    myl_block *value = (myl_block *)(uintptr_t)fields[1];
    fields[1] = 0;
    myl_core_drop_owned(box);
    return value;
}
static myl_block *name_block(const char *name) {
    char path[1200];
    path_of(name, path, sizeof path);
    return core_io_string(path, strlen(path), 1);
}
/* `Filesystem.read_file` (kind 1) or `read_text` (kind 2) of a file in `directory`. */
static myl_block *whole(int64_t cap, uint32_t kind, const char *name, int *status) {
    myl_block *path = name_block(name);
    myl_block *value = unbox(myl_core_file_access(cap, kind, path, NULL), status);
    myl_core_drop_owned(path);
    return value;
}
static void expect_pattern(const myl_block *value, size_t length) {
    assert(value->len == (int64_t)length);
    assert(value->cap == (int64_t)length);
    for (size_t at = 0; at < length; ++at) assert(((const unsigned char *)value + MYL_HEADER)[at] == pattern(at));
}
/* An open read-only file object (kind 0, mode `r`, the owner returned as it is). */
static myl_block *open_file(int64_t cap, const char *name) {
    myl_block *path = name_block(name);
    myl_block *owner = myl_core_file_access(cap, ((uint32_t)'r' << 8) | (1u << 17), path, NULL);
    myl_core_drop_owned(path);
    assert(owner);
    return owner;
}
static myl_block *read_object(myl_block *owner, uint32_t text, int64_t count, int *status) {
    return unbox(myl_core_file_method(owner, text << 16, count, NULL), status);
}

static int read_mode(void) {
    unsetenv("SELKA_OPTIONS");
    myl_core_start();
    heap_ceiling = 64u << 20;
    int64_t cap = myl_core_cap_grant(2);
    int status;
    unsigned long before;
    myl_block *value;

    /* A file of exactly one transfer: one full read, one read to see the end. */
    unsigned char *data = malloc(1 << 20);
    assert(data);
    fill(data, 65536);
    write_file("exact.bin", data, 65536);
    before = reads_seen;
    value = whole(cap, 1, "exact.bin", &status);
    assert(status == 0 && value && kind_of(value) == MYL_KIND_BYTES);
    assert(reads_seen - before == 2);
    expect_pattern(value, 65536);
    myl_core_drop_owned(value);

    /* Larger than a transfer: two reads fill the block, a third sees the end. */
    fill(data, 100000);
    write_file("large.bin", data, 100000);
    before = reads_seen;
    value = whole(cap, 1, "large.bin", &status);
    assert(status == 0 && value);
    assert(reads_seen - before == 3);
    expect_pattern(value, 100000);
    myl_core_drop_owned(value);

    /* A file of one mebibyte, read the same way. */
    fill(data, 1 << 20);
    write_file("mebi.bin", data, 1 << 20);
    value = whole(cap, 1, "mebi.bin", &status);
    assert(status == 0 && value);
    expect_pattern(value, 1 << 20);
    myl_core_drop_owned(value);

    /* Empty: no size to read into, the chunked path answers an empty block. */
    write_file("empty.bin", data, 0);
    value = whole(cap, 1, "empty.bin", &status);
    assert(status == 0 && value && value->len == 0);
    myl_core_drop_owned(value);

    /* Text: valid UTF-8 is a NUL-terminated `str`; invalid is status 5 and no value. */
    static const char valid[] = "h\xc3\xa9llo w\xc3\xb6rld\n";
    write_file("text.txt", (const unsigned char *)valid, sizeof valid - 1);
    value = whole(cap, 2, "text.txt", &status);
    assert(status == 0 && value && kind_of(value) == MYL_KIND_STR);
    assert(value->len == (int64_t)sizeof valid - 1 && value->cap == value->len);
    assert(!memcmp(block_data(value), valid, sizeof valid));
    myl_core_drop_owned(value);
    static const unsigned char invalid[] = {'a', 0xff, 'b', '\n'};
    write_file("bad.txt", invalid, sizeof invalid);
    value = whole(cap, 2, "bad.txt", &status);
    assert(status == 5 && !value);
    value = whole(cap, 1, "bad.txt", &status);
    assert(status == 0 && value && value->len == 4 && !memcmp(block_data(value), invalid, 4));
    myl_core_drop_owned(value);

    /* A missing file keeps its status. */
    value = whole(cap, 1, "missing.bin", &status);
    assert(status != 0 && !value);

    /* No size from `fstat` (/proc reports 0): read to the end in chunks. */
    myl_block *proc = core_io_string("/proc/self/stat", 15, 1);
    value = unbox(myl_core_file_access(cap, 1, proc, NULL), &status);
    myl_core_drop_owned(proc);
    assert(status == 0 && value && value->len > 40);
    assert(((unsigned char *)block_data(value))[value->len - 1] == '\n');
    myl_core_drop_owned(value);

    /* Not a regular file: a pipe delivers its bytes in two writes, then ends. */
    char fifo[1200];
    path_of("pipe", fifo, sizeof fifo);
    assert(!mkfifo(fifo, 0600));
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        int fd = open(fifo, O_WRONLY);
        if (fd < 0 || write(fd, "hello ", 6) != 6 || write(fd, "pipe", 4) != 4) _exit(3);
        close(fd);
        _exit(0);
    }
    value = whole(cap, 1, "pipe", &status);
    assert(status == 0 && value && value->len == 10 && !memcmp(block_data(value), "hello pipe", 10));
    myl_core_drop_owned(value);
    int wait_status;
    assert(waitpid(child, &wait_status, 0) == child && WIFEXITED(wait_status) && WEXITSTATUS(wait_status) == 0);

    /* The file grows after it is opened: the read still ends at the real end. */
    fill(data, 1000);
    write_file("grow.bin", data, 1000);
    myl_block *owner = open_file(cap, "grow.bin");
    unsigned char extra[5000];
    for (size_t at = 0; at < sizeof extra; ++at) extra[at] = pattern(1000 + at);
    append_file("grow.bin", extra, sizeof extra);
    value = read_object(owner, 0, -1, &status);
    assert(status == 0 && value);
    expect_pattern(value, 6000);
    myl_core_drop_owned(value);
    myl_core_drop_owned(owner);

    /* The file shrinks after it is opened: the block holds what was there. */
    fill(data, 5000);
    write_file("shrink.bin", data, 5000);
    owner = open_file(cap, "shrink.bin");
    char shrink[1200];
    assert(!truncate(path_of("shrink.bin", shrink, sizeof shrink), 1200));
    value = read_object(owner, 0, -1, &status);
    assert(status == 0 && value);
    expect_pattern(value, 1200);
    myl_core_drop_owned(value);
    myl_core_drop_owned(owner);

    /* A count below the size reads exactly that count and stops; the rest follows. */
    fill(data, 3000);
    write_file("count.bin", data, 3000);
    owner = open_file(cap, "count.bin");
    before = reads_seen;
    value = read_object(owner, 0, 100, &status);
    assert(status == 0 && value && reads_seen - before == 1);
    expect_pattern(value, 100);
    myl_core_drop_owned(value);
    value = read_object(owner, 0, -1, &status);
    assert(status == 0 && value && value->len == 2900);
    for (size_t at = 0; at < 2900; ++at) assert(block_data(value)[at] == pattern(100 + at));
    myl_core_drop_owned(value);
    myl_core_drop_owned(owner);

    free(data);
    core_io_table_free();
    assert(live_count() == 0);
    /* The 64 KiB chunks of small blocks stay charged; every large block was refunded. */
    assert(atomic_load_explicit(&heap_held, memory_order_relaxed) <= 4 * MYL_CHUNK);
    puts("read: sized single copies, two reads per transfer, every fallback exact");
    return 0;
}

/* A file above the byte ceiling is refused by the memory budget. */
static int budget_mode(void) {
    unsetenv("SELKA_OPTIONS");
    myl_core_start();
    unsigned char *data = calloc(1, 2 << 20);
    assert(data);
    write_file("big.bin", data, 2 << 20);
    free(data);
    heap_ceiling = 1u << 20;
    int64_t cap = myl_core_cap_grant(2);
    int status;
    (void)whole(cap, 1, "big.bin", &status);
    return 90;
}

int main(int argc, char **argv) {
    alarm(60);
    const char *where = getenv("FIXTURE_DIRECTORY");
    if (where) snprintf(directory, sizeof directory, "%s", where);
    if (argc > 1 && !strcmp(argv[1], "read")) return read_mode();
    if (argc > 1 && !strcmp(argv[1], "budget")) return budget_mode();
    return 2;
}
