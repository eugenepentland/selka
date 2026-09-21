#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static size_t allocations, frees;
static void *tracked_calloc(size_t count, size_t size) {
    allocations++;
    return calloc(count,size);
}
static void tracked_free(void *pointer) {
    if (pointer) frees++;
    free(pointer);
}

#define calloc tracked_calloc
#define free tracked_free
#include "../src/qbe_host_runtime.c"
#undef calloc
#undef free

void *myl_qbe_frame_allocate(void *context,uint64_t bytes) {
    (void)context; return tracked_calloc(1,(size_t)bytes);
}
void myl_qbe_frame_release(void *context,void *payload) {
    (void)context; tracked_free(payload);
}

static const size_t array_child[]={0},byte_array_child[]={2},byte_array_offset[]={0};
static const QbeHostType qbe_host_types[]={
    {"i64",8,0,0,1,64,1,NULL,NULL},
    {"Nine",72,9,8,3,0,0,array_child,NULL},
    {"u8",1,0,0,1,8,0,NULL,NULL},
    {"i8",1,0,0,1,8,1,NULL,NULL},
    {"Bytes256",256,256,1,3,0,0,byte_array_child,byte_array_offset},
    {"BadBytes256",255,256,1,3,0,0,byte_array_child,byte_array_offset},
    {"Bytes2048",2048,2048,1,3,0,0,byte_array_child,byte_array_offset},
};
static const size_t scalar_parameter[]={0};
static const size_t u8_parameter[]={2},i8_parameter[]={3};
static const size_t seven_parameters[]={0,0,0,0,0,0,0};
static const size_t eight_parameters[]={0,0,0,0,0,0,0,0};
static const size_t bytes_parameter[]={4},bad_bytes_parameter[]={5},large_bytes_parameter[]={6};
static const QbeHostDeclaration qbe_host_declarations[]={
    {"f0",scalar_parameter,1,0,1}, {"f1",scalar_parameter,1,0,1},
    {"f2",scalar_parameter,1,0,1}, {"f3",scalar_parameter,1,0,1},
    {"f4",scalar_parameter,1,0,1}, {"f5",scalar_parameter,1,0,1},
    {"f6",scalar_parameter,1,0,1}, {"f7",scalar_parameter,1,0,1},
    {"f8",scalar_parameter,1,0,1}, {"f9",NULL,0,1,1},
    {"f10",NULL,0,0,1},
    {"f11",u8_parameter,1,2,1}, {"f12",i8_parameter,1,3,1},
    {"f13",seven_parameters,7,0,1}, {"f14",eight_parameters,8,0,1},
    {"f15",bytes_parameter,1,4,1}, {"f16",bad_bytes_parameter,1,5,1},
    {"f17",large_bytes_parameter,1,6,1},
};
static const size_t qbe_host_declaration_count=sizeof(qbe_host_declarations)/sizeof(qbe_host_declarations[0]);

static const char *failure_code;
static size_t scalar_invocations;
static int invalid_u8;
static size_t packed_invocations,packed_fallback_invocations;
static int packed_mode;
void myl_qbe_fail(void *context,const char *code) {
    MylQbeContext *ctx=context;
    if (!ctx->trap) ctx->trap=code;
}

