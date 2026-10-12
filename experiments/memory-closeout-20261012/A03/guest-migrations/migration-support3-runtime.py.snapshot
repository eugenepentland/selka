#!/usr/bin/env python3
"""Check/run all transferred guest test functions; preserve rejected denominators.

Uses bounded shared admission from census.py. Do not wrap in build-slot.sh.
The mirror's synthetic main calls each public test in source order. Original
function bodies and assertions are retained, including an existing main (renamed).
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
import census


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--source-revision', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--check-only', action='store_true')
    parser.add_argument('--files', nargs='*')
    parser.add_argument('--ownership', choices=['opt-in', 'default'], default='opt-in')
    parser.add_argument('--modes', nargs='+', choices=list(census.MODES), default=['release'])
    args = parser.parse_args()
    root = census.ROOT
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output / 'results.json').exists():
        raise SystemExit('choose a fresh output directory; evidence already exists')
    ids = json.loads((census.HERE / 'guest-migrations/a01-handoff-identities.json').read_text())
    files = args.files or list(ids)
    mirror = output / 'sources'
    shutil.copytree(root / 'tests', mirror / 'tests')
    env = dict(os.environ, MYL_CORE_LEAKCHECK='1', ZIG=str(args.zig.resolve()), MYLANG_ZIG=str(args.zig.resolve()))
    for key in ('MYLANG_CORE_SANITIZE', 'MYLANG_COUNTERS', 'MYLANG_OPTIONS'):
        env.pop(key, None)
    lease = census.AdmissionLease(output, env, 10)
    census.LEASE = lease
    audit = census.load_helper('a03_migration_audit', 'experiments/zero-rc-20261011/audit.py')
    results = {'compiler_source_revision': args.source_revision,
               'compiler_path': str(args.compiler.resolve()), 'compiler_sha256': census.digest(args.compiler),
               'harness_sha256': census.digest(__file__), 'census_helper_sha256': census.digest(census.__file__),
               'ownership': args.ownership,
               'modes': args.modes, 'check_only': args.check_only, 'files': {}, 'failures': []}
    mode_flags = ['--experimental-zero-rc'] if args.ownership == 'opt-in' else []
    try:
        for name in files:
            original = root / name
            text = original.read_text()
            names = re.findall(r'^public func (test_\w+)\(\) -> bool:', text, re.M)
            unsupported = re.findall(r'^public func (test_\w+)\([^\n]*', text, re.M)
            if len(names) != len(unsupported):
                raise RuntimeError('nonstandard test signature in ' + name)
            derived = re.sub(r'^((?:public )?func )main\(', r'\1a03_original_main(', text, flags=re.M)
            derived += '\n\nfunc main(out: Stream) -> int:\n' if names else '\n\nfunc main() -> int:\n'
            derived += ''.join('    out.print(' + fn + '())\n' for fn in names)
            derived += '    return 0\n'
            source = mirror / name
            source.write_text(derived)
            row = {'source_sha256': census.digest(original), 'derived_sha256': census.digest(source),
                   'tests': names, 'test_count': len(names), 'modes': {}}
            results['files'][name] = row
            modes = ['check'] if args.check_only else args.modes
            for mode in modes:
                directory = output / 'raw' / name / mode
                directory.mkdir(parents=True, exist_ok=True)
                command = [args.compiler.resolve(), 'check' if args.check_only else 'build', source,
                           '--cache-dir', output / 'cache', *mode_flags]
                binary = directory / 'program'
                llvm = directory / 'program.ll'
                if not args.check_only:
                    command += ['--zig', args.zig.resolve(), *census.MODES[mode], '--counters',
                                '-o', binary, '--emit-llvm', llvm]
                result = census.invoke(command, directory / 'build', env, admitted=True)
                item = {'build': result}
                row['modes'][mode] = item
                if result['exit'] != 0:
                    results['failures'].append(name + '/' + mode + '/build')
                elif not args.check_only:
                    item.update(binary_sha256=census.digest(binary), llvm_sha256=census.digest(llvm))
                    symbols = subprocess.run(['nm', str(binary)], capture_output=True, text=True, check=True).stdout
                    item['structural_rc_free'] = not any(symbol in symbols or symbol in llvm.read_text()
                                                         for symbol in census.RC_SYMBOLS)
                    if not item['structural_rc_free']:
                        results['failures'].append(name + '/' + mode + '/structural')
                    counted = dict(env, MYLANG_COUNTERS=str(directory / 'counts.json'))
                    run = census.invoke([binary], directory / 'run', counted)
                    item['run'] = run
                    item['expected_stdout'] = 'True\n' * len(names)
                    item['passed'] = run['exit'] == 0 and run['stdout'] == item['expected_stdout'] and run['stderr'] == ''
                    if (directory / 'counts.json').exists():
                        item['counts'] = json.loads((directory / 'counts.json').read_text())
                        item['audit'] = audit.audit(directory / 'counts.json')
                    item['passed'] = (item['passed'] and item.get('audit', {}).get('observed_rc_free', False)
                                      and item.get('audit', {}).get('managed_leak_free', False))
                    if not item['passed']:
                        results['failures'].append(name + '/' + mode + '/run')
                census.save(output / 'results.json', results)
                print(name, mode, result['exit'], result['stderr'].split('\n')[0], flush=True)
    finally:
        lease.close()
        census.save(output / 'results.json', results)
    return 1 if results['failures'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
