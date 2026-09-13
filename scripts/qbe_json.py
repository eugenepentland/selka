"""Emit ordinary typed JSON native helpers; link with native_json_bridge.zig."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def source(metadata, types):
    types=metadata.get('types',types)
    by_name={item['name']:i for i,item in enumerate(types)}
    lines=['#include "qbe_runtime.h"','#include "native_host.h"','#include "native_owned.h"',
           '#include <stdlib.h>','#include <string.h>',metadata['schema'],
           'extern const myl_native_type '+metadata['byte_descriptor']+';',
           '#define JSON_BYTE_DESCRIPTOR '+metadata['byte_descriptor'],
           (ROOT/'src/qbe_json_runtime.c').read_text()]
    lines.append('static const QbeJsonType json_native_types[]={')
    for item in types:
        fields=item.get('fields',[])
        children=['SIZE_MAX' if f['type'] is None else str(by_name[f['type']]) for f in fields]
        offsets=[str(f['offset']) for f in fields]
        array=lambda entries: '(const size_t[]){'+','.join(entries)+'}' if entries else 'NULL'
        kind={'scalar':0,'record':1,'array':2,'variant':3,'domain':4}[item['kind']]
        count=item.get('count',0) if kind==2 else len(fields)
        lines.append('{'+','.join([json.dumps(item['name']),str(item['size']),str(count),str(item.get('stride',0)),str(kind),array(children),array(offsets)])+'},')
    lines.append('};')
    lines.append(callback_source(metadata.get('callbacks',[]),types,by_name))
    for operation in metadata['operations']:
        if operation['type'] not in by_name:
            raise ValueError('QBE JSON currently requires an ordinary wire value: '+operation['type'])
        lines.append('uint64_t '+operation['symbol']+'(void *ctx,void *input,int64_t limit,void *output,uint64_t authority){return json_convert(ctx,'+
                     str(operation['index'])+','+str(by_name[operation['type']])+','+str(int(operation['decode']))+',input,limit,output,authority);}')
    if metadata.get('document'):
        lines.append('extern const myl_native_type '+metadata['word_descriptor']+';')
        lines.append('#define JSON_WORD_DESCRIPTOR '+metadata['word_descriptor'])
        lines.append((ROOT/'src/qbe_json_document.c').read_text())
    return '\n'.join(lines)+'\n'


def callback_source(callbacks,types,by_name):
    def backing(name):
        item=types[by_name[name]]
        return backing(item['fields'][0]['type']) if item['kind']=='domain' else item
    def scalar(name):
        return backing(name)['kind']=='scalar'
    def ctype(name):
        return 'uint64_t' if scalar(name) else 'JsonValue'+str(by_name[name])
    lines=[]
    used=set()
    for callback in callbacks:
        for name in (callback['input'],callback['output']):
            if name not in by_name:
                raise ValueError('unsupported native JSON codec signature: '+name)
            if not scalar(name) and name not in used:
                item=types[by_name[name]]
                lines.append(f'typedef struct {{_Alignas({item["alignment"]}) unsigned char bytes[{max(1,item["size"])}];}} {ctype(name)};')
                used.add(name)
        large=types[by_name[callback['output']]]['size']>4096
        result_type='uint64_t' if large else ctype(callback['output'])
        input_type='const void *' if types[by_name[callback['input']]]['size']>4096 else ctype(callback['input'])
        lines.append(f'extern {result_type} {callback["symbol"]}(void *'+(', void *' if large else '')+f', {input_type});')
    lines.append('typedef struct {size_t function;void *input,*output;} JsonCallbackState;\n'
                 'static _Thread_local JsonCallbackState *json_callback;\n'
                 'static uint64_t json_codec_dispatch(void *ctx){(void)ctx;switch(json_callback->function){')
    for callback in callbacks:
        argument='json_callback->input' if types[by_name[callback['input']]]['size']>4096 else 'json_word(json_callback->input,&json_native_types['+str(by_name[backing(callback['input'])['name']])+'])' if scalar(callback['input']) else '*('+ctype(callback['input'])+' *)json_callback->input'
        size=types[by_name[callback['output']]]['size']
        if size>4096:
            lines.append(f'case {callback["index"]}:{{{callback["symbol"]}(ctx,json_callback->output,{argument});return 0;}}')
        else:
            lines.append(f'case {callback["index"]}:{{{ctype(callback["output"])} value={callback["symbol"]}(ctx,{argument});memcpy(json_callback->output,&value,{max(1,size)});return 0;}}')
    lines.append('default:return 0;}}\n'
                 'static int json_invoke(const NativeJsonCall *call,NativeJsonOutput *out){\n'
                 ' memset(out,0,sizeof *out);size_t input_type=0,output_type=0;\n'
                 ' switch(call->function){')
    for callback in callbacks:
        lines.append(f'case {callback["index"]}:input_type={by_name[callback["input"]]};output_type={by_name[callback["output"]]};break;')
    lines.append('default:return -2;}\n'
                 ' void *input=calloc(json_native_types[input_type].size ? json_native_types[input_type].size : 1,1);\n'
                 ' void *output=calloc(json_native_types[output_type].size ? json_native_types[output_type].size : 1,1);\n'
                 ' if(!input || !output){free(input);free(output);return -1;}\n'
                 ' int status=0;JsonNodes decoded={.nodes=(MylangHostNode *)call->nodes,.count=call->count};\n'
                 ' if(!json_unpack(&decoded,input_type,input,0) || decoded.cursor!=decoded.count){status=-2;goto done;}\n'
                 ' JsonCallbackState active={call->function,input,output},*saved=json_callback;json_callback=&active;\n'
                 ' MylQbeResult result;int failed=mylang_qbe_execute(json_codec_dispatch,call->steps,call->frames,&result);json_callback=saved;out->work=result.steps;\n'
                 ' if(failed){status=!strcmp(result.code,"R_STEP_LIMIT") ? 2:!strcmp(result.code,"R_FRAME_LIMIT") ? 3:!strcmp(result.code,"OutOfMemory") ? -1:strncmp(result.code,"R_",2) ? -2:1;goto done;}\n'
                 ' JsonNodes packed={0};\n'
                 ' if(!json_pack(&packed,output_type,output,0)){status=packed.error==2 ? 4:packed.error;free(packed.nodes);goto done;}\n'
                 ' out->data=packed.nodes;out->count=packed.count;\n'
                 'done:free(input);free(output);return status;\n}')
    return '\n'.join(lines)
