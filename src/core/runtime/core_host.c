#include <stddef.h>
/* Copied-node and packed-copy Host algorithms ported from qbe_host_runtime.c.
 * Core boxes own guest results. Scratch and compiler metadata caches are retired
 * on normal exit or trap; no old context, heap, runtime or byte-string ABI remains. */
typedef struct CoreHostScratch {struct CoreHostScratch *next;max_align_t alignment;unsigned char data[];} CoreHostScratch;
static CoreHostScratch *core_host_scratch_head;
static void *core_host_scratch(size_t bytes){CoreHostScratch *item=malloc(sizeof(*item)+bytes);if(!item)out_of_memory();item->next=core_host_scratch_head;core_host_scratch_head=item;return item->data;}
static void core_host_scratch_free(void *bytes){CoreHostScratch **at=&core_host_scratch_head;while(*at&&(*at)->data!=bytes)at=&(*at)->next;if(!*at)core_io_fail("R_HOST_CONTRACT");CoreHostScratch *item=*at;*at=item->next;free(item);}
static void core_host_fail(const char *code){if(!strcmp(code,"OutOfMemory"))out_of_memory();core_io_fail(code);}
typedef struct {
    const char *name;
    size_t size,count,stride;
    unsigned kind,bits,is_signed;
    const size_t *children,*offsets;
} CoreHostType;
typedef struct {
    const char *name;
    const size_t *parameters;
    size_t count,result;
    unsigned effects;
} CoreHostDeclaration;
typedef struct {
    const CoreIoHostRegistry *registry;
    uint64_t calls,work,call_limit;
    size_t value_limit,depth_limit,payload_limit;
    int initialized,invoking;
    const CoreIoHostBinding **bound;
} CoreHostState;
static const CoreHostType *core_host_types;
static const CoreHostDeclaration *core_host_declarations;
static const CoreIoHostBinding *core_host_binding(void *ctx,CoreHostState *state,const CoreHostDeclaration *declaration) {
    const CoreIoHostBinding *found=NULL;
    for (size_t i=0;i<state->registry->count;i++) {
        const CoreIoHostBinding *binding=&state->registry->bindings[i];
        if (!binding->name || strcmp(binding->name,declaration->name)) continue;
        if (found) { core_host_fail("HostDuplicateRegistration"); return NULL; }
        found=binding;
    }
    if (!found || !found->invoke) { core_host_fail("HostMissingRegistration"); return NULL; }
    if (!found->result || strcmp(found->result,core_host_types[declaration->result].name) || found->parameter_count!=declaration->count || found->effects!=declaration->effects || (found->parameter_count && !found->parameters)) {
        core_host_fail("HostSignatureMismatch"); return NULL;
    }
    for (size_t i=0;i<declaration->count;i++) if (!found->parameters[i] || strcmp(found->parameters[i],core_host_types[declaration->parameters[i]].name)) {
        core_host_fail("HostSignatureMismatch"); return NULL;
    }
    if (declaration->effects & ~found->grants) { core_host_fail("HostCapabilityDenied"); return NULL; }
    return found;
}
static int core_host_error(void *ctx,const char *code) {
    if (!strcmp(code,"OutOfMemory")) core_host_fail(code);
    else if (!strcmp(code,"HostCallLimit") || !strcmp(code,"HostWorkLimit") || !strcmp(code,"ValueCountLimit") || !strcmp(code,"ValueDepthLimit")) core_host_fail("R_HOST_LIMIT");
    else if (!strcmp(code,"HostFailure")) core_host_fail("R_HOST_FAILURE");
    else core_host_fail("R_HOST_CONTRACT");
    return 0;
}
static uint64_t core_host_word(const void *input,const CoreHostType *type) {
    uint64_t bits=0;
    memcpy(&bits,input,type->size);
    if (type->is_signed && type->bits<64 && (bits&(UINT64_C(1)<<(type->bits-1)))) bits|=UINT64_MAX<<type->bits;
    return bits;
}
static int core_host_valid(const CoreHostType *type,uint64_t bits) {
    if (type->bits==64) return 1;
    uint64_t maximum=(UINT64_C(1)<<(type->bits-type->is_signed))-1;
    return bits<=maximum || (type->is_signed && bits>=~maximum);
}
static int core_host_write(void *ctx,CoreHostState *state,size_t index,const void *input,CoreIoHostNode *nodes,size_t *cursor,size_t depth) {
    if (depth>state->depth_limit) return core_host_error(ctx,"ValueDepthLimit");
    if (*cursor==state->value_limit) return core_host_error(ctx,"ValueCountLimit");
    const CoreHostType *type=&core_host_types[index];
    CoreIoHostNode node={type->name,0,type->count};
    size_t child=SIZE_MAX;
    if (type->kind==1) { node.bits=core_host_word(input,type); node.children=0; }
    else if (type->kind==4) {
        uint32_t tag; memcpy(&tag,input,4); node.bits=tag;
        if (tag>=type->count) return core_host_error(ctx,"InvalidDataValue");
        child=type->children[tag]; node.children=child!=SIZE_MAX;
    } else if (type->kind!=2 && type->kind!=3 && type->kind!=5) return core_host_error(ctx,"NotDataType");
    if (nodes) nodes[*cursor]=node;
    (*cursor)++;
    size_t backing=*cursor;
    for (size_t i=0;i<node.children;i++) {
        size_t field=type->kind==3?0:type->kind==4?(size_t)node.bits:i;
        size_t next=type->kind==4?child:type->children[field];
        size_t offset=type->kind==3?i*type->stride:type->offsets[field];
        if (!core_host_write(ctx,state,next,(const unsigned char *)input+offset,nodes,cursor,depth+1)) return 0;
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
static int core_host_read(void *ctx,CoreHostState *state,size_t index,void *output,const CoreIoHostNode *nodes,size_t count,size_t *cursor,size_t depth) {
    if (depth>state->depth_limit) return core_host_error(ctx,"ValueDepthLimit");
    if (*cursor==count) return core_host_error(ctx,"InvalidDataValue");
    const CoreHostType *type=&core_host_types[index];
    const CoreIoHostNode *node=&nodes[(*cursor)++];
    if (!node->type || strcmp(node->type,type->name)) return core_host_error(ctx,"ValueTypeMismatch");
    if (type->kind==1) {
        if (node->children || !core_host_valid(type,node->bits)) return core_host_error(ctx,"InvalidDataValue");
        memcpy(output,&node->bits,type->size); return 1;
    }
    size_t children=type->count,child=SIZE_MAX;
    if (type->kind==4) {
        if (node->bits>=type->count) return core_host_error(ctx,"InvalidDataValue");
        child=type->children[node->bits]; children=child!=SIZE_MAX;
        uint32_t tag=(uint32_t)node->bits; memcpy(output,&tag,4);
    } else if ((type->kind!=2 && type->kind!=3 && type->kind!=5) || node->bits) return core_host_error(ctx,"InvalidDataValue");
    if (node->children!=children) return core_host_error(ctx,"InvalidDataValue");
    for (size_t i=0;i<children;i++) {
        size_t field=type->kind==3?0:type->kind==4?(size_t)node->bits:i;
        size_t next=type->kind==4?child:type->children[field];
        size_t offset=type->kind==3?i*type->stride:type->offsets[field];
        if (!core_host_read(ctx,state,next,(unsigned char *)output+offset,nodes,count,cursor,depth+1)) return 0;
    }
    return 1;
}
static size_t core_host_nodes(size_t index,size_t depth,size_t limit,size_t depth_limit) {
    if (!limit || depth>depth_limit) return limit;
    const CoreHostType *type=&core_host_types[index];
    if (type->kind==1) return 1;
    size_t total=1;
    if (type->kind==4) {
        size_t largest=0;
        for (size_t i=0;i<type->count;i++) if (type->children[i]!=SIZE_MAX) {
            size_t child=core_host_nodes(type->children[i],depth+1,limit-1,depth_limit);
            if (child>largest) largest=child;
        }
        return 1+largest;
    }
    if (type->kind==3) {
        size_t child=core_host_nodes(type->children[0],depth+1,limit-1,depth_limit);
        if (child && type->count>(limit-1)/child) return limit;
        return 1+type->count*child;
    }
    for (size_t i=0;i<type->count;i++) {
        total+=core_host_nodes(type->children[i],depth+1,limit-total,depth_limit);
        if (total==limit) return limit;
    }
    return total;
}
static int core_host_scalar_call(const CoreHostState *state,const CoreHostDeclaration *declaration) {
    if (state->depth_limit<1 || declaration->count>=state->value_limit || declaration->count>=8 || core_host_types[declaration->result].kind!=1) return 0;
    for (size_t i=0;i<declaration->count;i++) if (core_host_types[declaration->parameters[i]].kind!=1) return 0;
    return 1;
}
/* Kind 6 is the immutable `bytes` byte string: one owned payload the runtime
   copies in both directions. Its guest value is a single managed pointer word,
   so the schema carries no octet count and the payload ceiling bounds it. */
static int core_host_payload_type(size_t index) {
    return core_host_types[index].kind==6;
}
static int core_host_packed_type(size_t index,size_t *nodes,size_t depth,size_t depth_limit) {
    const CoreHostType *type=&core_host_types[index];
    if (depth>depth_limit) return 0;
    if (type->kind==6) {
        if (type->size!=sizeof(myl_block *)) return 0;
        *nodes=1; return 1;
    }
    if (type->kind==1) {
        if ((type->bits!=8 && type->bits!=16 && type->bits!=32 && type->bits!=64) || type->size!=type->bits/8) return 0;
        *nodes=1; return 1;
    }
    if (type->kind!=3 || type->stride!=1 || type->size!=type->count ||
        !type->children || !type->offsets || type->offsets[0]!=0) return 0;
    const CoreHostType *element=&core_host_types[type->children[0]];
    if (element->kind!=1 || element->size!=1 || element->bits!=8 || element->is_signed) return 0;
    if (depth+1>depth_limit || type->count==SIZE_MAX) return 0;
    *nodes=1+type->count;
    return 1;
}
static int core_host_packed_call(CoreHostState *state,const CoreHostDeclaration *declaration,const CoreIoHostBinding *binding,size_t *bytes) {
    if (!binding->invoke_packed) return 0;
    size_t nodes=0,total=0;
    for (size_t i=0;i<declaration->count;i++) {
        if (!core_host_packed_type(declaration->parameters[i],&nodes,1,state->depth_limit) ||
            nodes>state->value_limit-total) return 0;
        total+=nodes;
        size_t size=core_host_payload_type(declaration->parameters[i])?0:core_host_types[declaration->parameters[i]].size;
        if (size>SIZE_MAX-*bytes) return 0;
        *bytes+=size;
    }
    if (!core_host_packed_type(declaration->result,&nodes,1,state->depth_limit) ||
        nodes>state->value_limit-total) return 0;
    size_t size=core_host_payload_type(declaration->result)?0:core_host_types[declaration->result].size;
    if (size>SIZE_MAX-*bytes) return 0;
    *bytes+=size;
    /* Only the fixed part of the scratch is bounded here; a `bytes` payload is
       measured at call time against the registry's payload ceiling. */
    if (*bytes>1024u*1024u) return 0;
    return 1;
}
/* One argument's copied payload: a fixed shape's own storage, or the octets an
   immutable byte string currently holds. */
typedef struct { const unsigned char *octets; size_t size; } CoreHostPayload;
static int core_host_payload_of(void *ctx,CoreHostState *state,size_t index,const void *argument,CoreHostPayload *payload) {
    if (!core_host_payload_type(index)) {
        payload->octets=argument; payload->size=core_host_types[index].size; return 1;
    }
    myl_block *value=NULL;
    memcpy(&value,argument,sizeof value);
    if (!value) return core_host_error(ctx,"InvalidDataValue");
    size_t length=(size_t)value->len;
    payload->octets=block_data(value);
    if (length>state->payload_limit) return core_host_error(ctx,"ValueCountLimit");
    payload->size=length;
    return 1;
}
/* Copy a callback's published octets into a fresh guest byte string. Those
   octets belong to the callback, so the runtime only reads them, and a sticky
   trap or a refused allocation publishes no value. */
static void core_host_publish_payload(void *ctx,CoreHostState *state,const CoreIoHostPackedCall *call,void *output) {
    if (call->output.size!=call->output_written || (!call->output.bytes && call->output.size)) { core_host_error(ctx,"InvalidDataValue"); return; }
    if (call->output.size>state->payload_limit) { core_host_error(ctx,"ValueCountLimit"); return; }
    
    myl_block *value=core_io_string(call->output.bytes,call->output.size,0);
    if (!value) out_of_memory();
    memcpy(output,&value,sizeof value);
}
static void core_host_invoke_packed(void *ctx,CoreHostState *state,const CoreHostDeclaration *declaration,const CoreIoHostBinding *binding,const void *const *arguments,void *output) {
    if (declaration->count==SIZE_MAX) { core_host_error(ctx,"OutOfMemory"); return; }
    size_t value_count=declaration->count+1;
    if (value_count>SIZE_MAX/sizeof(CoreIoHostPackedValue)) { core_host_error(ctx,"OutOfMemory"); return; }
    size_t headers=value_count*sizeof(CoreIoHostPackedValue);
    /* Measure every argument before copying one, so an oversized byte string is
       refused before the callback can observe any of them. */
    size_t bytes=0;
    for (size_t i=0;i<declaration->count;i++) {
        CoreHostPayload payload;
        if (!core_host_payload_of(ctx,state,declaration->parameters[i],arguments[i],&payload)) return;
        if (payload.size>SIZE_MAX-bytes) { core_host_error(ctx,"OutOfMemory"); return; }
        bytes+=payload.size;
    }
    size_t output_size=core_host_payload_type(declaration->result)?0:core_host_types[declaration->result].size;
    if (output_size>SIZE_MAX-bytes) { core_host_error(ctx,"OutOfMemory"); return; }
    bytes+=output_size;
    if (bytes>SIZE_MAX-headers) { core_host_error(ctx,"OutOfMemory"); return; }
    union { max_align_t alignment; unsigned char bytes[1024]; } local;
    int owned=headers+bytes>sizeof local.bytes;
    unsigned char *scratch=owned?core_host_scratch(headers+bytes):local.bytes;
    if (!scratch) return;
    memset(scratch,0,headers);
    CoreIoHostPackedValue *values=(CoreIoHostPackedValue *)scratch;
    unsigned char *cursor=scratch+headers;
    for (size_t i=0;i<declaration->count;i++) {
        CoreHostPayload payload={NULL,0};
        (void)core_host_payload_of(ctx,state,declaration->parameters[i],arguments[i],&payload);
        values[i]=(CoreIoHostPackedValue){cursor,payload.size};
        if (payload.size) memcpy(cursor,payload.octets,payload.size);
        cursor+=payload.size;
    }
    /* A `bytes` result starts as an empty output the callback replaces with its
       own octets; every other shape keeps the zeroed scratch it is given. */
    void *expected_output=output_size?cursor:NULL;
    if (output_size) memset(cursor,0,output_size);
    values[declaration->count]=(CoreIoHostPackedValue){expected_output,output_size};
    state->calls++; state->work--;
    CoreIoHostPackedCall call={values,declaration->count,values[declaration->count],0,state->work,0};
    state->invoking=1;
    const char *failure=binding->invoke_packed(binding->context,&call);
    state->invoking=0;
    if (call.exhausted || call.work_remaining>state->work) core_host_error(ctx,"HostWorkLimit");
    else {
        state->work=call.work_remaining;
        if (failure) core_host_error(ctx,failure);
        else if (core_host_payload_type(declaration->result)) core_host_publish_payload(ctx,state,&call,output);
        else if (call.output.bytes!=expected_output || call.output.size!=output_size || call.output_written!=output_size) core_host_error(ctx,"InvalidDataValue");
        else if (output_size) memcpy(output,call.output.bytes,output_size);
    }
    if (owned) core_host_scratch_free(scratch);
}
static void core_host_invoke_scalar(void *ctx,CoreHostState *state,const CoreHostDeclaration *declaration,const CoreIoHostBinding *binding,const void *const *arguments,void *output) {
    CoreIoHostNode nodes[8]={0};
    for (size_t i=0;i<declaration->count;i++) {
        const CoreHostType *type=&core_host_types[declaration->parameters[i]];
        nodes[i]=(CoreIoHostNode){type->name,core_host_word(arguments[i],type),0};
    }
    state->calls++; state->work--;
    CoreIoHostCall call={nodes,declaration->count,nodes+declaration->count,1,0,state->work,0};
    state->invoking=1;
    const char *failure=binding->invoke(binding->context,&call);
    state->invoking=0;
    if (call.exhausted || call.work_remaining>state->work) core_host_error(ctx,"HostWorkLimit");
    else {
        state->work=call.work_remaining;
        if (failure) core_host_error(ctx,failure);
        else if (call.output_nodes>1) core_host_error(ctx,"ValueCountLimit");
        else if (call.output_nodes!=1) core_host_error(ctx,"InvalidDataValue");
        else {
            const CoreHostType *type=&core_host_types[declaration->result];
            const CoreIoHostNode *node=&nodes[declaration->count];
            if (!node->type || strcmp(node->type,type->name)) core_host_error(ctx,"ValueTypeMismatch");
            else if (node->children || !core_host_valid(type,node->bits)) core_host_error(ctx,"InvalidDataValue");
            else memcpy(output,&node->bits,type->size);
        }
    }
}
static void core_host_invoke_adapter(CoreHostState *state,const void *const *arguments,void *output) {
    void *ctx=NULL;
    size_t declaration_index=0;
    const CoreHostDeclaration *declaration=&core_host_declarations[declaration_index];
    const CoreIoHostBinding *binding=state->bound[declaration_index];
    if (state->invoking) { core_host_error(ctx,"HostReentry"); return; }
    if (state->calls==state->call_limit) { core_host_error(ctx,"HostCallLimit"); return; }
    if (!state->work) { core_host_error(ctx,"HostWorkLimit"); return; }
    size_t packed_bytes=0;
    if (core_host_packed_call(state,declaration,binding,&packed_bytes)) {
        core_host_invoke_packed(ctx,state,declaration,binding,arguments,output);
        return;
    }
    if (core_host_scalar_call(state,declaration)) {
        core_host_invoke_scalar(ctx,state,declaration,binding,arguments,output);
        return;
    }
    size_t count=0;
    for (size_t i=0;i<declaration->count;i++) if (!core_host_write(ctx,state,declaration->parameters[i],arguments[i],NULL,&count,1)) return;
    size_t capacity=core_host_nodes(declaration->result,1,state->value_limit-count,state->depth_limit);
    if (capacity>SIZE_MAX-count) { core_host_error(ctx,"OutOfMemory"); return; }
    size_t needed=count+capacity?count+capacity:1;
    if (needed>SIZE_MAX/sizeof(CoreIoHostNode)) { core_host_error(ctx,"OutOfMemory"); return; }
    CoreIoHostNode local_nodes[8]={0};
    /* The context retires frame scratch even when a contract failure jumps
       out of this C adapter before its ordinary epilogue. */
    CoreIoHostNode *nodes=needed<=8?local_nodes:core_host_scratch(needed*sizeof(*nodes));
    if (!nodes) { core_host_error(ctx,"OutOfMemory"); return; }
    size_t cursor=0;
    for (size_t i=0;i<declaration->count;i++) if (!core_host_write(ctx,state,declaration->parameters[i],arguments[i],nodes,&cursor,1)) {
        if (nodes!=local_nodes) core_host_scratch_free(nodes);
        return;
    }
    state->calls++; state->work--;
    CoreIoHostCall call={nodes,count,nodes+count,capacity,0,state->work,0};
    state->invoking=1;
    const char *failure=binding->invoke(binding->context,&call);
    state->invoking=0;
    if (call.exhausted || call.work_remaining>state->work) core_host_error(ctx,"HostWorkLimit");
    else {
        state->work=call.work_remaining;
        if (failure) core_host_error(ctx,failure);
        else if (call.output_nodes>capacity) core_host_error(ctx,"ValueCountLimit");
        else {
            cursor=0;
            if (core_host_read(ctx,state,declaration->result,output,nodes+count,call.output_nodes,&cursor,1) && cursor!=call.output_nodes) core_host_error(ctx,"InvalidDataValue");
        }
    }
    if (nodes!=local_nodes) core_host_scratch_free(nodes);
}
/* Compiler schemas use the exact nominal identities and Core byte offsets.
   Text and arrays below are private copies, cached by immortal metadata block. */
typedef struct CoreHostCache {
    struct CoreHostCache *next;myl_block *key;char *text;char **known;size_t known_count;
    CoreHostType *types;size_t type_count;CoreHostDeclaration declaration;CoreHostState state;
    const CoreIoHostBinding *bound;int32_t layout[5];
} CoreHostCache;
static CoreHostCache *core_host_cache;
static char *core_host_line(char **cursor){char *line=*cursor,*end=strchr(line,'\n');if(!end)core_io_fail("R_HOST_CONTRACT");*end=0;*cursor=end+1;return line;}
static size_t core_host_number(char **cursor){char *end;unsigned long long value=strtoull(*cursor,&end,10);if(end==*cursor)core_io_fail("R_HOST_CONTRACT");*cursor=end;while(**cursor==' '||**cursor=='\n')++*cursor;return(size_t)value;}
static CoreHostCache *core_host_schema(myl_block *metadata){
    for(CoreHostCache *item=core_host_cache;item;item=item->next)if(item->key==metadata)return item;
    CoreHostCache *item=calloc(1,sizeof(*item));if(!item)out_of_memory();item->next=core_host_cache;core_host_cache=item;item->key=metadata;
    item->text=malloc((size_t)metadata->len+1);if(!item->text)out_of_memory();memcpy(item->text,block_data(metadata),(size_t)metadata->len);item->text[metadata->len]=0;
    char *cursor=item->text;item->declaration.name=core_host_line(&cursor);
    item->declaration.count=core_host_number(&cursor);item->declaration.result=core_host_number(&cursor);item->declaration.effects=(unsigned)core_host_number(&cursor);
    (void)core_host_number(&cursor);size_t type_count=core_host_number(&cursor);item->type_count=type_count;item->known_count=core_host_number(&cursor);
    if(type_count>100000||item->declaration.count>100000)core_io_fail("R_HOST_CONTRACT");
    size_t *parameters=calloc(item->declaration.count?item->declaration.count:1,sizeof(size_t)*2);if(!parameters)out_of_memory();item->declaration.parameters=parameters;
    for(size_t i=0;i<item->declaration.count;++i){parameters[i]=core_host_number(&cursor);parameters[item->declaration.count+i]=core_host_number(&cursor);}
    item->known=calloc(item->known_count?item->known_count:1,sizeof(char *));if(!item->known)out_of_memory();for(size_t i=0;i<item->known_count;++i)item->known[i]=core_host_line(&cursor);
    item->types=calloc(type_count?type_count:1,sizeof(*item->types));if(!item->types)out_of_memory();
    for(size_t i=0;i<type_count;++i){CoreHostType *type=&item->types[i];type->name=core_host_line(&cursor);type->kind=(unsigned)core_host_number(&cursor);type->size=core_host_number(&cursor);type->count=core_host_number(&cursor);type->stride=core_host_number(&cursor);type->bits=(unsigned)core_host_number(&cursor);type->is_signed=(unsigned)core_host_number(&cursor);size_t count=type->kind==3?1:type->count;if(count){size_t *parts=calloc(count*2,sizeof(size_t));if(!parts)out_of_memory();type->children=parts;type->offsets=parts+count;for(size_t child=0;child<count;++child){parts[child]=core_host_number(&cursor);parts[count+child]=core_host_number(&cursor);}}}
    core_host_types=item->types;core_host_declarations=&item->declaration;
    CoreHostState *state=&item->state;state->registry=&core_io_native.host;const CoreIoHostRegistry *registry=state->registry;
    if(registry->count&&!registry->bindings)core_io_fail("R_HOST_CONTRACT");
    state->call_limit=registry->max_calls?registry->max_calls:10000;state->work=registry->max_work?registry->max_work:1000000;
    state->value_limit=registry->max_values?registry->max_values:65536;state->depth_limit=registry->max_depth?registry->max_depth:64;state->payload_limit=registry->max_payload?registry->max_payload:1024u*1024u;
    if(state->value_limit>100000||state->depth_limit>128||state->payload_limit>64u*1024u*1024u)core_io_fail("R_HOST_CONTRACT");
    for(size_t i=0;i<registry->count;++i){int known=0;for(size_t j=0;j<item->known_count;++j)if(registry->bindings[i].name&&!strcmp(registry->bindings[i].name,item->known[j]))known=1;if(!known)core_host_fail("HostUnknownFunction");}
    item->bound=core_host_binding(NULL,state,&item->declaration);state->bound=&item->bound;state->initialized=1;
    const CoreHostType *result=&item->types[item->declaration.result];item->layout[0]=(int32_t)result->size;item->layout[1]=result->kind==6?1:0;item->layout[2]=0;item->layout[3]=0;item->layout[4]=0;
    return item;
}
static uint64_t core_host_calls,core_host_work;static int core_host_budget_initialized,core_host_invoking;
myl_block *myl_core_host_invoke(myl_block *metadata,myl_block *arguments){
    core_io_initialize();if(core_host_invoking)core_io_fail("R_HOST_CONTRACT");CoreHostCache *schema=core_host_schema(metadata);
    if(!core_host_budget_initialized){core_host_budget_initialized=1;core_host_work=schema->state.work;}schema->state.calls=core_host_calls;schema->state.work=core_host_work;core_host_types=schema->types;core_host_declarations=&schema->declaration;
    const CoreHostType *result=&schema->types[schema->declaration.result];
    myl_block *box=block_new(SELKA_KIND_BOX,(int64_t)result->size,1);box->len=1;box->reserved=(int64_t)(intptr_t)schema->layout;memset(block_data(box),0,result->size);
    size_t count=schema->declaration.count;const void **values=core_host_scratch((count?count:1)*sizeof(void *));
    for(size_t i=0;i<count;++i)values[i]=block_data(arguments)+schema->declaration.parameters[count+i];
    core_host_invoking=1;core_host_invoke_adapter(&schema->state,values,block_data(box));core_host_invoking=0;core_host_calls=schema->state.calls;core_host_work=schema->state.work;core_host_scratch_free(values);return box;
}
static void core_host_cleanup(void){
    while(core_host_scratch_head){CoreHostScratch *item=core_host_scratch_head;core_host_scratch_head=item->next;free(item);}
    while(core_host_cache){CoreHostCache *item=core_host_cache;core_host_cache=item->next;for(size_t i=0;i<item->type_count;++i)free((void *)item->types[i].children);free((void *)item->declaration.parameters);free(item->known);free(item->types);free(item->text);free(item);}
    core_host_types=NULL;core_host_declarations=NULL;
}
