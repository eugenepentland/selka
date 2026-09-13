/* Native bytes are copied only at the normative JSON codec boundary. */
typedef struct { const char *name;size_t size,count,stride;unsigned kind;const size_t *children,*offsets; } QbeJsonType;
static const QbeJsonType json_native_types[];
typedef struct { MylangHostNode *nodes;size_t count,capacity,cursor;int error; } JsonNodes;
static uint64_t json_word(const void *input,const QbeJsonType *type) {
    uint64_t bits=0;memcpy(&bits,input,type->size);
    if (*type->name=='i' && type->size<8 && (bits&(UINT64_C(1)<<(type->size*8-1)))) bits|=UINT64_MAX<<(type->size*8);
    return bits;
}
static int json_pack(JsonNodes *nodes,size_t index,const void *input,size_t depth) {
    if(depth>128 || nodes->count==1048576){nodes->error=2;return 0;}
    if(nodes->count==nodes->capacity){
        size_t capacity=nodes->capacity ? nodes->capacity*2 : 32;
        void *next=realloc(nodes->nodes,capacity*sizeof *nodes->nodes);
        if(!next){nodes->error=-1;return 0;}nodes->nodes=next;nodes->capacity=capacity;
    }
    const QbeJsonType *type=&json_native_types[index];
    size_t slot=nodes->count++;
    nodes->nodes[slot]=(MylangHostNode){type->name,0,type->count};
    if(type->kind==0){nodes->nodes[slot].bits=json_word(input,type);nodes->nodes[slot].children=0;return 1;}
    if(type->kind==3){
        uint32_t tag;memcpy(&tag,input,4);
        if(tag>=type->count){nodes->error=-2;return 0;}
        size_t child=type->children[tag];nodes->nodes[slot].bits=tag;nodes->nodes[slot].children=child==SIZE_MAX ? 0 : 1;
        return child==SIZE_MAX || json_pack(nodes,child,(const unsigned char *)input+type->offsets[tag],depth+1);
    }
    for(size_t i=0;i<type->count;++i){
        size_t child=type->children[type->kind==2 ? 0 : i],offset=type->kind==2 ? i*type->stride : type->offsets[i];
        if(!json_pack(nodes,child,(const unsigned char *)input+offset,depth+1))return 0;
    }
    return 1;
}
static int json_unpack(JsonNodes *nodes,size_t index,void *output,size_t depth){
    if(depth>128 || nodes->cursor>=nodes->count)return 0;
    const QbeJsonType *type=&json_native_types[index];const MylangHostNode *node=&nodes->nodes[nodes->cursor++];
    if(!node->type || strcmp(node->type,type->name))return 0;
    if(type->kind==0){if(node->children)return 0;memcpy(output,&node->bits,type->size);return 1;}
    if(type->kind==3){
        if(node->bits>=type->count)return 0;
        uint32_t tag=(uint32_t)node->bits;size_t child=type->children[tag];
        if(node->children!=(child==SIZE_MAX ? 0u : 1u))return 0;
        memcpy(output,&tag,4);return child==SIZE_MAX || json_unpack(nodes,child,(unsigned char *)output+type->offsets[tag],depth+1);
    }
    if(node->bits || node->children!=type->count)return 0;
    for(size_t i=0;i<type->count;++i){
        size_t child=type->children[type->kind==2 ? 0 : i],offset=type->kind==2 ? i*type->stride : type->offsets[i];
        if(!json_unpack(nodes,child,(unsigned char *)output+offset,depth+1))return 0;
    }
    return 1;
}
static uint64_t json_convert(void *context,size_t schema_type,size_t native_type,int decoding,const void *input,int64_t limit,void *output,uint64_t authority){
    MylQbeContext *ctx=context;
    NativeJsonOutput converted={0};NativeJsonInput request={0};JsonNodes nodes={0};
    myl_native_owned_buffer *bytes=decoding ? (myl_native_owned_buffer *)input : NULL;
    int status=0;
    if(limit<=0 || limit>1048576){status=4;goto done;}
    if(decoding){
        if(!bytes){status=-2;goto done;}
        if(bytes->length>(uint64_t)limit){status=2;goto done;}
        if(bytes->length>ctx->max_steps-ctx->steps){status=5;goto done;}
        request.bytes=bytes->storage;request.length=bytes->length;
    }else{
        if(!json_pack(&nodes,native_type,input,0)){status=nodes.error;goto done;}
        request.nodes=nodes.nodes;request.count=nodes.count;
    }
    NativeJsonExecution execution={json_codecs,sizeof json_codecs/sizeof json_codecs[0]-1,json_invoke,free,ctx->max_steps-ctx->steps,ctx->max_frames-ctx->frames};
    NativeJsonRequest schema={json_shapes,sizeof json_shapes/sizeof json_shapes[0],schema_type,(size_t)limit,&execution};
    const NativeJsonAllocator allocation={malloc,realloc,free};
    status=decoding ? mylang_native_json_decode_v1(&allocation,&schema,&request,&converted) : mylang_native_json_encode_v1(&allocation,&schema,&request,&converted);
    if(converted.work>ctx->max_steps-ctx->steps){status=5;goto done;}
    if(status!=5 && status!=6 && status>=0)ctx->steps+=converted.work;
    if(status)goto done;
    if(decoding){
        JsonNodes decoded={.nodes=converted.data,.count=converted.count};
        memset(output,0,json_native_types[native_type].size);
        if(!json_unpack(&decoded,native_type,output,0) || decoded.cursor!=decoded.count)status=-2;
    }else{
        myl_native_owned_buffer *buffer=NULL;
        int created=myl_qbe_owned_new(ctx,&JSON_BYTE_DESCRIPTOR,authority,(int64_t)converted.count,SIZE_MAX/16,&buffer);
        if(created){status=created<0 ? -1 : 2;goto done;}
        memcpy(buffer->storage,converted.data,converted.count);buffer->length=converted.count;
        memcpy(output,&buffer,sizeof buffer);
    }
done:
    free(nodes.nodes);free(converted.data);
    if(bytes){static const myl_native_type owned={.size=8,.alignment=8,.kind=MYL_NATIVE_OWNED_BUFFER};myl_native_owned_drop(&ctx->heap,&owned,&bytes);}
    if(status<0)myl_qbe_fail(ctx,status==-2 ? "InternalError" : "OutOfMemory");
    if(status==5)myl_qbe_fail(ctx,"R_STEP_LIMIT");
    if(status==6)myl_qbe_fail(ctx,"R_FRAME_LIMIT");
    return status<0 || status>=5 ? 0 : (uint64_t)status;
}
