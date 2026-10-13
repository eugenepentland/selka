#!/usr/bin/env python3
"""Audit selected checked guest LLVM and symbols; this is not package retirement."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

PATTERN = r'(?:myl_core_(?:retain|release|share)(?:_[A-Za-z0-9_]+)?|myl\.layout\.[0-9]+\.(?:retain|release)|count_(?:load|is_unique|retain|release|release_shared))'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def audit(path):
    build = json.loads(path.read_text())
    common_path = Path(build['common_receipt'])
    assert sha(common_path) == build['common_receipt_sha256']
    common = json.loads(common_path.read_text())
    assert sha(build['compiler']) == build['compiler_sha256'] == common['compiler_sha256']
    for entry in common['installation_files']:
        assert sha(Path(common['installation']) / entry['path']) == entry['sha256']
    rows = {}
    for name in ('zero-rc', 'zero-rc-counted'):
        entry = build['binaries'][name]
        binary = Path(entry['path'])
        assert entry['status'] == 'ok' and sha(binary) == entry['sha256']
        symbols = subprocess.check_output(['nm', '--defined-only', str(binary)], text=True)
        legacy = sorted({line.split()[-1] for line in symbols.splitlines()
                         if line.split() and re.fullmatch(PATTERN, line.split()[-1])})
        rows[name] = {'binary': str(binary), 'binary_sha256': sha(binary),
                      'legacy_rc_native_symbols': legacy}
        assert not legacy, (name, legacy)
    entry = build['binaries']['zero-rc']['llvm']
    assert sha(entry['path']) == entry['sha256']
    source = Path(entry['path']).read_text()
    legacy = sorted(set(re.findall(r'@(' + PATTERN + r')\b', source)))
    # The emitter identifies managed-count loads with this TBAA/range pair.
    # Task synchronization counters have different provenance and remain valid.
    count_loads = re.findall(r'^.*load atomic i32[^\n]*!tbaa !3, !range !8.*$', source, re.M)
    count_initializers = re.findall(r'^\s*store i32 1, ptr %head, align 8, !tbaa !3\s*$', source, re.M)
    assert not legacy and not count_loads and not count_initializers
    return {'build_receipt': str(path.resolve()), 'build_receipt_sha256': sha(path),
            'binaries': rows, 'llvm': entry, 'legacy_rc_llvm_names': legacy,
            'managed_count_loads': len(count_loads), 'managed_count_initializers': len(count_initializers),
            'direct_drop_call_sites': len(re.findall(r'\bcall[^\n]*?@myl_core_drop_owned\b', source)),
            'scope': 'Selected checked guest LLVM and defined native symbols, including counted binaries. Runtime header layout and transfer soundness require the registered compiler tests. This does not establish retirement from the whole installed package.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('builds', nargs='+', type=Path)
    args = parser.parse_args()
    assert not args.output.exists()
    rows = {str(path.resolve()): audit(path) for path in args.builds}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({'harness_sha256': sha(__file__), 'builds': rows, 'status': 'passed'}, indent=2) + '\n')


if __name__ == '__main__':
    main()
