// json_typed.h: the schema-directed parser used by ladder versions v7..v9 of json_parse.c. Included
// with TP_PREFIX (a token), TP_FAST (SIMD/SWAR scanning primitives) and TP_LAZY (decode a string's
// escapes only when the row is kept). The parser accepts any valid JSON: arbitrary whitespace, any key
// order, unknown keys (skipped by a validating skipper), escapes in strings; the schema only says where
// the four fields go and that they have the types the job reads. A malformed document or a duplicate
// key traps.
#ifndef JSON_TYPED_COMMON
#define JSON_TYPED_COMMON
typedef struct {
    const unsigned char *d;
    int64_t n;
    region_t reg;
    row_t *rows;
    size_t nrows;
} pctx;

static inline int64_t tp_skip_ws(const unsigned char *d, int64_t n, int64_t pos) {
    while (pos < n) { unsigned char c = d[pos]; if (c != 32 && c != 9 && c != 10 && c != 13) break; pos++; }
    return pos;
}
/* decode the string body d[start..end) (escapes present) into the region */
static span_t tp_decode(pctx *c, int64_t start, int64_t end) {
    const unsigned char *d = c->d;
    unsigned char *buf = ralloc(&c->reg, (size_t)(end - start) + 8);
    size_t w = 0;
    int64_t i = start;
    while (i < end) {
        unsigned char b = d[i];
        if (b != '\\') { buf[w++] = b; i++; continue; }
        i++;
        unsigned char e = d[i++];
        switch (e) {
        case '"': case '\\': case '/': buf[w++] = e; break;
        case 'b': buf[w++] = 8; break;
        case 'f': buf[w++] = 12; break;
        case 'n': buf[w++] = 10; break;
        case 'r': buf[w++] = 13; break;
        case 't': buf[w++] = 9; break;
        case 'u': {
            int64_t code = 0;
            for (int k = 0; k < 4; k++) {
                if (i >= end) trap("truncated unicode escape");
                unsigned char h = d[i++];
                int v = h >= '0' && h <= '9' ? h - '0' : h >= 'a' && h <= 'f' ? h - 'a' + 10 : h >= 'A' && h <= 'F' ? h - 'A' + 10 : -1;
                if (v < 0) trap("bad hex digit");
                code = code * 16 + v;
            }
            if (code >= 0xD800 && code < 0xE000) trap("surrogate escapes are outside this model");
            if (code < 128) buf[w++] = (unsigned char)code;
            else if (code < 2048) { buf[w++] = (unsigned char)(192 + code / 64); buf[w++] = (unsigned char)(128 + code % 64); }
            else { buf[w++] = (unsigned char)(224 + code / 4096); buf[w++] = (unsigned char)(128 + code / 64 % 64); buf[w++] = (unsigned char)(128 + code % 64); }
            break;
        }
        default: trap("unknown escape");
        }
    }
    return (span_t){buf, w};
}
#endif /* JSON_TYPED_COMMON */

#define TP_CAT2(a, b) a##b
#define TP_CAT(a, b) TP_CAT2(a, b)
#define TP(name) TP_CAT(TP_PREFIX, name)

/* Find the closing quote of the string whose body starts at start. Returns its index and whether an
 * escape was seen; validates control characters. The document buffer is padded (32+ bytes), so the vector
 * loads may read past n; hits at or beyond n count as "unterminated". */
static inline int64_t TP(scan_string)(const unsigned char *d, int64_t n, int64_t start, int *escapes) {
    int64_t i = start;
    *escapes = 0;
#if TP_FAST
    const __m256i q = _mm256_set1_epi8('"'), bs = _mm256_set1_epi8('\\'), lim = _mm256_set1_epi8(32);
    for (;;) {
        __m256i v = _mm256_loadu_si256((const __m256i *)(d + i));
        __m256i hit = _mm256_or_si256(_mm256_or_si256(_mm256_cmpeq_epi8(v, q), _mm256_cmpeq_epi8(v, bs)),
                                      _mm256_cmpeq_epi8(_mm256_min_epu8(v, _mm256_set1_epi8(31)), v)); /* v < 32 */
        (void)lim;
        unsigned m = (unsigned)_mm256_movemask_epi8(hit);
        if (m) {
            int64_t at = i + __builtin_ctz(m);
            if (at >= n) trap("unterminated string");
            unsigned char b = d[at];
            if (b == '"') return at;
            if (b < 32) trap("control character in string");
            *escapes = 1;           /* backslash: the escaped byte may be a quote; step over the pair */
            i = at + 2;
            if (i > n) trap("unterminated escape");
            continue;
        }
        i += 32;
        if (i >= n) trap("unterminated string");
    }
#else
    while (i < n) {
        unsigned char b = d[i];
        if (b == '"') return i;
        if (b < 32) trap("control character in string");
        if (b == '\\') { *escapes = 1; i++; if (i >= n) trap("unterminated escape"); }
        i++;
    }
    trap("unterminated string");
#endif
}
/* A string at pos (the quote): returns the new position; the span is a view, or decoded when it has escapes
 * (immediately, or later when TP_LAZY and the caller asks for it via *raw_end). */
