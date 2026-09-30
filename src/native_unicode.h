#ifndef MYLANG_NATIVE_UNICODE_H
#define MYLANG_NATIVE_UNICODE_H
#include <stddef.h>
#include <stdint.h>
/* Decode one scalar from a payload already validated by the text constructor. */
static inline uint32_t myl_unicode_next(const unsigned char *data, size_t *at) {
    uint32_t point=data[(*at)++];
    if (point<0x80) return point;
    unsigned count=point<0xe0 ? 1 : point<0xf0 ? 2 : 3;
    point&=count==1 ? 0x1f : count==2 ? 0x0f : 0x07;
    while (count--) point=(point<<6)|(data[(*at)++]&0x3f);
    return point;
}
/* Beginning of the scalar immediately before a known scalar boundary. */
static inline size_t myl_unicode_previous(const unsigned char *data, size_t at) {
    at--;
    while ((data[at]&0xc0)==0x80) at--;
    return at;
}
/* CPython Unicode16 whitespace, pinned independently of ASCII classification. */
static inline int myl_unicode_space(uint32_t point) {
    if (point<128) return (point>=9 && point<=13) || (point>=28 && point<=32);
    if (point>=0x2000 && point<=0x200a) return 1;
    switch (point) {
    case 0x85: case 0xa0: case 0x1680: case 0x2028: case 0x2029:
    case 0x202f: case 0x205f: case 0x3000: return 1;
    default: return 0;
    }
}
#endif
