/* Copied host calls: metadata immutable, budgets and scratch execution-local. */
#include "qbe_runtime.h"
#include "native_providers.h"
#include "native_bytes.h"
#include <stdlib.h>
#include <string.h>
typedef struct {
    const char *name;
    size_t size,count,stride;
    unsigned kind,bits,is_signed;
    const size_t *children,*offsets;
} QbeHostType;
typedef struct {
    const char *name;
    const size_t *parameters;
    size_t count,result;
    unsigned effects;
} QbeHostDeclaration;
typedef struct {
    const MylangHostRegistry *registry;
    uint64_t calls,work,call_limit;
    size_t value_limit,depth_limit,payload_limit;
    int initialized,invoking;
    const MylangHostBinding *bound[];
} QbeHostState;
static const QbeHostType qbe_host_types[];
static const QbeHostDeclaration qbe_host_declarations[];
static const size_t qbe_host_declaration_count;
static const MylangHostRegistry qbe_empty_registry={0};
static const MylangHostBinding *qbe_host_binding(void *ctx,QbeHostState *state,const QbeHostDeclaration *declaration) {
    const MylangHostBinding *found=NULL;
    for (size_t i=0;i<state->registry->count;i++) {
        const MylangHostBinding *binding=&state->registry->bindings[i];
        if (!binding->name || strcmp(binding->name,declaration->name)) continue;
        if (found) { myl_qbe_fail(ctx,"HostDuplicateRegistration"); return NULL; }
        found=binding;
    }
    if (!found || !found->invoke) { myl_qbe_fail(ctx,"HostMissingRegistration"); return NULL; }
    if (!found->result || strcmp(found->result,qbe_host_types[declaration->result].name) || found->parameter_count!=declaration->count || found->effects!=declaration->effects || (found->parameter_count && !found->parameters)) {
        myl_qbe_fail(ctx,"HostSignatureMismatch"); return NULL;
    }
    for (size_t i=0;i<declaration->count;i++) if (!found->parameters[i] || strcmp(found->parameters[i],qbe_host_types[declaration->parameters[i]].name)) {
        myl_qbe_fail(ctx,"HostSignatureMismatch"); return NULL;
    }
    if (declaration->effects & ~found->grants) { myl_qbe_fail(ctx,"HostCapabilityDenied"); return NULL; }
    return found;
}
void myl_qbe_host_begin(void *context) {
    MylQbeContext *ctx=context;
    (void)mylang_host_charge;
    if (ctx->host_state) return;
    if (qbe_host_declaration_count>(SIZE_MAX-sizeof(QbeHostState))/sizeof(MylangHostBinding *)) {
        myl_qbe_fail(ctx,"OutOfMemory"); return;
    }
    QbeHostState *state=calloc(1,sizeof(*state)+qbe_host_declaration_count*sizeof(MylangHostBinding *));
    if (!state) { myl_qbe_fail(ctx,"OutOfMemory"); return; }
    ctx->host_state=state;
    state->registry=ctx->providers?&ctx->providers->host:&qbe_empty_registry;
    const MylangHostRegistry *registry=state->registry;
    if (registry->count && !registry->bindings) { myl_qbe_fail(ctx,"HostMissingRegistration"); return; }
    state->call_limit=registry->max_calls?registry->max_calls:10000;
    state->work=registry->max_work?registry->max_work:1000000;
    state->value_limit=registry->max_values?registry->max_values:65536;
    state->depth_limit=registry->max_depth?registry->max_depth:64;
    state->payload_limit=registry->max_payload?registry->max_payload:1024u*1024u;
    if (state->value_limit>100000 || state->depth_limit>128 || state->payload_limit>64u*1024u*1024u) { myl_qbe_fail(ctx,"HostInvalidBudget"); return; }
    for (size_t i=0;i<registry->count;i++) {
        const char *name=registry->bindings[i].name;
        int found=0;
        for (size_t j=0;name && j<qbe_host_declaration_count;j++) if (!strcmp(name,qbe_host_declarations[j].name)) found=1;
        if (!found) { myl_qbe_fail(ctx,"HostUnknownFunction"); return; }
    }
    for (size_t i=0;i<qbe_host_declaration_count;i++) {
        state->bound[i]=qbe_host_binding(ctx,state,&qbe_host_declarations[i]);
        if (!state->bound[i]) return;
    }
    state->initialized=1;
}
static int qbe_host_error(void *ctx,const char *code) {
    if (!strcmp(code,"OutOfMemory")) myl_qbe_fail(ctx,code);
    else if (!strcmp(code,"HostCallLimit") || !strcmp(code,"HostWorkLimit") || !strcmp(code,"ValueCountLimit") || !strcmp(code,"ValueDepthLimit")) myl_qbe_fail(ctx,"R_HOST_LIMIT");
    else if (!strcmp(code,"HostFailure")) myl_qbe_fail(ctx,"R_HOST_FAILURE");
    else myl_qbe_fail(ctx,"R_HOST_CONTRACT");
    return 0;
}
static uint64_t qbe_host_word(const void *input,const QbeHostType *type) {
    uint64_t bits=0;
    memcpy(&bits,input,type->size);
    if (type->is_signed && type->bits<64 && (bits&(UINT64_C(1)<<(type->bits-1)))) bits|=UINT64_MAX<<type->bits;
    return bits;
}
static int qbe_host_valid(const QbeHostType *type,uint64_t bits) {
    if (type->bits==64) return 1;
    uint64_t maximum=(UINT64_C(1)<<(type->bits-type->is_signed))-1;
    return bits<=maximum || (type->is_signed && bits>=~maximum);
}
static int qbe_host_write(void *ctx,QbeHostState *state,size_t index,const void *input,MylangHostNode *nodes,size_t *cursor,size_t depth) {
    if (depth>state->depth_limit) return qbe_host_error(ctx,"ValueDepthLimit");
    if (*cursor==state->value_limit) return qbe_host_error(ctx,"ValueCountLimit");
    const QbeHostType *type=&qbe_host_types[index];
    MylangHostNode node={type->name,0,type->count};
    size_t child=SIZE_MAX;
    if (type->kind==1) { node.bits=qbe_host_word(input,type); node.children=0; }
    else if (type->kind==4) {
        uint32_t tag; memcpy(&tag,input,4); node.bits=tag;
        if (tag>=type->count) return qbe_host_error(ctx,"InvalidDataValue");
        child=type->children[tag]; node.children=child!=SIZE_MAX;
    } else if (type->kind!=2 && type->kind!=3 && type->kind!=5) return qbe_host_error(ctx,"NotDataType");
    if (nodes) nodes[*cursor]=node;
    (*cursor)++;
    size_t backing=*cursor;
    for (size_t i=0;i<node.children;i++) {
        size_t field=type->kind==3?0:type->kind==4?(size_t)node.bits:i;
        size_t next=type->kind==4?child:type->children[field];
        size_t offset=type->kind==3?i*type->stride:type->offsets[field];
        if (!qbe_host_write(ctx,state,next,(const unsigned char *)input+offset,nodes,cursor,depth+1)) return 0;
    }
    /* FLOAT-NAN-OBSERVED-6: a binary64 domain (the one domain with a width) is
       a host-visible bit pattern, so any NaN crosses as the canonical quiet NaN
       whatever payload and sign guest arithmetic gave it. */
    if (nodes && type->kind==5 && type->bits==64 && backing<*cursor) {
        uint64_t bits=nodes[backing].bits;
        if ((bits&UINT64_C(0x7ff0000000000000))==UINT64_C(0x7ff0000000000000) && (bits&UINT64_C(0x000fffffffffffff)))
            nodes[backing].bits=UINT64_C(0x7ff8000000000000);
    }
    return 1;
}
static int qbe_host_read(void *ctx,QbeHostState *state,size_t index,void *output,const MylangHostNode *nodes,size_t count,size_t *cursor,size_t depth) {
    if (depth>state->depth_limit) return qbe_host_error(ctx,"ValueDepthLimit");
    if (*cursor==count) return qbe_host_error(ctx,"InvalidDataValue");
    const QbeHostType *type=&qbe_host_types[index];
    const MylangHostNode *node=&nodes[(*cursor)++];
    if (!node->type || strcmp(node->type,type->name)) return qbe_host_error(ctx,"ValueTypeMismatch");
    if (type->kind==1) {
        if (node->children || !qbe_host_valid(type,node->bits)) return qbe_host_error(ctx,"InvalidDataValue");
        memcpy(output,&node->bits,type->size); return 1;
    }
    size_t children=type->count,child=SIZE_MAX;
    if (type->kind==4) {
        if (node->bits>=type->count) return qbe_host_error(ctx,"InvalidDataValue");
        child=type->children[node->bits]; children=child!=SIZE_MAX;
        uint32_t tag=(uint32_t)node->bits; memcpy(output,&tag,4);
    } else if ((type->kind!=2 && type->kind!=3 && type->kind!=5) || node->bits) return qbe_host_error(ctx,"InvalidDataValue");
    if (node->children!=children) return qbe_host_error(ctx,"InvalidDataValue");
    for (size_t i=0;i<children;i++) {
        size_t field=type->kind==3?0:type->kind==4?(size_t)node->bits:i;
        size_t next=type->kind==4?child:type->children[field];
        size_t offset=type->kind==3?i*type->stride:type->offsets[field];
        if (!qbe_host_read(ctx,state,next,(unsigned char *)output+offset,nodes,count,cursor,depth+1)) return 0;
    }
    return 1;
}
static size_t qbe_host_nodes(size_t index,size_t depth,size_t limit,size_t depth_limit) {
    if (!limit || depth>depth_limit) return limit;
    const QbeHostType *type=&qbe_host_types[index];
    if (type->kind==1) return 1;
    size_t total=1;
    if (type->kind==4) {
        size_t largest=0;
        for (size_t i=0;i<type->count;i++) if (type->children[i]!=SIZE_MAX) {
            size_t child=qbe_host_nodes(type->children[i],depth+1,limit-1,depth_limit);
            if (child>largest) largest=child;
        }
        return 1+largest;
    }
    if (type->kind==3) {
        size_t child=qbe_host_nodes(type->children[0],depth+1,limit-1,depth_limit);
        if (child && type->count>(limit-1)/child) return limit;
        return 1+type->count*child;
    }
    for (size_t i=0;i<type->count;i++) {
        total+=qbe_host_nodes(type->children[i],depth+1,limit-total,depth_limit);
        if (total==limit) return limit;
    }
    return total;
}
static int qbe_host_scalar_call(const QbeHostState *state,const QbeHostDeclaration *declaration) {
    if (state->depth_limit<1 || declaration->count>=state->value_limit || declaration->count>=8 || qbe_host_types[declaration->result].kind!=1) return 0;
    for (size_t i=0;i<declaration->count;i++) if (qbe_host_types[declaration->parameters[i]].kind!=1) return 0;
    return 1;
}
/* Kind 6 is the immutable `bytes` byte string: one owned payload the runtime
   copies in both directions. Its guest value is a single managed pointer word,
   so the schema carries no octet count and the payload ceiling bounds it. */
