/* PM-3 ladder 4: scan_split (bench/parity/lib/scan_split.my): three rounds of
 *
 *   for line in text.split("\n"): lines += 1; width += len(line)
 *   fields += len(text.split(","))
 *   for run in text.split("x\nitem"): runs += 1; run_width += len(run)
 *
 * over the same 4.4 MB text, printing the same five numbers.
 *
 *   0  what mylang emits today: myl_core_str_split builds a list of fresh
 *      strings (per piece core_text_find_bytes: memchr for the first byte,
 *      then a byte loop over the rest of the separator; str_from: a small
 *      block from the free list, header stores, memcpy, NUL, len and the
 *      ASCII re-scan; a list push that grows the list by doubling its class
 *      or by realloc); the loop reads each piece's length (str_chars: the
 *      ASCII flag, then len); dropping the list releases every piece (the
 *      list's layout says which words are blocks: reference_at per element)
 *      and frees the list.
 *   1  views: a piece is (offset, length) into the text, which the list
 *      holds; no piece is allocated, copied or re-scanned (the text's ASCII
 *      flag answers for every piece), and dropping the list frees one block.
 *   2  rung 1 without the list: the split is iterated in place (a split
 *      iterator fused with the loop; `len(text.split(","))` counts pieces).
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef RUNG
#define RUNG 0
#endif

typedef struct block { uint32_t count, kind; int64_t len, cap; int64_t reserved; } block;
enum { ASCII = 1u << 8 };
#define DATA(b) ((unsigned char *)(b) + 32)

static void *free_lists[33];
static unsigned char *chunk_next, *chunk_end;
static __attribute__((noinline)) void *small_alloc(uint32_t class) {
    void *b = free_lists[class];
    if (b) { free_lists[class] = *(void **)b; return b; }
    size_t bytes = (size_t)class * 32;
    if ((size_t)(chunk_end - chunk_next) < bytes) { chunk_next = aligned_alloc(32, 1 << 16); chunk_end = chunk_next + (1 << 16); }
    b = chunk_next; chunk_next += bytes; return b;
}
static block *block_alloc(size_t data) {
    size_t bytes = 32 + data;
    block *b;
    uint32_t class = 0;
    if (bytes <= 1024) { class = (uint32_t)((bytes + 31) / 32); b = small_alloc(class); }
    else b = aligned_alloc(32, (bytes + 31) & ~(size_t)31);
    b->count = 1; b->kind = 3 | (class << 24); b->len = 0; b->reserved = 0; b->cap = (int64_t)data;
    return b;
}
static void block_free(block *b) {
    uint32_t class = b->kind >> 24;
    if (!class) { free(b); return; }
    *(void **)b = free_lists[class]; free_lists[class] = b;
}
static __attribute__((noinline)) bool text_ascii(const unsigned char *p, uint64_t len) {
    uint64_t at = 0;
    for (; at + 8 <= len; at += 8) { uint64_t w; memcpy(&w, p + at, 8); if (w & UINT64_C(0x8080808080808080)) return false; }
    for (; at < len; ++at) if (p[at] & 0x80) return false;
    return true;
}
static __attribute__((noinline)) block *str_from(const unsigned char *bytes, size_t len) {
    block *t = block_alloc(len + 1);
    memcpy(DATA(t), bytes, len);
    DATA(t)[len] = 0;
    t->len = (int64_t)len;
    t->reserved = 0;
    if (text_ascii(DATA(t), len)) t->kind |= ASCII;
    return t;
}
static __attribute__((noinline)) int64_t find_bytes(const block *text, const unsigned char *wanted, int64_t wlen, int64_t start) {
    const unsigned char *data = DATA(text);
    if (wlen > text->len - start) return -1;
    for (;;) {
        const unsigned char *hit = memchr(data + start, wanted[0], (size_t)(text->len - wlen - start + 1));
        if (!hit) return -1;
        start = hit - data;
        int64_t same = 1;
        while (same < wlen && hit[same] == wanted[same]) ++same;
        if (same == wlen) return start;
        ++start;
        if (start > text->len - wlen) return -1;
    }
}
static inline int64_t str_chars(const block *t) { return (t->kind & ASCII) ? t->len : -1; }

typedef struct view { int64_t at, len; } view;
typedef struct list { int64_t len, cap; void *items; } list;

static __attribute__((noinline)) void push(list *l, const void *item, size_t size) {
    if (l->len == l->cap) {
        l->cap = l->cap ? l->cap * 2 : 2;
        l->items = realloc(l->items, (size_t)l->cap * size);
    }
    memcpy((char *)l->items + (size_t)l->len * size, item, size);
    l->len++;
}

static __attribute__((noinline)) list split(const block *text, const char *sep) {
    list l = { 0, 0, NULL };
    int64_t slen = (int64_t)strlen(sep), at = 0;
    for (;;) {
        int64_t hit = find_bytes(text, (const unsigned char *)sep, slen, at);
        int64_t end = hit < 0 ? text->len : hit;
#if RUNG == 0
        block *piece = str_from(DATA(text) + at, (size_t)(end - at));
        push(&l, &piece, sizeof piece);
#else
        view piece = { at, end - at };
        push(&l, &piece, sizeof piece);
#endif
        if (hit < 0) break;
        at = hit + slen;
    }
    return l;
}
static __attribute__((noinline)) void drop(list *l) {
#if RUNG == 0
    for (int64_t i = 0; i < l->len; i++) {
        block *piece = ((block **)l->items)[i];
        if (piece && piece->count != UINT32_MAX && --piece->count == 0) block_free(piece);
    }
#endif
    free(l->items);
}

/* The pieces of one split, visited without a list (rung 2): calls f(len) per piece. */
#define FOR_PIECES(text, sep, LEN, BODY) do { \
    int64_t slen_ = (int64_t)strlen(sep), at_ = 0; \
    for (;;) { \
        int64_t hit_ = find_bytes(text, (const unsigned char *)(sep), slen_, at_); \
        int64_t end_ = hit_ < 0 ? (text)->len : hit_; \
        int64_t LEN = end_ - at_; \
        BODY; \
        if (hit_ < 0) break; \
        at_ = hit_ + slen_; \
    } \
} while (0)

