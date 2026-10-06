/* S2 text ABI: shared str/bytes leaf blocks; header flags and cache are §3.1. */
enum { MYL_TEXT_ASCII = 1u << 8, MYL_TEXT_HASHED = 2u << 8,
       MYL_TEXT_SCALARS = 4u << 8, MYL_TEXT_CURSOR = 8u << 8 };

static bool core_text_ascii(const unsigned char *bytes, uint64_t len) {
    uint64_t at = 0;
    for (; at + 8 <= len; at += 8) {
        uint64_t word;
        memcpy(&word, bytes + at, 8);
        if (word & UINT64_C(0x8080808080808080)) return false;
    }
    for (; at < len; ++at) if (bytes[at] & 0x80) return false;
    return true;
}

static void core_text_publish(myl_block *text) {
    text->kind &= ~(MYL_TEXT_ASCII | MYL_TEXT_HASHED | MYL_TEXT_SCALARS | MYL_TEXT_CURSOR);
    text->reserved = 0;
    if (core_text_ascii(block_data(text), (uint64_t)text->len)) text->kind |= MYL_TEXT_ASCII;
}

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

/* Equal lengths, then the bytes. Texts of one length that differ usually differ near
   an end, so a pair past 256 bytes compares its first and last eight bytes before the
   bulk compare, which a mismatch at the end would otherwise pay for in full (the old
   runtime's `myl_native_text_equal`). Shorter pairs go straight to `memcmp`: an extra
   path for them costs more than it saves. */
bool myl_core_str_eq(const myl_block *a, const myl_block *b) {
    if (a == b) return true;
    if (a->len != b->len) return false;
    if ((a->kind & b->kind & MYL_TEXT_HASHED) && (uint32_t)a->reserved != (uint32_t)b->reserved) return false;
    const size_t count = (size_t)a->len;
    const unsigned char *left = (const unsigned char *)a + MYL_HEADER, *right = (const unsigned char *)b + MYL_HEADER;
    if (count > 256) {
        uint64_t first_a, first_b, last_a, last_b;
        memcpy(&first_a, left, 8); memcpy(&first_b, right, 8);
        memcpy(&last_a, left + count - 8, 8); memcpy(&last_b, right + count - 8, 8);
        if ((first_a ^ first_b) | (last_a ^ last_b)) return false;
    }
    return memcmp(left, right, count) == 0;
}

uint64_t myl_core_str_chars(const myl_block *text) {
    if (text->kind & MYL_TEXT_ASCII) return (uint64_t)text->len;
    if (text->kind & MYL_TEXT_SCALARS) return (uint64_t)text->reserved >> 32;
    const unsigned char *bytes = (const unsigned char *)text + MYL_HEADER;
    uint64_t scalars = 0;
    for (int64_t i = 0; i < text->len; ++i) scalars += (bytes[i] & 0xc0) != 0x80;
    if (text->count != MYL_SATURATED && scalars <= UINT32_MAX) {
        myl_block *mutable = (myl_block *)text;
        mutable->reserved = (int64_t)((scalars << 32) | (uint32_t)text->reserved);
        mutable->kind |= MYL_TEXT_SCALARS;
    }
    return scalars;
}

