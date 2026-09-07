"""Bounded source capture, immutable identities and coordinator-only atomic records."""
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False,
                      allow_nan=False).encode('utf-8')


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def write_json(path, value):
    path = Path(path)
    data = canonical(value) + b'\n'
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate JSON key: ' + key)
            result[key] = value
        return result
    return json.loads(Path(path).read_bytes(), object_pairs_hook=unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError('nonfinite JSON')))


def source_files(root, *, max_files=10000, max_bytes=32 * 1024 * 1024, hashes_only=False):
    """Read regular files through directory FDs, refusing symlinks and special files."""
    result = {}
    total = 0
    visited = 0

    def walk(fd, prefix, depth=0):
        nonlocal total, visited
        if depth > 64:
            raise ValueError('source directory depth exceeded')
        for name in sorted(os.listdir(fd)):
            visited += 1
            if visited > max_files:
                raise ValueError('source entry budget exceeded')
            relative = prefix + name
            child = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
            try:
                before = os.fstat(child)
                if stat.S_ISDIR(before.st_mode):
                    walk(child, relative + '/', depth + 1)
                elif stat.S_ISREG(before.st_mode):
                    chunks = []
                    hasher = hashlib.sha256()
                    while True:
                        chunk = os.read(child, min(65536, max_bytes - total + 1))
                        if not chunk:
                            break
                        total += len(chunk)
                        if total > max_bytes:
                            raise ValueError('source byte budget exceeded')
                        hasher.update(chunk)
                        if not hashes_only:
                            chunks.append(chunk)
                    after = os.fstat(child)
                    if (before.st_mtime_ns, before.st_ctime_ns, before.st_size) != (after.st_mtime_ns, after.st_ctime_ns, after.st_size):
                        raise ValueError('source changed during capture')
                    result[relative] = hasher.hexdigest() if hashes_only else b''.join(chunks)
                else:
                    raise ValueError('source must contain only regular files and directories')
            finally:
                os.close(child)
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        walk(fd, '')
    finally:
        os.close(fd)
    return result


def inventory(files):
    return {name: hashlib.sha256(data).hexdigest() for name, data in sorted(files.items())}


def snapshot(source, destination):
    files = source_files(source)
    expected = inventory(files)
    destination = Path(destination)
    destination.mkdir(parents=False, exist_ok=False)
    for name, data in files.items():
        path = destination / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    if inventory(source_files(source)) != expected:
        raise ValueError('source changed while snapshot was prepared')
    return {'files': expected, 'sha256': digest(expected)}


def verify_snapshot(path, receipt):
    current = inventory(source_files(path))
    if current != receipt['files'] or digest(current) != receipt['sha256']:
        raise ValueError('frozen source snapshot changed')


@contextmanager
def locked(root):
    """A persistent lock inode; no stale-lock guessing or unlink race."""
    descriptor = os.open(Path(root) / '.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(descriptor)


def path_identity(path):
    path = Path(path).resolve(strict=True)
    if path.is_dir():
        files = source_files(path, max_files=100000, max_bytes=2 * 1024**3, hashes_only=True)
        return {'path': str(path), 'kind': 'directory', 'sha256': digest(files)}
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 2 * 1024**3:
            raise ValueError('tool must be a bounded regular file')
        hasher = hashlib.sha256()
        count = 0
        while data := os.read(descriptor, 65536):
            count += len(data)
            if count > 2 * 1024**3:
                raise ValueError('tool byte budget exceeded')
            hasher.update(data)
        after = os.fstat(descriptor)
        if (metadata.st_mtime_ns, metadata.st_ctime_ns, metadata.st_size) != (after.st_mtime_ns, after.st_ctime_ns, after.st_size):
            raise ValueError('tool changed during hashing')
        return {'path': str(path), 'kind': 'file', 'sha256': hasher.hexdigest()}
    finally:
        os.close(descriptor)
