#!/usr/bin/env python3
"""Archive exact placement counterfactual, qualification and108 outcomes."""
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WORK = ROOT / '.mylang-cache/goal110-search-placement'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def pack(name, source):
    raw = source.read_bytes()
    packed = gzip.compress(raw, mtime=0)
    target = HERE / (name + '.gz')
    if target.exists():
        assert target.read_bytes() == packed, target
    else:
        target.write_bytes(packed)
    assert gzip.decompress(target.read_bytes()) == raw
    return {'source_path': str(source.resolve()), 'raw_sha256': digest(raw), 'raw_bytes': len(raw),
            'archive': target.name, 'gzip_sha256': digest(packed), 'gzip_bytes': len(packed)}


subprocess.run(['git', 'diff', '--exit-code', '0311796e84e192e3ac1e4fd0bb9d5824b55be1e2',
                '--', 'src', 'vendor/qbe', 'docs', 'build.zig', 'build.zig.zon', 'SPEC.md'], cwd=ROOT, check=True)
timing = json.loads((WORK / 'placement-three-arm.json').read_text())
analysis = json.loads((WORK / 'paired-analysis.json').read_text())
assert timing['status'] == 'complete' and analysis['status'] == 'replayed' and analysis['outcomes'] == 108
assert timing['binary_hashes'] == {name: row['sha256'] for name, row in timing['artifacts_after']['binaries'].items()}
sources = {path.name: path for path in WORK.iterdir() if path.is_file() and path.suffix in ('.json', '.log')}
for variant in ('capture', 'fill32'):
    for path in (WORK / variant).iterdir():
        if path.is_file() and path.suffix == '.json':
            sources[variant + '-' + path.name] = path
    for directory in sorted((WORK / variant / 'tool-calls').iterdir()):
        for path in sorted(directory.iterdir()):
            if path.is_file() and (path.name in ('stdout', 'stderr') or path.suffix in ('.json', '.rsp', '.s')):
                sources[variant + '-call-' + directory.name + '-' + path.name] = path
for directory in ('mapping', 'proof'):
    for path in sorted((WORK / directory).iterdir()):
        if path.is_file() and path.suffix != '.o':
            sources[directory + '-' + path.name] = path
sources['compiler-receipt.json'] = ROOT / '.mylang-cache/goal110-floor-result-range-debug/compiler-receipt.json'
bindings = [pack(name, path) for name, path in sorted(sources.items())]
evidence = {'status': 'diagnostic_placement_recovery_no_production_adoption',
            'source_revision': '0311796e84e192e3ac1e4fd0bb9d5824b55be1e2',
            'baseline_revision': '6cf7bdce11bc205862bf75b9d9ce72e46caad0a2',
            'created_utc': datetime.now(timezone.utc).isoformat(), 'raw_bindings': bindings,
            'script_bindings': {path.name: digest(path.read_bytes()) for path in HERE.iterdir()
                                if path.suffix == '.py' or path.name in ('README.md', 'PLAN.md')},
            'qualification': {'text_ordinary_records': 200, 'diagnostic_outcomes': 108,
                              'complete_assembly_only_delta': '32NOPs beforeverifiedlooplabel',
                              'entire_caller_and_helpers_normalized_equal': True},
            'outcome': 'Search recovers from1.149086 to1.007983 timesG4, equality benefit retained0.912001 timesG4.',
            'limitations': ['Later167textsymbols move+32 too; no unique caller-address causal claim.',
                           'Private diagnostic wrapper guest, not official runner/goal confirmation or production source change.',
                           'Pointwise bootstrap excludes multiplicity and systematic host noise.',
                           'ELF/bitcode inputs remain live immutable private-cache artifacts bound by receipts, not Git executables.']}
(HERE / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
print('PASS', len(bindings), 'raw bindings;', len(evidence['script_bindings']), 'helpers/metadata')
print('evidence_sha256', digest((HERE / 'evidence.json').read_bytes()))