uint64_t myl_core_str_offset(const myl_block *text, uint64_t scalar) {
    if (text->kind & MYL_TEXT_ASCII) return scalar < (uint64_t)text->len ? scalar : (uint64_t)text->len;
    const unsigned char *bytes = (const unsigned char *)text + MYL_HEADER;
    uint64_t at = 0, index = 0;
    if ((text->kind & MYL_TEXT_CURSOR) && scalar <= UINT32_MAX) {
        uint64_t cursor = (uint64_t)text->cap;
        if ((uint32_t)(cursor >> 32) <= scalar) { index = cursor >> 32; at = (uint32_t)cursor; }
    }
    while (at + 32 <= (uint64_t)text->len) {
        uint64_t count = 0;
        for (unsigned word_at = 0; word_at < 32; word_at += 8) {
            uint64_t word;
            memcpy(&word, bytes + at + word_at, 8);
            uint64_t continuation = (word & ~(word << 1)) & UINT64_C(0x8080808080808080);
            count += 8 - (uint64_t)__builtin_popcountll(continuation);
        }
        if (index + count >= scalar) break;
        index += count; at += 32;
        while (at < (uint64_t)text->len && (bytes[at] & 0xc0) == 0x80) ++at;
    }
    while (at < (uint64_t)text->len && index < scalar) { ++at; while (at < (uint64_t)text->len && (bytes[at] & 0xc0) == 0x80) ++at; ++index; }
    if (text->count != MYL_SATURATED && text->len >= 256 && text->len <= UINT32_MAX && scalar <= UINT32_MAX && ((text->kind & MYL_TEXT_CURSOR) || text->cap == text->len)) {
        ((myl_block *)text)->cap = (int64_t)((scalar << 32) | at);
        ((myl_block *)text)->kind |= MYL_TEXT_CURSOR;
    }
    return at;
}

uint64_t myl_core_ir_str_width(myl_block *text, uint64_t offset) {
    if (offset >= (uint64_t)text->len) myl_core_s2_unsupported(-1);
    unsigned char c = block_data(text)[offset];
    return c < 0x80 ? 1 : c < 0xe0 ? 2 : c < 0xf0 ? 3 : 4;
}

uint32_t myl_core_ir_str_code(myl_block *text, uint64_t offset) {
    uint64_t width = myl_core_ir_str_width(text, offset);
    const unsigned char *bytes = block_data(text) + offset;
    uint32_t point = bytes[0] & (width == 1 ? 0x7f : width == 2 ? 0x1f : width == 3 ? 0xf : 7);
    for (uint64_t i = 1; i < width; ++i) point = (point << 6) | (bytes[i] & 0x3f);
    return point;
}

/* Runtime table of immortal one-byte scalars. Initialized before its first use. */
static struct { myl_block header; unsigned char data[32]; } core_ascii[128];
static bool core_ascii_ready;
static myl_block *core_ascii_char(unsigned char ch) {
    if (!core_ascii_ready) {
        for (unsigned i = 0; i < 128; ++i) {
            core_ascii[i].header = (myl_block){MYL_SATURATED, MYL_KIND_STR | MYL_TEXT_ASCII | MYL_TEXT_SCALARS, 1, 1, INT64_C(1) << 32};
            core_ascii[i].data[0] = (unsigned char)i;
            core_ascii[i].header.reserved |= myl_core_str_hash(&core_ascii[i].header);
            core_ascii[i].header.kind |= MYL_TEXT_HASHED;
        }
        core_ascii_ready = true;
    }
    return &core_ascii[ch].header;
}

myl_block *myl_core_ir_str_char(myl_block *text, uint64_t offset) {
    uint64_t width = myl_core_ir_str_width(text, offset);
    if (width == 1) return core_ascii_char(block_data(text)[offset]);
    return str_from((const char *)block_data(text) + offset, (size_t)width);
}

myl_block *myl_core_ir_str_from_view(const unsigned char *data, uint64_t len) { return str_from((const char *)data, (size_t)len); }
myl_block *myl_core_ir_span_materialize(const unsigned char *data, uint64_t len) { return myl_core_ir_str_from_view(data, len); }

static myl_block *str_new(int64_t len) {
    myl_block *text = block_new(MYL_KIND_STR, len, 1);
    text->len = len;
    block_data(text)[len] = 0;
    return text;
}

myl_block *myl_core_str_concat(const myl_block *a, const myl_block *b) {
    myl_block *text = str_new(a->len + b->len);
    memcpy(block_data(text), (const unsigned char *)a + MYL_HEADER, (size_t)a->len);
    memcpy(block_data(text) + a->len, (const unsigned char *)b + MYL_HEADER, (size_t)b->len);
    core_text_publish(text);
    return text;
}

