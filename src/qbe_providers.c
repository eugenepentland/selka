#include "qbe_runtime.h"
#include "native_providers.h"
#include "native_text.h"
#include <string.h>
/* Bounded host copy for the Python `env.get` surface. A value wider than this
   reports `InvalidProvider` rather than truncating; the raw `environment_get`
   spelling keeps its caller-declared `[N]u8` capacity. */
#define MYLANG_ENVIRONMENT_TEXT_LIMIT 16384u
/* Bound on the sorted name list `env.names()` publishes. */
#define MYLANG_ENVIRONMENT_NAMES_LIMIT 64
extern char **environ;
static const MylangNativeProviders empty={0};
static const MylangNativeProviders *providers(void *context) {
    const MylQbeContext *ctx=context;
    (void)mylang_host_charge;
    return ctx->providers ? ctx->providers:&empty;
}
uint64_t myl_qbe_grant_external(void *context,unsigned kind) {
    const MylangNativeProviders *p=providers(context);
    int available=kind==0 ? p->clock_now!=NULL:kind==1 ? p->random_u64!=NULL:kind==2 && p->environment_get!=NULL;
    if (!available) { myl_qbe_fail(context,"CapabilityUnavailable");return 0; }
    return UINT64_MAX-kind;
}
uint64_t myl_qbe_grant_external_checked(void *context,unsigned kind,const char *flag) {
    const MylangNativeProviders *p=providers(context);
    int available=kind==0 ? p->clock_now!=NULL:kind==1 ? p->random_u64!=NULL:kind==2 && p->environment_get!=NULL;
    if (!available) { myl_qbe_fail_missing_capability(context,flag);return 0; }
    return UINT64_MAX-kind;
}
int myl_qbe_external_read(void *context,uint64_t authority,unsigned kind,uint64_t *output) {
    if (kind>1 || authority!=UINT64_MAX-kind) { myl_qbe_fail_capability(context);return -1; }
    const MylangNativeProviders *p=providers(context);
    MylangProviderStatus status=MYLANG_PROVIDER_UNAVAILABLE;
    if (kind==0 && p->clock_now) {
        MylangClockResult result=p->clock_now(p->clock_context);
        status=result.status;
        if (status==MYLANG_PROVIDER_OK) memcpy(output,&result.value,8);
    } else if (kind==1 && p->random_u64) {
        MylangRandomResult result=p->random_u64(p->random_context);
        status=result.status;
        if (status==MYLANG_PROVIDER_OK) *output=result.value;
    }
    if (status==MYLANG_PROVIDER_OUT_OF_MEMORY) myl_qbe_fail_allocation(context);
    else if (status<MYLANG_PROVIDER_OK || status>MYLANG_PROVIDER_FAILED) myl_qbe_fail(context,"InvalidProviderResult");
    return myl_qbe_failed(context) ? -1:(int)status;
}
/* Decode an environment authority into its narrowed name scope. The root grant
   has no scope; a scoped authority borrows its blob from the context table. */
