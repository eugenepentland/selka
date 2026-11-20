/* The derived JSON codec's runtime (`json.encode` and `json.decode`, CODEC-1 step 1; `build_json.zig` writes the
 * adapters that call it). A document is parsed once into a tape of nodes; each node knows its parent, its next sibling
 * and the member name or index it sits under, so a decoder reads members by name in any order and an error names its
 * field path. Integers are read from their token, exactly, against the field's width. The first error is kept with its
 * kind, path, byte offset and sentence; after it every read answers a placeholder. A handle is the state's address. */
#include <ctype.h>
#include <inttypes.h>
#include <math.h>
#include <stdarg.h>

enum { JSON_NULL, JSON_FALSE, JSON_TRUE, JSON_NUMBER, JSON_STRING, JSON_ARRAY, JSON_OBJECT };
/* The kinds of `json.CodecErrorKind`, in declaration order. */
enum { JSON_E_SYNTAX, JSON_E_MISSING, JSON_E_UNEXPECTED, JSON_E_RANGE, JSON_E_UNKNOWN_MEMBER, JSON_E_UNKNOWN_CASE, JSON_E_DUPLICATE, JSON_E_UNWRITABLE, JSON_E_INVARIANT };
enum { JSON_KEY_ESCAPED = 1, JSON_MATCHED = 2 };
/* The deepest nesting of arrays and objects either direction takes, so `json.decode` reads what `json.encode` wrote.
 * A name echoed in a sentence is cut at JSON_ECHO bytes, and a path in a sentence keeps its first and last JSON_PATH_PART. */
enum { JSON_MAX_DEPTH = 1000, JSON_ECHO = 80, JSON_PATH_PART = 60 };

typedef struct {
    uint8_t kind, flags;
    uint32_t count;      /* children of an array or object */
    int64_t start, end;  /* the value's bytes */
    int64_t parent, next, cursor;
    int64_t key_start, key_end; /* a member's name, between its quotes (escaped form) */
    int64_t index;       /* an element's position */
} json_node;

typedef struct { const unsigned char *key; uint64_t key_len; int64_t index; bool object; } json_frame;

typedef struct {
    const unsigned char *data;
    int64_t len;
    json_node *nodes;
    int64_t count, capacity;
    /* the writer */
    char *out;
    size_t out_len, out_cap;
    json_frame *frames;
    size_t depth, frames_cap;
    /* the first error */
    bool failed;
    int kind;
    int64_t offset;
    char *path, *message;
} json_state;

static json_state *json_of(uint64_t handle) { return (json_state *)(uintptr_t)handle; }

/* ---- small text buffers ------------------------------------------------------- */

typedef struct { char *data; size_t len, cap; } json_text;
static void json_text_add(json_text *t, const void *bytes, size_t n) {
    if (n > SIZE_MAX - t->len - 1) out_of_memory();
    if (t->len + n + 1 > t->cap) {
        size_t cap = t->cap ? t->cap : 64;
        while (cap < t->len + n + 1) {
            if (cap > SIZE_MAX / 2) out_of_memory();
            cap *= 2;
        }
        char *data = realloc(t->data, cap);
        if (!data) out_of_memory();
        t->data = data;
        t->cap = cap;
    }
    if (n) memcpy(t->data + t->len, bytes, n);
    t->len += n;
    t->data[t->len] = 0;
}
static void json_text_str(json_text *t, const char *s) { json_text_add(t, s, strlen(s)); }
static void json_text_fmt(json_text *t, const char *format, ...) {
    char small[256];
    va_list args;
    va_start(args, format);
    int n = vsnprintf(small, sizeof small, format, args);
    va_end(args);
    if (n < 0) return;
    if ((size_t)n < sizeof small) { json_text_add(t, small, (size_t)n); return; }
    char *big = malloc((size_t)n + 1);
    if (!big) out_of_memory();
    va_start(args, format);
    vsnprintf(big, (size_t)n + 1, format, args);
    va_end(args);
    json_text_add(t, big, (size_t)n);
    free(big);
}
static void json_text_vfmt(json_text *t, const char *format, va_list args) {
    va_list again;
    va_copy(again, args);
    int n = vsnprintf(NULL, 0, format, again);
    va_end(again);
    if (n < 0) return;
    char *text = malloc((size_t)n + 1);
    if (!text) out_of_memory();
    vsnprintf(text, (size_t)n + 1, format, args);
    json_text_add(t, text, (size_t)n);
    free(text);
}
/* The length of the longest prefix of `s` no longer than `cap` bytes that ends on a UTF-8 character boundary. */
static size_t json_boundary(const unsigned char *s, size_t len, size_t cap) {
    if (len <= cap) return len;
    size_t at = cap;
    while (at > 0 && (s[at] & 0xC0) == 0x80) --at;
    return at;
}
/* Append `s` as JSON writes it inside quotes (`\"`, `\\`, `\n`, `\u0000`), so no control byte or quote reaches a path or
 * a sentence raw; with `cap` nonzero, a longer text is cut on a character boundary and ends in `...`. */
static void json_spell(json_text *t, const unsigned char *s, size_t len, size_t cap) {
    static const char hex[] = "0123456789abcdef";
    size_t keep = cap ? json_boundary(s, len, cap) : len;
    for (size_t i = 0; i < keep; ++i) {
        unsigned char c = s[i];
        if (c == '"' || c == '\\') { char e[2] = {'\\', (char)c}; json_text_add(t, e, 2); }
        else if (c == '\n') json_text_add(t, "\\n", 2);
        else if (c == '\r') json_text_add(t, "\\r", 2);
        else if (c == '\t') json_text_add(t, "\\t", 2);
        else if (c == '\b') json_text_add(t, "\\b", 2);
        else if (c == '\f') json_text_add(t, "\\f", 2);
        else if (c < 0x20) { char e[6] = {'\\', 'u', '0', '0', hex[c >> 4], hex[c & 15]}; json_text_add(t, e, 6); }
        else json_text_add(t, &c, 1);
    }
    if (keep < len) json_text_add(t, "...", 3);
}
static char *json_text_take(json_text *t) {
    if (!t->data) json_text_add(t, "", 0);
    return t->data;
}

