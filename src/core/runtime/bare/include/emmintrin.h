/* Bare build (no SSE2): the four SSE2 operations core_dict.c's probes use, on a 16-byte group in plain C, so the
   probes read the same control bytes in the same order and give the same answers. core_dict.c includes
   <emmintrin.h> as it does on Linux; the bare include path finds this file first. */
#ifndef MYL_BARE_EMMINTRIN_H
#define MYL_BARE_EMMINTRIN_H
#include "myl_bare_libc.h"
typedef struct { unsigned char lane[16]; } __m128i;
static inline __m128i _mm_set1_epi8(char value) {
    __m128i group;
    memset(group.lane, (unsigned char)value, sizeof group.lane);
    return group;
}
static inline __m128i _mm_loadu_si128(const __m128i *at) {
    __m128i group;
    memcpy(group.lane, at, sizeof group.lane);
    return group;
}
static inline __m128i _mm_cmpeq_epi8(__m128i left, __m128i right) {
    __m128i same;
    for (int i = 0; i < 16; ++i) same.lane[i] = left.lane[i] == right.lane[i] ? 0xff : 0;
    return same;
}
static inline int _mm_movemask_epi8(__m128i group) {
    int bits = 0;
    for (int i = 0; i < 16; ++i) bits |= (group.lane[i] >> 7) << i;
    return bits;
}
#endif
