#!/usr/bin/env python3
"""Seal static diagnostic bytes and current identities without running guests."""
from pathlib import Path
import base64, gzip, hashlib, json, subprocess

lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-byte-positive-20261003/refusal-diag'
experiment = Path(__file__).resolve().parent
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
analysis = json.loads((work / 'analysis.json').read_text())
assert analysis['verified_after']
proof = json.loads((work.parent / 'qualified-source.json').read_text())
assert all(sha(lane / name) == digest for name, digest in proof['source_sha256'].items())
builds = json.loads((work.parent / 'guest-builds.json').read_text())
assert all(sha(Path(builds['source']) / name) == digest for name, digest in builds['source37'].items())
compilers = {
    'v1': work.parent / 'release/bin/mylang',
    'selected': lane.parent / 'codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/mylang',
    'qbe': work.parent / 'release/bin/qbe',
}
expected = {
    'v1': 'f89c339c1be3bb21fadf34b69b394fffa87e7248f3f5feeab49b62fc761a9520',
    'selected': 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040',
    'qbe': '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63',
}
assert {name: sha(path) for name, path in compilers.items()} == expected
files = {}
for path in sorted(work.rglob('*')):
    if path.is_file():
        contents = path.read_bytes()
        files[str(path.relative_to(work))] = {'sha256': hashlib.sha256(contents).hexdigest(), 'size': len(contents), 'base64': base64.b64encode(contents).decode()}
receipt = {
    'kind': analysis['kind'], 'variant_compiler_source_commit': 'ee1f99f0aacb842872527c28652b129f0da55b03',
    'selected_compiler_source_commit': '3b33df52044a10cb84b908f8b1641af439e8c729',
    'compiler_identities': {name: {'path': str(path), 'sha256': expected[name]} for name, path in compilers.items()},
    'frozen_proof_source': proof,
    'lox_source': {'path': builds['source'], 'source37': builds['source37']},
    'control_metadata_scope': 'control/inputs.json source_commit denotes the frozen lane experiment. Its selected compiler is separately identified by d14 SHA; its IL is the unchanged selected byte-v3 control extraction.',
    'boundary_model_cases': len(analysis['admission_boundary_model']),
    'variant_summary': {name: {key: record[key] for key in ['whole_function_instructions', 'successful_path_instructions', 'admission']} for name, record in analysis['variants'].items()},
    'files': files, 'verified_after': True,
}
archive = experiment / 'receipts.json.gz'
assert not archive.exists()
with archive.open('wb') as stream:
    with gzip.GzipFile(fileobj=stream, mode='wb', mtime=0) as compressed:
        compressed.write((json.dumps(receipt, sort_keys=True) + '\n').encode())
compact = {name: value for name, value in receipt.items() if name != 'files'}
compact['archive'] = {'name': archive.name, 'sha256': sha(archive), 'files': len(files)}
(experiment / 'qualification.json').write_text(json.dumps(compact, indent=2) + '\n')
print(len(files), sha(archive))
