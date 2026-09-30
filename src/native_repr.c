/* Exact Unicode16 scalar repr, independent of ordinary print/str hot paths. */
#include "native_python.h"
#include "native_unicode.h"
#include "native_unicode_data.h"
#include "native_rc_collections.h"
#include <string.h>
#ifdef MYL_PYTHON_STEPS
size_t myl_native_repr_steps;
#define REPR_STEPS(n) (myl_native_repr_steps+=(n))
#else
#define REPR_STEPS(n) ((void)(n))
#endif

typedef struct { const unsigned char *data; size_t length; int bytes; unsigned char quote; } repr_input;
typedef struct { unsigned char *data; size_t octets, scalars; int plain; } repr_output;

static int printable(uint32_t point) {
    size_t low=0, high=sizeof myl_nonprintable/sizeof myl_nonprintable[0];
    while (low<high) {
        REPR_STEPS(1);
        size_t middle=low+(high-low)/2;
        if (point<myl_nonprintable[middle][0]) high=middle;
        else if (point>myl_nonprintable[middle][1]) low=middle+1;
        else return 0;
    }
    return 1;
}

static repr_input input_of(void *source, int bytes) {
    repr_input input={0};
    input.bytes=bytes;
    if (bytes) {
        const myl_native_bytes *value=source;
        input.data=value->storage; input.length=value->length;
    } else {
        const myl_native_text *value=source;
        input.data=myl_native_text_storage(value); input.length=value->bytes;
    }
    int single=input.length && memchr(input.data,'\'',input.length)!=NULL;
    int double_quote=input.length && memchr(input.data,'"',input.length)!=NULL;
    REPR_STEPS(2*input.length);
    input.quote=single && !double_quote ? '"' : '\'';
    return input;
}

static int output_bytes(repr_output *out, const unsigned char *data, size_t bytes, size_t scalars) {
    if (bytes>SIZE_MAX-out->octets || scalars>SIZE_MAX-out->scalars) return 0;
    if (out->data) memcpy(out->data+out->octets,data,bytes);
    out->octets+=bytes; out->scalars+=scalars;
    return 1;
}

static int output_escape(repr_output *out, uint32_t point, unsigned digits) {
    static const unsigned char hex[]="0123456789abcdef";
    unsigned char escaped[10]={'\\',digits==2 ? 'x' : digits==4 ? 'u' : 'U'};
    for (unsigned i=0;i<digits;i++) escaped[2+i]=hex[(point>>(4*(digits-1-i)))&15];
    return output_bytes(out,escaped,digits+2,digits+2);
}

static int output_point(repr_output *out, repr_input input, uint32_t point, size_t first, size_t last) {
    unsigned char escaped[2]={'\\',0};
    if (point=='\t') escaped[1]='t';
    else if (point=='\n') escaped[1]='n';
    else if (point=='\r') escaped[1]='r';
    else if (point=='\\' || point==input.quote) escaped[1]=(unsigned char)point;
    if (escaped[1]) return output_bytes(out,escaped,2,2);
    int copy=input.bytes ? point>=32 && point<127 : printable(point);
    if (!copy) return output_escape(out,point,point<256 ? 2 : point<65536 ? 4 : 8);
    if (point>=128) out->plain=0;
    return output_bytes(out,input.data+first,last-first,1);
}

static int render(repr_input input, repr_output *out) {
    if (input.bytes && !output_bytes(out,(const unsigned char *)"b",1,1)) return 0;
    if (!output_bytes(out,&input.quote,1,1)) return 0;
    for (size_t at=0;at<input.length;) {
        size_t first=at;
        uint32_t point=input.bytes ? input.data[at++] : myl_unicode_next(input.data,&at);
        REPR_STEPS(at-first);
        if (!output_point(out,input,point,first,at)) return 0;
    }
    return output_bytes(out,&input.quote,1,1);
}

static myl_native_text *repr_build(myl_native_heap *heap, void *source, int bytes) {
    repr_output measured={.plain=1};
    if (!render(input_of(source,bytes),&measured)) return NULL;
    myl_native_root root;
    myl_native_root_push(heap,&root,&source,&myl_rc_pointer_leaf);
    myl_native_text *result=myl_native_text_build_scalars(heap,measured.octets,measured.scalars);
    if (result) {
        repr_output out={.data=(unsigned char *)myl_native_text_storage(result),.plain=1};
        (void)render(input_of(source,bytes),&out);
        myl_native_text_publish(result,measured.scalars,measured.plain);
    }
    myl_native_root_pop(heap,&root);
    return result;
}

myl_native_text *myl_native_text_repr(myl_native_heap *heap, myl_native_text *input) {
    return repr_build(heap,input,0);
}
myl_native_text *myl_native_bytes_repr(myl_native_heap *heap, myl_native_bytes *input) {
    return repr_build(heap,input,1);
}
