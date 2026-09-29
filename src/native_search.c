/* Python search windows and constant-space two-way reverse substring search. */
#include "native_python.h"
#include <string.h>

typedef struct { const unsigned char *data; size_t length; int reverse; } octets;
typedef struct { size_t first, last; int valid; } search_window;
typedef struct { size_t cut, period; } factorization;
#ifdef MYL_SEARCH_STEPS
size_t myl_native_search_steps;
#endif

static unsigned char octet_at(octets text, size_t index) {
#ifdef MYL_SEARCH_STEPS
    myl_native_search_steps++;
#endif
    return text.data[text.reverse ? text.length - 1 - index : index];
}

/* Crochemore-Perrin critical factorization. SIZE_MAX represents suffix -1;
   every access uses suffix+k with k>=1, so its wrap is exactly index zero. */
static factorization maximal_suffix(octets needle, int order) {
    size_t suffix=SIZE_MAX, candidate=0, offset=1, period=1;
    while (offset < needle.length-candidate) {
        unsigned char a=octet_at(needle,suffix+offset), b=octet_at(needle,candidate+offset);
        if (a==b) {
            if (offset==period) { candidate+=period; offset=1; }
            else offset++;
        } else if (order ? a>b : a<b) {
            candidate+=offset; offset=1; period=candidate-suffix;
        } else {
            suffix=candidate++; offset=period=1;
        }
    }
    return (factorization){suffix+1,period};
}

static size_t periodic_memory(octets needle, factorization *split) {
    for (size_t i=0;i<split->cut;i++) {
        if (octet_at(needle,i)!=octet_at(needle,i+split->period)) {
            size_t right=needle.length-split->cut;
            size_t left=split->cut ? split->cut-1 : 0;
            split->period=(left>right ? left : right)+1;
            return 0;
        }
    }
    return needle.length-split->period;
}

/* Virtual reversed payloads need no copied buffer. The same two-way proof
   bounds comparisons linearly in haystack+needle, including periodic misses. */
static size_t reverse_find(octets haystack, octets needle) {
    factorization a=maximal_suffix(needle,0), b=maximal_suffix(needle,1);
    factorization split=a.cut>b.cut ? a : b;
    size_t memory_after=periodic_memory(needle,&split), memory=0, at=0;
    while (at<=haystack.length-needle.length) {
        size_t i=split.cut>memory ? split.cut : memory;
        while (i<needle.length && octet_at(needle,i)==octet_at(haystack,at+i)) i++;
        if (i<needle.length) {
            at+=i-split.cut+1; memory=0;
            continue;
        }
        i=split.cut;
        while (i>memory && octet_at(needle,i-1)==octet_at(haystack,at+i-1)) i--;
        if (i<=memory) return haystack.length-needle.length-at;
        at+=split.period; memory=memory_after;
    }
    return SIZE_MAX;
}

static size_t endpoint(size_t length, int64_t value, int start) {
    if (value>=0) return start || (uint64_t)value<=length ? (size_t)value : length;
    uint64_t distance=(uint64_t)(-(value+1))+1;
    return distance>length ? 0 : length-(size_t)distance;
}

static search_window window(size_t length, int64_t start, int64_t end) {
    size_t first=endpoint(length,start,1), last=endpoint(length,end,0);
    return (search_window){first,last,first<=last && first<=length};
}

static int64_t empty_answer(search_window bounds, int mode) {
    if (!bounds.valid) return mode==MYL_SEARCH_COUNT || mode>=MYL_SEARCH_PREFIX ? 0 : -1;
    if (mode==MYL_SEARCH_COUNT) return (int64_t)(bounds.last-bounds.first)+1;
    if (mode>=MYL_SEARCH_PREFIX) return 1;
    return (int64_t)(mode==MYL_SEARCH_RFIND || mode==MYL_SEARCH_RINDEX ? bounds.last : bounds.first);
}

static int64_t search_octets(octets input, octets needle, int mode) {
    if (needle.length>input.length) return mode>=MYL_SEARCH_COUNT ? 0 : -1;
    if (mode==MYL_SEARCH_COUNT)
        return (int64_t)myl_native_octets_count(input.data,input.length,needle.data,needle.length);
    if (mode>=MYL_SEARCH_PREFIX) {
        size_t at=mode==MYL_SEARCH_PREFIX ? 0 : input.length-needle.length;
        return !memcmp(input.data+at,needle.data,needle.length);
    }
    size_t found;
    if (mode==MYL_SEARCH_RFIND || mode==MYL_SEARCH_RINDEX) {
        input.reverse=needle.reverse=1;
        found=reverse_find(input,needle);
    } else found=myl_native_octets_find(input.data,input.length,needle.data,needle.length);
    return found==SIZE_MAX ? -1 : (int64_t)found;
}

int64_t myl_native_text_search_range(const myl_native_text *input, const myl_native_text *needle,
                                    int64_t start, int64_t end, int mode) {
    search_window bounds=window(input->length,start,end);
    if (!needle->length) return empty_answer(bounds,mode);
    if (!bounds.valid) return mode>=MYL_SEARCH_COUNT ? 0 : -1;
    size_t first=myl_native_text_offset(input,bounds.first), last=myl_native_text_offset(input,bounds.last);
    octets haystack={myl_native_text_storage(input)+first,last-first,0};
    octets sub={myl_native_text_storage(needle),needle->bytes,0};
    int64_t found=search_octets(haystack,sub,mode);
    if (found<0 || mode>=MYL_SEARCH_COUNT) return found;
    return (int64_t)myl_native_text_index(input,first+(size_t)found);
}

int64_t myl_native_bytes_search_range(const myl_native_bytes *input, const myl_native_bytes *needle,
                                     int64_t start, int64_t end, int mode) {
    search_window bounds=window(input->length,start,end);
    if (!needle->length) return empty_answer(bounds,mode);
    if (!bounds.valid) return mode>=MYL_SEARCH_COUNT ? 0 : -1;
    octets haystack={(const unsigned char *)input->storage+bounds.first,bounds.last-bounds.first,0};
    octets sub={needle->storage,needle->length,0};
    int64_t found=search_octets(haystack,sub,mode);
    return found<0 || mode>=MYL_SEARCH_COUNT ? found : found+(int64_t)bounds.first;
}
