//! Fixed C embedding adapter sections shared with the native runtime ABI.
/// Fixed adapter source section.
pub const embed_prelude =
    \\
    \\#include "qbe_runtime.h"
    \\#include "native_host.h"
    \\#include "native_providers.h"
    \\#include "native_embed.h"
    \\#include <string.h>
    \\#include <stdlib.h>
    \\#include <stdatomic.h>
    \\_Static_assert(sizeof(MylangTrapDetail)==sizeof(MylQbeTrapDetail),"trap detail ABI");
    \\_Static_assert(offsetof(MylangTrapDetail,length)==offsetof(MylQbeTrapDetail,length),"trap detail layout");
    \\_Static_assert(offsetof(MylangTrapDetail,operation)==offsetof(MylQbeTrapDetail,operation),"trap detail layout");
    \\static atomic_flag busy = ATOMIC_FLAG_INIT;
    \\static const MylangScalar *inputs;
    \\static size_t selected;
    \\static int host_error(MylangRunResult *out,const char *code) {
    \\    out->status=2;out->code=code;return 2;
    \\}
    \\static int valid_scalar(MylangScalar value,const char *type) {
    \\    if (!value.type || strcmp(value.type,type)) return 0;
    \\    if (!strcmp(type,"bool")) return value.bits<=1;
    \\    if (!strcmp(type,"float")) return 1;
    \\    unsigned width=0;
    \\    for (const char *p=type+1;*p;++p) width=width*10+(unsigned)(*p-'0');
    \\    if (width==64) return 1;
    \\    uint64_t mask=(UINT64_C(1)<<width)-1, raw=value.bits & mask;
    \\    if (*type=='i' && (raw & (UINT64_C(1)<<(width-1)))) raw |= ~mask;
    \\    return value.bits==raw;
    \\}
    \\extern void myl_qbe_host_begin(void *);
    \\static int execute(uint64_t (*entry)(void *),const MylangRunOptions *options,MylangRunResult *out) {
    \\    uint64_t steps=options && options->max_steps ? options->max_steps : MYL_QBE_UNBOUNDED;
    \\    uint64_t frames=options && options->max_frames ? options->max_frames : MYL_QBE_UNBOUNDED;
    \\    MylQbeResult result;
    \\    int stress=options && options->stress ? 1 : 0;
    \\    int status=mylang_qbe_execute_config(entry,steps,frames,stress,options ? options->providers : NULL,myl_qbe_host_begin,&result);
    \\    if (status && result.code && strncmp(result.code,"R_",2)) status=2;
    \\    out->status=status;out->steps=result.steps;out->code=result.code;
    \\    if (!status) memcpy(&out->value,&result.value,sizeof out->value);
    \\    out->frame_count=result.trace_count;out->omitted_frames=result.omitted_frames;
    \\    memcpy(&out->trap_detail,&result.trap_detail,sizeof out->trap_detail);
    \\    for (uint64_t i=0;i<result.trace_count;++i)
    \\        out->frames[i]=(MylangRunFrame){result.trace[i].function,result.trace[i].path,result.trace[i].line,result.trace[i].column};
    \\    if (result.trace_count) {out->path=result.trace[0].path;out->line=result.trace[0].line;out->column=result.trace[0].column;}
    \\    return status;
    \\}
;
/// Fixed adapter source section.
pub const embed_run =
    \\int mylang_native_run_v1(const MylangRunOptions *options, MylangRunResult *out) {
    \\ if (!out) return 2; memset(out,0,sizeof *out);
    \\ if (atomic_flag_test_and_set_explicit(&busy,memory_order_acquire)) return host_error(out,"Busy");
    \\ int status=execute(entry_run,options,out);
    \\ atomic_flag_clear_explicit(&busy,memory_order_release); return status;
    \\}