int main(void) {
    /* shared_text(): 2000 lines "item{i},{(i*7919)%100003},{'xxxxxx'[:i%7]}\n", 110 times. */
    char *line_block = malloc(1 << 16);
    size_t used = 0;
    for (int i = 0; i < 2000; i++) used += (size_t)sprintf(line_block + used, "item%d,%d,%.*s\n", i, (i * 7919) % 100003, i % 7, "xxxxxx");
    block *text = aligned_alloc(32, (32 + used * 110 + 1 + 31) & ~(size_t)31);
    text->count = 1; text->kind = 3 | ASCII; text->len = (int64_t)(used * 110); text->reserved = 0;
    for (int r = 0; r < 110; r++) memcpy(DATA(text) + used * (size_t)r, line_block, used);
    int64_t lines = 0, width = 0, fields = 0, runs = 0, run_width = 0;
    for (int round = 0; round < 3; round++) {
#if RUNG <= 1
        list l = split(text, "\n");
        for (int64_t i = 0; i < l.len; i++) {
            lines += 1;
#if RUNG == 0
            width += str_chars(((block **)l.items)[i]);
#else
            width += ((view *)l.items)[i].len;
#endif
        }
        drop(&l);
        list f = split(text, ",");
        fields += f.len;
        drop(&f);
        list x = split(text, "x\nitem");
        for (int64_t i = 0; i < x.len; i++) {
            runs += 1;
#if RUNG == 0
            run_width += str_chars(((block **)x.items)[i]);
#else
            run_width += ((view *)x.items)[i].len;
#endif
        }
        drop(&x);
#else
        FOR_PIECES(text, "\n", len, { lines += 1; width += len; });
        FOR_PIECES(text, ",", len, { (void)len; fields += 1; });
        FOR_PIECES(text, "x\nitem", len, { runs += 1; run_width += len; });
#endif
    }
    printf("%lld %lld %lld %lld %lld\n", (long long)lines, (long long)width, (long long)fields, (long long)runs, (long long)run_width);
    return 0;
}