static int environment_scope(void *context,uint64_t authority,const unsigned char **names,size_t *length) {
    MylQbeContext *ctx=context;
    if (authority==MYL_QBE_ENVIRONMENT_ROOT) { *names=NULL;*length=0;return 1; }
    if (authority<=MYL_QBE_ENVIRONMENT_SCOPE_BASE && authority>MYL_QBE_ENVIRONMENT_SCOPE_BASE-MYL_QBE_ENVIRONMENT_SCOPES) {
        unsigned index=(unsigned)(MYL_QBE_ENVIRONMENT_SCOPE_BASE-authority);
        if (index<ctx->environment_scope_count) {
            *names=ctx->environment_scopes[index].names;
            *length=ctx->environment_scopes[index].length;
            return 1;
        }
    }
    return 0;
}
/* Whether an exact NUL-terminated entry in a scope blob names `key`. */
static int scope_allows(const unsigned char *blob,size_t length,const unsigned char *key,size_t key_length) {
    size_t cursor=0;
    while (cursor<length) {
        size_t end=cursor;
        while (end<length && blob[end]!=0) end++;
        if (end-cursor==key_length && (key_length==0 || !memcmp(blob+cursor,key,key_length))) return 1;
        cursor=end+1;
    }
    return 0;
}
/* Register or dedup one `env.only(...)` name blob and return its scope authority. */
uint64_t myl_qbe_environment_only(void *context,uint64_t authority,const unsigned char *names,size_t length) {
    MylQbeContext *ctx=context;
    if (authority!=MYL_QBE_ENVIRONMENT_ROOT) { myl_qbe_fail_capability(context);return 0; }
    if (!length || names[length-1]!=0) { myl_qbe_fail(context,"InvalidCapability");return 0; }
    unsigned count=0;
    for (size_t cursor=0;cursor<length;) {
        size_t end=cursor;
        while (end<length && names[end]!=0) end++;
        if (end==cursor || end-cursor>MYL_QBE_ENVIRONMENT_NAME_LIMIT || count==MYL_QBE_ENVIRONMENT_NAMES) {
            myl_qbe_fail(context,"InvalidCapability");return 0;
        }
        count++;
        cursor=end+1;
    }
    for (unsigned i=0;i<ctx->environment_scope_count;i++) {
        if (ctx->environment_scopes[i].length==length && !memcmp(ctx->environment_scopes[i].names,names,length))
            return MYL_QBE_ENVIRONMENT_SCOPE_BASE-i;
    }
    if (ctx->environment_scope_count==MYL_QBE_ENVIRONMENT_SCOPES) { myl_qbe_fail(context,"CapacityLimit");return 0; }
    unsigned index=ctx->environment_scope_count++;
    ctx->environment_scopes[index].names=names;
    ctx->environment_scopes[index].length=length;
    return MYL_QBE_ENVIRONMENT_SCOPE_BASE-index;
}
/* The scanner above rejects an empty name, so `scope_allows` never sees one. */
int myl_qbe_environment_get(void *context,uint64_t authority,const unsigned char *key,size_t length,unsigned char *output,size_t capacity,size_t *written,int *present) {
    const unsigned char *scope;size_t scope_length;
    if (!environment_scope(context,authority,&scope,&scope_length)) { myl_qbe_fail_capability(context);return -1; }
    if (scope && !scope_allows(scope,scope_length,key,length)) { myl_qbe_fail_capability(context);return -1; }
    const MylangNativeProviders *p=providers(context);
    *written=0;*present=0;
    MylangEnvironmentResult result={MYLANG_PROVIDER_UNAVAILABLE,0,0};
    if (p->environment_get) result=p->environment_get(p->environment_context,key,length,output,capacity);
    if (result.status==MYLANG_PROVIDER_OUT_OF_MEMORY) { myl_qbe_fail_allocation(context);return -1; }
    if (result.status!=MYLANG_PROVIDER_OK) {
        int status=result.status==MYLANG_PROVIDER_NO_CAPACITY ? 4:(int)result.status;
        if (status<1 || status>4) { myl_qbe_fail(context,"InvalidProvider");return -1; }
        return status;
    }
    if ((result.present!=0 && result.present!=1) || (result.present && result.length>capacity)) {
        myl_qbe_fail(context,"InvalidProvider");return -1;
    }
    *written=result.present ? result.length:0;
    *present=result.present;
    if (capacity>*written) memset(output+*written,0,capacity-*written);
    return 0;
}
/* Python `env.get(name) -> Option[str]`: answer a rooted UTF-8 text on success
   and set `*present`. A denied or unusable authority traps through the shared
   capability path, the same error path the raw provider status maps onto. */
void *myl_qbe_environment_text(void *context,uint64_t authority,const unsigned char *key,size_t length,int *present) {
    const unsigned char *scope;size_t scope_length;
    if (!environment_scope(context,authority,&scope,&scope_length)) { myl_qbe_fail_capability(context);return NULL; }
    if (scope && !scope_allows(scope,scope_length,key,length)) { myl_qbe_fail_capability(context);return NULL; }
    const MylangNativeProviders *p=providers(context);
    *present=0;
    unsigned char frame[MYLANG_ENVIRONMENT_TEXT_LIMIT];
    MylangEnvironmentResult result={MYLANG_PROVIDER_UNAVAILABLE,0,0};
    if (p->environment_get) result=p->environment_get(p->environment_context,key,length,frame,sizeof frame);
    if (result.status==MYLANG_PROVIDER_OUT_OF_MEMORY) { myl_qbe_fail_allocation(context);return NULL; }
    if (result.status!=MYLANG_PROVIDER_OK) {
        int status=result.status==MYLANG_PROVIDER_NO_CAPACITY ? 4:(int)result.status;
        if (status<1 || status>4) { myl_qbe_fail(context,"InvalidProvider");return NULL; }
        myl_qbe_fail_capability(context);
        return NULL;
    }
    if ((result.present!=0 && result.present!=1) || (result.present && result.length>sizeof frame)) {
        myl_qbe_fail(context,"InvalidProvider");return NULL;
    }
    if (!result.present) return NULL;
    if (!myl_native_text_valid_utf8(frame,result.length)) { myl_qbe_fail(context,"R_ENVIRONMENT");return NULL; }
    myl_native_text *text=myl_native_text_from_utf8(myl_qbe_heap(context),frame,result.length);
    if (!text) { myl_qbe_fail_allocation(context);return NULL; }
    *present=1;
    return text;
}
/* One collected environment name borrowed from the allowlist, a scope blob, or
   the process environment. */
