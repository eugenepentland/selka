#!/usr/bin/env python3
"""Preserve an inspected, finished attempt as a verified deterministic archive."""
import argparse
import hashlib
import json
import lzma
from pathlib import Path
import tarfile

HERE = Path(__file__).resolve().parent


def digest(stream):
    result = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        result.update(block)
    return result.hexdigest()


def inventory(folder):
    result = []
    for path in sorted(folder.rglob('*')):
        assert not path.is_symlink(), ('unexpected symlink', path)
        if path.is_file():
            with path.open('rb') as source:
                result.append({'path': str(path.relative_to(folder)),
                               'bytes': path.stat().st_size, 'sha256': digest(source)})
    assert result
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('attempt')
    args = parser.parse_args()
    folder = (HERE / 'attempts' / args.attempt).resolve()
    assert folder.parent == HERE / 'attempts' and folder.is_dir()
    if args.attempt.startswith('native-'):
        for app in ('lox', 'eda'):
            qualified = json.loads((folder / 'qualification' / app / 'qualified.json').read_text())
            assert qualified['status'] == 'passed'
            modes = json.loads((folder / 'matrix' / app / 'results.json').read_text())
            expected = ('verified-release', 'release', 'debug', 'optimized-debug', 'no-facts')
            assert all(name + '-units' in modes for name in expected)
            assert all(row.get('returncode', 0) == 0 for row in modes.values())
            if app == 'lox':
                assert all(name + '-vm-regressions' in modes for name in expected)
            for name in expected:
                mode = modes[name + '-units']
                assert mode['result']['passed'] > 0
                assert all(mode['result'][name] == 0 for name in ('failed', 'skipped', 'unsupported'))
    elif args.attempt.startswith('runtime-'):
        assert (folder / 'parity-report.json').is_file()
        assert (folder / 'summary' / 'summary.json').is_file()
    else:
        raise ValueError('Only finished native/runtime attempts are supported')
    files = inventory(folder)
    destination = HERE / 'archives'
    destination.mkdir(exist_ok=True)
    archive = destination / (args.attempt + '.tar.xz')
    receipt = destination / (args.attempt + '.json')
    temporary = destination / (args.attempt + '.tar.xz.partial')
    assert not any(path.exists() for path in (archive, receipt, temporary))
    with lzma.open(temporary, 'wb', preset=6) as compressed:
        with tarfile.open(fileobj=compressed, mode='w|') as bundle:
            for entry in files:
                path = folder / entry['path']
                info = tarfile.TarInfo(args.attempt + '/' + entry['path'])
                info.size = entry['bytes']
                info.mode = 0o644
                with path.open('rb') as source:
                    bundle.addfile(info, source)
    # Verify every archived byte, then reject any input mutation during packing.
    observed = []
    with tarfile.open(temporary, mode='r|xz') as bundle:
        for member in bundle:
            assert member.isfile() and member.name.startswith(args.attempt + '/')
            with bundle.extractfile(member) as source:
                observed.append({'path': member.name[len(args.attempt) + 1:],
                                 'bytes': member.size, 'sha256': digest(source)})
    assert observed == files == inventory(folder), 'attempt changed or archive differs'
    temporary.rename(archive)
    with archive.open('rb') as source:
        archive_sha = digest(source)
    receipt.write_text(json.dumps({'attempt': args.attempt, 'archive': archive.name,
                                  'archive_sha256': archive_sha, 'files': files,
                                  'scope': 'Evidence files only; compiler installations and guest binaries are separately pinned by the archived receipts.',
                                  'verified': True, 'raw_files_retained': True}, indent=2) + '\n')
    print(json.dumps({'archive': str(archive), 'files': len(files),
                      'raw_bytes': sum(row['bytes'] for row in files),
                      'archive_bytes': archive.stat().st_size, 'sha256': archive_sha}))


if __name__ == '__main__':
    main()
