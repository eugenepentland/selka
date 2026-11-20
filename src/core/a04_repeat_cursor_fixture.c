/* NEW-CORE-TEXT-CURSOR-1: storage and cursor contract at both runtime ABIs. */
#include "core_rt_all.c"

myl_block *myl_core_task_call(void *run, myl_block *env) {
    return ((myl_block *(*)(myl_block *))run)(env);
}

int main(void) {
    myl_block *text = str_from("\xc3\xa9", 2);
    myl_block *repeated = block_new(MYL_KIND_STR, 40000, 1);
    repeated->len = 40000;
    for (int64_t at = 0; at < repeated->len; at += 2) memcpy(block_data(repeated) + at, block_data(text), 2);
    block_data(repeated)[40000] = 0;
    if (kind_of(repeated) != MYL_KIND_STR || repeated->len != 40000 || repeated->cap != repeated->len) return 1;
    if (block_data(repeated)[repeated->len] != 0 || myl_core_str_chars(repeated) != 20000) return 2;
    if (myl_core_str_offset(repeated, 10000) != 20000 || !(repeated->kind & MYL_TEXT_CURSOR)) return 3;
    if (myl_core_str_offset(repeated, 9999) != 19998 || myl_core_str_offset(repeated, 10001) != 20002) return 4;
    myl_block *bytes = block_new(MYL_KIND_BYTES, 2, 1);
    bytes->len = 2;
    memcpy(block_data(bytes), "\x00\xff", 2);
    myl_block *copied = block_new(MYL_KIND_BYTES, 7, 1);
    copied->len = 6;
    memcpy(block_data(copied), "\x00\xff\x00\xff\x00\xff", 6);
    block_data(copied)[6] = 0;
    if (kind_of(copied) != MYL_KIND_BYTES || copied->len != 6 || copied->cap != 7) return 5;
    if (memcmp(block_data(copied), "\x00\xff\x00\xff\x00\xff", 6) || block_data(copied)[6] != 0) return 6;
    block_data(bytes)[1] = 42;
    if (block_data(copied)[1] != 255) return 7;
    myl_block *empty_text = block_new(MYL_KIND_STR, 0, 1);
    myl_block *empty_bytes = block_new(MYL_KIND_BYTES, 1, 1);
    if (empty_text->len != 0 || empty_text->cap != 0 || block_data(empty_text)[0] != 0) return 8;
    if (empty_bytes->len != 0 || empty_bytes->cap != 1 || block_data(empty_bytes)[0] != 0) return 9;
    block_free(empty_bytes); block_free(empty_text); block_free(copied);
    block_free(bytes); block_free(repeated); block_free(text);
    return live_count() ? 10 : 0;
}
