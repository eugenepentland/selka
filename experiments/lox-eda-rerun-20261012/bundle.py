#!/usr/bin/env python3
"""Preserve verbose raw evidence losslessly in a hashed archive for Git."""
import gzip
import hashlib
import json
from pathlib import Path
import tarfile

HERE = Path(__file__).resolve().parent


def main():
    archive = HERE / 'raw-evidence.tar.gz'
    manifest = HERE / 'raw-evidence-manifest.json'
    assert not archive.exists() and not manifest.exists()
    files = sorted(p for directory in ('runtime', 'counted')
                   for p in (HERE / directory).rglob('*') if p.is_file())
    identities = {str(p.relative_to(HERE)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    with archive.open('wb') as stream:
        with gzip.GzipFile(fileobj=stream, mode='wb', compresslevel=6, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode='w|') as tar:
                for path in files:
                    assert not path.is_symlink()
                    tar.add(path, arcname=str(path.relative_to(HERE)), recursive=False)
    with tarfile.open(archive, 'r:gz') as tar:
        members = tar.getmembers()
        assert len(members) == len(identities)
        for member in members:
            assert member.isfile()
            assert hashlib.sha256(tar.extractfile(member).read()).hexdigest() == identities[member.name]
    manifest.write_text(json.dumps({'archive': archive.name,
                       'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                       'file_count': len(files), 'uncompressed_file_bytes': sum(p.stat().st_size for p in files),
                       'files': identities, 'archive_roundtrip': 'passed'}, indent=2) + '\n')
    print(f'Archived and verified {len(files)} evidence files; {archive.stat().st_size} compressed bytes.')


if __name__ == '__main__':
    main()
