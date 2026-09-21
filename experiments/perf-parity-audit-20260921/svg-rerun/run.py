#!/usr/bin/env python3
"""Rerun of experiments/svg-gap-fixes-20260921/run.py against the merged compiler (a1a5e609): the pre-merge production arms are the before arms."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/perf-audit-20260921/svg-merged'
BASE = ROOT / '.tmp/full-svg-benchmark-20260921'
OLD = ROOT / '.tmp/svg-gap-fixes-20260921'  # the pre-merge production arms become the 'before' arms
COMPILER = WORK / 'mylang-merged'
DOCS = ('lib/modules/straps-synth-lmx2595.sexp', 'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
CASES = ('fixture', 'changed-net', 'changed-value')
POLICIES = ('gc-lto', 'arena-lto', 'gc-lto-bounded', 'arena-lto-bounded')
OLD_DECLARATIONS = 'io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def environment():
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('MYLANG_') or key in ('LD_PRELOAD', 'GOGC', 'GOMEMLIMIT', 'GODEBUG', 'GOMAXPROCS', 'NETLISP_LIB_DIR', 'NETLISP_STDLIB_DIR'):
            del env[key]
    env['MYLANG_MEMORY_LIMIT'] = '268435456'
    return env


def prepare():
    WORK.mkdir(parents=True, exist_ok=True)
    for policy in ('gc', 'arena'):
        guest = WORK / f'guest-{policy}'
        guest.mkdir(exist_ok=True)
        for source in (ROOT / 'src/schematic/guest').glob('*.my'):
            shutil.copy2(source, guest / source.name)
        if policy == 'arena':
            entry = guest / 'main.my'
            text = entry.read_text()
            head, body = text.split('def main(host: Host) -> Result[None, int]:\n', 1)
            entry.write_text(head + 'def main(host: Host) -> Result[None, int]:\n    with arena():\n' + ''.join('    ' + line if line.strip() else line for line in body.splitlines(True)))


def build():
    assert COMPILER.exists(), 'Freeze the merged compiler as .tmp/perf-audit-20260921/svg-merged/mylang-merged first'
    prepare()
    records = {}
    for name in POLICIES:
        guest = WORK / ('guest-arena' if name.startswith('arena') else 'guest-gc') / 'main.my'
        emit = [str(COMPILER), 'emit-project-qbe', str(guest), '--drop-debug', '--no-cache']
        if not name.endswith('bounded'):
            emit += ['--drop-step-checks', '--drop-frame-checks']
        result = subprocess.run(emit, cwd=ROOT, env=environment(), capture_output=True, timeout=300)
        assert result.returncode == 0, result.stderr.decode()
        manifest = WORK / f'{name}-emitted.json'
        manifest.write_bytes(result.stdout)
        names = ','.join(d['name'] for d in json.loads(result.stdout)['host']['declarations'])
        (WORK / f'{name}.declared').write_text(names)
        command = [str(COMPILER), 'build', str(guest), '--project', '--provider', 'src/schematic/native_schematic.c',
                   '--backend', 'llvm', '--llvm-adapter', str(ROOT / 'experiments/llvm-backend/qbe_llvm.py'),
                   '--zig', '/home/epentland/.local/bin/zig', '--llvm-opt', '3', '--lto', '--keep-symbols',
                   f'--manifest-file={manifest}', '--cache-dir', str(WORK / f'cache-{name}'), '--report', '-o', str(WORK / name)]
        start = time.perf_counter()
        result = subprocess.run(command, cwd=ROOT, env=environment(), capture_output=True, timeout=1200)
        (OUT / f'{name}-build.stdout').write_bytes(result.stdout)
        (OUT / f'{name}-build.stderr').write_bytes(result.stderr)
        assert result.returncode == 0, (name, result.stderr.decode())
        records[name] = {'emit_argv': emit, 'build_argv': command, 'elapsed_seconds': time.perf_counter()-start,
                         'binary_sha256': sha(WORK / name), 'emitted_sha256': sha(manifest), 'declarations': names,
                         'receipt': json.loads(Path(str(WORK / name) + '.qbe-manifest.json').read_text())}
        print('Built', name, flush=True)
    sources = [*sorted((ROOT / 'src').glob('qbe*')), ROOT / 'src/native_host.h', ROOT / 'src/native_providers.h',
               ROOT / 'src/schematic/native_schematic.c', *sorted((ROOT / 'src/schematic/guest').glob('*.my'))]
    (OUT / 'builds.json').write_text(json.dumps({'compiler_sha256': sha(COMPILER), 'builds': records,
        'sources': {str(p.relative_to(ROOT)): sha(p) for p in sources if p.is_file()}}, indent=2)+'\n')


def invoke(binary, project, bounded=False, stress=False, extra=()):
    output, issue = WORK / 'qualified.svg', WORK / 'qualified.issue'
    output.write_bytes(b''); issue.write_bytes(b'')
    declared = Path(str(binary) + '.declared')
    env = environment()
    env.update(MYLANG_SCHEMATIC_DECLARED=declared.read_text() if declared.exists() else OLD_DECLARATIONS,
               MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
    env.update({f'MYLANG_SCHEMATIC_INPUT_{i}':str(project/path) for i,path in enumerate(DOCS)})
    args = [str(binary), '--print-result']
    if bounded and not any(v.startswith('--max-steps=') for v in extra): args += ['--max-steps=100000000']
    if stress: args += ['--gc-stress']
    result = subprocess.run([*args,*extra], cwd=ROOT, env=env, capture_output=True, timeout=90)
    return result.returncode, result.stdout, result.stderr, output.read_bytes(), issue.read_bytes()


def qualify():
    projects = {case: BASE/'projects'/case for case in CASES}
    variants = ROOT / '.tmp/svg-gap-audit-20260921/algorithm'
    projects.update({p.name.removeprefix('variant-project-'):p for p in variants.glob('variant-project-*')})
    records = {}
    for case, project in projects.items():
        expected = invoke(OLD/'gc-lto', project)
        assert expected[0] == (13 if case == 'empty_net_rejected' else 0), (case,expected[:3])
        for name in POLICIES:
            for stress in (False, True):
                actual = invoke(WORK/name, project, name.endswith('bounded'), stress)
                assert actual == expected, (case,name,stress,actual[:3],expected[:3],actual[4])
        records[case] = {'status':expected[0], 'input_sha256':{p:sha(project/p) for p in DOCS},
                         'svg_sha256':hashlib.sha256(expected[3]).hexdigest(),
                         'issue_sha256':hashlib.sha256(expected[4]).hexdigest(), 'all_normal_and_stress_match':True}
    budgets = {}
    for name in POLICIES:
        if not name.endswith('bounded'): continue
        budgets[name] = {}
        for flag,marker in (('--max-steps=1',b'R_STEP_LIMIT'),('--max-frames=1',b'R_FRAME_LIMIT')):
            actual = invoke(WORK/name, projects['fixture'], True, extra=(flag,))
            assert actual[0] != 0 and marker in actual[2], (name,flag,actual[:3])
            budgets[name][flag] = marker.decode()
    (OUT/'qualification.json').write_text(json.dumps({'cases':records,'budget_rejections':budgets},indent=2)+'\n')
    print('Qualified',len(POLICIES),'builds on',len(projects),'cases normally and under GC stress.',flush=True)


def measure():
    spec = importlib.util.spec_from_file_location('audit', ROOT/'experiments/svg-gap-audit-20260921/audit.py')
    audit = importlib.util.module_from_spec(spec); spec.loader.exec_module(audit)
    audit.OUT, audit.WORK = OUT, WORK
    original_invoke = audit.invoke
    def measured_invoke(binary, *args, **kwargs):
        declared = Path(str(binary) + '.declared')
        if declared.exists(): kwargs['env_extra'] = {**kwargs.get('env_extra',{}), 'MYLANG_SCHEMATIC_DECLARED':declared.read_text()}
        return original_invoke(binary,*args,**kwargs)
    audit.invoke = measured_invoke
    arms = {name:{'binary':str((WORK/name).relative_to(ROOT)), 'sha256':sha(WORK/name), 'bounded':name.endswith('bounded')} for name in POLICIES}
    for name in ('gc-lto','arena-lto','gc-lto-bounded','arena-lto-bounded'):
        arms['before-'+name] = {'binary':str((OLD/name).relative_to(ROOT)),'sha256':sha(OLD/name),'bounded':name.endswith('bounded')}
    for name in ('rust-o3','go-fast','zig-o3'):
        arms[name] = {'binary':str((BASE/name).relative_to(ROOT)),'sha256':sha(BASE/name),'native':True}
    pairs = [[name,'before-'+name] for name in POLICIES]
    pairs += [[name,native] for name in POLICIES for native in ('rust-o3','go-fast','zig-o3')]
    pairs += [['arena-lto','gc-lto'],['arena-lto-bounded','gc-lto-bounded']]
    config = {'arms':arms,'pairs':pairs,'output':'measurements.json'}
    manifest=OUT/'arms.json';manifest.write_text(json.dumps(config,indent=2)+'\n')
    audit.measure(manifest)


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('build','qualify','measure'))
    args=parser.parse_args()
    globals()[args.action]()
