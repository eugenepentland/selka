"""Emit copied-host schemas and independently named native bridge functions."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source(metadata):
    types = metadata.get('types', [])
    declarations = metadata.get('declarations', [])
    by_name = {item['name']: index for index, item in enumerate(types)}
    if len(by_name) != len(types):
        raise ValueError('duplicate QBE host type')
    lines = [(ROOT / 'src/qbe_host_runtime.c').read_text()]
    lines.append('static const QbeHostType qbe_host_types[] = {')
    for item in types:
        fields = item.get('fields', [])
        children = ['SIZE_MAX' if field['type'] is None else str(by_name[field['type']]) for field in fields]
        offsets = [str(field['offset']) for field in fields]
        def array(items):
            return '(const size_t[]){' + ','.join(items) + '}' if items else 'NULL'
        kind = {'unsupported': 0, 'scalar': 1, 'record': 2, 'array': 3, 'variant': 4, 'domain': 5}[item['kind']]
        count = item['count'] if kind in (3, 4) else len(fields)
        lines.append('{' + ','.join([
            json.dumps(item['name']), str(item['size']), str(count), str(item.get('stride', 0)),
            str(kind), str(item.get('bits', 0)), str(int(item.get('signed', False))),
            array(children), array(offsets),
        ]) + '},')
    if not types:
        lines.append('{0},')
    lines.append('};\nstatic const QbeHostDeclaration qbe_host_declarations[] = {')
    for declaration in declarations:
        parameters = [str(by_name[name]) for name in declaration['parameters']]
        table = '(const size_t[]){' + ','.join(parameters) + '}' if parameters else 'NULL'
        lines.append('{' + ','.join([
            json.dumps(declaration['name']), table, str(len(parameters)),
            str(by_name[declaration['result']]), str(declaration['effects']),
        ]) + '},')
    if not declarations:
        lines.append('{0},')
    lines.append(f'}};\nstatic const size_t qbe_host_declaration_count={len(declarations)};')
    for index, declaration in enumerate(declarations):
        lines.append(f'void {declaration["symbol"]}_host(void *ctx,const void *const *arguments,void *output) {{ qbe_host_invoke(ctx,{index},arguments,output); }}')
    return '\n'.join(lines) + '\n'
