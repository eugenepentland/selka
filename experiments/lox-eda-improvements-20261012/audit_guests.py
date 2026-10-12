#!/usr/bin/env python3
"""Audit the selected guest call sites and native symbols, not package retirement."""
import json
from pathlib import Path
import re
import subprocess

from receipts import build_path, sha, validate_build

HERE = Path(__file__).resolve().parent
PATTERN = r'(?:myl_core_(?:retain|release|share)(?:_[A-Za-z0-9_]+)?|myl\.layout\.[0-9]+\.(?:retain|release)|count_(?:load|is_unique|retain|release|release_shared))'


def main():
    results = {}
    for app in ('lox', 'eda'):
        path = build_path(app)
        build = validate_build(path)
        binary = Path(build['binaries']['zero-rc']['path'])
        llvm = binary.with_suffix('.ll')
        source = llvm.read_text()
        calls = sorted(set(re.findall(r'\bcall[^\n]*?@(' + PATTERN + r')\b', source)))
        symbols = subprocess.check_output(['nm', '--defined-only', str(binary)], text=True)
        legacy = sorted({line.split()[-1] for line in symbols.splitlines()
                         if line.split() and re.fullmatch(PATTERN, line.split()[-1])})
        results[app] = {'binary': str(binary), 'binary_sha256': sha(binary),
            'llvm': str(llvm), 'llvm_sha256': sha(llvm), 'build_receipt': str(path), 'build_receipt_sha256': sha(path),
            'legacy_rc_call_names': calls, 'legacy_rc_native_symbols': legacy,
            'direct_drop_call_sites': len(re.findall(r'\bcall[^\n]*?@myl_core_drop_owned\b', source)),
            'scope': 'Selected checked guest LLVM calls and defined native symbols. Compiler/runtime sources are unchanged; this does not establish RC retirement from the complete installed package.'}
        assert not calls and not legacy, app
    destination = HERE / 'guest-rc-symbol-audit.json'
    assert not destination.exists()
    destination.write_text(json.dumps(results, indent=2) + '\n')
    print('Both selected guests have no audited RC calls or symbols; direct destruction remains allowed.')


if __name__ == '__main__':
    main()
