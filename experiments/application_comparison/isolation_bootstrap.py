#!/usr/bin/env python3
"""Trusted namespace setup. Never expose this entry point as a participant tool."""
import ctypes
import json
import os
from pathlib import Path
import resource
import subprocess
import sys


def command(*args):
    subprocess.run(args, check=True, stdin=subprocess.DEVNULL,
                   stdout=subprocess.DEVNULL, close_fds=True)


def bind(source, target, writable=False):
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        target.mkdir(exist_ok=True)
    else:
        target.touch()
    command('/usr/bin/mount', '--bind', str(source), str(target))
    flags = 'remount,bind,nosuid,nodev' + ('' if writable else ',ro')
    command('/usr/bin/mount', '-o', flags, str(target))


def setup(config):
    root = Path(config['root'])
    command('/usr/bin/mount', '--make-rprivate', '/')
    command('/usr/bin/mount', '-t', 'tmpfs', '-o', 'size=64m,nosuid,nodev', 'tmpfs', str(root))
    for target, source in config['system_mounts'].items():
        bind(Path(source), root / target.lstrip('/'))
    for path in ('/dev/null', '/dev/zero', '/dev/urandom'):
        # Device files need their device semantics, unlike ordinary bind mounts.
        target = root / path.lstrip('/')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.touch()
        command('/usr/bin/mount', '--bind', path, str(target))
    for name in ('tmp', 'proc', 'home/worker', 'tools'):
        (root / name).mkdir(parents=True, exist_ok=True)
    command('/usr/bin/mount', '-t', 'tmpfs', '-o', 'size=256m,nosuid,nodev', 'tmpfs', str(root / 'tmp'))
    command('/usr/bin/mount', '-t', 'proc', '-o', 'nosuid,nodev,noexec', 'proc', str(root / 'proc'))
    bind(Path(config['work']), root / 'work', writable=True)
    bind(Path(config['cache']), root / 'cache', writable=True)
    for name, path in config['tools'].items():
        bind(Path(path), root / 'tools' / name)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_AS, (config['memory_bytes'], config['memory_bytes']))
    resource.setrlimit(resource.RLIMIT_FSIZE, (config['file_bytes'], config['file_bytes']))
    resource.setrlimit(resource.RLIMIT_NOFILE, (256, 256))
    resource.setrlimit(resource.RLIMIT_CPU, (config['cpu_seconds'], config['cpu_seconds']))
    os.chroot(root)
    os.chdir('/work')
    # Setpriv clears the capability bounding set before executing untrusted code.
    # PR_SET_DUMPABLE prevents same-uid processes using /proc/<pid>/root during setup.
    os.write(config['ready_fd'], b'isolated\n')
    os.close(config['ready_fd'])
    argv = ['/usr/bin/setpriv', '--no-new-privs', '--bounding-set=-all',
            '--inh-caps=-all', '--ambient-caps=-all',
            '--securebits=+noroot,+noroot_locked', *config['argv']]
    os.execve(argv[0], argv, {'PATH': '/usr/bin:/bin:/tools', 'HOME': '/home/worker',
                            'LANG': 'C.UTF-8', 'LC_ALL': 'C.UTF-8', 'PYTHONHASHSEED': '0',
                            'PYTHONDONTWRITEBYTECODE': '1',
                            'ZIG_GLOBAL_CACHE_DIR': '/cache/zig-global',
                            'ZIG_LOCAL_CACHE_DIR': '/cache/zig-local'})


def main():
    # No participant processes exist in this PID namespace before setup completes.
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(4, 0, 0, 0, 0) != 0:
        raise OSError(ctypes.get_errno(), 'cannot disable setup ptrace access')
    config = json.loads(sys.argv[1])
    try:
        setup(config)
    except Exception as error:
        print('comparison isolation setup failed: ' + str(error), file=sys.stderr)
        return 125


if __name__ == '__main__':
    sys.exit(main())