;
/// Fixed adapter source section.
pub const embed_start =
    \\int mylang_native_call_v1(const char *name,const MylangScalar *arguments,size_t count,
    \\ const MylangRunOptions *options,MylangCallResult *out) {
    \\ if (!out) return 2; memset(out,0,sizeof *out);
    \\ if (!name || (count && !arguments)) return host_error(&out->execution,"InvalidArgument");
    \\ if (atomic_flag_test_and_set_explicit(&busy,memory_order_acquire)) return host_error(&out->execution,"Busy");
    \\ int status=2; const char *return_type=NULL;
    \\
;
/// Fixed adapter source section.
pub const embed_end =
    \\ host_error(&out->execution,"UnknownFunction"); goto done;
    \\ inputs=arguments; status=execute(dispatch,options,&out->execution);
    \\ if (!status) {out->value.type=return_type;memcpy(&out->value.bits,&out->execution.value,sizeof out->value.bits);}
    \\done:
    \\ inputs=NULL; atomic_flag_clear_explicit(&busy,memory_order_release);return status;
    \\}
;
/// Fixed adapter source section.
pub const wire_start =
    \\int mylang_native_call_values_v1(const char *name,const MylangWireNode *arguments,size_t node_count,
    \\ MylangWireNode *output,size_t capacity,const MylangRunOptions *options,MylangWireResult *out) {
    \\ if (!out) return 2;memset(out,0,sizeof *out);
    \\ if (!name || (node_count && !arguments) || (capacity && !output)) return host_error(&out->execution,"InvalidArgument");
    \\ if (node_count>100000 || capacity>100000) return host_error(&out->execution,"WireLimit");
    \\ if (atomic_flag_test_and_set_explicit(&busy,memory_order_acquire)) return host_error(&out->execution,"Busy");
    \\ size_t result_type=0,argument_count=0;const size_t *parameter_types=NULL;
    \\ int status=2;MylangWireNode *prepared=NULL;
    \\ wire_error=NULL;wire_input=arguments;wire_count=node_count;wire_cursor=0;
    \\ memset(wire_arguments,0,sizeof wire_arguments);wire_return=NULL;
    \\
;
/// Fixed adapter source section.
pub const wire_end =
    \\ host_error(&out->execution,"UnknownFunction");goto done;
    \\ for (size_t i=0;i<argument_count;++i) {
    \\  size_t size=wire_types[parameter_types[i]].size;wire_arguments[i]=calloc(size ? size : 1,1);
    \\  if (!wire_arguments[i]) {host_error(&out->execution,"OutOfMemory");goto done;}
    \\  if (!wire_read(parameter_types[i],wire_arguments[i],0)) {host_error(&out->execution,wire_error);goto done;}
    \\ }
    \\ if (wire_cursor!=wire_count) {host_error(&out->execution,"InvalidArgument");goto done;}
    \\ size_t size=wire_types[result_type].size;wire_return=calloc(size ? size : 1,1);
    \\ if (!wire_return) {host_error(&out->execution,"OutOfMemory");goto done;}
    \\ status=execute(wire_dispatch,options,&out->execution);if(status)goto done;
    \\ prepared=calloc(100000,sizeof *prepared);
    \\ if (!prepared) {status=host_error(&out->execution,"OutOfMemory");goto done;}
    \\ size_t needed=0;
    \\ if (!wire_write(result_type,wire_return,prepared,&needed,0)) {status=host_error(&out->execution,wire_error);goto done;}
    \\ out->node_count=needed;
    \\ if (needed>capacity) {status=host_error(&out->execution,"OutputTooSmall");goto done;}
    \\ if (needed) memcpy(output,prepared,needed*sizeof *output);
    \\done:
    \\ free(prepared);free(wire_return);wire_return=NULL;
    \\ for(size_t i=0;i<QBE_WIRE_ARGUMENTS;++i){free(wire_arguments[i]);wire_arguments[i]=NULL;}
    \\ wire_input=NULL;atomic_flag_clear_explicit(&busy,memory_order_release);return status;
    \\}
