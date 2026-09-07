/* Linked with native_json_bridge.zig, which shares the VM's normative JSON parser. */
static void *json_pending;
static void cleanup_native_json(void) { free(json_pending);json_pending=NULL; }
static Slot json_document(size_t ok, size_t error) {
    V limit=pop();Slot input=pop_value();V authority=pop();
    Region *region=allocator_region(authority);
    if (limit<=0 || limit>1048576) {
        release_value(input);return boxed_variant(error,(Slot){4,NULL},1);
    }
    if (!input.object || !input.object->buffer) host_failure("InternalError");
    const size_t length=input.object->count;
    if ((U)length>(U)limit) {
        release_value(input);return boxed_variant(error,(Slot){2,NULL},1);
    }
    if (length>max_steps-steps) trap("R_STEP_LIMIT");
    Aggregate *scratch=new_object(length/sizeof(Slot)+(length%sizeof(Slot)!=0),0);
    scratch->count=0;
    unsigned char *bytes=(unsigned char *)scratch->fields;
    for (size_t i=0;i<length;++i) bytes[i]=(unsigned char)input.object->fields[i].number;
    int64_t *words=NULL;size_t count=0;
    const NativeJsonAllocator allocation={malloc,realloc,free};
    int status=mylang_native_json_document_v1(&allocation,bytes,length,&words,&count);
    json_pending=words;
    release_value((Slot){0,scratch});
    if (status<0) host_failure("OutOfMemory");
    if (count>max_steps-steps-length) trap("R_STEP_LIMIT");
    steps+=length+count;
    if (!status && count>guest_capacity_limit()-guest_capacity) status=2;
    if (status) {
        cleanup_native_json();release_value(input);return boxed_variant(error,(Slot){status,NULL},1);
    }
    Aggregate *output=new_object_in(count,0,region);
    output->buffer=1;guest_capacity+=count;
    for (size_t i=0;i<count;++i) output->fields[i]=(Slot){words[i],NULL};
    cleanup_native_json();release_value(input);
    return boxed_variant(ok,(Slot){0,output},1);
}
typedef struct { int status;Slot value; } NativeJsonResult;
static Aggregate *json_input(size_t type,Slot input,int decoding,NativeJsonInput *call) {
    size_t bytes;
    if (decoding) {
        call->length=input.object->count;bytes=call->length;
    } else {
        size_t old_values=host_value_limit,old_depth=host_depth_limit;
        /* Input is already a checked guest value. Let the normative encoder
           enforce traversal limits in codec-call order, including failures. */
        host_value_limit=SIZE_MAX;host_depth_limit=SIZE_MAX;
        host_write(type,input,NULL,&call->count,1);
        host_value_limit=old_values;host_depth_limit=old_depth;
        if (call->count>SIZE_MAX/sizeof(MylangHostNode)) host_failure("OutOfMemory");
        bytes=call->count*sizeof(MylangHostNode);
    }
    Aggregate *scratch=new_object(bytes/sizeof(Slot)+(bytes%sizeof(Slot)!=0),0);scratch->count=0;
    if (decoding) {
        unsigned char *text=(unsigned char *)scratch->fields;
        for (size_t i=0;i<call->length;++i) text[i]=(unsigned char)input.object->fields[i].number;
        call->bytes=text;
    } else {
        size_t old_values=host_value_limit,old_depth=host_depth_limit,cursor=0;
        host_value_limit=SIZE_MAX;host_depth_limit=SIZE_MAX;
        host_write(type,input,(MylangHostNode *)scratch->fields,&cursor,1);
        host_value_limit=old_values;host_depth_limit=old_depth;
        call->nodes=(MylangHostNode *)scratch->fields;
    }
    return scratch;
}
static NativeJsonResult json_typed(size_t type,int decoding) {
    V limit=pop();Slot input=pop_value();V authority=pop();Region *region=allocator_region(authority);
    if (limit<=0 || limit>1048576) {release_value(input);return (NativeJsonResult){4,{0}};}
    if (decoding && input.object->count>(U)limit) {release_value(input);return (NativeJsonResult){2,{0}};}
    if (decoding && input.object->count>max_steps-steps) trap("R_STEP_LIMIT");
    NativeJsonInput request={0};Aggregate *scratch=json_input(type,input,decoding,&request);
    NativeJsonExecution execution={json_codecs,sizeof(json_codecs)/sizeof(json_codecs[0])-1,json_invoke,free,max_steps-steps,max_frames-nf};
    NativeJsonRequest schema={json_shapes,sizeof(json_shapes)/sizeof(json_shapes[0]),type,(size_t)limit,&execution};
    NativeJsonOutput output={0};const NativeJsonAllocator allocation={malloc,realloc,free};
    int status=decoding ? mylang_native_json_decode_v1(&allocation,&schema,&request,&output) : mylang_native_json_encode_v1(&allocation,&schema,&request,&output);
    json_pending=output.data;release_value((Slot){0,scratch});
    if (status<0) host_failure(status==-2 ? "InternalError" : "OutOfMemory");
    if (status==5) trap("R_STEP_LIMIT");
    if (status==6) trap("R_FRAME_LIMIT");
    if (output.work>max_steps-steps) trap("R_STEP_LIMIT");
    steps+=output.work;
    Slot value={0};
    if (!status && decoding) {
        size_t cursor=0,old_depth=host_depth_limit;host_depth_limit=64;
        host_read(type,(const MylangHostNode *)output.data,output.count,&cursor,1);
        host_depth_limit=old_depth;value=values[--nv];
    } else if (!status) {
        if (output.count>guest_capacity_limit()-guest_capacity) status=2;
        else {
            Aggregate *buffer=new_object_in(output.count,0,region);buffer->buffer=1;guest_capacity+=output.count;
            const unsigned char *bytes=(const unsigned char *)output.data;
            for (size_t i=0;i<output.count;++i) buffer->fields[i]=(Slot){bytes[i],NULL};
            value=(Slot){0,buffer};
        }
    }
    cleanup_native_json();release_value(input);return (NativeJsonResult){status,value};
}
