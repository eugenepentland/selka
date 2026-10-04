// json_transform / parse component ladder. The timed region of the benchmark job
// (benchmarks/runtime/expanded/text/main.my, json_job):
//     json.loads(text) -> filter rows with "active" -> build {id, name, amount+bump} objects
//     -> json.dumps -> score(output)      (score = utf8 length + sum of utf8 bytes)
// This file implements the whole job so that every version reproduces the benchmark checksum, but
// the ladder varies ONLY the parse component (json.loads, plus releasing the tree it builds). The
// transform + serialize + score back end is one fixed, reasonable implementation shared by all
// versions; its time is excluded from the component time. The program prints
//     "checksum parse_ns whole_ns"   (version >= 1000 prints whole_ns in the second column).
// Usage: json_parse VERSION SIZE ITERATIONS SEED [DOCFILE]
//   untimed: document = compact json.dumps of SIZE rows
//       {"id": seed+j, "name": ("café,\"item\"" if j even else "naïve,item") + str(j),
//        "amount": (seed + 19 j) % 100003, "active": (seed + j) % 3 != 0}
//   DOCFILE replaces the generated document (the holdout: the same data, other formatting).
// Build with -fno-strict-aliasing.
#include "common.h"
#include <x86intrin.h>

/* ============================ document, reference rows, shared back end ============== */
typedef struct { int64_t id; const unsigned char *name; size_t name_len; int64_t amount; int active; } row_t;

static unsigned char *g_doc;
static size_t g_doc_len;

static void build_doc(int64_t size, int64_t seed) {
    size_t cap = (size_t)size * 128 + 64;
    unsigned char *d = malloc(cap), *p = d;
    *p++ = '[';
    for (int64_t j = 0; j < size; j++) {
        if (j) *p++ = ',';
        p += sprintf((char *)p, "{\"id\":%lld,\"name\":\"%s%lld\",\"amount\":%lld,\"active\":%s}", (long long)(seed + j),
                     j % 2 == 0 ? "caf\xc3\xa9,\\\"item\\\"" : "na\xc3\xafve,item", (long long)j,
                     (long long)((seed + j * 19) % 100003), (seed + j) % 3 != 0 ? "true" : "false");
    }
    *p++ = ']';
    g_doc = d;
    g_doc_len = (size_t)(p - d);
}

/* score(json.dumps(array(output))) for the active rows with amount + bump, keys in the order the job
 * builds them: id, name, amount. Strings escape '"', '\\' and controls as write_quoted does. */
static int64_t emit_score(const row_t *rows, size_t n, int64_t bump, unsigned char *out) {
    unsigned char *p = out;
    *p++ = '[';
    int first = 1;
    for (size_t i = 0; i < n; i++) {
        if (!rows[i].active) continue;
        if (!first) *p++ = ',';
        first = 0;
        memcpy(p, "{\"id\":", 6); p += 6;
        p += sprintf((char *)p, "%lld", (long long)rows[i].id);
        memcpy(p, ",\"name\":\"", 9); p += 9;
        for (size_t k = 0; k < rows[i].name_len; k++) {
            unsigned char c = rows[i].name[k];
            if (c == '"' || c == '\\') { *p++ = '\\'; *p++ = c; }
            else if (c < 32) {
                static const char hex[] = "0123456789abcdef";
                if (c == 8) { *p++ = '\\'; *p++ = 'b'; } else if (c == 9) { *p++ = '\\'; *p++ = 't'; }
                else if (c == 10) { *p++ = '\\'; *p++ = 'n'; } else if (c == 12) { *p++ = '\\'; *p++ = 'f'; }
                else if (c == 13) { *p++ = '\\'; *p++ = 'r'; }
                else { memcpy(p, "\\u00", 4); p += 4; *p++ = hex[c / 16]; *p++ = hex[c % 16]; }
            } else *p++ = c;
        }
        memcpy(p, "\",\"amount\":", 11); p += 11;
        p += sprintf((char *)p, "%lld", (long long)(rows[i].amount + bump));
        *p++ = '}';
    }
    *p++ = ']';
    int64_t total = (int64_t)(p - out);
    for (unsigned char *q = out; q < p; q++) total += *q;
    return total;
}

/* ============================= timing: rdtsc scaled to ns ============================ */
static double g_ns_per_tick;
static void calibrate(void) {
    int64_t t0 = now_ns(); uint64_t c0 = __rdtsc();
    while (now_ns() - t0 < 20000000) {}
    g_ns_per_tick = (double)(now_ns() - t0) / (double)(__rdtsc() - c0);
}

