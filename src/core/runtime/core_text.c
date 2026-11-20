/* S2 text ABI: shared str/bytes leaf blocks; header flags and cache are §3.1. */
enum { MYL_TEXT_ASCII = 1u << 8, MYL_TEXT_HASHED = 2u << 8,
       MYL_TEXT_SCALARS = 4u << 8, MYL_TEXT_CURSOR = 8u << 8, MYL_TEXT_TAIL = 16u << 8 };

/* P1F-6 (B1). Facts about a text (hash, scalar count, cursor) are cached in two ways.
   Before the pool starts, as always: a flag in `kind` with the value in `reserved` (hash low 32
   bits, scalar count bits 32-61) or in `cap` (cursor).  After it starts, the rule of
   OWNERSHIP-TEXT-READONLY-1 (core_rt.c, core_text_can_cache) holds: `kind` and the data are not
   written, so emitted code (which reads the ASCII and HASHED bits of kind, and the hash word
   only behind HASHED) races nothing, and facts live in the words themselves, each
   self-validated by a bit that a capacity or count never uses:
     reserved bit 63: hash valid (low 32 bits = hash); bit 62: scalar count valid (bits 32-61 = count);
     cap bit 63: cursor valid (bits 0-62 = scalar << 32 | at).
   Every post-start write is one atomic RMW of the same value (the facts are deterministic). A text
   hashed before the pool started keeps its hash word unwritten, since emitted code reads it there.
   Pre-start scalar counts and cursors are limited to 2^30 and 2^31, so the bits stay clear. */
#define MYL_TEXT_HASH_VALID (UINT64_C(1) << 63)
#define MYL_TEXT_COUNT_VALID (UINT64_C(1) << 62)
#define MYL_TEXT_CURSOR_VALID (UINT64_C(1) << 63)
#define MYL_TEXT_COUNT_MASK ((UINT64_C(1) << 30) - 1)
static uint32_t core_text_kind(const myl_block *text) { return __atomic_load_n(&text->kind, __ATOMIC_ACQUIRE); }
static uint64_t core_text_meta(const myl_block *text) { return (uint64_t)__atomic_load_n(&text->reserved, __ATOMIC_ACQUIRE); }
static void core_text_meta_or(myl_block *text, uint64_t bits) { __atomic_fetch_or(&text->reserved, (int64_t)bits, __ATOMIC_RELAXED); }
static void core_text_flag(myl_block *text, uint32_t flag) { __atomic_fetch_or(&text->kind, flag, __ATOMIC_RELEASE); }

/* Octets the scalar-position walks of this process have stepped over. With
   SELKA_CORE_TEXTWALK=1 the total is reported on stderr at exit, so a test can bound
   the lookup work of a scan without timing it (NEW-CORE-TEXT-CURSOR-1). */
static void core_text_walk_report(void) {
#if defined(MYL_BARE)
    /* A bare CPU has no environment to ask for the report. */
    return;
#endif
    const char *flag = getenv("SELKA_CORE_TEXTWALK");
    if (!flag || strcmp(flag, "1") != 0) return;
    char text[64];
    int len = snprintf(text, sizeof text, "myl-core textwalk: %llu octets\n", (unsigned long long)core_thread_walk_total());
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
#if defined(__SIZEOF_INT128__)
    __uint128_t product = (__uint128_t)a * b;
    return (uint64_t)product ^ (uint64_t)(product >> 64);
#else
    /* A 32-bit CPU (MYL_BARE): the same 128-bit product from four 32-bit ones, so the hash is the same. */
    uint64_t high, low = myl_bare_multiply_wide(a, b, &high);
    return low ^ high;
#endif
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
    uint32_t kind = core_text_kind(text);
    uint64_t meta = core_text_meta(text);
    if (kind & MYL_TEXT_HASHED) return (uint32_t)meta;
    if (meta & MYL_TEXT_HASH_VALID) return (uint32_t)meta;
    uint32_t folded = myl_core_span_hash((const unsigned char *)text + MYL_HEADER, (uint64_t)text->len);
    if (core_text_can_cache(text)) {
        myl_block *mutable = (myl_block *)text;
        if (core_parallel()) core_text_meta_or(mutable, MYL_TEXT_HASH_VALID | folded);
        else {
            core_text_meta_or(mutable, folded);
            core_text_flag(mutable, MYL_TEXT_HASHED);
        }
    }
    return folded;
}

/* Equal lengths, then the bytes. Texts of one length that differ usually differ near
   an end, so a pair past 256 bytes compares its first and last eight bytes before the
   bulk compare, which a mismatch at the end would otherwise pay for in full (the old
   runtime's `myl_native_text_equal`). Shorter pairs go straight to `memcmp`: an extra
   path for them costs more than it saves. */
/* Two octet runs of one length compare as main's text equality does: the hash and the first and last
   eight octets of a long run decide the common unequal cases before memcmp (C9 3a). */

