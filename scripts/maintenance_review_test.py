#!/usr/bin/env python3
"""Independent F08 tests; private store/repository fixtures only."""
import fcntl
import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]


def load(name):
    path = Path(os.environ.get('F10_MAINTENANCE_SCRIPTS', ROOT / 'scripts')) / (name + '.py')
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


store = load('core_store_gc')
service = load('service_worktree')


def blocks(path):
    """Bytes `path` holds on disk."""
    return Path(path).stat().st_blocks * 512


class MaintenanceReview(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / '.tmp' / 'f10-maintenance'
        scratch.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def pair(self, number):
        key = f'{number:064x}'
        object_path = self.root / 'units-v1' / key[:2] / (key + '.o')
        object_path.parent.mkdir(parents=True, exist_ok=True)
        object_path.write_bytes(bytes([number]) * 100)
        Path(str(object_path) + '.sum').write_bytes(b'checksum')
        return object_path, self.root / 'units-v1' / object_path.name

    def test_aliases_preserve_payload_and_unique_accounting_and_eviction_headroom(self):
        # The live store holds hard-linked flat aliases of its sharded objects. The collector no longer makes them (compilers read
        # the shard first); it counts the bytes once and takes every name of an object with it.
        first, flat = self.pair(1)
        second_object, second_flat = self.pair(2)
        for sharded, legacy in ((first, flat), (second_object, second_flat)):
            os.link(sharded, legacy)
            os.link(str(sharded) + '.sum', str(legacy) + '.sum')
        # The budget is disk: a file weighs its allocated blocks, and an alias shares its inode's blocks.
        pair = blocks(first) + blocks(Path(str(first) + '.sum'))
        # The aliases stay for this test: the flat pass, which retires them, is off (`flat_budget`).
        initial = store.maintain(self.root, apply=True, maximum=100 * pair, grace_seconds=-60, flat_budget=0.0)
        self.assertEqual(initial['retained_bytes'], 2 * pair)
        self.assertEqual(first.stat().st_ino, flat.stat().st_ino)
        self.assertEqual(first.read_bytes(), flat.read_bytes())
        # A cap of 1.85 pairs holds one: the target is 90% of it, 1.67 pairs.
        second = store.maintain(self.root, apply=True, maximum=pair * 185 // 100, batch=1, grace_seconds=-60, flat_budget=0.0)
        self.assertLessEqual(second['retained_bytes'], pair * 185 // 100 * 9 // 10)
        self.assertFalse(second['unmet_target'])
        physical = {}
        for path in self.root.rglob('*'):
            if path.is_file() and path.name.startswith('0') and (path.name.endswith('.o') or path.name.endswith('.o.sum')):
                stamp = path.stat()
                physical[stamp.st_dev, stamp.st_ino] = stamp.st_blocks * 512
        self.assertEqual(sum(physical.values()), second['retained_bytes'])
        survivors = list((self.root / 'units-v1').glob('*/*.o'))
        self.assertEqual(len(survivors), 1)
        for sharded in survivors:
            legacy = self.root / 'units-v1' / sharded.name
            self.assertEqual(sharded.stat().st_ino, legacy.stat().st_ino)
            self.assertEqual(Path(str(sharded) + '.sum').stat().st_ino,
                             Path(str(legacy) + '.sum').stat().st_ino)
        self.assertEqual(len(list((self.root / 'units-v1').glob('*.o'))), 1)

    def test_in_place_size_change_is_rescanned_even_when_the_directory_stamp_matches(self):
        sharded, flat = self.pair(3)
        report = store.maintain(self.root, apply=False, maximum=1 << 30)
        old_directory = sharded.parent.stat()
        before = blocks(sharded)
        # Grow it across a block boundary: the inventory counts blocks.
        sharded.write_bytes(b'x' * (3 * 4096))
        self.assertEqual(sharded.parent.stat().st_mtime_ns, old_directory.st_mtime_ns)
        updated = store.maintain(self.root, apply=False, maximum=1 << 30, rescan_seconds=0)
        self.assertGreater(blocks(sharded), before)
        self.assertEqual(updated['inventory_bytes'] - report['inventory_bytes'], blocks(sharded) - before)

    def test_service_child_keeps_checkout_lease_after_supervisor_sigkill(self):
        main = self.root / 'main'
        main.mkdir()
        def git(*args):
            return subprocess.run(['git', '-C', str(main), *args], check=True,
                                  capture_output=True, text=True).stdout.strip()
        git('init', '-b', 'main')
        git('config', 'user.name', 'F10 fixture')
        git('config', 'user.email', 'f10@example.invalid')
        for relative in service.RUNNERS.values():
            path = main / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('#!/bin/bash\nprintf ready > "$1"\nread -r line < "$2"\nprintf done > "$1"\n')
        git('add', '.')
        git('-c', 'core.hooksPath=/dev/null', 'commit', '-m', 'private service fixture')
        checkout = self.root / 'service'
        git('worktree', 'add', '--detach', str(checkout))
        service.register(checkout)
        fifo, ready = self.root / 'release', self.root / 'ready'
        os.mkfifo(fifo)
        release = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
        process = subprocess.Popen([sys.executable, '-B', service.__file__, '--worktree', str(checkout),
                                    '--service', 'core', '--', str(ready), str(fifo)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        try:
            deadline = time.monotonic() + 15
            while not ready.exists() and time.monotonic() < deadline:
                self.assertIsNone(process.poll())
                time.sleep(.01)
            self.assertTrue(ready.exists())
            process.kill()
            self.assertEqual(process.wait(10), -signal.SIGKILL)
            with (main / '.git' / 'mylang-services.lock').open('r+') as lock:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            os.write(release, b'release\n')
            deadline = time.monotonic() + 15
            while ready.read_text() != 'done' and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertEqual(ready.read_text(), 'done')
        finally:
            os.write(release, b'release\n')
            os.close(release)
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            process.communicate(timeout=10)


if __name__ == '__main__':
    unittest.main()
