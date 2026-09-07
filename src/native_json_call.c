/* Compiled codec execution has its own operand/frame/object registry. Only
   copied data crosses the boundary; checked methods receive no authority. */
typedef struct {
    Slot *values;Frame *frames;Aggregate *objects;
    size_t nv,cv,nf,cf,site,guest_capacity;
    size_t host_values,host_depth;
    uint64_t steps,max_steps,max_frames;
    int binding_call;
    NativeCodecEscape *escape;
    MylangNativeProviders providers;
} NativeCodecState;
static NativeCodecState json_suspend(void) {
    NativeCodecState state={values,frames,objects,nv,cv,nf,cf,site,guest_capacity,
        host_value_limit,host_depth_limit,steps,max_steps,max_frames,binding_call,codec_escape,providers};
    values=NULL;frames=NULL;objects=NULL;nv=cv=nf=cf=0;guest_capacity=0;binding_call=0;steps=0;
    host_value_limit=65536;host_depth_limit=64;providers=(MylangNativeProviders){0};
    return state;
}
static void json_resume(NativeCodecState state) {
    values=state.values;frames=state.frames;objects=state.objects;
    nv=state.nv;cv=state.cv;nf=state.nf;cf=state.cf;site=state.site;guest_capacity=state.guest_capacity;
    host_value_limit=state.host_values;host_depth_limit=state.host_depth;
    steps=state.steps;max_steps=state.max_steps;max_frames=state.max_frames;
    binding_call=state.binding_call;codec_escape=state.escape;providers=state.providers;
}
static int json_invoke(const NativeJsonCall *call,NativeJsonOutput *output) {
    /* Authority-free VM invocation rejects any program requiring a host registry. */
    if (host_declaration_count) return 1;
    NativeCodecState saved=json_suspend();
    /* Volatile state is required after longjmp; the jump never crosses Zig. */
    volatile NativeCodecEscape escape={0};
    codec_escape=(NativeCodecEscape *)&escape;max_steps=call->steps;max_frames=call->frames;
    int status=0;
    if (!setjmp(codec_escape->escape)) {
        size_t cursor=0;
        host_read(call->input_type,call->nodes,call->count,&cursor,1);
        if (cursor!=call->count) host_failure("InternalError");
        execute_entry(NULL,NULL,0,call->function);
        if (nf || nv!=1) host_failure("InternalError");
        size_t count=0;host_value_limit=SIZE_MAX;host_depth_limit=SIZE_MAX;
        host_write(call->output_type,values[0],NULL,&count,1);
        if (count>SIZE_MAX/sizeof(MylangHostNode)) host_failure("OutOfMemory");
        MylangHostNode *nodes=malloc(count*sizeof(MylangHostNode));
        if (!nodes) host_failure("OutOfMemory");
        output->data=nodes;output->count=count;cursor=0;
        host_write(call->output_type,values[0],nodes,&cursor,1);
    } else if (escape.host) {
        status=!strcmp(escape.code,"OutOfMemory") ? -1 :
            (!strcmp(escape.code,"ValueCountLimit") || !strcmp(escape.code,"ValueDepthLimit")) ? 4 : -2;
    } else {
        status=!strcmp(escape.code,"R_STEP_LIMIT") ? 2 : !strcmp(escape.code,"R_FRAME_LIMIT") ? 3 : 1;
    }
    output->work=steps;
    cleanup_values();
    json_resume(saved);
    return status;
}
