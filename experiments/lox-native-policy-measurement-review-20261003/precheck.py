"""Independent file/ELF/receipt/math reads; completed phases only."""
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import struct

ROOT = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
WORK = ROOT / '.tmp-lox-native-policy-screen-reviewed'
AUTHOR = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-native-policy-20261003')
AS = AUTHOR / '.tmp-lox-native-policy-20261003'
PROTOCOL = ROOT / 'experiments/lox-compiler-runtime-protocol-20261003'
VERSION = 'lox-compiler-runtime-guards-v2'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def doc(path):
    return json.loads(Path(path).read_bytes())


def files(root):
    root = Path(root)
    return {str(p.relative_to(root)): sha(p) for p in sorted(root.rglob('*')) if p.is_file()}


def elf(path):
    data = Path(path).read_bytes()
    h = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    assert h[0][:6] == b'\x7fELF\x02\x01'
    ph = [struct.unpack_from('<IIQQQQQQ', data, h[5] + i * h[9]) for i in range(h[10])]
    rows = [struct.unpack_from('<IIQQQQIIQQ', data, h[6] + i * h[11]) for i in range(h[12])]
    tab = rows[h[13]]
    names = data[tab[4]:tab[4] + tab[5]]
    allocated = {}
    for r in rows:
        if r[2] & 2:
            name = names[r[0]:].split(b'\0', 1)[0].decode()
            data_ = b'' if r[1] == 8 else data[r[4]:r[4] + r[5]]
            allocated[name] = dict(type=r[1], flags=r[2], address=r[3], size=r[5],
                alignment=r[8], sha256=hashlib.sha256(data_).hexdigest())
    return (h[1:5], h[7:11], ph, allocated)


def option(argv, flag):
    assert argv.count(flag) == 1
    return argv[argv.index(flag) + 1]


freeze = doc(AS / 'frozen-source-v2.json')
assert sha(AS / 'frozen-source-v2.json') == 'd2962dbc3edc07a9e505e702eb6cf547e198dbc42eb67e94c5e38b10e696cb43'
wrapper = doc(ROOT / '.tmp-lox-native-policy-prepare-command.json')
assert wrapper['status'] == 0 and wrapper['verified_after']
assert wrapper['before'] == wrapper['after'] and len(wrapper['after']) == 1038
assert wrapper['log_sha256'] == sha(ROOT / '.tmp-lox-native-policy-prepare.log')
expected = {str(AUTHOR / name): h for name, h in freeze['core'].items()}
expected.update({str(Path(freeze['source']) / name): h for name, h in freeze['source37'].items()})
prefix = AS / 'compiler-final-v2'
prefix_map = files(prefix)
assert len(prefix_map) == 16 and prefix_map == wrapper['current_prefix_before']
assert not any(p.is_symlink() for p in prefix.rglob('*'))
expected.update({str(prefix / name): h for name, h in prefix_map.items()})
for name in ['builds-v2.json','public-v2.json','native-v2/completed.json',
             'selected-boundaries-verified-v2/qualification.json',
             'producer-check-final-v2/qualification.json','equivalence-v2.json']:
    expected[str(AS / name)] = sha(AS / name)
for runtime in ['rc', 'gc']:
    for backend in ['llvm', 'qbe']:
        binary = AS / ('native-policy-v2-' + runtime + '-' + backend)
        for p in [binary, Path(str(binary) + '.qbe-manifest.json'), Path(str(binary) + '.qbe-receipt')]:
            expected[str(p)] = sha(p)
        runtime_path = doc(str(binary) + '.qbe-manifest.json')['runtime_object']
        expected[runtime_path] = sha(runtime_path)
for directory in [AUTHOR / 'experiments/lox-native-policy-20261003',
                  ROOT / 'experiments/lox-native-policy-review-20261003', PROTOCOL,
                  ROOT / 'experiments/lox-compiler-runtime-protocol-review-20261003',
                  ROOT / 'experiments/lox-compiler-runtime-protocol-final-review-20261003']:
    expected.update({str(directory / name): h for name, h in files(directory).items()})
for p in [AS / 'frozen-source-v2.json', ROOT / '.tmp-lox-native-policy-source37.json',
          ROOT / '.tmp-lox-native-policy-prepare.py']:
    expected[str(p)] = sha(p)