/* ================================== version interface ================================ */
typedef struct {
    void *(*parse)(void *ctx);                           /* build the version's tree/rows from the document */
    size_t (*extract)(void *ctx, void *tree, row_t *rows); /* untimed: expose rows[] to the back end */
    void (*teardown)(void *ctx, void *tree);              /* release the tree (timed with the parse) */
    void *ctx;
} version_t;

static int64_t drive(const version_t *v, int64_t size, int64_t iterations, int64_t seed, int64_t *parse_ns, int64_t *whole_ns) {
    row_t *rows = malloc(sizeof(row_t) * (size_t)size + 64);
    unsigned char *out = malloc((size_t)size * 160 + 64);
    int64_t checksum = 0;
    uint64_t ticks = 0;
    int64_t w0 = now_ns();
    for (int64_t step = 0; step < iterations; step++) {
        uint64_t a = __rdtsc();
        void *tree = v->parse(v->ctx);
        uint64_t b = __rdtsc();
        size_t n = v->extract(v->ctx, tree, rows);
        int64_t value = emit_score(rows, n, (seed + step) % 17, out);   /* rows still point into the tree */
        uint64_t c = __rdtsc();
        v->teardown(v->ctx, tree);
        uint64_t d = __rdtsc();
        ticks += (b - a) + (d - c);
        checksum = floormod(checksum + value, MOD);
    }
    if (getenv("JSON_DEBUG")) { void *t = v->parse(v->ctx); size_t n = v->extract(v->ctx, t, rows); for (size_t i = 0; i < n; i++) printf("row %zu id=%lld amount=%lld active=%d name=%.*s\n", i, (long long)rows[i].id, (long long)rows[i].amount, rows[i].active, (int)rows[i].name_len, rows[i].name); }
    *whole_ns = now_ns() - w0;
    *parse_ns = (int64_t)((double)ticks * g_ns_per_tick);
    free(rows); free(out);
    return checksum;
}

/* ==================================================================================== */
/* ---- v1: today's parser, transliterated from src/stdlib/json.my with mylang's representations ---
 *  - `Scanner` is a record passed `mut` by pointer: `position` lives in memory and every peek/advance
 *    goes through it; the document is a `bytes` object (copy made by source.encode()), indexed with a
 *    bounds check against its header;
 *  - every `Result[T, str]` is returned through memory (tag + payload);
 *  - each string is built in a fresh byte_buffer, snapshotted to bytes and decoded (validated and
 *    copied) into a new `str`; each number scans its digits twice (skip_digits, then parse_int_range);
 *    each literal slices the document (a copy) and compares it;
 *  - objects are insertion-ordered dictionaries: key membership probe, entry append, hash-index insert;
 *    arrays are lists with doubling growth;
 *  - all objects are RC blocks released at the end through the deferred drain queue.
 */
typedef struct { uint64_t refcount, flags; } rc_head;
enum { J_NULL, J_BOOL, J_INT, J_NUM, J_TEXT, J_ARRAY, J_OBJECT };
typedef struct { uint32_t tag, pad; union { int64_t i; double f; void *p; } v; } json_t;
typedef struct { rc_head rc; size_t length, bytes; uint32_t flags, hash; } str_o;       /* payload follows */
typedef struct { rc_head rc; int64_t len, cap, gen; const void *elem; unsigned char *data; } bytes_o;
typedef struct { rc_head rc; int64_t len, cap, gen; const void *elem; json_t *data; } jlist_o;
typedef struct { str_o *key; json_t value; } dentry;
typedef struct { rc_head rc; int64_t len, cap; dentry *entries; uint64_t *index; size_t index_cap; } jdict_o;
typedef struct { bytes_o *data; int64_t position; } scanner_t;
typedef struct { int ok; json_t value; } res_json;
typedef struct { int ok; str_o *s; } res_str;
typedef struct { int ok; } res_bool;

static void *g_dead[1 << 16];
static size_t g_dead_n;
static void drain(void) { while (g_dead_n) free(g_dead[--g_dead_n]); }
static inline void rc_dec(void *obj, rc_head *rc);
static void release_json(json_t v);
static inline void rc_dec(void *obj, rc_head *rc) {
    if (--rc->refcount == 0) {
        if (g_dead_n == (1 << 16)) drain();
        g_dead[g_dead_n++] = obj;
    }
}
static const void *g_elem = &g_elem;
static inline unsigned char *str_payload(str_o *s) { return (unsigned char *)(s + 1); }

static int64_t g_alloc_count;
static void *xmalloc(size_t n) { g_alloc_count++; return malloc(n); }

