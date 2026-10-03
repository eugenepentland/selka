"""Recheck frozen source/package/receipts; reads only, executes no payload."""
import ast
import base64
import difflib
import gzip
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
REVIEW = json.loads((HERE / 'review.json').read_bytes())
E = Path(REVIEW['source_root'])
S = Path(REVIEW['scratch'])


def sha(data):
    return hashlib.sha256(data).hexdigest()


for name, row in REVIEW['inputs'].items():
    data = (HERE / name).read_bytes()
    assert sha(data) == row['sha256'] and Path(row['path']).read_bytes() == data
index = json.loads((HERE / 'archive-manifest.json').read_bytes())
archive = (HERE / 'receipts.json.gz').read_bytes()
assert sha(archive) == index['archive_sha256']
files = json.loads(gzip.decompress(archive))['files']
assert set(files) == set(index['files']) and len(files) == 35
BYTES = {name: base64.b64decode(value, validate=True) for name, value in files.items()}
for name, data in BYTES.items():
    assert sha(data) == index['files'][name]['sha256']
    assert len(data) == index['files'][name]['bytes']
    root = E if name.startswith('source/') else S
    assert (root / name.split('/', 1)[1]).read_bytes() == data


def doc(name):
    return json.loads(BYTES[name])


frozen = doc('raw/frozen-source-v1.json')
assert sha(BYTES['raw/frozen-source-v1.json']) == REVIEW['source_descriptor_sha256']
assert len(frozen['files']) == 25
for name, expected in frozen['files'].items():
    data = BYTES['source/' + name]
    assert sha(data) == expected
    assert (Path(frozen['frozen_root']) / name).read_bytes() == data
base = doc('source/protocol-base.json')
assert len(base['files']) == 8 and len(base['reused']) == 4
for name, row in base['files'].items():
    expected = row['sha256']
    assert sha(Path(row['original_path']).read_bytes()) == expected
    assert sha(BYTES['source/base/' + name]) == expected
for name, row in base['reused'].items():
    assert sha(Path(row['original_path']).read_bytes()) == row['sha256']
    assert sha(BYTES['source/base/reused/' + name]) == row['sha256']
for name in REVIEW['unchanged_active_helpers']:
    assert BYTES['source/' + name] == BYTES['source/base/' + name]
changed = {name for name in base['files']
           if BYTES['source/' + name] != BYTES['source/base/' + name]}
assert changed == set(REVIEW['narrow_modified_base_files'])
diff = ''.join(''.join(difflib.unified_diff(
    BYTES['source/base/' + name].decode().splitlines(keepends=True),
    BYTES['source/' + name].decode().splitlines(keepends=True),
    fromfile='base/' + name, tofile='v2/' + name))
    for name in ['prepare.py', 'analyze.py', 'validation.py'])
assert diff.encode() == BYTES['source/protocol-delta.patch']


def definitions(name):
    return {node.name: ast.dump(node, include_attributes=False)
            for node in ast.parse(BYTES[name].decode()).body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}


for name, modified in [('prepare.py', {'main'}), ('analyze.py', {'main'}),
                       ('validation.py', {'analysis', 'validate'})]:
    original, current = definitions('source/base/' + name), definitions('source/' + name)
    assert set(original) == set(current)
    assert {key for key in original if original[key] != current[key]} == modified
HOST = doc('raw/host-frozen-v1.json')
assert HOST['status'] == 0 and HOST['tests'] == 30 and HOST['verified_after']
assert HOST['before'] == HOST['after'] and len(HOST['after']) == 37
assert HOST['descriptor_sha256'] == REVIEW['source_descriptor_sha256']
for path, expected in HOST['after'].items():
    assert sha(Path(path).read_bytes()) == expected
assert HOST['log_sha256'] == sha(BYTES['raw/host-frozen-v1.log'])
log = BYTES['raw/host-frozen-v1.log'].decode()
assert len(re.findall(r'^test_.* \.\.\. ok$', log, re.M)) == 30
assert 'Ran 30 tests' in log and log.endswith('OK\n')
assert HOST['argv'][2:5] == ['python3', '-m', 'unittest']
GUARD = doc('raw/guardian-v1.json')
assert GUARD['status'] == 0
assert sha(Path(GUARD['argv'][2]).read_bytes()) == GUARD['tool_sha256']
assert GUARD['log_sha256'] == sha(BYTES['raw/guardian-v1.log'])
assert b'88 check(s) passed' in BYTES['raw/guardian-v1.log']
qualification = json.loads((HERE / 'qualification.json').read_bytes())
assert qualification['source_descriptor_sha256'] == REVIEW['source_descriptor_sha256']
assert qualification['host_receipt_sha256'] == sha(BYTES['raw/host-frozen-v1.json'])
assert qualification['guardian_receipt_sha256'] == sha(BYTES['raw/guardian-v1.json'])
assert '13 new fixture setup errors' in qualification['historical_attempts']['host-v1.log']
print(json.dumps(dict(verified=True, source_files=25, originals_unchanged=12,
    changed_base_files=3, active_helpers_byte_exact=5, frozen_raw_package_files=35,
    actual_runtime_roles_required=6, author_synthetic_host_tests=30, author_guardian_checks=88,
    preservation_checked_by_exact_delta_and_function_AST=True,
    author_compiler_guest_native_or_perf_execution=False,
    reviewer_read_only_no_payload_execution=True, no_retrospective_alias_pass=True,
    performance_or_selection_claim=False), indent=2))
