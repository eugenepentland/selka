/* Number/text support, concatenated after the block and text runtimes.
   The inline LLVM fast path admits only plain digits up to eight places;
   this fallback preserves the full pinned whitespace/sign/underscore grammar. */
#include <stddef.h>
static bool ascii_space(unsigned char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'; }

/* The independent Zig formatter allocates only through this Core-block adapter. */
myl_block *myl_core_number_text_new(size_t length) {
    if (length > INT64_MAX) out_of_memory();
    myl_block *text = str_new((int64_t)length);
    text->kind |= 1u << 8;
    return text;
}

/* The prebuilt Zig formatter must not guess the selected runtime's kind offset. */
void myl_core_number_text_clear_ascii(myl_block *text) { text->kind &= ~MYL_TEXT_ASCII; }

/* Invalid packed formats or impossible bounded-frame failures are internal errors. */
_Noreturn void myl_core_number_text_invalid(void) { abort(); }

/* `int(text)` with the pinned grammar (docs/bytes.md): surrounding ASCII
   whitespace, one optional sign, decimal digits with single `_` separators
   between digits. An overflowing value is None. */
bool myl_core_span_parse_int(const unsigned char *s, uint64_t len, int64_t *out) {
    size_t start = 0, end = (size_t)len;
    while (start < end && ascii_space(s[start])) ++start;
    while (end > start && ascii_space(s[end - 1])) --end;
    bool negative = false;
    if (start < end && (s[start] == '+' || s[start] == '-')) negative = s[start++] == '-';
    if (start == end) return false;
    uint64_t magnitude = 0;
    bool previous_digit = false;
    for (size_t i = start; i < end; ++i) {
        unsigned char c = s[i];
        if (c == '_') {
            if (!previous_digit || i + 1 == end) return false;
            previous_digit = false;
            continue;
        }
        if (c < '0' || c > '9') return false;
        if (magnitude > (UINT64_MAX - (uint64_t)(c - '0')) / 10) return false;
        magnitude = magnitude * 10 + (uint64_t)(c - '0');
        previous_digit = true;
    }
    if (!previous_digit) return false;
    if (negative) {
        if (magnitude > (uint64_t)INT64_MAX + 1) return false;
        *out = magnitude == (uint64_t)INT64_MAX + 1 ? INT64_MIN : -(int64_t)magnitude;
    } else {
        if (magnitude > (uint64_t)INT64_MAX) return false;
        *out = (int64_t)magnitude;
    }
    return true;
}

bool myl_core_str_parse_int(myl_block *text, int64_t *out) { return myl_core_span_parse_int(block_data(text), (uint64_t)text->len, out); }

static const char core_number_pairs[] =
    "00010203040506070809" "10111213141516171819"
    "20212223242526272829" "30313233343536373839"
    "40414243444546474849" "50515253545556575859"
    "60616263646566676869" "70717273747576777879"
    "80818283848586878889" "90919293949596979899";

static const uint64_t core_number_powers[] = {
    1ULL, 10ULL, 100ULL, 1000ULL, 10000ULL, 100000ULL,
    1000000ULL, 10000000ULL, 100000000ULL, 1000000000ULL,
    10000000000ULL, 100000000000ULL, 1000000000000ULL,
    10000000000000ULL, 100000000000000ULL, 1000000000000000ULL,
    10000000000000000ULL, 100000000000000000ULL,
    1000000000000000000ULL, 10000000000000000000ULL
};

static unsigned core_number_length(uint64_t value) {
    if (!value) return 1;
    unsigned estimate = ((64u - (unsigned)__builtin_clzll(value)) * 1233u) >> 12;
    return estimate + (value >= core_number_powers[estimate]);
}

/* Two digits per division, backwards into an exactly sized destination. */
static void core_number_write(unsigned char *end, uint64_t value) {
    while (value >= 100) {
        unsigned pair = (unsigned)(value % 100);
        value /= 100;
        end -= 2;
        memcpy(end, core_number_pairs + pair * 2, 2);
    }
    if (value >= 10) {
        end -= 2;
        memcpy(end, core_number_pairs + value * 2, 2);
    } else *--end = (unsigned char)('0' + value);
}

myl_block *myl_core_str_from_i64(int64_t value) {
    bool negative = value < 0;
    uint64_t magnitude = negative ? -(uint64_t)value : (uint64_t)value;
    unsigned length = core_number_length(magnitude) + negative;
    myl_block *text = str_new(length);
    text->kind |= 1u << 8; /* published ASCII flag */
    unsigned char *data = block_data(text);
    core_number_write(data + length, magnitude);
    if (negative) data[0] = '-';
    return text;
}

myl_block *myl_core_str_from_u64(uint64_t value) {
    unsigned length = core_number_length(value);
    myl_block *text = str_new(length);
    text->kind |= 1u << 8;
    core_number_write(block_data(text) + length, value);
    return text;
}

void myl_core_print_i64(int64_t fd, int64_t value) {
    unsigned char buffer[32];
    bool negative = value < 0;
    uint64_t magnitude = negative ? -(uint64_t)value : (uint64_t)value;
    unsigned length = core_number_length(magnitude) + negative;
    core_number_write(buffer + length, magnitude);
    if (negative) buffer[0] = '-';
    stream_write(stream_for(fd), buffer, length);
}

void myl_core_print_u64(int64_t fd, uint64_t value) {
    unsigned char buffer[32];
    unsigned length = core_number_length(value);
    core_number_write(buffer + length, value);
    stream_write(stream_for(fd), buffer, length);
}

/* Port of native_bytes' clamped byte-range parsing; no temporary decoded text. */
static int64_t core_number_endpoint(int64_t index, int64_t length) {
    if (index < 0) index += length;
    return index < 0 ? 0 : index > length ? length : index;
}
static bool core_parse_int_range(myl_block *source, int64_t start, int64_t end, int64_t *out) {
    start = core_number_endpoint(start, source->len);
    end = core_number_endpoint(end, source->len);
    if (end < start) end = start;
    /* Parse directly through a span helper, keeping the published source immutable. */
    const unsigned char *s = block_data(source) + start;
    size_t lower = 0, upper = (size_t)(end - start);
    while (lower < upper && ascii_space(s[lower])) ++lower;
    while (upper > lower && ascii_space(s[upper - 1])) --upper;
    bool negative = false;
    if (lower < upper && (s[lower] == '+' || s[lower] == '-')) negative = s[lower++] == '-';
    if (lower == upper) return false;
    uint64_t magnitude = 0, bound = (uint64_t)INT64_MAX + negative;
    bool digit_before = false;
    for (size_t i = lower; i < upper; ++i) {
        unsigned char c = s[i];
        if (c == '_') { if (!digit_before || i + 1 == upper) return false; digit_before = false; continue; }
        if (c < '0' || c > '9') return false;
        uint64_t digit = c - '0';
        if (magnitude > bound / 10 || (magnitude == bound / 10 && digit > bound % 10)) return false;
        magnitude = magnitude * 10 + digit;
        digit_before = true;
    }
    if (!digit_before) return false;
    int64_t value = negative ? (magnitude == (uint64_t)INT64_MAX + 1 ? INT64_MIN : -(int64_t)magnitude) : (int64_t)magnitude;
    *out = value;
    return true;
}

/* Core's scalar Option uses the low byte of the SysV integer result register;
   the second result register carries the scalar. Full-word C tags are 0 or 1. */
typedef struct { uint64_t tag; int64_t value; } myl_core_parsed_int;
_Static_assert(sizeof(myl_core_parsed_int) == 16, "Core scalar Option size");
_Static_assert(offsetof(myl_core_parsed_int, value) == 8, "Core scalar Option payload");
myl_core_parsed_int myl_core_parse_int_range(myl_block *source, int64_t start, int64_t end) {
    myl_core_parsed_int result = { 0, 0 };
    result.tag = core_parse_int_range(source, start, end, &result.value);
    return result;
}

/* Width-specific saturation uses a wider intermediate, including unsigned 64-bit
   multiplication whose full product exceeds signed 128-bit range. */
uint64_t myl_core_saturating_integer(uint64_t left, uint64_t right, uint32_t width, uint32_t mode) {
    if (mode & 1) {
        /* The caller sign-extends signed operands before the bit-preserving ABI. */
        __int128 a = (int64_t)left, b = (int64_t)right;
        __int128 value = (mode & 2) ? a * b : a - b;
        __int128 upper = ((__int128)1 << (width - 1)) - 1, lower = -upper - 1;
        return (uint64_t)(value > upper ? upper : value < lower ? lower : value);
    }
    uint64_t upper = width == 64 ? UINT64_MAX : (UINT64_C(1) << width) - 1;
    if (!(mode & 2)) return left < right ? 0 : left - right;
    __uint128_t product = (__uint128_t)left * right;
    return product > upper ? upper : (uint64_t)product;
}
