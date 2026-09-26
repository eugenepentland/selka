/* Exercise the actual copied-codec runtime with production RC storage. */
#include "native_providers.h"
#include "native_embed.h"
#include "native_rc_alloc.h"
#include <assert.h>
#include <setjmp.h>
#include <stdlib.h>
#include <string.h>
#define QBE_CODEC_ARGUMENTS 1
#define QBE_CODEC_DEPTH 128
#define QBE_CODEC_ROOTS 1025
static int valid_scalar(MylangScalar value,const char *type){
    return value.type && !strcmp(value.type,type) && (strcmp(type,"u8") || value.bits<256);
}
#include "qbe_codecs_runtime.c"
enum { I64, U32, U8, TEXT, LIST, DICT, RECORD, BOX, DOMAIN, RESULT, DOMAIN_LIST };
typedef struct { myl_native_text *first,*second; } Pair;
typedef struct { uint32_t tag,padding; myl_native_text *payload; } Result;
static const myl_native_type integer={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type scalar={.size=4,.alignment=4,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type byte={.size=1,.alignment=1,.kind=MYL_NATIVE_PLAIN};
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=2};
static const myl_native_field pair_fields[]={{0,&pointer,0},{sizeof(void *),&pointer,0}};
static const myl_native_type pair_type={.size=sizeof(Pair),.alignment=_Alignof(Pair),.kind=MYL_NATIVE_RECORD,.fields=pair_fields,.field_count=2};
static const myl_native_type box_type={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER,.collection_kind=5,.element=&pair_type};
static const myl_native_field result_fields[]={{offsetof(Result,payload),&pointer,0},{offsetof(Result,payload),&pointer,1}};
static const myl_native_type result_type={.size=sizeof(Result),.alignment=_Alignof(Result),.kind=MYL_NATIVE_VARIANT,.fields=result_fields,.field_count=2};
static const myl_native_type *const co_native_types[]={&integer,&scalar,&byte,&pointer,&pointer,&pointer,&pair_type,&box_type,&pointer,&result_type,&pointer};
static const size_t text_children[]={U32},list_children[]={TEXT},dict_children[]={TEXT,TEXT},pair_children[]={TEXT,TEXT},pair_offsets[]={0,sizeof(void *)},box_children[]={RECORD},domain_children[]={TEXT},result_children[]={DOMAIN,TEXT},result_offsets[]={offsetof(Result,payload),offsetof(Result,payload)},domain_list_children[]={DOMAIN};
static const CoCodec codec={TEXT,0,1,RESULT,0,1,TEXT};
static const CoType co_types[]={
    {"i64",8,0,0,0,NULL,NULL,NULL},
    {"u32",4,0,0,0,NULL,NULL,NULL},
    {"u8",1,0,0,0,NULL,NULL,NULL},
    {"str",sizeof(void *),0,0,5,text_children,NULL,NULL},
    {"list[str]",sizeof(void *),0,0,6,list_children,NULL,NULL},
    {"dict[str,str]",sizeof(void *),2,0,9,dict_children,NULL,NULL},
    {"Pair",sizeof(Pair),2,0,1,pair_children,pair_offsets,NULL},
    {"Box",sizeof(void *),0,0,10,box_children,NULL,NULL},
    {"Domain",sizeof(void *),1,0,4,domain_children,NULL,&codec},
    {"Result",sizeof(Result),2,0,3,result_children,result_offsets,NULL},
    {"list[Domain]",sizeof(void *),0,0,6,domain_list_children,NULL,NULL},
};
static const myl_rc_shape plain8={.size=8,.kind=MYL_RC_SHAPE_NONE},plain4={.size=4,.kind=MYL_RC_SHAPE_NONE},plain1={.size=1,.kind=MYL_RC_SHAPE_NONE},pointer_shape={.size=sizeof(void *),.kind=MYL_RC_SHAPE_POINTER};
static const myl_rc_field pair_edges[]={{0,&pointer_shape,0},{sizeof(void *),&pointer_shape,0}},result_edges[]={{offsetof(Result,payload),&pointer_shape,0},{offsetof(Result,payload),&pointer_shape,1}};
static const myl_rc_shape pair_shape={.size=sizeof(Pair),.kind=MYL_RC_SHAPE_RECORD,.as.record={pair_edges,2}},result_shape={.size=sizeof(Result),.kind=MYL_RC_SHAPE_VARIANT,.as.variant={result_edges,2,0}};
static const myl_rc_shape *const shapes[]={&plain8,&plain4,&plain1,&pointer_shape,&pair_shape,&result_shape};
static const myl_rc_descriptor descriptors[]={
    {.type=&integer,.shape=&plain8},{.type=&scalar,.shape=&plain4},{.type=&byte,.shape=&plain1},{.type=&pointer,.shape=&pointer_shape},
    {.type=&pair_type,.shape=&pair_shape},{.type=&box_type,.shape=&pointer_shape},{.type=&result_type,.shape=&result_shape}
};
static const myl_rc_module module={MYL_RC_ABI_VERSION,shapes,sizeof shapes/sizeof *shapes,descriptors,sizeof descriptors/sizeof *descriptors};
static unsigned mode;
static int co_method(size_t function,void *ctx,const void *input,void *output){
    myl_native_text *source=*(myl_native_text *const *)input;
    myl_native_text *copy=myl_native_text_from_utf8(myl_qbe_heap(ctx),myl_native_text_storage(source),source->bytes);
    if(!copy)return co_bad("OutOfMemory");
    if(function==0){Result *result=output;result->tag=mode==1;result->payload=copy;}
    else memcpy(output,&copy,sizeof copy);
    if(mode==2)myl_qbe_fail(ctx,"R_CODEC_TEST");
    return 1;
}
static int co_validate_one(void *ctx,size_t type,const void *value){
    (void)ctx;(void)value;
    return type!=DOMAIN || mode!=3;
}
static MylQbeContext *begin(size_t type,const MylangWireNode *nodes,size_t count,int rc){
    MylQbeContext *ctx=calloc(1,sizeof *ctx);assert(ctx);
    myl_native_heap_init(&ctx->heap,64u<<20);
    if(rc){assert(myl_rc_storage_init(&ctx->heap)==MYL_RC_OK);assert(myl_rc_module_register(&ctx->heap,&module)==MYL_RC_OK);}
    co_context=ctx;ctx->adapter_cleanup=co_cleanup;
    co_input=nodes;co_count=count;co_cursor=0;co_needed=0;co_capacity=100000;co_error=NULL;co_domain=NULL;co_rejected=0;co_calls=0;co_max_calls=100;
    co_result_type=I64;co_argument_count=1;co_injected=NULL;co_root_count=0;co_return=NULL;
    static size_t parameter;parameter=type;co_parameter_types=&parameter;
    co_arguments[0]=calloc(1,co_types[type].size);co_prepared=calloc(100000,sizeof *co_prepared);
    assert(co_arguments[0] && co_prepared && !co_temporaries);mode=0;
    return ctx;
}
static void finish(MylQbeContext *ctx){
    co_cleanup(ctx);
    assert(!ctx->adapter_cleanup && !co_temporaries && !co_root_count);
    if(myl_rc_enabled(&ctx->heap))assert(!ctx->heap.objects_live);
    else{myl_native_heap_collect(&ctx->heap);assert(!ctx->heap.objects_live);}
    myl_native_heap_destroy(&ctx->heap);assert(!ctx->heap.bytes);
    free(co_arguments[0]);co_arguments[0]=NULL;free(co_prepared);co_prepared=NULL;free(ctx);
}
static void lists_and_boxes(void){
    static const MylangWireNode list[]={{"list[str]",0,2},{"str",0,1},{"u32",'a',0},{"str",0,1},{"u32",'b',0}};
    MylQbeContext *ctx=begin(LIST,list,sizeof list/sizeof *list,1);
    assert(co_read(LIST,co_arguments[0],0));
    myl_native_list *values=*(myl_native_list **)co_arguments[0];myl_native_text *text=NULL;
    assert(values->length==2 && myl_native_list_get(values,0,&text));
    assert(((myl_rc_object *)text-1)->owners==1);
    assert(co_write(LIST,co_arguments[0],0) && co_needed==5);
    finish(ctx);
    static const MylangWireNode pair[]={{"Pair",0,2},{"str",0,1},{"u32",'a',0},{"str",0,1},{"u32",'b',0}};
    ctx=begin(BOX,pair,sizeof pair/sizeof *pair,1);
    assert(co_read(BOX,co_arguments[0],0));
    assert(co_write(BOX,co_arguments[0],0) && co_needed==5);
    finish(ctx);
}
static void partial_and_duplicate(void){
    static const MylangWireNode partial[]={{"Pair",0,2},{"str",0,1},{"u32",'a',0},{"i64",0,0}};
    MylQbeContext *ctx=begin(RECORD,partial,sizeof partial/sizeof *partial,1);
    assert(!co_read(RECORD,co_arguments[0],0) && !strcmp(co_error,"InvalidArgument"));
    assert(!((Pair *)co_arguments[0])->first && !ctx->heap.objects_live);
    finish(ctx);
    static const MylangWireNode duplicate[]={{"dict[str,str]",0,2},{"str",0,1},{"u32",'a',0},{"str",0,1},{"u32",'b',0},{"str",0,1},{"u32",'a',0},{"str",0,1},{"u32",'c',0}};
    ctx=begin(DICT,duplicate,sizeof duplicate/sizeof *duplicate,1);
    assert(!co_read(DICT,co_arguments[0],0) && !strcmp(co_error,"InvalidArgument"));
    assert(!*(void **)co_arguments[0] && !ctx->heap.objects_live);
    finish(ctx);
}
static const MylangWireNode domain_nodes[]={{"Domain",0,1},{"str",0,1},{"u32",'z',0}};
static void domain_ownership(void){
    MylQbeContext *ctx=begin(DOMAIN,domain_nodes,3,1);
    assert(co_read(DOMAIN,co_arguments[0],0));
    size_t live=ctx->heap.objects_live;
    assert(co_write(DOMAIN,co_arguments[0],0) && co_needed==3 && ctx->heap.objects_live==live);
    finish(ctx);
    ctx=begin(DOMAIN,domain_nodes,3,1);mode=1;
    assert(!co_read(DOMAIN,co_arguments[0],0) && co_rejected && !strcmp(co_error,"DomainCodecRejected"));
    assert(co_needed==2 && !ctx->heap.objects_live);finish(ctx);
    ctx=begin(DOMAIN,domain_nodes,3,1);mode=3;
    assert(!co_read(DOMAIN,co_arguments[0],0) && !ctx->heap.objects_live);finish(ctx);
}
static void callback_trap_cleanup(void){
    static const MylangWireNode nested[]={{"list[Domain]",0,1},{"Domain",0,1},{"str",0,1},{"u32",'z',0}};
    MylQbeContext *ctx=begin(DOMAIN_LIST,nested,4,1);mode=2;
    jmp_buf unwind;ctx->unwind=&unwind;
    if(!setjmp(unwind)){(void)co_read(DOMAIN_LIST,co_arguments[0],0);assert(0);}
    assert(ctx->trap && !strcmp(ctx->trap,"R_CODEC_TEST") && co_temporaries && ctx->heap.objects_live);
    ctx->unwind=NULL;finish(ctx);
    ctx=begin(DOMAIN,domain_nodes,3,1);
    assert(co_read(DOMAIN,co_arguments[0],0));mode=2;ctx->unwind=&unwind;
    if(!setjmp(unwind)){(void)co_write(DOMAIN,co_arguments[0],0);assert(0);}
    assert(co_temporaries && ctx->trap);ctx->unwind=NULL;finish(ctx);
}
static void allocation_and_gc(void){
    static const MylangWireNode list[]={{"list[str]",0,1},{"str",0,1},{"u32",'a',0}};
    MylQbeContext *ctx=begin(LIST,list,3,1);ctx->heap.limit=ctx->heap.bytes;
    assert(!co_read(LIST,co_arguments[0],0) && !strcmp(co_error,"OutOfMemory"));finish(ctx);
    ctx=begin(DOMAIN,domain_nodes,3,0);ctx->heap.stress=1;
    assert(co_read(DOMAIN,co_arguments[0],0));
    assert(co_write(DOMAIN,co_arguments[0],0) && co_needed==3);finish(ctx);
}
int myl_rc_codecs_verify(void){
    lists_and_boxes();partial_and_duplicate();domain_ownership();callback_trap_cleanup();allocation_and_gc();return 11;
}
#ifndef MYL_RC_CODECS_LIBRARY
int main(void){return myl_rc_codecs_verify()==11?0:1;}
#endif
