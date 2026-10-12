#!/usr/bin/env python3
"""Archive and independently read back the raw runtime and counted evidence."""
import gzip
import hashlib
import json
from pathlib import Path
import tarfile

HERE = Path(__file__).resolve().parent


def sha_stream(stream):
    digest = hashlib.sha256()
    while chunk := stream.read(1024 * 1024):
        digest.update(chunk)
    return digest.hexdigest()


def main():
    # A validated report is a prerequisite: incomplete timing journals are not a completed run.
    results = json.loads((HERE / 'results.json').read_text())
    assert len(results['cells']) == 60
    paths = sorted(path for folder in ('runtime', 'counted') for path in (HERE / folder).rglob('*') if path.is_file())
    assert paths and all(not path.is_symlink() for path in paths)
    destination = HERE / 'raw-evidence.tar.gz'
    manifest_path = HERE / 'raw-evidence-manifest.json'
    assert not destination.exists() and not manifest_path.exists()
    manifest = {}
    with destination.open('xb') as raw, gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode='w') as archive:
            for path in paths:
                name = str(path.relative_to(HERE))
                with path.open('rb') as stream:
                    manifest[name] = {'bytes': path.stat().st_size, 'sha256': sha_stream(stream)}
                info = archive.gettarinfo(str(path), arcname=name)
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ''
                with path.open('rb') as stream:
                    archive.addfile(info, stream)
    checked = {}
    with tarfile.open(destination, 'r:gz') as archive:
        for member in archive:
            assert member.isfile() and member.name not in checked
            checked[member.name] = {'bytes': member.size, 'sha256': sha_stream(archive.extractfile(member))}
    assert checked == manifest
    with destination.open('rb') as stream:
        digest = sha_stream(stream)
    manifest_path.write_text(json.dumps({'archive': destination.name, 'sha256': digest,
        'members': manifest, 'validated_readback': True}, indent=2) + '\n')
    print('Archived and verified', len(manifest), 'raw evidence files.')


if __name__ == '__main__':
    main()
