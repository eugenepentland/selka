/* PM-3 extra ladder: str_build's append loop (bench/parity/micro/str_build.my),
 * where the profile pointed at the uniqueness test and the header.
 *
 *   for i in range(16000000): _ = buffer.append_range(piece, 0, 8)
 *
 *   0  what mylang emits today: per append, the buffer's uniqueness test (a
 *      copy call on the shared path, which may replace the buffer), then the
 *      inline fast path: load len and cap from the header, room test, an
 *      8-byte `llvm.memmove` into the data (untyped, so it may alias the
 *      header) and a store of len + 8 back into the header; the out-of-line
 *      append on the slow path. len lives in memory: each iteration's load
 *      waits on the previous store.
 *   1  rung 0 with the uniqueness test hoisted out of the loop (the buffer is
 *      unique after the first iteration, and nothing in the loop shares it).
 *   2  rung 1 with len and cap kept in registers across the loop (written back
 *      once at the end, and around the slow path): the header is invariant
 *      except through this loop's own appends, and the data store is typed so
 *      it cannot alias the header.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef RUNG
#define RUNG 0
#endif

typedef struct block { uint32_t count, kind; int64_t len, cap; int64_t reserved; } block;
#define DATA(b) ((unsigned char *)(b) + 32)

static __attribute__((noinline, cold)) block *buffer_copy(block *b) { (void)b; abort(); }
static __attribute__((noinline)) block *append_checked(block *b, const unsigned char *piece, int64_t n) {
    int64_t cap = b->cap * 2 > b->len + n ? b->cap * 2 : b->len + n;
    b = realloc(b, (size_t)(32 + cap));
    b->cap = cap;
    memcpy(DATA(b) + b->len, piece, (size_t)n);
    b->len += n;
    return b;
}

__attribute__((noinline)) static block *build(block *buffer, const unsigned char *piece, int64_t count) {
#if RUNG >= 1
    if (buffer->count != 1) buffer = buffer_copy(buffer);
#endif
#if RUNG >= 2
    int64_t len = buffer->len, cap = buffer->cap;
    for (int64_t i = 0; i < count; i++) {
        if (cap - len >= 8) {
            memcpy(DATA(buffer) + len, piece, 8);
            len += 8;
        } else {
            buffer->len = len;
            buffer = append_checked(buffer, piece, 8);
            len = buffer->len; cap = buffer->cap;
        }
    }
    buffer->len = len;
#else
    for (int64_t i = 0; i < count; i++) {
#if RUNG == 0
        if (buffer->count != 1) buffer = buffer_copy(buffer);
#endif
        int64_t len = buffer->len, cap = buffer->cap;
        if (cap - len >= 8) {
            memmove(DATA(buffer) + len, piece, 8);
            buffer->len = len + 8;
        } else {
            buffer = append_checked(buffer, piece, 8);
        }
        __asm__ volatile("" ::: "memory"); /* the memmove's untyped store: the header may have changed */
    }
#endif
    return buffer;
}

int main(void) {
    block *buffer = malloc(32 + 16);
    buffer->count = 1; buffer->kind = 0; buffer->len = 0; buffer->cap = 16; buffer->reserved = 0;
    static const unsigned char piece[9] = "mylang!\n";
    buffer = build(buffer, piece, 16000000);
    int64_t length = buffer->len, total = 0;
    for (int64_t j = 0; j < length / 1021; j++) total = (total + DATA(buffer)[j * 1021]) % 1000003;
    printf("%lld %lld\n", (long long)length, (long long)total);
    return 0;
}