assert expected == wrapper['after']
for path, h in expected.items():
    assert sha(path) == h
manifest = doc(WORK / 'binaries.json')
prepared = doc(WORK / 'prepared.json')
guards = doc(WORK / 'guards.json')
inputs = doc(WORK / 'preparation-inputs.json')
builds = doc(WORK / 'rebuilt-build.json')
assert prepared['runtime_guard_protocol'] == inputs['protocol'] == VERSION
assert len(guards) == prepared['guards'] == 252
assert sha(WORK / 'guards.json') == prepared['guards_sha256']
assert sha(WORK / 'binaries.json') == prepared['manifest_sha256']
assert sha(WORK / 'runtime-bindings.json') == prepared['runtime_bindings_sha256']
assert manifest['source37']['baseline'] == manifest['source37']['candidate'] == freeze['source37']
assert files(WORK / 'baseline') == files(WORK / 'candidate') == freeze['source37']
assert manifest['compiler_sha256'] == prefix_map['bin/mylang']
assert manifest['qbe_sha256'] == prefix_map['bin/qbe']
assert builds['runtime'] == 'rc' and len(builds['builds']) == 2
qualified = doc(WORK / 'author-qualification.json')
assert qualified['verified_after'] and qualified['before'] == qualified['after']
assert qualified['before']['source37'] == freeze['source37']
assert sha(WORK / 'author-qualification.json') == manifest['qualification_sha256']
roles = {}
reproduction = doc(WORK / 'rebuild-equivalence.json')
for row in builds['builds']:
    assert type(row['status']) is int and row['status'] == 0
    backend = option(row['argv'], '--backend')
    assert '--rc-runtime' in row['argv'] and '--gc-runtime' not in row['argv']
    if backend == 'llvm':
        assert '--qbe' not in row['argv'] and option(row['argv'], '--llvm-opt') == '3' and '--lto' in row['argv']
    else:
        assert option(row['argv'], '--qbe') == inputs['qbe'] and '--lto' not in row['argv']
    path = WORK / 'bin' / ('rebuilt-' + backend)
    assert Path(option(row['argv'], '-o')) == path
    assert sha(path) == row['binary_sha256']
    assert sha(str(path) + '.qbe-manifest.json') == row['manifest_sha256']
    assert sha(row['runtime_object']) == row['runtime_object_sha256']
    roles['rebuilt-' + backend] = path
    candidate = Path(manifest['binaries']['candidate-' + backend])
    assert elf(path) == elf(candidate)
    assert elf(path)[3] == reproduction[backend]['allocated_sections_exact']
    assert reproduction[backend]['rebuilt_sha256'] == sha(path)
    assert reproduction[backend]['qualified_sha256'] == sha(candidate)
for name in ['baseline-llvm','baseline-qbe','candidate-llvm','candidate-qbe']:
    roles[name] = Path(manifest['binaries'][name])
actual_bindings = {}
for role, binary in roles.items():
    sidecar = Path(str(binary) + '.qbe-manifest.json')
    meta = doc(sidecar)
    assert meta['backend'] == role.split('-')[1]
    runtime = meta['runtime_object']
    actual_bindings[role] = dict(binary=str(binary), binary_sha256=sha(binary), manifest=str(sidecar),
        manifest_sha256=sha(sidecar), runtime_object=runtime, runtime_object_sha256=sha(runtime))
assert doc(WORK / 'runtime-bindings.json') == {'protocol': VERSION, 'bindings': actual_bindings}
allowed = set()
base = doc(PROTOCOL / 'protocol-base.json')
for name in ['prepare.py','analyze.py','build.py','elf.py','closeout.py','validation.py','archive.py','runtime_bindings.py','README.md','protocol-base.json']:
    allowed.add(PROTOCOL / name)
for name, row in base['files'].items():
    copy, original = PROTOCOL / 'base' / name, Path(row['original_path'])
    assert sha(copy) == sha(original) == row['sha256']
    allowed.update([copy, original])
for name, row in base['reused'].items():
    copy, current = PROTOCOL / 'base/reused' / name, ROOT / name
    assert sha(copy) == sha(current) == row['sha256']
    allowed.update([copy, current])
