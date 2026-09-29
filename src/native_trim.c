/* Character-set trim scans trusted scalar boundaries once, then shares/copies
   through the existing indexed constructors. Byte sets accept every octet. */
#include "native_python.h"
#include "native_unicode.h"
#include <stdlib.h>
#include <string.h>
#ifdef MYL_PYTHON_STEPS
size_t myl_native_trim_steps;
#define TRIM_STEPS(n) (myl_native_trim_steps+=(n))
#else
#define TRIM_STEPS(n) ((void)(n))
#endif

enum { SMALL_POINTS=32, UNICODE_WORDS=0x110000/64 };
typedef struct { uint64_t ascii[4]; uint32_t small[SMALL_POINTS]; size_t count; uint64_t *wide; } scalar_set;
typedef struct { size_t first, last; } trim_span;

static int ascii_space(uint32_t point) {
    return point==' ' || (point>=9 && point<=13);
}

static int set_contains(const scalar_set *set, uint32_t point) {
    TRIM_STEPS(1);
    if (point<256) return (int)((set->ascii[point/64]>>(point%64))&1);
    if (set->wide) return (int)((set->wide[point/64]>>(point%64))&1);
    for (size_t i=0;i<set->count;i++) {
        TRIM_STEPS(1);
        if (set->small[i]==point) return 1;
    }
    return 0;
}

/* A large charset uses deterministic direct membership, never a collision-
   sensitive hash table. Charge temporary storage while no collection can run. */
static int set_widen(myl_native_heap *heap, scalar_set *set) {
    size_t bytes=UNICODE_WORDS*sizeof(uint64_t);
    if (heap->bytes>heap->limit || bytes>heap->limit-heap->bytes) {
        heap->exhausted=1;
        return 0;
    }
    set->wide=calloc(UNICODE_WORDS,sizeof(uint64_t));
    if (!set->wide) return 0;
    heap->bytes+=bytes;
    for (size_t i=0;i<set->count;i++) set->wide[set->small[i]/64]|=UINT64_C(1)<<(set->small[i]%64);
    return 1;
}

static void set_release(myl_native_heap *heap, scalar_set *set) {
    if (!set->wide) return;
    heap->bytes-=UNICODE_WORDS*sizeof(uint64_t);
    free(set->wide);
}

static int set_add(myl_native_heap *heap, scalar_set *set, uint32_t point) {
    TRIM_STEPS(1);
    if (point<256) { set->ascii[point/64]|=UINT64_C(1)<<(point%64); return 1; }
    if (set_contains(set,point)) return 1;
    if (!set->wide && set->count==SMALL_POINTS && !set_widen(heap,set)) return 0;
    if (set->wide) set->wide[point/64]|=UINT64_C(1)<<(point%64);
    else set->small[set->count++]=point;
    return 1;
}

static int text_set(myl_native_heap *heap, scalar_set *set, const myl_native_text *chars) {
    const unsigned char *data=myl_native_text_storage(chars);
    for (size_t at=0;at<chars->bytes;)
        if (!set_add(heap,set,myl_unicode_next(data,&at))) return 0;
    return 1;
}

static int trim_point(const scalar_set *set, uint32_t point) {
    TRIM_STEPS(1);
    return set ? set_contains(set,point) : myl_unicode_space(point);
}

static trim_span text_span(const myl_native_text *input, const scalar_set *set, int ends) {
    const unsigned char *data=myl_native_text_storage(input);
    size_t low=0, high=input->bytes, first=0, last=input->length;
    if (ends!=2) while (low<high) {
        size_t next=low;
        if (!trim_point(set,myl_unicode_next(data,&next))) break;
        low=next; first++;
    }
    if (ends!=1) while (high>low) {
        size_t next=myl_unicode_previous(data,high), cursor=next;
        if (!trim_point(set,myl_unicode_next(data,&cursor))) break;
        high=next; last--;
    }
    return (trim_span){first,last};
}

myl_native_text *myl_native_text_trim_chars(myl_native_heap *heap, myl_native_text *input,
                                           const myl_native_text *chars, int ends) {
    scalar_set set={0};
    if (chars && !text_set(heap,&set,chars)) { set_release(heap,&set); return NULL; }
    trim_span span=text_span(input,chars ? &set : NULL,ends);
    set_release(heap,&set);
    return myl_native_text_copy(heap,input,span.first,span.last-span.first);
}

myl_native_bytes *myl_native_bytes_trim_chars(myl_native_heap *heap, myl_native_bytes *input,
                                             const myl_native_bytes *chars, int ends) {
    scalar_set set={0};
    if (chars) {
        const unsigned char *data=chars->storage;
        for (size_t at=0;at<chars->length;at++) set.ascii[data[at]/64]|=UINT64_C(1)<<(data[at]%64);
    } else {
        for (unsigned point=0;point<128;point++)
            if (ascii_space(point)) set.ascii[point/64]|=UINT64_C(1)<<(point%64);
    }
    const unsigned char *data=input->storage;
    size_t first=0,last=input->length;
    if (ends!=2) while (first<last && set_contains(&set,data[first])) first++;
    if (ends!=1) while (last>first && set_contains(&set,data[last-1])) last--;
    return myl_native_bytes_slice(heap,input,(int64_t)first,(int64_t)last);
}