/* ---- paths and errors ---------------------------------------------------------- */

static bool json_unescape(const unsigned char *s, int64_t start, int64_t end, json_text *t, int64_t *bad);

/* Append a member's name as the document means it (its escapes decoded), spelled as JSON writes it. */
static void json_key(const json_state *st, const json_node *n, json_text *out) {
    const unsigned char *raw = st->data + n->key_start;
    size_t raw_len = (size_t)(n->key_end - n->key_start);
    if (!(n->flags & JSON_KEY_ESCAPED)) { json_spell(out, raw, raw_len, 0); return; }
    json_text decoded = {0};
    int64_t bad;
    if (json_unescape(st->data, n->key_start, n->key_end, &decoded, &bad)) json_spell(out, (const unsigned char *)decoded.data, decoded.len, 0);
    else json_text_add(out, raw, raw_len);
    free(decoded.data);
}

/* Append the path of `node` (`items[3].stamp`), or nothing for the whole document. */
static void json_path_of(const json_state *st, int64_t node, json_text *out) {
    if (node <= 0 || node >= st->count) return;
    int64_t parent = st->nodes[node].parent;
    json_path_of(st, parent, out);
    const json_node *n = &st->nodes[node];
    if (parent >= 0 && st->nodes[parent].kind == JSON_OBJECT) {
        if (out->len) json_text_add(out, ".", 1);
        json_key(st, n, out);
    } else {
        json_text_fmt(out, "[%" PRId64 "]", n->index);
    }
}

/* The subject of a sentence: the path in backquotes, its first and last JSON_PATH_PART bytes when it is longer, or "the
 * document". */
static void json_where(json_text *message, const json_text *path) {
    if (!path->len) { json_text_str(message, "the document"); return; }
    json_text_add(message, "`", 1);
    if (path->len <= 2 * JSON_PATH_PART + 3) json_text_add(message, path->data, path->len);
    else {
        const unsigned char *p = (const unsigned char *)path->data;
        json_text_add(message, p, json_boundary(p, path->len, JSON_PATH_PART));
        json_text_add(message, "...", 3);
        size_t from = path->len - JSON_PATH_PART;
        while (from < path->len && (p[from] & 0xC0) == 0x80) ++from;
        json_text_add(message, p + from, path->len - from);
    }
    json_text_add(message, "`", 1);
}

/* Keep the first error: its kind, the path (`path`, a member below `node` when `member` is given), its offset and its
 * sentence, which reads "<where> at byte <offset> <what>". */
static void json_fail(json_state *st, int kind, int64_t node, const unsigned char *member, size_t member_len, int64_t offset, const char *format, ...) {
    if (st->failed) return;
    st->failed = true;
    st->kind = kind;
    st->offset = offset;
    json_text path = {0};
    json_path_of(st, node, &path);
    if (member) {
        if (path.len) json_text_add(&path, ".", 1);
        json_spell(&path, member, member_len, 0);
    }
    json_text message = {0};
    json_where(&message, &path);
    json_text_fmt(&message, " at byte %" PRId64 " ", offset);
    va_list args;
    va_start(args, format);
    json_text_vfmt(&message, format, args);
    va_end(args);
    st->path = json_text_take(&path);
    st->message = json_text_take(&message);
}

static const char *json_kind_name(int kind) {
    static const char *const names[] = {"null", "false", "true", "a number", "a string", "an array", "an object"};
    return kind >= 0 && kind <= JSON_OBJECT ? names[kind] : "a value";
}

/* ---- the parser: one pass into the tape --------------------------------------- */

static int64_t json_node_new(json_state *st, uint8_t kind, int64_t start, int64_t parent) {
    if (st->count == st->capacity) {
        int64_t capacity = st->capacity ? st->capacity * 2 : 64;
        json_node *nodes = realloc(st->nodes, (size_t)capacity * sizeof *nodes);
        if (!nodes) out_of_memory();
        st->nodes = nodes;
        st->capacity = capacity;
    }
    int64_t id = st->count++;
    st->nodes[id] = (json_node){.kind = kind, .start = start, .end = start, .parent = parent, .next = -1, .cursor = -1, .key_start = 0, .key_end = 0, .index = 0};
    return id;
}

static int64_t json_space(const json_state *st, int64_t at) {
    while (at < st->len) {
        unsigned char c = st->data[at];
        if (c != ' ' && c != '\t' && c != '\n' && c != '\r') break;
        ++at;
    }
    return at;
}

/* The end of the string whose opening quote is at `at`, or -1; `escaped` says whether it holds a backslash. */
static int64_t json_string_end(json_state *st, int64_t at, int64_t container, bool *escaped) {
    *escaped = false;
    int64_t i = at + 1;
    while (i < st->len) {
        unsigned char c = st->data[i];
        if (c == '"') return i + 1;
        if (c < 0x20) {
            json_fail(st, JSON_E_SYNTAX, container, NULL, 0, i, "has a control character inside a string; write it as an escape such as \\n");
            return -1;
        }
        if (c == '\\') {
            *escaped = true;
            if (i + 1 >= st->len) break;
            unsigned char e = st->data[i + 1];
            if (e == 'u') {
                for (int k = 2; k < 6; ++k) {
                    if (i + k >= st->len || !isxdigit(st->data[i + k])) {
                        json_fail(st, JSON_E_SYNTAX, container, NULL, 0, i, "has a \\u escape without four hexadecimal digits");
                        return -1;
                    }
                }
                i += 6;
                continue;
            }
            if (!strchr("\"\\/bfnrt", e) || e == 0) {
                json_fail(st, JSON_E_SYNTAX, container, NULL, 0, i, "has an unknown escape \\%c in a string", e >= 0x20 && e < 0x7f ? e : '?');
                return -1;
            }
            i += 2;
            continue;
        }
        ++i;
    }
    json_fail(st, JSON_E_SYNTAX, container, NULL, 0, at, "has a string that never ends");
    return -1;
}