static bytes_o *new_bytes(const unsigned char *src, size_t n) {
    bytes_o *b = xmalloc(sizeof *b);
    b->rc.refcount = 1; b->rc.flags = 0;
    b->len = b->cap = (int64_t)n; b->gen = 0; b->elem = g_elem;
    b->data = xmalloc(n ? n : 1);
    memcpy(b->data, src, n);
    return b;
}
static void free_bytes(bytes_o *b) { free(b->data); free(b); }

/* Reading `scanner.data` copies the field out of the record, which retains the bytes object, and the copy
 * is released when the helper returns (visible in B0's skip_whitespace: a refcount increment and decrement
 * around every at_end/peek, plus a 16-byte copy of the record). The empty asm keeps the pair from being
 * folded away, as the RC protocol's memory side effects are in the real code. */
static inline bytes_o *acquire(const scanner_t *s) {
    scanner_t copy = *s;
    bytes_o *d = copy.data;
    if (d->rc.flags & 0x4000000000000000ULL) trap("rc");
    d->rc.refcount++;
    __asm__ volatile("" : : "r"(d) : "memory");
    return d;
}
static inline void release(bytes_o *d) {
    __asm__ volatile("" : : "r"(d) : "memory");
    if (--d->rc.refcount == 0) trap("rc underflow");
}
static inline int at_end(const scanner_t *s) {
    bytes_o *d = acquire(s);
    int r = s->position >= d->len;
    release(d);
    return r;
}
static inline int64_t peek(const scanner_t *s) {
    if (at_end(s)) return -1;
    bytes_o *d = acquire(s);
    if ((uint64_t)s->position >= (uint64_t)d->len) trap("index");
    int64_t b = d->data[s->position];
    release(d);
    return b;
}
static inline void advance(scanner_t *s) {
    int64_t p;
    if (__builtin_add_overflow(s->position, 1, &p)) trap("overflow");
    s->position = p;
}
__attribute__((noinline)) static void skip_whitespace(scanner_t *s) {
    while (!at_end(s)) {
        int64_t b = peek(s);
        if (b != 32 && b != 9 && b != 10 && b != 13) return;
        advance(s);
    }
}
__attribute__((noinline)) static void skip_digits(scanner_t *s) {
    while (!at_end(s) && peek(s) >= 48 && peek(s) <= 57) advance(s);
}
static res_json err_json(void) { trap("JSON error"); }

/* a byte_buffer: header + growing storage */
typedef struct { bytes_o *b; } buf_t;
static buf_t buf_new(void) {
    buf_t bf; bf.b = new_bytes((const unsigned char *)"", 0);
    bf.b->cap = 0; free(bf.b->data); bf.b->data = NULL;
    return bf;
}
static void buf_append_range(buf_t *bf, const bytes_o *src, int64_t start, int64_t end) {
    int64_t n = end - start, need = bf->b->len + n;
    if (need > bf->b->cap) {
        int64_t cap = bf->b->cap < 8 ? 8 : bf->b->cap * 2;
        while (cap < need) cap *= 2;
        bf->b->data = realloc(bf->b->data, (size_t)cap);
        bf->b->cap = cap;
    }
    memcpy(bf->b->data + bf->b->len, src->data + start, (size_t)n);
    bf->b->len = need;
}
static void buf_append_byte(buf_t *bf, int c) {
    if (bf->b->len >= bf->b->cap) {
        int64_t cap = bf->b->cap < 8 ? 8 : bf->b->cap * 2;
        bf->b->data = realloc(bf->b->data, (size_t)cap);
        bf->b->cap = cap;
    }
    bf->b->data[bf->b->len++] = (unsigned char)c;
}
/* bytes(values).decode(): snapshot, validate UTF-8, build a str */
static int utf8_valid_len(const unsigned char *p, size_t n, size_t *scalars) {
    size_t i = 0, count = 0;
    while (i < n) {
        unsigned c = p[i];
        size_t k = c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : (c >> 3) == 30 ? 4 : 0;
        if (!k || i + k > n) return 0;
        for (size_t m = 1; m < k; m++) if ((p[i + m] & 0xC0) != 0x80) return 0;
        i += k; count++;
    }
    *scalars = count;
    return 1;
}
static str_o *decode_buf(buf_t *bf) {
    bytes_o *snap = new_bytes(bf->b->data ? bf->b->data : (const unsigned char *)"", (size_t)bf->b->len);
    size_t scalars;
    if (!utf8_valid_len(snap->data, (size_t)snap->len, &scalars)) trap("not UTF-8");
    str_o *s = xmalloc(sizeof *s + (size_t)snap->len + 1);
    s->rc.refcount = 1; s->rc.flags = 0;
    s->length = scalars; s->bytes = (size_t)snap->len; s->flags = 0; s->hash = 0;
    memcpy(str_payload(s), snap->data, (size_t)snap->len);
    free_bytes(snap);
    return s;
}
static void free_buf(buf_t *bf) { free(bf->b->data); free(bf->b); }

