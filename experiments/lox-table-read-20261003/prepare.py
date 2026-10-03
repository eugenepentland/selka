#!/usr/bin/env python3
"""Apply a table read overlay to the exact frozen final-sweep source."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def hashes(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob('*')) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--dest', type=Path, required=True)
    parser.add_argument('--variant', choices=['final', 'wrapper', 'direct', 'local'],
                        default='final')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    expected = json.loads((here / 'control-source.json').read_text())
    assert hashes(args.baseline) == expected['source_all_files_sha256'], 'baseline source differs'
    assert not args.dest.exists(), 'destination must be new'
    shutil.copytree(args.baseline, args.dest)
    patch = {'final': 'final-table-entries.patch',
             'wrapper': 'intermediate-wrapper.patch',
             'direct': 'intermediate-direct.patch',
             'local': 'rejected-local.patch'}[args.variant]
    subprocess.run(['patch', '--batch', '--fuzz=0', '-p1', '-i', str(here / patch)],
                   cwd=args.dest, check=True)
    if args.variant == 'final':
        final = json.loads((here / 'final-source.json').read_text())
        assert hashes(args.dest) == final['source_all_files_sha256'], 'overlay replay differs'
    print(json.dumps(hashes(args.dest), indent=2))


if __name__ == '__main__':
    main()
