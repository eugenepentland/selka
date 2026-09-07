/* Linked with native_json_bridge.zig, which shares the VM's normative JSON parser. */
typedef struct { void *(*allocate)(size_t);void *(*reallocate)(void *,size_t);void (*release)(void *); } NativeJsonAllocator;
extern int mylang_native_json_document_v1(const NativeJsonAllocator *, const unsigned char *, size_t, int64_t **, size_t *);
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