static inline int64_t TP(string)(pctx *c, int64_t pos, span_t *out, int *needs_decode) {
    int escapes;
    int64_t end = TP(scan_string)(c->d, c->n, pos + 1, &escapes);
    if (!escapes) { *out = (span_t){c->d + pos + 1, (size_t)(end - pos - 1)}; *needs_decode = 0; return end + 1; }
#if TP_LAZY
    *out = (span_t){c->d + pos + 1, (size_t)(end - pos - 1)};
    *needs_decode = 1;
#else
    *out = tp_decode(c, pos + 1, end);
    *needs_decode = 0;
#endif
    return end + 1;
}
static inline int64_t TP(integer)(pctx *c, int64_t pos, int64_t *out) {
    const unsigned char *d = c->d;
    int64_t n = c->n, i = pos;
    int neg = 0;
    if (i < n && d[i] == '-') { neg = 1; i++; }
    if (i >= n || d[i] < '0' || d[i] > '9') trap("number needs a digit");
    int64_t v = 0;
    if (d[i] == '0') { i++; if (i < n && d[i] >= '0' && d[i] <= '9') trap("leading zero"); }
    else {
#if TP_FAST
        /* up to 8 digits at once: classify the 8 bytes, count the digit prefix, convert with the SWAR multiply chain */
        uint64_t w;
        memcpy(&w, d + i, 8);
        uint64_t nd = ((w + 0x4646464646464646ULL) | (w - 0x3030303030303030ULL)) & 0x8080808080808080ULL;
        unsigned len = nd ? (unsigned)(__builtin_ctzll(nd) >> 3) : 8;
        if (len < 8 && i + len <= n) {
            uint64_t x = w << (8 * (8 - len));               /* digits right-aligned in the high bytes */
            x = (x & 0x0F0F0F0F0F0F0F0FULL) * 2561 >> 8;
            x = (x & 0x00FF00FF00FF00FFULL) * 6553601 >> 16;
            x = (x & 0x0000FFFF0000FFFFULL) * 42949672960001ULL >> 32;
            v = (int64_t)x; i += len;
        } else
#endif
        {
            uint64_t acc = 0;
            int digits = 0;
            while (i < n && d[i] >= '0' && d[i] <= '9') { acc = acc * 10 + (uint64_t)(d[i] - '0'); i++; if (++digits > 18) trap("integer outside this model"); }
            v = (int64_t)acc;
        }
    }
    if (i < n && (d[i] == '.' || d[i] == 'e' || d[i] == 'E')) trap("float outside this model");
    *out = neg ? -v : v;
    return i;
}
/* validating skipper for any value (unknown keys) */
static int64_t TP(skip_value)(pctx *c, int64_t pos, int depth) {
    const unsigned char *d = c->d;
    int64_t n = c->n;
    if (depth > 64) trap("nesting too deep");
    pos = tp_skip_ws(d, n, pos);
    if (pos >= n) trap("unexpected end");
    unsigned char b = d[pos];
    if (b == '"') { int e; int64_t end = TP(scan_string)(d, n, pos + 1, &e); return end + 1; }
    if (b == '{' || b == '[') {
        unsigned char close = b == '{' ? '}' : ']';
        pos = tp_skip_ws(d, n, pos + 1);
        if (pos < n && d[pos] == close) return pos + 1;
        for (;;) {
            if (b == '{') {
                pos = tp_skip_ws(d, n, pos);
                if (pos >= n || d[pos] != '"') trap("object keys must be strings");
                int e; pos = TP(scan_string)(d, n, pos + 1, &e) + 1;
                pos = tp_skip_ws(d, n, pos);
                if (pos >= n || d[pos] != ':') trap("expected :");
                pos++;
            }
            pos = TP(skip_value)(c, pos, depth + 1);
            pos = tp_skip_ws(d, n, pos);
            if (pos >= n) trap("unterminated");
            if (d[pos] == close) return pos + 1;
            if (d[pos] != ',') trap("expected separator");
            pos++;
        }
    }
    if (b == 't') { if (pos + 4 <= n && !memcmp(d + pos, "true", 4)) return pos + 4; trap("bad literal"); }
    if (b == 'f') { if (pos + 5 <= n && !memcmp(d + pos, "false", 5)) return pos + 5; trap("bad literal"); }
    if (b == 'n') { if (pos + 4 <= n && !memcmp(d + pos, "null", 4)) return pos + 4; trap("bad literal"); }
    if (b == '-' || (b >= '0' && b <= '9')) {
        int64_t i = pos;
        if (d[i] == '-') i++;
        if (i >= n || d[i] < '0' || d[i] > '9') trap("number needs a digit");
        if (d[i] == '0') { i++; if (i < n && d[i] >= '0' && d[i] <= '9') trap("leading zero"); }
        else while (i < n && d[i] >= '0' && d[i] <= '9') i++;
        if (i < n && d[i] == '.') { i++; if (i >= n || d[i] < '0' || d[i] > '9') trap("fraction needs a digit"); while (i < n && d[i] >= '0' && d[i] <= '9') i++; }
        if (i < n && (d[i] == 'e' || d[i] == 'E')) { i++; if (i < n && (d[i] == '+' || d[i] == '-')) i++; if (i >= n || d[i] < '0' || d[i] > '9') trap("exponent needs a digit"); while (i < n && d[i] >= '0' && d[i] <= '9') i++; }
        return i;
    }
    trap("unexpected character");
}

