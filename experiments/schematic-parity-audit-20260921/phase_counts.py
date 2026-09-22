#!/usr/bin/env python3
"""Attribute host-call counts to main's six pipeline calls; not a timed arm."""
import json
from pathlib import Path
import re
from measure import invoke
from build_probes import ROOT, WORK, run


def main():
    manifest = json.loads((WORK / 'manifest.json').read_text())
    functions = manifest['functions']
    symbols = {f['name']: f['symbol'] for f in functions}
    main_symbol = symbols['main::main']
    pattern = rf'^define [^\n]*@{main_symbol}\(.*?^}}'
    ir = (WORK / 'whole.ll').read_text()
    match = re.search(pattern, ir, re.M | re.S)
    assert match
    stages = []
    lines = []
    for line in match[0].splitlines():
        lines.append(line)
        for name in ('schematic_inputs::load', 'sexpr::parse', 'schematic::build', 'svg::render'):
            if ' call ' in line and '@'+symbols[name]+'(' in line:
                stages.append(name)
                lines.append(f'  call void @myl_audit_phase(i32 {len(stages)})')
    assert len(stages) == 6, stages
    ir = ir[:match.start()] + '\n'.join(lines) + ir[match.end():] + '\ndeclare void @myl_audit_phase(i32)\n'
    ll = WORK / 'phases.ll'
    ll.write_text(ir)
    obj = ll.with_suffix('.o')
    run(['zig', 'cc', '-O3', '-fPIC', '-g0', '-c', ll, '-o', obj])
    source = (WORK / 'metadata-counts.c').read_text()
    source += '\nvoid myl_audit_phase(int stage) {\n'
    source += '  for (size_t i=0;i<qbe_host_declaration_count;i++) fprintf(stderr,"phase %d %s %llu\\n",stage,qbe_host_declarations[i].name,audit_calls[i]);\n}\n'
    meta = WORK / 'metadata-phases.c'
    meta.write_text(source)
    assets = next((WORK / 'cache-o3/runtime').glob('*'))
    run(['zig', 'cc', '-O2', '-fPIC', '-g0', '-I', assets, '-c', meta, '-o', meta.with_suffix('.o')])
    receipt = json.loads((WORK / 'unit-o3.qbe-manifest.json').read_text())
    guests = [Path(f['object']) for f in receipt['functions']]
    entry = next(p for p in guests[0].parent.glob('*.o') if p not in guests and re.search(r' T main$', run(['nm', p]), re.M))
    run(['zig', 'cc', '-O2', '-fPIC', '-g0', obj, meta.with_suffix('.o'), entry, WORK / 'provider.o', receipt['runtime_object'], '-lm', '-Wl,--gc-sections', '-o', WORK / 'phases'])
    _, ref = invoke('unit-o3')
    _, result = invoke('phases')
    assert result[:2] == ref[:2] and result[3:] == ref[3:]
    phases = []
    previous = {}
    for stage, name in enumerate(stages, 1):
        cumulative = {line.split()[2]: int(line.split()[3]) for line in result[2].decode().splitlines() if line.startswith(f'phase {stage} ')}
        phases.append({'stage': stage, 'function': name, 'calls': {k: v-previous.get(k, 0) for k, v in cumulative.items()}})
        previous = cumulative
    (Path(__file__).parent / 'phase-counts.json').write_text(json.dumps(phases, indent=2)+'\n')
    print(json.dumps(phases, indent=2))


if __name__ == '__main__':
    main()
