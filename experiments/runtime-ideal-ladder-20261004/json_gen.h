// json_gen.h: the generic Json-tree parser used by ladder versions v2..v6 of json_parse.c.
// Included once per version with GP_PREFIX (a token) and GP_CFG (feature bits below). All of them
// position the scanner in a register (passed and returned by value), return results in registers, and
// build a tree of 16-byte nodes; the flags turn today's costs on or off one at a time.
//   CFG_RC       tree objects are malloc'd and released through the deferred drain queue (else bump region)
//   CFG_ENCCOPY  json.loads copies the document first (source.encode())
//   CFG_COPYSTR  each string goes through buffer -> snapshot -> UTF-8 validation -> new str (else a view
//                of the document, or a region copy only when the literal has escapes)
//   CFG_TWOPASS  an integer's digits are scanned, then scanned again by parse_int_range (else one pass)
//   CFG_DICT     objects are insertion-ordered hash dictionaries with a duplicate-key probe (else a flat
//                entry array with a linear duplicate check)
//   CFG_LITCOPY  true/false/null compare a freshly copied slice of the document (else compare in place)
#ifndef JSON_GEN_COMMON
#define JSON_GEN_COMMON
#define CFG_RC 1
#define CFG_ENCCOPY 2
#define CFG_COPYSTR 4
#define CFG_TWOPASS 8
#define CFG_DICT 16
#define CFG_LITCOPY 32
enum { G_NULL, G_BOOL, G_INT, G_TEXT, G_ARRAY, G_OBJECT };
typedef struct { uint32_t tag, len; union { int64_t i; const unsigned char *p; void *ptr; } u; } gnode;
typedef struct { span_t key; gnode value; } gentry;
typedef struct { int64_t len, cap; gentry *entries; uint64_t *index; size_t index_cap; } gobj;
typedef struct { int64_t pos; gnode v; } gres;
typedef struct {
    const unsigned char *src; int64_t n;
    const unsigned char *d;            /* the working copy (== src unless CFG_ENCCOPY) */
    region_t reg;
    void **trk; size_t ntrk, captrk;   /* CFG_RC: blocks to release at teardown */
    gnode root;
} gctx;

static inline uint32_t gp_hash(const unsigned char *p, size_t n) {
    uint64_t h = 0x9e3779b97f4a7c15ULL;
    size_t i = 0;
    for (; i + 8 <= n; i += 8) { uint64_t w; memcpy(&w, p + i, 8); unsigned __int128 m = (unsigned __int128)(h ^ w) * 0xbf58476d1ce4e5b9ULL; h = (uint64_t)m ^ (uint64_t)(m >> 64); }
    uint64_t w = 0; memcpy(&w, p + i, n - i);
    unsigned __int128 m = (unsigned __int128)(h ^ w ^ n) * 0xbf58476d1ce4e5b9ULL; h = (uint64_t)m ^ (uint64_t)(m >> 64);
    return (uint32_t)(h ^ (h >> 32));
}
static inline void *gp_alloc(gctx *c, int rc, size_t n) {
    if (!rc) return ralloc(&c->reg, n);
    void *p = malloc(n);
    if (c->ntrk == c->captrk) { c->captrk = c->captrk ? c->captrk * 2 : 256; c->trk = realloc(c->trk, c->captrk * sizeof(void *)); }
    c->trk[c->ntrk++] = p;
    return p;
}
static inline int64_t gp_skip_ws(const unsigned char *d, int64_t n, int64_t pos) {
    while (pos < n) { unsigned char c = d[pos]; if (c != 32 && c != 9 && c != 10 && c != 13) break; pos++; }
    return pos;
}
#endif /* JSON_GEN_COMMON */

#define GP_CAT2(a, b) a##b
#define GP_CAT(a, b) GP_CAT2(a, b)
#define GP(name) GP_CAT(GP_PREFIX, name)
#define RC ((GP_CFG) & CFG_RC)

static gres GP(value)(gctx *c, int64_t pos, int depth);

