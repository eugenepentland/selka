"""Generate ordinary wire-value adapters using explicit native layout metadata."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def packed_parameters(parameters, types):
    """Mirror the native ABI's bounded direct argument budget."""
    def cost(name):
        item = types[name]
        return 8 if item['kind'] == 'scalar' or item['size'] > 4096 else ((max(8, item['size']) + 7) // 8) * 8
    return len(parameters) > 128 or sum(map(cost, parameters)) > 4096


def source(units, types):
    by_name = {item['name']: i for i, item in enumerate(types)}
    if len(by_name) != len(types):
        raise ValueError('duplicate QBE wire type')
    exports = []
    for unit in units:
        item = unit.get('export')
        if item is None:
            continue
        supported = not item.get('references', False) and item['result'] in by_name and all(t in by_name for t in item['parameters'])
        exports.append((unit, supported))
    maximum=max([1]+[len(unit['export']['parameters']) for unit,supported in exports if supported])
    lines = [f'#define QBE_WIRE_ARGUMENTS {maximum}', (ROOT/'src/qbe_wire_runtime.c').read_text()]
    for index, item in enumerate(types):
        if item['kind'] != 'scalar':
            lines.append(f'typedef struct {{ _Alignas({item["alignment"]}) unsigned char bytes[{max(1,item["size"])}]; }} WireValue{index};')
    packed = lambda parameters: packed_parameters(parameters, {item['name']: item for item in types})
    def ctype(name):
        index = by_name[name]
        return 'uint64_t' if types[index]['kind']=='scalar' else f'WireValue{index}'
    lines.append('static const QbeWireType wire_types[] = {')
    for item in types:
        fields = item.get('fields', [])
        children = ['SIZE_MAX' if field['type'] is None else str(by_name[field['type']]) for field in fields]
        offsets = [str(field['offset']) for field in fields]
        array = lambda entries: '(const size_t[]){'+','.join(entries)+'}' if entries else 'NULL'
        kind = {'scalar':0,'record':1,'array':2,'variant':3}[item['kind']]
        count = item.get('count',0) if kind==2 else len(fields)
        lines.append('{'+','.join([json.dumps(item['name']),str(item['size']),str(count),str(item.get('stride',0)),str(kind),array(children),array(offsets)])+'},')
    if not types:
        lines.append('{0},')
    lines.append('};')
    for unit, supported in exports:
        if supported:
            item=unit['export']
            large=types[by_name[item['result']]]['size']>4096
            result_type='uint64_t' if large else ctype(item['result'])
            lines.append(f'extern {result_type} {unit["symbol"]}(void *'+(', void *' if large else '')+(', const uint64_t *' if packed(item['parameters']) else ''.join(', '+('const void *' if types[by_name[t]]['size']>4096 else ctype(t)) for t in item['parameters']))+');')
    lines.append('static uint64_t wire_dispatch(void *ctx) {(void)ctx;switch(selected) {')
    for index,(unit,supported) in enumerate(exports):
        if not supported:
            continue
        item=unit['export']
        arguments=[]
        for i,name in enumerate(item['parameters']):
            t=by_name[name]
            arguments.append(f'wire_arguments[{i}]' if types[t]['size']>4096 else f'wire_word(wire_arguments[{i}],&wire_types[{t}])' if types[t]['kind']=='scalar' else f'*({ctype(name)} *)wire_arguments[{i}]')
        lines.append(f'case {index}: {{')
        cleanup=''
        if packed(item['parameters']):
            lines.append(f'uint64_t *packet=malloc({len(arguments)}*sizeof *packet);if(!packet){{myl_qbe_fail(ctx,"OutOfMemory");return 0;}}')
            for i,name in enumerate(item['parameters']):
                value=f'wire_word(wire_arguments[{i}],&wire_types[{by_name[name]}])' if types[by_name[name]]['kind']=='scalar' else f'(uint64_t)(uintptr_t)wire_arguments[{i}]'
                lines.append(f'packet[{i}]={value};')
            arguments=['packet'];cleanup='free(packet);'
        if types[by_name[item['result']]]['size']>4096:
            lines.append(f'{unit["symbol"]}(ctx,wire_return'+''.join(', '+a for a in arguments)+');'+cleanup+'return 0;}')
        else:
            lines.append(f'{ctype(item["result"])} result={unit["symbol"]}(ctx'+''.join(', '+a for a in arguments)+');'+cleanup)
            lines.append(f'memcpy(wire_return,&result,{max(1,types[by_name[item["result"]]]["size"])}); return 0; }}')
    lines.append('default:return 0;}}')
    lines.append('int mylang_native_call_values_v1(const char *name,const MylangWireNode *arguments,size_t node_count,\n'
                 ' MylangWireNode *output,size_t capacity,const MylangRunOptions *options,MylangWireResult *out) {\n'
                 ' if (!out) return 2;memset(out,0,sizeof *out);\n'
                 ' if (!name || (node_count && !arguments) || (capacity && !output)) return host_error(&out->execution,"InvalidArgument");\n'
                 ' if (node_count>100000 || capacity>100000) return host_error(&out->execution,"WireLimit");\n'
                 ' if (atomic_flag_test_and_set_explicit(&busy,memory_order_acquire)) return host_error(&out->execution,"Busy");\n'
                 ' size_t result_type=0,argument_count=0;const size_t *parameter_types=NULL;\n'
                 ' int status=2;MylangWireNode *prepared=NULL;\n'
                 ' wire_error=NULL;wire_input=arguments;wire_count=node_count;wire_cursor=0;\n'
                 ' memset(wire_arguments,0,sizeof wire_arguments);wire_return=NULL;\n')
    for index,(unit,supported) in enumerate(exports):
        item=unit['export']
        lines.append(' if (!strcmp(name,'+json.dumps(item['name'])+')) {')
        if supported:
            params=item['parameters']
            table='(const size_t[]){'+','.join(str(by_name[t]) for t in params)+'}' if params else 'NULL'
            # Compound literals have block lifetime: use immutable block-static tables.
            if params:
                lines.append(' static const size_t parameters[]={'+','.join(str(by_name[t]) for t in params)+'};')
                table='parameters'
            lines.append(f' selected={index};result_type={by_name[item["result"]]};argument_count={len(params)};parameter_types={table};goto invoke; }}')
        else:
            lines.append(' host_error(&out->execution,"UnsupportedSignature");goto done;}')
    lines.append(' host_error(&out->execution,"UnknownFunction");goto done;\n' +
                 ('invoke:\n' if any(supported for _,supported in exports) else '') +
                 ' for (size_t i=0;i<argument_count;++i) {\n'
                 '  size_t size=wire_types[parameter_types[i]].size;wire_arguments[i]=calloc(size ? size : 1,1);\n'
                 '  if (!wire_arguments[i]) {host_error(&out->execution,"OutOfMemory");goto done;}\n'
                 '  if (!wire_read(parameter_types[i],wire_arguments[i],0)) {host_error(&out->execution,wire_error);goto done;}\n'
                 ' }\n if (wire_cursor!=wire_count) {host_error(&out->execution,"InvalidArgument");goto done;}\n'
                 ' size_t size=wire_types[result_type].size;wire_return=calloc(size ? size : 1,1);\n'
                 ' if (!wire_return) {host_error(&out->execution,"OutOfMemory");goto done;}\n'
                 ' status=execute(wire_dispatch,options,&out->execution);if(status)goto done;\n'
                 ' prepared=calloc(100000,sizeof *prepared);\n'
                 ' if (!prepared) {status=host_error(&out->execution,"OutOfMemory");goto done;}\n'
                 ' size_t needed=0;\n'
                 ' if (!wire_write(result_type,wire_return,prepared,&needed,0)) {status=host_error(&out->execution,wire_error);goto done;}\n'
                 ' out->node_count=needed;\n'
                 ' if (needed>capacity) {status=host_error(&out->execution,"OutputTooSmall");goto done;}\n'
                 ' if (needed) memcpy(output,prepared,needed*sizeof *output);\n'
                 'done:\n free(prepared);free(wire_return);wire_return=NULL;\n'
                 ' for(size_t i=0;i<QBE_WIRE_ARGUMENTS;++i){free(wire_arguments[i]);wire_arguments[i]=NULL;}\n'
                 ' wire_input=NULL;atomic_flag_clear_explicit(&busy,memory_order_release);return status;\n}')
    return '\n'.join(lines)+'\n'