static int64_t json_number_end(json_state *st, int64_t at, int64_t container) {
    int64_t i = at;
    if (i < st->len && st->data[i] == '-') ++i;
    if (i >= st->len || !isdigit(st->data[i])) goto bad;
    if (st->data[i] == '0') ++i;
    else while (i < st->len && isdigit(st->data[i])) ++i;
    if (i < st->len && st->data[i] == '.') {
        ++i;
        if (i >= st->len || !isdigit(st->data[i])) goto bad;
        while (i < st->len && isdigit(st->data[i])) ++i;
    }
    if (i < st->len && (st->data[i] == 'e' || st->data[i] == 'E')) {
        ++i;
        if (i < st->len && (st->data[i] == '+' || st->data[i] == '-')) ++i;
        if (i >= st->len || !isdigit(st->data[i])) goto bad;
        while (i < st->len && isdigit(st->data[i])) ++i;
    }
    return i;
bad:
    json_fail(st, JSON_E_SYNTAX, container, NULL, 0, at, "has a malformed number");
    return -1;
}

/* Parse the whole document; on a syntax error the state is failed and the tape is not used. */
static void json_parse(json_state *st) {
    int64_t at = json_space(st, 0);
    int64_t container = -1;   /* the open array or object */
    int64_t last = -1;        /* the last child added to it */
    int depth = 0;
    bool expect_value = true;
    int64_t key_start = 0, key_end = 0;
    bool key_escaped = false;
    for (;;) {
        if (expect_value) {
            at = json_space(st, at);
            if (at >= st->len) { json_fail(st, JSON_E_SYNTAX, container, NULL, 0, at, "ends where a value should be"); return; }
            unsigned char c = st->data[at];
            uint8_t kind;
            int64_t end = at;
            if (c == '{') kind = JSON_OBJECT;
            else if (c == '[') kind = JSON_ARRAY;
            else if (c == '"') kind = JSON_STRING;
            else if (c == '-' || isdigit(c)) kind = JSON_NUMBER;
            else if (st->len - at >= 4 && !memcmp(st->data + at, "null", 4)) { kind = JSON_NULL; end = at + 4; }
            else if (st->len - at >= 4 && !memcmp(st->data + at, "true", 4)) { kind = JSON_TRUE; end = at + 4; }
            else if (st->len - at >= 5 && !memcmp(st->data + at, "false", 5)) { kind = JSON_FALSE; end = at + 5; }
            else { json_fail(st, JSON_E_SYNTAX, container, NULL, 0, at, "has `%c` where a value should be", c >= 0x20 && c < 0x7f ? c : '?'); return; }
            int64_t id = json_node_new(st, kind, at, container);
            if (container >= 0) {
                json_node *parent = &st->nodes[container];
                if (last >= 0) st->nodes[last].next = id;
                st->nodes[id].index = parent->count;
                parent->count++;
                if (parent->kind == JSON_OBJECT) {
                    st->nodes[id].key_start = key_start;
                    st->nodes[id].key_end = key_end;
                    if (key_escaped) st->nodes[id].flags |= JSON_KEY_ESCAPED;
                }
            } else if (id != 0) {
                json_fail(st, JSON_E_SYNTAX, -1, NULL, 0, at, "has more than one value");
                return;
            }
            if (kind == JSON_STRING) {
                bool escaped;
                end = json_string_end(st, at, container, &escaped);
                if (end < 0) return;
            } else if (kind == JSON_NUMBER) {
                end = json_number_end(st, at, container);
                if (end < 0) return;
            }
            if (kind == JSON_OBJECT || kind == JSON_ARRAY) {
                if (++depth > JSON_MAX_DEPTH) { json_fail(st, JSON_E_SYNTAX, container, NULL, 0, at, "nests arrays and objects deeper than %d", JSON_MAX_DEPTH); return; }
                container = id;
                last = -1;
                at = json_space(st, at + 1);
                if (at < st->len && st->data[at] == (kind == JSON_OBJECT ? '}' : ']')) {
                    st->nodes[id].end = at + 1;
                    at += 1;
                    --depth;
                    last = id;
                    container = st->nodes[id].parent;
                    expect_value = false;
                    goto after_value;
                }
                if (kind == JSON_OBJECT) goto read_key;
                continue;
            }
            st->nodes[id].end = end;
            at = end;
            last = id;
            expect_value = false;
        }
    after_value:
        at = json_space(st, at);
        if (container < 0) {
            if (at < st->len) json_fail(st, JSON_E_SYNTAX, -1, NULL, 0, at, "has text after the value ends");
            return;
        }
        {
            json_node *open = &st->nodes[container];
            unsigned char close = open->kind == JSON_OBJECT ? '}' : ']';
            if (at >= st->len) { json_fail(st, JSON_E_SYNTAX, container, NULL, 0, at, "ends before its %s closes", open->kind == JSON_OBJECT ? "object" : "array"); return; }
            unsigned char c = st->data[at];
            if (c == close) {
                open->end = at + 1;
                at += 1;
                --depth;
                last = container;
                container = open->parent;
                goto after_value;
            }
            if (c != ',') { json_fail(st, JSON_E_SYNTAX, container, NULL, 0, at, "needs `,` or `%c` here", close); return; }
            at += 1;
            if (open->kind == JSON_ARRAY) { expect_value = true; continue; }
        }
    read_key:
        at = json_space(st, at);
        if (at >= st->len || st->data[at] != '"') { json_fail(st, JSON_E_SYNTAX, container, NULL, 0, at, "needs a member name in quotes here"); return; }
        {
            int64_t end = json_string_end(st, at, container, &key_escaped);
            if (end < 0) return;
            key_start = at + 1;
            key_end = end - 1;
            at = json_space(st, end);
            if (at >= st->len || st->data[at] != ':') { json_fail(st, JSON_E_SYNTAX, container, NULL, 0, at, "needs `:` after a member name"); return; }
            at += 1;
            expect_value = true;
        }
    }
}

uint64_t myl_core_json_read(const unsigned char *data, uint64_t len) {
    json_state *st = calloc(1, sizeof *st);
    if (!st) out_of_memory();
    st->data = data;
    st->len = (int64_t)len;
    json_parse(st);
    return (uint64_t)(uintptr_t)st;
}

