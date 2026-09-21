/* The copied-managed kind reads a guest list header, which the runtime
 * implementation includes through this header rather than the ABI one. */
#include "native_collections.h"
/* Copied native values and explicit domain conversions share one execution. */
typedef struct {size_t wire,decode,encode,result,ok,err,error_type;} CoCodec;
typedef struct {const char *name;size_t size,count,stride;unsigned kind;const size_t *children,*offsets;const CoCodec *codec;} CoType;
static const CoType co_types[];
static const MylangWireNode *co_input;
static size_t co_count,co_cursor,co_needed,co_result_type,co_argument_count;
static const size_t *co_parameter_types;
static void *co_arguments[QBE_CODEC_ARGUMENTS],*co_return;
static MylangWireNode *co_prepared;
/* Output entries the caller actually provided. `co_write` must never exceed it:
 * a text result is one node per scalar, so its size is the guest value's, not
 * the signature's, and the signature cannot bound it. */
static size_t co_capacity;
static const char *co_error,*co_domain;
static uint64_t co_calls,co_max_calls;
static int co_rejected;
static void *co_context;
static int co_bad(const char *code){co_error=code;return 0;}
static int co_charge(void){if(co_calls==co_max_calls)return co_bad("CodecCallLimit");++co_calls;return 1;}
static int co_method(size_t,void *,const void *,void *);
static int co_write(size_t,const void *,size_t);
static uint64_t co_word(const void *input,size_t index){
    const CoType *type=&co_types[index];
    while(type->kind==4)type=&co_types[type->children[0]];
    uint64_t bits=0;memcpy(&bits,input,type->size);
    if(*type->name=='i' && type->size<8 && (bits&(UINT64_C(1)<<(type->size*8-1))))bits|=UINT64_MAX<<(type->size*8);
    return bits;
}
static int co_read(size_t index,void *output,size_t depth){
    if(depth>=128)return co_bad("WireLimit");
    if(co_cursor>=co_count)return co_bad("InvalidArgument");
    const CoType *type=&co_types[index];const MylangWireNode *node=&co_input[co_cursor++];
    if(!node->type || strcmp(node->type,type->name))return co_bad("InvalidArgument");
    if(type->kind==0){
        if(node->children || !valid_scalar((MylangScalar){node->type,node->bits},type->name))return co_bad("InvalidArgument");
        memcpy(output,&node->bits,type->size);return 1;
    }
    if(type->kind==4){
        if(!type->codec || node->bits || node->children!=1)return co_bad("InvalidArgument");
        const CoCodec *codec=type->codec;int ok=0;
        void *wire=calloc(co_types[codec->wire].size ? co_types[codec->wire].size : 1,1);
        void *result=calloc(co_types[codec->result].size ? co_types[codec->result].size : 1,1);
        if(!wire || !result){co_bad("OutOfMemory");goto domain_done;}
        if(!co_read(codec->wire,wire,depth+1))goto domain_done;
        const char *previous=co_domain;co_domain=type->name;
        if(!co_charge() || !co_method(codec->decode,co_context,wire,result))goto domain_done;
        uint32_t tag;memcpy(&tag,result,4);
        if(tag!=codec->ok && tag!=codec->err){co_bad("InternalError");goto domain_done;}
        const void *payload=(const unsigned char *)result+co_types[codec->result].offsets[tag];
        if(tag==codec->ok){memcpy(output,payload,type->size);co_domain=previous;ok=1;}
        else{co_rejected=1;co_needed=0;if(co_write(codec->error_type,payload,0))co_bad("DomainCodecRejected");}
    domain_done:free(wire);free(result);return ok;
    }
    if(type->kind==5)return co_bad("UnsupportedArgument");
    if(type->kind==3){
        if(node->bits>=type->count)return co_bad("InvalidArgument");
        uint32_t tag=(uint32_t)node->bits;size_t child=type->children[tag];
        if(node->children!=(child==SIZE_MAX ? 0u : 1u))return co_bad("InvalidArgument");
        memcpy(output,&tag,4);return child==SIZE_MAX || co_read(child,(unsigned char *)output+type->offsets[tag],depth+1);
    }
    if(node->bits || node->children!=type->count)return co_bad("InvalidArgument");
    for(size_t i=0;i<type->count;++i){
        size_t child=type->children[type->kind==2 ? 0:i],offset=type->kind==2 ? i*type->stride:type->offsets[i];
        if(!co_read(child,(unsigned char *)output+offset,depth+1))return 0;
    }
    return 1;
}
static int co_write(size_t index,const void *input,size_t depth){
    if(depth>=128 || co_needed>=100000 || co_needed>=co_capacity)return co_bad("WireLimit");
    const CoType *type=&co_types[index];MylangWireNode *node=&co_prepared[co_needed++];
    *node=(MylangWireNode){type->name,0,type->count};
    if(type->kind==0){node->bits=co_word(input,index);node->children=0;return 1;}
    if(type->kind==5){
        /* One copied managed text: the guest value is a handle to a list whose
         * payload is `length` scalars, so the result is one node per scalar and
         * its size belongs to the value rather than to the signature. Nothing is
         * allocated here, so the handle in the caller's return slot needs no
         * root across a safepoint. */
        const myl_native_list *text=*(const myl_native_list *const *)input;
        if(!text || !text->storage)return co_bad("InvalidResult");
        if(text->length>100000-co_needed || co_needed+text->length>co_capacity)return co_bad("WireLimit");
        node->children=text->length;
        const CoType *element=&co_types[type->children[0]];
        for(size_t i=0;i<text->length;++i){
            MylangWireNode *child=&co_prepared[co_needed++];
            *child=(MylangWireNode){element->name,co_word((const unsigned char *)text->storage+i*element->size,type->children[0]),0};
        }
        return 1;
    }
    if(type->kind==4){
        if(!type->codec)return co_bad("UnsupportedSignature");
        node->children=1;const CoCodec *codec=type->codec;
        void *wire=calloc(co_types[codec->wire].size ? co_types[codec->wire].size : 1,1);
        if(!wire)return co_bad("OutOfMemory");
        const char *previous=co_domain;co_domain=type->name;
        int ok=co_charge() && co_method(codec->encode,co_context,input,wire) && co_write(codec->wire,wire,depth+1);
        if(ok)co_domain=previous;free(wire);return ok;
    }
    if(type->kind==3){
        uint32_t tag;memcpy(&tag,input,4);if(tag>=type->count)return co_bad("InternalError");
        size_t child=type->children[tag];node->bits=tag;node->children=child==SIZE_MAX ? 0:1;
        return child==SIZE_MAX || co_write(child,(const unsigned char *)input+type->offsets[tag],depth+1);
    }
    for(size_t i=0;i<type->count;++i){
        size_t child=type->children[type->kind==2 ? 0:i],offset=type->kind==2 ? i*type->stride:type->offsets[i];
        if(!co_write(child,(const unsigned char *)input+offset,depth+1))return 0;
    }
    return 1;
}
