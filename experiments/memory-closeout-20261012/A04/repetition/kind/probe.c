/* Concatenated after the same runtime fragments as src/core/driver.zig. */
#define CHECK(expression) do { if (!(expression)) { fputs(#expression "\n", stderr); return 1; } } while (0)
int main(void) {
    myl_block *bytes = block_new(MYL_KIND_BYTES, 3, 1);
    bytes->len = 2;
    block_data(bytes)[0] = 0xff;
    block_data(bytes)[1] = 0;
    myl_block *repeated = myl_core_octets_repeat_unsigned(bytes, 3);
    CHECK(kind_of(repeated) == MYL_KIND_BYTES);
    CHECK(repeated->len == 6);
    for (size_t i = 0; i < 6; ++i) CHECK(block_data(repeated)[i] == (i % 2 ? 0 : 0xff));
    myl_block *text = str_from("\xc3\xa9", 2);
    myl_block *repeated_text = myl_core_octets_repeat_signed(text, 2);
    CHECK(kind_of(repeated_text) == MYL_KIND_STR);
    CHECK(repeated_text->len == 4);
    CHECK(memcmp(block_data(repeated_text), "\xc3\xa9\xc3\xa9", 4) == 0);
    block_free(repeated_text); block_free(text); block_free(repeated); block_free(bytes);
    return 0;
}
