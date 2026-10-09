/* Checks collisions.py's pairs against the runtime's span hash (copied from core_text.c). */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static uint64_t fold(uint64_t a, uint64_t b) { __uint128_t p = (__uint128_t)a * b; return (uint64_t)p ^ (uint64_t)(p >> 64); }
static uint32_t span_hash(const unsigned char *bytes, uint64_t length) {
    size_t len = (size_t)length;
    const uint64_t word_key = UINT64_C(0xa0761d6478bd642f), state_key = UINT64_C(0xe7037ed1a0b428db);
    uint64_t state = UINT64_C(0x243f6a8885a308d3) ^ len, hash;
    if (len <= 8) {
        uint64_t low = 0, high = 0;
        if (len >= 4) { uint32_t first, last; memcpy(&first, bytes, 4); memcpy(&last, bytes + len - 4, 4); low = first; high = last; }
        else if (len) low = (uint64_t)bytes[0] << 16 | (uint64_t)bytes[len >> 1] << 8 | bytes[len - 1];
        hash = fold(low ^ word_key, high ^ state ^ state_key);
    } else {
        uint64_t word;
        for (size_t at = 0; at + 8 < len; at += 8) { memcpy(&word, bytes + at, 8); state = fold(word ^ word_key, state ^ state_key); }
        memcpy(&word, bytes + len - 8, 8);
        hash = fold(word ^ word_key, state ^ state_key);
    }
    return (uint32_t)(hash ^ (hash >> 32));
}
int main(void) {
    char window[16], a[64], b[64]; int len, bad = 0, n = 0;
    while (scanf("%d %15s %63s %63s", &len, window, a, b) == 4) {
        n++;
        if (span_hash((unsigned char *)a, strlen(a)) != span_hash((unsigned char *)b, strlen(b)) || !strcmp(a, b)) { printf("BAD %s %s\n", a, b); bad++; }
    }
    printf("%d pairs, %d bad\n", n, bad);
    return bad != 0;
}
