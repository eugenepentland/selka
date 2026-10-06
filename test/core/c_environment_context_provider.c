#include "../../src/native_providers.h"
#include <string.h>
static MylangEnvironmentResult absent(void *context,const uint8_t *name,size_t length,uint8_t *output,size_t capacity) {
    (void)name;(void)length;(void)output;(void)capacity;
    return (MylangEnvironmentResult){context && !strcmp(context,"CUSTOM") ? MYLANG_PROVIDER_OK : MYLANG_PROVIDER_FAILED,0,0};
}
MylangNativeProviders mylang_native_providers_v7(void) {
    static char context[]="CUSTOM";
    MylangNativeProviders providers={0};
    providers.environment_context=context;
    providers.environment_get=absent;
    return providers;
}