__attribute__((noinline)) static int read_escape(scanner_t *s, buf_t *out) {
    if (at_end(s)) trap("unterminated escape");
    int64_t b = peek(s);
    advance(s);
    if (b == 34 || b == 92 || b == 47) { buf_append_byte(out, (int)b); return 1; }
    if (b == 98) { buf_append_byte(out, 8); return 1; }
    if (b == 102) { buf_append_byte(out, 12); return 1; }
    if (b == 110) { buf_append_byte(out, 10); return 1; }
    if (b == 114) { buf_append_byte(out, 13); return 1; }
    if (b == 116) { buf_append_byte(out, 9); return 1; }
    if (b != 117) trap("unknown escape");
    int64_t code = 0;
    for (int i = 0; i < 4; i++) {
        if (at_end(s)) trap("truncated unicode escape");
        int64_t h = peek(s), v = h >= 48 && h <= 57 ? h - 48 : h >= 97 && h <= 102 ? h - 87 : h >= 65 && h <= 70 ? h - 55 : -1;
        if (v < 0) trap("bad hex digit");
        code = code * 16 + v;
        advance(s);
    }
    if (code >= 0xD800 && code < 0xE000) trap("surrogate escapes are outside this model");
    if (code < 128) buf_append_byte(out, (int)code);
    else if (code < 2048) { buf_append_byte(out, (int)(192 + code / 64)); buf_append_byte(out, (int)(128 + code % 64)); }
    else { buf_append_byte(out, (int)(224 + code / 4096)); buf_append_byte(out, (int)(128 + code / 64 % 64)); buf_append_byte(out, (int)(128 + code % 64)); }
    return 1;
}
__attribute__((noinline)) static res_str read_string(scanner_t *s) {
    advance(s);
    buf_t out = buf_new();
    int64_t span = s->position, offset = span;
    for (;;) {
        bytes_o *dd = acquire(s);
        int more = offset < dd->len;
        release(dd);
        if (!more) break;
        dd = acquire(s);
        if ((uint64_t)offset >= (uint64_t)dd->len) trap("index");
        int64_t byte = dd->data[offset];
        release(dd);
        offset += 1;
        if (byte == 34) {
            s->position = offset;
            buf_append_range(&out, s->data, span, offset - 1);
            str_o *r = decode_buf(&out);
            free_buf(&out);
            return (res_str){1, r};
        }
        if (byte < 32) trap("control character in string");
        if (byte == 92) {
            s->position = offset;
            buf_append_range(&out, s->data, span, offset - 1);
            read_escape(s, &out);
            offset = s->position;
            span = offset;
        }
    }
    trap("unterminated string");
}
__attribute__((noinline)) static int read_integer_part(scanner_t *s) {
    if (peek(s) == 45) advance(s);
    if (at_end(s) || !(peek(s) >= 48 && peek(s) <= 57)) trap("number needs a digit");
    if (peek(s) != 48) { skip_digits(s); return 1; }
    advance(s);
    if (!at_end(s) && peek(s) >= 48 && peek(s) <= 57) trap("leading zero");
    return 1;
}
__attribute__((noinline)) static int read_fraction(scanner_t *s) {
    if (at_end(s) || peek(s) != 46) return 0;
    advance(s);
    if (at_end(s) || !(peek(s) >= 48 && peek(s) <= 57)) trap("fraction needs a digit");
    skip_digits(s);
    return 1;
}
__attribute__((noinline)) static int read_exponent(scanner_t *s) {
    if (at_end(s)) return 0;
    if (peek(s) != 101 && peek(s) != 69) return 0;
    advance(s);
    if (peek(s) == 43 || peek(s) == 45) advance(s);
    if (at_end(s) || !(peek(s) >= 48 && peek(s) <= 57)) trap("exponent needs a digit");
    skip_digits(s);
    return 1;
}
/* data.parse_int_range(start, end): the second pass over the digits */
__attribute__((noinline)) static int parse_int_range(const bytes_o *d, int64_t start, int64_t end, int64_t *out) {
    int64_t i = start, neg = 0, v = 0;
    if (i < end && d->data[i] == '-') { neg = 1; i++; }
    for (; i < end; i++) {
        if (__builtin_mul_overflow(v, 10, &v) || __builtin_add_overflow(v, d->data[i] - '0', &v)) return 0;
    }
    *out = neg ? -v : v;
    return 1;
}
__attribute__((noinline)) static res_json read_number(scanner_t *s) {
    int64_t start = s->position;
    read_integer_part(s);
    int floating = read_fraction(s);
    if (read_exponent(s)) floating = 1;
    if (!floating) {
        int64_t v;
        if (parse_int_range(s->data, start, s->position, &v)) return (res_json){1, {J_INT, 0, {.i = v}}};
    }
    trap("float numbers are outside this model");
}
__attribute__((noinline)) static res_json read_literal(scanner_t *s, const char *word, size_t wl, json_t value) {
    int64_t start = s->position;
    if (start + (int64_t)wl > s->data->len) trap("truncated literal");
    bytes_o *slice = new_bytes(s->data->data + start, wl);      /* data[start:start+len(word)] copies */
    int same = memcmp(slice->data, word, wl) == 0;
    free_bytes(slice);
    if (!same) trap("unknown literal");
    s->position = start + (int64_t)wl;
    return (res_json){1, value};
}

