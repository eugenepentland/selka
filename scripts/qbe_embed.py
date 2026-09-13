"""Generate native embedding ABI adapters around independently callable QBE code."""
import hashlib
import json
import re

SCALARS = {'bool', 'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64'}


def library_wrapper(entry, units, schema=None, wire_types=None, entry_parameters=None, codecs=None):
    entry_parameters = entry_parameters or []
    capabilities = {'clock_cap': 0, 'random_cap': 1, 'environment_cap': 2}
    if any(t != 'allocator' and t not in capabilities for t in entry_parameters):
        raise ValueError('unsupported QBE run ABI entry capability')
    exports = []
    declarations = {entry: len(entry_parameters)}
    for unit in units:
        export = unit.get('export')
        if export is None:
            continue
        name, parameters, result = export['name'], export['parameters'], export['result']
        if not isinstance(name, str) or not isinstance(parameters, list) or not all(isinstance(t, str) for t in parameters) or not isinstance(result, str):
            raise ValueError('invalid QBE export signature')
        supported = export.get('scalar', True) and result in SCALARS and all(t in SCALARS for t in parameters)
        if supported:
            declarations[unit['symbol']] = len(parameters)
        exports.append((name, parameters, result, unit['symbol'], supported))
    if len({e[0] for e in exports}) != len(exports):
        raise ValueError('duplicate QBE export name')
    if schema is not None and not isinstance(schema, str):
        raise ValueError('invalid QBE interface schema')
    schema_literal = 'NULL' if schema is None else json.dumps(schema, ensure_ascii=False)
    hash_literal = 'NULL' if schema is None else json.dumps(hashlib.sha256(schema.encode()).hexdigest())
    lines = [PRELUDE,
             'const char *mylang_native_schema_json_v1(void) {return '+schema_literal+';}',
             'const char *mylang_native_schema_sha256_v1(void) {return '+hash_literal+';}']
    for symbol, count in declarations.items():
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', symbol):
            raise ValueError('invalid QBE export symbol')
        lines.append(f'extern uint64_t {symbol}(void *' + (', const uint64_t *' if count>128 else ', uint64_t' * count) + ');')
    lines.append('static uint64_t entry_run(void *ctx) {')
    for i, ty in enumerate(entry_parameters):
        value = '1' if ty == 'allocator' else f'myl_qbe_grant_external(ctx,{capabilities[ty]})'
        lines.append(f' uint64_t arg{i}={value};')
    if entry_parameters:
        lines.append(' if(myl_qbe_failed(ctx))return 0;')
    if len(entry_parameters)>128:
        lines.append(f'uint64_t *packet=malloc({len(entry_parameters)}*sizeof *packet);if(!packet){{myl_qbe_fail(ctx,"OutOfMemory");return 0;}}')
        for i in range(len(entry_parameters)):
            lines.append(f'packet[{i}]=arg{i};')
        lines.append(f'uint64_t result={entry}(ctx,packet);free(packet);return result;}}')
    else:
        lines.append('return '+entry+'(ctx'+''.join(f', arg{i}' for i in range(len(entry_parameters)))+');}')
    lines.append('static uint64_t dispatch(void *ctx) {(void)ctx; switch(selected) {')
    for index, (_, parameters, _, symbol, supported) in enumerate(exports):
        if supported:
            arguments = ''.join(f', inputs[{i}].bits' for i in range(len(parameters)))
            if len(parameters)>128:
                lines.append(f'case {index}: {{uint64_t *packet=malloc({len(parameters)}*sizeof *packet);if(!packet){{myl_qbe_fail(ctx,"OutOfMemory");return 0;}}')
                lines.append(f'for(size_t i=0;i<{len(parameters)};++i)packet[i]=inputs[i].bits;uint64_t result={symbol}(ctx,packet);free(packet);return result;}}')
            else:
                lines.append(f'case {index}: return {symbol}(ctx{arguments});')
    lines.append('default: return 0; }}')
    lines.append('int mylang_native_run_v1(const MylangRunOptions *options, MylangRunResult *out) {\n'
                 ' if (!out) return 2; memset(out,0,sizeof *out);\n'
                 ' if (atomic_flag_test_and_set_explicit(&busy,memory_order_acquire)) return host_error(out,"Busy");\n'
                 ' int status=execute(entry_run,options,out);\n'
                 ' atomic_flag_clear_explicit(&busy,memory_order_release); return status;\n}')
    lines.append('int mylang_native_call_v1(const char *name,const MylangScalar *arguments,size_t count,\n'
                 ' const MylangRunOptions *options,MylangCallResult *out) {\n'
                 ' if (!out) return 2; memset(out,0,sizeof *out);\n'
                 ' if (!name || (count && !arguments)) return host_error(&out->execution,"InvalidArgument");\n'
                 ' if (atomic_flag_test_and_set_explicit(&busy,memory_order_acquire)) return host_error(&out->execution,"Busy");\n'
                 ' int status=2; const char *return_type=NULL;\n')
    for index, (name, parameters, result, _, supported) in enumerate(exports):
        lines.append(f' if (!strcmp(name,{json.dumps(name)})) {{')
        if not supported:
            lines.append(' host_error(&out->execution,"UnsupportedSignature"); goto done; }')
            continue
        conditions = [f'count != {len(parameters)}']
        conditions.extend(f'!valid_scalar(arguments[{i}],{json.dumps(ty)})' for i, ty in enumerate(parameters))
        lines.append(' if (' + ' || '.join(conditions) + ') {host_error(&out->execution,"InvalidArgument");goto done;}')
        lines.append(f' selected={index}; return_type={json.dumps(result)}; goto invoke; }}')
    lines.append(' host_error(&out->execution,"UnknownFunction"); goto done;\n' +
                 ('invoke:\n' if any(e[4] for e in exports) else '') +
                 ' inputs=arguments; status=execute(dispatch,options,&out->execution);\n'
                 ' if (!status) {out->value.type=return_type;memcpy(&out->value.bits,&out->execution.value,sizeof out->value.bits);}\n'
                 'done:\n inputs=NULL; atomic_flag_clear_explicit(&busy,memory_order_release);return status;\n}')
    if wire_types is not None:
        from qbe_wire import source
        lines.append(source(units, wire_types))
    if codecs is not None:
        from qbe_codecs import source as codec_source
        lines.append(codec_source(units, codecs, wire_types or []))
    return '\n'.join(lines) + '\n'


