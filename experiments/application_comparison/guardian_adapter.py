"""Trusted main-arm Zig adapter, including an enforced Guardian policy boundary."""
from pathlib import Path
from .execution import freeze_adapter, verify_adapter
from .isolation import Limits
from .storage import path_identity

ROOT = Path(__file__).resolve().parent


def commands():
    return [
        {'phase': 'guardian', 'argv': ['/usr/bin/python3', '-I', '-S', '/tools/guardian_runner']},
        {'phase': 'check', 'argv': ['/tools/zig/zig', 'test', 'main.zig', '-ODebug']},
        {'phase': 'build', 'argv': ['/tools/zig/zig', 'build-exe', 'main.zig', '-OReleaseSafe', '-femit-bin=/cache/app']},
        {'phase': 'run', 'argv': ['/cache/app']}]


def freeze(guardian, zig):
    return freeze_adapter('zig', {'guardian': guardian, 'zig': zig,
        'guardian_runner': ROOT / 'guardian_runner.py', 'guardian_policy': ROOT / 'guardian_policy'}, commands(),
        limits=Limits(wall_seconds=60, cpu_seconds=60, memory_bytes=4 * 1024**3))


def require(adapter):
    verify_adapter(adapter)
    if (adapter['language'] != 'zig' or adapter['commands'] != commands() or
            set(adapter['tools']) != {'guardian', 'zig', 'guardian_runner', 'guardian_policy'}):
        raise ValueError('main Zig adapter requires the trusted Guardian entry and tools')
    for name, path in [('guardian_runner', ROOT / 'guardian_runner.py'), ('guardian_policy', ROOT / 'guardian_policy')]:
        if adapter['tools'][name] != path_identity(path):
            raise ValueError('main Zig Guardian implementation or policy identity mismatch')
