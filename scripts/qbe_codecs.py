"""Generate the native copied-value ABI with explicit compiled domain codecs."""
import json
from qbe_wire import packed_parameters
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def source(units,metadata,ordinary_types):
    types=metadata['types'];by_name={item['name']:i for i,item in enumerate(types)}
    ordinary={item['name']:i for i,item in enumerate(ordinary_types)}
    codecs={item['domain']:item for item in metadata['codecs']}
    def backing(name):
        item=types[by_name[name]]
        return backing(item['fields'][0]['type']) if item['kind']=='domain' else item
    def scalar(name):
        return backing(name)['kind']=='scalar'
    def ctype(name):
        if scalar(name):return 'uint64_t'
        return 'WireValue'+str(ordinary[name]) if name in ordinary else 'CodecValue'+str(by_name[name])
    exports=[]
    for unit in units:
        export=unit.get('export')
        if export is not None:
            supported=not export.get('references',False) and export['result'] in by_name and all(t in by_name for t in export['parameters'])
            exports.append((unit,supported))
    packed=lambda parameters: packed_parameters(parameters,{item['name']:item for item in types})
    maximum=max([1]+[len(unit['export']['parameters']) for unit,supported in exports if supported])
    lines=[f'#define QBE_CODEC_ARGUMENTS {maximum}',(ROOT/'src/qbe_codecs_runtime.c').read_text()]
    for name,index in by_name.items():
        if not scalar(name) and name not in ordinary:
            item=types[index];lines.append(f'typedef struct {{_Alignas({item["alignment"]}) unsigned char bytes[{max(1,item["size"])}];}} {ctype(name)};')
    lines.append('static const CoType co_types[]={')
    array=lambda entries:'(const size_t[]){'+','.join(entries)+'}' if entries else 'NULL'
    for item in types:
        fields=item.get('fields',[])
        children=['SIZE_MAX' if field['type'] is None else str(by_name[field['type']]) for field in fields]
        offsets=[str(field['offset']) for field in fields]
        kind={'scalar':0,'record':1,'array':2,'variant':3,'domain':4}[item['kind']]
        count=item.get('count',0) if kind==2 else len(fields)
        codec='NULL'
        if item['name'] in codecs:
            c=codecs[item['name']]
            values=[by_name[c['wire']],c['decode'],c['encode'],by_name[c['result']],c['ok'],c['err'],by_name[c['error_type']]]
            codec='&(const CoCodec){'+','.join(map(str,values))+'}'
        lines.append('{'+','.join([json.dumps(item['name']),str(item['size']),str(count),str(item.get('stride',0)),str(kind),array(children),array(offsets),codec])+'},')
    if not types:lines.append('{0},')
    lines.append('};')
    for callback in metadata['callbacks']:
        large=types[by_name[callback['output']]]['size']>4096
        out_type='uint64_t' if large else ctype(callback['output'])
        in_type='const void *' if types[by_name[callback['input']]]['size']>4096 else ctype(callback['input'])
        lines.append(f'extern {out_type} {callback["symbol"]}(void *'+(', void *' if large else '')+f', {in_type});')
    lines.append('static int co_method(size_t function,void *ctx,const void *input,void *output){(void)ctx;(void)input;(void)output;switch(function){')
    for callback in metadata['callbacks']:
        name=callback['input'];argument='input' if types[by_name[name]]['size']>4096 else f'co_word(input,{by_name[name]})' if scalar(name) else f'*({ctype(name)} *)input'
        size=max(1,types[by_name[callback['output']]]['size'])
        if size>4096:
            lines.append(f'case {callback["index"]}:{{{callback["symbol"]}(ctx,output,{argument});return !myl_qbe_failed(ctx);}}')
        else:
            lines.append(f'case {callback["index"]}:{{{ctype(callback["output"])} result={callback["symbol"]}(ctx,{argument});memcpy(output,&result,{size});return !myl_qbe_failed(ctx);}}')
    lines.append('default:return co_bad("InternalError");}}')
    for unit,supported in exports:
        if supported:
            e=unit['export'];large=types[by_name[e['result']]]['size']>4096
            result_type='uint64_t' if large else ctype(e['result'])
            lines.append(f'extern {result_type} {unit["symbol"]}(void *'+(', void *' if large else '')+(', const uint64_t *' if packed(e['parameters']) else ''.join(', '+('const void *' if types[by_name[t]]['size']>4096 else ctype(t)) for t in e['parameters']))+');')
    lines.append('static int co_public(void *ctx){(void)ctx;switch(selected){')
    for index,(unit,supported) in enumerate(exports):
        if not supported:continue
        e=unit['export'];arguments=[f'co_arguments[{i}]' if types[by_name[t]]['size']>4096 else f'co_word(co_arguments[{i}],{by_name[t]})' if scalar(t) else f'*({ctype(t)} *)co_arguments[{i}]' for i,t in enumerate(e['parameters'])]
        size=max(1,types[by_name[e['result']]]['size'])
        lines.append(f'case {index}:{{')
        cleanup=''
        if packed(e['parameters']):
            lines.append(f'uint64_t *packet=malloc({len(arguments)}*sizeof *packet);if(!packet)return co_bad("OutOfMemory");')
            for i,name in enumerate(e['parameters']):
                value=f'co_word(co_arguments[{i}],{by_name[name]})' if scalar(name) else f'(uint64_t)(uintptr_t)co_arguments[{i}]'
                lines.append(f'packet[{i}]={value};')
            arguments=['packet'];cleanup='free(packet);'
        if size>4096:
            lines.append(f'{unit["symbol"]}(ctx,co_return'+''.join(', '+a for a in arguments)+');'+cleanup+'return !myl_qbe_failed(ctx);}')
        else:
            lines.append(f'{ctype(e["result"])} result={unit["symbol"]}(ctx'+''.join(', '+a for a in arguments)+');'+cleanup+f'memcpy(co_return,&result,{size});return !myl_qbe_failed(ctx);}}')
    lines.append('default:return co_bad("InternalError");}}\n'
                 'static uint64_t co_execute(void *ctx){\n'
                 ' co_context=ctx;\n'
                 ' for(size_t i=0;i<co_argument_count;++i){\n'
                 '  size_t size=co_types[co_parameter_types[i]].size;co_arguments[i]=calloc(size ? size:1,1);\n'
                 '  if(!co_arguments[i]){co_bad("OutOfMemory");return 0;}\n'
                 '  if(!co_read(co_parameter_types[i],co_arguments[i],0))return 0;\n'
                 ' }\n if(co_cursor!=co_count){co_bad("InvalidArgument");return 0;}\n'
                 ' size_t size=co_types[co_result_type].size;co_return=calloc(size ? size:1,1);\n'
                 ' if(!co_return){co_bad("OutOfMemory");return 0;}\n'
                 ' if(co_charge() && co_public(ctx))co_write(co_result_type,co_return,0);\n'
                 ' return 0;\n}')
    lines.append('int mylang_native_call_codecs_v1(const char *name,const MylangWireNode *arguments,size_t node_count,\n'
                 ' MylangWireNode *output,size_t capacity,const MylangCodecOptions *options,MylangCodecResult *out){\n'
                 ' if(!out)return 2;memset(out,0,sizeof *out);MylangRunResult *execution=&out->value.execution;\n'
                 ' if(!name || (node_count && !arguments) || (capacity && !output))return host_error(execution,"InvalidArgument");\n'
                 ' if(node_count>100000 || capacity>100000)return host_error(execution,"WireLimit");\n'
                 ' if(atomic_flag_test_and_set_explicit(&busy,memory_order_acquire))return host_error(execution,"Busy");\n'
                 ' int status=2;co_input=arguments;co_count=node_count;co_cursor=0;co_needed=0;co_rejected=0;co_error=NULL;co_domain=NULL;\n'
                 ' co_calls=0;co_max_calls=options && options->max_calls ? options->max_calls:4096;\n'
                 ' memset(co_arguments,0,sizeof co_arguments);co_return=NULL;co_prepared=NULL;\n')
    for index,(unit,supported) in enumerate(exports):
        e=unit['export'];lines.append(' if(!strcmp(name,'+json.dumps(e['name'])+')){')
        if supported:
            if e['parameters']:
                lines.append(' static const size_t parameters[]={'+','.join(str(by_name[t]) for t in e['parameters'])+'};')
            table='parameters' if e['parameters'] else 'NULL'
            lines.append(f' selected={index};co_result_type={by_name[e["result"]]};co_argument_count={len(e["parameters"])};co_parameter_types={table};goto invoke;}}')
        else:lines.append('host_error(execution,"UnsupportedSignature");goto done;}')
    lines.append(' host_error(execution,"UnknownFunction");goto done;\n'+('invoke:\n' if any(s for _,s in exports) else '')+
                 ' co_prepared=calloc(100000,sizeof *co_prepared);if(!co_prepared){host_error(execution,"OutOfMemory");goto done;}\n'
                 ' status=execute(co_execute,options ? &options->run:NULL,execution);\n'
                 ' if(!status && co_error)status=host_error(execution,co_error);\n'
                 ' if(!status || (co_rejected && co_error && !strcmp(co_error,"DomainCodecRejected"))){\n'
                 '  out->value.node_count=co_needed;\n'
                 '  if(co_needed>capacity)status=host_error(execution,"OutputTooSmall");\n'
                 '  else if(co_needed)memcpy(output,co_prepared,co_needed*sizeof *output);\n'
                 ' }\n'
                 'done:\n out->calls=co_calls;out->domain=co_domain;out->rejected=co_rejected;\n'
                 ' for(size_t i=0;i<QBE_CODEC_ARGUMENTS;++i){free(co_arguments[i]);co_arguments[i]=NULL;}\n'
                 ' free(co_return);free(co_prepared);co_return=NULL;co_prepared=NULL;co_input=NULL;co_context=NULL;\n'
                 ' atomic_flag_clear_explicit(&busy,memory_order_release);return status;\n}')
    return '\n'.join(lines)+'\n'
