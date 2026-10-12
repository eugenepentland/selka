"""Strict, shared artifact identities for the application qualification harnesses."""
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_files(directory):
    directory = Path(directory)
    return {str(path.relative_to(directory)): sha(path) for path in sorted(directory.rglob('*'))
            if path.is_file() and (path.suffix == '.my' or path.name == 'mylang.json')}


def build_path(application):
    selected = HERE / 'build' / (application + '-selected.json')
    if selected.exists():
        selection = json.loads(selected.read_text())
        path = Path(selection['path'])
        assert sha(path) == selection['sha256']
        return path
    return HERE / 'build' / application / 'build-receipt.json'


def validate_build(path):
    path = Path(path)
    build = json.loads(path.read_text())
    common_path = Path(build['common_receipt'])
    assert sha(common_path) == build['common_receipt_sha256']
    common = json.loads(common_path.read_text())
    assert sha(build['compiler']) == build['compiler_sha256'] == common['compiler_sha256']
    for entry in common['installation_files']:
        assert sha(Path(common['installation']) / entry['path']) == entry['sha256']
    for source in build['sources'].values():
        assert source_files(source['root']) == source['files'], source['root']
    assert len(build['binaries']) == 6
    for binary in build['binaries'].values():
        assert binary['status'] == 'ok' and sha(binary['path']) == binary['sha256']
    return build


def qualified(application, path):
    receipt = HERE / 'qualification' / application / 'qualified.json'
    value = json.loads(receipt.read_text())
    assert value['status'] == 'passed'
    assert Path(value['manifest']).resolve() == Path(path).resolve()
    assert value['manifest_sha256'] == sha(path)
    for name, identity in value['evidence'].items():
        assert sha(name) == identity
    return value