/* one string literal at pos (the opening quote); returns the new position */
static int64_t GP(string)(gctx *c, int64_t pos, span_t *out) {
    const unsigned char *d = c->d;
    int64_t n = c->n, i = pos + 1, start = i;
    int escapes = 0;
    while (i < n) {
        unsigned char b = d[i];
        if (b == '"') break;
        if (b < 32) trap("control character in string");
        if (b == '\\') { escapes = 1; i++; if (i >= n) trap("unterminated escape"); }
        i++;
    }
    if (i >= n) trap("unterminated string");
    int64_t end = i;            /* the closing quote */
    if (!(GP_CFG & CFG_COPYSTR) && !escapes) { out->p = d + start; out->n = (size_t)(end - start); return end + 1; }
    /* decode (or, in the faithful mode, always rebuild) into fresh storage */
    size_t cap = 8;
    unsigned char *buf = NULL;
    size_t w = 0;
    if (GP_CFG & CFG_COPYSTR) {  /* byte_buffer: starts empty, grows by doubling, reallocated each time */
        buf = gp_alloc(c, RC, cap);
    } else {
        buf = gp_alloc(c, RC, (size_t)(end - start) + 8);
    }
    int64_t k = start;
    while (k < end) {
        unsigned char b = d[k];
        if (b != '\\') {
            if (GP_CFG & CFG_COPYSTR) {
                /* append_range of the plain span up to the next escape or the end */
                int64_t m = k;
                while (m < end && d[m] != '\\') m++;
                size_t need = w + (size_t)(m - k);
                if (need > cap) { size_t nc = cap; while (nc < need) nc *= 2; unsigned char *nb = gp_alloc(c, RC, nc); memcpy(nb, buf, w); buf = nb; cap = nc; }
                memcpy(buf + w, d + k, (size_t)(m - k)); w += (size_t)(m - k); k = m;
            } else { buf[w++] = b; k++; }
            continue;
        }
        k++;
        unsigned char e = d[k++];
        unsigned char tmp[4]; size_t tn = 0;
        switch (e) {
        case '"': case '\\': case '/': tmp[tn++] = e; break;
        case 'b': tmp[tn++] = 8; break;
        case 'f': tmp[tn++] = 12; break;
        case 'n': tmp[tn++] = 10; break;
        case 'r': tmp[tn++] = 13; break;
        case 't': tmp[tn++] = 9; break;
        case 'u': {
            int64_t code = 0;
            for (int q = 0; q < 4; q++) {
                if (k >= end) trap("truncated unicode escape");
                unsigned char h = d[k++];
                int v = h >= '0' && h <= '9' ? h - '0' : h >= 'a' && h <= 'f' ? h - 'a' + 10 : h >= 'A' && h <= 'F' ? h - 'A' + 10 : -1;
                if (v < 0) trap("bad hex digit");
                code = code * 16 + v;
            }
            if (code >= 0xD800 && code < 0xE000) trap("surrogate escapes are outside this model");
            if (code < 128) tmp[tn++] = (unsigned char)code;
            else if (code < 2048) { tmp[tn++] = (unsigned char)(192 + code / 64); tmp[tn++] = (unsigned char)(128 + code % 64); }
            else { tmp[tn++] = (unsigned char)(224 + code / 4096); tmp[tn++] = (unsigned char)(128 + code / 64 % 64); tmp[tn++] = (unsigned char)(128 + code % 64); }
            break;
        }
        default: trap("unknown escape");
        }
        if (GP_CFG & CFG_COPYSTR) {
            size_t need = w + tn;
            if (need > cap) { size_t nc = cap; while (nc < need) nc *= 2; unsigned char *nb = gp_alloc(c, RC, nc); memcpy(nb, buf, w); buf = nb; cap = nc; }
        }
        memcpy(buf + w, tmp, tn); w += tn;
    }
    if (GP_CFG & CFG_COPYSTR) {
        unsigned char *snap = gp_alloc(c, RC, w ? w : 1);       /* bytes(values) */
        memcpy(snap, buf, w);
        size_t i2 = 0;                                           /* decode(): validate UTF-8 */
        while (i2 < w) {
            unsigned cc = snap[i2];
            size_t kk = cc < 0x80 ? 1 : (cc >> 5) == 6 ? 2 : (cc >> 4) == 14 ? 3 : (cc >> 3) == 30 ? 4 : 0;
            if (!kk || i2 + kk > w) trap("not UTF-8");
            for (size_t m = 1; m < kk; m++) if ((snap[i2 + m] & 0xC0) != 0x80) trap("not UTF-8");
            i2 += kk;
        }
        unsigned char *fin = gp_alloc(c, RC, w + 32);           /* the str object: header + payload */
        memcpy(fin + 24, snap, w);
        out->p = fin + 24; out->n = w;
    } else { out->p = buf; out->n = w; }
    return end + 1;
}

