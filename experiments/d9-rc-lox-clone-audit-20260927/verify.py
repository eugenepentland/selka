"""Verify preserved diagnostic evidence without executing an instrumented guest."""
from pathlib import Path
import gzip
import hashlib
import json

ROOT = Path(__file__).resolve().parent


def read(name):
    path = ROOT / name
    data = gzip.decompress(path.read_bytes()) if name.endswith('.gz') else path.read_bytes()
    return json.loads(data)


def main():
    identities = read('identities.json')
    for name, digest in identities['archive_sha256'].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    gc = read('matched/cow-counts.json.gz')['runs']
    rc = [r for r in read('matched/lox.json.gz')['runs'] if r['arm'] == 'after']
    probe = read('probe/probe.json.gz')['runs']
    for n in (4, 5):
        references = []
        for backend in ('qbe', 'llvm'):
            g = next(r for r in gc if r['backend'] == backend and r['n'] == n)
            r = next(r for r in rc if r['backend'] == backend and r['case'] == f'n{n}')
            assert g['exit'] == r['exit'] == 0 and not g['timeout'] and not r['timeout']
            assert g['stdout'] == r['stdout']
            c = r['counts']
            assert not c['saturated'] and not c['owner_limit'] and not c['hold_limit']
            assert c['heap_allocate'] == c['retire']
            assert c['owner_acquire'] + c['heap_allocate'] == c['owner_release']
            assert c['hold_acquire'] == c['hold_release']
            manifest = read(f'matched/gc-counts-{backend}.manifest.json.gz')
            assert manifest['backend'] == backend
            references.append((g, r))
        assert references[0][0]['counts'] == references[1][0]['counts']
        assert references[0][1]['counts'] == references[1][1]['counts']
        p = next(r for r in probe if r['n'] == n)
        assert p['exit'] == 0 and not p['timeout']
        assert p['stdout'] == references[0][1]['stdout']
        assert p['counts'] == references[0][1]['counts']
        counters = p['probe']
        assert not counters['rows_overflow'] and not counters['operations_overflow']
        rows = counters['rows']
        assert sum(r['created'] for r in rows) == p['counts']['clone_shell']
        assert all(r['kind'] == 1 and r['requests'] == r['created'] == r['committed'] for r in rows)
        assert not any(r[k] for r in rows for k in ('rolled_back', 'memo_reuses', 'pinned_requests', 'arena_requests'))
    obj = 'myl_t_' + hashlib.sha256(b'object::Obj').hexdigest()
    entry = 'myl_t_' + hashlib.sha256(b'table::Entry').hexdigest()
    for summary in read('probe/summary.json'):
        assert summary['rows'][0]['element_symbol'] == obj
        assert summary['rows'][1]['element_symbol'] == entry
    print('PASS: evidence hashes; both-backend matched output and counts; complete probe attribution')


if __name__ == '__main__':
    main()
