/* S2-0: C transcription of bench/parity/suite/text_ops.my. All rungs build
 * the same 200000 independently formatted lines, join them, parse the fields,
 * replace item with it, and print the benchmark checksum. Rungs are cumulative:
 * 0 owned split strings; 1 slice views (identity: this source has no slices);
 * 2 split-piece spans in lists; 3 lazy split without lists; 4 memchr/two-way
 * search; 5 one-buffer replace (identity: the base already sizes once).
 * This is an ideal-C bound, not a removal of safety checks from production.
 */
#define _GNU_SOURCE
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
#if RUNG >= 4
    if (wlen > text->len - start) return -1;
    const unsigned char *found = wlen == 1 ? memchr(data + start, wanted[0], (size_t)(text->len - start)) : memmem(data + start, (size_t)(text->len - start), wanted, (size_t)wlen);
    return found ? found - data : -1;
#endif
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


typedef struct span { const unsigned char *data; int64_t len; } span;
typedef struct pieces { span *items; size_t len, cap; } pieces;
static void push_piece(pieces *p, span v) {
    if (p->len == p->cap) { p->cap = p->cap ? p->cap * 2 : 2; p->items = realloc(p->items, p->cap * sizeof(span)); }
    p->items[p->len++] = v;
}
static int64_t span_find(span s, const char *sep, int64_t at) {
    size_t n = strlen(sep);
    if (n > (size_t)(s.len - at)) return -1;
#if RUNG >= 4
    const unsigned char *p = n == 1 ? memchr(s.data + at, sep[0], (size_t)(s.len-at)) : memmem(s.data+at, (size_t)(s.len-at), sep, n);
    return p ? p-s.data : -1;
#else
    for (;;) {
        const unsigned char *p = memchr(s.data+at, sep[0], (size_t)(s.len-at)-(n-1));
        if (!p) return -1;
        at = p-s.data;
        size_t i=1; while (i<n && p[i]==(unsigned char)sep[i]) ++i;
        if (i==n) return at;
        if (++at > s.len-(int64_t)n) return -1;
    }
#endif
}
static span next_piece(span s, const char *sep, int64_t *cursor) {
    int64_t hit = span_find(s, sep, *cursor), end = hit < 0 ? s.len : hit;
    span p = {s.data+*cursor, end-*cursor};
    *cursor = hit < 0 ? s.len+1 : hit+(int64_t)strlen(sep);
    return p;
}
static pieces split(span s, const char *sep) {
    pieces result = {0}; int64_t at=0;
    while (at<=s.len) {
        span p=next_piece(s,sep,&at);
#if RUNG < 2
        block *owned=str_from(p.data,(size_t)p.len); p=(span){DATA(owned),owned->len};
#endif
        push_piece(&result,p);
    }
    return result;
}
static void drop(pieces p) {
#if RUNG < 2
    for (size_t i=0;i<p.len;i++) block_free((block *)(p.items[i].data-32));
#endif
    free(p.items);
}
static size_t decimal(unsigned char *out, int64_t n) {
    unsigned char reversed[32]; size_t used=0;
    do { reversed[used++]=(unsigned char)('0'+n%10); n/=10; } while(n);
    for (size_t j=0;j<used;j++) out[j]=reversed[used-j-1];
    return used;
}
static block *make_text(void) {
    pieces lines={0}; size_t length=199999;
    for (int64_t i=0;i<200000;i++) {
        unsigned char buf[128]; memcpy(buf,"item",4); size_t at=4;
        at+=decimal(buf+at,i); buf[at++]=','; at+=decimal(buf+at,(i*7919)%100003); buf[at++]=',';
        memset(buf+at,'x',(size_t)(i%7)); at+=(size_t)(i%7);
        block *line=str_from(buf,at); push_piece(&lines,(span){DATA(line),line->len}); length+=at;
    }
    block *result=block_alloc(length+1); result->len=(int64_t)length; result->kind|=ASCII;
    size_t at=0;
    for (size_t i=0;i<lines.len;i++) { if (i) DATA(result)[at++]='\n'; memcpy(DATA(result)+at,lines.items[i].data,(size_t)lines.items[i].len); at+=(size_t)lines.items[i].len; block_free((block *)(lines.items[i].data-32)); }
    DATA(result)[at]=0; free(lines.items); return result;
}
static void consume(span line, int64_t *total, int64_t *widths, int64_t *sevens) {
    span fields[3];
#if RUNG < 3
    pieces p=split(line,","); if(p.len!=3) abort(); memcpy(fields,p.items,sizeof(fields));
#else
    int64_t cursor=0; for(int i=0;i<3;i++) fields[i]=next_piece(line,",",&cursor);
#endif
    int64_t number=0;
    for(int64_t i=0;i<fields[1].len;i++) { unsigned char c=fields[1].data[i]; if(c<'0'||c>'9') abort(); number=number*10+c-'0'; }
    *total+=number; *widths+=fields[2].len; *sevens+=fields[0].len && fields[0].data[fields[0].len-1]=='7';
#if RUNG < 3
    drop(p);
#endif
}
static block *replace(block *text) {
    int64_t hits=0,at=0,hit;
    while((hit=find_bytes(text,(const unsigned char *)"item",4,at))>=0) { ++hits; at=hit+4; }
    block *out=block_alloc((size_t)(text->len-2*hits)+1); out->len=text->len-2*hits; at=0; int64_t used=0;
    while((hit=find_bytes(text,(const unsigned char *)"item",4,at))>=0) { memcpy(DATA(out)+used,DATA(text)+at,(size_t)(hit-at)); used+=hit-at; memcpy(DATA(out)+used,"it",2); used+=2; at=hit+4; }
    memcpy(DATA(out)+used,DATA(text)+at,(size_t)(text->len-at)); DATA(out)[out->len]=0;
    if(text_ascii(DATA(out),(uint64_t)out->len)) out->kind|=ASCII;
    return out;
}
int main(void) {
    block *text=make_text(); span all={DATA(text),text->len}; int64_t total=0,widths=0,sevens=0;
#if RUNG < 3
    pieces lines=split(all,"\n"); for(size_t i=0;i<lines.len;i++) consume(lines.items[i],&total,&widths,&sevens); drop(lines);
#else
    int64_t cursor=0; while(cursor<=all.len) consume(next_piece(all,"\n",&cursor),&total,&widths,&sevens);
#endif
    block *rewritten=replace(text); int64_t count=0,at=0,hit;
    while((hit=find_bytes(text,(const unsigned char *)",1",2,at))>=0) { ++count; at=hit+2; }
    printf("%lld %lld %lld\n%lld %lld %lld\n",(long long)total,(long long)widths,(long long)sevens,(long long)text->len,(long long)rewritten->len,(long long)count);
    block_free(rewritten); block_free(text); return 0;
}