/* ---- string bodies ------------------------------------------------------------- */

static int json_hex(unsigned char c) { return isdigit(c) ? c - '0' : (tolower(c) - 'a' + 10); }
static void json_utf8(json_text *t, uint32_t code) {
    unsigned char b[4];
    size_t n;
    if (code < 0x80) { b[0] = (unsigned char)code; n = 1; }
    else if (code < 0x800) { b[0] = 0xC0 | (code >> 6); b[1] = 0x80 | (code & 0x3F); n = 2; }
    else if (code < 0x10000) { b[0] = 0xE0 | (code >> 12); b[1] = 0x80 | ((code >> 6) & 0x3F); b[2] = 0x80 | (code & 0x3F); n = 3; }
    else { b[0] = 0xF0 | (code >> 18); b[1] = 0x80 | ((code >> 12) & 0x3F); b[2] = 0x80 | ((code >> 6) & 0x3F); b[3] = 0x80 | (code & 0x3F); n = 4; }
    json_text_add(t, b, n);
}
/* Decode the escaped body [start, end) into `t`; false on a lone surrogate, which no `str` can hold. */
/* `bad` is where the escape of a lone surrogate starts, when it answers false. */
static bool json_unescape(const unsigned char *s, int64_t start, int64_t end, json_text *t, int64_t *bad) {
    int64_t i = start, run = start;
    while (i < end) {
        if (s[i] != '\\') { ++i; continue; }
        json_text_add(t, s + run, (size_t)(i - run));
        unsigned char e = s[i + 1];
        if (e == 'u') {
            uint32_t code = 0;
            for (int k = 2; k < 6; ++k) code = code * 16 + (uint32_t)json_hex(s[i + k]);
            *bad = i;
            i += 6;
            if (code >= 0xD800 && code < 0xDC00) {
                if (i + 6 > end || s[i] != '\\' || s[i + 1] != 'u') return false;
                uint32_t low = 0;
                for (int k = 2; k < 6; ++k) low = low * 16 + (uint32_t)json_hex(s[i + k]);
                if (low < 0xDC00 || low >= 0xE000) return false;
                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                i += 6;
            } else if (code >= 0xDC00 && code < 0xE000) return false;
            json_utf8(t, code);
        } else {
            char c = e == 'b' ? '\b' : e == 'f' ? '\f' : e == 'n' ? '\n' : e == 'r' ? '\r' : e == 't' ? '\t' : (char)e;
            json_text_add(t, &c, 1);
            i += 2;
        }
        run = i;
    }
    json_text_add(t, s + run, (size_t)(end - run));
    return true;
}

static bool json_key_is(const json_state *st, const json_node *n, const unsigned char *name, uint64_t len) {
    if (!(n->flags & JSON_KEY_ESCAPED)) return (uint64_t)(n->key_end - n->key_start) == len && !memcmp(st->data + n->key_start, name, len);
    json_text t = {0};
    int64_t bad;
    bool same = json_unescape(st->data, n->key_start, n->key_end, &t, &bad) && t.len == len && !memcmp(t.data, name, len);
    free(t.data);
    return same;
}

/* ---- reads ------------------------------------------------------------------- */

static bool json_usable(const json_state *st, int64_t node) { return !st->failed && node >= 0 && node < st->count; }
static void json_wrong(json_state *st, int64_t node, const char *wanted) {
    json_fail(st, JSON_E_UNEXPECTED, node, NULL, 0, st->nodes[node].start, "is %s; it must be %s", json_kind_name(st->nodes[node].kind), wanted);
}

int64_t myl_core_json_object(uint64_t handle, int64_t node) {
    json_state *st = json_of(handle);
    if (!json_usable(st, node)) return -1;
    if (st->nodes[node].kind != JSON_OBJECT) { json_wrong(st, node, "an object"); return -1; }
    return node;
}

int64_t myl_core_json_member(uint64_t handle, int64_t object, const unsigned char *name, uint64_t len, bool required) {
    json_state *st = json_of(handle);
    if (!json_usable(st, object)) return -1;
    json_node *o = &st->nodes[object];
    if (o->count) {
        /* Members usually come in declaration order: start after the last one found and wrap around once. */
        int64_t first = object + 1;
        int64_t start = o->cursor >= 0 && st->nodes[o->cursor].next >= 0 ? st->nodes[o->cursor].next : first;
        int64_t at = start;
        do {
            json_node *n = &st->nodes[at];
            if (!(n->flags & JSON_MATCHED) && json_key_is(st, n, name, len)) {
                n->flags |= JSON_MATCHED;
                o->cursor = at;
                return at;
            }
            at = n->next >= 0 ? n->next : first;
        } while (at != start);
    }
    if (required) json_fail(st, JSON_E_MISSING, object, name, (size_t)len, o->start, "is missing; the field has no default, so the object must give it");
    return -1;
}

/* Every member was read: one left over is a name given twice or one the record has no field for. */
/* Every member was read: one left over is a name given twice or one the object has no place for (a record's field, or
 * `case` and `value` in the wrapper of a case with fields). */
static void json_close(json_state *st, int64_t object, const unsigned char *names, uint64_t len, bool wrapper) {
    if (!json_usable(st, object) || !st->nodes[object].count) return;
    for (int64_t at = object + 1; at >= 0; at = st->nodes[at].next) {
        json_node *n = &st->nodes[at];
        if (n->flags & JSON_MATCHED) continue;
        bool known = false;
        for (uint64_t i = 0; i < len && !known;) {
            uint64_t j = i;
            while (j < len && names[j] != '\n') ++j;
            known = json_key_is(st, n, names + i, j - i);
            i = j + 1;
        }
        json_text key = {0};
        int64_t bad;
        if (!json_unescape(st->data, n->key_start, n->key_end, &key, &bad)) {
            key.len = 0;
            json_text_add(&key, st->data + n->key_start, (size_t)(n->key_end - n->key_start));
        }
        if (known) json_fail(st, JSON_E_DUPLICATE, object, (const unsigned char *)key.data, key.len, n->key_start - 1, "is given twice; give each member once");
        else if (wrapper) json_fail(st, JSON_E_UNKNOWN_MEMBER, object, (const unsigned char *)key.data, key.len, n->key_start - 1, "is not part of a case with fields, which holds only `case` and `value`; remove the member");
        else json_fail(st, JSON_E_UNKNOWN_MEMBER, object, (const unsigned char *)key.data, key.len, n->key_start - 1, "is not a field of the record; remove the member or add the field");
        free(key.data);
        return;
    }
}

