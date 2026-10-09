/* S2 text ABI: shared str/bytes leaf blocks; header flags and cache are §3.1. */
enum { MYL_TEXT_ASCII = 1u << 8, MYL_TEXT_HASHED = 2u << 8,
       MYL_TEXT_SCALARS = 4u << 8, MYL_TEXT_CURSOR = 8u << 8, MYL_TEXT_TAIL = 16u << 8 };

/* Octets the scalar-position walks of this process have stepped over. With
   MYL_CORE_TEXTWALK=1 the total is reported on stderr at exit, so a test can bound
   the lookup work of a scan without timing it (NEW-CORE-TEXT-CURSOR-1). */
static uint64_t core_text_walked;
static void core_text_walk_report(void) {
    const char *flag = getenv("MYL_CORE_TEXTWALK");
    if (!flag || strcmp(flag, "1") != 0) return;
    char text[64];
    int len = snprintf(text, sizeof text, "myl-core textwalk: %llu octets\n", (unsigned long long)core_text_walked);
    os_write(2, (const unsigned char *)text, (size_t)len);
}

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

/* Reset a fresh text's flags and cache; `ascii` says its octets are known ASCII. */
static void core_text_publish_known(myl_block *text, bool ascii) {
    text->kind &= ~(MYL_TEXT_ASCII | MYL_TEXT_HASHED | MYL_TEXT_SCALARS | MYL_TEXT_CURSOR | MYL_TEXT_TAIL);
    text->reserved = 0;
    if (ascii || core_text_ascii(block_data(text), (uint64_t)text->len)) text->kind |= MYL_TEXT_ASCII;
}

static void core_text_publish(myl_block *text) { core_text_publish_known(text, false); }

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
    core_text_walked += (uint64_t)text->len;
    for (int64_t i = 0; i < text->len; ++i) scalars += (bytes[i] & 0xc0) != 0x80;
    if (text->count != MYL_SATURATED && scalars <= UINT32_MAX) {
        myl_block *mutable = (myl_block *)text;
        mutable->reserved = (int64_t)((scalars << 32) | (uint32_t)text->reserved);
        mutable->kind |= MYL_TEXT_SCALARS;
    }
    return scalars;
}

/* A scalar position: scalar index `scalar` begins at octet `at`. */
typedef struct { uint64_t scalar, at; } core_anchor;

/* The text cursor (NEW-CORE-TEXT-CURSOR-1) is the last position a lookup resolved,
   packed `scalar << 32 | at`. A text with no spare capacity keeps it in its `cap`
   word (an append restores `cap = len`); a text with at least eight spare octets keeps
   it in its last eight, past the terminating NUL (MYL_TEXT_TAIL). Immortal texts,
   texts under 256 octets and texts past 4 GiB keep none. */
static unsigned char *core_cursor_tail(const myl_block *text) { return (unsigned char *)text + MYL_HEADER + text->cap - 7; }

static bool core_cursor_get(const myl_block *text, core_anchor *cursor) {
    if (!(text->kind & MYL_TEXT_CURSOR)) return false;
    uint64_t packed = (uint64_t)text->cap;
    if (text->kind & MYL_TEXT_TAIL) memcpy(&packed, core_cursor_tail(text), 8);
    *cursor = (core_anchor){packed >> 32, (uint32_t)packed};
    return true;
}

static void core_cursor_set(const myl_block *text, core_anchor cursor) {
    if (text->count == MYL_SATURATED || text->len < 256 || text->len > UINT32_MAX || cursor.scalar > UINT32_MAX) return;
    myl_block *mutable = (myl_block *)text;
    uint64_t packed = cursor.scalar << 32 | cursor.at;
    if (!(text->kind & MYL_TEXT_CURSOR)) {
        if (text->cap == text->len) mutable->kind |= MYL_TEXT_CURSOR;
        else if (text->cap - text->len >= 8) mutable->kind |= MYL_TEXT_CURSOR | MYL_TEXT_TAIL;
        else return;
    }
    if (text->kind & MYL_TEXT_TAIL) memcpy(core_cursor_tail(text), &packed, 8);
    else mutable->cap = (int64_t)packed;
}

/* Scalar starts in the 32 octets at `bytes`: every octet that is not a continuation. */
static uint64_t core_text_starts32(const unsigned char *bytes) {
    uint64_t count = 0;
    for (unsigned word_at = 0; word_at < 32; word_at += 8) {
        uint64_t word;
        memcpy(&word, bytes + word_at, 8);
        uint64_t continuation = (word & ~(word << 1)) & UINT64_C(0x8080808080808080);
        count += 8 - (uint64_t)__builtin_popcountll(continuation);
    }
    return count;
}

/* Walk from `from` to scalar `target`, forward or back, 32 octets at a time while the
   target is not in the next block. A forward walk stops at the end of the text. */
static core_anchor core_text_step(const unsigned char *bytes, uint64_t len, core_anchor from, uint64_t target) {
    uint64_t at = from.at, index = from.scalar;
    if (target >= index) {
        while (at + 32 <= len) {
            uint64_t count = core_text_starts32(bytes + at);
            if (index + count >= target) break;
            index += count; at += 32;
            while (at < len && (bytes[at] & 0xc0) == 0x80) ++at;
        }
        while (at < len && index < target) { ++at; while (at < len && (bytes[at] & 0xc0) == 0x80) ++at; ++index; }
        return (core_anchor){index, at};
    }
    uint64_t left = index - target;
    while (at >= 32) {
        uint64_t count = core_text_starts32(bytes + at - 32);
        if (count >= left) break;
        left -= count; at -= 32;
    }
    while (left) { --at; if ((bytes[at] & 0xc0) != 0x80) --left; }
    return (core_anchor){target, at};
}

