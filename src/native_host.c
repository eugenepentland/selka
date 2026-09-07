/* Checked copied-value host calls. Scratch is registered with normal VM cleanup. */
typedef struct {
    const char *name;
    unsigned kind, bits, is_signed, tag_bits;
    size_t count;
    const size_t *children;
} HostShape;
typedef struct {
    const char *name;
    const size_t *parameters;
    size_t count, result;
    unsigned effects;
} HostDeclaration;
static const HostShape host_shapes[];
static const HostDeclaration host_declarations[];
static const size_t host_declaration_count;
static uint64_t host_calls, host_work, host_call_limit;
static size_t host_value_limit, host_depth_limit;
static const MylangHostBinding *host_binding(const HostDeclaration *declaration) {
    const MylangHostBinding *found=NULL;
    for (size_t i=0;i<providers.host.count;++i) {
        const MylangHostBinding *binding=&providers.host.bindings[i];
        if (!binding->name || strcmp(binding->name,declaration->name)) continue;
        if (found) host_failure("HostDuplicateRegistration");
        found=binding;
    }
    if (!found || !found->invoke) host_failure("HostMissingRegistration");
    if (!found->result || strcmp(found->result,host_shapes[declaration->result].name) ||
        found->parameter_count!=declaration->count || found->effects!=declaration->effects ||
        (found->parameter_count && !found->parameters)) host_failure("HostSignatureMismatch");
    for (size_t i=0;i<declaration->count;++i)
        if (!found->parameters[i] || strcmp(found->parameters[i],host_shapes[declaration->parameters[i]].name))
            host_failure("HostSignatureMismatch");
    if (declaration->effects & ~found->grants) host_failure("HostCapabilityDenied");
    return found;
}
static void host_begin(void) {
    if (providers.host.count && !providers.host.bindings) host_failure("HostMissingRegistration");
    host_calls=0;
    host_call_limit=providers.host.max_calls ? providers.host.max_calls : 10000;
    host_work=providers.host.max_work ? providers.host.max_work : 1000000;
    host_value_limit=providers.host.max_values ? providers.host.max_values : 65536;
    host_depth_limit=providers.host.max_depth ? providers.host.max_depth : 64;
    if (host_value_limit>100000 || host_depth_limit>128) host_failure("HostInvalidBudget");
    for (size_t i=0;i<providers.host.count;++i) {
        const char *name=providers.host.bindings[i].name;int found=0;
        if (!name) host_failure("HostUnknownFunction");
        for (size_t j=0;j<host_declaration_count;++j) if (!strcmp(name,host_declarations[j].name)) found=1;
        if (!found) host_failure("HostUnknownFunction");
    }
    for (size_t i=0;i<host_declaration_count;++i) (void)host_binding(&host_declarations[i]);
}
static void host_call_failure(const char *code) {
    if (!strcmp(code,"OutOfMemory")) host_failure(code);
    if (!strcmp(code,"HostCallLimit") || !strcmp(code,"HostWorkLimit") ||
        !strcmp(code,"ValueCountLimit") || !strcmp(code,"ValueDepthLimit")) trap("R_HOST_LIMIT");
    if (!strcmp(code,"HostFailure")) trap("R_HOST_FAILURE");
    trap("R_HOST_CONTRACT");
}
static void host_write(size_t type, Slot value, MylangHostNode *output, size_t *cursor, size_t depth) {
    if (depth>host_depth_limit) host_call_failure("ValueDepthLimit");
    if (*cursor==host_value_limit) host_call_failure("ValueCountLimit");
    const HostShape *shape=&host_shapes[type];
    MylangHostNode node={shape->name,0,0};
    size_t child=SIZE_MAX;
    if (shape->kind==1) node.bits=(uint64_t)(U)value.number;
    else if (shape->kind==2 || shape->kind==3) node.children=shape->count;
    else if (shape->kind==4) {
        node.bits=shape->bits ? (uint64_t)((U)value.number & variant_mask(shape->tag_bits)) : value.object->tag;
        if (node.bits>=shape->count) host_call_failure("InvalidDataValue");
        child=shape->children[node.bits];node.children=child!=SIZE_MAX;
    } else if (shape->kind==5) { child=shape->children[0];node.children=1; }
    else host_call_failure("NotDataType");
    if (output) output[*cursor]=node;
    ++*cursor;
    for (size_t i=0;i<node.children;++i) {
        size_t next=child;
        Slot part=value;
        if (shape->kind==4 && shape->bits) {
            const HostShape *payload=&host_shapes[child];
            part=(Slot){variant_payload(value.number,shape->tag_bits,payload->bits,payload->is_signed),NULL};
        } else if (shape->kind!=5) {
            if (!value.object || i>=value.object->count) host_call_failure("InvalidDataValue");
            part=value.object->fields[i];
            if (shape->kind!=4) next=shape->children[shape->kind==3 ? 0 : i];
        }
        host_write(next,part,output,cursor,depth+1);
    }
}
static void host_read(size_t type, const MylangHostNode *nodes, size_t count, size_t *cursor, size_t depth) {
    if (depth>host_depth_limit) host_call_failure("ValueDepthLimit");
    if (*cursor==count) host_call_failure("InvalidDataValue");
    const HostShape *shape=&host_shapes[type];
    const MylangHostNode *node=&nodes[(*cursor)++];
    if (!node->type || strcmp(node->type,shape->name)) host_call_failure("ValueTypeMismatch");
    if (shape->kind==1) {
        if (node->children) host_call_failure("InvalidDataValue");
        V number=(V)node->bits;
        if (shape->is_signed && (node->bits>>63)) number-=(V)((U)1<<64);
        V lower=shape->is_signed ? -(V)((U)1<<(shape->bits-1)) : 0;
        V upper=(V)(((U)1<<(shape->bits-shape->is_signed))-1);
        if (number<lower || number>upper) host_call_failure("InvalidDataValue");
        push(number);return;
    }
    if (shape->kind==2 || shape->kind==3) {
        if (node->bits || node->children!=shape->count) host_call_failure("InvalidDataValue");
        for (size_t i=0;i<shape->count;++i) host_read(shape->children[shape->kind==3 ? 0 : i],nodes,count,cursor,depth+1);
        make_record(shape->count,NULL);return;
    }
    if (shape->kind==4) {
        if (node->bits>=shape->count) host_call_failure("InvalidDataValue");
        size_t child=shape->children[node->bits];int present=child!=SIZE_MAX;
        if (node->children!=(size_t)present) host_call_failure("InvalidDataValue");
        Slot payload={0};
        if (present) {host_read(child,nodes,count,cursor,depth+1);payload=values[--nv];}
        if (!shape->bits) push_value(boxed_variant((size_t)node->bits,payload,present));
        else push(present ? variant_make(payload.number,shape->tag_bits,host_shapes[child].bits,(size_t)node->bits) : (V)node->bits);
        return;
    }
    if (shape->kind==5) {
        if (node->bits || node->children!=1) host_call_failure("InvalidDataValue");
        host_read(shape->children[0],nodes,count,cursor,depth+1);return;
    }
    host_call_failure("NotDataType");
}
static size_t host_nodes(size_t type, size_t depth, size_t limit) {
    if (!limit || depth>host_depth_limit) return limit;
    const HostShape *shape=&host_shapes[type];
    if (shape->kind==1) return 1;
    size_t total=1;
    if (shape->kind==4) {
        size_t largest=0;
        for (size_t i=0;i<shape->count;++i) if (shape->children[i]!=SIZE_MAX) {
            size_t child=host_nodes(shape->children[i],depth+1,limit-1);
            if (child>largest) largest=child;
        }
        return 1+largest;
    }
    if (shape->kind==3) {
        size_t child=host_nodes(shape->children[0],depth+1,limit-1);
        if (child && shape->count>(limit-1)/child) return limit;
        return 1+shape->count*child;
    }
    for (size_t i=0;i<shape->count;++i) {
        total+=host_nodes(shape->children[i],depth+1,limit-total);
        if (total==limit) return limit;
    }
    return total;
}
static void host_invoke(size_t declaration_index) {
    const HostDeclaration *declaration=&host_declarations[declaration_index];
    const MylangHostBinding *binding=host_binding(declaration);
    if (host_calls==host_call_limit) host_call_failure("HostCallLimit");
    if (!host_work) host_call_failure("HostWorkLimit");
    if (nv<declaration->count) host_call_failure("InternalError");
    const size_t base=nv-declaration->count;
    size_t count=0;
    for (size_t i=0;i<declaration->count;++i) host_write(declaration->parameters[i],values[base+i],NULL,&count,1);
    if (host_value_limit>SIZE_MAX/sizeof(MylangHostNode)) host_call_failure("OutOfMemory");
    const size_t output_capacity=host_nodes(declaration->result,1,host_value_limit-count);
    const size_t bytes=(count+output_capacity)*sizeof(MylangHostNode);
    Aggregate *scratch=new_object(bytes/sizeof(Slot)+(bytes%sizeof(Slot)!=0),0);
    scratch->count=0;
    MylangHostNode *nodes=(MylangHostNode *)scratch->fields;
    size_t cursor=0;
    for (size_t i=0;i<declaration->count;++i) host_write(declaration->parameters[i],values[base+i],nodes,&cursor,1);
    ++host_calls;--host_work;
    MylangHostCall call={nodes,count,nodes+count,output_capacity,0,host_work,0};
    const char *failure=binding->invoke(binding->context,&call);
    if (call.exhausted || call.work_remaining>host_work) host_call_failure("HostWorkLimit");
    host_work=call.work_remaining;
    if (failure) host_call_failure(failure);
    if (call.output_nodes>output_capacity) host_call_failure("ValueCountLimit");
    clear_values(base);cursor=0;
    host_read(declaration->result,nodes+count,call.output_nodes,&cursor,1);
    if (cursor!=call.output_nodes) host_call_failure("InvalidDataValue");
    release_value((Slot){0,scratch});
}
