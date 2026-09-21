#include "native_providers.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static const unsigned char input[]={0,255,65};
static int mode;
static const char *length(void *context,MylangHostCall *call) {
    (void)context;
    if (!mylang_host_charge(call,1)) return "HostWorkLimit";
    if (!call->capacity) return "ValueCountLimit";
    call->output[0]=(MylangHostNode){"i64",sizeof input,0};call->output_nodes=1;
    if (mode==4) call->output[0].type="bool";
    if (mode==5) return "HostFailure";
    return NULL;
}
static const char *byte(void *context,MylangHostCall *call) {
    (void)context;
    if (!mylang_host_charge(call,1)) return "HostWorkLimit";
    if (call->argument_nodes!=1 || call->arguments[0].bits>=sizeof input) return "HostFailure";
    if (!call->capacity) return "ValueCountLimit";
    call->output[0]=(MylangHostNode){"u8",input[call->arguments[0].bits],0};call->output_nodes=1;return NULL;
}
static const char *put(void *context,MylangHostCall *call) {
    (void)context;
    if (!mylang_host_charge(call,1)) return "HostWorkLimit";
    if (call->argument_nodes!=1 || !call->capacity) return "HostFailure";
    fputc((int)call->arguments[0].bits,stderr);
    call->output[0]=(MylangHostNode){"i64",0,0};call->output_nodes=1;return NULL;
}
static const char *i64_parameter[]={"i64"}, *u8_parameter[]={"u8"};
static MylangHostBinding bindings[]={
    {"io::length",NULL,0,"i64",32,32,NULL,length,NULL},
    {"io::byte",i64_parameter,1,"u8",32,32,NULL,byte,NULL},
    {"io::put",u8_parameter,1,"i64",32,32,NULL,put,NULL},
};
MylangNativeProviders mylang_native_providers(void) {
    const char *setting=getenv("MYLANG_HOST_MODE");mode=setting?atoi(setting):0;
    if (mode==2) bindings[0].grants=0;
    if (mode==3) bindings[0].result="u8";
    return (MylangNativeProviders){.host={.bindings=bindings,.count=mode==1?2:3,
        .max_calls=mode==6?1:10000,.max_work=mode==7?1:1000000,.max_values=mode==8?1:65536}};
}