static int64_t GP(integer)(gctx *c, int64_t pos, int64_t *out) {
    const unsigned char *d = c->d;
    int64_t n = c->n, i = pos;
    int neg = 0;
    if (i < n && d[i] == '-') { neg = 1; i++; }
    if (i >= n || d[i] < '0' || d[i] > '9') trap("number needs a digit");
    int64_t start = i;
    uint64_t acc = 0;
    int digits = 0;
    if (d[i] == '0') { i++; if (i < n && d[i] >= '0' && d[i] <= '9') trap("leading zero"); }
    else if (GP_CFG & CFG_TWOPASS) { while (i < n && d[i] >= '0' && d[i] <= '9') i++; }   /* skip_digits */
    else { while (i < n && d[i] >= '0' && d[i] <= '9') { acc = acc * 10 + (uint64_t)(d[i] - '0'); i++; if (++digits > 18) trap("integer outside this model"); } }
    if (i < n && (d[i] == '.' || d[i] == 'e' || d[i] == 'E')) trap("float outside this model");
    int64_t v = (int64_t)acc;
    if (GP_CFG & CFG_TWOPASS) {                                                           /* parse_int_range */
        v = 0;
        for (int64_t q = start; q < i; q++)
            if (__builtin_mul_overflow(v, 10, &v) || __builtin_add_overflow(v, d[q] - '0', &v)) trap("integer outside this model");
    }
    *out = neg ? -v : v;
    return i;
}

static gres GP(array)(gctx *c, int64_t pos, int depth) {
    const unsigned char *d = c->d;
    int64_t n = c->n;
    pos = gp_skip_ws(d, n, pos + 1);
    gnode *items = NULL;
    uint32_t len = 0, cap = 0;
    if (pos < n && d[pos] == ']') return (gres){pos + 1, {G_ARRAY, 0, {.ptr = NULL}}};
    for (;;) {
        gres r = GP(value)(c, pos, depth + 1);
        if (len == cap) {
            uint32_t nc = cap ? cap * 2 : 4;
            gnode *ni = gp_alloc(c, RC, (size_t)nc * sizeof(gnode));
            if (len) memcpy(ni, items, (size_t)len * sizeof(gnode));
            items = ni; cap = nc;
        }
        items[len++] = r.v;
        pos = gp_skip_ws(d, n, r.pos);
        if (pos >= n) trap("unterminated array");
        if (d[pos] == ']') return (gres){pos + 1, {G_ARRAY, len, {.ptr = items}}};
        if (d[pos] != ',') trap("expected , or ]");
        pos++;
    }
}

static gres GP(object)(gctx *c, int64_t pos, int depth) {
    const unsigned char *d = c->d;
    int64_t n = c->n;
    gobj *o = gp_alloc(c, RC, sizeof *o);
    memset(o, 0, sizeof *o);
    pos = gp_skip_ws(d, n, pos + 1);
    if (pos < n && d[pos] == '}') return (gres){pos + 1, {G_OBJECT, 0, {.ptr = o}}};
    for (;;) {
        pos = gp_skip_ws(d, n, pos);
        if (pos >= n || d[pos] != '"') trap("object keys must be strings");
        span_t key;
        pos = GP(string)(c, pos, &key);
        /* duplicate-key probe */
        if (GP_CFG & CFG_DICT) {
            if (o->index_cap) {
                uint32_t h = gp_hash(key.p, key.n);
                size_t mask = o->index_cap - 1, at = h & mask;
                for (uint64_t slot; (slot = o->index[at]); at = (at + 1) & mask) {
                    if ((uint32_t)(slot >> 32) != h) continue;
                    gentry *e = &o->entries[(slot & 0xffffffffu) - 1];
                    if (e->key.n == key.n && !memcmp(e->key.p, key.p, key.n)) trap("duplicate key");
                }
            }
        } else {
            for (int64_t q = 0; q < o->len; q++) if (o->entries[q].key.n == key.n && !memcmp(o->entries[q].key.p, key.p, key.n)) trap("duplicate key");
        }
        pos = gp_skip_ws(d, n, pos);
        if (pos >= n || d[pos] != ':') trap("expected :");
        gres r = GP(value)(c, pos + 1, depth + 1);
        pos = r.pos;
        if (o->len >= o->cap) {
            int64_t nc = o->cap ? o->cap * 2 : 4;
            gentry *ne = gp_alloc(c, RC, (size_t)nc * sizeof(gentry));
            if (o->len) memcpy(ne, o->entries, (size_t)o->len * sizeof(gentry));
            o->entries = ne; o->cap = nc;
        }
        o->entries[o->len] = (gentry){key, r.v};
        o->len++;
        if (GP_CFG & CFG_DICT) {
            if ((size_t)o->len * 8 > o->index_cap * 5) {
                size_t cap = o->index_cap ? o->index_cap * 2 : 8;
                while ((size_t)o->len * 8 > cap * 5) cap *= 2;
                uint64_t *idx = gp_alloc(c, RC, cap * 8);
                memset(idx, 0, cap * 8);
                for (int64_t q = 0; q < o->len; q++) {
                    uint32_t h = gp_hash(o->entries[q].key.p, o->entries[q].key.n);
                    size_t at = h & (cap - 1);
                    while (idx[at]) at = (at + 1) & (cap - 1);
                    idx[at] = (uint64_t)h << 32 | (uint64_t)(q + 1);
                }
                o->index = idx; o->index_cap = cap;
            } else {
                uint32_t h = gp_hash(key.p, key.n);
                size_t at = h & (o->index_cap - 1);
                while (o->index[at]) at = (at + 1) & (o->index_cap - 1);
                o->index[at] = (uint64_t)h << 32 | (uint64_t)o->len;
            }
        }
        pos = gp_skip_ws(d, n, pos);
        if (pos >= n) trap("unterminated object");
        if (d[pos] == '}') return (gres){pos + 1, {G_OBJECT, (uint32_t)o->len, {.ptr = o}}};
        if (d[pos] != ',') trap("expected , or }");
        pos++;
    }
}