static int qbe_host_payload_type(size_t index) {
    return qbe_host_types[index].kind==6;
}
static int qbe_host_packed_type(size_t index,size_t *nodes,size_t depth,size_t depth_limit) {
    const QbeHostType *type=&qbe_host_types[index];
    if (depth>depth_limit) return 0;
    if (type->kind==6) {
        if (type->size!=sizeof(myl_native_bytes *)) return 0;
        *nodes=1; return 1;
    }
    if (type->kind==1) {
        if ((type->bits!=8 && type->bits!=16 && type->bits!=32 && type->bits!=64) || type->size!=type->bits/8) return 0;
        *nodes=1; return 1;
    }
    if (type->kind!=3 || type->stride!=1 || type->size!=type->count ||
        !type->children || !type->offsets || type->offsets[0]!=0) return 0;
    const QbeHostType *element=&qbe_host_types[type->children[0]];
    if (element->kind!=1 || element->size!=1 || element->bits!=8 || element->is_signed) return 0;
    if (depth+1>depth_limit || type->count==SIZE_MAX) return 0;
    *nodes=1+type->count;
    return 1;
}
static int qbe_host_packed_call(QbeHostState *state,const QbeHostDeclaration *declaration,const MylangHostBinding *binding,size_t *bytes) {
    if (!binding->invoke_packed) return 0;
    size_t nodes=0,total=0;
    for (size_t i=0;i<declaration->count;i++) {
        if (!qbe_host_packed_type(declaration->parameters[i],&nodes,1,state->depth_limit) ||
            nodes>state->value_limit-total) return 0;
        total+=nodes;
        size_t size=qbe_host_payload_type(declaration->parameters[i])?0:qbe_host_types[declaration->parameters[i]].size;
        if (size>SIZE_MAX-*bytes) return 0;
        *bytes+=size;
    }
    if (!qbe_host_packed_type(declaration->result,&nodes,1,state->depth_limit) ||
        nodes>state->value_limit-total) return 0;
    size_t size=qbe_host_payload_type(declaration->result)?0:qbe_host_types[declaration->result].size;
    if (size>SIZE_MAX-*bytes) return 0;
    *bytes+=size;
    /* Only the fixed part of the scratch is bounded here; a `bytes` payload is
       measured at call time against the registry's payload ceiling. */
    if (*bytes>1024u*1024u) return 0;
    return 1;
}
/* One argument's copied payload: a fixed shape's own storage, or the octets an
   immutable byte string currently holds. */
