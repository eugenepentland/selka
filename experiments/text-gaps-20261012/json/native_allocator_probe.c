/* Linux/glibc qualification probe only. Never use these runs as timing samples. */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
extern void *__libc_malloc(size_t);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);
extern void __libc_free(void *);
static uint64_t malloc_calls, calloc_calls, realloc_calls, free_calls, nonnull_frees;
static uint64_t malloc_bytes, calloc_bytes, realloc_bytes;
void *malloc(size_t size) {
    malloc_calls++; malloc_bytes += size;
    return __libc_malloc(size);
}
void *calloc(size_t count, size_t size) {
    calloc_calls++; calloc_bytes += count * size;
    return __libc_calloc(count, size);
}
void *realloc(void *value, size_t size) {
    realloc_calls++; realloc_bytes += size;
    return __libc_realloc(value, size);
}
void free(void *value) {
    free_calls++; nonnull_frees += value != NULL;
    __libc_free(value);
}
__attribute__((destructor)) static void report(void) {
    /* Snapshot before reporting; reporting itself may call the allocator. */
    uint64_t m = malloc_calls, c = calloc_calls, r = realloc_calls;
    uint64_t f = free_calls, n = nonnull_frees;
    uint64_t mb = malloc_bytes, cb = calloc_bytes, rb = realloc_bytes;
    fprintf(stderr, "{\"version\":\"native-allocator-v1\",\"malloc_calls\":%llu,\"calloc_calls\":%llu,\"realloc_calls\":%llu,\"free_calls\":%llu,\"nonnull_frees\":%llu,\"malloc_bytes\":%llu,\"calloc_bytes\":%llu,\"realloc_bytes\":%llu}\n",
            (unsigned long long)m, (unsigned long long)c, (unsigned long long)r,
            (unsigned long long)f, (unsigned long long)n, (unsigned long long)mb,
            (unsigned long long)cb, (unsigned long long)rb);
}
