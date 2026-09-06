/* Test-only allocation accounting and deterministic fault injection.
   Include before the generated runtime; no production allocator hooks. */
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { max_align_t alignment; size_t size; } TestHeader;
static size_t test_attempts, test_fail_at, test_live, test_peak;
static int test_fail(void) { return ++test_attempts == test_fail_at; }
static void test_account(size_t size) {
    test_live += size;
    if (test_live > test_peak) test_peak = test_live;
}
static void *test_malloc(size_t size) {
    if (test_fail() || size > SIZE_MAX - sizeof(TestHeader)) return NULL;
    TestHeader *header = malloc(sizeof(TestHeader) + size);
    if (!header) return NULL;
    header->size = size; test_account(size); return header + 1;
}
static void *test_calloc(size_t count, size_t size) {
    if (count && size > SIZE_MAX / count) return NULL;
    size *= count;
    void *value = test_malloc(size);
    if (value) memset(value, 0, size);
    return value;
}
static void test_free(void *value) {
    if (!value) return;
    TestHeader *header = (TestHeader *)value - 1;
    test_live -= header->size; free(header);
}
static void *test_realloc(void *value, size_t size) {
    if (!value) return test_malloc(size);
    if (test_fail() || size > SIZE_MAX - sizeof(TestHeader)) return NULL;
    TestHeader *old = (TestHeader *)value - 1;
    size_t previous = old->size;
    TestHeader *header = realloc(old, sizeof(TestHeader) + size);
    if (!header) return NULL;
    test_live -= previous; header->size = size; test_account(size);
    return header + 1;
}
static void test_finish(void) {
    fprintf(stderr, "native-memory: attempts=%zu peak=%zu live=%zu\n", test_attempts, test_peak, test_live);
    if (test_live != 0) _Exit(90);
}
__attribute__((constructor)) static void test_setup(void) {
    const char *failure = getenv("NATIVE_FAIL_ALLOCATION");
    if (failure) test_fail_at = (size_t)strtoull(failure, NULL, 10);
    atexit(test_finish);
}
#define malloc test_malloc
#define calloc test_calloc
#define realloc test_realloc
#define free test_free
