default:return -2;}
 void *input=calloc(json_native_types[input_type].size ? json_native_types[input_type].size : 1,1);
 void *output=calloc(json_native_types[output_type].size ? json_native_types[output_type].size : 1,1);
 if(!input || !output){free(input);free(output);return -1;}
 int status=0;JsonNodes decoded={.nodes=(MylangHostNode *)call->nodes,.count=call->count};
 if(!json_unpack(&decoded,input_type,input,0) || decoded.cursor!=decoded.count){status=-2;goto done;}
 JsonCallbackState active={call->function,input,output},*saved=json_callback;json_callback=&active;
 MylQbeResult result;int failed=mylang_qbe_execute(json_codec_dispatch,call->steps,call->frames,&result);json_callback=saved;out->work=result.steps;
 if(failed){status=!strcmp(result.code,"R_STEP_LIMIT") ? 2:!strcmp(result.code,"R_FRAME_LIMIT") ? 3:!strcmp(result.code,"OutOfMemory") ? -1:strncmp(result.code,"R_",2) ? -2:1;goto done;}
 JsonNodes packed={0};
 if(!json_pack(&packed,output_type,output,0)){status=packed.error==2 ? 4:packed.error;free(packed.nodes);goto done;}
 out->data=packed.nodes;out->count=packed.count;
done:free(input);free(output);return status;
}
