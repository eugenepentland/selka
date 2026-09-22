/* `memmem` is a GNU extension, so the feature macro has to precede <string.h>. */
#define _GNU_SOURCE
#include "native_text_methods.h"
#include <string.h>
/* Splits on maximal runs of ASCII whitespace, dropping every empty piece. It is
   declared here rather than in the companion header so this file stays the only
   one the whitespace-split addition touches on the runtime side; the QBE
   emitter reaches it by symbol name. */
myl_native_list *myl_native_text_split_whitespace(myl_native_heap *, myl_native_text *);
/* The runtime trap reporter the emitted checks call; declared here for the same
   reason, and defined in qbe_runtime.c beside every other trap reporter. */
void myl_qbe_fail(void *, const char *);
/* Traced pointer slot: it roots a receiver across an allocation and describes the
   element of the list `splitlines` builds. */
static const myl_native_type pointer_type = { .size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER };
/* Every ASCII whitespace scalar, tested on one octet: an octet at or above 0x80
   is part of a non-ASCII scalar, which is neither whitespace nor a digit nor a
   letter, so the octet test answers exactly what the scalar test did. */
static int space_octet(unsigned char value) {
    return value==' '||value=='\t'||value=='\n'||value=='\r'||value==0x0b||value==0x0c;
}
static int classified(unsigned char value, int property) {
    if (property==MYL_TEXT_DIGIT) return value>='0' && value<='9';
    if (property==MYL_TEXT_ALPHA) return (value>='a'&&value<='z') || (value>='A'&&value<='Z');
    return space_octet(value);
}
/* An empty needle matches everywhere, and answering before the comparison keeps
   the empty string's absent payload out of pointer arithmetic. */
static int matches_at(const myl_native_text *input, size_t at, const myl_native_text *needle) {
    if (!needle->bytes) return 1;
    if (input->bytes-at < needle->bytes) return 0;
    return !memcmp(myl_native_text_storage(input)+at, myl_native_text_storage(needle), needle->bytes);
}
/* Non-overlapping occurrences in octets, scanning left to right exactly as the
   VM does. Both payloads are valid UTF-8, so an octet match starts a scalar in
   both and advancing by the needle's octets cannot land inside a scalar. The
   scan is the shared bulk search, so an offset that cannot start a match costs
   no comparison call. */
static size_t occurrences(const myl_native_text *input, const myl_native_text *needle) {
    return myl_native_octets_count(myl_native_text_storage(input),input->bytes,myl_native_text_storage(needle),needle->bytes);
}
/* An empty needle answers -1 here; the emitted call traps R_EMPTY_SEPARATOR
   before this runs. A needle longer than the receiver is absent as before, and
   the scan itself runs in the libc bulk primitive instead of one `memcmp` call
   per candidate scalar. The answer is a scalar index, which is the octet offset
   itself for ASCII text and one walk otherwise. */
int64_t myl_native_text_find(const myl_native_text *input, const myl_native_text *needle) {
    if (!needle->length || needle->length>input->length) return -1;
    size_t at=myl_native_text_find_bytes(input,needle);
    if (at==SIZE_MAX) return -1;
    return (int64_t)myl_native_text_index(input,at);
}
int64_t myl_native_text_count(const myl_native_text *input, const myl_native_text *needle) {
    return (int64_t)occurrences(input,needle);
}
int myl_native_text_edge(const myl_native_text *input, const myl_native_text *affix, int leading) {
    if (affix->length>input->length) return 0;
    return matches_at(input, leading ? 0 : input->bytes-affix->bytes, affix);
}
int myl_native_text_every(const myl_native_text *input, int property) {
    if (!input->length) return 0;
    const unsigned char *bytes=myl_native_text_storage(input);
    for (size_t i=0;i<input->bytes;i++) if (!classified(bytes[i],property)) return 0;
    return 1;
}
myl_native_text *myl_native_text_trim(myl_native_heap *heap, myl_native_text *input, int ends) {
    const unsigned char *bytes=myl_native_text_storage(input);
    size_t lower=0, upper=input->bytes;
    if (ends!=MYL_TEXT_TRAILING) while (lower<upper && space_octet(bytes[lower])) lower++;
    if (ends!=MYL_TEXT_LEADING) while (upper>lower && space_octet(bytes[upper-1])) upper--;
    size_t first=myl_native_text_index(input,lower), last=myl_native_text_index(input,upper);
    return myl_native_text_copy(heap,input,first,last-first);
}
/* Case mapping rewrites ASCII letters one octet for one octet, so the payload
   stays valid UTF-8, the scalar count is unchanged and every non-ASCII scalar
   is copied through untouched. */