for key in ['compiler','qbe','candidate_map','qualification','control_binaries']:
    allowed.add(Path(inputs[key]))
original_bins = set(map(Path, inputs['qualified'].values()))
control = doc(inputs['control_binaries'])
original_bins.update(Path(control['binaries'][arm]) for arm in ['ast-llvm','ast-qbe','rust','go'])
for binary in original_bins:
    allowed.add(binary)
    for suffix in ['.qbe-manifest.json','.qbe-receipt']:
        p = Path(str(binary) + suffix)
        if p.is_file():
            allowed.add(p)
            if suffix.endswith('manifest.json'):
                allowed.add(Path(doc(p)['runtime_object']))
for dirname in ['baseline','candidate','reference','inputs','bin']:
    allowed.update(p for p in (WORK / dirname).rglob('*') if p.is_file())
for name in ['candidate-source37.json','author-qualification.json','binaries.json','rebuilt-build.json',
             'rebuild-equivalence.json','prepare-command.json','prepare-build.log',
             'preparation-inputs.json','runtime-bindings.json']:
    allowed.add(WORK / name)
for row in actual_bindings.values():
    allowed.update(Path(row[key]) for key in ['binary','manifest','runtime_object'])
assert {str(p): sha(p) for p in sorted(allowed)} == guards
for backend in ['llvm','qbe']:
    candidate = manifest['binaries']['candidate-' + backend]
    original = inputs['qualified'][backend]
    assert sha(candidate) == sha(original)
    for suffix in ['.qbe-manifest.json','.qbe-receipt']:
        assert sha(candidate + suffix) == sha(original + suffix)
    for path in [original, original + '.qbe-manifest.json', original + '.qbe-receipt', doc(original + '.qbe-manifest.json')['runtime_object']]:
        assert sha(path) == qualified['before']['artifacts_sha256'][path]
for arm in ['baseline-llvm','baseline-qbe','rust','go']:
    old = {'baseline-llvm':'ast-llvm','baseline-qbe':'ast-qbe'}.get(arm, arm)
    assert sha(manifest['binaries'][arm]) == control['binary_sha256'][old]


def math_result(receipt, before, after, metric):
    values = {(r['case'], r['arm'], r['round']): r for r in receipt['samples']}
    result = {}
    for case in receipt['cases']:
        name = case['id']
        ratios = [values[name,after,i][metric] / values[name,before,i][metric]
                  for i in range(receipt['rounds'])]
        median = statistics.median(ratios)
        result[name] = dict(candidate_over_baseline=median, reduction_pct=100*(1-median),
            paired_ratios=ratios, spread_pct=100*(max(ratios)-min(ratios))/median)
    engines = {}
    for engine in ['vm','tree']:
        ratios = [v['candidate_over_baseline'] for n,v in result.items() if n.startswith(engine+'/')]
        gm = statistics.geometric_mean(ratios)
        engines[engine] = dict(cases=len(ratios),candidate_over_baseline=gm,reduction_pct=100*(1-gm))
    return dict(baseline=before,candidate=after,metric=metric,engines=engines,rows=result)


def equal_math(left, right):
    if isinstance(right,dict):
        return isinstance(left,dict) and set(left)==set(right) and all(equal_math(left[k],v) for k,v in right.items())
    if isinstance(right,list):
        return isinstance(left,list) and len(left)==len(right) and all(equal_math(x,y) for x,y in zip(left,right))
    if type(right) is float:
        return type(left) in [int,float] and math.isclose(left,right,rel_tol=1e-12,abs_tol=1e-12)
    return type(left) is type(right) and left==right


