#!/usr/bin/env python3
"""Execute aggregate success, optional-layout, and real trap-unwind RC probes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'experiments/d9-rc-aggregate-probes-20260926'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def optional_driver(workspace):
    imports, calls, hashes = [], [], {}
    for name in ('option_propagation', 'option_niche'):
        source = ROOT / 'tests/lang' / (name + '.my')
        text = source.read_text()
        hashes[str(source.relative_to(ROOT))] = sha(source)
        (workspace / source.name).write_text(text)
        imports.append('import ' + name)
        for case in re.findall(r'public def (test_\w+)\(', text):
            # This driver isolates aggregate layout; arena compiler integration
            # has its own probes after the runtime/compiler branches are joined.
            if True:
                calls.append(name + '.' + case)
    text = 'module aggregate_optional_driver\n' + '\n'.join(imports)
    text += '\n\ndef main() -> int:\n'
    text += ''.join('    assert ' + case + '()\n' for case in calls)
    text += '    return 0\n'
    path = workspace / 'aggregate_optional_driver.my'
    path.write_text(text)
    return path, calls, hashes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', choices=('qbe', 'llvm'), required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    workspace = args.workspace.resolve()
    workspace.mkdir(parents=True, exist_ok=True)
    optional, cases, hashes = optional_driver(workspace)
    aggregate = ROOT / 'tests/lang/rc_aggregate_values.my'
    trap = HERE / 'trap.my'
    result = {'compiler_sha256': sha(compiler), 'compiler_mode': 'Debug',
              'compiler_source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'backend': args.backend, 'guest_mode': 'ReleaseFast', 'groups': {}}
    groups = [('aggregate', aggregate, re.findall(r'public def (test_\w+)\(', aggregate.read_text())),
              ('optional', optional, cases), ('trap', trap, ['33-frame aggregate unwind'])]
    hashes.update({str(p.relative_to(ROOT)): sha(p) for p in (aggregate, trap)})
    result['source_sha256'] = hashes
    for name, source, selected in groups:
        command = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(source),
                   '--backend', args.backend, '--mode', 'ReleaseFast', '--rc-runtime=stats',
                   '--cache-dir=' + str(workspace / 'cache'), '--max-memory=512M', '--run']
        done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300)
        records = [json.loads(line.removeprefix('MYLANG_RC_COUNTS '))
                   for line in done.stderr.splitlines() if line.startswith('MYLANG_RC_COUNTS ')]
        row = {'cases': selected, 'command': command, 'exit': done.returncode,
               'stdout': done.stdout, 'stderr': done.stderr, 'counts': records}
        result['groups'][name] = row
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        assert done.returncode == (1 if name == 'trap' else 0), row
        assert not done.stdout and len(records) == 1, row
        counts = records[0]
        assert counts['version'] == 1 and not counts['saturated'], row
        assert counts['heap_allocate'] == counts['retire'], row
        assert counts['heap_allocate'] + counts['owner_acquire'] == counts['owner_release'], row
        assert counts['hold_acquire'] == counts['hold_release'], row
        if name == 'trap':
            assert 'aggregate unwind probe' in done.stderr and 'R_ASSERT' in done.stderr, row
        print(args.backend, name, len(selected), counts, flush=True)


if __name__ == '__main__':
    main()
