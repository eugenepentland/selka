"""Five fresh private C3 modes under one shared build admission; no timing."""
from pathlib import Path
import hashlib, json, os, subprocess

HERE = Path(__file__).resolve().parent
plan = json.loads((HERE / 'contract-plan.json').read_text())
ROOT = Path(plan['workdir'])
PRIVATE = Path(plan['private_module'])
assert os.environ.get('MYLANG_ADMISSION_KIND') == 'build'
assert plan['compiler_sha256'] == '6842cc711ca6f6eadf2967a76ca60f57044ec06e0c9c2cf15b2834fd3cdebbaf'
def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def unchanged():
    assert sha(plan['compiler']) == plan['compiler_sha256']
    assert sha(plan['common_receipt']) == plan['common_receipt_sha256']
    common = json.loads(Path(plan['common_receipt']).read_text())
    assert common['source_commit'] == '91f5b5d3010893e7642a8fbee90fa910aa7fabab'
    assert len(plan['installation_files']) == 6
    assert all(sha(Path(plan['installation']) / name) == digest for name, digest in plan['installation_files'].items())
    source = Path(plan['canonical_source_root'])
    actual = {str(f.relative_to(source)): sha(f) for f in sorted(source.rglob('*')) if f.is_file() and (f.suffix == '.my' or f.name == 'mylang.json')}
    assert actual == plan['canonical_source_pins']
    for name, digest in actual.items():
        if name != 'diagram_membership.my':
            assert sha(PRIVATE.parent / name) == digest
    assert sha(PRIVATE) == plan['adapted_module_sha256']
    assert hashlib.sha256(PRIVATE.read_bytes()[:plan['prefix_bytes']]).hexdigest() == plan['prefix_sha256']
env = {**os.environ, **plan['environment'], 'TMPDIR': str(PRIVATE.parent.parent)}
env.pop('MYLANG_COUNTERS', None)
records = {'label': 'fresh C3 private diagram contracts; canonical suite is coordinator-owned',
           'reused_test_results': False, 'plan_sha256': sha(HERE / 'contract-plan.json'),
           'workdir': str(ROOT), 'compiler_sha256': plan['compiler_sha256'], 'modes': {}}
for mode, admitted_command in plan['commands'].items():
    unchanged()
    command = admitted_command[2:]
    stdout = HERE / (mode + '.json')
    stderr = HERE / (mode + '.stderr')
    with stdout.open('w') as out, stderr.open('w') as err:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=out, stderr=err)
    unchanged()
    row = {'fresh': True, 'reused': False, 'command': command,
           'shared_admission': 'one outer build lease; no nested admission',
           'returncode': result.returncode, 'stdout_sha256': sha(stdout), 'stderr_sha256': sha(stderr)}
    if stdout.stat().st_size:
        doc = json.loads(stdout.read_text())
        row['counts'] = {k: doc[k] for k in ['passed', 'failed', 'skipped', 'cached', 'unsupported']}
    records['modes'][mode] = row
    (HERE / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
    assert result.returncode == 0, (mode, row)
    assert row['counts'] == {'passed': 3, 'failed': 0, 'skipped': 0, 'cached': 0, 'unsupported': 0}, (mode, row)
records['status'] = 'passed; 3/3 in all five fresh modes'
(HERE / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
print(records['status'])