myl_native_text *myl_native_text_case(myl_native_heap *heap, myl_native_text *input, int upper) {
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *result=myl_native_text_build(heap,input->bytes);
    if (result) {
        unsigned char *bytes=(unsigned char *)myl_native_text_storage(result);
        memcpy(bytes,myl_native_text_storage(input),input->bytes);
        for (size_t i=0;i<input->bytes;i++) {
            if (upper && bytes[i]>='a' && bytes[i]<='z') bytes[i]-=32;
            else if (!upper && bytes[i]>='A' && bytes[i]<='Z') bytes[i]+=32;
        }
        myl_native_text_publish(result,input->length,input->flags&MYL_TEXT_ASCII);
    }
    myl_native_root_pop(heap,&root);
    return result;
}
myl_native_text *myl_native_text_zfill(myl_native_heap *heap, myl_native_text *input, int64_t width) {
    size_t target = width<=0 ? 0 : ((uint64_t)width>0xffffffffu ? (size_t)0xffffffffu : (size_t)width);
    if (input->length>=target) return myl_native_text_copy(heap,input,0,input->length);
    const unsigned char *first=myl_native_text_storage(input);
    /* A leading sign is one ASCII scalar, so one octet. */
    size_t keep = (input->length && (first[0]=='+' || first[0]=='-')) ? 1 : 0;
    size_t pad = target-input->length;
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *result=myl_native_text_build(heap,pad+input->bytes);
    if (result) {
        unsigned char *out=(unsigned char *)myl_native_text_storage(result);
        size_t at=0;
        if (keep) out[at++]=first[0];
        memset(out+at,'0',pad);
        at+=pad;
        if (input->bytes-keep) memcpy(out+at,first+keep,input->bytes-keep);
        myl_native_text_publish(result,target,input->flags&MYL_TEXT_ASCII);
    }
    myl_native_root_pop(heap,&root);
    return result;
}
/* One counting scan sizes the result exactly; the copying scan then finds the
   same matches again and moves each unchanged run between them with one
   `memcpy`, instead of testing every offset and copying octet by octet. */
myl_native_text *myl_native_text_replace(myl_native_heap *heap, myl_native_text *input, myl_native_text *needle, myl_native_text *insert) {
    if (!needle->length) return NULL;
    size_t hits=occurrences(input,needle);
    if (insert->bytes && hits>SIZE_MAX/insert->bytes) return NULL;
    size_t kept=input->bytes-hits*needle->bytes, added=hits*insert->bytes;
    if (added>SIZE_MAX-kept) return NULL;
    size_t total=kept+added;
    myl_native_root a,b,c;
    myl_native_root_push(heap,&a,&input,&pointer_type);
    myl_native_root_push(heap,&b,&needle,&pointer_type);
    myl_native_root_push(heap,&c,&insert,&pointer_type);
    myl_native_text *result=myl_native_text_build(heap,total);
    if (result) {
        const unsigned char *source=myl_native_text_storage(input);
        const unsigned char *needle_bytes=myl_native_text_storage(needle);
        const unsigned char *insert_bytes=myl_native_text_storage(insert);
        unsigned char *out=(unsigned char *)myl_native_text_storage(result);
        size_t at=0, cursor=0;
        for (size_t left=hits; left; left--) {
            size_t hit=myl_native_octets_find(source+cursor,input->bytes-cursor,needle_bytes,needle->bytes);
            if (hit==SIZE_MAX) break;
            if (hit) memcpy(out+at,source+cursor,hit);
            at+=hit;
            if (insert->bytes) memcpy(out+at,insert_bytes,insert->bytes);
            at+=insert->bytes;
            cursor+=hit+needle->bytes;
        }
        if (cursor<input->bytes) memcpy(out+at,source+cursor,input->bytes-cursor);
        myl_native_text_publish(result,input->length-hits*needle->length+hits*insert->length,
                                input->flags&insert->flags&MYL_TEXT_ASCII);
    }
    myl_native_root_pop(heap,&c); myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
/* One line, rooted so the growing list and the fresh piece both survive the append. */
static int append_line(myl_native_heap *heap, myl_native_list *result, myl_native_text *input, size_t start, size_t end) {
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&result,&pointer_type);
    myl_native_text *piece=myl_native_text_substring(heap,input,start,end);
    if (!piece) { myl_native_root_pop(heap,&a); return 0; }
    myl_native_root_push(heap,&b,&piece,&pointer_type);
    int appended=myl_native_list_append(heap,result,&piece);
    myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return appended;
}
myl_native_list *myl_native_text_lines(myl_native_heap *heap, myl_native_text *input) {
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&input,&pointer_type);
    myl_native_list *result=myl_native_list_new(heap,&pointer_type,0);
    myl_native_root_push(heap,&b,&result,&pointer_type);
    if (result) {
        const unsigned char *bytes=myl_native_text_storage(input);
        size_t start=0, cursor=0;
        while (cursor<input->bytes) {
            unsigned char octet=bytes[cursor];
            if (octet!='\n' && octet!='\r') { cursor++; continue; }
            if (!append_line(heap,result,input,start,cursor)) { result=NULL; break; }
            cursor++;
            if (octet=='\r' && cursor<input->bytes && bytes[cursor]=='\n') cursor++;
            start=cursor;
        }
        if (result && start<input->bytes && !append_line(heap,result,input,start,input->bytes)) result=NULL;
    }
    myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
