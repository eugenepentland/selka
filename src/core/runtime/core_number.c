/* Number/text support, concatenated after the block and text runtimes.
   The inline LLVM fast path admits only plain digits up to eight places;
   this fallback preserves the full pinned whitespace/sign/underscore grammar. */
static bool ascii_space(unsigned char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v'; }

/* `int(text)` with the pinned grammar (docs/bytes.md): surrounding ASCII
   whitespace, one optional sign, decimal digits with single `_` separators
   between digits. An overflowing value is None. */
bool myl_core_str_parse_int(myl_block *text, int64_t *out) {
    const unsigned char *s = block_data(text);
    size_t start = 0, end = (size_t)text->len;
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