void myl_core_json_close(uint64_t handle, int64_t object, const unsigned char *names, uint64_t len) {
    json_close(json_of(handle), object, names, len, false);
}

/* A decoded record whose `@invariant` does not hold (CODEC-INV): an error of kind `invariant` at its `{`. */
void myl_core_json_invariant(uint64_t handle, int64_t object, const unsigned char *name, uint64_t len) {
    json_state *st = json_of(handle);
    if (!json_usable(st, object)) return;
    json_text spelled = {0};
    json_spell(&spelled, name, (size_t)len, JSON_ECHO);
    json_fail(st, JSON_E_INVARIANT, object, NULL, 0, st->nodes[object].start, "is a `%s` whose invariant does not hold", json_text_take(&spelled));
    free(spelled.data);
}

uint64_t myl_core_json_array(uint64_t handle, int64_t node, int64_t exact) {
    json_state *st = json_of(handle);
    if (!json_usable(st, node)) return 0;
    json_node *n = &st->nodes[node];
    if (n->kind != JSON_ARRAY) { json_wrong(st, node, "an array"); return 0; }
    if (exact >= 0 && (int64_t)n->count != exact) {
        json_fail(st, JSON_E_UNEXPECTED, node, NULL, 0, n->start, "has %u elements; it must have exactly %" PRId64, n->count, exact);
        return 0;
    }
    return n->count;
}

int64_t myl_core_json_element(uint64_t handle, int64_t array, int64_t previous) {
    json_state *st = json_of(handle);
    if (!json_usable(st, array)) return -1;
    if (previous < 0) return st->nodes[array].count ? array + 1 : -1;
    return previous < st->count ? st->nodes[previous].next : -1;
}

bool myl_core_json_none(uint64_t handle, int64_t node) {
    json_state *st = json_of(handle);
    return !json_usable(st, node) || st->nodes[node].kind == JSON_NULL;
}

/* The case a node names: a bare string for a case without fields, `{"case": name, "value": fields}` for one with them.
 * `names` lists the cases, one per line, each marked `+` (has fields) or `-`. */
int64_t myl_core_json_case(uint64_t handle, int64_t node, const unsigned char *names, uint64_t len) {
    json_state *st = json_of(handle);
    if (!json_usable(st, node)) return 0;
    json_node *n = &st->nodes[node];
    int64_t name_node = node;
    if (n->kind == JSON_OBJECT) {
        name_node = myl_core_json_member(handle, node, (const unsigned char *)"case", 4, true);
        if (name_node < 0) return 0;
        if (st->nodes[name_node].kind != JSON_STRING) { json_wrong(st, name_node, "a case name in a string"); return 0; }
    } else if (n->kind != JSON_STRING) {
        json_wrong(st, node, "a case name in a string, or an object with `case` and `value`");
        return 0;
    }
    json_node *s = &st->nodes[name_node];
    json_text name = {0};
    int64_t bad;
    if (!json_unescape(st->data, s->start + 1, s->end - 1, &name, &bad)) json_text_add(&name, "?", 1);
    int64_t index = 0;
    json_text listed = {0};
    for (uint64_t i = 0; i < len; ++index) {
        uint64_t j = i;
        while (j < len && names[j] != '\n') ++j;
        bool fields = names[i] == '+';
        const unsigned char *case_name = names + i + 1;
        uint64_t case_len = j - i - 1;
        if (case_len == name.len && !memcmp(case_name, name.data, name.len)) {
            free(name.data);
            free(listed.data);
            if (fields && n->kind != JSON_OBJECT) {
                json_fail(st, JSON_E_UNEXPECTED, node, NULL, 0, n->start, "names the case `%.*s` without its fields; write {\"case\": \"%.*s\", \"value\": {...}}", (int)case_len, case_name, (int)case_len, case_name);
                return 0;
            }
            if (!fields && n->kind == JSON_OBJECT) {
                json_fail(st, JSON_E_UNEXPECTED, node, NULL, 0, n->start, "is an object, but the case `%.*s` has no fields; write it as the string \"%.*s\"", (int)case_len, case_name, (int)case_len, case_name);
                return 0;
            }
            return index;
        }
        if (listed.len) json_text_add(&listed, ", ", 2);
        json_text_add(&listed, case_name, case_len);
        i = j + 1;
    }
    json_text spelled = {0}, cases = {0};
    json_spell(&spelled, (const unsigned char *)(name.data ? name.data : ""), name.len, JSON_ECHO);
    json_spell(&cases, (const unsigned char *)(listed.data ? listed.data : "none"), listed.data ? listed.len : 4, 4 * JSON_ECHO);
    json_fail(st, JSON_E_UNKNOWN_CASE, name_node, NULL, 0, s->start, "is \"%s\", which is not a case (the cases are %s)", json_text_take(&spelled), json_text_take(&cases));
    free(spelled.data);
    free(cases.data);
    free(name.data);
    free(listed.data);
    return 0;
}

int64_t myl_core_json_case_value(uint64_t handle, int64_t node) {
    json_state *st = json_of(handle);
    if (!json_usable(st, node)) return -1;
    int64_t value = myl_core_json_member(handle, node, (const unsigned char *)"value", 5, true);
    json_close(st, node, (const unsigned char *)"case\nvalue\n", 11, true);
    return value;
}

