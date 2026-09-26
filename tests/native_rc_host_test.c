/* The host bridge publishes owned bytes and tracks scratch across real traps. */
#include "native_rc_alloc.h"
#include <assert.h>
#include <setjmp.h>
#include "qbe_host_runtime.c"
static const size_t array_child[]={0},parameters[]={1};
static const QbeHostType qbe_host_types[]={
    {.name="i64",.size=8,.kind=1,.bits=64,.is_signed=1},
    {.name="i64[9]",.size=72,.count=9,.stride=8,.kind=3,.children=array_child},
};
static const QbeHostDeclaration qbe_host_declarations[]={
    {.name="host::sum",.parameters=parameters,.count=1,.result=0}
};
static const size_t qbe_host_declaration_count=1;
static const void *last_nodes;
static unsigned reject;
static const char *invoke(void *ctx,MylangHostCall *call){
    (void)ctx;last_nodes=call->arguments;
    assert(call->argument_nodes==10 && call->arguments[1].bits==7);
    if(reject)return "HostFailure";
    call->output[0]=(MylangHostNode){"i64",63,0};call->output_nodes=1;return NULL;
}
static void copied_bytes(void){
    MylQbeContext ctx={0};myl_native_heap_init(&ctx.heap,1u<<20);
    assert(myl_rc_storage_init(&ctx.heap)==MYL_RC_OK);
    QbeHostState state={.payload_limit=100};
    unsigned char octets[]={10,20,30};
    MylangHostPackedCall call={.output={octets,3},.output_written=3};
    myl_native_bytes *out=NULL;
    qbe_host_publish_payload(&ctx,&state,&call,&out);
    assert(out && ((myl_rc_object *)out-1)->owners==1 && out->length==3);
    octets[1]=99;assert(((unsigned char *)out->storage)[1]==20);
    myl_rc_owner_release(&ctx.heap,out);out=NULL;
    ctx.trap="R_HOST_FAILURE";qbe_host_publish_payload(&ctx,&state,&call,&out);
    assert(!out && !ctx.heap.objects_live);
    ctx.trap=NULL;call.output_written=2;qbe_host_publish_payload(&ctx,&state,&call,&out);
    assert(!out && !ctx.heap.objects_live && !strcmp(ctx.trap,"R_HOST_CONTRACT"));
    myl_native_heap_destroy(&ctx.heap);assert(!ctx.heap.bytes);
}
static void scratch_survives_trap(void){
    static const char *const types[]={"i64[9]"};
    const MylangHostBinding binding={.name="host::sum",.parameters=types,.parameter_count=1,.result="i64",.invoke=invoke};
    MylangNativeProviders providers={.host={.bindings=&binding,.count=1}};
    MylQbeContext *ctx=calloc(1,sizeof *ctx);assert(ctx);ctx->providers=&providers;
    myl_native_heap_init(&ctx->heap,1u<<20);assert(myl_rc_storage_init(&ctx->heap)==MYL_RC_OK);
    int64_t numbers[9]={7,7,7,7,7,7,7,7,7},out=0;
    const void *arguments[]={numbers};reject=0;
    qbe_host_invoke(ctx,0,arguments,&out);
    assert(out==63 && !ctx->frame_allocations && !ctx->trap && !ctx->heap.objects_live);
    reject=1;jmp_buf unwind;ctx->unwind=&unwind;
    if(!setjmp(unwind)){qbe_host_invoke(ctx,0,arguments,&out);assert(0);}
    assert(ctx->trap && !strcmp(ctx->trap,"R_HOST_FAILURE") && ctx->frame_allocations);
    ctx->unwind=NULL;
    myl_qbe_frame_release(ctx,(void *)last_nodes);
    assert(!ctx->frame_allocations && !ctx->heap.objects_live);
    free(ctx->host_state);myl_native_heap_destroy(&ctx->heap);assert(!ctx->heap.bytes);free(ctx);
}
int myl_rc_host_verify(void){copied_bytes();scratch_survives_trap();return 4;}
#ifndef MYL_RC_HOST_LIBRARY
int main(void){return myl_rc_host_verify()==4?0:1;}
#endif