bool myl_core_str_eq(const myl_block *a, const myl_block *b) {
    if (a == b) return true;
    if (a->len != b->len) return false;
    uint32_t kind_a = core_text_kind(a), kind_b = core_text_kind(b);
    uint64_t meta_a = core_text_meta(a), meta_b = core_text_meta(b);
    bool hashed_a = (kind_a & MYL_TEXT_HASHED) || (meta_a & MYL_TEXT_HASH_VALID);
    bool hashed_b = (kind_b & MYL_TEXT_HASHED) || (meta_b & MYL_TEXT_HASH_VALID);
    if (hashed_a && hashed_b && (uint32_t)meta_a != (uint32_t)meta_b) return false;
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
    uint32_t kind = core_text_kind(text);
    if (kind & MYL_TEXT_ASCII) return (uint64_t)text->len;
    uint64_t meta = core_text_meta(text);
    if ((kind & MYL_TEXT_SCALARS) || (meta & MYL_TEXT_COUNT_VALID)) return (meta >> 32) & MYL_TEXT_COUNT_MASK;
    const unsigned char *bytes = (const unsigned char *)text + MYL_HEADER;
    uint64_t scalars = 0;
    core_text_walked += (uint64_t)text->len;
    for (int64_t i = 0; i < text->len; ++i) scalars += (bytes[i] & 0xc0) != 0x80;
    if (core_text_can_cache(text) && scalars <= MYL_TEXT_COUNT_MASK) {
        myl_block *mutable = (myl_block *)text;
        if (core_parallel()) {
            /* A text hashed before the pool started keeps its hash word unwritten (emitted code reads it there). */
            if (!(kind & MYL_TEXT_HASHED)) core_text_meta_or(mutable, MYL_TEXT_COUNT_VALID | (scalars << 32));
        } else {
            core_text_meta_or(mutable, scalars << 32);
            core_text_flag(mutable, MYL_TEXT_SCALARS);
        }
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

/* A cursor in `cap` (a text with no spare capacity; `cap` is then its length): before the pool starts the
   word holds the bare cursor under MYL_TEXT_CURSOR; after it, bit 63 marks it, and a negative `cap` means
   "no spare capacity" to every owner-side capacity test, so an owner that later appends grows the text. */
static bool core_cursor_get(const myl_block *text, core_anchor *cursor) {
    uint32_t kind = core_text_kind(text);
    uint64_t packed;
    if (kind & MYL_TEXT_TAIL) {
        if (!(kind & MYL_TEXT_CURSOR)) return false;
        memcpy(&packed, core_cursor_tail(text), 8);
    } else {
        int64_t cap = __atomic_load_n(&text->cap, __ATOMIC_RELAXED);
        if (!(kind & MYL_TEXT_CURSOR) && cap >= 0) return false;
        packed = (uint64_t)cap & ~MYL_TEXT_CURSOR_VALID;
    }
    *cursor = (core_anchor){packed >> 32, (uint32_t)packed};
    return true;
}

static void core_cursor_set(const myl_block *text, core_anchor cursor) {
    if (!core_text_can_cache(text) || text->len < 256 || text->len > UINT32_MAX || cursor.scalar >= (UINT64_C(1) << 31)) return;
    myl_block *mutable = (myl_block *)text;
    uint64_t packed = cursor.scalar << 32 | cursor.at;
    uint32_t kind = core_text_kind(text);
    if (core_parallel()) {
        if (kind & MYL_TEXT_TAIL) return;  /* a tail cursor is written only before the pool starts */
        int64_t cap = __atomic_load_n(&text->cap, __ATOMIC_RELAXED);
        if (!(kind & MYL_TEXT_CURSOR) && cap >= 0 && cap != text->len) return;  /* spare capacity: no cursor word */
        __atomic_store_n(&mutable->cap, (int64_t)(packed | MYL_TEXT_CURSOR_VALID), __ATOMIC_RELAXED);
        return;
    }
    if (!(kind & MYL_TEXT_CURSOR)) {
        if (text->cap == text->len) core_text_flag(mutable, MYL_TEXT_CURSOR);
        else if (text->cap - text->len >= 8) core_text_flag(mutable, MYL_TEXT_CURSOR | MYL_TEXT_TAIL);
        else return;
        kind = core_text_kind(text);
    }
    if (kind & MYL_TEXT_TAIL) memcpy(core_cursor_tail(text), &packed, 8);
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
static inline __attribute__((always_inline)) uint64_t core_text_locate_core(const myl_block *text, const unsigned char *bytes, uint64_t len, uint64_t scalar, core_anchor hint) {
    core_anchor best = {0, 0}, cursor;
    uint64_t gap = scalar;
    uint64_t meta = core_text_meta(text);
    if ((core_text_kind(text) & MYL_TEXT_SCALARS) || (meta & MYL_TEXT_COUNT_VALID)) {
        uint64_t chars = (meta >> 32) & MYL_TEXT_COUNT_MASK;
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
static uint64_t core_text_locate(const myl_block *text, uint64_t scalar, core_anchor hint) {
    return core_text_locate_core(text, TEXT_BYTES(text), (uint64_t)text->len, scalar, hint);
}

static uint64_t core_text_locate_at(const myl_block *text, const unsigned char *bytes, uint64_t len, uint64_t scalar, core_anchor hint) {
    return core_text_locate_core(text, bytes, len, scalar, hint);
}

uint64_t myl_core_str_offset(const myl_block *text, uint64_t scalar) {
    if (text->kind & MYL_TEXT_ASCII) return scalar < (uint64_t)text->len ? scalar : (uint64_t)text->len;
    return core_text_locate(text, scalar, (core_anchor){0, 0});
}

static uint64_t core_text_chars(const myl_block *text, const unsigned char *bytes, uint64_t len) {
    uint32_t kind = core_text_kind(text);
    if (kind & MYL_TEXT_ASCII) return len;
    uint64_t meta = core_text_meta(text);
    if ((kind & MYL_TEXT_SCALARS) || (meta & MYL_TEXT_COUNT_VALID)) return (meta >> 32) & MYL_TEXT_COUNT_MASK;
    uint64_t scalars = 0;
    core_text_walked += len;
    for (uint64_t i = 0; i < len; ++i) scalars += (bytes[i] & 0xc0) != 0x80;
    if (core_text_can_cache(text) && scalars <= MYL_TEXT_COUNT_MASK) {
        myl_block *mutable = (myl_block *)text;
        if (core_parallel()) {
            if (!(kind & MYL_TEXT_HASHED)) core_text_meta_or(mutable, MYL_TEXT_COUNT_VALID | (scalars << 32));
        } else {
            core_text_meta_or(mutable, scalars << 32);
            core_text_flag(mutable, MYL_TEXT_SCALARS);
        }
    }
    return scalars;
}

static uint64_t core_text_offset(const myl_block *text, const unsigned char *bytes, uint64_t len, uint64_t scalar) {
    if (text->kind & MYL_TEXT_ASCII) return scalar < len ? scalar : len;
    return core_text_locate_at(text, bytes, len, scalar, (core_anchor){0, 0});
}

/* The count and offset of octets that a sentinel-or-owner argument gives (C9 3a): the owner's cached facts
   are read exactly as main reads them, and nothing is written into a sentinel (`core_text_can_cache`). */



/* The octet width of the scalar at `offset` in the `len` octets at `bytes` (C9 2b: a span, so a view needs no block). */
static uint64_t core_text_width(const unsigned char *bytes, uint64_t len, uint64_t offset) {
    if (offset >= len) myl_core_s2_unsupported(-1);
    unsigned char c = bytes[offset];
    return c < 0x80 ? 1 : c < 0xe0 ? 2 : c < 0xf0 ? 3 : 4;
}

uint64_t myl_core_ir_str_width(myl_block *text, uint64_t offset) { return core_text_width(block_data(text), (uint64_t)text->len, offset); }

uint32_t myl_core_ir_str_code(myl_block *text, uint64_t offset) {
    uint64_t width = myl_core_ir_str_width(text, offset);
    const unsigned char *bytes = block_data(text) + offset;
    uint32_t point = bytes[0] & (width == 1 ? 0x7f : width == 2 ? 0x1f : width == 3 ? 0xf : 7);
    for (uint64_t i = 1; i < width; ++i) point = (point << 6) | (bytes[i] & 0x3f);
    return point;
}

/* Runtime table of immortal one-byte scalars. Initialized before its first use. */
static struct { myl_block header; unsigned char data[32]; } core_ascii[128];
static pthread_once_t core_ascii_once = PTHREAD_ONCE_INIT;
static void core_ascii_initialize(void) {
    for (unsigned i = 0; i < 128; ++i) {
        core_ascii[i].header = (myl_block){MYL_STATIC_HEADER MYL_KIND_STR | MYL_TEXT_ASCII | MYL_TEXT_SCALARS, 1, 1, INT64_C(1) << 32};
        core_ascii[i].data[0] = (unsigned char)i;
        core_ascii[i].header.reserved |= myl_core_str_hash(&core_ascii[i].header);
        core_ascii[i].header.kind |= MYL_TEXT_HASHED;
    }
}
static myl_block *core_ascii_char(unsigned char ch) {
    pthread_once(&core_ascii_once, core_ascii_initialize);
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

/* PY-FSTRING-1: a text block with room for `capacity` octets and length zero, so
   a format string fills one buffer it reserved from its pieces' exact lengths.
   An empty text is the empty ASCII string: each append then keeps that claim
   only while the octets it adds are ASCII too. */
myl_block *myl_core_str_reserve(int64_t capacity) {
    if (capacity < 0) out_of_memory();
    myl_block *text = block_new(MYL_KIND_STR, capacity, 1);
    text->len = 0;
    text->kind |= MYL_TEXT_ASCII;
    block_data(text)[0] = 0;
    return text;
}

/* The octets `a[0:alen]` then `b[0:blen]` in a new block: both operands are read in place (C9). */
static myl_block *core_text_concat(const unsigned char *a, uint64_t alen, const unsigned char *b, uint64_t blen) {
    myl_block *text = str_new((int64_t)(alen + blen));
    memcpy(block_data(text), a, (size_t)alen);
    memcpy(block_data(text) + alen, b, (size_t)blen);
    core_text_publish(text);
    return text;
}
myl_block *myl_core_str_concat(const unsigned char *a, uint64_t a_len, const unsigned char *b, uint64_t b_len) {
    return core_text_concat(a, a_len, b, b_len);
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

/* Expose the bounded scalar capture to each of the two append wrappers. */
__attribute__((always_inline))
static inline myl_block *core_text_append_bytes(myl_block *a, const unsigned char *bytes, int64_t count, bool ascii) {
    if (a->len < 0 || count < 0 || count > INT64_MAX - a->len) out_of_memory();
    int64_t len = a->len + count;
    const bool static_source = (a->kind & MYL_STATIC_STORAGE) != 0;
    /* An immortal source is copied directly into the final append allocation.
     * Never alter its header, and never allocate an intermediate owned shell. */
    if (!static_source) {
        if ((a->kind & (MYL_TEXT_CURSOR | MYL_TEXT_TAIL)) == MYL_TEXT_CURSOR) a->cap = a->len;
        a->kind &= ~(MYL_TEXT_CURSOR | MYL_TEXT_TAIL);
    }
    if (static_source || len > a->cap) {
        int64_t cap = a->cap > INT64_MAX / 2 ? len : a->cap > 0 ? a->cap * 2 : 16;
        if (cap < len) cap = len;
        size_t room;
        myl_block *grown = block_alloc(MYL_KIND_STR, block_data_size(cap, 1, true), &room);
        grown->cap = (int64_t)room - 1;
        grown->len = a->len;
        memcpy(block_data(grown), block_data(a), (size_t)a->len);
        if (count <= 16) core_text_copy_short(block_data(grown) + a->len, bytes, (size_t)count);
        else memcpy(block_data(grown) + a->len, bytes, (size_t)count);
        if (!static_source) block_free(a);
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

/* PY-FSTRING-1: the renderer's sink appends one run of spelled bytes to a text
   block that was reserved for them, so the block grows only if a bound was low. */
myl_block *myl_core_str_append_bytes(myl_block *text, const unsigned char *bytes, size_t len) {
    return core_text_append_bytes(text, bytes, (int64_t)len, false);
}

/* A run whose octets are known ASCII (a literal piece, decimal digits,
   True/False) keeps the block's ASCII flag, so a later scalar count or `len`
   does not rescan it. The claim survives only if the text so far was ASCII too. */
myl_block *myl_core_str_append_ascii(myl_block *text, const unsigned char *bytes, size_t len) {
    return core_text_append_bytes(text, bytes, (int64_t)len, (text->kind & MYL_TEXT_ASCII) != 0);
}

/* True and False reach a reserved block as the same octets `print` writes, and
   keep the block's ASCII claim only when the text before them was ASCII. */
myl_block *myl_core_format_bool_append(myl_block *text, bool value) {
    bool ascii = (text->kind & MYL_TEXT_ASCII) != 0;
    return value ? core_text_append_bytes(text, (const unsigned char *)"True", 4, ascii)
                 : core_text_append_bytes(text, (const unsigned char *)"False", 5, ascii);
}

/* Keep scalar capture and allocation register pressure off the ASCII leaf path. */
__attribute__((noinline)) static myl_block *core_text_append_char_general(myl_block *a, myl_block *text, uint64_t offset, uint64_t width) {
    unsigned char bytes[4];
    core_text_copy_short(bytes, block_data(text) + offset, (size_t)width);
    bool ascii = width == 1 && (a->kind & MYL_TEXT_ASCII) != 0;
    return core_text_append_bytes(a, bytes, (int64_t)width, ascii);
}

myl_block *myl_core_ir_str_append_char(myl_block *a, myl_block *text, uint64_t offset) {
    uint64_t width = myl_core_ir_str_width(text, offset);
    /* Capture an ASCII octet before any write, including a same-owner read. */
    if (width == 1 && a->len >= 0 && a->len < a->cap &&
        (a->kind & (MYL_STATIC_STORAGE | MYL_TEXT_CURSOR | MYL_TEXT_TAIL)) == 0) {
        unsigned char octet = block_data(text)[offset];
        return core_text_append_bytes(a, &octet, 1, (a->kind & MYL_TEXT_ASCII) != 0);
    }
    return core_text_append_char_general(a, text, offset, width);
}

/* Runtime position consumers must reject negatives even without a source guard. */
_Noreturn void myl_core_negative_position(int64_t index, int64_t length, bool text) {
    static const myl_core_site sites[] = {
        {TRAP_LIST_BOUNDS, 0, 0, 64, "index", "<runtime>", "<runtime>"},
        {TRAP_TEXT_BOUNDS, 0, 0, 64, "index", "<runtime>", "<runtime>"}
    };
    myl_core_trap(&sites[text], index, length);
    abort();
}

/* A byte offset that falls inside a scalar: the plan's R_TEXT_BOUNDARY. The
   caller passes the site the compiler emitted for this slice, so the trap prints
   its source line and function like every other check (B3). */
_Noreturn void myl_core_text_boundary(const myl_core_site *site, int64_t offset, int64_t length) {
    myl_core_trap(site, offset, length);
    abort();
}

static int64_t core_text_clamp(int64_t index, int64_t len, bool text) {
    if (index < 0) myl_core_negative_position(index, len, text);
    return index > len ? len : index;
}

/* The octets `text[start:end]` covers: where they begin and how many (two registers). */
typedef struct { uint64_t at, len; } core_text_span;
core_text_span myl_core_ir_str_slice_span(myl_block *text, int64_t start, int64_t end) {
    int64_t len = (int64_t)myl_core_str_chars(text);
    start = core_text_clamp(start, len, true); end = core_text_clamp(end, len, true);
    uint64_t a = myl_core_str_offset(text, (uint64_t)start), b = a;
    if (end > start) b = (text->kind & MYL_TEXT_ASCII) ? (uint64_t)end : core_text_locate(text, (uint64_t)end, (core_anchor){(uint64_t)start, a});
    return (core_text_span){a, b - a};
}

/* A continuation octet begins no scalar, so a slice endpoint there would cut one. */
static inline bool core_text_continuation(unsigned char octet) { return (octet & 0xc0) == 0x80; }

/* The octet at byte offset `index` of `text`, bounds-checked as text. */
int64_t myl_core_ir_str_byte(const unsigned char *data, uint64_t len, int64_t index) {
    int64_t length = (int64_t)len;
    if (index < 0 || index >= length) myl_core_negative_position(index, length, true);
    return (int64_t)data[index];
}

/* A byte-offset slice of text (C9 2b: the text is an (owner, data, length) triple, as in myl_core_text_trim).
   Negative bounds trap; the end clamps to the length; an endpoint inside a multi-byte scalar traps
   R_TEXT_BOUNDARY, so a slice of valid text is valid text. The owner gives only the ASCII flag. */
myl_block *myl_core_ir_str_slice_bytes(const myl_core_site *site, const myl_block *text, const unsigned char *bytes, uint64_t text_len, int64_t start, int64_t end) {
    int64_t length = (int64_t)text_len;
    start = core_text_clamp(start, length, true);
    end = core_text_clamp(end, length, true);
    if (start < end) {
        if (core_text_continuation(bytes[start])) myl_core_text_boundary(site, start, length);
        if (end < length && core_text_continuation(bytes[end])) myl_core_text_boundary(site, end, length);
        return core_text_known(bytes + start, (size_t)(end - start), (text->kind & MYL_TEXT_ASCII) != 0);
    }
    return core_text_known(bytes + start, 0, true);
}

/* The borrowed octets of myl_core_ir_str_slice_bytes: the same clamps, the same
   R_TEXT_BOUNDARY trap, and no block. */
typedef struct { uint64_t at, len; } core_text_byte_span;
core_text_byte_span myl_core_ir_str_slice_bytes_span(const myl_core_site *site, myl_block *text, int64_t start, int64_t end) {
    int64_t length = (int64_t)text->len;
    start = core_text_clamp(start, length, true);
    end = core_text_clamp(end, length, true);
    const unsigned char *bytes = (const unsigned char *)text + MYL_HEADER;
    if (start < end) {
        if (core_text_continuation(bytes[start])) myl_core_text_boundary(site, start, length);
        if (end < length && core_text_continuation(bytes[end])) myl_core_text_boundary(site, end, length);
    }
    return (core_text_byte_span){ (uint64_t)start, end > start ? (uint64_t)(end - start) : 0 };
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
/* Sentinel form (C9 2b): the separator is an (owner, data, length) triple. Its owner gives the ASCII flag only:
   a view passes the sentinel, so a result joined by a view is flagged ASCII only when its parts say so. */
myl_block *myl_core_str_join(const myl_block *separator, const unsigned char *separator_bytes, uint64_t separator_len, myl_block *parts) {
    myl_block **items = (myl_block **)block_data(parts);
    const int64_t width = (int64_t)separator_len;
    int64_t total = parts->len > 1 ? width * (parts->len - 1) : 0;
    bool short_copies = width <= 16;
    bool ascii = parts->len < 2 || (separator->kind & MYL_TEXT_ASCII);
    for (int64_t i = 0; i < parts->len; ++i) { total += items[i]->len; ascii = ascii && (items[i]->kind & MYL_TEXT_ASCII); short_copies = short_copies && items[i]->len <= 16; }
    myl_block *text = str_new(total);
    unsigned char *at = block_data(text);
    if (short_copies) core_text_join_short(at, items, (size_t)parts->len, separator_bytes, (size_t)width);
    else for (int64_t i = 0; i < parts->len; ++i) {
        if (i) { core_text_copy(at, separator_bytes, (size_t)width); at += width; }
        core_text_copy(at, (const unsigned char *)items[i] + MYL_HEADER, (size_t)items[i]->len); at += items[i]->len;
    }
    if (ascii) text->kind |= MYL_TEXT_ASCII;
    return text;
}
/* A list view of text parts (C9 lists): the separator is its octets, a view or a block's span, and the parts are the
   `count` element blocks at `items`, read in place, so a parameter's list joins with no copy of the list. The
   separator carries no cached facts here, so its ASCII flag is read from its octets. */
myl_block *myl_core_str_join_view(const unsigned char *separator_bytes, uint64_t separator_len, myl_block **items, int64_t count) {
    const int64_t width = (int64_t)separator_len;
    int64_t total = count > 1 ? width * (count - 1) : 0;
    bool short_copies = width <= 16;
    bool separator_ascii = true;
    for (uint64_t i = 0; i < separator_len; ++i) if (separator_bytes[i] & 0x80) { separator_ascii = false; break; }
    bool ascii = count < 2 || separator_ascii;
    for (int64_t i = 0; i < count; ++i) { total += items[i]->len; ascii = ascii && (items[i]->kind & MYL_TEXT_ASCII); short_copies = short_copies && items[i]->len <= 16; }
    myl_block *text = str_new(total);
    unsigned char *at = block_data(text);
    if (short_copies) core_text_join_short(at, items, (size_t)count, separator_bytes, (size_t)width);
    else for (int64_t i = 0; i < count; ++i) {
        if (i) { core_text_copy(at, separator_bytes, (size_t)width); at += width; }
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
    if (wanted_len == 1) {
        const unsigned char *hit = memchr(data + start, wanted[0], (size_t)(len - start));
        return hit ? hit - data : -1;
    }
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

static int64_t core_text_find_bytes(const unsigned char *text, uint64_t text_len, const unsigned char *needle, uint64_t needle_len, int64_t start) {
    return core_span_find(text, text_len, needle, needle_len, start);
}

/* Scalars that start in bytes [from, to): every byte that is not a UTF-8 continuation. */
static uint64_t core_text_starts(const unsigned char *bytes, uint64_t from, uint64_t to) {
    uint64_t count = 0;
    core_text_walked += to - from;
    for (; from + 32 <= to; from += 32) count += core_text_starts32(bytes + from);
    for (uint64_t i = from; i < to; ++i) count += (bytes[i] & 0xc0) != 0x80;
    return count;
}

/* The octet offset of the first match (C2): the method spelling answers in bytes,
   while `myl_core_str_find` above keeps the scalar index the helper uses. */
int64_t myl_core_str_find_byte(myl_block *text, myl_block *needle) {
    return core_text_find_bytes(TEXT_SPAN(text), TEXT_SPAN(needle), 0);
}

/* The scalar index of a match is counted from the nearer end: a match near the end
   of a long text is the cached scalar count less the few scalars after it (the old
   runtime's `index_walk`). */
int64_t myl_core_str_find(const myl_block *text, const unsigned char *bytes, uint64_t len, const myl_block *needle, const unsigned char *needle_bytes, uint64_t needle_len) {
    int64_t hit = core_text_find_bytes(bytes, len, needle_bytes, needle_len, 0);
    if (hit < 0 || (text->kind & MYL_TEXT_ASCII)) return hit;
    const uint64_t at = (uint64_t)hit;
    if (at <= len - at) return (int64_t)core_text_starts(bytes, 0, at);
    return (int64_t)(core_text_chars(text, bytes, len) - core_text_starts(bytes, at, len));
}

bool myl_core_str_contains(myl_block *text, myl_block *needle) { return core_text_find_bytes(TEXT_SPAN(text), TEXT_SPAN(needle), 0) >= 0; }

/* NEW-CORE-S1-VIEW-4: the reading helpers over borrowed `(data, length)` spans, each
   answering what its `myl_core_str_*` form answers for the texts those octets spell. */
bool myl_core_span_eq(const unsigned char *a, uint64_t a_len, const unsigned char *b, uint64_t b_len) { return a_len == b_len && memcmp(a, b, (size_t)a_len) == 0; }
uint64_t myl_core_span_chars(const unsigned char *a, uint64_t a_len) { return core_text_starts(a, 0, a_len); }
bool myl_core_span_starts(const unsigned char *a, uint64_t a_len, const unsigned char *b, uint64_t b_len) { return b_len <= a_len && memcmp(a, b, (size_t)b_len) == 0; }
bool myl_core_span_ends(const unsigned char *a, uint64_t a_len, const unsigned char *b, uint64_t b_len) { return b_len <= a_len && memcmp(a + a_len - b_len, b, (size_t)b_len) == 0; }
bool myl_core_span_contains(const unsigned char *a, uint64_t a_len, const unsigned char *b, uint64_t b_len) { return core_span_find(a, (int64_t)a_len, b, (int64_t)b_len, 0) >= 0; }
/* The span forms of `encode` and the byte offset of a match (C9 str): the same answers as the block forms, over (data, length). */
myl_block *myl_core_span_encode(const unsigned char *a, uint64_t a_len) {
    myl_block *out = str_from((const char *)a, (size_t)a_len);
    out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return out;
}
int64_t myl_core_span_find_byte(const unsigned char *a, uint64_t a_len, const unsigned char *b, uint64_t b_len) { return core_text_find_bytes(a, a_len, b, b_len, 0); }
bool myl_core_str_starts(myl_block *text, myl_block *needle) { return needle->len <= text->len && memcmp(block_data(text), block_data(needle), (size_t)needle->len) == 0; }
bool myl_core_str_ends(myl_block *text, myl_block *needle) { return needle->len <= text->len && memcmp(block_data(text) + text->len - needle->len, block_data(needle), (size_t)needle->len) == 0; }

/* A list of text blocks: one block pointer per element, at the target's pointer width (4 on a 32-bit CPU). */
static const int32_t core_text_list_layout[] = {sizeof(myl_block *), 1, 0, 0, 0};
/* Offset-only lists are private to a compiler-proven nonescaping split. */
static uint64_t core_split_initial_capacity(uint64_t len, uint64_t separator_len) {
    /* Clamp before adding: even UINT64_MAX input cannot wrap the capacity.
       Sparse large inputs reserve at most 128 pairs, never a text-sized list. */
    const uint64_t maximum = len / separator_len;
    return maximum < 128 ? maximum + 1 : 128;
}
myl_block *myl_core_span_split_offsets(const unsigned char *text, uint64_t len, const unsigned char *separator, uint64_t separator_len) {
    if (!separator_len) myl_core_s2_unsupported(-1);
    myl_block *list = myl_core_list_new_slow((int64_t)core_split_initial_capacity(len, separator_len), 16);
    int64_t at = 0;
    for (;;) {
        int64_t hit = -1;
        if (separator_len == 1) {
            /* Frequent single-byte pieces avoid the general needle-search frame. */
            if ((uint64_t)at < len) {
                const unsigned char *found = memchr(text + at, separator[0], (size_t)(len - (uint64_t)at));
                if (found) hit = found - text;
            }
        } else if (separator_len == 2 && len - (uint64_t)at >= 2) {
            /* Verify the second byte locally; bound failed probes before libc's
               linear fallback so repeated first bytes retain predictable work. */
            uint64_t cursor = (uint64_t)at;
            unsigned tried = 0;
            for (; tried < 8 && cursor + 1 < len; ++tried) {
                const unsigned char *found = memchr(text + cursor, separator[0], (size_t)(len - cursor - 1));
                if (!found) break;
                cursor = (uint64_t)(found - text);
                if (found[1] == separator[1]) { hit = (int64_t)cursor; break; }
                ++cursor;
            }
            if (hit < 0 && tried == 8 && cursor + 1 < len) {
                extern void *memmem(const void *, size_t, const void *, size_t);
                const unsigned char *found = memmem(text + cursor, (size_t)(len - cursor), separator, 2);
                if (found) hit = found - text;
            }
        } else {
            hit = core_span_find(text, (int64_t)len, separator, (int64_t)separator_len, at);
        }
        int64_t end = hit < 0 ? (int64_t)len : hit;
        if (list->len == list->cap) list = myl_core_list_grow(list, 16);
        uint64_t *piece = (uint64_t *)block_data(list) + 2 * list->len++;
        piece[0] = (uint64_t)at; piece[1] = (uint64_t)(end - at);
        if (hit < 0) break;
        at = hit + (int64_t)separator_len;
    }
    return list;
}
/* Only constant nonnegative indexed users observe this prefix. A too-short input
   retains its true length, so the original located index check still traps. */
void myl_core_span_split_fill(const unsigned char *text, uint64_t len, const unsigned char *separator,
                             uint64_t separator_len, myl_block *list, uint64_t capacity) {
    if (!separator_len) myl_core_s2_unsupported(-1);
    list->len = 0;
    int64_t at = 0;
    while ((uint64_t)list->len < capacity) {
        int64_t hit = core_span_find(text, (int64_t)len, separator, (int64_t)separator_len, at);
        int64_t end = hit < 0 ? (int64_t)len : hit;
        uint64_t *piece = (uint64_t *)block_data(list) + 2 * list->len++;
        piece[0] = (uint64_t)at; piece[1] = (uint64_t)(end - at);
        if (hit < 0) break;
        at = hit + (int64_t)separator_len;
    }
}
myl_block *myl_core_str_split_offsets(myl_block *text, myl_block *separator) {
    return myl_core_span_split_offsets(block_data(text), (uint64_t)text->len, block_data(separator), (uint64_t)separator->len);
}
uint64_t myl_core_str_split_count(myl_block *text, myl_block *separator) {
    if (!separator->len) myl_core_s2_unsupported(-1);
    uint64_t pieces = 1;
    int64_t at = 0, hit;
    while ((hit = core_text_find_bytes(TEXT_SPAN(text), TEXT_SPAN(separator), at)) >= 0) { ++pieces; at = hit + separator->len; }
    return pieces;
}
/* The count of pieces over borrowed spans (a view source or separator): the same answer with no owned copy. */
uint64_t myl_core_span_split_count(const unsigned char *text, uint64_t len, const unsigned char *separator, uint64_t separator_len) {
    if (!separator_len) myl_core_s2_unsupported(-1);
    uint64_t pieces = 1;
    int64_t at = 0, hit;
    while ((hit = core_span_find(text, (int64_t)len, separator, (int64_t)separator_len, at)) >= 0) { ++pieces; at = hit + (int64_t)separator_len; }
    return pieces;
}
/* Private lazy split cursors include leading, adjacent and trailing empty pieces. */
int64_t myl_core_split_start(myl_block *text, myl_block *separator, int64_t unused) {
    (void)text; (void)unused;
    if (!separator->len) myl_core_s2_unsupported(-1);
    return 0;
}
int64_t myl_core_split_end(myl_block *text, myl_block *separator, int64_t start) {
    int64_t hit = core_text_find_bytes(TEXT_SPAN(text), TEXT_SPAN(separator), start);
    return hit < 0 ? text->len : hit;
}
int64_t myl_core_split_next(myl_block *text, myl_block *separator, int64_t end) {
    return end == text->len ? -1 : end + separator->len;
}
/* The lazy split cursors over borrowed spans (C9 S1): a view receiver or separator takes these, so the split of a
   parameter walks its octets with no owned copy. They answer what the block cursors above answer. */
int64_t myl_core_span_split_start(const unsigned char *text, uint64_t text_len, const unsigned char *separator, uint64_t separator_len, int64_t unused) {
    (void)text; (void)text_len; (void)unused;
    if (!separator_len) myl_core_s2_unsupported(-1);
    return 0;
}
int64_t myl_core_span_split_end(const unsigned char *text, uint64_t text_len, const unsigned char *separator, uint64_t separator_len, int64_t start) {
    int64_t hit = core_text_find_bytes(text, text_len, separator, separator_len, start);
    return hit < 0 ? (int64_t)text_len : hit;
}
int64_t myl_core_span_split_next(const unsigned char *text, uint64_t text_len, const unsigned char *separator, uint64_t separator_len, int64_t end) {
    (void)text;
    return end == (int64_t)text_len ? -1 : end + (int64_t)separator_len;
}
/* Sentinel form (C9 2b): the text and the separator are (owner, data, length) triples. Only their octets are read
   (no flag is copied: every piece is a fresh text), so a view passes the sentinel as its owner. */
myl_block *myl_core_str_split(const myl_block *text, const unsigned char *text_bytes, uint64_t text_len, const myl_block *separator, const unsigned char *separator_bytes, uint64_t separator_len) {
    (void)text;
    (void)separator;
    if (!separator_len) myl_core_s2_unsupported(-1);
    myl_block *list = myl_core_list_new_slow(0, sizeof(myl_block *));
    list->reserved = (int64_t)(intptr_t)core_text_list_layout;
    int64_t at = 0;
    for (;;) {
        int64_t hit = core_text_find_bytes(text_bytes, text_len, separator_bytes, separator_len, at);
        int64_t end = hit < 0 ? (int64_t)text_len : hit;
        myl_block *piece = str_from((const char *)text_bytes + at, (size_t)(end - at));
        if (list->len == list->cap) list = myl_core_list_grow(list, sizeof(myl_block *));
        ((myl_block **)block_data(list))[list->len++] = piece;
        if (hit < 0) break;
        at = hit + (int64_t)separator_len;
    }
    return list;
}

/* The integers of a list (C9 lists): `count` values at `values`, read in place, whether the list is a block or a view. */
bool myl_core_span_bytes_valid_list(const int64_t *values, int64_t count) {
    for (int64_t i = 0; i < count; ++i) if (values[i] < 0 || values[i] > 255) return false;
    return true;
}

bool myl_core_bytes_valid_list(myl_block *list) {
    return myl_core_span_bytes_valid_list((const int64_t *)block_data(list), list->len);
}

myl_block *myl_core_span_bytes_from_list(const int64_t *values, int64_t count) {
    myl_block *bytes = str_new(count);
    for (int64_t i = 0; i < count; ++i) block_data(bytes)[i] = (unsigned char)values[i];
    bytes->kind = (bytes->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return bytes;
}

myl_block *myl_core_bytes_from_list(myl_block *list) {
    return myl_core_span_bytes_from_list((const int64_t *)block_data(list), list->len);
}

myl_block *myl_core_bytes_concat(const myl_block *a, const myl_block *b) { myl_block *out = core_text_concat((const unsigned char *)a + MYL_HEADER, (uint64_t)a->len, (const unsigned char *)b + MYL_HEADER, (uint64_t)b->len); out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES; return out; }
myl_block *myl_core_bytes_slice(myl_block *text, int64_t start, int64_t end) {
    start = core_text_clamp(start, text->len, false); end = core_text_clamp(end, text->len, false);
    /* Octets need no ASCII flag; a slice of an ASCII block keeps it, without a scan. */
    myl_block *out = core_octets_copy(block_data(text) + start, (size_t)(end > start ? end - start : 0), (text->kind & MYL_TEXT_ASCII) != 0);
    out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return out;
}

myl_block *myl_core_text_encode(myl_block *text) {
    myl_block *copy = myl_core_owned_octets_copy(text);
    copy->kind = (copy->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return copy;
}
int64_t myl_core_bytes_find(myl_block *text, myl_block *needle) { return core_text_find_bytes(TEXT_SPAN(text), TEXT_SPAN(needle), 0); }

uint64_t myl_core_str_index_offset(myl_block *text, int64_t index) {
    /* Validation conversion: the caller reports its located checked-read trap. */
    return index < 0 ? (uint64_t)text->len : myl_core_str_offset(text, (uint64_t)index);
}
uint64_t myl_core_bytes_index_offset(myl_block *text, int64_t index) {
    return (uint64_t)index;
}

static int64_t core_text_step_bound(int64_t value, int64_t len, int64_t step, bool stop, bool text) {
    if ((!stop && value == INT64_MIN) || (stop && value == INT64_MAX)) return step < 0 ? (stop ? -1 : len - 1) : (stop ? len : 0);
    if (value < 0) myl_core_negative_position(value, len, text);
    if (step < 0) return value >= len ? len - 1 : value;
    return value > len ? len : value;
}

/* The stepped copy of the `text_len` octets at `bytes` (C9 2b). `owner` gives the ASCII flag and, for an owned
   text, its cached scalar count; a view passes the sentinel, which has neither, so its count is scanned. */
static inline __attribute__((always_inline)) myl_block *core_text_slice_step(const myl_block *owner, const unsigned char *bytes, uint64_t text_len, int64_t start, int64_t end, int64_t step, bool unicode) {
    int64_t len = unicode ? (int64_t)(owner == &myl_core_text_no_cache ? myl_core_span_chars(bytes, text_len) : myl_core_str_chars(owner)) : (int64_t)text_len;
    start = core_text_step_bound(start, len, step, false, unicode); end = core_text_step_bound(end, len, step, true, unicode);
    myl_block *out = str_new((int64_t)text_len);
    out->len = 0;
    const bool ascii = !unicode || (owner->kind & MYL_TEXT_ASCII);
    core_anchor walked = {0, 0};
    for (int64_t i = start; step > 0 ? i < end : i > end;) {
        /* Each element is found from the previous one: the walk costs the step. */
        if (!ascii) walked = core_text_move(bytes, text_len, walked, (uint64_t)i);
        uint64_t at = ascii ? (uint64_t)i : walked.at;
        uint64_t width = unicode ? core_text_width(bytes, text_len, at) : 1;
        /* One octet is stored directly (a call to memcpy per character is most of the step's cost). */
        if (width == 1) block_data(out)[out->len] = bytes[at];
        else memcpy(block_data(out) + out->len, bytes + at, (size_t)width);
        out->len += (int64_t)width;
        if ((step > 0 && i > INT64_MAX - step) || (step < 0 && i < INT64_MIN - step)) break;
        i += step;
    }
    block_data(out)[out->len] = 0;
    core_text_publish_known(out, (owner->kind & MYL_TEXT_ASCII) != 0);
    if (!unicode) out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return out;
}

/* Sentinel form (C9 2b): the text is an (owner, data, length) triple; see myl_core_text_trim. */
myl_block *myl_core_str_slice_step(const myl_block *text, const unsigned char *bytes, uint64_t text_len, int64_t start, int64_t end, int64_t step) {
    return core_text_slice_step(text, bytes, text_len, start, end, step, true);
}
myl_block *myl_core_bytes_slice_step(myl_block *text, int64_t start, int64_t end, int64_t step) { return core_text_slice_step(text, block_data(text), (uint64_t)text->len, start, end, step, false); }

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
/* Span cursors (CX2): a borrowed text view walks its octets in place, with the same separators and offsets. */
int64_t myl_core_span_split_ws_start(const unsigned char *text, uint64_t text_len, int64_t at) {
    if (at < 0) return at;
    while (at < (int64_t)text_len && core_text_space(text[at])) ++at;
    return at;
}
int64_t myl_core_span_split_ws_end(const unsigned char *text, uint64_t text_len, int64_t at) {
    if (at < 0) return at;
    while (at < (int64_t)text_len && !core_text_space(text[at])) ++at;
    return at;
}
/* Whitespace split over a borrowed text span (CX2): the pieces are copies; the text is read in place. */
myl_block *myl_core_span_str_split_whitespace(const unsigned char *text, uint64_t text_len) {
    myl_block *list = myl_core_list_new_slow(0, sizeof(myl_block *));
    list->reserved = (int64_t)(intptr_t)core_text_list_layout;
    int64_t at = 0, length = (int64_t)text_len;
    while (at < length) {
        while (at < length && core_text_space(text[at])) ++at;
        int64_t start = at;
        while (at < length && !core_text_space(text[at])) ++at;
        if (start == at) break;
        myl_block *piece = str_from((const char *)text + start, (size_t)(at - start));
        if (list->len == list->cap) list = myl_core_list_grow(list, sizeof(myl_block *));
        ((myl_block **)block_data(list))[list->len++] = piece;
    }
    return list;
}
/* Block form of the separator split for a `byte_buffer` receiver or separator (W13): a buffer has the block layout of
   bytes, but no span admission, so its octets are read here as `myl_core_str_split` reads a span's. */
myl_block *myl_core_buffer_split(myl_block *text, myl_block *separator) {
    return myl_core_str_split(text, block_data(text), (uint64_t)text->len, separator, block_data(separator), (uint64_t)separator->len);
}
myl_block *myl_core_str_split_whitespace(myl_block *text) {
    return myl_core_span_str_split_whitespace(block_data(text), (uint64_t)text->len);
}

myl_block *myl_core_span_bytes_to_list(const unsigned char *data, uint64_t length) {
    myl_block *list = myl_core_list_new_slow((int64_t)length, 8);
    list->len = (int64_t)length;
    for (uint64_t i = 0; i < length; ++i) ((int64_t *)block_data(list))[i] = data[i];
    return list;
}

myl_block *myl_core_bytes_to_list(myl_block *bytes) {
    return myl_core_span_bytes_to_list(block_data(bytes), (uint64_t)bytes->len);
}

bool myl_core_bytes_contains_value(myl_block *bytes, int64_t value) {
    return value >= 0 && value <= 255 && memchr(block_data(bytes), (unsigned char)value, (size_t)bytes->len) != NULL;
}

/* S3 helpers port native_text_methods.c/native_search.c/native_trim.c/native_repr.c
 * into independent owned blocks. Inputs borrow, outputs own a fresh block. */
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

/* Sentinel form (C9 2b): the octets are the span; the owner gives only the result's family. */
myl_block *myl_core_text_case(const myl_block *input, const unsigned char *data, uint64_t len, bool upper) {
    myl_block *result = str_new((int64_t)len);
    memcpy(block_data(result), data, (size_t)len);
    for (uint64_t i = 0; i < len; i++) {
        unsigned char *value = block_data(result) + i;
        if (upper && *value >= 'a' && *value <= 'z') *value -= 32;
        else if (!upper && *value >= 'A' && *value <= 'Z') *value += 32;
    }
    core_text_family(result, input);
    return result;
}

/* The span form (F20): the octets are the borrowed (data, length) of an owned text or of a view, which needs no
 * copy. It is the one place the property logic lives; the block form below reads the same octets through it. */
bool myl_core_span_text_every(const unsigned char *data, uint64_t length, int32_t property) {
    if (!length) return false;
    for (uint64_t i = 0; i < length; i++) {
        unsigned char value = data[i];
        bool good = property == 0 ? value >= '0' && value <= '9' :
                    property == 1 ? (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z') : core_text_space(value);
        if (!good) return false;
    }
    return true;
}

bool myl_core_text_every(myl_block *input, int32_t property) {
    return myl_core_span_text_every(block_data(input), (uint64_t)input->len, property);
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

/* The span form (F20): the first scalar of the borrowed octets (data, length), which is all `ord` reads. An octet past
 * `length` decodes as zero, the terminator that follows a text block's octets, so a view reads only its own octets. The
 * block form below reads the same scalar through it. */
int64_t myl_core_span_text_ord(const unsigned char *data, uint64_t length) {
    uint32_t point = length ? data[0] : 0;
    if (point < 0x80) return (int64_t)point;
    unsigned count = point < 0xe0 ? 1 : point < 0xf0 ? 2 : 3;
    point &= count == 1 ? 0x1f : count == 2 ? 0x0f : 0x07;
    for (unsigned at = 1; at <= count; at++) point = (point << 6) | ((at < length ? data[at] : 0) & 0x3f);
    return (int64_t)point;
}

int64_t myl_core_text_ord(myl_block *text) {
    return myl_core_span_text_ord(block_data(text), (uint64_t)text->len);
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

static size_t core_search_endpoint(size_t length, int64_t value, bool start, bool text) {
    if (value >= 0) return start || (uint64_t)value <= length ? (size_t)value : length;
    myl_core_negative_position(value, (int64_t)length, text);
}

static core_search_window core_window(size_t length, int64_t start, int64_t end, bool text) {
    size_t first = core_search_endpoint(length, start, true, text), last = core_search_endpoint(length, end, false, text);
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
        while (at <= input.length - needle.length) {
            int64_t hit = core_span_find(input.data, (int64_t)input.length, needle.data, (int64_t)needle.length, (int64_t)at);
            if (hit < 0) break;
            count++; at = (size_t)hit + needle.length;
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
        int64_t hit = core_span_find(input.data, (int64_t)input.length, needle.data, (int64_t)needle.length, 0);
        found = hit < 0 ? SIZE_MAX : (size_t)hit;
    }
    return found == SIZE_MAX ? -1 : (int64_t)found;
}

int64_t myl_core_text_search(const myl_block *input, const unsigned char *input_bytes, uint64_t input_len, const myl_block *needle, const unsigned char *needle_bytes, uint64_t needle_len, int64_t start, int64_t end, int32_t mode) {
    core_search_window bounds = core_window((size_t)core_text_chars(input, input_bytes, input_len), start, end, true);
    if (!needle_len) return core_empty_answer(bounds, mode);
    if (!bounds.valid) return mode >= CORE_COUNT ? 0 : -1;
    const bool ascii = (input->kind & MYL_TEXT_ASCII) != 0;
    size_t first = (size_t)core_text_offset(input, input_bytes, input_len, bounds.first), last = (size_t)bounds.last;
    if (!ascii) last = (size_t)core_text_locate_at(input, input_bytes, input_len, bounds.last, (core_anchor){bounds.first, first});
    int64_t found = core_search_octets((core_octets){input_bytes + first, last - first, false}, (core_octets){needle_bytes, (size_t)needle_len, false}, mode);
    if (found < 0 || mode >= CORE_COUNT) return found;
    if (ascii) return (int64_t)(first + (size_t)found);
    /* Count from the nearer window end, and leave the cursor on the match: the next
       call of a scan starts or ends there (NEW-CORE-TEXT-CURSOR-1). */
    const uint64_t hit = first + (uint64_t)found;
    const uint64_t index = hit - first <= last - hit ? bounds.first + core_text_starts(input_bytes, first, hit) : bounds.last - core_text_starts(input_bytes, hit, last);
    core_cursor_set(input, (core_anchor){index, hit});
    return (int64_t)index;
}

/* Explicit-owner lookups (C9 S1). A `str` parameter of an internal function is an owner (its block, or the
   static sentinel for a borrowed slice) and its span (data, length). The owner's cached facts serve the lookup
   exactly as the owned helpers' do, and nothing is written into the sentinel (`core_text_can_cache`). A parameter
   of a call uses its frame header as the owner (`text_frame`), so one call walks only the distance moved. */
int64_t myl_core_xc_chars(const myl_block *owner, const unsigned char *bytes, uint64_t len) {
    return (int64_t)core_text_chars(owner, bytes, len);
}
uint64_t myl_core_xc_index(const myl_block *owner, const unsigned char *bytes, uint64_t len, int64_t index) {
    /* Validation conversion: the caller reports its located checked-read trap. */
    if (index < 0) return len;
    return core_text_offset(owner, bytes, len, (uint64_t)index);
}
int64_t myl_core_xc_search(const myl_block *owner, const unsigned char *bytes, uint64_t len, const myl_block *needle, const unsigned char *needle_bytes, uint64_t needle_len, int64_t start, int64_t end, int32_t mode) {
    return myl_core_text_search(owner, bytes, len, needle, needle_bytes, needle_len, start, end, mode);
}

/* A byte-offset search over text (C2): the window and the answer are octets, and an
   endpoint that falls inside a scalar traps R_TEXT_BOUNDARY with the caller's site,
   exactly like a byte slice. */
/* The span form (C9 str): the input and the needle are their borrowed (data, length) spans. */
int64_t myl_core_span_text_search_bytes(const myl_core_site *site, const unsigned char *bytes, uint64_t input_len, const unsigned char *needle_bytes, uint64_t needle_len, int64_t start, int64_t end, int32_t mode) {
    const size_t length = (size_t)input_len;
    core_search_window bounds = core_window(length, start, end, true);
    if (bounds.valid) {
        if (core_text_continuation(bytes[bounds.first])) myl_core_text_boundary(site, (int64_t)bounds.first, (int64_t)length);
        if (bounds.last < length && core_text_continuation(bytes[bounds.last])) myl_core_text_boundary(site, (int64_t)bounds.last, (int64_t)length);
    }
    if (!needle_len) return core_empty_answer(bounds, mode);
    if (!bounds.valid) return mode >= CORE_COUNT ? 0 : -1;
    int64_t found = core_search_octets((core_octets){bytes + bounds.first, bounds.last - bounds.first, false}, (core_octets){needle_bytes, (size_t)needle_len, false}, mode);
    return found < 0 || mode >= CORE_COUNT ? found : found + (int64_t)bounds.first;
}
int64_t myl_core_text_search_bytes(const myl_core_site *site, myl_block *input, myl_block *needle, int64_t start, int64_t end, int32_t mode) {
    return myl_core_span_text_search_bytes(site, block_data(input), (uint64_t)input->len, block_data(needle), (uint64_t)needle->len, start, end, mode);
}

/* The byte-window search over (data, length) (C9 2b): the same window and answers as the block form. */
static int64_t core_bytes_search_span(const unsigned char *data, uint64_t len, const unsigned char *needle, uint64_t needle_len, int64_t start, int64_t end, int32_t mode) {
    core_search_window bounds = core_window((size_t)len, start, end, false);
    if (!needle_len) return core_empty_answer(bounds, mode);
    if (!bounds.valid) return mode >= CORE_COUNT ? 0 : -1;
    int64_t found = core_search_octets((core_octets){data + bounds.first, bounds.last - bounds.first, false}, (core_octets){needle, (size_t)needle_len, false}, mode);
    return found < 0 || mode >= CORE_COUNT ? found : found + (int64_t)bounds.first;
}

int64_t myl_core_bytes_search(myl_block *input, myl_block *needle, int64_t start, int64_t end, int32_t mode) {
    return core_bytes_search_span(block_data(input), (uint64_t)input->len, block_data(needle), (uint64_t)needle->len, start, end, mode);
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
static inline __attribute__((always_inline)) void core_set_add(core_scalar_set *set, uint32_t point) {
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

/* The block form: an owned input and an owned set, as on main (its body is main's, so an owned call compiles to main's). */
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

/* Span form (C9 2b): the input and the set are (owner, data, length) triples. Only their octets are read; the
   input's owner gives the ASCII flag the result copies, and a view passes the static sentinel, which has none. */
myl_block *myl_core_text_trim_span(const myl_block *input, const unsigned char *input_bytes, uint64_t input_len,
                                   const myl_block *chars, const unsigned char *chars_bytes, uint64_t chars_len, int32_t ends, bool explicit_chars) {
    (void)chars;
    core_scalar_set set = {0};
    if (explicit_chars) for (size_t at = 0; at < (size_t)chars_len;) core_set_add(&set, core_unicode_next(chars_bytes, &at));
    size_t low = 0, high = (size_t)input_len;
    if (ends != 2) while (low < high) {
        size_t next = low;
        uint32_t point = core_unicode_next(input_bytes, &next);
        if (!(explicit_chars ? core_set_contains(&set, point) : core_unicode_space(point))) break;
        low = next;
    }
    if (ends != 1) while (high > low) {
        size_t next = core_unicode_previous(input_bytes, high), cursor = next;
        uint32_t point = core_unicode_next(input_bytes, &cursor);
        if (!(explicit_chars ? core_set_contains(&set, point) : core_unicode_space(point))) break;
        high = next;
    }
    free(set.wide);
    return core_text_known(input_bytes + low, high - low, (input->kind & MYL_TEXT_ASCII) != 0);
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

/* Sentinel form (C9 2b): the three texts are (owner, data, length) triples. Only the octets are read; the
   owner of the input gives the result's family, and the needle's and insert's owners are not read. */
myl_block *myl_core_text_replace(const myl_block *input, const unsigned char *input_bytes, uint64_t input_len,
                                 const myl_block *needle, const unsigned char *needle_bytes, uint64_t needle_len,
                                 const myl_block *insert, const unsigned char *insert_bytes, uint64_t insert_len) {
    (void)needle;
    (void)insert;
    int64_t hits = core_bytes_search_span(input_bytes, input_len, needle_bytes, needle_len, 0, INT64_MAX, CORE_COUNT);
    uint64_t kept = (uint64_t)((int64_t)input_len - hits * (int64_t)needle_len);
    if (insert_len && (uint64_t)hits > (uint64_t)INT64_MAX / insert_len) out_of_memory();
    uint64_t added = (uint64_t)hits * insert_len;
    if (added > (uint64_t)INT64_MAX - kept) out_of_memory();
    myl_block *result = str_new((int64_t)(kept + added));
    int64_t at = 0, cursor = 0;
    for (int64_t left = hits; left; left--) {
        int64_t hit = core_text_find_bytes(input_bytes, input_len, needle_bytes, needle_len, cursor);
        memcpy(block_data(result) + at, input_bytes + cursor, (size_t)(hit - cursor));
        at += hit - cursor;
        memcpy(block_data(result) + at, insert_bytes, (size_t)insert_len);
        at += (int64_t)insert_len; cursor = hit + (int64_t)needle_len;
    }
    memcpy(block_data(result) + at, input_bytes + cursor, (size_t)((int64_t)input_len - cursor));
    core_text_family(result, input);
    return result;
}

static myl_block *core_append_line(myl_block *list, const myl_block *owner, const unsigned char *data, size_t start, size_t end) {
    myl_block *piece = str_from((const char *)data + start, end - start);
    core_text_family(piece, owner);
    if (list->len == list->cap) list = myl_core_list_grow(list, sizeof(myl_block *));
    ((myl_block **)block_data(list))[list->len++] = piece;
    return list;
}

/* Sentinel form (C9 2b): the octets are the span of an owned text or of a view, which needs no copy; the owner gives
 * only the pieces' family (a view passes `myl_core_text_no_cache`). */
myl_block *myl_core_text_splitlines(const myl_block *owner, const unsigned char *data, uint64_t len) {
    myl_block *list = myl_core_list_new_slow(0, sizeof(myl_block *));
    list->reserved = (int64_t)(intptr_t)core_text_list_layout;
    size_t start = 0, cursor = 0;
    while (cursor < (size_t)len) {
        unsigned char octet = data[cursor];
        if (octet != '\n' && octet != '\r') { cursor++; continue; }
        list = core_append_line(list, owner, data, start, cursor);
        cursor++;
        if (octet == '\r' && cursor < (size_t)len && data[cursor] == '\n') cursor++;
        start = cursor;
    }
    if (start < (size_t)len) list = core_append_line(list, owner, data, start, (size_t)len);
    return list;
}

/* Sentinel form (C9 2b), as `myl_core_text_case`: the octets are the span; an owner's cached scalar count is used when it
 * has one, and a view's scalars are counted from its octets. */
myl_block *myl_core_text_zfill(const myl_block *owner, const unsigned char *data, uint64_t len, int64_t width) {
    uint64_t length = kind_of(owner) == MYL_KIND_BYTES ? len :
                      owner == &myl_core_text_no_cache ? myl_core_span_chars(data, len) : myl_core_str_chars(owner);
    uint64_t target = width <= 0 ? 0 : (uint64_t)width > UINT32_MAX ? UINT32_MAX : (uint64_t)width;
    uint64_t pad = target > length ? target - length : 0;
    myl_block *result = str_new((int64_t)len + (int64_t)pad);
    size_t keep = len && (data[0] == '+' || data[0] == '-') ? 1 : 0;
    if (keep) block_data(result)[0] = data[0];
    memset(block_data(result) + keep, '0', (size_t)pad);
    memcpy(block_data(result) + keep + pad, data + keep, (size_t)len - keep);
    core_text_family(result, owner);
    return result;
}

/* The first octet of `values` in the window [start, end) of `input`, or -1. An `end` past the length is the length
   (`find_any` passes INT64_MAX), and a negative bound traps with the written index and length. */
int64_t myl_core_bytes_find_any(myl_block *input, myl_block *values, int64_t start, int64_t end) {
    size_t length=input->len;
    if (start < 0) myl_core_negative_position(start, input->len, false);
    if (end < 0) myl_core_negative_position(end, input->len, false);
    if ((uint64_t)end<length) length=(size_t)end;
    size_t at = (uint64_t)start>length ? length : (size_t)start;
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
    size_t first = core_search_endpoint((size_t)bytes->len, start, false, false), last = core_search_endpoint((size_t)bytes->len, end, false, false);
    return myl_core_span_utf8_count(block_data(bytes) + first, last > first ? last - first : 0);
}
myl_block *myl_core_bytes_decode_text(myl_block *bytes) { return str_from((const char *)block_data(bytes), (size_t)bytes->len); }
/* The caller has validated this exact UTF-8 span; the result owns its copy. */
myl_block *myl_core_span_decode_text(const unsigned char *bytes, uint64_t length) {
    return str_from((const char *)bytes, (size_t)length);
}
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
/* The span form of `repr` (C9 str): the text is its borrowed (data, length). */
myl_block *myl_core_span_text_repr(const unsigned char *data, uint64_t length, bool bytes) {
    core_repr_input input = {data, (size_t)length, bytes, '\''};
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
myl_block *myl_core_text_repr(myl_block *source, bool bytes) {
    return myl_core_span_text_repr(block_data(source), (uint64_t)source->len, bytes);
}

/* Borrowed spans contain no header, owner, or reference count. The compiler
   validates their source relationships before lowering, in every build mode. */
typedef struct { const unsigned char *data; uint64_t len; } core_borrowed_span;
int64_t myl_core_view_chars(const unsigned char *data, uint64_t len) {
    int64_t chars = 0;
    for (uint64_t i = 0; i < len; i++) chars += (data[i] & 0xc0) != 0x80;
    return chars;
}
static uint64_t core_view_offset(const unsigned char *data, uint64_t len, uint64_t scalar) {
    uint64_t at = 0, seen = 0;
    /* Skip bounded ASCII words without needing an owner or cached metadata.
       Non-ASCII prefixes fall back to the scalar walk, including partial tails. */
    while (len - at >= 8 && scalar - seen >= 8) {
        uint64_t word;
        memcpy(&word, data + at, sizeof word);
        if (word & UINT64_C(0x8080808080808080)) break;
        at += 8; seen += 8;
    }
    while (at < len && seen < scalar) {
        ++at;
        while (at < len && (data[at] & 0xc0) == 0x80) ++at;
        ++seen;
    }
    return at;
}
core_borrowed_span myl_core_view_slice(const unsigned char *data, uint64_t len, int64_t start, int64_t end, bool text) {
    /* Positive text endpoints only need a bounded prefix scan. Counting the
       entire owner on every small slice would make this quadratic in its size. */
    if (!text || start < 0 || end < 0) {
        int64_t count = text ? myl_core_view_chars(data, len) : (int64_t)len;
        start = core_text_clamp(start, count, text);
        end = core_text_clamp(end, count, text);
    }
    if (end < start) end = start;
    uint64_t first = text ? core_view_offset(data, len, (uint64_t)start) : (uint64_t)start;
    uint64_t last = text ? core_view_offset(data + first, len - first, (uint64_t)(end - start)) + first : (uint64_t)end;
    return (core_borrowed_span){data + first, last - first};
}
/* The octets `text[start:end]` of a borrowed text (a view of a parameter, a payload or a returned borrow): the byte
   slice myl_core_ir_str_slice_bytes makes of an owned text, with the same clamps and the same R_TEXT_BOUNDARY trap at
   an endpoint inside a scalar, so a slice of valid text is valid text however the text is held (FX8). No copy. */
core_borrowed_span myl_core_view_slice_text(const myl_core_site *site, const unsigned char *data, uint64_t len, int64_t start, int64_t end) {
    int64_t length = (int64_t)len;
    start = core_text_clamp(start, length, true);
    end = core_text_clamp(end, length, true);
    if (start >= end) return (core_borrowed_span){data + start, 0};
    if (core_text_continuation(data[start])) myl_core_text_boundary(site, start, length);
    if (end < length && core_text_continuation(data[end])) myl_core_text_boundary(site, end, length);
    return (core_borrowed_span){data + start, (uint64_t)(end - start)};
}
/* The octets a no-argument `strip`, `lstrip` or `rstrip` keeps, borrowed from the
   text: the same whitespace scan as myl_core_text_trim (ends 0 both, 1 leading only,
   2 trailing only), with no copy. The result borrows `data`, so its owner keeps it alive. */
core_borrowed_span myl_core_text_trim_view(const unsigned char *data, uint64_t len, int32_t ends) {
    size_t low = 0, high = (size_t)len;
    if (ends != 2) while (low < high) {
        size_t next = low;
        uint32_t point = core_unicode_next(data, &next);
        if (!core_unicode_space(point)) break;
        low = next;
    }
    if (ends != 1) while (high > low) {
        size_t next = core_unicode_previous(data, high), cursor = next;
        uint32_t point = core_unicode_next(data, &cursor);
        if (!core_unicode_space(point)) break;
        high = next;
    }
    return (core_borrowed_span){data + low, high - low};
}
/* The span form of an explicit-set text trim (CX-4): the input and the set are borrowed (data, length) spans, and the
   result borrows the kept octets, so a comparison or a length reads them in place. The owned form is
   myl_core_text_trim, which a caller that keeps its result still uses. */
core_borrowed_span myl_core_span_text_trim_view(const unsigned char *data, uint64_t len, const unsigned char *chars, uint64_t chars_len,
                                                int32_t ends, bool explicit_chars) {
    core_scalar_set set = {0};
    if (explicit_chars) for (size_t at = 0; at < (size_t)chars_len;) core_set_add(&set, core_unicode_next(chars, &at));
    size_t low = 0, high = (size_t)len;
    if (ends != 2) while (low < high) {
        size_t next = low;
        uint32_t point = core_unicode_next(data, &next);
        if (!(explicit_chars ? core_set_contains(&set, point) : core_unicode_space(point))) break;
        low = next;
    }
    if (ends != 1) while (high > low) {
        size_t next = core_unicode_previous(data, high), cursor = next;
        uint32_t point = core_unicode_next(data, &cursor);
        if (!(explicit_chars ? core_set_contains(&set, point) : core_unicode_space(point))) break;
        high = next;
    }
    free(set.wide);
    return (core_borrowed_span){data + low, high - low};
}
core_borrowed_span myl_core_xc_slice(const myl_block *owner, const unsigned char *bytes, uint64_t len, int64_t start, int64_t end) {
    const int64_t count = (int64_t)core_text_chars(owner, bytes, len);
    start = core_text_clamp(start, count, true);
    end = core_text_clamp(end, count, true);
    if (end < start) end = start;
    const uint64_t first = core_text_offset(owner, bytes, len, (uint64_t)start);
    const uint64_t last = core_text_offset(owner, bytes, len, (uint64_t)end);
    return (core_borrowed_span){bytes + first, last - first};
}
uint64_t myl_core_view_index(const unsigned char *data, uint64_t len, int64_t index, bool text) {
    /* Validation conversion: the caller reports its located checked-read trap. */
    if (index < 0) return len;
    return text ? core_view_offset(data, len, (uint64_t)index) : (uint64_t)index;
}
myl_block *myl_core_view_char(const unsigned char *data, uint64_t len, uint64_t offset) {
    uint64_t end = offset + 1;
    while (end < len && (data[end] & 0xc0) == 0x80) ++end;
    if (end == offset + 1) return core_ascii_char(data[offset]);
    return str_from((const char *)data + offset, (size_t)(end - offset));
}
/* The scalar code at an octet offset of a borrowed span (a view receiver of str_code). */
uint32_t myl_core_span_str_code(const unsigned char *data, uint64_t len, uint64_t offset) {
    uint64_t width = core_text_width(data, len, offset);
    const unsigned char *bytes = data + offset;
    uint32_t point = bytes[0] & (width == 1 ? 0x7f : width == 2 ? 0x1f : width == 3 ? 0xf : 7);
    for (uint64_t i = 1; i < width; ++i) point = (point << 6) | (bytes[i] & 0x3f);
    return point;
}
/* The octet width of the scalar at an octet offset of a borrowed span (a view receiver of str_width). */
uint64_t myl_core_span_str_width(const unsigned char *data, uint64_t len, uint64_t offset) {
    return core_text_width(data, len, offset);
}
/* A borrowed span's scalar appended to an owned accumulator. The scalar's octets are copied first, so an
   append that writes the accumulator cannot overwrite a view that borrows it. */
myl_block *myl_core_span_str_append_char(myl_block *a, const unsigned char *data, uint64_t len, uint64_t offset) {
    uint64_t width = core_text_width(data, len, offset);
    unsigned char bytes[4];
    core_text_copy_short(bytes, data + offset, (size_t)width);
    bool ascii = width == 1 && (a->kind & MYL_TEXT_ASCII) != 0;
    return core_text_append_bytes(a, bytes, (int64_t)width, ascii);
}
uint8_t myl_core_view_byte(const unsigned char *data, uint64_t len, uint64_t offset) {
    (void)len;
    return data[offset];
}
myl_block *myl_core_view_copy_text(const unsigned char *data, uint64_t len) {
    return myl_core_ir_str_from_view(data, len);
}
myl_block *myl_core_view_copy_bytes(const unsigned char *data, uint64_t len) {
    myl_block *copy = myl_core_ir_str_from_view(data, len);
    copy->kind = (copy->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return copy;
}
/* The copy of a `-> bytes` source extern's result (D-FFI-3): `length` octets at `data`, read before the call returns
   to the program, so C may free or reuse them afterwards. A null pointer with length 0 is the empty value; a negative
   length, or a null pointer with a positive one, traps R_FOREIGN_RESULT at the call. */
myl_block *myl_core_foreign_bytes(const myl_core_site *site, const unsigned char *data, int64_t length) {
    if (length < 0 || (!data && length > 0)) {
        myl_core_trap(site, data != NULL, length);
        abort();
    }
    static const unsigned char empty = 0;
    return myl_core_view_copy_bytes(length ? data : &empty, (uint64_t)length);
}

/* Span forms of the bytes helpers (C9 bytes): a bytes view argument is its (data, length) pair, so the helper reads
   the borrowed octets in place. Each mirrors the block form above it, which keeps its body for owned bytes. */
/* The span form of a bytes trim that keeps a borrowed result (CX-4): the same set and scan as myl_core_span_bytes_trim,
   with the kept octets borrowed from the input rather than copied. */
core_borrowed_span myl_core_span_bytes_trim_view(const unsigned char *data, uint64_t length, const unsigned char *chars, uint64_t chars_len,
                                                 int32_t ends, bool explicit_chars) {
    uint64_t set[4] = {0};
    if (explicit_chars) for (uint64_t i = 0; i < chars_len; i++) {
        unsigned char value = chars[i]; set[value / 64] |= UINT64_C(1) << (value % 64);
    } else for (unsigned point = 0; point < 128; point++) if (core_text_space((unsigned char)point)) set[point / 64] |= UINT64_C(1) << (point % 64);
    uint64_t first = 0, last = length;
    if (ends != 2) while (first < last) {
        unsigned char value = data[first];
        if (!((set[value / 64] >> (value % 64)) & 1)) break;
        first++;
    }
    if (ends != 1) while (last > first) {
        unsigned char value = data[last - 1];
        if (!((set[value / 64] >> (value % 64)) & 1)) break;
        last--;
    }
    return (core_borrowed_span){data + first, last - first};
}
/* The octets in [start, end) of a borrowed bytes span, borrowed from it (lane HC: a slice of a borrowed bytes trim). The
   bounds are clamped to the span, as a slice of an owned bytes value clamps them. */
core_borrowed_span myl_core_span_bytes_slice_view(const unsigned char *data, uint64_t length, int64_t start, int64_t end) {
    uint64_t first = start < 0 ? 0 : (uint64_t)start > length ? length : (uint64_t)start;
    uint64_t last = end < 0 ? 0 : (uint64_t)end > length ? length : (uint64_t)end;
    if (last < first) last = first;
    return (core_borrowed_span){data + first, last - first};
}
myl_block *myl_core_span_bytes_trim(const unsigned char *data, uint64_t length, const unsigned char *chars, uint64_t chars_len, int32_t ends, bool explicit_chars) {
    uint64_t set[4] = {0};
    if (explicit_chars) for (uint64_t i = 0; i < chars_len; i++) {
        unsigned char value = chars[i]; set[value / 64] |= UINT64_C(1) << (value % 64);
    } else for (unsigned point = 0; point < 128; point++) if (core_text_space((unsigned char)point)) set[point / 64] |= UINT64_C(1) << (point % 64);
    uint64_t first = 0, last = length;
    if (ends != 2) while (first < last) {
        unsigned char value = data[first];
        if (!((set[value / 64] >> (value % 64)) & 1)) break;
        first++;
    }
    if (ends != 1) while (last > first) {
        unsigned char value = data[last - 1];
        if (!((set[value / 64] >> (value % 64)) & 1)) break;
        last--;
    }
    myl_block *out = core_octets_copy(data + first, (size_t)(last - first), false);
    out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return out;
}

int64_t myl_core_span_bytes_find(const unsigned char *data, uint64_t length, const unsigned char *needle, uint64_t needle_len) {
    return core_text_find_bytes(data, length, needle, needle_len, 0);
}

int64_t myl_core_span_bytes_find_any(const unsigned char *bytes, uint64_t length, const unsigned char *set, uint64_t set_len, int64_t start, int64_t end) {
    if (start < 0) myl_core_negative_position(start, (int64_t)length, false);
    if (end < 0) myl_core_negative_position(end, (int64_t)length, false);
    if ((uint64_t)end < length) length = (uint64_t)end;
    size_t at = (uint64_t)start > length ? (size_t)length : (size_t)start;
    if (at >= length || !set_len) return -1;
    if (set_len == 1) {
        const unsigned char *found = memchr(bytes + at, set[0], (size_t)length - at);
        return found ? (int64_t)(found - bytes) : -1;
    }
    if (set_len == 2 && set[0] != set[1]) {
        /* The windowed search of myl_core_bytes_find_any, over the span. */
        size_t window = 64;
        while (at < length) {
            size_t span = (size_t)length - at < window ? (size_t)length - at : window;
            const unsigned char *first = memchr(bytes + at, set[0], span);
            size_t bound = first ? (size_t)(first - (bytes + at)) : span;
            const unsigned char *second = bound ? memchr(bytes + at, set[1], bound) : NULL;
            if (second) return (int64_t)(second - bytes);
            if (first) return (int64_t)(first - bytes);
            at += span;
            if (window <= SIZE_MAX / 2) window *= 2;
        }
        return -1;
    }
    uint64_t members[4] = {0, 0, 0, 0};
    for (uint64_t i = 0; i < set_len; i++) members[set[i] >> 6] |= (uint64_t)1 << (set[i] & 63);
    for (size_t i = at; i < length; i++) if (members[bytes[i] >> 6] >> (bytes[i] & 63) & 1) return (int64_t)i;
    return -1;
}

int64_t myl_core_span_bytes_search(const unsigned char *data, uint64_t len, const unsigned char *needle, uint64_t needle_len, int64_t start, int64_t end, int32_t mode) {
    return core_bytes_search_span(data, len, needle, needle_len, start, end, mode);
}

bool myl_core_span_bytes_contains_value(const unsigned char *data, uint64_t len, int64_t value) {
    return value >= 0 && value <= 255 && memchr(data, (unsigned char)value, (size_t)len) != NULL;
}

myl_block *myl_core_span_bytes_concat(const unsigned char *a, uint64_t alen, const unsigned char *b, uint64_t blen) {
    myl_block *out = core_text_concat(a, alen, b, blen);
    out->kind = (out->kind & ~MYL_KIND_MASK) | MYL_KIND_BYTES;
    return out;
}

myl_block *myl_core_span_bytes_hex(const unsigned char *data, uint64_t length) {
    static const unsigned char digits[] = "0123456789abcdef";
    if (length > INT64_MAX / 2) out_of_memory();
    myl_block *out = str_new((int64_t)length * 2);
    out->kind |= 1u << 8;
    for (uint64_t i = 0; i < length; ++i) {
        block_data(out)[i * 2] = digits[data[i] >> 4];
        block_data(out)[i * 2 + 1] = digits[data[i] & 15];
    }
    return out;
}

int64_t myl_core_span_bytes_utf8_count_range(const unsigned char *data, uint64_t length, int64_t start, int64_t end) {
    size_t first = core_search_endpoint((size_t)length, start, false, false), last = core_search_endpoint((size_t)length, end, false, false);
    return myl_core_span_utf8_count(data + first, last > first ? last - first : 0);
}
