#!/usr/bin/env python3
"""Exercise the real SVG application through one persistent VM development host."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def wait_status(path, predicate, process):
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        assert process.poll() is None, 'watcher exited'
        try:
            row = json.loads(path.read_text())
            if predicate(row):
                return row
        except (FileNotFoundError, json.JSONDecodeError):
            pass
        time.sleep(0.05)
    raise AssertionError('watcher did not publish expected status')


def trial(runner):
    binary_hash = hashlib.sha256(runner.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='schematic-reload-') as directory:
        folder = Path(directory)
        project = folder / 'guest'
        shutil.copytree(ROOT / 'src/schematic/guest', project)
        fixtures = ROOT / 'experiments/schematic/fixtures'
        documents = [fixtures / name for name in ('straps-synth-lmx2595.sexp', 'lmx2595rhar.sexp', 'spi.sexp')]
        output = folder / 'preview.svg'
        status = Path(str(output) + '.status.json')
        process = subprocess.Popen([sys.executable, str(ROOT / 'scripts/dev.py'),
            '--runner', str(runner), '--project', str(project), '--output', str(output),
            '--interval', '0.05', '--debounce', '0.05', *map(str, documents)],
            env=dict(os.environ, PATH='/no-build-tools'), stdout=subprocess.DEVNULL)
        try:
            first = wait_status(status, lambda row: row['state'] == 'fresh', process)
            original_svg = output.read_bytes()
            renderer = project / 'svg.my'
            original = renderer.read_text()
            assert '#0d1117' in original
            renderer.write_text(original.replace('#0d1117', '#123abc'))
            changed = wait_status(status, lambda row: row['state'] == 'fresh' and row['source'] != first['source'], process)
            assert changed['host_pid'] == first['host_pid']
            changed_svg = output.read_bytes()
            assert changed_svg == original_svg.replace(b'#0d1117', b'#123abc')
            renderer.write_text('module svg; broken')
            failed = wait_status(status, lambda row: row['failure'] is not None, process)
            assert failed['active'] == changed['active']
            assert output.read_bytes() == changed_svg
            renderer.write_text(original)
            repaired = wait_status(status, lambda row: row['state'] == 'fresh' and row['source'] == first['source'], process)
            assert repaired['host_pid'] == first['host_pid']
            assert output.read_bytes() == original_svg
        finally:
            process.terminate()
            process.wait(timeout=10)
        assert json.loads(status.read_text())['state'] == 'stopped'
    assert hashlib.sha256(runner.read_bytes()).hexdigest() == binary_hash
    return {'runner_sha256': binary_hash, 'same_host_process': True,
            'changed_svg_exactly': True, 'failed_edit_retained_last_good': True,
            'repair_restored_original': True, 'build_tools_on_path': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = trial(args.runner.resolve())
    if args.output:
        args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('SVG reload: changed, failed, and repaired real guest in one host; unchanged binary')
