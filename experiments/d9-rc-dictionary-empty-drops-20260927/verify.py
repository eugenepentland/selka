#!/usr/bin/env python3
"""Check preserved dictionary empty-drop evidence; no benchmarks are rerun."""
import gzip
import hashlib
import json
from pathlib import Path
import statistics
import sys

ROOT = Path(__file__).resolve().parent


def content(name):
    return gzip.decompress((ROOT / (name + '.gz')).read_bytes())


def data(name):
    return json.loads(content(name))


def digest(bits):
    return hashlib.sha256(bits).hexdigest()


def balanced(counts):
    assert counts['runtime'] == 'rc-v3-counting' and not counts['saturated']
    assert counts['heap_allocate'] == counts['retire']
    assert counts['hold_acquire'] == counts['hold_release']
    assert counts['owner_acquire'] + counts['heap_allocate'] == counts['owner_release']


def trace(row):
    return '\n'.join(line for line in row['stderr'].splitlines()
                     if not line.startswith('MYLANG_RC_COUNTS '))


def main():
    for name, row in json.loads((ROOT / 'files.json').read_text()).items():
        bits = content(name)
        assert len(bits) == row['bytes'] and digest(bits) == row['sha256'], name
    identity = json.loads((ROOT / 'identity.json').read_text())
    assert identity['base'] == '0f5e4d0f9b68bfb21b18cf1f0a0c286d5fbe2411'
    receipt = data('measurements.json')
    assert receipt['compilers'] == identity['compilers']
    assert receipt['source']['sha256'] == digest(content('workload/dict_count.my'))
    assert len(receipt['builds']) == 8 and len(receipt['runs']) == 22
    for row in receipt['builds']:
        assert row['status'] == 0 and row['manifest']['backend'] == row['backend']
        if row['backend'] == 'llvm':
            assert row['manifest']['optimization'] == '3'
            assert row['manifest']['lto'] and not row['manifest']['thin_lto']
    counts = None
    for row in receipt['runs']:
        assert row['status'] == 0 and row['stdout'] == content('workload/dict_count.expected').decode()
        if row.get('stats'):
            balanced(row['counts'])
            counts = counts or row['counts']
            assert counts == row['counts']
            continue
        fields = [line.split(',') for line in row['perf'].splitlines()]
        active = [f for f in fields if len(f) > 4 and f[0].isdigit() and 'instructions' in f[2]]
        assert len(active) == 1 and float(active[0][4]) == 100.0
        assert int(active[0][0]) == row['instructions']
        binary = next(x for x in identity['binaries'] if x['side'] == row['side'] and x['backend'] == row['backend'])
        assert row['binary_sha256'] == binary['sha256']
    assert counts['heap_allocate'] == 2029 and counts['clone_shell'] == 0
    assert counts['owner_acquire'] == counts['hold_acquire'] == 2001 and counts['unique_check'] == 1001
    for backend in ['qbe', 'llvm']:
        for side in ['gc', 'before', 'after']:
            values = [x['instructions'] for x in receipt['runs']
                      if x['side'] == side and x['backend'] == backend and not x.get('stats')]
            assert len(values) == 3 and statistics.median(values) == receipt['medians'][side + '-' + backend]
        assert receipt['medians']['after-' + backend] < receipt['medians']['before-' + backend]
        assert receipt['medians']['after-' + backend] > 1.3 * receipt['medians']['gc-' + backend]
    emission = receipt['emission']
    assert [x['markers'] for x in emission] == [0, 5]
    assert [x['slot_drop'] for x in emission] == [23, 18]
    assert [x['unique'] for x in emission] == [2, 2]
    for side in ['before', 'after']:
        il = content(side + '-main.ssa').decode()
        assert '%rcentries =l alloc8 416' in il and '%rcguards =l alloc8 104' in il
        assert 'call $myl_qbe_rc_frame_enter' in il
    native = data('native-inspection.json')
    for backend in ['qbe', 'llvm']:
        assert native['before-' + backend]['slot_drop_calls'] - native['after-' + backend]['slot_drop_calls'] == 5
    guests = data('guests.json')['runs']
    assert len(guests) == 8 and sum(json.loads(x['stdout'])['passed'] for x in guests) == 64
    assert all(x['status'] == 0 and json.loads(x['stdout'])['failed'] == 0 for x in guests)
    controls = data('controls.json')['runs']
    assert len(controls) == 40
    for row in controls:
        balanced(row['counts'])
        if row['side'] != 'before':
            continue
        other = next(x for x in controls if x['side'] == 'after'
                     and all(x[k] == row[k] for k in ['backend', 'case', 'budget', 'options']))
        assert (row['status'], row['stdout'], trace(row), row['counts']) == (other['status'], other['stdout'], trace(other), other['counts'])
    reentrant = data('reentrant.json')['runs']
    assert len(reentrant) == 4
    for row in reentrant:
        balanced(row['counts'])
        assert row['status'] == 0 and row['stdout'] == 'status=0 phase=2 observed=1 bad=0 result=10\n'
    if '--live' in sys.argv:
        for row in [*identity['compilers'].values(), *identity['binaries']]:
            assert digest(Path(row['path']).read_bytes()) == row['sha256']
    print('Verified18 full-size instruction observations at100%,4 identical counted runs,64 assertions,40 paired controls and4 real-finalizer entries.')


if __name__ == '__main__':
    main()