static gres GP(literal)(gctx *c, int64_t pos, const char *word, size_t wl, gnode value) {
    if (pos + (int64_t)wl > c->n) trap("truncated literal");
    if (GP_CFG & CFG_LITCOPY) {
        unsigned char *slice = gp_alloc(c, RC, wl);
        memcpy(slice, c->d + pos, wl);
        if (memcmp(slice, word, wl)) trap("unknown literal");
    } else if (memcmp(c->d + pos, word, wl)) trap("unknown literal");
    return (gres){pos + (int64_t)wl, value};
}

static gres GP(value)(gctx *c, int64_t pos, int depth) {
    if (depth > 64) trap("nesting too deep");
    pos = gp_skip_ws(c->d, c->n, pos);
    if (pos >= c->n) trap("unexpected end");
    unsigned char b = c->d[pos];
    if (b == '{') return GP(object)(c, pos, depth);
    if (b == '[') return GP(array)(c, pos, depth);
    if (b == '"') { span_t s; int64_t np = GP(string)(c, pos, &s); return (gres){np, {G_TEXT, (uint32_t)s.n, {.p = s.p}}}; }
    if (b == 't') return GP(literal)(c, pos, "true", 4, (gnode){G_BOOL, 0, {.i = 1}});
    if (b == 'f') return GP(literal)(c, pos, "false", 5, (gnode){G_BOOL, 0, {.i = 0}});
    if (b == 'n') return GP(literal)(c, pos, "null", 4, (gnode){G_NULL, 0, {.i = 0}});
    if (b == '-' || (b >= '0' && b <= '9')) { int64_t v; int64_t np = GP(integer)(c, pos, &v); return (gres){np, {G_INT, 0, {.i = v}}}; }
    trap("unexpected character");
}

static void *GP(parse)(void *vc) {
    gctx *c = vc;
    c->reg.used = 0;
    c->ntrk = 0;
    if (GP_CFG & CFG_ENCCOPY) {
        unsigned char *copy = gp_alloc(c, RC, (size_t)c->n + 1);
        memcpy(copy, c->src, (size_t)c->n);
        c->d = copy;
    } else c->d = c->src;
    gres r = GP(value)(c, 0, 1);
    int64_t pos = gp_skip_ws(c->d, c->n, r.pos);
    if (pos != c->n) trap("trailing characters");
    c->root = r.v;
    return &c->root;
}
static void GP(teardown)(void *vc, void *tree) {
    gctx *c = vc;
    (void)tree;
    if (RC) {
        for (size_t i = 0; i < c->ntrk; i++) {
            if (g_dead_n == (1 << 16)) drain();
            g_dead[g_dead_n++] = c->trk[i];
        }
        drain();
        c->ntrk = 0;
    }
}

#undef RC
#undef GP
#undef GP_CAT
#undef GP_CAT2
#undef GP_PREFIX
#undef GP_CFG