/* dictionaries: insertion-ordered entries + a hash index of (hash<<32 | entry+1) slots */
static uint32_t str_hash(str_o *s) {
    if (s->flags & 2u) return s->hash;
    uint64_t h = 0x9e3779b97f4a7c15ULL;
    const unsigned char *p = str_payload(s);
    size_t n = s->bytes, i = 0;
    for (; i + 8 <= n; i += 8) { uint64_t w; memcpy(&w, p + i, 8); unsigned __int128 m = (unsigned __int128)(h ^ w) * 0xbf58476d1ce4e5b9ULL; h = (uint64_t)m ^ (uint64_t)(m >> 64); }
    uint64_t w = 0; memcpy(&w, p + i, n - i);
    unsigned __int128 m = (unsigned __int128)(h ^ w ^ n) * 0xbf58476d1ce4e5b9ULL; h = (uint64_t)m ^ (uint64_t)(m >> 64);
    s->hash = (uint32_t)(h ^ (h >> 32)); s->flags |= 2u;
    return s->hash;
}
static jdict_o *dict_new(void) {
    jdict_o *d = xmalloc(sizeof *d);
    memset(d, 0, sizeof *d);
    d->rc.refcount = 1;
    return d;
}
static int64_t dict_find(jdict_o *d, str_o *key) {
    if (!d->index_cap) return -1;
    uint32_t h = str_hash(key);
    size_t mask = d->index_cap - 1, at = h & mask;
    for (uint64_t slot; (slot = d->index[at]); at = (at + 1) & mask) {
        if ((uint32_t)(slot >> 32) != h) continue;
        dentry *e = &d->entries[(slot & 0xffffffffu) - 1];
        if (e->key->bytes == key->bytes && memcmp(str_payload(e->key), str_payload(key), key->bytes) == 0) return (int64_t)((slot & 0xffffffffu) - 1);
    }
    return -1;
}
static void dict_insert(jdict_o *d, str_o *key, json_t value) {
    if (d->len >= d->cap) {
        d->cap = d->cap < 4 ? 4 : d->cap * 2;
        d->entries = realloc(d->entries, (size_t)d->cap * sizeof(dentry));
    }
    d->entries[d->len] = (dentry){key, value};
    d->len++;
    if ((size_t)d->len * 8 > d->index_cap * 5) {   /* load factor 5/8 */
        size_t cap = d->index_cap ? d->index_cap * 2 : 8;
        while ((size_t)d->len * 8 > cap * 5) cap *= 2;
        uint64_t *idx = xmalloc(cap * 8);
        memset(idx, 0, cap * 8);
        for (int64_t i = 0; i < d->len; i++) {
            uint32_t h = str_hash(d->entries[i].key);
            size_t at = h & (cap - 1);
            while (idx[at]) at = (at + 1) & (cap - 1);
            idx[at] = (uint64_t)h << 32 | (uint64_t)(i + 1);
        }
        free(d->index);
        d->index = idx; d->index_cap = cap;
    } else {
        uint32_t h = str_hash(key);
        size_t at = h & (d->index_cap - 1);
        while (d->index[at]) at = (at + 1) & (d->index_cap - 1);
        d->index[at] = (uint64_t)h << 32 | (uint64_t)d->len;
    }
}
static jlist_o *list_new(void) {
    jlist_o *l = xmalloc(sizeof *l);
    memset(l, 0, sizeof *l);
    l->rc.refcount = 1; l->elem = g_elem;
    return l;
}
static void list_append(jlist_o *l, json_t v) {
    if (l->len >= l->cap) {
        l->cap = l->cap < 4 ? 4 : l->cap * 2;
        l->data = realloc(l->data, (size_t)l->cap * sizeof(json_t));
    }
    l->data[l->len++] = v;
    l->gen++;
}
static void release_json(json_t v) {
    if (v.tag == J_TEXT) { str_o *s = v.v.p; rc_dec(s, &s->rc); }
    else if (v.tag == J_ARRAY) {
        jlist_o *l = v.v.p;
        if (--l->rc.refcount == 0) { for (int64_t i = 0; i < l->len; i++) release_json(l->data[i]); free(l->data); if (g_dead_n == (1 << 16)) drain(); g_dead[g_dead_n++] = l; }
    } else if (v.tag == J_OBJECT) {
        jdict_o *d = v.v.p;
        if (--d->rc.refcount == 0) {
            for (int64_t i = 0; i < d->len; i++) { rc_dec(d->entries[i].key, &d->entries[i].key->rc); release_json(d->entries[i].value); }
            free(d->entries); free(d->index);
            if (g_dead_n == (1 << 16)) drain();
            g_dead[g_dead_n++] = d;
        }
    }
}