/* The Unicode scalar value of a text that holds exactly one scalar. The
   emitted length check has already rejected every other text, so this decodes
   the single stored scalar and cannot fail. */
int64_t myl_native_text_ord(const myl_native_text *text) {
    return (int64_t)myl_native_text_point_at(text,0);
}
/* One-scalar text for a Unicode scalar value: `0..0x10FFFF` excluding the
   surrogate range, encoded here so the caller needs no intermediate list. An
   invalid code is a located `R_TEXT_SCALAR` trap; a refused allocation answers
   NULL once the emitted check reports the budget. */
myl_native_text *myl_native_text_chr(void *context, myl_native_heap *heap, int64_t code) {
    if (code < 0 || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) {
        myl_qbe_fail(context, "R_TEXT_SCALAR");
        return NULL;
    }
    uint32_t point = (uint32_t)code;
    unsigned char raw[4];
    size_t width = 0;
    if (point < 0x80) raw[width++] = (unsigned char)point;
    else if (point < 0x800) {
        raw[width++] = (unsigned char)(0xc0 | (point >> 6));
        raw[width++] = (unsigned char)(0x80 | (point & 0x3f));
    } else if (point < 0x10000) {
        raw[width++] = (unsigned char)(0xe0 | (point >> 12));
        raw[width++] = (unsigned char)(0x80 | ((point >> 6) & 0x3f));
        raw[width++] = (unsigned char)(0x80 | (point & 0x3f));
    } else {
        raw[width++] = (unsigned char)(0xf0 | (point >> 18));
        raw[width++] = (unsigned char)(0x80 | ((point >> 12) & 0x3f));
        raw[width++] = (unsigned char)(0x80 | ((point >> 6) & 0x3f));
        raw[width++] = (unsigned char)(0x80 | (point & 0x3f));
    }
    return myl_native_text_from_utf8(heap, raw, width);
}
/* The located trap an `ord` argument that is not exactly one scalar raises. The
   emitted length check calls this by name, exactly as the separator check calls
   `myl_qbe_fail_empty_separator`. */
void myl_native_fail_text_scalar(void *context) { myl_qbe_fail(context, "R_TEXT_SCALAR"); }
/* Python's no-argument split: break the receiver on maximal runs of ASCII
   whitespace and keep only the nonempty pieces, so leading, trailing and
   doubled whitespace produce no empty string. `space_octet` is the same
   predicate `str.isspace()` classifies with, so the two cannot disagree about
   which octet separates. */
myl_native_list *myl_native_text_split_whitespace(myl_native_heap *heap, myl_native_text *input) {
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&input,&pointer_type);
    myl_native_list *result=myl_native_list_new(heap,&pointer_type,0);
    myl_native_root_push(heap,&b,&result,&pointer_type);
    if (result) {
        const unsigned char *bytes=myl_native_text_storage(input);
        size_t cursor=0;
        while (cursor<input->bytes) {
            while (cursor<input->bytes && space_octet(bytes[cursor])) cursor++;
            size_t start=cursor;
            while (cursor<input->bytes && !space_octet(bytes[cursor])) cursor++;
            if (start==cursor) break;
            if (!append_line(heap,result,input,start,cursor)) { result=NULL; break; }
        }
    }
    myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
