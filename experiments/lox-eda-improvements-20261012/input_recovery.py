"""Resolve only explicitly pinned, byte-identical recovered expected-output files."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / 'input-recovery/manifest.json'
ENTRIES = json.loads(MANIFEST.read_text())['entries'] if MANIFEST.exists() else {}


def read_bytes(path):
    original = str(path)
    if original not in ENTRIES:
        return Path(path).read_bytes()
    entry = ENTRIES[original]
    recovered = Path(entry['path']).read_bytes()
    assert hashlib.sha256(recovered).hexdigest() == entry['sha256'], original
    if Path(original).exists():
        assert hashlib.sha256(Path(original).read_bytes()).hexdigest() == entry['sha256'], original
    return recovered


def identity():
    if not ENTRIES:
        return None
    return {'manifest': str(MANIFEST),
            'manifest_sha256': hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
            'resolver_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'scope': 'Same logical input identities; byte-identical expected outputs in this experiment.'}


def relocated_spec(original):
    original = Path(original)
    document = json.loads(original.read_text())
    if document.get('expected_stdout') not in ENTRIES:
        return original
    for path in document['files']:
        if path in ENTRIES:
            read_bytes(path)
    document['files'] = [ENTRIES[p]['path'] if p in ENTRIES else p for p in document['files']]
    document['expected_stdout'] = ENTRIES[document['expected_stdout']]['path']
    document['input_recovery'] = {**identity(), 'original_spec': str(original),
                                'original_spec_sha256': hashlib.sha256(original.read_bytes()).hexdigest()}
    directory = HERE / 'input-recovery/count-specs'
    directory.mkdir(exist_ok=True)
    destination = directory / original.name
    encoded = json.dumps(document, indent=2) + '\n'
    if destination.exists():
        assert destination.read_text() == encoded
    else:
        destination.write_text(encoded)
    return destination