static core_anchor core_text_move(const unsigned char *bytes, uint64_t len, core_anchor from, uint64_t target) {
    core_anchor found = core_text_step(bytes, len, from, target);
    core_text_walked += found.at > from.at ? found.at - from.at : from.at - found.at;
    return found;
}

static void core_text_nearer(core_anchor *best, uint64_t *gap, uint64_t target, core_anchor anchor) {
    uint64_t distance = anchor.scalar <= target ? target - anchor.scalar : anchor.scalar - target;
    if (distance < *gap) { *best = anchor; *gap = distance; }
}

/* The octet where scalar `scalar` of a non-ASCII text begins (its length past the
   end): a walk from the nearest of the text's start, its end when the scalar count
   is cached, its cursor and the caller's `hint`. A walk records where it ended, so
   a scan that moves its index either way pays for the distance moved. */
static uint64_t core_text_locate(const myl_block *text, uint64_t scalar, core_anchor hint) {
    const unsigned char *bytes = (const unsigned char *)text + MYL_HEADER;
    const uint64_t len = (uint64_t)text->len;
    core_anchor best = {0, 0}, cursor;
    uint64_t gap = scalar;
    if (text->kind & MYL_TEXT_SCALARS) {
        uint64_t chars = (uint64_t)text->reserved >> 32;
        if (scalar >= chars) return len;
        core_text_nearer(&best, &gap, scalar, (core_anchor){chars, len});
    }
    core_text_nearer(&best, &gap, scalar, hint);
    if (core_cursor_get(text, &cursor)) core_text_nearer(&best, &gap, scalar, cursor);
    if (!gap) return best.at;
    core_anchor found = core_text_move(bytes, len, best, scalar);
    core_cursor_set(text, found);
    return found.at;
}