myl_block *myl_core_ir_str_append(myl_block *a, const myl_block *b) {
    bool ascii = (a->kind & b->kind & MYL_TEXT_ASCII) != 0;
    int64_t len = a->len + b->len;
    if (a->count != 1) myl_core_s2_unsupported(-1);
    if (a->kind & MYL_TEXT_CURSOR) { a->cap = a->len; a->kind &= ~MYL_TEXT_CURSOR; }
    if (len > a->cap) {
        int64_t cap = a->cap > 0 ? a->cap * 2 : 16;
        if (cap < len) cap = len;
        size_t room;
        myl_block *grown = block_alloc(MYL_KIND_STR, (size_t)cap + 1, &room);
        grown->cap = (int64_t)room - 1;
        grown->len = a->len;
        memcpy(block_data(grown), block_data(a), (size_t)a->len);
        memcpy(block_data(grown) + a->len, (const unsigned char *)b + MYL_HEADER, (size_t)b->len);
        block_free(a);
        a = grown;
    } else memmove(block_data(a) + a->len, (const unsigned char *)b + MYL_HEADER, (size_t)b->len);
    a->len = len;
    block_data(a)[len] = 0;
    a->kind &= ~(MYL_TEXT_ASCII | MYL_TEXT_HASHED | MYL_TEXT_SCALARS | MYL_TEXT_CURSOR);
    if (ascii) a->kind |= MYL_TEXT_ASCII;
    a->reserved = 0;
    return a;
}

myl_block *myl_core_ir_str_append_char(myl_block *a, myl_block *text, uint64_t offset) {
    uint64_t width = myl_core_ir_str_width(text, offset);
    struct { myl_block block; unsigned char bytes[4]; } piece = {{MYL_SATURATED, MYL_KIND_STR | (width == 1 ? MYL_TEXT_ASCII : 0), (int64_t)width, (int64_t)width, 0}, {0}};
    memcpy(piece.bytes, block_data(text) + offset, (size_t)width);
    return myl_core_ir_str_append(a, &piece.block);
}

static int64_t core_text_clamp(int64_t index, int64_t len) {
    if (index < 0) index += len;
    return index < 0 ? 0 : index > len ? len : index;
}

myl_block *myl_core_ir_str_slice(myl_block *text, int64_t start, int64_t end) {
    int64_t len = (int64_t)myl_core_str_chars(text);
    start = core_text_clamp(start, len); end = core_text_clamp(end, len);
    uint64_t a = myl_core_str_offset(text, (uint64_t)start), b = end > start ? myl_core_str_offset(text, (uint64_t)end) : a;
    return str_from((const char *)block_data(text) + a, (size_t)(b - a));
}

static inline void core_text_copy_short(unsigned char *output, const unsigned char *input, size_t count) {
    if (count>=8) {
        uint64_t first,last;
        memcpy(&first,input,8); memcpy(&last,input+count-8,8);
        memcpy(output,&first,8); memcpy(output+count-8,&last,8);
    } else if (count>=4) {
        uint32_t first,last;
        memcpy(&first,input,4); memcpy(&last,input+count-4,4);
        memcpy(output,&first,4); memcpy(output+count-4,&last,4);
    } else if (count>=2) {
        uint16_t first,last;
        memcpy(&first,input,2); memcpy(&last,input+count-2,2);
        memcpy(output,&first,2); memcpy(output+count-2,&last,2);
    } else if (count) output[0]=input[0];
}
static inline void core_text_copy(unsigned char *output, const unsigned char *input, size_t count) {
    if (count>16) { memcpy(output,input,count); return; }
    core_text_copy_short(output,input,count);
}
/* The sizing pass proves every copy in this leaf is at most sixteen octets.
 * Choose the separator's bounded word width once, then keep its endpoints in
 * registers while the output cursor advances. Only bounded fixed-size copies
 * appear in this leaf, and no input aliases the fresh output.
 * The two overlapping stores cover any separator in the chosen size band. */