/* An integer token's value: its sign and magnitude, or a refusal for a fraction, an exponent or a magnitude past 2^64. */
static bool json_integer(json_state *st, int64_t node, bool *negative, uint64_t *magnitude, const char *range) {
    json_node *n = &st->nodes[node];
    if (n->kind != JSON_NUMBER) { json_wrong(st, node, "an integer"); return false; }
    const unsigned char *s = st->data + n->start;
    int64_t len = n->end - n->start, i = 0;
    *negative = s[0] == '-';
    i = *negative;
    uint64_t value = 0;
    bool over = false;
    for (; i < len && isdigit(s[i]); ++i) {
        unsigned digit = (unsigned)(s[i] - '0');
        if (value > (UINT64_MAX - digit) / 10) over = true;
        else value = value * 10 + digit;
    }
    if (i < len) {
        json_fail(st, JSON_E_UNEXPECTED, node, NULL, 0, n->start, "is %.*s, a number with a fraction or an exponent; it must be an integer (%s)", (int)(len > 40 ? 40 : len), (const char *)s, range);
        return false;
    }
    if (over) {
        json_fail(st, JSON_E_RANGE, node, NULL, 0, n->start, "is %.*s, outside %s", (int)(len > 40 ? 40 : len), (const char *)s, range);
        return false;
    }
    *magnitude = value;
    return true;
}

int64_t myl_core_json_i64(uint64_t handle, int64_t node, int64_t low, int64_t high) {
    json_state *st = json_of(handle);
    if (!json_usable(st, node)) return 0;
    char range[96];
    snprintf(range, sizeof range, "the range %" PRId64 " to %" PRId64, low, high);
    bool negative;
    uint64_t magnitude;
    if (!json_integer(st, node, &negative, &magnitude, range)) return 0;
    bool fits = negative ? magnitude <= (uint64_t)0 - (uint64_t)low : magnitude <= (uint64_t)high;
    if (!fits) {
        json_node *n = &st->nodes[node];
        json_fail(st, JSON_E_RANGE, node, NULL, 0, n->start, "is %.*s, outside %s", (int)(n->end - n->start), (const char *)st->data + n->start, range);
        return 0;
    }
    return negative ? (int64_t)((uint64_t)0 - magnitude) : (int64_t)magnitude;
}

uint64_t myl_core_json_u64(uint64_t handle, int64_t node, uint64_t high) {
    json_state *st = json_of(handle);
    if (!json_usable(st, node)) return 0;
    char range[96];
    snprintf(range, sizeof range, "the range 0 to %" PRIu64, high);
    bool negative;
    uint64_t magnitude;
    if (!json_integer(st, node, &negative, &magnitude, range)) return 0;
    if ((negative && magnitude != 0) || magnitude > high) {
        json_node *n = &st->nodes[node];
        json_fail(st, JSON_E_RANGE, node, NULL, 0, n->start, "is %.*s, outside %s", (int)(n->end - n->start), (const char *)st->data + n->start, range);
        return 0;
    }
    return magnitude;
}

static double json_number(json_state *st, int64_t node, bool single) {
    json_node *n = &st->nodes[node];
    if (n->kind != JSON_NUMBER) { json_wrong(st, node, "a number"); return 0; }
    size_t len = (size_t)(n->end - n->start);
    char small[64];
    char *text = len < sizeof small ? small : malloc(len + 1);
    if (!text) out_of_memory();
    memcpy(text, st->data + n->start, len);
    text[len] = 0;
    double value = single ? (double)strtof(text, NULL) : strtod(text, NULL);
    if (isinf(value)) json_fail(st, JSON_E_RANGE, node, NULL, 0, n->start, "is %.*s, too large for a %s", (int)(len > 40 ? 40 : len), text, single ? "f32" : "float");
    if (text != small) free(text);
    return isinf(value) ? 0 : value;
}
double myl_core_json_f64(uint64_t handle, int64_t node) {
    json_state *st = json_of(handle);
    return json_usable(st, node) ? json_number(st, node, false) : 0;
}
float myl_core_json_f32(uint64_t handle, int64_t node) {
    json_state *st = json_of(handle);
    return json_usable(st, node) ? (float)json_number(st, node, true) : 0;
}

bool myl_core_json_bool(uint64_t handle, int64_t node) {
    json_state *st = json_of(handle);
    if (!json_usable(st, node)) return false;
    uint8_t kind = st->nodes[node].kind;
    if (kind != JSON_TRUE && kind != JSON_FALSE) { json_wrong(st, node, "true or false"); return false; }
    return kind == JSON_TRUE;
}

myl_block *myl_core_json_str(uint64_t handle, int64_t node) {
    json_state *st = json_of(handle);
    if (!json_usable(st, node)) return str_from("", 0);
    json_node *n = &st->nodes[node];
    if (n->kind != JSON_STRING) { json_wrong(st, node, "a string"); return str_from("", 0); }
    const unsigned char *body = st->data + n->start + 1;
    size_t body_len = (size_t)(n->end - n->start - 2);
    if (!memchr(body, '\\', body_len)) return str_from((const char *)body, body_len);
    json_text t = {0};
    int64_t bad = n->start;
    if (!json_unescape(st->data, n->start + 1, n->end - 1, &t, &bad)) {
        free(t.data);
        json_fail(st, JSON_E_SYNTAX, node, NULL, 0, bad, "has a \\u escape of half a surrogate pair, which no text can hold");
        return str_from("", 0);
    }
    myl_block *text = str_from(t.data ? t.data : "", t.len);
    free(t.data);
    return text;
}

/* ---- the writer -------------------------------------------------------------- */

uint64_t myl_core_json_writer(void) {
    json_state *st = calloc(1, sizeof *st);
    if (!st) out_of_memory();
    st->offset = 0;
    return (uint64_t)(uintptr_t)st;
}

static void json_out(json_state *st, const void *bytes, size_t n) {
    if (!n) return;
    if (n > SIZE_MAX - st->out_len) out_of_memory();
    if (st->out_len + n > st->out_cap) {
        size_t cap = st->out_cap ? st->out_cap : 256;
        while (cap < st->out_len + n) {
            if (cap > SIZE_MAX / 2) out_of_memory();
            cap *= 2;
        }
        char *out = realloc(st->out, cap);
        if (!out) out_of_memory();
        st->out = out;
        st->out_cap = cap;
    }
    memcpy(st->out + st->out_len, bytes, n);
    st->out_len += n;
}

