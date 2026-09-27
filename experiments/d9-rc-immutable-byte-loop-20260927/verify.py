#!/usr/bin/env python3
"""Verify immutable-byte evidence without rerunning performance workloads."""
from pathlib import Path
import gzip, hashlib, json, statistics, sys, tarfile

root = Path(__file__).resolve().parent
sha = lambda value: hashlib.sha256(value).hexdigest()
def read(name):
    path = root / name
    return gzip.decompress(path.read_bytes()) if name.endswith('.gz') else path.read_bytes()
def data(name):
    return json.loads(read(name))
def balanced(c):
    assert not c['saturated']
    assert c['heap_allocate'] == c['retire']
    assert c['owner_acquire'] + c['heap_allocate'] == c['owner_release']
    assert c['hold_acquire'] == c['hold_release']

identity = data('identity.json')
for name, digest in identity['archive'].items():
    assert sha((root / name).read_bytes()) == digest, name
with tarfile.open(root / 'measured-source.tar.gz') as archive:
    for name, digest in identity['measured_source'].items():
        assert sha(archive.extractfile(name).read()) == digest, name
assert data('final-emission-identity.json')['bytes_equal_measured']
assert data('refusal.json')['source_restored']
assert data('refusal.json')['fast_copy_discarded']
assert data('refusal.json')['fallback_bounds_and_drop_present']
guard = data('guard-probe.json')['runs'][-1]
assert guard['exit'] == 0
for line in guard['stdout'].splitlines():
    original, fast, remaining = map(int, line.split())
    assert fast == (original == 0) and original == remaining
assert len(guard['stdout'].splitlines()) == 7

validation = data('validation.json.gz')['runs']
assert len(validation) == 8
for row in validation:
    assert row['build_exit'] == row['exit'] == 0 and row['stdout'] == ''
    assert row['manifest']['backend'] == row['backend']
    if row['mode'] == 'rc': balanced(row['counts'])
    else: assert '--gc-stress' in row['environment']['MYLANG_OPTIONS']
for backend in ('qbe', 'llvm'):
    rows = [x for x in validation if x['backend'] == backend and x['mode'] == 'rc']
    assert rows[0]['counts'] == rows[1]['counts']
probe = data('refusal-validation.json.gz')['runs']
assert len(probe) == 2
for row in probe:
    assert row['build_exit'] == row['exit'] == 0 and row['stdout'] == ''
    balanced(row['counts'])
    assert row['counts'] == next(x['counts'] for x in validation if x['backend'] == row['backend'] and x['mode'] == 'rc')

traps = data('traps.json.gz')['rows']
assert len(traps) == 8
ntrap = nsuccess = 0
for row in traps:
    assert row['build_exit'] == 0 and row['manifest']['backend'] == row['backend']
    for run in row['runs']:
        balanced(run['counts'])
        if run['exit'] == 0:
            nsuccess += 1
            assert run['stdout'] == 'before\n210\n'
        else:
            ntrap += 1
            code = 'R_STEP_LIMIT' if row['mode'] == 'steps' else 'R_OVERFLOW' if run['case'] == 'overflow' else 'R_LIST_BOUNDS'
            assert run['exit'] == 1 and code in run['stderr']
for backend in ('qbe', 'llvm'):
    for mode in ('fast', 'steps'):
        a, b = [x for x in traps if x['backend'] == backend and x['mode'] == mode]
        assert [(x['exit'], x['stdout'], x['counts']) for x in a['runs']] == [(x['exit'], x['stdout'], x['counts']) for x in b['runs']]
steps = data('step-boundaries.json.gz')
assert len(steps) == 8
for row in steps:
    assert row['exit'] == 1 and row['stdout'] == 'before\n' and 'R_STEP_LIMIT' in row['stderr']
    balanced(row['counts'])
assert ntrap + len(steps) == 24 and nsuccess == 12

builds = data('benchmark-builds.json.gz')['rows']
final = data('final-builds.json.gz')['rows']
assert len(builds) == 8 and len(final) == 4
for row in builds + final:
    assert row['exit'] == 0 and row['manifest']['backend'] == row['backend']
for row in data('final-binary-identity.json'):
    a = next(x for x in builds if (x['arm'], x['backend'], x['counted']) == ('after', row['backend'], row['counted']))
    b = next(x for x in final if (x['backend'], x['counted']) == (row['backend'], row['counted']))
    assert a['binary_sha256'] == b['binary_sha256'] == row['sha256'] and row['identical']
runs = data('measurements.json.gz')['runs']
assert len(runs) == 28
expected = read('bytes_scan.expected').decode()
for row in runs:
    assert row['exit'] == 0 and row['stdout'] == expected
    if row['phase'] == 'instructions': assert row['event_running_percent'] == 100
    elif row['phase'] == 'counts': balanced(row['counts'])
    else: assert row['guest_max_rss_kib'] > 0
summary = data('summary.json')
accepted = data('accepted-gc-reference.json')['samples']
for backend in ('qbe', 'llvm'):
    counts = [x['counts'] for x in runs if x['backend'] == backend and x['phase'] == 'counts']
    assert counts[0] == counts[1]
    for arm in ('before', 'after'):
        values = [x['instructions'] for x in runs if (x['arm'], x['backend'], x['phase']) == (arm, backend, 'instructions')]
        assert len(values) == 3 and statistics.median(values) == summary[backend][arm]['instructions']
    denominator = accepted['parity/micro/bytes_scan|' + backend]['medians']['gc']['instructions']
    assert denominator == summary[backend]['accepted_gc_instructions']
    assert summary[backend]['after_over_accepted_gc'] == summary[backend]['after']['instructions'] / denominator
assert '17 passed' in read('focus-bytes-final.log.gz').decode()
assert '15 passed' in read('focus-initial.log.gz').decode()
assert '88 check(s) passed' in read('guardian-final.log').decode()

if '--live' in sys.argv:
    for compiler in [*identity['measured_compilers'].values(), identity['final_compiler'], identity['probe_compiler']]:
        assert sha(Path(compiler['path']).read_bytes()) == compiler['sha256'], compiler['path']
    for row in builds + final:
        assert sha(Path(row['binary']).read_bytes()) == row['binary_sha256'], row['binary']
    for row in validation + probe:
        assert sha(Path(row['run_command'][0]).read_bytes()) == row['binary_sha256']
print('PASS: 12 full instruction samples at 100%, 12 direct guest RSS samples, 4 identical count controls, 50 guest assertions, 24 traps/12 successes, final guest identity, Guardian 88')
