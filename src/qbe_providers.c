#include "qbe_runtime.h"
#include "native_providers.h"
#include <string.h>
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
int myl_qbe_environment_get(void *context,uint64_t authority,const unsigned char *key,size_t length,unsigned char *output,size_t capacity,size_t *written,int *present) {
    if (authority!=UINT64_MAX-2) { myl_qbe_fail_capability(context);return -1; }
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
