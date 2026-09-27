"""Check archived exact-output, counter and paired trap evidence independently."""
from pathlib import Path
import gzip
import hashlib
import json
import re
import statistics

root = Path(__file__).resolve().parent
identity = json.loads((root / 'identity.json').read_text())
for name, expected in identity['artifacts'].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, name

measurement = json.loads(gzip.decompress((root / 'measurement.json.gz').read_bytes()))
controls = json.loads(gzip.decompress((root / 'controls.json.gz').read_bytes()))
assert measurement['compilers'] == controls['compilers']
assert measurement['driver_sha256'] == identity['artifacts']['measure.py']
assert controls['driver_sha256'] == identity['artifacts']['controls.py']
assert len(measurement['builds']) == 8 and all(r['ok'] for r in measurement['builds'])
assert len(measurement['runs']) == 18 and len(measurement['counts']) == 4
assert len(controls['runs']) == 32


def balanced(counts):
    assert not counts['saturated']
    assert counts['heap_allocate'] == counts['retire']
    assert counts['owner_acquire'] + counts['heap_allocate'] == counts['owner_release']
    assert counts['hold_acquire'] == counts['hold_release']


def without_counts(text):
    return re.sub(r'^MYLANG_RC_COUNTS .*\n?', '', text, flags=re.M)


for backend in ('qbe', 'llvm'):
    medians = {}
    for side in ('gc', 'before', 'after'):
        rows = [r for r in measurement['runs'] if r['backend'] == backend and r['side'] == side]
        assert len(rows) == 3 and {r['repeat'] for r in rows} == {0, 1, 2}
        assert len({r['binary_sha256'] for r in rows}) == 1
        for row in rows:
            assert row['status'] == 0 and row['stderr'] == ''
            assert row['stdout'] == identity['benchmark_stdout']
            lines = [line.split(',') for line in row['perf'].splitlines()
                     if 'instructions' in line and line.split(',')[0].isdigit()]
            assert len(lines) == 1 and float(lines[0][4]) == 100.0
            assert int(lines[0][0]) == row['instructions']
            assert 'cpu_core/instructions/u' in row['command'] and '--no-scale' in row['command']
        medians[side] = statistics.median(r['instructions'] for r in rows)
    summary = measurement['summary'][backend]
    assert summary['medians'] == medians
    assert summary['after_before'] == medians['after'] / medians['before']
    assert summary['after_gc'] == medians['after'] / medians['gc']
    counted = [r for r in measurement['counts'] if r['backend'] == backend]
    assert len(counted) == 2 and {r['side'] for r in counted} == {'before', 'after'}
    assert counted[0]['counts'] == counted[1]['counts']
    for row in counted:
        assert row['status'] == 0 and row['stdout'] == identity['benchmark_stdout']
        balanced(row['counts'])
    for case, trap in [('success', None), ('overflow', 'R_OVERFLOW'),
                       ('steps', 'R_STEP_LIMIT'), ('frames', 'R_FRAME_LIMIT')]:
        for mode in ('gc', 'rc'):
            pair = [r for r in controls['runs'] if (r['case'], r['backend'], r['mode']) == (case, backend, mode)]
            assert len(pair) == 2 and {r['side'] for r in pair} == {'before', 'after'}
            assert pair[0].get('counts') == pair[1].get('counts')
            assert without_counts(pair[0]['stderr']) == without_counts(pair[1]['stderr'])
            for row in pair:
                assert row['build_status'] == 0
                assert row['status'] == (1 if trap else 0)
                assert row['stdout'] == ('before\n' if trap else '')
                if trap:
                    assert trap in row['stderr']
                if mode == 'rc':
                    balanced(row['counts'])
print('PASS: 18 full-size instruction samples, four exact counter runs and 32 paired guest/trap outcomes')
