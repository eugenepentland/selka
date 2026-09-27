"""Validate archived identities, full output checks and ownership balances."""
from pathlib import Path
import gzip
import hashlib
import json
import statistics

ROOT = Path(__file__).resolve().parent


def read(name):
    p = ROOT / name
    return json.loads(gzip.decompress(p.read_bytes()) if name.endswith('.gz') else p.read_bytes())


def balanced(c):
    assert not c['saturated'] and not c['owner_limit'] and not c['hold_limit']
    assert c['heap_allocate'] == c['retire']
    assert c['owner_acquire'] + c['heap_allocate'] == c['owner_release']
    assert c['hold_acquire'] == c['hold_release']


def main():
    for name, digest in read('identities.json')['archive_sha256'].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    identity = read('identities.json')
    data = read('measure.json.gz')
    assert data['compiler_sha256']['after'] == identity['compiler_sha256']
    assert len(data['builds']) == 8 and len(data['checks']) == 24 and len(data['runs']) == 36
    for b in data['builds']:
        assert b['exit'] == 0 and b['manifest']['backend'] == b['backend']
    for check in data['checks']:
        assert check['ok'] and check['status'] == 0
        if check['counted']:
            balanced(check['counts'])
    for run in data['runs']:
        assert run['exit'] == 0 and run['percent_running'] == 100
        assert run['event_runtime_ns'] > 0 and run['instructions'] > 0
        assert run['svg_sha256'] == next(c['svg_sha256'] for c in data['checks'] if c['case'] == run['case'])
    for case in ('fixture', 'changed-net', 'changed-value'):
        for arm in ('before', 'after'):
            counts = [r['counts'] for r in data['checks'] if r['arm'] == arm and r['case'] == case and r['counted']]
            assert len(counts) == 2 and counts[0] == counts[1]
        for backend in ('qbe', 'llvm'):
            medians = {arm: statistics.median(r['instructions'] for r in data['runs'] if r['arm'] == arm and r['backend'] == backend and r['case'] == case) for arm in ('before', 'after')}
            print(case, backend, medians, medians['after'] / medians['before'])
    guest_data = read('guests-final.json.gz')
    assert guest_data['compiler_sha256'] == identity['compiler_sha256']
    before = read('before-emitted.json.gz')['functions']
    after = read('after-emitted.json.gz')['functions']
    def entry(functions, name, alternate):
        return next(f for f in functions if f['name'] == name and f['symbol'].endswith('_rc_borrow') == alternate)
    for name in ('layout::partPin', 'layout::innerPin', 'layout::depth'):
        assert entry(before, name, False)['il'] == entry(after, name, False)['il']
    inner = entry(after, 'layout::innerPin', True)['il']
    picked = entry(after, 'layout::partPin', True)
    depth = entry(after, 'layout::depth', False)
    assert inner.count('call $' + picked['symbol'] + '(') == 2
    assert inner.count('call $' + depth['symbol'] + '(') == 2
    assert 'call $myl_rc_native_' not in inner
    assert 'call $myl_rc_native_' not in depth['il']
    guests = guest_data['runs']
    assert len(guests) == 4
    for run in guests:
        assert run['exit'] == 0 and run['stdout'] == 'True\n' * 5
        assert run['manifest']['backend'] == run['backend']
        if run['mode'] == 'rc':
            balanced(run['counts'])
    trap_data = read('traps.json.gz')
    assert trap_data['compiler_sha256'] == identity['compiler_sha256']
    traps = trap_data['runs']
    assert len(traps) == 12
    for run in traps:
        assert run['manifest']['backend'] == run['backend']
        assert run['exit'] == 1 and run['stdout'] == 'before\n' and {'bounds':'R_LIST_BOUNDS','steps':'R_STEP_LIMIT','frames':'R_FRAME_LIMIT'}[run['case']] in run['stderr']
        if run['mode'] == 'rc':
            balanced(run['counts'])
    print('Verified 24 exact schematic output checks, 36 unscaled instruction samples, 20 assertions and 12 bounds/step/frame traps.')


if __name__ == '__main__':
    main()