static const char *scalar(void *opaque,MylangHostCall *call) {
    (void)opaque;
    scalar_invocations++;
    assert(call->argument_nodes==1 && call->capacity>=1);
    call->output[0]=(MylangHostNode){"i64",call->arguments[0].bits+1,0};
    call->output_nodes=1;
    return failure_code;
}
static const char *large(void *opaque,MylangHostCall *call) {
    (void)opaque;
    assert(call->capacity>=10);
    call->output[0]=(MylangHostNode){"Nine",0,9};
    for (size_t i=0;i<9;i++) call->output[i+1]=(MylangHostNode){"i64",i,0};
    call->output_nodes=10;
    return failure_code;
}
static const char *zero_scalar(void *opaque,MylangHostCall *call) {
    (void)opaque;
    assert(call->argument_nodes==0 && call->capacity==1);
    call->output[0]=(MylangHostNode){"i64",42,0};
    call->output_nodes=1;
    return NULL;
}
static const char *narrow_u8(void *opaque,MylangHostCall *call) {
    (void)opaque;
    assert(call->argument_nodes==1 && call->arguments[0].bits==255);
    call->output[0]=(MylangHostNode){"u8",invalid_u8?256:255,0};
    call->output_nodes=1;
    return NULL;
}
static const char *narrow_i8(void *opaque,MylangHostCall *call) {
    (void)opaque;
    assert(call->argument_nodes==1 && call->arguments[0].bits==UINT64_MAX);
    call->output[0]=(MylangHostNode){"i8",UINT64_MAX-1,0};
    call->output_nodes=1;
    return NULL;
}
static const char *many_scalars(void *opaque,MylangHostCall *call) {
    (void)opaque;
    uint64_t sum=0;
    for (size_t i=0;i<call->argument_nodes;i++) sum+=call->arguments[i].bits;
    assert(call->capacity==1);
    call->output[0]=(MylangHostNode){"i64",sum,0};
    call->output_nodes=1;
    return NULL;
}
static const char *malformed(void *opaque,MylangHostCall *call) {
    (void)opaque;
    call->output[0]=(MylangHostNode){"i64",0,1};
    call->output_nodes=1;
    return NULL;
}
static const char *missing_output(void *opaque,MylangHostCall *call) {
    (void)opaque; (void)call;
    return NULL;
}
static const char *extra_output(void *opaque,MylangHostCall *call) {
    (void)opaque;
    call->output[0]=(MylangHostNode){"i64",0,0};
    call->output_nodes=2;
    return NULL;
}
static const char *wrong_type(void *opaque,MylangHostCall *call) {
    (void)opaque;
    call->output[0]=(MylangHostNode){"Nine",0,0};
    call->output_nodes=1;
    return NULL;
}
static const char *increase_work(void *opaque,MylangHostCall *call) {
    (void)opaque;
    call->work_remaining++;
    call->output[0]=(MylangHostNode){"i64",0,0};
    call->output_nodes=1;
    return NULL;
}
static const char *exhaust_work(void *opaque,MylangHostCall *call) {
    (void)opaque;
    call->exhausted=1;
    return NULL;
}
static const char *no_capacity(void *opaque,MylangHostCall *call) {
    (void)opaque;
    (void)call;
    scalar_invocations++;
    assert(call->argument_nodes==1 && call->capacity==0);
    return "HostFailure";
}
static const char *no_capacity_many(void *opaque,MylangHostCall *call) {
    (void)opaque;
    assert(call->argument_nodes==7 && call->capacity==0);
    return "HostFailure";
}
static const char *reenter(void *opaque,MylangHostCall *call) {
    MylQbeContext *ctx=opaque;
    uint64_t input=1,output=0;
    const void *arguments[]={&input};
    qbe_host_invoke(ctx,0,arguments,&output);
    call->output[0]=(MylangHostNode){"i64",0,0};
    call->output_nodes=1;
    return NULL;
}
static const char *packed_fallback(void *opaque,MylangHostCall *call) {
    (void)opaque; (void)call; packed_fallback_invocations++;
    return "HostFailure";
}
static const char *packed_bytes(void *opaque,MylangHostPackedCall *call) {
    packed_invocations++;
    assert(call->argument_count==1 && call->arguments[0].size==call->output.size);
    size_t size=call->output.size;
    assert(size==256 || size==2048);
    unsigned char *input=call->arguments[0].bytes,*output=call->output.bytes;
    if (!mylang_host_packed_charge(call,1)) return "HostWorkLimit";
    unsigned char first=input[0]; input[0]^=0xff; /* must mutate only scratch */
    if (packed_mode!=7) memset(output,first,size);
    call->output_written=size;
    if (packed_mode==1) call->work_remaining+=2;
    if (packed_mode==2) call->exhausted=1;
    if (packed_mode==3) return "HostFailure";
    if (packed_mode==4) call->output_written=255;
    if (packed_mode==5) {
        MylQbeContext *ctx=opaque; unsigned char nested[256]={0},result[256]={0};
        const void *arguments[]={nested}; qbe_host_invoke(ctx,15,arguments,result);
    }
    if (packed_mode==6) call->output.bytes=input;
    if (packed_mode==8) call->output.size--;
    return NULL;
}

