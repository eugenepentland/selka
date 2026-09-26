/* Ordinary copied-value bridge. Included in the generated library adapter. */
#include <stdlib.h>
typedef struct { const char *name; size_t size, count, stride; unsigned kind; const size_t *children, *offsets; } QbeWireType;
static const QbeWireType wire_types[];
static const MylangWireNode *wire_input;
static size_t wire_count, wire_cursor;
static const char *wire_error;
static void *wire_arguments[QBE_WIRE_ARGUMENTS], *wire_return;
static int wire_bad(const char *code) {wire_error=code;return 0;}
static uint64_t wire_word(const void *input,const QbeWireType *type) {
    uint64_t bits=0;
    memcpy(&bits,input,type->size);
    if (*type->name=='i' && type->size<8 && (bits & (UINT64_C(1)<<(type->size*8-1)))) bits|=UINT64_MAX<<(type->size*8);
    return bits;
}
static int wire_validate_one(void *,size_t,const void *);
/* The ordinary wire reader runs before a guest context exists. Validate its
   completed argument tree inside execute(), before any guest body observes it. */
static int wire_validate(void *ctx,size_t index,const void *input,size_t depth) {
    if(depth>=128){myl_qbe_fail(ctx,"WireLimit");return 0;}
    const QbeWireType *type=&wire_types[index];
    if(type->kind==3 || type->kind==7){
        size_t tag=0;
        if(type->kind==3){uint32_t value;memcpy(&value,input,4);tag=value;}
        else {const void *reference;memcpy(&reference,input,sizeof reference);
            while(tag<type->count && (type->children[tag]==SIZE_MAX)!=(reference==NULL))++tag;}
        if(tag>=type->count){myl_qbe_fail(ctx,"InternalError");return 0;}
        const size_t child=type->children[tag];
        return child==SIZE_MAX || wire_validate(ctx,child,(const unsigned char *)input+type->offsets[tag],depth+1);
    }
    if(type->kind!=0) for(size_t i=0;i<type->count;++i){
        const size_t child=type->children[type->kind==2?0:i],offset=type->kind==2?i*type->stride:type->offsets[i];
        if(!wire_validate(ctx,child,(const unsigned char *)input+offset,depth+1))return 0;
    }
    return wire_validate_one(ctx,index,input);
}
static int wire_read(size_t index,void *output,size_t depth) {
    if (depth>=128) return wire_bad("WireLimit");
    if (wire_cursor>=wire_count) return wire_bad("InvalidArgument");
    const QbeWireType *type=&wire_types[index];
    const MylangWireNode *node=&wire_input[wire_cursor++];
    if (!node->type || strcmp(node->type,type->name)) return wire_bad("InvalidArgument");
    if (type->kind==0) {
        if (node->children || !valid_scalar((MylangScalar){node->type,node->bits},type->name)) return wire_bad("InvalidArgument");
        memcpy(output,&node->bits,type->size);return 1;
    }
    if (type->kind==3) {
        if (node->bits>=type->count) return wire_bad("InvalidArgument");
        size_t tag=(size_t)node->bits, child=type->children[tag];
        if (node->children!=(child==SIZE_MAX ? 0u : 1u)) return wire_bad("InvalidArgument");
        uint32_t native_tag=(uint32_t)tag;memcpy(output,&native_tag,4);
        return child==SIZE_MAX || wire_read(child,(unsigned char *)output+type->offsets[tag],depth+1);
    }
    if (type->kind==7) {
        /* A niche optional has no tag word: `None` is the null reference and
           `Some` is the reference itself, read over the same word. */
        if (node->bits>=type->count) return wire_bad("InvalidArgument");
        size_t child=type->children[node->bits];
        if (node->children!=(child==SIZE_MAX ? 0u : 1u)) return wire_bad("InvalidArgument");
        memset(output,0,type->size);
        return child==SIZE_MAX || wire_read(child,output,depth+1);
    }
    if (node->bits || node->children!=type->count) return wire_bad("InvalidArgument");
    for (size_t i=0;i<type->count;++i) {
        size_t child=type->children[type->kind==2 ? 0 : i];
        size_t offset=type->kind==2 ? i*type->stride : type->offsets[i];
        if (!wire_read(child,(unsigned char *)output+offset,depth+1)) return 0;
    }
    return 1;
}
static int wire_write(size_t index,const void *input,MylangWireNode *output,size_t *count,size_t depth) {
    if (depth>=128 || *count>=100000) return wire_bad("WireLimit");
    const QbeWireType *type=&wire_types[index];
    MylangWireNode *node=&output[(*count)++];
    *node=(MylangWireNode){type->name,0,type->count};
    if (type->kind==0) {node->bits=wire_word(input,type);node->children=0;return 1;}
    if (type->kind==3) {
        uint32_t tag;memcpy(&tag,input,4);
        if (tag>=type->count) return wire_bad("InternalError");
        size_t child=type->children[tag];node->bits=tag;node->children=child==SIZE_MAX ? 0 : 1;
        return child==SIZE_MAX || wire_write(child,(const unsigned char *)input+type->offsets[tag],output,count,depth+1);
    }
    if (type->kind==7) {
        const void *reference;memcpy(&reference,input,sizeof reference);
        size_t tag=0;
        while (tag<type->count && (type->children[tag]==SIZE_MAX)!=(reference==NULL)) ++tag;
        if (tag==type->count) return wire_bad("InternalError");
        size_t child=type->children[tag];node->bits=tag;node->children=child==SIZE_MAX ? 0 : 1;
        return child==SIZE_MAX || wire_write(child,input,output,count,depth+1);
    }
    for (size_t i=0;i<type->count;++i) {
        size_t child=type->children[type->kind==2 ? 0 : i];
        size_t offset=type->kind==2 ? i*type->stride : type->offsets[i];
        if (!wire_write(child,(const unsigned char *)input+offset,output,count,depth+1)) return 0;
    }
    return 1;
}
