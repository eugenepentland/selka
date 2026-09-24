#include "qbe_runtime.h"
#include "native_providers.h"
#include <stdlib.h>
#include <string.h>
typedef struct Resource {
    myl_native_resource base;
    MylQbeContext *context;
    struct Resource *previous,*next;
    uint64_t handle;
    unsigned kind,permissions;
    /* The provider that acquired this handle: the host's, or a stand-in's. */
    const MylangResourceProvider *provider;
} Resource;
/* One derived-capability scope. A `fs.dir(path)` entry is the joined prefix a
   derived filesystem resolves under; a `net.host(name)` entry is the single
   endpoint string a narrowed Network may acquire. Entries own their bytes until
   the execution context is destroyed. The sentinel carries a 1-based scope index
   so scope 0 keeps the historical grant/restrict encoding. */
typedef struct { char *prefix; size_t length; } DirScope;
#define MYL_QBE_RESOURCE_SCOPES 64
/* An authority encodes `stand_in*2048 + scope*16 + kind*8 + permissions`,
   negated below -16. `scope` runs 0..64; `stand_in` is 0 for a host-granted
   capability and a 1-based stand-in registry index otherwise, so a derived
   capability (`fs.dir`, `read_only`, `net.host`) keeps its stand-in index and
   a stand-in can never be turned into a host-granted authority. */
#define MYL_QBE_RESOURCE_STAND_IN_UNIT 2048
#define MYL_QBE_RESOURCE_SCOPE_MAX ((int64_t)MYL_QBE_STAND_IN_LIMIT*MYL_QBE_RESOURCE_STAND_IN_UNIT + MYL_QBE_RESOURCE_SCOPES*16 + 15)
static uint64_t encode(unsigned stand_in,uint64_t scope,unsigned kind,unsigned permissions) {
    int64_t encoded=(int64_t)stand_in*MYL_QBE_RESOURCE_STAND_IN_UNIT+(int64_t)scope*16+kind*8+permissions;
    return (uint64_t)(INT64_C(-16)-encoded);
}
static const MylangResourceProvider empty={0};
static const MylangResourceProvider *provider(MylQbeContext *ctx,unsigned kind) {
    (void)mylang_host_charge;
    if (!ctx->providers) return &empty;
    return kind ? &ctx->providers->network:&ctx->providers->filesystem;
}
static int status(MylQbeContext *ctx,MylangProviderStatus value) {
    if (value==MYLANG_PROVIDER_OUT_OF_MEMORY) myl_qbe_fail_allocation(ctx);
    else if (value<MYLANG_PROVIDER_OK || value>MYLANG_PROVIDER_FAILED) myl_qbe_fail(ctx,"InvalidProvider");
    return myl_qbe_failed(ctx) ? -1:(int)value;
}
static void unlink_resource(Resource *resource) {
    MylQbeContext *ctx=resource->context;
    if (resource->previous) resource->previous->next=resource->next;
    if (resource->next) resource->next->previous=resource->previous;
    else ctx->resource_tails[resource->kind]=resource->previous;
    ctx->resource_live[resource->kind]--;
}
static void drop(myl_native_resource *value) {
    Resource *resource=(Resource *)value;
    const MylangResourceProvider *p=resource->provider;
    p->release(p->context,resource->handle);
    unlink_resource(resource);
    free(resource);
}
static void cleanup(void *context) {
    MylQbeContext *ctx=context;
    for (unsigned kind=2;kind;kind--) while (ctx->resource_tails[kind-1]) drop(ctx->resource_tails[kind-1]);
    DirScope *scopes=ctx->resource_scopes;
    for (size_t i=0;i<ctx->resource_scope_count;++i) free(scopes[i].prefix);
    free(scopes);
    ctx->resource_scopes=NULL;ctx->resource_scope_count=0;ctx->resource_scope_capacity=0;
}
uint64_t myl_qbe_grant_resource(void *context,unsigned kind) {
    MylQbeContext *ctx=context;
    if (kind>1) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    const MylangResourceProvider *p=provider(ctx,kind);
    if (p->permissions & ~7u) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    if (!p->acquire || !p->complete || !p->release) { myl_qbe_fail(ctx,"CapabilityUnavailable");return 0; }
    return (uint64_t)(INT64_C(-16)-(int64_t)(kind*8+p->permissions));
}
uint64_t myl_qbe_grant_resource_checked(void *context,unsigned kind,const char *flag) {
    MylQbeContext *ctx=context;
    if (kind>1) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    const MylangResourceProvider *p=provider(ctx,kind);
    if (p->permissions & ~7u) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    if (!p->acquire || !p->complete || !p->release) { myl_qbe_fail_missing_capability(ctx,flag);return 0; }
    return (uint64_t)(INT64_C(-16)-(int64_t)(kind*8+p->permissions));
}
static int authority(MylQbeContext *ctx,uint64_t bits,unsigned *kind,unsigned *permissions,unsigned *scope,unsigned *stand_in) {
    int64_t value;memcpy(&value,&bits,8);
    if (value > -16 || value < -16 - MYL_QBE_RESOURCE_SCOPE_MAX) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    uint64_t encoded=(uint64_t)(-16-value);
    *permissions=encoded&7;*kind=(encoded>>3)&1;*scope=(unsigned)((encoded%MYL_QBE_RESOURCE_STAND_IN_UNIT)>>4);
    *stand_in=(unsigned)(encoded/MYL_QBE_RESOURCE_STAND_IN_UNIT);
    if (*scope>MYL_QBE_RESOURCE_SCOPES) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    return 1;
}
/* Whether a relative path stays inside a scoped root, mirroring scopedPath. An
   empty path names the directory itself and only metadata/listing accept it. */
