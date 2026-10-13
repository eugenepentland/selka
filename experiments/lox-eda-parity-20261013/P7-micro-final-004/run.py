#!/usr/bin/env python3
"""Authorized C4 six-cell campaign; interleave one reviewed window per cell."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path.cwd()
HERE = Path(__file__).resolve().parent
P4 = Path('/home/epentland/ai/canopy/mylang-lox-eda-parity-20261013-p4/experiments/lox-eda-parity-20261013/P4/micro-regression-final-004')
COORDINATOR = Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012')
TOOLS = Path('/home/epentland/ai/canopy/mylang-lox-eda-parity-20261013-p4/experiments/text-gaps-20261012/bench/tools/measure.py')
WINDOWS = ROOT / 'experiments/lox-eda-parity-20261013/P7-micro-windows/windows.py'
DEST = ROOT / '.tmp/lox-eda-parity/P7-micro-windows/final-004'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    assert not os.environ.get('MYLANG_ADMISSION_KIND'), 'campaign never nests admissions'
    assert not (HERE / 'initial-receipt.json').exists(), 'never overwrite a campaign'
    gate_path = COORDINATOR / 'experiments/lox-eda-parity-20261013/coordinator/gate-003/last-run.json'
    gate = json.loads(gate_path.read_text())
    assert gate['success'] and gate['inputs_stable']
    binding = json.loads((P4 / 'compiler-binding.json').read_text())
    assert binding['source_commit'] == '42a93ae15b0990778379066475d3b803a596cf07'
    assert binding['compiler_sha256'] == '6c3e20ff94dcfdbe6c47e8d8bd5ec14b6a32cf3d35e9c3be17c253db1626d9df'
    assert sha(binding['receipt']) == binding['receipt_sha256']
    common = json.loads(Path(binding['receipt']).read_text())
    assert common['compiler_sha256'] == binding['compiler_sha256']
    paths = {str(Path(__file__).resolve()), str(WINDOWS), str(TOOLS), str(gate_path), str(binding['receipt'])}
    paths.update(str(P4 / name) for name in ('compiler-binding.json', 'build-validation.json', 'builds.json', 'inputs.json', 'untimed-qualification.json'))
    for item in common['installation_files']:
        path = Path(common['installation']) / item['path']
        assert sha(path) == item['sha256']
        paths.add(str(path))
    specs = sorted((P4 / 'specs').glob('*.json'))
    assert {p.stem for p in specs} == {c+'.'+p for c in ('csv_aggregate','json_transform','string_split') for p in ('small','large')}
    commands = []
    for spec_path in specs:
        spec = json.loads(spec_path.read_text())
        output = DEST / spec_path.stem
        assert not output.exists(), 'fresh final output required'
        assert spec['provenance']['host_snapshot']['path'] == str(output / 'cell.host-before.json')
        assert (len(spec['arms']),spec['warmups'],spec['rounds'],spec['rss_rounds']) == (7,3,15,3)
        paths.add(str(spec_path))
        for path in spec['files']:
            if not Path(path).exists():
                assert path == str(output / 'cell.host-before.json'), path
            else:
                paths.add(path)
        for entry in [*spec['arms'].values(), *spec['counted'].values()]:
            assert sha(entry['binary']) == entry['sha256']
            paths.add(entry['binary'])
        commands.append({'cell':spec_path.stem,'output':str(output),'argv':[sys.executable,'-B',str(WINDOWS),'--spec',str(spec_path),'--tools',str(TOOLS),'--output',str(output),'--cpu','8','--timeout','120','--window-seconds','55','--max-windows','1']})
    pins = {p:sha(p) for p in sorted(paths)}
    (HERE / 'initial-receipt.json').write_text(json.dumps({'status':'authorized_prepared','scope':6,'compiler_binding':binding,'gate_sha256':sha(gate_path),'inputs':pins,'commands':commands,'note':'One reviewed exclusive timing window per cell per cycle; original historical samples not pooled.'},indent=2)+'\n')
    rows=[]
    cycle=0
    while any(not (Path(c['output'])/'COMPLETE.json').exists() for c in commands):
        for item in commands:
            if (Path(item['output'])/'COMPLETE.json').exists():
                continue
            assert all(sha(p)==h for p,h in pins.items()), 'input changed before timing window'
            label=item['cell']+'.cycle%03d'%cycle
            with (HERE/(label+'.log')).open('wb') as log:
                result=subprocess.run(item['argv'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
            row={'cell':item['cell'],'cycle':cycle,'argv':item['argv'],'returncode':result.returncode,'log':str(HERE/(label+'.log'))}
            rows.append(row)
            (HERE/'execution.json').write_text(json.dumps(rows,indent=2)+'\n')
            assert result.returncode==0, row
            assert all(sha(p)==h for p,h in pins.items()), 'input changed during timing window'
            print(item['cell'],cycle,'complete' if (Path(item['output'])/'COMPLETE.json').exists() else 'checkpointed',flush=True)
        cycle+=1
    results={}
    for item in commands:
        output=Path(item['output']);doc=json.loads((output/'cell.json').read_text());marker=json.loads((output/'COMPLETE.json').read_text());assert sha(output/'cell.json')==marker['cell_sha256'];assert all(sha(p)==h for p,h in doc['identities'].items());assert doc['identities']==doc['identities_after']
        for v in doc['counted'].values():
            if v.get('counter_path'):assert sha(v['counter_path'])==v['counter_sha256']
        results[item['cell']]={'path':str(output/'cell.json'),'sha256':sha(output/'cell.json'),'complete_marker_sha256':sha(output/'COMPLETE.json'),'window_count':len(doc['windows']),'statuses':doc['arm_status'],'counted_statuses':{a:v['status'] for a,v in doc['counted'].items()}}
    assert all(sha(p)==h for p,h in pins.items())
    (HERE/'completed-receipt.json').write_text(json.dumps({'status':'complete','scope':6,'inputs':pins,'results':results,'execution_count':len(rows)},indent=2)+'\n')
    print('six C4 cells finished; raw results retained',flush=True)


if __name__=='__main__':main()