;
/// Fixed adapter source section.
pub const codec_execute =
    \\static uint64_t co_execute(void *ctx){
    \\ co_context=ctx;((MylQbeContext *)ctx)->adapter_cleanup=co_cleanup;
    \\ for(size_t i=0;i<co_argument_count;++i){
    \\  size_t size=co_types[co_parameter_types[i]].size;co_arguments[i]=calloc(size ? size:1,1);
    \\  if(!co_arguments[i]){co_bad("OutOfMemory");goto cleanup;}
    \\  if(co_injected && co_injected[i]){uint64_t sentinel=co_injected[i];
    \\   if(sentinel>2){if(co_cursor>=co_count){co_bad("InvalidArgument");goto cleanup;}
    \\    sentinel=myl_qbe_stand_in(ctx,sentinel-3,co_input[co_cursor++].bits);if(myl_qbe_failed(ctx))goto cleanup;}
    \\   memcpy(co_arguments[i],&sentinel,size<8?size:8);continue;}
    \\  if(!co_read(co_parameter_types[i],co_arguments[i],0))goto cleanup;
    \\ }
    \\ if(co_cursor!=co_count){co_bad("InvalidArgument");goto cleanup;}
    \\ size_t size=co_types[co_result_type].size;co_return=calloc(size ? size:1,1);
    \\ if(!co_return){co_bad("OutOfMemory");goto cleanup;}
    \\ if(co_charge() && co_public(ctx) && co_root_value(co_result_type,co_return))co_write(co_result_type,co_return,0);
    \\cleanup:
    \\ co_cleanup(ctx);return 0;
    \\}
;
/// Fixed adapter source section.
pub const codec_start =
    \\int mylang_native_call_codecs_v1(const char *name,const MylangWireNode *arguments,size_t node_count,
    \\ MylangWireNode *output,size_t capacity,const MylangCodecOptions *options,MylangCodecResult *out){
    \\ if(!out)return 2;memset(out,0,sizeof *out);MylangRunResult *execution=&out->value.execution;
    \\ if(!name || (node_count && !arguments) || (capacity && !output))return host_error(execution,"InvalidArgument");
    \\ if(node_count>100000 || capacity>100000)return host_error(execution,"WireLimit");
    \\ if(atomic_flag_test_and_set_explicit(&busy,memory_order_acquire))return host_error(execution,"Busy");
    \\ int status=2;co_input=arguments;co_count=node_count;co_cursor=0;co_needed=0;co_rejected=0;co_error=NULL;co_domain=NULL;
    \\ co_capacity=capacity;
    \\ co_calls=0;co_max_calls=options && options->max_calls ? options->max_calls:4096;
    \\ memset(co_arguments,0,sizeof co_arguments);co_return=NULL;co_prepared=NULL;co_context=NULL;co_root_count=0;
    \\
;
/// Fixed adapter source section.
pub const codec_end =
    \\ host_error(execution,"UnknownFunction");goto done;
    \\ co_prepared=calloc(100000,sizeof *co_prepared);if(!co_prepared){host_error(execution,"OutOfMemory");goto done;}
    \\ status=execute(co_execute,options ? &options->run:NULL,execution);
    \\ if(!status && co_error)status=host_error(execution,co_error);
    \\ if(!status || (co_rejected && co_error && !strcmp(co_error,"DomainCodecRejected"))){
    \\  out->value.node_count=co_needed;
    \\  if(co_needed>co_capacity)status=host_error(execution,"OutputTooSmall");
    \\  else if(co_needed)memcpy(output,co_prepared,co_needed*sizeof *output);
    \\ }
    \\done:
    \\ out->calls=co_calls;out->domain=co_domain;out->rejected=co_rejected;
    \\ for(size_t i=0;i<QBE_CODEC_ARGUMENTS;++i){free(co_arguments[i]);co_arguments[i]=NULL;}
    \\ free(co_return);free(co_prepared);co_return=NULL;co_prepared=NULL;co_input=NULL;co_context=NULL;
    \\ atomic_flag_clear_explicit(&busy,memory_order_release);return status;
    \\}
;