__attribute__((noinline)) static res_json read_value(scanner_t *s, int64_t depth);
__attribute__((noinline)) static res_json read_array(scanner_t *s, int64_t depth) {
    advance(s);
    jlist_o *items = list_new();
    skip_whitespace(s);
    if (peek(s) == 93) { advance(s); return (res_json){1, {J_ARRAY, 0, {.p = items}}}; }
    while (!at_end(s)) {
        res_json r = read_value(s, depth + 1);
        list_append(items, r.value);
        skip_whitespace(s);
        int64_t byte = peek(s);
        if (byte == 93) { advance(s); return (res_json){1, {J_ARRAY, 0, {.p = items}}}; }
        if (byte != 44) trap("expected , or ]");
        advance(s);
    }
    trap("unterminated array");
}
__attribute__((noinline)) static res_bool read_member(scanner_t *s, jdict_o *fields, int64_t depth) {
    skip_whitespace(s);
    if (peek(s) != 34) trap("object keys must be strings");
    res_str key = read_string(s);
    if (dict_find(fields, key.s) >= 0) trap("duplicate key");
    skip_whitespace(s);
    if (peek(s) != 58) trap("expected :");
    advance(s);
    res_json v = read_value(s, depth + 1);
    dict_insert(fields, key.s, v.value);
    return (res_bool){1};
}
__attribute__((noinline)) static res_json read_object(scanner_t *s, int64_t depth) {
    advance(s);
    jdict_o *fields = dict_new();
    skip_whitespace(s);
    if (peek(s) == 125) { advance(s); return (res_json){1, {J_OBJECT, 0, {.p = fields}}}; }
    while (!at_end(s)) {
        read_member(s, fields, depth);
        skip_whitespace(s);
        int64_t byte = peek(s);
        if (byte == 125) { advance(s); return (res_json){1, {J_OBJECT, 0, {.p = fields}}}; }
        if (byte != 44) trap("expected , or }");
        advance(s);
    }
    trap("unterminated object");
}
__attribute__((noinline)) static res_json read_value(scanner_t *s, int64_t depth) {
    if (depth > 64) trap("nesting too deep");
    skip_whitespace(s);
    int64_t byte = peek(s);
    if (byte == 123) return read_object(s, depth);
    if (byte == 91) return read_array(s, depth);
    if (byte == 34) { res_str r = read_string(s); return (res_json){1, {J_TEXT, 0, {.p = r.s}}}; }
    if (byte == 116) return read_literal(s, "true", 4, (json_t){J_BOOL, 0, {.i = 1}});
    if (byte == 102) return read_literal(s, "false", 5, (json_t){J_BOOL, 0, {.i = 0}});
    if (byte == 110) return read_literal(s, "null", 4, (json_t){J_NULL, 0, {.i = 0}});
    if (byte == 45 || (byte >= 48 && byte <= 57)) return read_number(s);
    trap("unexpected character");
}

