"""Check archived proof controls and matched performance identities without builds."""
from pathlib import Path
import gzip
import hashlib
import json
import statistics

ROOT = Path(__file__).resolve().parent


def read(name):
    data = (ROOT / name).read_bytes()
    return json.loads(gzip.decompress(data) if name.endswith('.gz') else data)


def balanced(row):
    c = row['counts']
    assert not c['saturated'] and not c['owner_limit'] and not c['hold_limit']
    assert c['heap_allocate'] == c['retire']
    assert c['owner_acquire'] + c['heap_allocate'] == c['owner_release']
    assert c['hold_acquire'] == c['hold_release']


def main():
    for name, digest in read('identities.json')['archive_sha256'].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    measured = read('lox.json.gz')
    final = read('lox-final.json.gz')
    assert len(measured['builds']) == 8 and len(final['builds']) == 4
    for data in (measured, final):
        for build in data['builds']:
            assert build['exit'] == 0 and build['manifest']['backend'] == build['backend']
    for build in final['builds']:
        assert build['prototype_binary_identical']
        old = next(b for b in measured['builds'] if b['arm'] == 'after' and b['backend'] == build['backend'] and b['counted'] == build['counted'])
        assert old['binary_sha256'] == build['binary_sha256']
    assert len(measured['runs']) == 32 and len(final['runs']) == 12
    for row in measured['runs'] + final['runs']:
        assert row['exit'] == 0 and not row['timeout']
        if row['counted']:
            balanced(row)
    for backend in ('qbe', 'llvm'):
        for n in (4, 5):
            rows = [r for r in measured['runs'] if r['backend'] == backend and r['n'] == n]
            assert len({r['stdout'] for r in rows}) == 1
            for r in final['runs']:
                if r['backend'] == backend and r['n'] == n:
                    assert r['stdout'] == rows[0]['stdout']
                    if r['counted']:
                        assert r['counts'] == next(x['counts'] for x in rows if x['arm'] == 'after' and x['counted'])
            medians = {arm: statistics.median(r['instructions'] for r in rows if r['arm'] == arm and not r['counted']) for arm in ('before', 'after')}
            print(backend, n, medians, 'ratio', medians['after'] / medians['before'])
    expected = (ROOT / 'inputs/binary_trees.tree.out').read_text()
    full = [r for r in final['runs'] if r['n'] == 10]
    assert len(full) == 4 and all(r['stdout'] == expected for r in full)
    assert len({json.dumps(r['counts'], sort_keys=True) for r in full if r['counted']}) == 1
    guests = read('guests-final.json.gz')['runs']
    assert len(guests) == 4
    for row in guests:
        assert row['exit'] == 0 and row['stdout'] == 'True\n' * 9
        if row['mode'] == 'rc':
            balanced(row)
    for name, count in (('failures-final.json.gz', 12), ('clone-failure.json.gz', 4)):
        rows = read(name)['runs']
        assert len(rows) == count
        for row in rows:
            assert row['exit'] == 1
            expected = 'R_MEMORY_BUDGET' if 'budget' in row['case'] else 'R_LIST_BOUNDS'
            assert expected in row['stderr']
            if row['mode'] == 'rc':
                balanced(row)
    print('Verified final binary identity, N4/N5 comparison, exact N10 output, 36 standalone assertions and 16 failure controls.')


if __name__ == '__main__':
    main()