#define CORE_JOIN_SHORT_WORDS(Word) do { \
    Word first,last; \
    memcpy(&first,between,sizeof first); \
    memcpy(&last,between+width-sizeof last,sizeof last); \
    for (size_t i=0;i<length;i++) { \
        if (i) { \
            memcpy(output,&first,sizeof first); \
            memcpy(output+width-sizeof last,&last,sizeof last); \
            output+=width; \
        } \
        const myl_block *part=items[i]; \
        const size_t bytes=part->len; \
        if (bytes) core_text_copy_short(output,(const unsigned char *)part + MYL_HEADER,bytes); \
        output+=bytes; \
    } \
    return; \
} while (0)
static __attribute__((noinline)) void core_text_join_short(unsigned char *output, myl_block *const *items, size_t length,
                                                const unsigned char *between, size_t width) {
    if (!length) return;
    if (width>=8) CORE_JOIN_SHORT_WORDS(uint64_t);
    if (width>=4) CORE_JOIN_SHORT_WORDS(uint32_t);
    if (width>=2) CORE_JOIN_SHORT_WORDS(uint16_t);
    if (width) CORE_JOIN_SHORT_WORDS(unsigned char);
    for (size_t i=0;i<length;i++) {
        const myl_block *part=items[i];
        const size_t bytes=part->len;
        if (bytes) core_text_copy_short(output,(const unsigned char *)part + MYL_HEADER,bytes);
        output+=bytes;
    }
}
#undef CORE_JOIN_SHORT_WORDS
myl_block *myl_core_str_join(const myl_block *separator, myl_block *parts) {
    myl_block **items = (myl_block **)block_data(parts);
    int64_t total = parts->len > 1 ? separator->len * (parts->len - 1) : 0;
    bool short_copies = separator->len <= 16;
    bool ascii = parts->len < 2 || (separator->kind & MYL_TEXT_ASCII);
    for (int64_t i = 0; i < parts->len; ++i) { total += items[i]->len; ascii = ascii && (items[i]->kind & MYL_TEXT_ASCII); short_copies = short_copies && items[i]->len <= 16; }
    myl_block *text = str_new(total);
    unsigned char *at = block_data(text);
    if (short_copies) core_text_join_short(at, items, (size_t)parts->len, (const unsigned char *)separator + MYL_HEADER, (size_t)separator->len);
    else for (int64_t i = 0; i < parts->len; ++i) {
        if (i) { core_text_copy(at, (const unsigned char *)separator + MYL_HEADER, (size_t)separator->len); at += separator->len; }
        core_text_copy(at, (const unsigned char *)items[i] + MYL_HEADER, (size_t)items[i]->len); at += items[i]->len;
    }
    if (ascii) text->kind |= MYL_TEXT_ASCII;
    return text;
}

/* Bytewise search keeps UTF-8 boundaries because both needle and haystack are valid. */
static int64_t core_text_find_bytes(const myl_block *text, const myl_block *needle, int64_t start) {
    if (!needle->len) return start;
    const unsigned char *data = (const unsigned char *)text + MYL_HEADER;
    const unsigned char *wanted = (const unsigned char *)needle + MYL_HEADER;
    if (needle->len > text->len - start) return -1;
    for (unsigned tried = 0; tried < 8; ++tried) {
        const unsigned char *hit = memchr(data + start, wanted[0], (size_t)(text->len - needle->len - start + 1));
        if (!hit) return -1;
        start = hit - data;
        /* The rest of a candidate is short in every search here: a loop that stops at
           the first difference costs less than a `memcmp` call per candidate. */
        int64_t same = 1;
        while (same < needle->len && hit[same] == wanted[same]) ++same;
        if (same == needle->len) return start;
        ++start;
        if (start > text->len - needle->len) return -1;
    }
    /* libc's bounded linear search handles repeated first bytes after a few cheap candidates. */
    extern void *memmem(const void *, size_t, const void *, size_t);
    const unsigned char *hit = memmem(data + start, (size_t)(text->len - start), wanted, (size_t)needle->len);
    if (hit) return hit - data;
    return -1;
}