typedef struct { const unsigned char *bytes; size_t length; } MylEnvironmentName;
static int name_order(const MylEnvironmentName *a,const MylEnvironmentName *b) {
    size_t shortest=a->length<b->length?a->length:b->length;
    int order=shortest?memcmp(a->bytes,b->bytes,shortest):0;
    if (order) return order;
    return a->length<b->length?-1:a->length>b->length?1:0;
}
static void name_add(MylEnvironmentName *names,unsigned *count,const unsigned char *bytes,size_t length) {
    if (!length || length>MYL_QBE_ENVIRONMENT_NAME_LIMIT || *count==MYLANG_ENVIRONMENT_NAMES_LIMIT) return;
    for (unsigned i=0;i<*count;i++) if (names[i].length==length && !memcmp(names[i].bytes,bytes,length)) return;
    names[(*count)++]=(MylEnvironmentName){bytes,length};
}
static int allow_has(const char *allow,const unsigned char *bytes,size_t length) {
    if (!*allow) return 1;
    for (const char *cursor=allow;*cursor;) {
        const char *comma=strchr(cursor,',');
        size_t width=comma?(size_t)(comma-cursor):strlen(cursor);
        if (width==length && (length==0 || !memcmp(cursor,bytes,length))) return 1;
        if (!comma) break;
        cursor=comma+1;
    }
    return 0;
}
/* Python `env.names() -> list[str]`: publish the visible names, sorted. A root
   authority lists the `--allow-env` allowlist, or the whole process environment
   when no allowlist is set; a narrowed authority lists its scope names. */
void *myl_qbe_environment_names(void *context,uint64_t authority) {
    MylQbeContext *ctx=context;
    const unsigned char *scope;size_t scope_length;
    if (!environment_scope(context,authority,&scope,&scope_length)) { myl_qbe_fail_capability(context);return NULL; }
    const MylangNativeProviders *p=providers(context);
    const char *allow=(const char *)p->environment_context;
    if (!allow) allow="";
    MylEnvironmentName names[MYLANG_ENVIRONMENT_NAMES_LIMIT];
    unsigned count=0;
    if (scope) {
        for (size_t cursor=0;cursor<scope_length;) {
            size_t end=cursor;
            while (end<scope_length && scope[end]!=0) end++;
            if (allow_has(allow,scope+cursor,end-cursor)) name_add(names,&count,scope+cursor,end-cursor);
            cursor=end+1;
        }
    } else if (*allow) {
        for (const char *cursor=allow;*cursor;) {
            const char *comma=strchr(cursor,',');
            size_t width=comma?(size_t)(comma-cursor):strlen(cursor);
            if (width) name_add(names,&count,(const unsigned char *)cursor,width);
            if (!comma) break;
            cursor=comma+1;
        }
    } else {
        for (char **entry=environ;entry && *entry;entry++) {
            const char *equals=strchr(*entry,'=');
            size_t width=equals?(size_t)(equals-*entry):strlen(*entry);
            name_add(names,&count,(const unsigned char *)*entry,width);
        }
    }
    for (unsigned i=1;i<count;i++) {
        MylEnvironmentName key=names[i];
        unsigned j=i;
        while (j>0 && name_order(&names[j-1],&key)>0) { names[j]=names[j-1];j--; }
        names[j]=key;
    }
    static const myl_native_type pointer_type={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
    myl_native_heap *heap=myl_qbe_heap(context);
    myl_native_list *list=myl_native_list_new(heap,&pointer_type,count);
    if (!list) { myl_qbe_fail_allocation(context);return NULL; }
    myl_native_root root;
    myl_native_root_push(heap,&root,&list,&pointer_type);
    for (unsigned i=0;i<count;i++) {
        if (!myl_native_text_valid_utf8(names[i].bytes,names[i].length)) continue;
        myl_native_text *text=myl_native_text_from_utf8(heap,names[i].bytes,names[i].length);
        if (!text || !myl_native_list_append(heap,list,&text)) { myl_qbe_fail_allocation(context);list=NULL;break; }
    }
    myl_native_root_pop(heap,&root);
    return list;
}
