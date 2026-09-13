/* Owned native-word result of the normative JSON document parser. */
uint64_t myl_qbe_json_document(void *context,void *input,int64_t limit,void *output,uint64_t authority) {
    MylQbeContext *ctx=context;
    myl_native_owned_buffer *bytes=input,*buffer=NULL;
    int64_t *words=NULL;size_t count=0;int status=0;
    if(limit<=0 || limit>1048576){status=4;goto done;}
    if(!bytes){status=-2;goto done;}
    if(bytes->length>(uint64_t)limit){status=2;goto done;}
    if(bytes->length>ctx->max_steps-ctx->steps){status=5;goto done;}
    const NativeJsonAllocator allocation={malloc,realloc,free};
    status=mylang_native_json_document_v1(&allocation,bytes->storage,bytes->length,&words,&count);
    if(status<0)goto done;
    if(count>ctx->max_steps-ctx->steps-bytes->length){status=5;goto done;}
    ctx->steps+=bytes->length+count;
    if(status)goto done;
    int created=myl_qbe_owned_new(ctx,&JSON_WORD_DESCRIPTOR,authority,(int64_t)count,SIZE_MAX/16,&buffer);
    if(created){status=created<0 ? -1 : 2;goto done;}
    if(count)memcpy(buffer->storage,words,count*sizeof *words);
    buffer->length=count;memcpy(output,&buffer,sizeof buffer);
done:
    free(words);
    if(bytes){static const myl_native_type owned={.size=8,.alignment=8,.kind=MYL_NATIVE_OWNED_BUFFER};myl_native_owned_drop(&ctx->heap,&owned,&bytes);}
    if(status<0)myl_qbe_fail(ctx,status==-2 ? "InternalError" : "OutOfMemory");
    if(status==5)myl_qbe_fail(ctx,"R_STEP_LIMIT");
    return status<0 || status>=5 ? 0 : (uint64_t)status;
}