static int scoped_relative(const unsigned char *path,size_t length,unsigned char mode) {
    if (!length) return mode=='m'||mode=='l';
    for (size_t i=0;i<length;++i) if (path[i]=='\\'||path[i]==0) return 0;
    size_t start=0;
    for (size_t i=0;i<=length;++i) {
        if (i!=length&&path[i]!='/') continue;
        size_t part=i-start;
        if (!part) return 0;
        if (part==1&&path[start]=='.') return 0;
        if (part==2&&path[start]=='.'&&path[start+1]=='.') return 0;
        start=i+1;
    }
    return 1;
}
/* A `dir(path)` segment is a scoped relative path; empty names the receiver. */
static int dir_segment(const unsigned char *path,size_t length) {
    return !length||scoped_relative(path,length,'m');
}
static DirScope *scope_append(MylQbeContext *ctx) {
    if (ctx->resource_scope_count==ctx->resource_scope_capacity) {
        size_t grown=ctx->resource_scope_capacity?ctx->resource_scope_capacity*2:8;
        if (grown>MYL_QBE_RESOURCE_SCOPES) grown=MYL_QBE_RESOURCE_SCOPES;
        DirScope *items=realloc(ctx->resource_scopes,grown*sizeof *items);
        if (!items) return NULL;
        ctx->resource_scopes=items;ctx->resource_scope_capacity=grown;
    }
    return &((DirScope *)ctx->resource_scopes)[ctx->resource_scope_count];
}
/* Record `path` under the receiver's scope and return the indexed sentinel. It
   performs no I/O; the prefix is joined when a resource is acquired. */
uint64_t myl_qbe_dir_resource(void *context,uint64_t bits,const unsigned char *path,size_t length) {
    MylQbeContext *ctx=context;
    unsigned kind,permissions,parent,stand_in;
    if (!authority(ctx,bits,&kind,&permissions,&parent,&stand_in)) return 0;
    if (kind!=0) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    if (length>4096 || !dir_segment(path,length)) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    if (parent>ctx->resource_scope_count || ctx->resource_scope_count>=MYL_QBE_RESOURCE_SCOPES) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    const char *base=NULL;size_t base_length=0;
    if (parent) { DirScope *scopes=ctx->resource_scopes;base=scopes[parent-1].prefix;base_length=scopes[parent-1].length; }
    size_t total=base_length+length+(base_length&&length?1:0);
    char *prefix=malloc(total+1);
    if (!prefix) { myl_qbe_fail_allocation(ctx);return 0; }
    if (base_length) memcpy(prefix,base,base_length);
    if (base_length&&length) prefix[base_length]='/';
    if (length) memcpy(prefix+base_length+(base_length?1:0),path,length);
    prefix[total]=0;
    DirScope *entry=scope_append(ctx);
    if (!entry) { free(prefix);myl_qbe_fail_allocation(ctx);return 0; }
    entry->prefix=prefix;entry->length=total;
    ctx->resource_scope_count++;
    ctx->cleanup=cleanup;
    return encode(stand_in,ctx->resource_scope_count,kind,permissions);
}
/* Record `name` as the only endpoint a narrowed Network may acquire and return
   the indexed sentinel. It performs no I/O. Re-narrowing a scope is idempotent
   for the same endpoint and otherwise traps, so a derived capability can never
   widen. */
