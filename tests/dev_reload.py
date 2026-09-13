#!/usr/bin/env python3
"""Persistent host generations, failed repairs, snapshot isolation and watcher publication."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('development', ROOT / 'scripts/dev.py')
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


def source(byte):
    return 'module main;import io;fn main()->i64{_ = io::put(' + str(byte) + 'u8);return 0;}'


def wait_status(path, predicate, process):
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise AssertionError('watcher exited unexpectedly')
        try:
            value = json.loads(path.read_text())
            if predicate(value):
                return value
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(0.02)
    raise AssertionError('watcher did not reach expected status')


def protocol(runner, project, documents):
    host = dev.Host(runner)
    try:
        pid = host.process.pid
        first_key, first = dev.capture(project, documents)
        (project / 'main.my').write_text(source(66))
        assert dev.prepare(host, first)['svg'] == 'A'
        assert host.request('commit')['status'] == 'active'
        (_, second) = dev.capture(project, documents)
        assert dev.prepare(host, second)['svg'] == 'B'
        assert host.request('discard')['status'] == 'discarded'
        assert host.request('commit')['failure'] == 'NoPreparedGeneration'
        (project / 'main.my').write_text('module main;import io;import missing;fn main()->i64{return 0;}')
        assert dev.prepare(host, dev.capture(project, documents)[1])['status'] == 'error'
        (project / 'missing.my').write_text('module missing;')
        assert dev.capture(project, documents)[0] != first_key
        assert dev.prepare(host, dev.capture(project, documents)[1])['status'] == 'prepared'
        (project / 'missing.my').unlink()
        assert dev.prepare(host, dev.capture(project, documents)[1])['status'] == 'error'
        (project / 'main.my').write_text(source(67))
        io = project / 'io.my'
        original = io.read_text()
        io.write_text(original.replace('put(value: u8)', 'put(value: i64)'))
        (project / 'main.my').write_text(source(67).replace('67u8', '67'))
        assert dev.prepare(host, dev.capture(project, documents)[1])['status'] == 'error'
        io.write_text(original)
        (project / 'main.my').write_text(source(67))
        resident_path = Path('/proc') / str(pid) / 'statm'
        initial_pages = int(resident_path.read_text().split()[1])
        for _ in range(40):
            assert dev.prepare(host, dev.capture(project, documents)[1])['svg'] == 'C'
            assert host.request('commit')['status'] == 'active'
        final_pages = int(resident_path.read_text().split()[1])
        assert (final_pages - initial_pages) * os.sysconf('SC_PAGE_SIZE') < 16 * 1024 * 1024
        assert host.process.pid == pid and host.process.poll() is None
    finally:
        host.close()
    assert host.process.poll() == 0


def watcher(runner, project, documents, output):
    command = [sys.executable, str(ROOT / 'scripts/dev.py'), '--runner', str(runner),
               '--project', str(project), '--output', str(output), '--interval', '0.02',
               '--debounce', '0.02', *map(str, documents)]
    process = subprocess.Popen(command, env=dict(os.environ, PATH='/no-build-tools'),
                               stdout=subprocess.DEVNULL)
    status = Path(str(output) + '.status.json')
    try:
        first = wait_status(status, lambda v: v['state'] == 'fresh', process)
        assert output.read_text() == 'C'
        (project / 'main.my').write_text('module main; broken')
        wait_status(status, lambda v: v['failure'] is not None, process)
        assert output.read_text() == 'C'
        (project / 'main.my').write_text(source(68))
        fresh = wait_status(status, lambda v: v['state'] == 'fresh' and v['source'] != first['source'], process)
        assert fresh['host_pid'] == first['host_pid']
        assert output.read_text() == 'D'
        documents[0].write_text('changed fixture')
        wait_status(status, lambda v: v['state'] == 'fresh' and v['source'] != fresh['source'], process)
    finally:
        process.terminate()
        process.wait(timeout=5)
    stopped = json.loads(status.read_text())
    assert stopped['state'] == 'stopped'
    assert not (Path('/proc') / str(stopped['host_pid'])).exists()


def superseded(runner, project, documents, output):
    original = dev.prepare
    calls = []

    def change_during_request(host, files):
        response = original(host, files)
        calls.append(response)
        if len(calls) == 1:
            (project / 'main.my').write_text(source(69))
        return response

    dev.prepare = change_during_request
    try:
        assert dev.watch(SimpleNamespace(runner=runner, project=project, documents=documents,
                         output=output, debounce=0, interval=0.01, once=True)) == 0
    finally:
        dev.prepare = original
    assert len(calls) == 2 and output.read_text() == 'E'


def boundaries(runner, project, documents, root):
    fifo = project / 'blocked.my'
    os.mkfifo(fifo)
    try:
        try:
            dev.capture(project, documents)
            raise AssertionError('FIFO source accepted')
        except ValueError:
            pass
    finally:
        fifo.unlink()
    document = documents[0]
    data = document.read_bytes()
    document.unlink()
    os.mkfifo(document)
    try:
        try:
            dev.capture(project, documents)
            raise AssertionError('FIFO input accepted')
        except ValueError:
            pass
    finally:
        document.unlink()
        document.write_bytes(data)
    host = dev.Host(runner)
    host.response_limit = 8
    try:
        try:
            host.request('discard')
            raise AssertionError('oversized response accepted')
        except RuntimeError as error:
            assert 'limit' in str(error)
    finally:
        host.close()
    slow = root / 'slow-host'
    slow.write_text('#!' + sys.executable + "\nimport sys,time\nsys.stdin.readline()\nprint('partial',end='',flush=True)\ntime.sleep(30)\n")
    slow.chmod(0o700)
    host = dev.Host(slow)
    host.timeout = 0.05
    try:
        try:
            host.request('discard')
            raise AssertionError('partial response did not time out')
        except RuntimeError as error:
            assert 'timed out' in str(error)
    finally:
        host.close()
    result = subprocess.run([sys.executable, str(ROOT / 'scripts/dev.py'), '--runner', str(runner),
                             '--project', str(project), '--output', str(root / 'x'),
                             '--interval', 'nan', *map(str, documents)], capture_output=True)
    assert result.returncode == 2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', type=Path, required=True)
    runner = parser.parse_args().runner.resolve()
    before = (hashlib.sha256(runner.read_bytes()).hexdigest(), runner.stat().st_mtime_ns)
    with tempfile.TemporaryDirectory(prefix='dev reload ') as directory:
        root = Path(directory)
        project = root / 'project'
        project.mkdir()
        (project / 'io.my').write_bytes((ROOT / 'src/schematic/guest/io.my').read_bytes())
        (project / 'main.my').write_text(source(65))
        documents = [root / str(i) for i in range(3)]
        for document in documents:
            document.write_text('input')
        boundaries(runner, project, documents, root)
        protocol(runner, project, documents)
        watcher(runner, project, documents, root / 'preview.svg')
        superseded(runner, project, documents, root / 'preview.svg')
    assert before == (hashlib.sha256(runner.read_bytes()).hexdigest(), runner.stat().st_mtime_ns)
    print('persistent development reload: pass')


if __name__ == '__main__':
    main()
