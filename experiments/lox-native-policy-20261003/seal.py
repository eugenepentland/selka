#!/usr/bin/env python3
"""Seal exact raw receipts and referenced fragments without mutable caches."""
from pathlib import Path
import hashlib, json, os, tarfile

lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-native-policy-20261003'
destination = Path(__file__).parent
os.sched_setaffinity(0, set(os.sched_getaffinity(0)) - {2, 3, 10, 11})
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
selected = set()
suffixes = {'.json', '.jsonl', '.stdout', '.stderr', '.log', '.py', '.my', '.txt'}
def raw(path):
    return path.suffix in suffixes or path.name.endswith('.qbe-receipt')
selected.update(p for p in work.iterdir() if p.is_file() and raw(p) and not p.name.startswith('archive-final-v2.'))
for directory in work.iterdir():
    if not directory.is_dir():
        continue
    if directory.name in {'frozen-core', 'frozen-core-v2', 'native', 'native-v2', 'counting-diagnostic', 'source37'}:
        selected.update(p for p in directory.rglob('*') if p.is_file() and 'tmp' not in p.relative_to(directory).parts)
    elif directory.name.startswith(('selected-boundaries-', 'producer-check')):
        selected.update(p for p in directory.iterdir() if p.is_file() and raw(p))

# Lean session manifests refer to BLAKE3-named IL and metadata files. Retain
# those exact bytes for every historical attempt as well as final comparisons.
for manifest in list(selected):
    if manifest.suffix != '.json':
        continue
    try:
        document = json.loads(manifest.read_text())
    except (ValueError, UnicodeDecodeError):
        continue
    if not isinstance(document, dict) or not document.get('store'):
        continue
    for function in document.get('functions', []):
        if not isinstance(function, dict):
            continue
        for key in ['il_digest', 'meta_digest']:
            if key in function:
                path = Path(document['store']) / function[key]
                if path.is_relative_to(work):
                    assert path.is_file(), path
                    selected.add(path)

assert json.loads((work / 'native-v2/completed.json').read_text())['verified_after']
assert json.loads((work / 'public-v2.json').read_text())['verified_after']
assert json.loads((work / 'selected-boundaries-verified-v2/qualification.json').read_text())['verified_after']
mapping = {str(p.relative_to(work)): sha(p) for p in sorted(selected)}
archive = destination / 'evidence.tar.xz'
assert not archive.exists()
with tarfile.open(archive, 'w:xz', preset=6) as stream:
    for path in sorted(selected):
        info = stream.gettarinfo(str(path), arcname=str(path.relative_to(work)))
        info.mtime = 0
        info.uid = info.gid = 0
        info.uname = info.gname = ''
        with path.open('rb') as source:
            stream.addfile(info, source)
assert all(sha(work / p) == h for p, h in mapping.items())
record = dict(archive=archive.name, archive_sha256=sha(archive), files=mapping,
              scope='Exact raw qualification/provenance/source receipts; mutable caches and ELF/prefix binaries excluded. Original scratch remains preserved.',
              current_replay_helpers_sha256={p.name: sha(p) for p in sorted(destination.glob('*.py'))},
              source_descriptor_sha256=sha(work / 'frozen-source-v2.json'),
              compiler_descriptor_sha256=sha(work / 'compiler-final-v2.json'))
(destination / 'archive.json').write_text(json.dumps(record, indent=2) + '\n')
print(len(mapping), 'raw files sealed', record['archive_sha256'])