typedef struct { const unsigned char *doc; size_t len; str_o *source; } v1_ctx;
static void *v1_parse(void *c) {
    v1_ctx *ctx = c;
    bytes_o *data = new_bytes(ctx->doc, ctx->len);                 /* source.encode() */
    scanner_t sc = { data, 0 };
    res_json r = read_value(&sc, 1);
    skip_whitespace(&sc);
    if (!at_end(&sc)) trap("trailing characters");
    free_bytes(data);
    json_t *boxed = xmalloc(sizeof *boxed);
    *boxed = r.value;
    return boxed;
}
static const unsigned char *dkey(jdict_o *d, const char *name, size_t nl, json_t *out) {
    for (int64_t i = 0; i < d->len; i++)
        if (d->entries[i].key->bytes == nl && memcmp(str_payload(d->entries[i].key), name, nl) == 0) { *out = d->entries[i].value; return (const unsigned char *)1; }
    trap("missing key");
}
static size_t v1_extract(void *c, void *tree, row_t *rows) {
    (void)c;
    json_t *root = tree;
    jlist_o *arr = root->v.p;
    for (int64_t i = 0; i < arr->len; i++) {
        jdict_o *d = arr->data[i].v.p;
        json_t a, id, name, amt;
        dkey(d, "active", 6, &a); dkey(d, "id", 2, &id); dkey(d, "name", 4, &name); dkey(d, "amount", 6, &amt);
        str_o *ns = name.v.p;
        rows[i] = (row_t){id.v.i, str_payload(ns), ns->bytes, amt.v.i, (int)a.v.i};
    }
    return (size_t)arr->len;
}
static void v1_teardown(void *c, void *tree) {
    (void)c;
    json_t *root = tree;
    release_json(*root);
    free(root);
    drain();
}

/* ==================================================================================== */
/* The remaining versions parse straight from the document bytes. */

/* a bump region for per-job objects */
typedef struct { unsigned char *base; size_t used, cap; } region_t;
static inline void *ralloc(region_t *r, size_t n) {
    n = (n + 15) & ~(size_t)15;
    if (r->used + n > r->cap) trap("region exhausted");
    void *p = r->base + r->used;
    r->used += n;
    return p;
}
typedef struct { const unsigned char *p; size_t n; } span_t;

/* ---- generic-tree parsers (v2..v6): json_gen.h, instantiated with the flags that are still on ---- */
#define GP_PREFIX v2_   /* v1's work with a register scanner: everything else still on */
#define GP_CFG (CFG_RC | CFG_ENCCOPY | CFG_COPYSTR | CFG_TWOPASS | CFG_DICT | CFG_LITCOPY)
#include "json_gen.h"
#define GP_PREFIX v3_   /* + bump region, no RC/drain */
#define GP_CFG (CFG_ENCCOPY | CFG_COPYSTR | CFG_TWOPASS | CFG_DICT | CFG_LITCOPY)
#include "json_gen.h"
#define GP_PREFIX v4_   /* + borrowed document, string views, in-place literals */
#define GP_CFG (CFG_TWOPASS | CFG_DICT)
#include "json_gen.h"
#define GP_PREFIX v5_   /* + single-pass integers */
#define GP_CFG (CFG_DICT)
#include "json_gen.h"
#define GP_PREFIX v6_   /* + flat objects instead of hash dictionaries */
#define GP_CFG 0
#include "json_gen.h"

/* ---- schema-directed parsers (v7..v9): json_typed.h ---- */
#include "json_typed.h"
#define TP_PREFIX t7_   /* rows straight from the bytes */
#define TP_FAST 0
#define TP_LAZY 0
#include "json_typed.h"
#define TP_PREFIX t8_   /* + demand-driven string decoding */
#define TP_FAST 0
#define TP_LAZY 1
#include "json_typed.h"
#ifdef __AVX2__
#define TP_PREFIX t9_   /* + AVX2 string scan, SWAR integers */
#define TP_FAST 1
#define TP_LAZY 1
#include "json_typed.h"
#endif

/* extraction from a generic tree (untimed) */
static size_t g_extract(void *vc, void *tree, row_t *rows) {
    (void)vc;
    gnode *root = tree;
    if (root->tag != G_ARRAY) trap("document is not an array");
    gnode *items = root->u.ptr;
    for (uint32_t i = 0; i < root->len; i++) {
        gobj *o = items[i].u.ptr;
        row_t r = {0, 0, 0, 0, 0};
        unsigned seen = 0;
        for (int64_t k = 0; k < o->len; k++) {
            gentry *e = &o->entries[k];
            if (e->key.n == 2 && !memcmp(e->key.p, "id", 2)) { r.id = e->value.u.i; seen |= 1; }
            else if (e->key.n == 4 && !memcmp(e->key.p, "name", 4)) { r.name = e->value.u.p; r.name_len = e->value.len; seen |= 2; }
            else if (e->key.n == 6 && !memcmp(e->key.p, "amount", 6)) { r.amount = e->value.u.i; seen |= 4; }
            else if (e->key.n == 6 && !memcmp(e->key.p, "active", 6)) { r.active = (int)e->value.u.i; seen |= 8; }
        }
        if (seen != 15) trap("row misses a field");
        rows[i] = r;
    }
    return root->len;
}
static size_t typed_extract(void *vc, void *tree, row_t *rows) {
    pctx *c = vc;
    (void)tree;
    memcpy(rows, c->rows, c->nrows * sizeof(row_t));
    return c->nrows;
}
static void no_teardown(void *vc, void *tree) { (void)vc; (void)tree; }

