#!/usr/bin/env python3
"""Acceptance for automatic checking, recovery, content identity, and shutdown."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    root = Path(__file__).resolve().parents[1]
    script = root / 'scripts/watch.py'
    spec = importlib.util.spec_from_file_location('watch_driver', script)
    watch = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(watch)
    with tempfile.TemporaryDirectory(prefix='mylang-watch-') as directory:
        directory = Path(directory)
        project = directory / 'project'
        project.mkdir()
        entry, data = project / 'main.my', project / 'data.my'
        entry.write_text('module main\nimport data\n\n\ndef main() -> i64:\n    return data.value()\n')
        valid = 'module data\nexport value\n\n\ndef value() -> i64:\n    return 7\n'
        data.write_text(valid)
        command = [sys.executable, str(script), str(entry), '--compiler', compiler, '--interval=.02']
        with tempfile.TemporaryFile() as diagnostics:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=diagnostics)
            with selectors.DefaultSelector() as ready:
                ready.register(process.stdout, selectors.EVENT_READ)

                def reply(status):
                    assert ready.select(30), 'watch reply timed out'
                    value = json.loads(process.stdout.readline())
                    assert value['status'] == status, value
                    return value

                try:
                    assert reply(0)['reuse'] == {'hits': 0, 'misses': 2}
                    data.touch()
                    assert not ready.select(.2), 'timestamp-only edit caused a check'
                    before = data.stat()
                    data.write_text(valid.replace('7', '9'))
                    os.utime(data, ns=(before.st_atime_ns, before.st_mtime_ns))
                    assert reply(0)['reuse'] == {'hits': 1, 'misses': 1}
                    replacement = project / 'replacement.tmp'
                    replacement.write_text(valid.replace('7', 'True'))
                    replacement.replace(data)
                    reply(1)
                    data.unlink()
                    reply(1)
                    data.write_text(valid)
                    reply(0)
                    nested = project / 'nested'
                    nested.mkdir()
                    entry.write_text('module main\nimport nested.value as nested\n\n\ndef main() -> i64:\n    return nested.value()\n')
                    reply(1)
                    (nested / 'value.my').write_text('module nested.value\nexport value\n\n\ndef value() -> i64:\n    return 4\n')
                    reply(0)
                    process.send_signal(signal.SIGTERM)
                    assert process.wait(timeout=10) == 143
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                    process.stdout.close()
        manifest = directory / 'config.json'
        manifest.write_text(json.dumps({'version': 1, 'module': 'config', 'values': [{'name': 'value', 'type': 'i64', 'value': '7'}]}))
        manifest_text = manifest.read_text()
        entry.write_text('module main\nimport config\n\n\ndef main() -> i64:\n    return config.value()\n')
        with tempfile.TemporaryFile() as diagnostics:
            process = subprocess.Popen(command + ['--inputs=' + str(manifest)], stdout=subprocess.PIPE, stderr=diagnostics)
            with selectors.DefaultSelector() as ready:
                ready.register(process.stdout, selectors.EVENT_READ)
                try:
                    assert ready.select(30)
                    assert json.loads(process.stdout.readline())['status'] == 0
                    manifest.write_text('{}')
                    assert ready.select(30)
                    assert json.loads(process.stdout.readline())['status'] == 2
                    manifest.unlink()
                    assert ready.select(30)
                    assert json.loads(process.stdout.readline())['status'] == 2
                    manifest.write_text(manifest_text)
                    assert ready.select(30)
                    assert json.loads(process.stdout.readline())['status'] == 0
                    process.send_signal(signal.SIGINT)
                    assert process.wait(timeout=10) == 130
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
                    process.stdout.close()
        rejected = subprocess.run(command + ['--once'], capture_output=True, timeout=30)
        assert rejected.returncode == 1 and json.loads(rejected.stdout)['status'] == 1
        accepted = subprocess.run(command + ['--once', '--inputs=' + str(manifest)], capture_output=True, timeout=30)
        assert accepted.returncode == 0 and json.loads(accepted.stdout)['status'] == 0
        fifo = project / 'blocked.my'
        os.mkfifo(fifo)
        assert watch.snapshot(project, [])[str(fifo)] == ('error', 'NotRegularFile')
        fifo.unlink()
        for limit in ({'max_entries': 1}, {'max_bytes': 1}):
            try:
                watch.snapshot(project, [], **limit)
                raise AssertionError('watch budget not enforced')
            except ValueError:
                pass
        (project / 'loop').symlink_to(project, target_is_directory=True)
        try:
            watch.snapshot(project, [])
            raise AssertionError('watch cycle not rejected')
        except ValueError:
            pass
        (project / 'loop').unlink()
        deep = directory / 'deep'
        deep.mkdir()
        current = deep
        for _ in range(256):
            current = current / 'x'
            current.mkdir()
        try:
            watch.snapshot(deep, [])
            raise AssertionError('watch depth not rejected')
        except ValueError:
            pass
        fake = directory / 'compiler'
        pid_file = directory / 'child.pid'
        fake.write_text('#!' + sys.executable + '\nimport os,time\nopen(' + repr(str(pid_file)) + ',"w").write(str(os.getpid()))\ntime.sleep(60)\n')
        fake.chmod(0o700)
        hung = subprocess.run([sys.executable, script, entry, '--compiler', fake, '--timeout=.2'], capture_output=True, timeout=10)
        assert hung.returncode == 2 and b'timed out' in hung.stderr, hung.stderr
        try:
            os.kill(int(pid_file.read_text()), 0)
            raise AssertionError('timed out compiler left running')
        except ProcessLookupError:
            pass
        # An edit after the child starts checking must schedule another request.
        started, proceed = directory / 'started', directory / 'proceed'
        fake.write_text('#!' + sys.executable + '\nimport os,pathlib,sys,time,json\n'
                        + 'for i,line in enumerate(sys.stdin):\n'
                        + ' if i == 0:\n'
                        + '  pathlib.Path(' + repr(str(started)) + ').write_text(str(os.getpid()))\n'
                        + '  while not pathlib.Path(' + repr(str(proceed)) + ').exists(): time.sleep(.01)\n'
                        + ' print(json.dumps({"version":"check-session-v1","action":"check","status":0,"sequence":i}),flush=True)\n')
        child = subprocess.Popen([sys.executable, script, entry, '--compiler', fake, '--interval=.02'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 10
            while not started.exists():
                assert time.monotonic() < deadline
                time.sleep(.01)
            entry.write_text(entry.read_text() + '\n# edit during check\n')
            proceed.touch()
            with selectors.DefaultSelector() as ready:
                ready.register(child.stdout, selectors.EVENT_READ)
                for sequence in range(2):
                    assert ready.select(10)
                    assert json.loads(child.stdout.readline())['sequence'] == sequence
            child.terminate()
            assert child.wait(timeout=10) == 143
            try:
                os.kill(int(started.read_text()), 0)
                raise AssertionError('interrupted watcher left its compiler running')
            except ProcessLookupError:
                pass
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            child.stdout.close()
            child.stderr.close()
        for payload in ('[]', '{"version":"check-session-v1","action":"check","status":true}'):
            fake.write_text('#!' + sys.executable + '\nimport sys\nsys.stdin.readline()\nprint(' + repr(payload) + ',flush=True)\n')
            bad = subprocess.run([sys.executable, script, entry, '--compiler', fake], capture_output=True, timeout=10)
            assert bad.returncode == 2 and b'invalid compiler session reply' in bad.stderr
        fake.write_text('#!' + sys.executable + '\n')
        ended = subprocess.run([sys.executable, script, entry, '--compiler', fake], capture_output=True, timeout=10)
        assert ended.returncode == 2 and b'ended before its reply' in ended.stderr
    print('watch acceptance: edits, recovery, content hashes, manifests, budgets, and child cleanup passed')


if __name__ == '__main__':
    main()
