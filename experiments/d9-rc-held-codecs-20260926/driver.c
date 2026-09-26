/* Exercise admitted codec calls and refused ordinary-wire calls on real libraries. */
#include "native_providers.h"
#include "native_embed.h"
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
typedef int (*CodecCall)(const char *,const MylangWireNode *,size_t,MylangWireNode *,size_t,const MylangCodecOptions *,MylangCodecResult *);
typedef int (*ValueCall)(const char *,const MylangWireNode *,size_t,MylangWireNode *,size_t,const MylangRunOptions *,MylangWireResult *);
int main(int argc,char **argv){
    assert(argc==2);
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
    if(!library){fprintf(stderr,"%s\n",dlerror());return 2;}
    CodecCall codec=(CodecCall)dlsym(library,"mylang_native_call_codecs_v1");
    ValueCall value=(ValueCall)dlsym(library,"mylang_native_call_values_v1");
    assert(codec && value);
    const MylangWireNode input[]={{"DictValues<i64,i64>",0,1},{"dict<i64,i64>",0,1},{"i64",1,0},{"i64",7,0}};
    MylangWireNode output[8]={0};MylangCodecResult result={0};MylangWireResult ordinary={0};
    assert(value("bridge::receive",input,4,output,8,NULL,&ordinary)==2);
    assert(!strcmp(ordinary.execution.code,"UnsupportedSignature"));
    assert(codec("bridge::receive",input,4,output,8,NULL,&result)==0);
    assert(result.value.node_count==1 && output[0].bits==7 && !strcmp(output[0].type,"i64"));
    assert(codec("bridge::produce",NULL,0,output,8,NULL,&result)==0);
    assert(result.value.node_count==4 && output[3].bits==7);
    assert(codec("bridge::receive",input,3,output,8,NULL,&result)==2);
    assert(!strcmp(result.value.execution.code,"InvalidArgument") && !result.value.node_count);
    assert(codec("bridge::produce",NULL,0,NULL,0,NULL,&result)==2);
    assert(!strcmp(result.value.execution.code,"OutputTooSmall") && result.value.node_count==4);
    assert(dlclose(library)==0);
    puts("5 held-view bridge scenarios passed");return 0;
}
