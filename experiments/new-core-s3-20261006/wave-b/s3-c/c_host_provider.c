/* Trusted test adapter for Core's copied node, packed bytes and scalar extern paths. */
#include "../../../../src/native_providers.h"
#include <string.h>
int64_t scalar_echo(int64_t value){return value;}
static const char *echo(void *context,MylangHostCall *call){
    (void)context;if(call->argument_nodes!=3||call->capacity<3)return "HostFailure";
    if(!mylang_host_charge(call,3))return "HostWorkLimit";
    memcpy(call->output,call->arguments,3*sizeof(*call->output));call->output_nodes=3;return NULL;
}
static const char *unused(void *context,MylangHostCall *call){(void)context;(void)call;return "HostFailure";}
static const char *raw(void *context,MylangHostPackedCall *call){
    (void)context;if(call->argument_count!=1)return "HostFailure";
    if(!mylang_host_packed_charge(call,call->arguments[0].size))return "HostWorkLimit";
    call->output=call->arguments[0];call->output_written=call->output.size;return NULL;
}
MylangNativeProviders mylang_native_providers_v7(void){
    static const char *pair_params[]={"c_host::Pair"},*bytes_params[]={"bytes"};
    static const MylangHostBinding bindings[]={
        {"c_host::echo",pair_params,1,"c_host::Pair",32,32,NULL,echo,NULL},
        {"c_host::raw",bytes_params,1,"bytes",32,32,NULL,unused,raw}
    };
    MylangNativeProviders providers={0};providers.host=(MylangHostRegistry){bindings,2,0,0,0,0,0};return providers;
}
