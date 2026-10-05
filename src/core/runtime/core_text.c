/* Minimal S2-0 hand-built IR support; S2-T owns the full text implementation.
   This source is concatenated after core_rt.c, sharing its block allocator. */
static uint64_t core_ir_utf8_width(myl_block *text, uint64_t offset) {
    if (offset >= (uint64_t)text->len) myl_core_s2_unsupported(-1);
    unsigned char c = block_data(text)[offset];
    uint64_t width = c < 0x80 ? 1 : c < 0xe0 ? 2 : c < 0xf0 ? 3 : 4;
    if (c < 0x80 || (c >= 0xc2 && c <= 0xf4 && offset + width <= (uint64_t)text->len)) return width;
    myl_core_s2_unsupported(-1);
    return 0;
}

myl_block *myl_core_ir_str_char(myl_block *text, uint64_t offset) {
    uint64_t width = core_ir_utf8_width(text, offset);
    return str_from((const char *)block_data(text) + offset, (size_t)width);
}

myl_block *myl_core_ir_str_from_view(const unsigned char *data, uint64_t len) {
    return str_from((const char *)data, (size_t)len);
}

/* Explicit span-helper ABI used by the foundational admission/lifetime tests. */
myl_block *myl_core_ir_span_materialize(const unsigned char *data, uint64_t len) {
    return myl_core_ir_str_from_view(data, len);
}

/* S2-T1 published hash ABI copied for dictionary qualification; replaced at merge. */
#define MYL_TEXT_HASHED (2u << 8)
static uint64_t core_text_fold(uint64_t a, uint64_t b) {
    __uint128_t product = (__uint128_t)a * b;
    return (uint64_t)product ^ (uint64_t)(product >> 64);
}

/* Same deterministic word-at-a-time octet hash as the oracle; no old runtime link. */
uint32_t myl_core_span_hash(const unsigned char *bytes, uint64_t length) {
    size_t len = (size_t)length;
    const uint64_t word_key = UINT64_C(0xa0761d6478bd642f), state_key = UINT64_C(0xe7037ed1a0b428db);
    uint64_t state = UINT64_C(0x243f6a8885a308d3) ^ len, hash;
    if (len <= 8) {
        uint64_t low = 0, high = 0;
        if (len >= 4) {
            uint32_t first, last;
            memcpy(&first, bytes, 4); memcpy(&last, bytes + len - 4, 4);
            low = first; high = last;
        } else if (len) low = (uint64_t)bytes[0] << 16 | (uint64_t)bytes[len >> 1] << 8 | bytes[len - 1];
        hash = core_text_fold(low ^ word_key, high ^ state ^ state_key);
    } else {
        uint64_t word;
        for (size_t at = 0; at + 8 < len; at += 8) {
            memcpy(&word, bytes + at, 8);
            state = core_text_fold(word ^ word_key, state ^ state_key);
        }
        memcpy(&word, bytes + len - 8, 8);
        hash = core_text_fold(word ^ word_key, state ^ state_key);
    }
    return (uint32_t)(hash ^ (hash >> 32));
}

uint32_t myl_core_str_hash(const myl_block *text) {
    if (text->kind & MYL_TEXT_HASHED) return (uint32_t)text->reserved;
    uint32_t folded = myl_core_span_hash((const unsigned char *)text + MYL_HEADER, (uint64_t)text->len);
    if (text->count != MYL_SATURATED) {
        myl_block *mutable = (myl_block *)text;
        mutable->reserved = (int64_t)(((uint64_t)text->reserved & UINT64_C(0xffffffff00000000)) | folded);
        mutable->kind |= MYL_TEXT_HASHED;
    }
    return folded;
}
