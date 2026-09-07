"""Content receipts for mounted system trees; detects drift, not an immutable OS image."""
import hashlib
import os
from pathlib import Path
import stat
import time
from .storage import digest, read_json, write_json

from .runtime_policy import SYSTEM_PATHS


def tree_identity(root, *, max_bytes=64 * 1024**3, max_entries=1000000):
    root = Path(root).resolve(strict=True)
    records = {}
    total = 0
    def changed(before, after):
        return (before.st_dev, before.st_ino, before.st_mode, before.st_size, before.st_mtime_ns, before.st_ctime_ns, before.st_uid, before.st_gid) != (
            after.st_dev, after.st_ino, after.st_mode, after.st_size, after.st_mtime_ns, after.st_ctime_ns, after.st_uid, after.st_gid)
    def visit(path, key, depth):
        nonlocal total
        if depth > 128 or len(records) >= max_entries:
            raise ValueError('system inventory entry/depth budget exceeded')
        before = path.lstat()
        mode = stat.S_IMODE(before.st_mode)
        if stat.S_ISLNK(before.st_mode):
            records[key] = {'kind': 'symlink', 'target': os.readlink(path)}
        elif stat.S_ISDIR(before.st_mode):
            records[key] = {'kind': 'directory', 'mode': mode}
            for child in sorted(path.iterdir()):
                visit(child, key + '/' + child.name, depth + 1)
        elif stat.S_ISREG(before.st_mode):
            hasher = hashlib.sha256()
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            try:
                if changed(before, os.fstat(fd)):
                    raise ValueError('system file changed before capture')
                while chunk := os.read(fd, 1024 * 1024):
                    total += len(chunk)
                    if total > max_bytes:
                        raise ValueError('system inventory byte budget exceeded')
                    hasher.update(chunk)
                if changed(before, os.fstat(fd)):
                    raise ValueError('system file changed during capture')
            finally:
                os.close(fd)
            records[key] = {'kind': 'file', 'mode': mode, 'size': before.st_size, 'sha256': hasher.hexdigest()}
        else:
            raise ValueError('unsupported special file in system inventory: ' + str(path))
        records[key].update(uid=before.st_uid, gid=before.st_gid)
        if changed(before, path.lstat()):
            raise ValueError('system path changed during capture')
    try:
        visit(root, '.', 0)
    except PermissionError as error:
        raise ValueError('environment inventory incomplete: cannot read ' + str(error.filename)) from error
    return {'path': str(root), 'sha256': digest(records), 'entries': len(records), 'bytes': total}


def capture(paths=SYSTEM_PATHS, *, tools=None):
    started = time.monotonic()
    mounts, contents = {}, {}
    for value in paths:
        path = Path(value).absolute()
        if not path.exists():
            mounts[str(path)] = None
            continue
        resolved = str(path.resolve(strict=True))
        mounts[str(path)] = resolved
        if resolved not in contents:
            contents[resolved] = tree_identity(resolved)
    uname = os.uname()
    body = {'version': 'application-environment-v2', 'mounts': mounts, 'contents': contents,
            'kernel': {'system': uname.sysname, 'release': uname.release, 'version': uname.version, 'machine': uname.machine},
            'cpu_count': os.cpu_count(),
            'tools': {name: {'source_path': str(Path(path).absolute()), 'identity': tree_identity(path)}
                      for name, path in sorted((tools or {}).items())},
            'immutable_image': False}
    return dict(body, sha256=digest(body), capture_seconds=time.monotonic() - started)


def session_tools(tools, task_adapter, practice_adapter):
    """Name every tool mounted by participant commands or either check adapter."""
    result = {'participant:' + name: str(Path(path).absolute()) for name, path in tools.items()}
    for phase, adapter in (('task', task_adapter), ('practice', practice_adapter)):
        result.update({phase + ':' + name: item['path'] for name, item in adapter['tools'].items()})
    return result


def validate(receipt, *, require_system=False, required_tools=None):
    body = {key: value for key, value in receipt.items() if key not in ('sha256', 'capture_seconds')}
    if receipt.get('version') != 'application-environment-v2' or digest(body) != receipt.get('sha256'):
        raise ValueError('environment receipt changed')
    if require_system and set(receipt['mounts']) != set(SYSTEM_PATHS):
        raise ValueError('environment receipt does not cover all runtime system mounts')
    if required_tools is not None:
        expected = {name: str(Path(path).absolute()) for name, path in required_tools.items()}
        actual = {name: item['source_path'] for name, item in receipt['tools'].items()}
        if actual != expected:
            raise ValueError('environment receipt does not cover session tools')


def verify(receipt, *, require_system=False, required_tools=None):
    validate(receipt, require_system=require_system, required_tools=required_tools)
    current = capture(receipt['mounts'], tools={key: item['source_path'] for key, item in receipt['tools'].items()})
    if current['sha256'] != receipt['sha256']:
        raise ValueError('mounted system or tool environment changed')
    return current



def grading_evidence(root, manifest):
    """Validate retained session evidence without recapturing today's environment."""
    required = manifest.get('environment_sha256')
    if required is None:
        return None
    directory = Path(root) / 'driver'
    try:
        config = read_json(directory / 'configuration.json')
        result = read_json(directory / 'result.json')
        receipt = read_json(directory / 'environment.json')
        before = read_json(directory / 'environment-before.json')
        after = read_json(directory / 'environment-after.json')
    except FileNotFoundError as error:
        raise ValueError('missing required session environment evidence') from error
    for item in (receipt, before, after):
        validate(item, require_system=True)
        if item['sha256'] != required:
            raise ValueError('session environment evidence identity mismatch')
    if (directory / 'interrupted.json').exists() or (
            config.get('trial_configuration_sha256') != manifest.get('trial_configuration_sha256') or
            result['configuration_sha256'] != digest(config) or
            result['session_sha256'] != digest(manifest) or
            config['environment'] != {'status': 'before-verified', 'sha256': required} or
            result['environment']['status'] != 'before-and-after-verified' or
            result['environment']['sha256'] != required):
        raise ValueError('session environment verification did not complete consistently')
    if manifest.get('coordinator_sha256') is not None:
        from . import coordinator_receipt
        for name in ('coordinator-before.json', 'coordinator-after.json'):
            try:
                recorded = read_json(directory / name)
            except FileNotFoundError as error:
                raise ValueError('missing required coordinator evidence') from error
            coordinator_receipt.validate(recorded, transport_identity=config['transport'])
            if recorded['sha256'] != manifest['coordinator_sha256'] or config.get('coordinator_sha256') != recorded['sha256']:
                raise ValueError('coordinator grading evidence mismatch')
    return {'sha256': required, 'driver_result_sha256': digest(result)}

def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('capture', 'verify'))
    parser.add_argument('receipt', type=Path)
    args = parser.parse_args()
    if args.operation == 'capture':
        if args.receipt.exists():
            raise FileExistsError(args.receipt)
        result = capture()
        write_json(args.receipt, result)
    else:
        result = verify(read_json(args.receipt), require_system=True)
    print(result['sha256'], round(result['capture_seconds'], 3), 'seconds; mutable-host receipt')


if __name__ == '__main__':
    main()