uint64_t myl_qbe_host_resource(void *context,uint64_t bits,const unsigned char *name,size_t length) {
    MylQbeContext *ctx=context;
    unsigned kind,permissions,parent,stand_in;
    if (!authority(ctx,bits,&kind,&permissions,&parent,&stand_in)) return 0;
    if (kind!=1) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    if (!length || length>4096 || memchr(name,0,length)) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    if (parent>ctx->resource_scope_count || ctx->resource_scope_count>=MYL_QBE_RESOURCE_SCOPES) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    if (parent) {
        DirScope *scopes=ctx->resource_scopes;
        if (scopes[parent-1].length!=length || memcmp(scopes[parent-1].prefix,name,length)) { myl_qbe_fail(ctx,"InvalidCapability");return 0; }
    }
    char *endpoint=malloc(length+1);
    if (!endpoint) { myl_qbe_fail_allocation(ctx);return 0; }
    memcpy(endpoint,name,length);endpoint[length]=0;
    DirScope *entry=scope_append(ctx);
    if (!entry) { free(endpoint);myl_qbe_fail_allocation(ctx);return 0; }
    entry->prefix=endpoint;entry->length=length;
    ctx->resource_scope_count++;
    ctx->cleanup=cleanup;
    return encode(stand_in,ctx->resource_scope_count,kind,permissions);
}
uint64_t myl_qbe_restrict_resource(void *context,uint64_t bits,unsigned mask) {
    unsigned kind,permissions,scope,stand_in;
    if (!authority(context,bits,&kind,&permissions,&scope,&stand_in)) return 0;
    return encode(stand_in,scope,kind,permissions&mask);
}
int myl_qbe_resource_new(void *context,uint64_t bits,unsigned kind,const unsigned char *request,size_t length,myl_native_resource **output) {
    MylQbeContext *ctx=context;
    unsigned selected,permissions,scope,stand_in;
    *output=NULL;
    if (!authority(ctx,bits,&selected,&permissions,&scope,&stand_in)) return -1;
    if (selected!=kind) { myl_qbe_fail(ctx,"InvalidCapability");return -1; }
    if (scope>ctx->resource_scope_count) { myl_qbe_fail(ctx,"InvalidCapability");return -1; }
    /* A stand-in answers from its own registry entry and never from the host
       providers; a stand-in Network refuses every request. */
    const MylangResourceProvider *p=provider(ctx,kind);
    if (stand_in) {
        p=myl_qbe_stand_in_provider(ctx,stand_in-1,kind);
        if (!p) { myl_qbe_fail(ctx,"InvalidCapability");return -1; }
        if (kind==1) return MYL_QBE_STAND_IN_DENIED;
    }
    /* A scoped filesystem serves only relative requests inside its root; reject
       escapes before opening, even when a direct provider root would follow them. */
    if (scope && kind==0 && (length<2 || request[1]!=':' || !scoped_relative(request+2,length-2,request[0]))) return 2;
    if (ctx->resource_live[kind]>=1024) return 4;
    if (!p->acquire || !p->release || !p->complete) return 1;
    const unsigned char *effective=request;size_t effective_length=length;
    unsigned char *joined=NULL;
    if (scope) {
        DirScope *scopes=ctx->resource_scopes;
        const char *base=scopes[scope-1].prefix;size_t base_length=scopes[scope-1].length;
        if (kind==1) {
            /* A narrowed Network asks for exactly its scoped endpoint: the
               guest's request bytes are ignored and the recorded endpoint is
               always the effective request, so `connect` needs no request. */
            (void)request;(void)length;
            effective=(const unsigned char *)base;effective_length=base_length;
        } else {
            const unsigned char *path=request+2;size_t path_length=length-2;
            size_t total=2+base_length+path_length+(base_length&&path_length?1:0);
            if (total>4096) { myl_qbe_fail(ctx,"InvalidCapability");return -1; }
            joined=malloc(total);
            if (!joined) { myl_qbe_fail_allocation(ctx);return -1; }
            joined[0]=request[0];joined[1]=':';
            size_t at=2;
            if (base_length) { memcpy(joined+at,base,base_length);at+=base_length; }
            if (base_length&&path_length) joined[at++]='/';
            if (path_length) memcpy(joined+at,path,path_length);
            at+=path_length;
            effective=joined;effective_length=at;
        }
    }
    Resource *resource=calloc(1,sizeof *resource);
    unsigned char *bytes=malloc(effective_length?effective_length:1);
    if (!resource || !bytes) { free(resource);free(bytes);free(joined);myl_qbe_fail_allocation(ctx);return -1; }
    if (effective_length) memcpy(bytes,effective,effective_length);
    free(joined);
    MylangResourceResult result=p->acquire(p->context,bytes,effective_length,permissions);
    free(bytes);
    int code=status(ctx,result.status);
    if (code) { free(resource);return code; }
    resource->base.drop=drop;resource->context=ctx;resource->kind=kind;resource->provider=p;
    resource->permissions=permissions;resource->handle=result.handle;
    resource->previous=ctx->resource_tails[kind];
    if (resource->previous) resource->previous->next=resource;
    ctx->resource_tails[kind]=resource;ctx->resource_live[kind]++;
    ctx->cleanup=cleanup;
    *output=&resource->base;
    return 0;
}
int myl_qbe_resource_complete(void *context,myl_native_resource *value) {
    Resource *resource=(Resource *)value;
    if (!resource || resource->context!=context) { myl_qbe_fail(context,"InvalidOwner");return -1; }
    if (!(resource->permissions&4)) return 2;
    const MylangResourceProvider *p=resource->provider;
    int code=status(context,p->complete(p->context,resource->handle));
    if (!code) { unlink_resource(resource);free(resource); }
    return code;
}
int myl_qbe_resource_read(void *context,myl_native_resource *value,unsigned char *output,size_t capacity,size_t *length,int *eof) {
    Resource *resource=(Resource *)value;
    *length=0;*eof=0;
    if (!resource || resource->context!=context) { myl_qbe_fail(context,"InvalidOwner");return -1; }
    if (!(resource->permissions&1)) return 2;
    const MylangResourceProvider *p=resource->provider;
    if (!p->read) return 1;
    unsigned char *bytes=malloc(capacity?capacity:1);
    if (!bytes) { myl_qbe_fail_allocation(context);return -1; }
    MylangResourceRead result=p->read(p->context,resource->handle,bytes,capacity);
    int code=status(context,result.status);
    if (!code && (result.length>capacity || (result.eof!=0 && result.eof!=1))) { myl_qbe_fail(context,"InvalidProvider");code=-1; }
    if (!code) {
        if (result.length) memcpy(output,bytes,result.length);
        *length=result.length;*eof=result.eof;
    }
    free(bytes);return code;
}
int myl_qbe_resource_write(void *context,myl_native_resource *value,const unsigned char *input,size_t length,size_t *written) {
    Resource *resource=(Resource *)value;
    *written=0;
    if (!resource || resource->context!=context) { myl_qbe_fail(context,"InvalidOwner");return -1; }
    if (!(resource->permissions&2)) return 2;
    const MylangResourceProvider *p=resource->provider;
    if (!p->write) return 1;
    unsigned char *bytes=malloc(length?length:1);
    if (!bytes) { myl_qbe_fail_allocation(context);return -1; }
    if (length) memcpy(bytes,input,length);
    MylangResourceWrite result=p->write(p->context,resource->handle,bytes,length);
    free(bytes);
    int code=status(context,result.status);
    if (!code && result.length>length) { myl_qbe_fail(context,"InvalidProvider");return -1; }
    if (!code) *written=result.length;
    return code;
}
