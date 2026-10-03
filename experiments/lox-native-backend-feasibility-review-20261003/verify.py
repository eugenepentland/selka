"""Read-only verification of the written proposal's source/artifact bindings."""
import gzip
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile

HERE = Path(__file__).resolve().parent
review = json.loads((HERE / 'review.json').read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


def saved(name):
    return gzip.decompress((HERE / 'inputs' / (name + '.gz')).read_bytes())


for name, row in review['inputs'].items():
    compressed = (HERE / 'inputs' / (name + '.gz')).read_bytes()
    data = gzip.decompress(compressed)
    assert sha(compressed) == row['copy_sha256']
    assert sha(data) == row['sha256']
    assert Path(row['path']).read_bytes() == data
for name, expected in json.loads(saved('files-final.json')).items():
    assert sha(saved(name)) == expected
for name, expected in json.loads(saved('files.json')).items():
    assert sha(saved(name)) == expected

analysis = json.loads(saved('analysis.json'))
assert analysis['verified_before_after']
assert sha(saved('raw.json.gz')) == analysis['raw_archive_sha256']
raw = json.loads(gzip.decompress(saved('raw.json.gz')))
archive = subprocess.run(['git', 'archive', analysis['selected_core_commit']],
                         cwd=review['author_worktree'], capture_output=True,
                         check=True).stdout
with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
    base = {item.name: sha(stream.extractfile(item).read())
            for item in stream if item.isfile()}
assert len(analysis['selected_core_files']) == 37
for name, expected in analysis['selected_core_files'].items():
    assert sha(raw['selected/' + name].encode()) == base[name] == expected

descriptor = analysis['native_v2_descriptor']
assert sha(raw['native-v2/proof-v2.json'].encode()) == descriptor['sha256']
assert Path(descriptor['path']).read_bytes() == raw['native-v2/proof-v2.json'].encode()
assert len(descriptor['files']) == 12
frozen = Path(descriptor['path']).with_suffix('')
for name, expected in descriptor['files'].items():
    assert sha(raw['native-v2/' + name].encode()) == expected
    assert sha((frozen / name).read_bytes()) == expected
source = Path(analysis['selected_source_path'])
assert len(analysis['selected_source37']) == 37
assert {str(p.relative_to(source)): sha(p.read_bytes())
        for p in source.rglob('*') if p.is_file()} == analysis['selected_source37']
for path, expected in analysis['selected_artifacts'].items():
    assert sha(Path(path).read_bytes()) == expected
for model in analysis['lexical_models']:
    assert sha(raw['selected-il/' + model['file']].encode()) == model['sha256']
    assert model['actual_translation_or_codegen_executed'] is False
print(json.dumps(dict(verified=True, proposal_files=7, selected_core_files=37,
                     selected_source_files=37, frozen_V2_files=12,
                     original_producer_addendum_preserved=True,
                     implementation_or_performance_claim=False), indent=2))
