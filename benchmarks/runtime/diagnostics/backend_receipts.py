"""Inspect effective emitted backends, rather than infer them from unordered flags."""
import hashlib
import json
from pathlib import Path


def capture(binaries):
    rows = {}
    for name, binary in binaries.items():
        arm = name.rsplit('/', 1)[-1]
        if arm not in ('my-llvm', 'my-qbe'):
            continue
        path = Path(str(binary) + '.qbe-manifest.json')
        document = json.loads(path.read_text())
        backend = arm.removeprefix('my-')
        if document.get('backend') != backend:
            raise ValueError('effective guest backend differs from arm: ' + name)
        if backend == 'llvm' and (document.get('optimization') != '3' or document.get('lto') is not True):
            raise ValueError('LLVM guest must actually use O3/LTO: ' + name)
        if backend == 'qbe' and document.get('lto') is not False:
            raise ValueError('QBE guest has unexpected LTO: ' + name)
        runtime = Path(document['runtime_object'])
        rows[name] = {'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                      'backend': document['backend'], 'optimization': document['optimization'],
                      'lto': document['lto'], 'link_identity': document['link_identity'],
                      'runtime_object': str(runtime), 'runtime_object_sha256': hashlib.sha256(runtime.read_bytes()).hexdigest()}
    return rows
