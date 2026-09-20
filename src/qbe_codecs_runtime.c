/* Copied native values and explicit domain conversions share one execution. */
#include "native_text.h"
/* `myl_qbe_heap` returns a pointer. Without this declaration the call is an
   implicit `int` and the heap address is truncated to 32 bits, so every text
   argument or result faulted on a wild pointer; `qbe_bytes.h` includes the same
   header for the same reason. */
#include "qbe_runtime.h"
typedef struct {size_t wire,decode,encode,result,ok,err,error_type;} CoCodec;
typedef struct {const char *name;size_t size,count,stride;unsigned kind;const size_t *children,*offsets;const CoCodec *codec;} CoType;
static const CoType co_types[];
static const MylangWireNode *co_input;
static size_t co_count,co_cursor,co_needed,co_result_type,co_argument_count;
static const size_t *co_parameter_types;
static void *co_arguments[QBE_CODEC_ARGUMENTS],*co_return;
static MylangWireNode *co_prepared;
static const char *co_error,*co_domain;
static uint64_t co_calls,co_max_calls;
static int co_rejected;
static void *co_context;
/* The caller's output capacity, compared only by the epilogue. The staging
   path is bounded by the global node cap instead, so a result that does not fit
   still reports its required `node_count` (native_embed.h: OutputTooSmall)
   rather than a bare WireLimit from the middle of the write. */
static size_t co_capacity;
/* Every text the adapter holds across guest code is rooted: reading an argument
   allocates in the managed heap, and the guest call that follows can collect.
   Roots point at static slots, because a root records the address of the value,
   not its bytes. */
static const myl_native_type co_pointer_type={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static void *co_text_values[QBE_CODEC_ARGUMENTS];
static myl_native_root co_text_roots[QBE_CODEC_ARGUMENTS];
static size_t co_root_count;
static int co_bad(const char *code){co_error=code;return 0;}
static int co_charge(void){if(co_calls==co_max_calls)return co_bad("CodecCallLimit");++co_calls;return 1;}
static int co_method(size_t,void *,const void *,void *);
static int co_write(size_t,const void *,size_t);
static int co_root(void *value){
    if(co_root_count==QBE_CODEC_ARGUMENTS)return 0;
    co_text_values[co_root_count]=value;
    myl_native_root_push(myl_qbe_heap(co_context),&co_text_roots[co_root_count],&co_text_values[co_root_count],&co_pointer_type);
    ++co_root_count;return 1;
}
static void co_unroot(void){
    while(co_root_count){--co_root_count;myl_native_root_pop(myl_qbe_heap(co_context),&co_text_roots[co_root_count]);}
}
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
    if(type->kind==5){
        /* One node per Unicode scalar, decoded into fresh guest-owned storage.
           The input node count already bounds the request, so the decoded size
           is bounded by it rather than by anything the request claims. */
        if(node->bits || node->children>co_count-co_cursor)return co_bad("InvalidArgument");
        const CoType *element=&co_types[type->children[0]];
        if(element->kind || element->size!=sizeof(uint32_t))return co_bad("InternalError");
        myl_native_text *text=myl_native_text_new(myl_qbe_heap(co_context),node->children);
        if(!text)return co_bad("OutOfMemory");
        if(!co_root(text))return co_bad("OutOfMemory");
        myl_native_list *list=(myl_native_list *)text;
        list->length=node->children;
        for(size_t i=0;i<node->children;++i){
            const MylangWireNode *child=&co_input[co_cursor++];
            uint32_t scalar;
            if(!child->type || strcmp(child->type,element->name) || child->children || child->bits>UINT32_MAX)return co_bad("InvalidArgument");
            scalar=(uint32_t)child->bits;
            if(!myl_native_list_set(list,i,&scalar))return co_bad("InternalError");
        }
        memcpy(output,&text,sizeof text);return 1;
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
    if(depth>=128 || co_needed>=100000)return co_bad("WireLimit");
    const CoType *type=&co_types[index];MylangWireNode *node=&co_prepared[co_needed++];
    *node=(MylangWireNode){type->name,0,type->count};
    if(type->kind==0){node->bits=co_word(input,index);node->children=0;return 1;}
    if(type->kind==5){
        const myl_native_text *text=*(const myl_native_text *const *)input;
        if(!text)return co_bad("InternalError");
        const myl_native_list *list=(const myl_native_list *)text;
        const CoType *element=&co_types[type->children[0]];
        if(element->kind || element->size!=sizeof(uint32_t))return co_bad("InternalError");
        /* One node per scalar of the guest text, bounded by the staging array
           alone: the caller's capacity is deliberately not consulted here, so a
           result that does not fit is still measured and the epilogue reports
           OutputTooSmall with the required count instead of WireLimit. */
        if(list->length>100000-co_needed)return co_bad("WireLimit");
        node->children=list->length;
        for(size_t i=0;i<list->length;++i){
            uint32_t scalar;
            if(!myl_native_list_get(list,i,&scalar))return co_bad("InternalError");
            co_prepared[co_needed++]=(MylangWireNode){element->name,scalar,0};
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