uint64_t myl_core_str_offset(const myl_block *text, uint64_t scalar) {
    if (text->kind & MYL_TEXT_ASCII) return scalar < (uint64_t)text->len ? scalar : (uint64_t)text->len;
    return core_text_locate(text, scalar, (core_anchor){0, 0});
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

/* A fresh block of the `len` octets at `bytes`, flagged ASCII only when `ascii` says
   so, with no scan: a span of an ASCII text is ASCII (NEW-CORE-S1-ASCII-1). A clear flag
   is always safe; every reader of the flag falls back to the general path. */
static myl_block *core_octets_copy(const unsigned char *bytes, size_t len, bool ascii) {
    myl_block *text = block_new(MYL_KIND_STR, (int64_t)len, 1);
    memcpy(block_data(text), bytes, len);
    block_data(text)[len] = 0;
    text->len = (int64_t)len;
    text->kind &= ~(MYL_TEXT_ASCII | MYL_TEXT_HASHED | MYL_TEXT_SCALARS | MYL_TEXT_CURSOR | MYL_TEXT_TAIL);
    text->reserved = 0;
    if (ascii) text->kind |= MYL_TEXT_ASCII;
    return text;
}

/* A fresh text of the `len` octets at `bytes`: scanned for its ASCII flag unless its
   source is known ASCII. */
static myl_block *core_text_known(const unsigned char *bytes, size_t len, bool ascii) {
    return ascii ? core_octets_copy(bytes, len, true) : str_from((const char *)bytes, len);
}

myl_block *myl_core_ir_str_from_view(const unsigned char *data, uint64_t len) { return str_from((const char *)data, (size_t)len); }
myl_block *myl_core_ir_str_from_span(const unsigned char *data, uint64_t len, bool ascii) { return core_text_known(data, (size_t)len, ascii); }
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

static inline myl_block *core_text_append_bytes(myl_block *a, const unsigned char *bytes, int64_t count, bool ascii) {
    int64_t len = a->len + count;
    if (a->count != 1) myl_core_s2_unsupported(-1);
    if ((a->kind & (MYL_TEXT_CURSOR | MYL_TEXT_TAIL)) == MYL_TEXT_CURSOR) a->cap = a->len;
    a->kind &= ~(MYL_TEXT_CURSOR | MYL_TEXT_TAIL);
    if (len > a->cap) {
        int64_t cap = a->cap > 0 ? a->cap * 2 : 16;
        if (cap < len) cap = len;
        size_t room;
        myl_block *grown = block_alloc(MYL_KIND_STR, (size_t)cap + 1, &room);
        grown->cap = (int64_t)room - 1;
        grown->len = a->len;
        memcpy(block_data(grown), block_data(a), (size_t)a->len);
        if (count <= 16) core_text_copy_short(block_data(grown) + a->len, bytes, (size_t)count);
        else memcpy(block_data(grown) + a->len, bytes, (size_t)count);
        block_free(a);
        a = grown;
    } else if (count <= 16) core_text_copy_short(block_data(a) + a->len, bytes, (size_t)count);
    else memmove(block_data(a) + a->len, bytes, (size_t)count);
    a->len = len;
    block_data(a)[len] = 0;
    a->kind &= ~(MYL_TEXT_ASCII | MYL_TEXT_HASHED | MYL_TEXT_SCALARS);
    if (ascii) a->kind |= MYL_TEXT_ASCII;
    a->reserved = 0;
    return a;
}

myl_block *myl_core_ir_str_append(myl_block *a, const myl_block *b) {
    bool ascii = (a->kind & b->kind & MYL_TEXT_ASCII) != 0;
    return core_text_append_bytes(a, (const unsigned char *)b + MYL_HEADER, b->len, ascii);
}

myl_block *myl_core_ir_str_append_char(myl_block *a, myl_block *text, uint64_t offset) {
    uint64_t width = myl_core_ir_str_width(text, offset);
    unsigned char bytes[4];
    /* Capture the complete scalar before a cursor reset, growth or alias free.
     * The bounded copy reads exactly width bytes, including three-byte UTF-8. */
    core_text_copy_short(bytes, block_data(text) + offset, (size_t)width);
    bool ascii = width == 1 && (a->kind & MYL_TEXT_ASCII) != 0;
    return core_text_append_bytes(a, bytes, (int64_t)width, ascii);
}

static int64_t core_text_clamp(int64_t index, int64_t len) {
    if (index < 0) index += len;
    return index < 0 ? 0 : index > len ? len : index;
}

/* The octets `text[start:end]` covers: where they begin and how many (two registers). */
typedef struct { uint64_t at, len; } core_text_span;
core_text_span myl_core_ir_str_slice_span(myl_block *text, int64_t start, int64_t end) {
    int64_t len = (int64_t)myl_core_str_chars(text);
    start = core_text_clamp(start, len); end = core_text_clamp(end, len);
    uint64_t a = myl_core_str_offset(text, (uint64_t)start), b = a;
    if (end > start) b = (text->kind & MYL_TEXT_ASCII) ? (uint64_t)end : core_text_locate(text, (uint64_t)end, (core_anchor){(uint64_t)start, a});
    return (core_text_span){a, b - a};
}

myl_block *myl_core_ir_str_slice(myl_block *text, int64_t start, int64_t end) {
    core_text_span span = myl_core_ir_str_slice_span(text, start, end);
    return core_text_known(block_data(text) + span.at, (size_t)span.len, (text->kind & MYL_TEXT_ASCII) != 0);
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
/* The first octet offset at or after `start` where the `wanted_len` octets at `wanted`
   occur in the `len` octets at `data`, or -1. */
static int64_t core_span_find(const unsigned char *data, int64_t len, const unsigned char *wanted, int64_t wanted_len, int64_t start) {
    if (!wanted_len) return start;
    if (wanted_len > len - start) return -1;
    for (unsigned tried = 0; tried < 8; ++tried) {
        const unsigned char *hit = memchr(data + start, wanted[0], (size_t)(len - wanted_len - start + 1));
        if (!hit) return -1;
        start = hit - data;
        /* The rest of a candidate is short in every search here: a loop that stops at
           the first difference costs less than a `memcmp` call per candidate. */
        int64_t same = 1;
        while (same < wanted_len && hit[same] == wanted[same]) ++same;
        if (same == wanted_len) return start;
        ++start;
        if (start > len - wanted_len) return -1;
    }
    /* libc's bounded linear search handles repeated first bytes after a few cheap candidates. */
    extern void *memmem(const void *, size_t, const void *, size_t);
    const unsigned char *hit = memmem(data + start, (size_t)(len - start), wanted, (size_t)wanted_len);
    if (hit) return hit - data;
    return -1;
}

static int64_t core_text_find_bytes(const myl_block *text, const myl_block *needle, int64_t start) {
    return core_span_find(block_data(text), text->len, block_data(needle), needle->len, start);
}

/* Scalars that start in bytes [from, to): every byte that is not a UTF-8 continuation. */
static uint64_t core_text_starts(const unsigned char *bytes, uint64_t from, uint64_t to) {
    uint64_t count = 0;
    core_text_walked += to - from;
    for (; from + 32 <= to; from += 32) count += core_text_starts32(bytes + from);
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

/* NEW-CORE-S1-VIEW-4: the reading helpers over borrowed `(data, length)` spans, each
   answering what its `myl_core_str_*` form answers for the texts those octets spell. */
bool myl_core_span_eq(const unsigned char *a, uint64_t a_len, const unsigned char *b, uint64_t b_len) { return a_len == b_len && memcmp(a, b, (size_t)a_len) == 0; }
uint64_t myl_core_span_chars(const unsigned char *a, uint64_t a_len) { return core_text_starts(a, 0, a_len); }
bool myl_core_span_starts(const unsigned char *a, uint64_t a_len, const unsigned char *b, uint64_t b_len) { return b_len <= a_len && memcmp(a, b, (size_t)b_len) == 0; }
bool myl_core_span_ends(const unsigned char *a, uint64_t a_len, const unsigned char *b, uint64_t b_len) { return b_len <= a_len && memcmp(a + a_len - b_len, b, (size_t)b_len) == 0; }
bool myl_core_span_contains(const unsigned char *a, uint64_t a_len, const unsigned char *b, uint64_t b_len) { return core_span_find(a, (int64_t)a_len, b, (int64_t)b_len, 0) >= 0; }
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
    /* Octets need no ASCII flag; a slice of an ASCII block keeps it, without a scan. */
    myl_block *out = core_octets_copy(block_data(text) + start, (size_t)(end > start ? end - start : 0), (text->kind & MYL_TEXT_ASCII) != 0);
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
    const bool ascii = !unicode || (text->kind & MYL_TEXT_ASCII);
    core_anchor walked = {0, 0};
    for (int64_t i = start; step > 0 ? i < end : i > end;) {
        /* Each element is found from the previous one: the walk costs the step. */
        if (!ascii) walked = core_text_move(block_data(text), (uint64_t)text->len, walked, (uint64_t)i);
        uint64_t at = ascii ? (uint64_t)i : walked.at;
        uint64_t width = unicode ? myl_core_ir_str_width(text, at) : 1;
        memcpy(block_data(out) + out->len, block_data(text) + at, (size_t)width);
        out->len += (int64_t)width;
        if ((step > 0 && i > INT64_MAX - step) || (step < 0 && i < INT64_MIN - step)) break;
        i += step;
    }
    block_data(out)[out->len] = 0;
    core_text_publish_known(out, (text->kind & MYL_TEXT_ASCII) != 0);
    if (!unicode) out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return out;
}

myl_block *myl_core_str_slice_step(myl_block *text, int64_t start, int64_t end, int64_t step) { return core_text_slice_step(text, start, end, step, true); }
myl_block *myl_core_bytes_slice_step(myl_block *text, int64_t start, int64_t end, int64_t step) { return core_text_slice_step(text, start, end, step, false); }

static bool core_text_space(unsigned char ch) { return ch == ' ' || (ch >= 9 && ch <= 13); }
/* Private split-loop cursors use the same six whitespace octets as the list form.
   Out-of-range offsets return unchanged; non-ASCII UTF-8 is never a separator. */
int64_t myl_core_split_ws_start(myl_block *text, int64_t at) {
    if (at < 0) return at;
    while (at < text->len && core_text_space(block_data(text)[at])) ++at;
    return at;
}
int64_t myl_core_split_ws_end(myl_block *text, int64_t at) {
    if (at < 0) return at;
    while (at < text->len && !core_text_space(block_data(text)[at])) ++at;
    return at;
}
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

/* S3 helpers port native_text_methods.c/native_search.c/native_trim.c/native_repr.c
 * into independent one-count blocks. Inputs borrow, outputs own a fresh block. */
static uint32_t core_unicode_next(const unsigned char *data, size_t *at) {
    uint32_t point = data[(*at)++];
    if (point < 0x80) return point;
    unsigned count = point < 0xe0 ? 1 : point < 0xf0 ? 2 : 3;
    point &= count == 1 ? 0x1f : count == 2 ? 0x0f : 0x07;
    while (count--) point = (point << 6) | (data[(*at)++] & 0x3f);
    return point;
}

static size_t core_unicode_previous(const unsigned char *data, size_t at) {
    at--;
    while ((data[at] & 0xc0) == 0x80) at--;
    return at;
}

static bool core_unicode_space(uint32_t point) {
    if (point < 128) return (point >= 9 && point <= 13) || (point >= 28 && point <= 32);
    if (point >= 0x2000 && point <= 0x200a) return true;
    switch (point) {
    case 0x85: case 0xa0: case 0x1680: case 0x2028: case 0x2029:
    case 0x202f: case 0x205f: case 0x3000: return true;
    default: return false;
    }
}

static void core_text_family(myl_block *result, const myl_block *source) {
    core_text_publish(result);
    if (kind_of(source) == MYL_KIND_BYTES) result->kind = (result->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
}

int64_t myl_core_text_bound(uint64_t value) { return value > INT64_MAX ? INT64_MAX : (int64_t)value; }

myl_block *myl_core_text_case(myl_block *input, bool upper) {
    myl_block *result = str_new(input->len);
    memcpy(block_data(result), block_data(input), (size_t)input->len);
    for (int64_t i = 0; i < input->len; i++) {
        unsigned char *value = block_data(result) + i;
        if (upper && *value >= 'a' && *value <= 'z') *value -= 32;
        else if (!upper && *value >= 'A' && *value <= 'Z') *value += 32;
    }
    core_text_family(result, input);
    return result;
}

bool myl_core_text_every(myl_block *input, int32_t property) {
    if (!input->len) return false;
    for (int64_t i = 0; i < input->len; i++) {
        unsigned char value = block_data(input)[i];
        bool good = property == 0 ? value >= '0' && value <= '9' :
                    property == 1 ? (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z') : core_text_space(value);
        if (!good) return false;
    }
    return true;
}

bool myl_core_text_scalar_valid(uint64_t code) {
    return code <= 0x10ffff && (code < 0xd800 || code > 0xdfff);
}

static size_t core_unicode_encode(unsigned char *out, uint32_t point) {
    if (point < 0x80) { out[0] = (unsigned char)point; return 1; }
    if (point < 0x800) {
        out[0] = (unsigned char)(0xc0 | (point >> 6)); out[1] = (unsigned char)(0x80 | (point & 63)); return 2;
    }
    if (point < 0x10000) {
        out[0] = (unsigned char)(0xe0 | (point >> 12)); out[1] = (unsigned char)(0x80 | ((point >> 6) & 63));
        out[2] = (unsigned char)(0x80 | (point & 63)); return 3;
    }
    out[0] = (unsigned char)(0xf0 | (point >> 18)); out[1] = (unsigned char)(0x80 | ((point >> 12) & 63));
    out[2] = (unsigned char)(0x80 | ((point >> 6) & 63)); out[3] = (unsigned char)(0x80 | (point & 63)); return 4;
}

myl_block *myl_core_text_chr(uint64_t code) {
    if (code < 128) return core_ascii_char((unsigned char)code);
    unsigned char raw[4];
    size_t width = core_unicode_encode(raw, (uint32_t)code);
    return str_from((const char *)raw, width);
}

int64_t myl_core_text_ord(myl_block *text) {
    size_t at = 0;
    return (int64_t)core_unicode_next(block_data(text), &at);
}

/* Native search's constant-space two-way reverse matching, including periodic misses. */
typedef struct { const unsigned char *data; size_t length; bool reverse; } core_octets;
typedef struct { size_t first, last; bool valid; } core_search_window;
typedef struct { size_t cut, period; } core_factorization;
static unsigned char core_octet_at(core_octets text, size_t index) {
    return text.data[text.reverse ? text.length - 1 - index : index];
}

static core_factorization core_maximal_suffix(core_octets needle, bool order) {
    size_t suffix = SIZE_MAX, candidate = 0, offset = 1, period = 1;
    while (offset < needle.length - candidate) {
        unsigned char a = core_octet_at(needle, suffix + offset), b = core_octet_at(needle, candidate + offset);
        if (a == b) {
            if (offset == period) { candidate += period; offset = 1; }
            else offset++;
        } else if (order ? a > b : a < b) { candidate += offset; offset = 1; period = candidate - suffix; }
        else { suffix = candidate++; offset = period = 1; }
    }
    return (core_factorization){suffix + 1, period};
}

static size_t core_periodic_memory(core_octets needle, core_factorization *split) {
    for (size_t i = 0; i < split->cut; i++) {
        if (core_octet_at(needle, i) != core_octet_at(needle, i + split->period)) {
            size_t right = needle.length - split->cut, left = split->cut ? split->cut - 1 : 0;
            split->period = (left > right ? left : right) + 1;
            return 0;
        }
    }
    return needle.length - split->period;
}

static size_t core_reverse_find(core_octets haystack, core_octets needle) {
    core_factorization a = core_maximal_suffix(needle, false), b = core_maximal_suffix(needle, true);
    core_factorization split = a.cut > b.cut ? a : b;
    size_t memory_after = core_periodic_memory(needle, &split), memory = 0, at = 0;
    while (at <= haystack.length - needle.length) {
        size_t i = split.cut > memory ? split.cut : memory;
        while (i < needle.length && core_octet_at(needle, i) == core_octet_at(haystack, at + i)) i++;
        if (i < needle.length) { at += i - split.cut + 1; memory = 0; continue; }
        i = split.cut;
        while (i > memory && core_octet_at(needle, i - 1) == core_octet_at(haystack, at + i - 1)) i--;
        if (i <= memory) return haystack.length - needle.length - at;
        at += split.period; memory = memory_after;
    }
    return SIZE_MAX;
}

static size_t core_search_endpoint(size_t length, int64_t value, bool start) {
    if (value >= 0) return start || (uint64_t)value <= length ? (size_t)value : length;
    uint64_t distance = (uint64_t)(-(value + 1)) + 1;
    return distance > length ? 0 : length - (size_t)distance;
}

static core_search_window core_window(size_t length, int64_t start, int64_t end) {
    size_t first = core_search_endpoint(length, start, true), last = core_search_endpoint(length, end, false);
    return (core_search_window){first, last, first <= last && first <= length};
}

enum { CORE_FIND, CORE_RFIND, CORE_INDEX, CORE_RINDEX, CORE_COUNT, CORE_PREFIX, CORE_SUFFIX };
static int64_t core_empty_answer(core_search_window bounds, int mode) {
    if (!bounds.valid) return mode == CORE_COUNT || mode >= CORE_PREFIX ? 0 : -1;
    if (mode == CORE_COUNT) return (int64_t)(bounds.last - bounds.first) + 1;
    if (mode >= CORE_PREFIX) return 1;
    return (int64_t)(mode == CORE_RFIND || mode == CORE_RINDEX ? bounds.last : bounds.first);
}

static int64_t core_search_octets(core_octets input, core_octets needle, int mode) {
    if (needle.length > input.length) return mode >= CORE_COUNT ? 0 : -1;
    if (mode == CORE_COUNT) {
        int64_t count = 0;
        size_t at = 0;
        extern void *memmem(const void *, size_t, const void *, size_t);
        while (at <= input.length - needle.length) {
            const unsigned char *hit = memmem(input.data + at, input.length - at, needle.data, needle.length);
            if (!hit) break;
            count++; at = (size_t)(hit - input.data) + needle.length;
        }
        return count;
    }
    if (mode >= CORE_PREFIX) {
        size_t at = mode == CORE_PREFIX ? 0 : input.length - needle.length;
        return memcmp(input.data + at, needle.data, needle.length) == 0;
    }
    size_t found;
    if (mode == CORE_RFIND || mode == CORE_RINDEX) {
        input.reverse = needle.reverse = true; found = core_reverse_find(input, needle);
    } else {
        extern void *memmem(const void *, size_t, const void *, size_t);
        const unsigned char *hit = memmem(input.data, input.length, needle.data, needle.length);
        found = hit ? (size_t)(hit - input.data) : SIZE_MAX;
    }
    return found == SIZE_MAX ? -1 : (int64_t)found;
}

int64_t myl_core_text_search(myl_block *input, myl_block *needle, int64_t start, int64_t end, int32_t mode) {
    core_search_window bounds = core_window((size_t)myl_core_str_chars(input), start, end);
    if (!needle->len) return core_empty_answer(bounds, mode);
    if (!bounds.valid) return mode >= CORE_COUNT ? 0 : -1;
    const bool ascii = (input->kind & MYL_TEXT_ASCII) != 0;
    size_t first = (size_t)myl_core_str_offset(input, bounds.first), last = (size_t)bounds.last;
    if (!ascii) last = (size_t)core_text_locate(input, bounds.last, (core_anchor){bounds.first, first});
    int64_t found = core_search_octets((core_octets){block_data(input) + first, last - first, false}, (core_octets){block_data(needle), (size_t)needle->len, false}, mode);
    if (found < 0 || mode >= CORE_COUNT) return found;
    if (ascii) return (int64_t)(first + (size_t)found);
    /* Count from the nearer window end, and leave the cursor on the match: the next
       call of a scan starts or ends there (NEW-CORE-TEXT-CURSOR-1). */
    const uint64_t hit = first + (uint64_t)found;
    const uint64_t index = hit - first <= last - hit ? bounds.first + core_text_starts(block_data(input), first, hit) : bounds.last - core_text_starts(block_data(input), hit, last);
    core_cursor_set(input, (core_anchor){index, hit});
    return (int64_t)index;
}

int64_t myl_core_bytes_search(myl_block *input, myl_block *needle, int64_t start, int64_t end, int32_t mode) {
    core_search_window bounds = core_window((size_t)input->len, start, end);
    if (!needle->len) return core_empty_answer(bounds, mode);
    if (!bounds.valid) return mode >= CORE_COUNT ? 0 : -1;
    int64_t found = core_search_octets((core_octets){block_data(input) + bounds.first, bounds.last - bounds.first, false}, (core_octets){block_data(needle), (size_t)needle->len, false}, mode);
    return found < 0 || mode >= CORE_COUNT ? found : found + (int64_t)bounds.first;
}

/* Deterministic direct scalar membership, as native_trim.c; temporary wide bits
 * belong to this call, and are freed before any counted result is published. */
enum { CORE_SMALL_POINTS = 32, CORE_UNICODE_WORDS = 0x110000 / 64 };
typedef struct { uint64_t ascii[4]; uint32_t small[CORE_SMALL_POINTS]; size_t count; uint64_t *wide; } core_scalar_set;
static bool core_set_contains(const core_scalar_set *set, uint32_t point) {
    if (point < 256) return (set->ascii[point / 64] >> (point % 64)) & 1;
    if (set->wide) return (set->wide[point / 64] >> (point % 64)) & 1;
    for (size_t i = 0; i < set->count; i++) if (set->small[i] == point) return true;
    return false;
}
static void core_set_add(core_scalar_set *set, uint32_t point) {
    if (point < 256) { set->ascii[point / 64] |= UINT64_C(1) << (point % 64); return; }
    if (core_set_contains(set, point)) return;
    if (!set->wide && set->count == CORE_SMALL_POINTS) {
        set->wide = calloc(CORE_UNICODE_WORDS, sizeof(uint64_t));
        if (!set->wide) out_of_memory();
        for (size_t i = 0; i < set->count; i++) set->wide[set->small[i] / 64] |= UINT64_C(1) << (set->small[i] % 64);
    }
    if (set->wide) set->wide[point / 64] |= UINT64_C(1) << (point % 64);
    else set->small[set->count++] = point;
}

myl_block *myl_core_text_trim(myl_block *input, myl_block *chars, int32_t ends, bool explicit_chars) {
    core_scalar_set set = {0};
    if (explicit_chars) for (size_t at = 0; at < (size_t)chars->len;) core_set_add(&set, core_unicode_next(block_data(chars), &at));
    size_t low = 0, high = (size_t)input->len;
    if (ends != 2) while (low < high) {
        size_t next = low;
        uint32_t point = core_unicode_next(block_data(input), &next);
        if (!(explicit_chars ? core_set_contains(&set, point) : core_unicode_space(point))) break;
        low = next;
    }
    if (ends != 1) while (high > low) {
        size_t next = core_unicode_previous(block_data(input), high), cursor = next;
        uint32_t point = core_unicode_next(block_data(input), &cursor);
        if (!(explicit_chars ? core_set_contains(&set, point) : core_unicode_space(point))) break;
        high = next;
    }
    free(set.wide);
    return core_text_known(block_data(input) + low, high - low, (input->kind & MYL_TEXT_ASCII) != 0);
}

myl_block *myl_core_bytes_trim(myl_block *input, myl_block *chars, int32_t ends, bool explicit_chars) {
    uint64_t set[4] = {0};
    if (explicit_chars) for (int64_t i = 0; i < chars->len; i++) {
        unsigned char value = block_data(chars)[i]; set[value / 64] |= UINT64_C(1) << (value % 64);
    } else for (unsigned point = 0; point < 128; point++) if (core_text_space((unsigned char)point)) set[point / 64] |= UINT64_C(1) << (point % 64);
    int64_t first = 0, last = input->len;
    if (ends != 2) while (first < last) {
        unsigned char value = block_data(input)[first];
        if (!((set[value / 64] >> (value % 64)) & 1)) break;
        first++;
    }
    if (ends != 1) while (last > first) {
        unsigned char value = block_data(input)[last - 1];
        if (!((set[value / 64] >> (value % 64)) & 1)) break;
        last--;
    }
    return myl_core_bytes_slice(input, first, last);
}

myl_block *myl_core_text_replace(myl_block *input, myl_block *needle, myl_block *insert) {
    int64_t hits = myl_core_bytes_search(input, needle, 0, INT64_MAX, CORE_COUNT);
    uint64_t kept = (uint64_t)(input->len - hits * needle->len);
    if (insert->len && (uint64_t)hits > (uint64_t)INT64_MAX / (uint64_t)insert->len) out_of_memory();
    uint64_t added = (uint64_t)hits * (uint64_t)insert->len;
    if (added > (uint64_t)INT64_MAX - kept) out_of_memory();
    myl_block *result = str_new((int64_t)(kept + added));
    int64_t at = 0, cursor = 0;
    for (int64_t left = hits; left; left--) {
        int64_t hit = core_text_find_bytes(input, needle, cursor);
        memcpy(block_data(result) + at, block_data(input) + cursor, (size_t)(hit - cursor));
        at += hit - cursor;
        memcpy(block_data(result) + at, block_data(insert), (size_t)insert->len);
        at += insert->len; cursor = hit + needle->len;
    }
    memcpy(block_data(result) + at, block_data(input) + cursor, (size_t)(input->len - cursor));
    core_text_family(result, input);
    return result;
}

static myl_block *core_append_line(myl_block *list, myl_block *input, size_t start, size_t end) {
    myl_block *piece = str_from((const char *)block_data(input) + start, end - start);
    core_text_family(piece, input);
    if (list->len == list->cap) list = myl_core_list_grow(list, 8);
    ((myl_block **)block_data(list))[list->len++] = piece;
    return list;
}

myl_block *myl_core_text_splitlines(myl_block *input) {
    myl_block *list = myl_core_list_new_slow(0, 8);
    list->reserved = (int64_t)(intptr_t)core_text_list_layout;
    size_t start = 0, cursor = 0;
    while (cursor < (size_t)input->len) {
        unsigned char octet = block_data(input)[cursor];
        if (octet != '\n' && octet != '\r') { cursor++; continue; }
        list = core_append_line(list, input, start, cursor);
        cursor++;
        if (octet == '\r' && cursor < (size_t)input->len && block_data(input)[cursor] == '\n') cursor++;
        start = cursor;
    }
    if (start < (size_t)input->len) list = core_append_line(list, input, start, (size_t)input->len);
    return list;
}

myl_block *myl_core_text_zfill(myl_block *input, int64_t width) {
    uint64_t length = kind_of(input) == MYL_KIND_BYTES ? (uint64_t)input->len : myl_core_str_chars(input);
    uint64_t target = width <= 0 ? 0 : (uint64_t)width > UINT32_MAX ? UINT32_MAX : (uint64_t)width;
    uint64_t pad = target > length ? target - length : 0;
    myl_block *result = str_new(input->len + (int64_t)pad);
    size_t keep = input->len && (block_data(input)[0] == '+' || block_data(input)[0] == '-') ? 1 : 0;
    if (keep) block_data(result)[0] = block_data(input)[0];
    memset(block_data(result) + keep, '0', (size_t)pad);
    memcpy(block_data(result) + keep + pad, block_data(input) + keep, (size_t)input->len - keep);
    core_text_family(result, input);
    return result;
}

int64_t myl_core_bytes_find_any(myl_block *input, myl_block *values, int64_t start) {
    size_t length=input->len;
    size_t at = start<0 ? 0 : ((uint64_t)start>length ? length : (size_t)start);
    if (at>=length || !values->len) return -1;
    const unsigned char *bytes=block_data(input);
    const unsigned char *set=block_data(values);
    if (values->len==1) {
        const unsigned char *found=memchr(bytes+at,set[0],length-at);
        return found ? (int64_t)(found-bytes) : -1;
    }
    if (values->len==2 && set[0]!=set[1]) {
        /* A window at a time, doubling from 64 octets, and the second octet only
           up to the first's hit: a search stops within twice the distance to its
           answer, so a loop of searches over input missing one octet stays
           linear instead of rescanning to the end on every call. */
        size_t window=64;
        while (at<length) {
            size_t span=length-at<window ? length-at : window;
            const unsigned char *first=memchr(bytes+at,set[0],span);
            size_t bound=first ? (size_t)(first-(bytes+at)) : span;
            const unsigned char *second=bound ? memchr(bytes+at,set[1],bound) : NULL;
            if (second) return (int64_t)(second-bytes);
            if (first) return (int64_t)(first-bytes);
            at+=span;
            if (window<=SIZE_MAX/2) window*=2;
        }
        return -1;
    }
    uint64_t members[4]={0,0,0,0};
    for (size_t i=0;i<values->len;i++) members[set[i]>>6]|=(uint64_t)1<<(set[i]&63);
    for (size_t i=at;i<length;i++) if (members[bytes[i]>>6]>>(bytes[i]&63)&1) return (int64_t)i;
    return -1;
}

/* Validation/count ported from native_bytes.c, with -1 the invalid marker. */
int64_t myl_core_span_utf8_count(const unsigned char *bytes, uint64_t length) {
    uint64_t at = 0;
    int64_t count = 0;
    while (at < length) {
        while (at + 8 <= length) {
            uint64_t word;
            memcpy(&word, bytes + at, 8);
            if (word & UINT64_C(0x8080808080808080)) break;
            at += 8; count += 8;
        }
        if (at < length && bytes[at] < 0x80) { at++; count++; continue; }
        if (at == length) break;
        unsigned char first = bytes[at];
        unsigned remaining;
        uint32_t minimum;
        if (first >= 0xc2 && first <= 0xdf) { remaining = 1; minimum = 0x80; }
        else if (first >= 0xe0 && first <= 0xef) { remaining = 2; minimum = 0x800; }
        else if (first >= 0xf0 && first <= 0xf4) { remaining = 3; minimum = 0x10000; }
        else return -1;
        if (remaining > length - at - 1) return -1;
        uint32_t point = first & ((1u << (6 - remaining)) - 1u);
        for (unsigned index = 0; index < remaining; index++) {
            unsigned char next = bytes[at + 1 + index];
            if ((next & 0xc0) != 0x80) return -1;
            point = (point << 6) | (next & 63u);
        }
        if (point < minimum || point > 0x10ffff || (point >= 0xd800 && point <= 0xdfff)) return -1;
        at += remaining + 1; count++;
    }
    return count;
}

int64_t myl_core_bytes_utf8_count(myl_block *bytes) { return myl_core_span_utf8_count(block_data(bytes), (uint64_t)bytes->len); }
int64_t myl_core_bytes_utf8_count_range(myl_block *bytes, int64_t start, int64_t end) {
    size_t first = core_search_endpoint((size_t)bytes->len, start, false), last = core_search_endpoint((size_t)bytes->len, end, false);
    return myl_core_span_utf8_count(block_data(bytes) + first, last > first ? last - first : 0);
}
myl_block *myl_core_bytes_decode_text(myl_block *bytes) { return str_from((const char *)block_data(bytes), (size_t)bytes->len); }
myl_block *myl_core_bytes_utf8_error(void) { return str_from("invalid UTF-8 in byte string", sizeof("invalid UTF-8 in byte string") - 1); }

/* Packed PY-FSTRING-SPEC-1 text layout, ported from format_spec.zig.
 * Only fields accepted by its text resolver reach this entry. */
myl_block *myl_core_text_format(myl_block *input, uint64_t spec) {
    uint32_t fill = (uint32_t)(spec & 0x1fffff);
    unsigned alignment = (unsigned)((spec >> 21) & 7);
    uint64_t width = (spec >> 49) & 0xfff;
    uint64_t scalars = myl_core_str_chars(input);
    if ((spec >> 36) & 1) {
        uint64_t precision = (spec >> 37) & 0xfff;
        if (scalars > precision) scalars = precision;
    }
    uint64_t bytes = myl_core_str_offset(input, scalars), pad = width > scalars ? width - scalars : 0;
    uint64_t left = alignment == 2 ? pad : alignment == 3 ? pad / 2 : 0;
    unsigned char raw[4];
    size_t fill_bytes = core_unicode_encode(raw, fill);
    myl_block *result = str_new((int64_t)(bytes + pad * fill_bytes));
    unsigned char *out = block_data(result);
    for (uint64_t i = 0; i < left; i++) { memcpy(out, raw, fill_bytes); out += fill_bytes; }
    memcpy(out, block_data(input), (size_t)bytes); out += bytes;
    for (uint64_t i = left; i < pad; i++) { memcpy(out, raw, fill_bytes); out += fill_bytes; }
    core_text_publish(result);
    return result;
}

/* Scalar repr ports native_repr.c's quote/escape/Unicode16 printability rules. */
typedef struct { const unsigned char *data; size_t length; bool bytes; unsigned char quote; } core_repr_input;
typedef struct { unsigned char *data; size_t octets; } core_repr_output;
static bool core_printable(uint32_t point) {
    size_t low = 0, high = sizeof core_nonprintable / sizeof core_nonprintable[0];
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (point < core_nonprintable[middle][0]) high = middle;
        else if (point > core_nonprintable[middle][1]) low = middle + 1;
        else return false;
    }
    return true;
}
static void core_repr_bytes(core_repr_output *out, const unsigned char *data, size_t length) {
    if (length > SIZE_MAX - out->octets) out_of_memory();
    if (out->data) memcpy(out->data + out->octets, data, length);
    out->octets += length;
}
static void core_repr_escape(core_repr_output *out, uint32_t point, unsigned digits) {
    static const unsigned char hex[] = "0123456789abcdef";
    unsigned char escaped[10] = {'\\', digits == 2 ? 'x' : digits == 4 ? 'u' : 'U'};
    for (unsigned i = 0; i < digits; i++) escaped[2 + i] = hex[(point >> (4 * (digits - 1 - i))) & 15];
    core_repr_bytes(out, escaped, digits + 2);
}
static void core_repr_point(core_repr_output *out, core_repr_input input, uint32_t point, size_t first, size_t last) {
    unsigned char escaped[2] = {'\\', 0};
    if (point == '\t') escaped[1] = 't';
    else if (point == '\n') escaped[1] = 'n';
    else if (point == '\r') escaped[1] = 'r';
    else if (point == '\\' || point == input.quote) escaped[1] = (unsigned char)point;
    if (escaped[1]) { core_repr_bytes(out, escaped, 2); return; }
    if (!(input.bytes ? point >= 32 && point < 127 : core_printable(point))) {
        core_repr_escape(out, point, point < 256 ? 2 : point < 65536 ? 4 : 8); return;
    }
    core_repr_bytes(out, input.data + first, last - first);
}
static void core_repr_render(core_repr_input input, core_repr_output *out) {
    if (input.bytes) core_repr_bytes(out, (const unsigned char *)"b", 1);
    core_repr_bytes(out, &input.quote, 1);
    for (size_t at = 0; at < input.length;) {
        size_t first = at;
        uint32_t point = input.bytes ? input.data[at++] : core_unicode_next(input.data, &at);
        core_repr_point(out, input, point, first, at);
    }
    core_repr_bytes(out, &input.quote, 1);
}
myl_block *myl_core_text_repr(myl_block *source, bool bytes) {
    core_repr_input input = {block_data(source), (size_t)source->len, bytes, '\''};
    if (memchr(input.data, '\'', input.length) && !memchr(input.data, '"', input.length)) input.quote = '"';
    core_repr_output measured = {0};
    core_repr_render(input, &measured);
    if (measured.octets > INT64_MAX) out_of_memory();
    myl_block *result = str_new((int64_t)measured.octets);
    core_repr_output output = {block_data(result), 0};
    core_repr_render(input, &output);
    core_text_publish(result);
    return result;
}