static void *TP(parse)(void *vc) {
    pctx *c = vc;
    const unsigned char *d = c->d;
    int64_t n = c->n, pos = tp_skip_ws(d, n, 0);
    c->reg.used = 0;
    c->nrows = 0;
    if (pos >= n || d[pos] != '[') trap("expected an array of rows");
    pos = tp_skip_ws(d, n, pos + 1);
    if (pos < n && d[pos] == ']') pos++;
    else for (;;) {
        pos = tp_skip_ws(d, n, pos);
        if (pos >= n || d[pos] != '{') trap("expected an object row");
        row_t row = {0, 0, 0, 0, 0};
        unsigned seen = 0;
        int name_pending = 0;
        int64_t name_start = 0, name_end = 0;
        pos = tp_skip_ws(d, n, pos + 1);
        if (pos < n && d[pos] == '}') trap("missing fields");
        for (;;) {
            pos = tp_skip_ws(d, n, pos);
            if (pos >= n || d[pos] != '"') trap("object keys must be strings");
            span_t key; int kd;
            pos = TP(string)(c, pos, &key, &kd);
            if (kd) key = tp_decode(c, (int64_t)(key.p - d), (int64_t)(key.p - d) + (int64_t)key.n);
            pos = tp_skip_ws(d, n, pos);
            if (pos >= n || d[pos] != ':') trap("expected :");
            pos = tp_skip_ws(d, n, pos + 1);
            unsigned bit = 0;
            if (key.n == 2 && key.p[0] == 'i' && key.p[1] == 'd') bit = 1;
            else if (key.n == 4 && !memcmp(key.p, "name", 4)) bit = 2;
            else if (key.n == 6 && !memcmp(key.p, "amount", 6)) bit = 4;
            else if (key.n == 6 && !memcmp(key.p, "active", 6)) bit = 8;
            if (bit) {
                if (seen & bit) trap("duplicate key");
                seen |= bit;
                if (bit == 1) pos = TP(integer)(c, pos, &row.id);
                else if (bit == 4) pos = TP(integer)(c, pos, &row.amount);
                else if (bit == 2) {
                    span_t s; int nd;
                    if (pos >= n || d[pos] != '"') trap("name must be a string");
                    pos = TP(string)(c, pos, &s, &nd);
                    row.name = s.p; row.name_len = s.n;
                    if (nd) { name_pending = 1; name_start = (int64_t)(s.p - d); name_end = name_start + (int64_t)s.n; }
                } else {
                    if (pos + 4 <= n && !memcmp(d + pos, "true", 4)) { row.active = 1; pos += 4; }
                    else if (pos + 5 <= n && !memcmp(d + pos, "false", 5)) { row.active = 0; pos += 5; }
                    else trap("active must be a bool");
                }
            } else {
                pos = TP(skip_value)(c, pos, 3);
            }
            pos = tp_skip_ws(d, n, pos);
            if (pos >= n) trap("unterminated object");
            if (d[pos] == '}') { pos++; break; }
            if (d[pos] != ',') trap("expected , or }");
            pos++;
        }
        if (seen != 15) trap("row misses a field");
        if (name_pending && row.active) { span_t s = tp_decode(c, name_start, name_end); row.name = s.p; row.name_len = s.n; }
        c->rows[c->nrows++] = row;
        pos = tp_skip_ws(d, n, pos);
        if (pos >= n) trap("unterminated array");
        if (d[pos] == ']') { pos++; break; }
        if (d[pos] != ',') trap("expected , or ]");
        pos++;
    }
    pos = tp_skip_ws(d, n, pos);
    if (pos != n) trap("trailing characters");
    return c;
}

#undef TP
#undef TP_CAT
#undef TP_CAT2
#undef TP_PREFIX
#undef TP_FAST
#undef TP_LAZY