/* Before a value: the comma an array needs between its elements. */
static void json_value_starts(json_state *st) {
    if (!st->depth) return;
    json_frame *top = &st->frames[st->depth - 1];
    if (top->object) return;
    if (top->index++) json_out(st, ",", 1);
}

static void json_writer_fail(json_state *st, const char *detail);
static void json_open(json_state *st, bool object) {
    json_value_starts(st);
    if (st->depth >= JSON_MAX_DEPTH) {
        json_writer_fail(st, "it nests arrays and objects deeper than 1000 levels, the most json.decode reads");
        return;
    }
    if (st->depth == st->frames_cap) {
        size_t cap = st->frames_cap ? st->frames_cap * 2 : 16;
        json_frame *frames = realloc(st->frames, cap * sizeof *frames);
        if (!frames) out_of_memory();
        st->frames = frames;
        st->frames_cap = cap;
    }
    st->frames[st->depth++] = (json_frame){.object = object, .index = 0};
    json_out(st, object ? "{" : "[", 1);
}
static void json_shut(json_state *st, bool object) {
    if (st->depth) --st->depth;
    json_out(st, object ? "}" : "]", 1);
}
void myl_core_json_begin_object(uint64_t handle) { if (!json_of(handle)->failed) json_open(json_of(handle), true); }
void myl_core_json_end_object(uint64_t handle) { if (!json_of(handle)->failed) json_shut(json_of(handle), true); }
void myl_core_json_begin_array(uint64_t handle) { if (!json_of(handle)->failed) json_open(json_of(handle), false); }
void myl_core_json_end_array(uint64_t handle) { if (!json_of(handle)->failed) json_shut(json_of(handle), false); }

void myl_core_json_put_key(uint64_t handle, const unsigned char *name, uint64_t len) {
    json_state *st = json_of(handle);
    if (st->failed || !st->depth) return;
    json_frame *top = &st->frames[st->depth - 1];
    if (top->index++) json_out(st, ",", 1);
    top->key = name;
    top->key_len = len;
    json_out(st, "\"", 1);
    json_out(st, name, (size_t)len);
    json_out(st, "\":", 2);
}

static void json_quote(json_state *st, const unsigned char *s, uint64_t len) {
    static const char hex[] = "0123456789abcdef";
    json_out(st, "\"", 1);
    uint64_t run = 0;
    for (uint64_t i = 0; i < len; ++i) {
        unsigned char c = s[i];
        if (c >= 0x20 && c != '"' && c != '\\') continue;
        json_out(st, s + run, (size_t)(i - run));
        run = i + 1;
        char escape[6] = {'\\', 'u', '0', '0', hex[c >> 4], hex[c & 15]};
        if (c == '"' || c == '\\') { escape[1] = (char)c; json_out(st, escape, 2); }
        else if (c == '\n') json_out(st, "\\n", 2);
        else if (c == '\r') json_out(st, "\\r", 2);
        else if (c == '\t') json_out(st, "\\t", 2);
        else if (c == '\b') json_out(st, "\\b", 2);
        else if (c == '\f') json_out(st, "\\f", 2);
        else json_out(st, escape, 6);
    }
    json_out(st, s + run, (size_t)(len - run));
    json_out(st, "\"", 1);
}

void myl_core_json_put_str(uint64_t handle, const unsigned char *s, uint64_t len) {
    json_state *st = json_of(handle);
    if (st->failed) return;
    json_value_starts(st);
    json_quote(st, s, len);
}
void myl_core_json_put_case(uint64_t handle, const unsigned char *s, uint64_t len) { myl_core_json_put_str(handle, s, len); }
void myl_core_json_put_null(uint64_t handle) {
    json_state *st = json_of(handle);
    if (st->failed) return;
    json_value_starts(st);
    json_out(st, "null", 4);
}
void myl_core_json_put_bool(uint64_t handle, bool value) {
    json_state *st = json_of(handle);
    if (st->failed) return;
    json_value_starts(st);
    json_out(st, value ? "true" : "false", value ? 4 : 5);
}
void myl_core_json_put_i64(uint64_t handle, int64_t value) {
    json_state *st = json_of(handle);
    if (st->failed) return;
    json_value_starts(st);
    char number[32];
    int n = snprintf(number, sizeof number, "%" PRId64, value);
    json_out(st, number, (size_t)n);
}
void myl_core_json_put_u64(uint64_t handle, uint64_t value) {
    json_state *st = json_of(handle);
    if (st->failed) return;
    json_value_starts(st);
    char number[32];
    int n = snprintf(number, sizeof number, "%" PRIu64, value);
    json_out(st, number, (size_t)n);
}

/* The path of the value being written, from the writer's open containers. */
static void json_writer_fail(json_state *st, const char *detail) {
    if (st->failed) return;
    json_text path = {0};
    for (size_t i = 0; i < st->depth; ++i) {
        json_frame *f = &st->frames[i];
        if (f->object) {
            if (!f->key) continue;
            if (path.len) json_text_add(&path, ".", 1);
            json_spell(&path, f->key, (size_t)f->key_len, 0);
        } else json_text_fmt(&path, "[%" PRId64 "]", f->index - 1);
    }
    st->failed = true;
    st->kind = JSON_E_UNWRITABLE;
    st->offset = (int64_t)st->out_len;
    json_text message = {0};
    if (path.len) {
        json_where(&message, &path);
        json_text_fmt(&message, " cannot be written: %s", detail);
    } else json_text_fmt(&message, "the value cannot be written: %s", detail);
    st->path = json_text_take(&path);
    st->message = json_text_take(&message);
}

/* Whether the decimal `back` read in is `value`, as a double or as an `f32`. */
static bool json_reads_back(double back, double value, bool single) {
    return single ? (float)back == (float)value : back == value;
}

/* `scientific` ([-]d.ddde(+|-)xx) moved by one unit in its last digit, up for `step` 1 and down for -1 (in magnitude), its
 * count of digits kept, written into `out`. */
