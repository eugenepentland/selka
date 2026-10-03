#!/usr/bin/env python3
"""Apply the sweep overlay to the exact immutable joined-flat control source."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def hashes(source):
    return {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(source.rglob('*')) if p.is_file()}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--control-source', type=Path, required=True)
    p.add_argument('--dest', type=Path, required=True)
    p.add_argument('--initial', action='store_true', help='78-test initial measured arm; default is final 80-test arm')
    a = p.parse_args()
    here = Path(__file__).resolve().parent
    records = json.loads((here / 'qualification.json').read_text())['source']
    assert hashes(a.control_source) == records['control']['all_files_sha256'], 'control source differs from frozen joined-flat baseline'
    assert not a.dest.exists(), 'destination already exists'
    shutil.copytree(a.control_source, a.dest)
    patch = here / ('sweep.patch' if a.initial else 'final-sweep.patch')
    with patch.open('rb') as stream:
        subprocess.run(['patch', '-p1', '--batch', '--forward'], cwd=a.dest, stdin=stream, check=True)
    arm = 'sweep' if a.initial else 'qualified'
    assert hashes(a.dest) == records[arm]['all_files_sha256'], 'overlay replay differs from recorded source'
    print(f'exact {arm} source replayed at {a.dest.resolve()}')


if __name__ == '__main__':
    main()