typedef struct { const unsigned char *octets; size_t size; } QbeHostPayload;
static int qbe_host_payload_of(void *ctx,QbeHostState *state,size_t index,const void *argument,QbeHostPayload *payload) {
    if (!qbe_host_payload_type(index)) {
        payload->octets=argument; payload->size=qbe_host_types[index].size; return 1;
    }
    myl_native_bytes *value=NULL;
    memcpy(&value,argument,sizeof value);
    if (!value) return qbe_host_error(ctx,"InvalidDataValue");
    size_t length=0;
    payload->octets=myl_native_bytes_range(value,0,INT64_MAX,&length);
    if (length>state->payload_limit) return qbe_host_error(ctx,"ValueCountLimit");
    payload->size=length;
    return 1;
}
/* Copy a callback's published octets into a fresh guest byte string. Those
   octets belong to the callback, so the runtime only reads them, and a sticky
   trap or a refused allocation publishes no value. */
static void qbe_host_publish_payload(void *ctx,QbeHostState *state,const MylangHostPackedCall *call,void *output) {
    if (call->output.size!=call->output_written || (!call->output.bytes && call->output.size)) { qbe_host_error(ctx,"InvalidDataValue"); return; }
    if (call->output.size>state->payload_limit) { qbe_host_error(ctx,"ValueCountLimit"); return; }
    if (((MylQbeContext *)ctx)->trap) return;
    myl_native_bytes *value=myl_native_bytes_new(myl_qbe_heap(ctx),call->output.bytes,call->output.size);
    if (!value) { myl_qbe_fail_allocation(ctx); return; }
    memcpy(output,&value,sizeof value);
}
static void qbe_host_invoke_packed(void *ctx,QbeHostState *state,const QbeHostDeclaration *declaration,const MylangHostBinding *binding,const void *const *arguments,void *output) {
    if (declaration->count==SIZE_MAX) { qbe_host_error(ctx,"OutOfMemory"); return; }
    size_t value_count=declaration->count+1;
    if (value_count>SIZE_MAX/sizeof(MylangHostPackedValue)) { qbe_host_error(ctx,"OutOfMemory"); return; }
    size_t headers=value_count*sizeof(MylangHostPackedValue);
    /* Measure every argument before copying one, so an oversized byte string is
       refused before the callback can observe any of them. */
    size_t bytes=0;
    for (size_t i=0;i<declaration->count;i++) {
        QbeHostPayload payload;
        if (!qbe_host_payload_of(ctx,state,declaration->parameters[i],arguments[i],&payload)) return;
        if (payload.size>SIZE_MAX-bytes) { qbe_host_error(ctx,"OutOfMemory"); return; }
        bytes+=payload.size;
    }
    size_t output_size=qbe_host_payload_type(declaration->result)?0:qbe_host_types[declaration->result].size;
    if (output_size>SIZE_MAX-bytes) { qbe_host_error(ctx,"OutOfMemory"); return; }
    bytes+=output_size;
    if (bytes>SIZE_MAX-headers) { qbe_host_error(ctx,"OutOfMemory"); return; }
    union { max_align_t alignment; unsigned char bytes[1024]; } local;
    int owned=headers+bytes>sizeof local.bytes;
    unsigned char *scratch=owned?myl_qbe_frame_allocate(ctx,headers+bytes):local.bytes;
    if (!scratch) return;
    memset(scratch,0,headers);
    MylangHostPackedValue *values=(MylangHostPackedValue *)scratch;
    unsigned char *cursor=scratch+headers;
    for (size_t i=0;i<declaration->count;i++) {
        QbeHostPayload payload={NULL,0};
        (void)qbe_host_payload_of(ctx,state,declaration->parameters[i],arguments[i],&payload);
        values[i]=(MylangHostPackedValue){cursor,payload.size};
        if (payload.size) memcpy(cursor,payload.octets,payload.size);
        cursor+=payload.size;
    }
    /* A `bytes` result starts as an empty output the callback replaces with its
       own octets; every other shape keeps the zeroed scratch it is given. */
    void *expected_output=output_size?cursor:NULL;
    if (output_size) memset(cursor,0,output_size);
    values[declaration->count]=(MylangHostPackedValue){expected_output,output_size};
    state->calls++; state->work--;
    MylangHostPackedCall call={values,declaration->count,values[declaration->count],0,state->work,0};
    state->invoking=1;
    const char *failure=binding->invoke_packed(binding->context,&call);
    state->invoking=0;
    if (call.exhausted || call.work_remaining>state->work) qbe_host_error(ctx,"HostWorkLimit");
    else {
        state->work=call.work_remaining;
        if (failure) qbe_host_error(ctx,failure);
        else if (qbe_host_payload_type(declaration->result)) qbe_host_publish_payload(ctx,state,&call,output);
        else if (call.output.bytes!=expected_output || call.output.size!=output_size || call.output_written!=output_size) qbe_host_error(ctx,"InvalidDataValue");
        else if (!((MylQbeContext *)ctx)->trap && output_size) memcpy(output,call.output.bytes,output_size);
    }
    if (owned) myl_qbe_frame_release(ctx,scratch);
}
static void qbe_host_invoke_scalar(void *ctx,QbeHostState *state,const QbeHostDeclaration *declaration,const MylangHostBinding *binding,const void *const *arguments,void *output) {
    MylangHostNode nodes[8]={0};
    for (size_t i=0;i<declaration->count;i++) {
        const QbeHostType *type=&qbe_host_types[declaration->parameters[i]];
        nodes[i]=(MylangHostNode){type->name,qbe_host_word(arguments[i],type),0};
    }
    state->calls++; state->work--;
    MylangHostCall call={nodes,declaration->count,nodes+declaration->count,1,0,state->work,0};
    state->invoking=1;
    const char *failure=binding->invoke(binding->context,&call);
    state->invoking=0;
    if (call.exhausted || call.work_remaining>state->work) qbe_host_error(ctx,"HostWorkLimit");
    else {
        state->work=call.work_remaining;
        if (failure) qbe_host_error(ctx,failure);
        else if (call.output_nodes>1) qbe_host_error(ctx,"ValueCountLimit");
        else if (call.output_nodes!=1) qbe_host_error(ctx,"InvalidDataValue");
        else {
            const QbeHostType *type=&qbe_host_types[declaration->result];
            const MylangHostNode *node=&nodes[declaration->count];
            if (!node->type || strcmp(node->type,type->name)) qbe_host_error(ctx,"ValueTypeMismatch");
            else if (node->children || !qbe_host_valid(type,node->bits)) qbe_host_error(ctx,"InvalidDataValue");
            else memcpy(output,&node->bits,type->size);
        }
    }
}
static void qbe_host_invoke(void *context,size_t declaration_index,const void *const *arguments,void *output) {
    MylQbeContext *ctx=context;
    myl_qbe_host_begin(ctx);
    if (ctx->trap) return;
    QbeHostState *state=ctx->host_state;
    const QbeHostDeclaration *declaration=&qbe_host_declarations[declaration_index];
    const MylangHostBinding *binding=state->bound[declaration_index];
    if (state->invoking) { qbe_host_error(ctx,"HostReentry"); return; }
    if (state->calls==state->call_limit) { qbe_host_error(ctx,"HostCallLimit"); return; }
    if (!state->work) { qbe_host_error(ctx,"HostWorkLimit"); return; }
    size_t packed_bytes=0;
    if (qbe_host_packed_call(state,declaration,binding,&packed_bytes)) {
        qbe_host_invoke_packed(ctx,state,declaration,binding,arguments,output);
        return;
    }
    if (qbe_host_scalar_call(state,declaration)) {
        qbe_host_invoke_scalar(ctx,state,declaration,binding,arguments,output);
        return;
    }
    size_t count=0;
    for (size_t i=0;i<declaration->count;i++) if (!qbe_host_write(ctx,state,declaration->parameters[i],arguments[i],NULL,&count,1)) return;
    size_t capacity=qbe_host_nodes(declaration->result,1,state->value_limit-count,state->depth_limit);
    if (capacity>SIZE_MAX-count) { qbe_host_error(ctx,"OutOfMemory"); return; }
    size_t needed=count+capacity?count+capacity:1;
    MylangHostNode local_nodes[8]={0};
    MylangHostNode *nodes=needed<=8?local_nodes:calloc(needed,sizeof(*nodes));
    if (!nodes) { qbe_host_error(ctx,"OutOfMemory"); return; }
    size_t cursor=0;
    for (size_t i=0;i<declaration->count;i++) if (!qbe_host_write(ctx,state,declaration->parameters[i],arguments[i],nodes,&cursor,1)) {
        if (nodes!=local_nodes) free(nodes);
        return;
    }
    state->calls++; state->work--;
    MylangHostCall call={nodes,count,nodes+count,capacity,0,state->work,0};
    state->invoking=1;
    const char *failure=binding->invoke(binding->context,&call);
    state->invoking=0;
    if (call.exhausted || call.work_remaining>state->work) qbe_host_error(ctx,"HostWorkLimit");
    else {
        state->work=call.work_remaining;
        if (failure) qbe_host_error(ctx,failure);
        else if (call.output_nodes>capacity) qbe_host_error(ctx,"ValueCountLimit");
        else {
            cursor=0;
            if (qbe_host_read(ctx,state,declaration->result,output,nodes+count,call.output_nodes,&cursor,1) && cursor!=call.output_nodes) qbe_host_error(ctx,"InvalidDataValue");
        }
    }
    if (nodes!=local_nodes) free(nodes);
}