/* Scalars that start in bytes [from, to): every byte that is not a UTF-8 continuation. */
static uint64_t core_text_starts(const unsigned char *bytes, uint64_t from, uint64_t to) {
    uint64_t count = 0;
    for (uint64_t i = from; i < to; ++i) count += (bytes[i] & 0xc0) != 0x80;
    return count;
}

/* The scalar index of a match is counted from the nearer end: a match near the end
   of a long text is the cached scalar count less the few scalars after it (the old
   runtime's `index_walk`). */
int64_t myl_core_str_find(myl_block *text, myl_block *needle) {
    int64_t hit = core_text_find_bytes(text, needle, 0);
    if (hit < 0 || (text->kind & MYL_TEXT_ASCII)) return hit;
    const unsigned char *bytes = block_data(text);
    const uint64_t at = (uint64_t)hit, length = (uint64_t)text->len;
    if (at <= length - at) return (int64_t)core_text_starts(bytes, 0, at);
    return (int64_t)(myl_core_str_chars(text) - core_text_starts(bytes, at, length));
}

bool myl_core_str_contains(myl_block *text, myl_block *needle) { return core_text_find_bytes(text, needle, 0) >= 0; }
bool myl_core_str_starts(myl_block *text, myl_block *needle) { return needle->len <= text->len && memcmp(block_data(text), block_data(needle), (size_t)needle->len) == 0; }
bool myl_core_str_ends(myl_block *text, myl_block *needle) { return needle->len <= text->len && memcmp(block_data(text) + text->len - needle->len, block_data(needle), (size_t)needle->len) == 0; }

static const int32_t core_text_list_layout[] = {8, 1, 0, 0, 0};
myl_block *myl_core_str_split(myl_block *text, myl_block *separator) {
    if (!separator->len) myl_core_s2_unsupported(-1);
    myl_block *list = myl_core_list_new_slow(0, 8);
    list->reserved = (int64_t)(intptr_t)core_text_list_layout;
    int64_t at = 0;
    for (;;) {
        int64_t hit = core_text_find_bytes(text, separator, at);
        int64_t end = hit < 0 ? text->len : hit;
        myl_block *piece = str_from((const char *)block_data(text) + at, (size_t)(end - at));
        if (list->len == list->cap) list = myl_core_list_grow(list, 8);
        ((myl_block **)block_data(list))[list->len++] = piece;
        if (hit < 0) break;
        at = hit + separator->len;
    }
    return list;
}

bool myl_core_bytes_valid_list(myl_block *list) {
    const int64_t *values = (const int64_t *)block_data(list);
    for (int64_t i = 0; i < list->len; ++i) if (values[i] < 0 || values[i] > 255) return false;
    return true;
}

