"""Run under one shared build admission lease; edits only a new scratch tree."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, required=True)
parser.add_argument('--scratch', type=Path, required=True)
args = parser.parse_args()
here = Path(__file__).resolve().parent
root = args.source_root.resolve()
scratch = args.scratch.resolve()
manifest = json.loads((here / 'inputs.json').read_text())
base = manifest['base_commit']


def sha(data):
    return hashlib.sha256(data).hexdigest()


def call(argv, *, cwd=None, env=None):
    argv = list(map(str, argv))
    process = subprocess.run(argv, cwd=cwd, env=env, capture_output=True,
                             text=True, timeout=90)
    return dict(argv=argv, status=process.returncode,
                stdout=process.stdout, stderr=process.stderr)


def git_source(path):
    return subprocess.check_output(['git', 'show', base + ':' + path], cwd=root)


def save():
    (here / 'results.json').write_text(json.dumps(result, indent=2) + '\n')


scratch.mkdir(parents=True, exist_ok=False)
driver = git_source('src/core/driver.zig').decode()
section = driver.split('pub const runtime_source =', 1)[1].split('/// One build:', 1)[0]
runtime_paths = ['src/core/' + name for name in re.findall(r'@embedFile\("([^\"]+)"\)', section)]
paths = list(runtime_paths)
patch_bytes = []
for item in manifest['patches']:
    data = (here / item['path']).read_bytes()
    assert sha(data) == item['sha256'], item['path']
    patch_bytes.append(data)
    paths.extend(re.findall(r'^--- a/(.+)$', data.decode(), re.MULTILINE))
inputs = {}
for path in dict.fromkeys(paths):
    data = git_source(path)
    target = scratch / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    inputs[path] = {'before_sha256': sha(data)}
result = dict(scope='Unapplied combined native C3 draft, without ownership selector; not generated-guest or package qualification.',
              base_commit=base, source_root=str(root), scratch=str(scratch),
              zig=os.environ['ZIG'], zig_sha256=sha(Path(os.environ['ZIG']).read_bytes()),
              patches=[], inputs=inputs, fixtures={}, passed=False)
for item, data in zip(manifest['patches'], patch_bytes):
    patch = call(['patch', '--batch', '--fuzz=0', '-p1', '-i', here / item['path']], cwd=scratch)
    result['patches'].append(dict(item, apply=patch))
    save()
    if patch['status'] != 0:
        raise SystemExit('Draft patch failed: ' + item['path'])
for path in inputs:
    inputs[path]['after_sha256'] = sha((scratch / path).read_bytes())
    inputs[path]['changed'] = inputs[path]['before_sha256'] != inputs[path]['after_sha256']
runtime = b'\n'.join((scratch / path).read_bytes() for path in runtime_paths)
assembly = scratch / 'native'
assembly.mkdir()
(assembly / 'core_rt.c').write_bytes(runtime)
result['runtime_sha256'] = sha(runtime)
result['runtime_paths_in_order'] = runtime_paths
result['selectors_remaining'] = {
    path: [i + 1 for i, line in enumerate((scratch / path).read_text().splitlines())
           if 'MYL_ZERO_RC' in line]
    for path in runtime_paths if b'MYL_ZERO_RC' in (scratch / path).read_bytes()
}
forbidden = re.compile(r'\b(?:count_(?:retain|release|release_shared|is_unique)|myl_core_(?:retain(?:_slow)?|release|share|free_block|task_submit|task_result|group_close))\b')
runtime_text = runtime.decode()
result['poison_directives'] = [line for line in runtime_text.splitlines()
                               if line.startswith('#pragma GCC poison ')]
operational_source = '\n'.join(line for line in runtime_text.splitlines()
                               if not line.startswith('#pragma GCC poison '))
result['legacy_source_symbols'] = sorted(set(forbidden.findall(operational_source)))
passed = not result['selectors_remaining'] and not result['legacy_source_symbols']
save()
for name in ['capacity', 'owned']:
    source = assembly / (name + '.c')
    shutil.copyfile(here / (name + '-fixture.c'), source)
    binary = assembly / name
    row = {'source_sha256': sha(source.read_bytes()), 'runs': []}
    result['fixtures'][name] = row
    row['build'] = call([os.environ['ZIG'], 'cc', '-O2', '-std=c11', '-pthread', source, '-o', binary])
    row['passed'] = row['build']['status'] == 0
    if row['passed']:
        row['binary_sha256'] = sha(binary.read_bytes())
        symbols = call(['nm', binary])
        (here / (name + '.nm')).write_text(symbols['stdout'])
        row['symbols_sha256'] = sha(symbols['stdout'].encode())
        row['forbidden_symbols'] = sorted(set(forbidden.findall(symbols['stdout'])))
        row['passed'] &= symbols['status'] == 0 and not row['forbidden_symbols']
        for scenario in range(13) if name == 'capacity' else [None]:
            run = call([binary, *([str(scenario)] if scenario is not None else [])],
                       env=dict(os.environ, MYL_CORE_LEAKCHECK='1'))
            expected_status = 1 if scenario is not None and scenario != 0 else 0
            expected_out = ('preserved\n' if scenario == 0 else
                            'owned layout copy rotate reverse transfer drop preserved\n' if scenario is None else '')
            expected_err = ('' if expected_status == 0 else
                            'error[R_MEMORY_BUDGET]: memory budget exhausted; raise it with --max-memory=SIZE\n' if scenario == 9 else
                            'fatal: out of memory\n')
            run['scenario'] = scenario
            run['passed'] = (run['status'] == expected_status and run['stdout'] == expected_out
                             and run['stderr'] == expected_err)
            row['runs'].append(run)
            row['passed'] &= run['passed']
    passed &= row['passed']
    save()
    print(name, row['passed'], flush=True)
negative = call([os.environ['ZIG'], 'cc', '-O2', '-std=c11', '-pthread', '-I', assembly,
                 '-c', here / 'count-member-negative.c', '-o', assembly / 'forbidden-count.o'])
negative['passed'] = negative['status'] != 0 and 'no member named' in negative['stderr'] and 'count' in negative['stderr']
result['count_member_negative'] = negative
passed &= negative['passed']
result['passed'] = bool(passed)
save()
print('combined', result['passed'], result['runtime_sha256'], flush=True)
raise SystemExit(0 if passed else 1)
