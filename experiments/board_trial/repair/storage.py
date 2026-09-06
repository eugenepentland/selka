"""Coordinator-owned snapshots, append-only attempt directories and tool identities."""
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil
import time


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.tmp')
    with temporary.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')
    temporary.replace(path)


def utc():
    return datetime.now(timezone.utc).isoformat()


def identity(path):
    path = Path(path).resolve(strict=True)
    return {'path': str(path), 'sha256': digest(path)}


def verify_tools(manifest):
    for item in manifest['tools'].values():
        if digest(item['path']) != item['sha256']:
            raise ValueError('tool changed since preparation: ' + item['path'])


def inventory(root):
    result = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError('symlinks are not trial source: ' + str(path))
        if path.is_file():
            result[path.relative_to(root).as_posix()] = digest(path)
    return result


def verify_base(root, manifest):
    if inventory(root / 'base') != manifest['base_files']:
        raise ValueError('coordinator baseline changed')


def verify_work(root, manifest):
    files = inventory(root / 'work')
    expected = set(manifest['editable']) | set(manifest['instructions'])
    if set(files) != expected:
        raise ValueError('work tree has missing or unexpected files')
    for name, expected_digest in manifest['instructions'].items():
        if files[name] != expected_digest:
            raise ValueError('task instructions changed: ' + name)
    return {name: files[name] for name in manifest['editable']}


@contextmanager
def locked(root):
    path = root / '.coordinator.lock'
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(fd, str(os.getpid()).encode())
        os.close(fd)
        yield
    finally:
        path.unlink()


def command(directory, name, argv, timeout=60):
    """Retain exact command, streams, timeout and elapsed time even on ordinary failure."""
    started = time.monotonic()
    record = {'argv': [str(value) for value in argv], 'started': utc()}
    try:
        process = subprocess.run(record['argv'], cwd=directory, capture_output=True, timeout=timeout)
        stdout, stderr = process.stdout, process.stderr
        record.update(status='passed' if process.returncode == 0 else 'failed', returncode=process.returncode)
    except subprocess.TimeoutExpired as error:
        stdout, stderr = error.stdout or b'', error.stderr or b''
        record.update(status='timeout', returncode=None)
    except OSError as error:
        stdout, stderr = b'', str(error).encode()
        record.update(status='launch-error', returncode=None)
    record['elapsed_seconds'] = time.monotonic() - started
    (directory / (name + '.stdout')).write_bytes(stdout)
    (directory / (name + '.stderr')).write_bytes(stderr)
    write_json(directory / (name + '.json'), record)
    return record


def work_inventory(root):
    result = {}
    for path in sorted(root.rglob('*')):
        name = path.relative_to(root).as_posix()
        if path.is_symlink():
            result[name] = {'symlink': os.readlink(path)}
        elif path.is_file():
            result[name] = digest(path)
    return result


def capture_work(source, destination, files):
    """Retain ordinary submitted bytes without following out-of-scope links."""
    for name, fingerprint in files.items():
        if not isinstance(fingerprint, str):
            continue
        path = source / name
        if path.is_symlink():
            raise ValueError('source changed during snapshot')
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, target)
        if digest(target) != fingerprint:
            raise ValueError('source changed during snapshot')
    if work_inventory(source) != files:
        raise ValueError('source changed during snapshot')
