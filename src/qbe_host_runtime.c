/* Copied host calls: metadata immutable, budgets and scratch execution-local. */
#include "qbe_runtime.h"
#include "native_providers.h"
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
    size_t value_limit,depth_limit;
    int initialized;
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
    QbeHostState *state=calloc(1,sizeof(*state));
    if (!state) { myl_qbe_fail(ctx,"OutOfMemory"); return; }
    ctx->host_state=state;
    state->registry=ctx->providers?&ctx->providers->host:&qbe_empty_registry;
    const MylangHostRegistry *registry=state->registry;
    if (registry->count && !registry->bindings) { myl_qbe_fail(ctx,"HostMissingRegistration"); return; }
    state->call_limit=registry->max_calls?registry->max_calls:10000;
    state->work=registry->max_work?registry->max_work:1000000;
    state->value_limit=registry->max_values?registry->max_values:65536;
    state->depth_limit=registry->max_depth?registry->max_depth:64;
    if (state->value_limit>100000 || state->depth_limit>128) { myl_qbe_fail(ctx,"HostInvalidBudget"); return; }
    for (size_t i=0;i<registry->count;i++) {
        const char *name=registry->bindings[i].name;
        int found=0;
        for (size_t j=0;name && j<qbe_host_declaration_count;j++) if (!strcmp(name,qbe_host_declarations[j].name)) found=1;
        if (!found) { myl_qbe_fail(ctx,"HostUnknownFunction"); return; }
    }
    for (size_t i=0;i<qbe_host_declaration_count;i++) if (!qbe_host_binding(ctx,state,&qbe_host_declarations[i])) return;
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
    for (size_t i=0;i<node.children;i++) {
        size_t field=type->kind==3?0:type->kind==4?(size_t)node.bits:i;
        size_t next=type->kind==4?child:type->children[field];
        size_t offset=type->kind==3?i*type->stride:type->offsets[field];
        if (!qbe_host_write(ctx,state,next,(const unsigned char *)input+offset,nodes,cursor,depth+1)) return 0;
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
static void qbe_host_invoke(void *context,size_t declaration_index,const void *const *arguments,void *output) {
    MylQbeContext *ctx=context;
    myl_qbe_host_begin(ctx);
    if (ctx->trap) return;
    QbeHostState *state=ctx->host_state;
    const QbeHostDeclaration *declaration=&qbe_host_declarations[declaration_index];
    const MylangHostBinding *binding=qbe_host_binding(ctx,state,declaration);
    if (!binding) return;
    if (state->calls==state->call_limit) { qbe_host_error(ctx,"HostCallLimit"); return; }
    if (!state->work) { qbe_host_error(ctx,"HostWorkLimit"); return; }
    size_t count=0;
    for (size_t i=0;i<declaration->count;i++) if (!qbe_host_write(ctx,state,declaration->parameters[i],arguments[i],NULL,&count,1)) return;
    size_t capacity=qbe_host_nodes(declaration->result,1,state->value_limit-count,state->depth_limit);
    MylangHostNode *nodes=calloc(count+capacity?count+capacity:1,sizeof(*nodes));
    if (!nodes) { qbe_host_error(ctx,"OutOfMemory"); return; }
    size_t cursor=0;
    for (size_t i=0;i<declaration->count;i++) if (!qbe_host_write(ctx,state,declaration->parameters[i],arguments[i],nodes,&cursor,1)) { free(nodes); return; }
    state->calls++; state->work--;
    MylangHostCall call={nodes,count,nodes+count,capacity,0,state->work,0};
    const char *failure=binding->invoke(binding->context,&call);
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
    free(nodes);
}
