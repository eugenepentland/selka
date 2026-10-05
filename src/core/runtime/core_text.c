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
