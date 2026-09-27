#!/usr/bin/env python3
"""Read preserved PC-context comparisons and guest receipts without rebuilding."""
from pathlib import Path
import gzip
import hashlib
import json
import sys
ROOT = Path(__file__).resolve().parent

def bits(name):
    return gzip.decompress((ROOT / (name + '.gz')).read_bytes())

for name, item in json.loads((ROOT / 'files.json').read_text()).items():
    value = bits(name)
    assert len(value) == item['bytes'] and hashlib.sha256(value).hexdigest() == item['sha256']
rows = json.loads(bits('results.json'))
for case in ['dict_count', 'bytes_scan']:
    assert bits(case + '-before.ssa') == bits(case + '-after.ssa')
    entries = [x for x in rows['emission'] if x['case'] == case]
    assert len(entries) == 2 and all(x['status'] == 0 for x in entries)
    assert entries[0]['il_sha256'] == entries[1]['il_sha256']
assert rows['adjacent']['dictionary_drops'] == 5 and rows['adjacent']['byte_guards'] == 1
assert rows['adjacent']['source_sha256'] == hashlib.sha256(bits('rc_loop_guard_context.my')).hexdigest()
assert len(rows['runs']) == 4
counts = None
for row in rows['runs']:
    assert row['build_status'] == row['status'] == 0 and row['stdout'] == '220\n'
    assert row['manifest']['backend'] == row['backend']
    if row['backend'] == 'llvm':
        assert row['manifest']['optimization'] == '3' and row['manifest']['lto']
    if row['mode'] == 'rc':
        c = row['counts']; counts = counts or c
        assert counts == c and c['heap_allocate'] == c['retire'] == 42
        assert c['owner_acquire'] == 11 and c['owner_release'] == 53
        assert c['arena_allocate'] == 11 and c['hold_acquire'] == c['hold_release'] == 0
        assert c['clone_shell'] == 0 and not c['saturated']
if '--live' in sys.argv:
    compilers = [{'path': x['compiler'], 'sha256': x['compiler_sha256']} for x in rows['emission']]
    for item in [rows['after_compiler'], *compilers]:
        assert hashlib.sha256(Path(item['path']).read_bytes()).hexdigest() == item['sha256']
print('Verified2 independent exact-IL comparisons and4 successful actual-backend guests with balanced RC counts.')