/* ============================= driver glue and main ============================= */
static int64_t *g_hole;
int main(int argc, char **argv) {
    if (argc == 5 && (!strcmp(argv[1], "gen") || !strcmp(argv[1], "genpretty"))) {
        /* gen SIZE SEED PATH: the benchmark document. genpretty: same data, pretty-printed with whitespace,
         * reordered keys, an extra nested field and é escapes, to exercise the general paths. */
        int64_t size = atoll(argv[2]), seed = atoll(argv[3]);
        FILE *f = fopen(argv[4], "wb");
        if (!strcmp(argv[1], "gen")) { build_doc(size, seed); fwrite(g_doc, 1, g_doc_len, f); }
        else {
            fprintf(f, "[\n");
            for (int64_t j = 0; j < size; j++) {
                fprintf(f, "%s  { \"active\" : %s,\n    \"extra\": {\"k\": [1, -25, null, \"x\\ny\"]},\n    \"amount\" : %lld ,\n    \"name\": \"%s%lld\",\n    \"id\":%lld }\n",
                        j ? ",\n" : "", (seed + j) % 3 != 0 ? "true" : "false", (long long)((seed + j * 19) % 100003),
                        j % 2 == 0 ? "caf\\u00e9,\\\"item\\\"" : "na\xc3\xafve,item", (long long)j, (long long)(seed + j));
            }
            fprintf(f, "]\n");
        }
        fclose(f);
        return 0;
    }
    if (argc < 5) return 2;
    int which = atoi(argv[1]);
    int whole = which >= 1000;
    if (whole) which -= 1000;
    int64_t size = atoll(argv[2]), iterations = atoll(argv[3]), seed = atoll(argv[4]);
    if (argc == 6) {
        FILE *f = fopen(argv[5], "rb");
        if (!f) { perror("fopen"); return 2; }
        fseek(f, 0, SEEK_END); g_doc_len = (size_t)ftell(f); fseek(f, 0, SEEK_SET);
        g_doc = malloc(g_doc_len + 64);
        if (fread(g_doc, 1, g_doc_len, f) != g_doc_len) return 2;
        fclose(f);
    } else {
        if (which >= 30) return 2;
        build_doc(size, seed);
    }
    calibrate();
    /* the document buffer carries tail padding so vector/SWAR loads may run past the end */
    { unsigned char *padded = malloc(g_doc_len + 64); memcpy(padded, g_doc, g_doc_len); memset(padded + g_doc_len, 0, 64); g_doc = padded; }
    v1_ctx c1 = { g_doc, g_doc_len, NULL };
    gctx gc = { g_doc, (int64_t)g_doc_len, g_doc, { malloc(g_doc_len * 12 + 65536), 0, g_doc_len * 12 + 65536 }, NULL, 0, 0, {0, 0, {0}} };
    pctx pc = { g_doc, (int64_t)g_doc_len, { malloc(g_doc_len * 4 + 65536), 0, g_doc_len * 4 + 65536 }, malloc(sizeof(row_t) * (size_t)size + 64), 0 };
    version_t v;
    switch (which) {
    case 1: case 20: v = (version_t){ v1_parse, v1_extract, v1_teardown, &c1 }; break;
    case 2: v = (version_t){ v2_parse, g_extract, v2_teardown, &gc }; break;
    case 3: v = (version_t){ v3_parse, g_extract, v3_teardown, &gc }; break;
    case 4: v = (version_t){ v4_parse, g_extract, v4_teardown, &gc }; break;
    case 5: v = (version_t){ v5_parse, g_extract, v5_teardown, &gc }; break;
    case 6: v = (version_t){ v6_parse, g_extract, v6_teardown, &gc }; break;
    case 7: case 30: v = (version_t){ t7_parse, typed_extract, no_teardown, &pc }; break;
    case 8: v = (version_t){ t8_parse, typed_extract, no_teardown, &pc }; break;
#ifdef __AVX2__
    case 9: case 31: v = (version_t){ t9_parse, typed_extract, no_teardown, &pc }; break;
#endif
    default: return 2;
    }
    int64_t parse_ns, whole_ns;
    int64_t checksum = drive(&v, size, iterations, seed, &parse_ns, &whole_ns);
    printf("%lld %lld\n", (long long)checksum, (long long)(whole ? whole_ns : parse_ns));
    return 0;
}