static void json_nudge(char *out, size_t size, const char *scientific, int step) {
    const char *at = scientific;
    bool negative = *at == '-';
    if (negative) ++at;
    char digits[24];
    int count = 0;
    for (; *at && *at != 'e'; ++at) if (*at != '.' && count < 23) digits[count++] = *at;
    int exponent = *at == 'e' ? atoi(at + 1) : 0;
    int i = count - 1;
    if (step > 0) {
        while (i >= 0 && digits[i] == '9') digits[i--] = '0';
        if (i >= 0) digits[i] += 1;
        else { digits[0] = '1'; ++exponent; }
    } else {
        while (i >= 0 && digits[i] == '0') digits[i--] = '9';
        if (i >= 0) digits[i] -= 1;
        if (digits[0] == '0' && count > 1) {
            memmove(digits, digits + 1, (size_t)count - 1);
            digits[count - 1] = '9';
            --exponent;
        }
    }
    digits[count] = 0;
    snprintf(out, size, "%s%c%s%se%d", negative ? "-" : "", digits[0], count > 1 ? "." : "", digits + 1, exponent);
}

/* The shortest decimal that reads back as the same value, spelled as Python's `repr` and Selka's `str(float)` spell it:
 * positional from 1e-4 up to 1e16, with `.0` when it has no fraction (`2.0`, `-0.0`, `123456789.0`), and an exponent of
 * at least two digits beyond (`1e+16`, `1e-05`, `5e-324`). */
static void json_put_double(json_state *st, double value, bool single) {
    if (st->failed) return;
    json_value_starts(st);
    if (isnan(value) || isinf(value)) {
        json_writer_fail(st, isnan(value) ? "NaN has no JSON form" : "an infinity has no JSON form");
        return;
    }
    /* A decimal of at most 15 (a float's 6) significant digits reads back as itself, so when the 15-digit rounding reads
     * back, it with its trailing zeros dropped (below) is the shortest; otherwise 16, then 17 (9 for f32) digits. A
     * subnormal holds fewer digits than that, so its search starts at one digit. An exact power of two has a gap below it
     * half the gap above, so a rounding that misses can have a neighbour, one unit in its last digit away, that reads
     * back: that one is the shortest (Python's `repr` picks it too). */
    char scientific[48];
    bool subnormal = value != 0 && fabs(value) < (single ? 1.17549435082228751e-38 : 2.2250738585072014e-308);
    int binary_exponent;
    bool power_of_two = value != 0 && fabs(frexp(value, &binary_exponent)) == 0.5;
    for (int precision = subnormal ? 0 : single ? 5 : 14; precision <= (single ? 8 : 16); ++precision) {
        snprintf(scientific, sizeof scientific, "%.*e", precision, value);
        double back = strtod(scientific, NULL);
        if (json_reads_back(back, value, single)) break;
        if (!power_of_two) continue;
        char nudged[48];
        json_nudge(nudged, sizeof nudged, scientific, (back < value) == (value > 0) ? 1 : -1);
        if (json_reads_back(strtod(nudged, NULL), value, single)) {
            memcpy(scientific, nudged, sizeof scientific);
            break;
        }
    }
    /* `scientific` is [-]d[.ddd]e(+|-)xx: split it into its sign, its digits and its decimal exponent. */
    const char *at = scientific;
    bool negative = *at == '-';
    if (negative) ++at;
    char digits[24];
    size_t count = 0;
    for (; *at && *at != 'e'; ++at) if (*at != '.' && count < sizeof digits - 1) digits[count++] = *at;
    digits[count] = 0;
    int exponent = *at == 'e' ? atoi(at + 1) : 0;
    while (count > 1 && digits[count - 1] == '0') digits[--count] = 0;
    json_text out = {0};
    if (negative) json_text_add(&out, "-", 1);
    if (exponent >= -4 && exponent < 16) {
        if (exponent < 0) {
            json_text_add(&out, "0.", 2);
            for (int k = -1; k > exponent; --k) json_text_add(&out, "0", 1);
            json_text_add(&out, digits, count);
        } else {
            size_t whole = (size_t)exponent + 1;
            json_text_add(&out, digits, whole < count ? whole : count);
            for (size_t k = count; k < whole; ++k) json_text_add(&out, "0", 1);
            json_text_add(&out, ".", 1);
            if (whole < count) json_text_add(&out, digits + whole, count - whole);
            else json_text_add(&out, "0", 1);
        }
    } else {
        json_text_add(&out, digits, 1);
        if (count > 1) {
            json_text_add(&out, ".", 1);
            json_text_add(&out, digits + 1, count - 1);
        }
        json_text_fmt(&out, "e%c%02d", exponent < 0 ? '-' : '+', exponent < 0 ? -exponent : exponent);
    }
    json_out(st, out.data, out.len);
    free(out.data);
}
void myl_core_json_put_f64(uint64_t handle, double value) { json_put_double(json_of(handle), value, false); }
void myl_core_json_put_f32(uint64_t handle, float value) { json_put_double(json_of(handle), (double)value, true); }

myl_block *myl_core_json_written(uint64_t handle) {
    json_state *st = json_of(handle);
    return str_from(st->out ? st->out : "", st->out_len);
}

/* ---- the outcome ------------------------------------------------------------- */

bool myl_core_json_ok(uint64_t handle) { return !json_of(handle)->failed; }
int64_t myl_core_json_error_kind(uint64_t handle) { return json_of(handle)->kind; }
int64_t myl_core_json_error_offset(uint64_t handle) { return json_of(handle)->offset; }
myl_block *myl_core_json_error_path(uint64_t handle) {
    const char *path = json_of(handle)->path;
    return str_from(path ? path : "", path ? strlen(path) : 0);
}
myl_block *myl_core_json_error_message(uint64_t handle) {
    const char *message = json_of(handle)->message;
    return str_from(message ? message : "", message ? strlen(message) : 0);
}
void myl_core_json_done(uint64_t handle) {
    json_state *st = json_of(handle);
    free(st->nodes);
    free(st->out);
    free(st->frames);
    free(st->path);
    free(st->message);
    free(st);
}