PRELUDE = r'''
#include "qbe_runtime.h"
#include "native_host.h"
#include "native_providers.h"
#include "native_embed.h"
#include <string.h>
#include <stdlib.h>
#include <stdatomic.h>
static atomic_flag busy = ATOMIC_FLAG_INIT;
static const MylangScalar *inputs;
static size_t selected;
static int host_error(MylangRunResult *out,const char *code) {
    out->status=2;out->code=code;return 2;
}
static int valid_scalar(MylangScalar value,const char *type) {
    if (!value.type || strcmp(value.type,type)) return 0;
    if (!strcmp(type,"bool")) return value.bits<=1;
    unsigned width=0;
    for (const char *p=type+1;*p;++p) width=width*10+(unsigned)(*p-'0');
    if (width==64) return 1;
    uint64_t mask=(UINT64_C(1)<<width)-1, raw=value.bits & mask;
    if (*type=='i' && (raw & (UINT64_C(1)<<(width-1)))) raw |= ~mask;
    return value.bits==raw;
}
extern void myl_qbe_host_begin(void *);
static int execute(uint64_t (*entry)(void *),const MylangRunOptions *options,MylangRunResult *out) {
    uint64_t steps=options && options->max_steps ? options->max_steps : 10000000;
    uint64_t frames=options && options->max_frames ? options->max_frames : 1024;
    MylQbeResult result;
    int status=mylang_qbe_execute_config(entry,steps,frames,0,options ? options->providers : NULL,myl_qbe_host_begin,&result);
    if (status && result.code && strncmp(result.code,"R_",2)) status=2;
    out->status=status;out->steps=result.steps;out->code=result.code;
    if (!status) memcpy(&out->value,&result.value,sizeof out->value);
    out->frame_count=result.trace_count;out->omitted_frames=result.omitted_frames;
    for (uint64_t i=0;i<result.trace_count;++i)
        out->frames[i]=(MylangRunFrame){result.trace[i].function,result.trace[i].path,result.trace[i].line,result.trace[i].column};
    if (result.trace_count) {out->path=result.trace[0].path;out->line=result.trace[0].line;out->column=result.trace[0].column;}
    return status;
}
'''