myl_block *myl_core_bytes_from_list(myl_block *list) {
    myl_block *bytes = str_new(list->len);
    int64_t *values = (int64_t *)block_data(list);
    for (int64_t i = 0; i < list->len; ++i) block_data(bytes)[i] = (unsigned char)values[i];
    bytes->kind = (bytes->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return bytes;
}

myl_block *myl_core_bytes_concat(const myl_block *a, const myl_block *b) { myl_block *out = myl_core_str_concat(a, b); out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES; return out; }
myl_block *myl_core_bytes_slice(myl_block *text, int64_t start, int64_t end) {
    start = core_text_clamp(start, text->len); end = core_text_clamp(end, text->len);
    myl_block *out = str_from((const char *)block_data(text) + start, (size_t)(end > start ? end - start : 0));
    out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return out;
}

myl_block *myl_core_text_encode(myl_block *text) { retain_block(text); return text; }
int64_t myl_core_bytes_find(myl_block *text, myl_block *needle) { return core_text_find_bytes(text, needle, 0); }

uint64_t myl_core_str_index_offset(myl_block *text, int64_t index) {
    if (index < 0) index += (int64_t)myl_core_str_chars(text);
    return index < 0 ? (uint64_t)text->len : myl_core_str_offset(text, (uint64_t)index);
}
uint64_t myl_core_bytes_index_offset(myl_block *text, int64_t index) {
    if (index < 0) index += text->len;
    return (uint64_t)index;
}

static int64_t core_text_step_bound(int64_t value, int64_t len, int64_t step, bool stop) {
    if ((!stop && value == INT64_MIN) || (stop && value == INT64_MAX)) return step < 0 ? (stop ? -1 : len - 1) : (stop ? len : 0);
    if (value < 0) value += len;
    if (step < 0) return value < 0 ? -1 : value >= len ? len - 1 : value;
    return value < 0 ? 0 : value > len ? len : value;
}

static myl_block *core_text_slice_step(myl_block *text, int64_t start, int64_t end, int64_t step, bool unicode) {
    int64_t len = unicode ? (int64_t)myl_core_str_chars(text) : text->len;
    start = core_text_step_bound(start, len, step, false); end = core_text_step_bound(end, len, step, true);
    myl_block *out = str_new(text->len);
    out->len = 0;
    for (int64_t i = start; step > 0 ? i < end : i > end;) {
        uint64_t at = unicode ? myl_core_str_offset(text, (uint64_t)i) : (uint64_t)i;
        uint64_t width = unicode ? myl_core_ir_str_width(text, at) : 1;
        memcpy(block_data(out) + out->len, block_data(text) + at, (size_t)width);
        out->len += (int64_t)width;
        if ((step > 0 && i > INT64_MAX - step) || (step < 0 && i < INT64_MIN - step)) break;
        i += step;
    }
    block_data(out)[out->len] = 0;
    core_text_publish(out);
    if (!unicode) out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return out;
}

myl_block *myl_core_str_slice_step(myl_block *text, int64_t start, int64_t end, int64_t step) { return core_text_slice_step(text, start, end, step, true); }
myl_block *myl_core_bytes_slice_step(myl_block *text, int64_t start, int64_t end, int64_t step) { return core_text_slice_step(text, start, end, step, false); }

static bool core_text_space(unsigned char ch) { return ch == ' ' || (ch >= 9 && ch <= 13); }
myl_block *myl_core_str_split_whitespace(myl_block *text) {
    myl_block *list = myl_core_list_new_slow(0, 8);
    list->reserved = (int64_t)(intptr_t)core_text_list_layout;
    int64_t at = 0;
    while (at < text->len) {
        while (at < text->len && core_text_space(block_data(text)[at])) ++at;
        int64_t start = at;
        while (at < text->len && !core_text_space(block_data(text)[at])) ++at;
        if (start == at) break;
        myl_block *piece = str_from((const char *)block_data(text) + start, (size_t)(at - start));
        if (list->len == list->cap) list = myl_core_list_grow(list, 8);
        ((myl_block **)block_data(list))[list->len++] = piece;
    }
    return list;
}

myl_block *myl_core_bytes_to_list(myl_block *bytes) {
    myl_block *list = myl_core_list_new_slow(bytes->len, 8);
    list->len = bytes->len;
    for (int64_t i = 0; i < bytes->len; ++i) ((int64_t *)block_data(list))[i] = block_data(bytes)[i];
    return list;
}

bool myl_core_bytes_contains_value(myl_block *bytes, int64_t value) {
    return value >= 0 && value <= 255 && memchr(block_data(bytes), (unsigned char)value, (size_t)bytes->len) != NULL;
}
