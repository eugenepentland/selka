#include "native_text_methods.h"
#include <string.h>
/* Traced pointer slot: it roots a receiver across an allocation and describes the
   element of the list `splitlines` builds. */
static const myl_native_type pointer_type = { .size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER };
const uint32_t *myl_native_text_points(const myl_native_text *text) { return text->storage; }
static int space_point(uint32_t point) {
    return point==' '||point=='\t'||point=='\n'||point=='\r'||point==0x0b||point==0x0c;
}
static int classified(uint32_t point, int property) {
    if (property==MYL_TEXT_DIGIT) return point>='0' && point<='9';
    if (property==MYL_TEXT_ALPHA) return (point>='a'&&point<='z') || (point>='A'&&point<='Z');
    return space_point(point);
}
static int matches_at(const myl_native_text *input, size_t at, const myl_native_text *needle) {
    if (input->length-at < needle->length) return 0;
    return !memcmp(myl_native_text_points(input)+at, needle->storage, needle->length*4);
}
/* Non-overlapping occurrences, scanning left to right exactly as the VM does. */
static size_t occurrences(const myl_native_text *input, const myl_native_text *needle) {
    size_t found=0, at=0;
    while (needle->length && at+needle->length<=input->length) {
        if (matches_at(input,at,needle)) { found++; at+=needle->length; } else at++;
    }
    return found;
}
int64_t myl_native_text_find(const myl_native_text *input, const myl_native_text *needle) {
    if (!needle->length || needle->length>input->length) return -1;
    for (size_t at=0; at+needle->length<=input->length; at++)
        if (matches_at(input,at,needle)) return (int64_t)at;
    return -1;
}
int64_t myl_native_text_count(const myl_native_text *input, const myl_native_text *needle) {
    return (int64_t)occurrences(input,needle);
}
int myl_native_text_edge(const myl_native_text *input, const myl_native_text *affix, int leading) {
    if (affix->length>input->length) return 0;
    return matches_at(input, leading ? 0 : input->length-affix->length, affix);
}
int myl_native_text_every(const myl_native_text *input, int property) {
    if (!input->length) return 0;
    const uint32_t *points=myl_native_text_points(input);
    for (size_t i=0;i<input->length;i++) if (!classified(points[i],property)) return 0;
    return 1;
}
myl_native_text *myl_native_text_trim(myl_native_heap *heap, myl_native_text *input, int ends) {
    const uint32_t *points=myl_native_text_points(input);
    size_t lower=0, upper=input->length;
    if (ends!=MYL_TEXT_TRAILING) while (lower<upper && space_point(points[lower])) lower++;
    if (ends!=MYL_TEXT_LEADING) while (upper>lower && space_point(points[upper-1])) upper--;
    return myl_native_text_copy(heap,input,lower,upper-lower);
}
myl_native_text *myl_native_text_case(myl_native_heap *heap, myl_native_text *input, int upper) {
    myl_native_text *result=myl_native_text_copy(heap,input,0,input->length);
    if (!result) return NULL;
    uint32_t *points=result->storage;
    for (size_t i=0;i<result->length;i++) {
        if (upper && points[i]>='a' && points[i]<='z') points[i]-=32;
        else if (!upper && points[i]>='A' && points[i]<='Z') points[i]+=32;
    }
    return result;
}
myl_native_text *myl_native_text_zfill(myl_native_heap *heap, myl_native_text *input, int64_t width) {
    size_t target = width<=0 ? 0 : ((uint64_t)width>0xffffffffu ? (size_t)0xffffffffu : (size_t)width);
    if (input->length>=target) return myl_native_text_copy(heap,input,0,input->length);
    const uint32_t *first=myl_native_text_points(input);
    size_t keep = (input->length && (first[0]=='+' || first[0]=='-')) ? 1 : 0;
    myl_native_root root;
    myl_native_root_push(heap,&root,&input,&pointer_type);
    myl_native_text *result=myl_native_list_new(heap,&myl_native_text_point,target);
    if (result) {
        uint32_t *out=result->storage;
        const uint32_t *in=myl_native_text_points(input);
        size_t at=0;
        if (keep) out[at++]=in[0];
        for (size_t i=0;i<target-input->length;i++) out[at++]='0';
        if (input->length-keep) memcpy(out+at,in+keep,(input->length-keep)*4);
        result->length=target;
    }
    myl_native_root_pop(heap,&root);
    return result;
}
myl_native_text *myl_native_text_replace(myl_native_heap *heap, myl_native_text *input, myl_native_text *needle, myl_native_text *insert) {
    if (!needle->length) return NULL;
    size_t hits=occurrences(input,needle);
    if (insert->length && hits>SIZE_MAX/insert->length) return NULL;
    size_t kept=input->length-hits*needle->length, added=hits*insert->length;
    if (added>SIZE_MAX-kept) return NULL;
    size_t total=kept+added;
    myl_native_root a,b,c;
    myl_native_root_push(heap,&a,&input,&pointer_type);
    myl_native_root_push(heap,&b,&needle,&pointer_type);
    myl_native_root_push(heap,&c,&insert,&pointer_type);
    myl_native_text *result=myl_native_list_new(heap,&myl_native_text_point,total);
    if (result) {
        uint32_t *out=result->storage;
        size_t at=0, cursor=0;
        while (cursor<input->length) {
            if (cursor+needle->length<=input->length && matches_at(input,cursor,needle)) {
                if (insert->length) memcpy(out+at,insert->storage,insert->length*4);
                at+=insert->length;
                cursor+=needle->length;
            } else out[at++]=myl_native_text_points(input)[cursor++];
        }
        result->length=at;
    }
    myl_native_root_pop(heap,&c); myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
/* One line, rooted so the growing list and the fresh piece both survive the append. */
static int append_line(myl_native_heap *heap, myl_native_list *result, myl_native_text *input, size_t start, size_t count) {
    myl_native_root a,b;
    myl_native_root_push(heap,&a,&result,&pointer_type);
    myl_native_text *piece=myl_native_text_copy(heap,input,start,count);
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
        size_t start=0, cursor=0;
        while (cursor<input->length) {
            uint32_t point=myl_native_text_points(input)[cursor];
            if (point!='\n' && point!='\r') { cursor++; continue; }
            if (!append_line(heap,result,input,start,cursor-start)) { result=NULL; break; }
            cursor++;
            if (point=='\r' && cursor<input->length && myl_native_text_points(input)[cursor]=='\n') cursor++;
            start=cursor;
        }
        if (result && start<input->length && !append_line(heap,result,input,start,input->length-start)) result=NULL;
    }
    myl_native_root_pop(heap,&b); myl_native_root_pop(heap,&a);
    return result;
}
