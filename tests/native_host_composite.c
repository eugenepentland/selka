#include "native_providers.h"
#include <stdlib.h>
#include <string.h>
static const char *echo(void *context,MylangHostCall *call) {
    (void)context;
    if (call->capacity<call->argument_nodes) return "ValueCountLimit";
    memcpy(call->output,call->arguments,call->argument_nodes*sizeof(MylangHostNode));
    call->output_nodes=call->argument_nodes;
    if (getenv("MYLANG_HOST_BAD")) call->output[0].children=9;
    return NULL;
}
static const char *parameters[]={"Outcome"};
static const MylangHostBinding bindings[]={{"echo",parameters,1,"Outcome",64,64,NULL,echo}};
MylangNativeProviders mylang_native_providers(void) {
    return (MylangNativeProviders){.host={.bindings=bindings,.count=1}};
}