names = {p.stem for p in (WORK / 'reference/benchmarks/lox/bench/scripts').glob('*.lox')}
assert len(names)==13
coverage = {}
for name, phase, arms, count in [('smoke','check',set(manifest['binaries']),156),
        ('screen','counters',{'baseline-llvm','baseline-qbe','candidate-llvm','candidate-qbe'},104)]:
    receipt=doc(WORK/(name+'.json'))
    assert receipt['verified_after'] and receipt['manifest']==manifest
    assert receipt['phase']==phase and receipt['rounds']==1
    assert {c['id'] for c in receipt['cases']}=={engine+'/'+n for engine in ['vm','tree'] for n in names}
    cells={(r['case'],r['arm'],r['round']) for r in receipt['samples']}
    assert len(cells)==len(receipt['samples'])==count
    assert cells=={(engine+'/'+n,arm,0) for engine in ['vm','tree'] for n in names for arm in arms}
    assert set(receipt['binary_sha256'])==arms
    assert all(receipt['binary_sha256'][a]==manifest['binary_sha256'][a] for a in arms)
    cases={c['id']:c for c in receipt['cases']};stats={}
    bench=WORK/'reference/benchmarks/lox/bench'
    sizes=doc(bench/'sizes.json')
    for c in cases.values():
        assert sha(c['script'])==c['script_sha256']
        tier='smoke' if phase=='check' else 'tree'
        assert receipt['tier']==tier and c['size']==sizes[c['name']][tier]
        assert Path(c['script'])==WORK/'inputs'/(c['name']+'.'+tier+'.lox')
        assert Path(c['expected'])==bench/'expected'/(c['name']+'.'+tier+'.out')
        source=bench/'scripts'/(c['name']+'.lox')
        first,rest=source.read_text().split('\n',1)
        assert first.startswith('var N = ')
        assert Path(c['script']).read_text()==f"var N = {c['size']};\n"+rest
    for r in receipt['samples']:
        assert type(r['status']) is int and r['status']==0
        assert r['stdout_sha256']==sha(cases[r['case']]['expected'])
        if phase=='check':
            m=re.fullmatch(r'\[stats\] engine=(vm|tree) allocations=(\d+) collections=(\d+) freed=(\d+) live=(\d+)\n',r['stderr'])
            assert m and m[1]==cases[r['case']]['engine']
            actual=dict(zip(['allocations','collections','freed','live'],map(int,m.groups()[1:])))
            assert actual==r['collector_stats']
            assert stats.setdefault(r['case'],actual)==actual
        else:
            assert not r['stderr']
            for event in ['instructions','cycles','branches','branch-misses']:
                assert type(r[event]) is int and r[event]>=0 and r[event+'_running_pct']==100
    command=doc(WORK/(name+'.command.json'))
    assert command['status']==0 and command['sources_verified_after']
    assert command['source_hashes_before']==command['source_hashes_after']
    assert command['manifest_sha256']==sha(WORK/'binaries.json')
    assert command['log_sha256']==sha(WORK/(name+'.log'))
    assert command['argv'][2]==phase and option(command['argv'],'--rounds')=='1'
    assert command['source_hashes_after']=={arm:v['hashes'] for arm,v in manifest['candidate_sources'].items()}
    argv=command['argv']
    assert Path(option(argv,'--work')).name==WORK.name
    assert Path(option(argv,'--out')).name==name+'.json'
    assert set(option(argv,'--arms').split(','))==arms
    assert option(argv,'--tier')==receipt['tier']
    assert option(argv,'--cpu')==str(receipt['cpu'])=='10'
    assert argv.count('--stats')==int(phase=='check')
    coverage[name]=count
screen=doc(WORK/'screen.json')
metrics={}
for metric, filename in [('instructions','screen-instructions.json'),('cycles','screen-cycles.json')]:
    analysis=doc(WORK/filename)
    assert analysis['receipt_sha256']==sha(WORK/'screen.json')
    assert analysis['runtime_guard_protocol']==VERSION and analysis['stable_guards_after']==252
    assert analysis['screen_only'] and analysis['coverage_verified'] and analysis['samples']==104
    expected={f'candidate-{b}-over-baseline-{b}':math_result(screen,'baseline-'+b,'candidate-'+b,metric) for b in ['llvm','qbe']}
    assert equal_math(analysis['comparisons'],expected)
    metrics[metric]={k:v['engines'] for k,v in expected.items()}
print(json.dumps(dict(scope='Completed preparation/smoke/screen only; active wall excluded',
    wrapper_inputs=1038,exact_protocol_guards=252,exact_runtime_roles=6,
    measured_qualified_ELFs_sidecars_exact=True,allocated_rebuilds_exact=True,
    completed_coverage=coverage,PMU_four_events100=True,screen_math_verified=True,
    metrics=metrics,fullwall_or_counter_or_closeout_or_archive_claim=False,
    no_guest_compiler_or_perf_execution=True),indent=2))
