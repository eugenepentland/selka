/* Production provider failures must release C scratch before real longjmp. */
#include "qbe_files.h"
#include "native_providers.h"
#include "native_rc_alloc.h"
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
enum { ACQUIRE_OOM, READ_OOM, READ_LENGTH, READ_EOF, COMPLETE_OOM, WRITE_OOM, ACQUIRE_INVALID, INVALID_AUTH, COMPLETE_DENIED, COMPLETE_UTF8_OOM };
typedef struct { unsigned mode, reads, writes, live, completed, released; MylQbeContext *context; } Provider;
static MylangResourceResult acquire(void *context,const uint8_t *bytes,size_t length,unsigned permissions) {
    Provider *state=context;
    assert(length>=2 && bytes[1]==':' && permissions==7);
    if (state->mode==ACQUIRE_OOM) return (MylangResourceResult){MYLANG_PROVIDER_OUT_OF_MEMORY,0};
    if (state->mode==ACQUIRE_INVALID) return (MylangResourceResult){(MylangProviderStatus)99,0};
    ++state->live;
    return (MylangResourceResult){MYLANG_PROVIDER_OK,1};
}
static MylangProviderStatus complete(void *context,uint64_t handle) {
    Provider *state=context;
    assert(handle==1 && state->live==1);
    if (state->mode==COMPLETE_OOM || state->mode==COMPLETE_UTF8_OOM) { myl_native_heap_collect(&state->context->heap); return MYLANG_PROVIDER_OUT_OF_MEMORY; }
    if (state->mode==COMPLETE_DENIED) return MYLANG_PROVIDER_DENIED;
    --state->live;++state->completed;
    return MYLANG_PROVIDER_OK;
}
static void release(void *context,uint64_t handle) {
    Provider *state=context;
    assert(handle==1 && state->live==1);
    --state->live;++state->released;
}
static MylangResourceRead read_bytes(void *context,uint64_t handle,uint8_t *bytes,size_t capacity) {
    Provider *state=context;
    assert(handle==1 && capacity);
    if (++state->reads==1) {
        bytes[0]=state->mode==COMPLETE_UTF8_OOM?255:'x';
        return (MylangResourceRead){MYLANG_PROVIDER_OK,1,state->mode==COMPLETE_OOM || state->mode==COMPLETE_UTF8_OOM};
    }
    if (state->mode==READ_LENGTH) return (MylangResourceRead){MYLANG_PROVIDER_OK,capacity+1,0};
    if (state->mode==READ_EOF) return (MylangResourceRead){MYLANG_PROVIDER_OK,1,2};
    return (MylangResourceRead){MYLANG_PROVIDER_OUT_OF_MEMORY,0,0};
}
static MylangResourceWrite write_bytes(void *context,uint64_t handle,const uint8_t *bytes,size_t length) {
    Provider *state=context;
    assert(handle==1 && length && bytes[0]=='x');
    if (++state->writes==1) return (MylangResourceWrite){MYLANG_PROVIDER_OK,1};
    return (MylangResourceWrite){MYLANG_PROVIDER_OUT_OF_MEMORY,0};
}
static const myl_native_type pointer = {.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
/* Both collectors use the same real failure implementation. Caller inputs stay
 * rooted/owned outside the helper, so any extra heap value after failure leaks. */
static void scenario(unsigned mode,int rc,int entry) {
    MylQbeContext *ctx=calloc(1,sizeof *ctx);assert(ctx);
    Provider *state=calloc(1,sizeof *state);assert(state);state->mode=mode;state->context=ctx;
    MylangNativeProviders providers={.filesystem={.context=state,.permissions=7,
        .acquire=acquire,.complete=complete,.release=release,.read=read_bytes,.write=write_bytes}};
    ctx->providers=&providers;
    myl_native_heap_init(&ctx->heap,4u<<20);
    assert(!myl_rc_enabled(&ctx->heap));
    if (rc) assert(myl_rc_storage_init(&ctx->heap)==MYL_RC_OK);
    myl_native_text *path=myl_native_text_from_utf8(&ctx->heap,(const unsigned char *)"file",4);
    assert(path);
    myl_native_root path_root, input_root;
    myl_native_root_push(&ctx->heap,&path_root,&path,&pointer);
    myl_native_bytes *input=myl_native_bytes_new(&ctx->heap,(const unsigned char *)"xxxx",4);
    assert(input);
    myl_native_root_push(&ctx->heap,&input_root,&input,&pointer);
    size_t baseline=ctx->heap.objects_live;
    uint64_t authority=myl_qbe_grant_resource(ctx,0);
    if (mode==INVALID_AUTH) authority=0;
    myl_native_resource *owner=NULL;
    if (entry && mode!=ACQUIRE_OOM && mode!=ACQUIRE_INVALID && mode!=INVALID_AUTH) assert(myl_qbe_resource_new(ctx,authority,0,(const unsigned char *)"r:file",6,&owner)==0);
    jmp_buf unwind;
    ctx->unwind=&unwind;
    if (!setjmp(unwind)) {
        uint64_t result=0;
        if (entry==1) myl_qbe_file_method(ctx,owner,mode==WRITE_OOM?MYL_FILE_WRITE:MYL_FILE_READLINE,-1,input,&result);
        else if (entry==0) myl_qbe_file_access(ctx,authority,mode==WRITE_OOM?MYL_FILE_WRITE_FILE:mode==COMPLETE_UTF8_OOM?(MYL_FILE_READ_TEXT | (1u<<16)):MYL_FILE_READ_FILE,path,input,&result);
        else if (!owner) myl_qbe_resource_new(ctx,authority,0,(const unsigned char *)"r:file",6,&owner);
        else if (mode==COMPLETE_OOM) myl_qbe_resource_complete(ctx,owner);
        else if (mode==WRITE_OOM) {
            size_t written=0;
            myl_qbe_resource_write(ctx,owner,(const unsigned char *)"xx",2,&written);
            assert(written==1);
            myl_qbe_resource_write(ctx,owner,(const unsigned char *)"xx",2,&written);
        } else {
            unsigned char bytes[4]={0};size_t length=0;int eof=0;
            myl_qbe_resource_read(ctx,owner,bytes,sizeof bytes,&length,&eof);
            assert(length==1 && bytes[0]=='x');
            myl_qbe_resource_read(ctx,owner,bytes,sizeof bytes,&length,&eof);
        }
        assert(0 && "provider fatal status must leave through real longjmp");
    }
    ctx->unwind=NULL;
    assert(ctx->trap && !strcmp(ctx->trap,mode==INVALID_AUTH?"InvalidCapability":(mode==READ_LENGTH || mode==READ_EOF || mode==ACQUIRE_INVALID)?"InvalidProvider":"OutOfMemory"));
    if (entry && owner) { assert(state->live==1); owner->drop(owner); }
    assert(!state->live && !ctx->resource_live[0]);
    if (mode==COMPLETE_OOM || mode==COMPLETE_UTF8_OOM) assert(state->released==1 && !state->completed);
    if (!entry && (mode==READ_OOM || mode==READ_LENGTH || mode==READ_EOF || mode==WRITE_OOM)) assert(state->released==1 && !state->completed);
    if (!rc) myl_native_heap_collect(&ctx->heap);
    assert(ctx->heap.objects_live==baseline);
    assert(ctx->heap.roots==&input_root);
    myl_native_root_pop(&ctx->heap,&input_root);
    myl_native_root_pop(&ctx->heap,&path_root);
    if (rc) { myl_rc_owner_release(&ctx->heap,input); myl_rc_owner_release(&ctx->heap,path); }
    if (ctx->cleanup) ctx->cleanup(ctx);
    myl_native_heap_destroy(&ctx->heap);
    assert(!ctx->heap.bytes);
    free(state);free(ctx);
}
static void completion_retry(int rc) {
    MylQbeContext *ctx=calloc(1,sizeof *ctx);assert(ctx);
    Provider state={.mode=COMPLETE_DENIED};
    MylangNativeProviders providers={.filesystem={.context=&state,.permissions=7,
        .acquire=acquire,.complete=complete,.release=release,.read=read_bytes,.write=write_bytes}};
    ctx->providers=&providers;
    myl_native_heap_init(&ctx->heap,4u<<20);
    if (rc) assert(myl_rc_storage_init(&ctx->heap)==MYL_RC_OK);
    uint64_t authority=myl_qbe_grant_resource(ctx,0);
    myl_native_resource *owner=NULL;
    assert(!myl_qbe_resource_new(ctx,authority,0,(const unsigned char *)"r:file",6,&owner));
    assert(myl_qbe_resource_complete(ctx,owner)==MYLANG_PROVIDER_DENIED);
    assert(!ctx->trap && state.live==1 && ctx->resource_live[0]==1);
    state.mode=READ_OOM;
    assert(!myl_qbe_resource_complete(ctx,owner));
    assert(!state.live && state.completed==1 && !state.released && !ctx->resource_live[0]);
    ctx->cleanup(ctx);
    myl_native_heap_destroy(&ctx->heap);
    assert(!ctx->heap.bytes);
    free(ctx);
}
int myl_native_file_cleanup_verify(void) {
    for (int rc=0;rc!=2;++rc) {
        for (unsigned mode=0;mode!=8;++mode) { scenario(mode,rc,0); scenario(mode,rc,2); }
        scenario(READ_OOM,rc,1);
        scenario(WRITE_OOM,rc,1);
        completion_retry(rc);
        scenario(COMPLETE_UTF8_OOM,rc,0);
    }
    return 40;
}
#ifndef MYL_FILE_CLEANUP_LIBRARY
int main(void) { assert(myl_native_file_cleanup_verify()==40); puts("native file cleanup: 40 passed"); return 0; }
#endif
