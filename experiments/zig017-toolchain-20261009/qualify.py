#!/usr/bin/env python3
"""Check all retained compiler artifacts against representative source fixtures."""
import json
import subprocess
from build_hashes import HERE, ROOT, WORK
from build_compilers import digest

builds = json.loads((HERE / 'compiler-builds.json').read_text())
if (HERE / 'compiler-llvm-builds.json').exists():
    builds += json.loads((HERE / 'compiler-llvm-builds.json').read_text())
names = sorted({x['name'] for x in builds if x['exit'] == 0})
fixtures = ['recursive_values.my', 'callbacks.my', 'callback_slots.my', 'rc_match_scalars.my',
            'migrated/generic_arrays.my', 'migrated/generic_inference_case_1.my',
            'migrated/structural_constraints_case_1.my']
rows = []
for fixture in fixtures:
    expected = None
    for name in names:
        command = [str(WORK / 'compilers' / name / 'bin/mylang'), 'check',
                   str(ROOT / 'tests/lang' / fixture), '--no-cache']
        result = subprocess.run(command, capture_output=True)
        if expected is None:
            expected = (result.returncode, result.stdout, result.stderr)
        assert (result.returncode, result.stdout, result.stderr) == expected, (fixture, name, result.stderr)
        assert result.returncode == 0, (fixture, result.stderr)
        rows.append({'compiler': name, 'fixture': fixture, 'exit': result.returncode})
snapshot = WORK / 'source'
manifest = {str(p.relative_to(snapshot)): digest(p) for p in sorted(snapshot.rglob('*')) if p.is_file()}
assert manifest == json.loads((HERE / 'source-manifest.json').read_text()), 'source snapshot changed'
latest = {row['name']: row for row in builds if row['exit'] == 0}
for name, row in latest.items():
    assert digest(WORK / 'compilers' / name / 'bin/mylang') == row['binary_sha256'], name
(HERE / 'qualification.json').write_text(json.dumps({'checks': rows, 'sources_unchanged': True,
                                                   'binaries_unchanged': True}, indent=2) + '\n')
print(f'{len(rows)} fixture checks passed; frozen sources and recorded binaries match')