static const char *i64_parameters[]={"i64"};
static const char *u8_parameters[]={"u8"},*i8_parameters[]={"i8"};
static const char *seven_i64_parameters[]={"i64","i64","i64","i64","i64","i64","i64"};
static const char *eight_i64_parameters[]={"i64","i64","i64","i64","i64","i64","i64","i64"};
static const char *bytes_parameters[]={"Bytes256"},*bad_bytes_parameters[]={"BadBytes256"},*large_bytes_parameters[]={"Bytes2048"};
static MylangHostBinding bindings[18];
static MylangNativeProviders providers;

static void reset_bindings(void) {
    static const char *names[]={"f0","f1","f2","f3","f4","f5","f6","f7","f8","f9","f10","f11","f12","f13","f14","f15","f16","f17"};
    memset(bindings,0,sizeof(bindings));
    for (size_t i=0;i<9;i++) bindings[i]=(MylangHostBinding){names[i],i64_parameters,1,"i64",1,1,NULL,scalar,NULL};
    bindings[9]=(MylangHostBinding){names[9],NULL,0,"Nine",1,1,NULL,large,NULL};
    bindings[10]=(MylangHostBinding){names[10],NULL,0,"i64",1,1,NULL,zero_scalar,NULL};
    bindings[11]=(MylangHostBinding){names[11],u8_parameters,1,"u8",1,1,NULL,narrow_u8,NULL};
    bindings[12]=(MylangHostBinding){names[12],i8_parameters,1,"i8",1,1,NULL,narrow_i8,NULL};
    bindings[13]=(MylangHostBinding){names[13],seven_i64_parameters,7,"i64",1,1,NULL,many_scalars,NULL};
    bindings[14]=(MylangHostBinding){names[14],eight_i64_parameters,8,"i64",1,1,NULL,many_scalars,NULL};
    bindings[15]=(MylangHostBinding){names[15],bytes_parameters,1,"Bytes256",1,1,NULL,packed_fallback,packed_bytes};
    bindings[16]=(MylangHostBinding){names[16],bad_bytes_parameters,1,"BadBytes256",1,1,NULL,packed_fallback,packed_bytes};
    bindings[17]=(MylangHostBinding){names[17],large_bytes_parameters,1,"Bytes2048",1,1,NULL,packed_fallback,packed_bytes};
    providers=(MylangNativeProviders){.host={.bindings=bindings,.count=18}};
    failure_code=NULL;
    scalar_invocations=0;
    invalid_u8=0;
    packed_invocations=packed_fallback_invocations=0; packed_mode=0;
}
static void dispose(MylQbeContext *ctx) {
    tracked_free(ctx->host_state);
    ctx->host_state=NULL;
}
static MylQbeContext context(void) {
    MylQbeContext ctx={0};
    ctx.providers=&providers;
    return ctx;
}

