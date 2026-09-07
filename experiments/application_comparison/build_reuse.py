"""Suite-local verified executables; never cache behavioral answers or failed gates."""
import copy
import hashlib
import os
from pathlib import Path
import stat
from .storage import digest


class BuildReuse:
    """Coordinator memory only. Each runtime gets its own writable executable copy.

A new instance defines a new suite. Entries cannot be supplied by participants or
loaded from their caches. Source, full adapter/tool identities and limits key each
entry; callers verify those live identities before and after every evaluation.
"""
    def __init__(self):
        self.entries = {}

    @staticmethod
    def eligible(adapter):
        return (adapter['language'] == 'zig' and len(adapter['commands']) > 1 and
                adapter['commands'][-1]['argv'][0] == '/cache/app' and
                adapter['commands'][-2]['phase'] == 'build')

    @staticmethod
    def key(receipt, adapter):
        return digest({'policy': 'suite-build-reuse-v1', 'source': receipt['sha256'],
                       'adapter': adapter['sha256']})

    def restore(self, receipt, adapter, cache):
        entry = self.entries.get(self.key(receipt, adapter))
        if entry is None:
            return None
        data, metadata = entry
        if hashlib.sha256(data).hexdigest() != metadata['binary_sha256']:
            raise ValueError('prepared executable identity changed')
        target = Path(cache) / 'app'
        with target.open('xb') as stream:
            stream.write(data)
        target.chmod(0o700)
        return dict(copy.deepcopy(metadata), reused=True)

    def capture(self, receipt, adapter, cache, directory, steps):
        # Sandbox descendants have terminated before this coordinator-only read.
        # Never follow a candidate-provided symlink into the coordinator filesystem.
        fd = os.open(Path(cache) / 'app', os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        try:
            info = os.fstat(fd)
            if (not stat.S_ISREG(info.st_mode) or not info.st_mode & stat.S_IXUSR or
                    info.st_size > adapter['limits']['file_bytes']):
                raise ValueError('build must produce a bounded regular executable')
            with os.fdopen(fd, 'rb', closefd=False) as stream:
                data = stream.read(adapter['limits']['file_bytes'] + 1)
            if len(data) != info.st_size:
                raise ValueError('prepared executable changed or exceeded limit')
        finally:
            os.close(fd)
        key = self.key(receipt, adapter)
        metadata = {'policy': 'suite-build-reuse-v1', 'key': key,
                    'binary_sha256': hashlib.sha256(data).hexdigest(),
                    'origin_directory': str(Path(directory).resolve()),
                    'prefix_steps_sha256': digest(steps)}
        self.entries[key] = (data, metadata)
        return dict(copy.deepcopy(metadata), reused=False)