int main(void) {
    reset_bindings();
    MylQbeContext ctx=context();
    myl_qbe_host_begin(&ctx);
    assert(!ctx.trap && ctx.host_state);
    QbeHostState *state=ctx.host_state;
    assert(state->bound[8]==&bindings[8] && state->bound[9]==&bindings[9] && state->bound[16]==&bindings[16]);
    size_t after_begin=allocations;
    for (uint64_t i=0;i<100;i++) {
        uint64_t output=0;
        const void *arguments[]={&i};
        qbe_host_invoke(&ctx,8,arguments,&output);
        assert(!ctx.trap && output==i+1);
    }
    assert(allocations==after_begin); /* small scalar calls stay allocation-free */
    uint64_t zero_output=0;
    qbe_host_invoke(&ctx,10,NULL,&zero_output);
    assert(!ctx.trap && zero_output==42 && allocations==after_begin);
    uint8_t u8_input=255,u8_output=0; const void *u8_arguments[]={&u8_input};
    qbe_host_invoke(&ctx,11,u8_arguments,&u8_output);
    assert(!ctx.trap && u8_output==255 && allocations==after_begin);
    int8_t i8_input=-1,i8_output=0; const void *i8_arguments[]={&i8_input};
    qbe_host_invoke(&ctx,12,i8_arguments,&i8_output);
    assert(!ctx.trap && i8_output==-2 && allocations==after_begin);
    uint64_t many_values[]={1,2,3,4,5,6,7,8},many_output=0;
    const void *many_arguments[]={&many_values[0],&many_values[1],&many_values[2],&many_values[3],&many_values[4],&many_values[5],&many_values[6],&many_values[7]};
    qbe_host_invoke(&ctx,13,many_arguments,&many_output);
    assert(!ctx.trap && many_output==28 && allocations==after_begin);
    qbe_host_invoke(&ctx,14,many_arguments,&many_output);
    assert(!ctx.trap && many_output==36 && allocations==after_begin+1 && frees==1);
    uint64_t output[9]={0};
    qbe_host_invoke(&ctx,9,NULL,output);
    assert(!ctx.trap && allocations==after_begin+2 && frees==2);
    for (size_t i=0;i<9;i++) assert(output[i]==i);
    dispose(&ctx);

    /* spec-case: HOST-PACKED-1 */
    reset_bindings(); ctx=context(); myl_qbe_host_begin(&ctx);
    unsigned char packed_input[256],packed_output[256];
    memset(packed_input,0,256); packed_input[0]=37; memset(packed_output,0xaa,256);
    const void *packed_arguments[]={packed_input};
    qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(!ctx.trap && packed_invocations==1 && !packed_fallback_invocations);
    assert(packed_input[0]==37); /* callback mutated only the runtime copy */
    for (size_t i=0;i<256;i++) assert(packed_output[i]==37);
    dispose(&ctx);

    reset_bindings(); packed_mode=1; ctx=context(); myl_qbe_host_begin(&ctx);
    memset(packed_output,0xaa,256); qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_LIMIT") && packed_output[0]==0xaa); dispose(&ctx);
    reset_bindings(); packed_mode=2; ctx=context(); myl_qbe_host_begin(&ctx);
    memset(packed_output,0xaa,256); qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_LIMIT") && packed_output[0]==0xaa); dispose(&ctx);
    reset_bindings(); packed_mode=3; ctx=context(); myl_qbe_host_begin(&ctx);
    memset(packed_output,0xaa,256); qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_FAILURE") && packed_output[0]==0xaa); dispose(&ctx);
    reset_bindings(); packed_mode=4; ctx=context(); myl_qbe_host_begin(&ctx);
    memset(packed_output,0xaa,256); qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_CONTRACT") && packed_output[0]==0xaa); dispose(&ctx);
    reset_bindings(); packed_mode=5; ctx=context(); bindings[15].context=&ctx; myl_qbe_host_begin(&ctx);
    memset(packed_output,0xaa,256); qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_CONTRACT") && packed_output[0]==0xaa); dispose(&ctx);
    reset_bindings(); packed_mode=6; ctx=context(); myl_qbe_host_begin(&ctx);
    memset(packed_output,0xaa,256); qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_CONTRACT") && packed_output[0]==0xaa); dispose(&ctx);
    reset_bindings(); packed_mode=7; ctx=context(); myl_qbe_host_begin(&ctx);
    memset(packed_output,0xaa,256); qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(!ctx.trap); for (size_t i=0;i<256;i++) assert(packed_output[i]==0); dispose(&ctx);
    reset_bindings(); packed_mode=8; ctx=context(); myl_qbe_host_begin(&ctx);
    memset(packed_output,0xaa,256); qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_CONTRACT") && packed_output[0]==0xaa); dispose(&ctx);

    reset_bindings(); ctx=context(); myl_qbe_host_begin(&ctx);
    unsigned char large_packed_input[2048]={0},large_packed_output[2048]={0};
    large_packed_input[0]=91; const void *large_packed_arguments[]={large_packed_input};
    size_t before_large_allocations=allocations,before_large_frees=frees;
    qbe_host_invoke(&ctx,17,large_packed_arguments,large_packed_output);
    assert(!ctx.trap && large_packed_output[0]==91 && large_packed_output[2047]==91);
    assert(allocations==before_large_allocations+1 && frees==before_large_frees+1); dispose(&ctx);

    reset_bindings(); ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,16,packed_arguments,packed_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_FAILURE") && !packed_invocations && packed_fallback_invocations==1); dispose(&ctx);
    reset_bindings(); providers.host.max_values=513; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_FAILURE") && !packed_invocations && packed_fallback_invocations==1); dispose(&ctx);
    reset_bindings(); providers.host.max_depth=1; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_LIMIT") && !packed_invocations && !packed_fallback_invocations); dispose(&ctx);
    reset_bindings(); providers.host.max_work=1; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,15,packed_arguments,packed_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_LIMIT") && packed_invocations==1); dispose(&ctx);

    reset_bindings(); bindings[0].invoke=malformed; ctx=context();
    myl_qbe_host_begin(&ctx);
    uint64_t input=0,result=0; const void *arguments[]={&input};
    qbe_host_invoke(&ctx,0,arguments,&result);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_CONTRACT")); dispose(&ctx);

    reset_bindings(); bindings[0].invoke=missing_output; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,0,arguments,&result);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_CONTRACT")); dispose(&ctx);
    reset_bindings(); bindings[0].invoke=extra_output; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,0,arguments,&result);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_LIMIT")); dispose(&ctx);
    reset_bindings(); bindings[0].invoke=wrong_type; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,0,arguments,&result);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_CONTRACT")); dispose(&ctx);
    reset_bindings(); bindings[0].invoke=increase_work; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,0,arguments,&result);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_LIMIT")); dispose(&ctx);
    reset_bindings(); bindings[0].invoke=exhaust_work; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,0,arguments,&result);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_LIMIT")); dispose(&ctx);

    reset_bindings(); invalid_u8=1; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,11,u8_arguments,&u8_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_CONTRACT")); dispose(&ctx);

    reset_bindings(); bindings[0].context=&ctx; bindings[0].invoke=reenter; ctx=context(); bindings[0].context=&ctx;
    myl_qbe_host_begin(&ctx); qbe_host_invoke(&ctx,0,arguments,&result);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_CONTRACT")); dispose(&ctx);

    reset_bindings(); providers.host.count=14; ctx=context(); myl_qbe_host_begin(&ctx);
    assert(ctx.trap && !strcmp(ctx.trap,"HostMissingRegistration")); dispose(&ctx);
    reset_bindings(); bindings[9]=bindings[0]; ctx=context(); myl_qbe_host_begin(&ctx);
    assert(ctx.trap && !strcmp(ctx.trap,"HostDuplicateRegistration")); dispose(&ctx);
    reset_bindings(); bindings[0].result="Nine"; ctx=context(); myl_qbe_host_begin(&ctx);
    assert(ctx.trap && !strcmp(ctx.trap,"HostSignatureMismatch")); dispose(&ctx);
    reset_bindings(); bindings[0].grants=0; ctx=context(); myl_qbe_host_begin(&ctx);
    assert(ctx.trap && !strcmp(ctx.trap,"HostCapabilityDenied")); dispose(&ctx);
    reset_bindings(); providers.host.max_values=100001; ctx=context(); myl_qbe_host_begin(&ctx);
    assert(ctx.trap && !strcmp(ctx.trap,"HostInvalidBudget")); dispose(&ctx);
    reset_bindings(); providers.host.max_values=1; bindings[0].invoke=no_capacity; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,0,arguments,&result);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_FAILURE") && scalar_invocations==1); dispose(&ctx);
    reset_bindings(); providers.host.max_values=8; ctx=context(); myl_qbe_host_begin(&ctx);
    after_begin=allocations; qbe_host_invoke(&ctx,13,many_arguments,&many_output);
    assert(!ctx.trap && many_output==28 && allocations==after_begin); dispose(&ctx);
    reset_bindings(); providers.host.max_values=7; bindings[13].invoke=no_capacity_many; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,13,many_arguments,&many_output);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_FAILURE")); dispose(&ctx);

    reset_bindings(); providers.host.max_calls=1; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,0,arguments,&result); qbe_host_invoke(&ctx,0,arguments,&result);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_LIMIT")); dispose(&ctx);
    reset_bindings(); providers.host.max_work=1; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,0,arguments,&result); qbe_host_invoke(&ctx,0,arguments,&result);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_LIMIT")); dispose(&ctx);

    reset_bindings(); failure_code="HostFailure"; ctx=context(); myl_qbe_host_begin(&ctx);
    qbe_host_invoke(&ctx,0,arguments,&result);
    assert(ctx.trap && !strcmp(ctx.trap,"R_HOST_FAILURE")); dispose(&ctx);
    assert(allocations==frees);
    return 0;
}
