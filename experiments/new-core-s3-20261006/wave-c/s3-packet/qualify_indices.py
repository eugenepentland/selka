#!/usr/bin/env python3
"""Compare signed byte indices with the qualified old core, retaining every run."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[4]
INDICES = ('-1', '-3', '0', '2', '-4', '3', '-9223372036854775808', '9223372036854775807')


def run(command, evidence, name, native=False):
    done = subprocess.run(list(map(str, command)), capture_output=True, text=True,
                          env={**os.environ, 'MYL_CORE_LEAKCHECK': '1'} if native else None)
    record = dict(command=list(map(str, command)), status=done.returncode,
                  stdout=done.stdout, stderr=done.stderr)
    (evidence / f'{name}.json').write_text(json.dumps(record, indent=2) + '\n')
    if done.returncode < 0 or (not native and done.returncode) or (native and done.returncode not in (0, 1)):
        raise RuntimeError(f'bad status: {record}')
    if native and ('leak' in done.stderr or 'R_CORE_FACT' in done.stderr):
        raise RuntimeError(f'leak/fact failure: {record}')
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mylang', type=Path, required=True)
    parser.add_argument('--core', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    args = parser.parse_args()
    for path in (args.evidence, args.cache):
        if not path.resolve().is_relative_to(ROOT) or path.exists():
            raise RuntimeError(f'use a fresh private path: {path}')
        path.mkdir(parents=True)
    text = (ROOT / 'src/core/byte_index_test.zig').read_text()
    literal = text.split('const program =\n', 1)[1].split('\n;', 1)[0]
    source = args.cache / 'index.my'
    source.write_text('\n'.join(line.removeprefix('    \\\\') for line in literal.splitlines()) + '\n')
    modes = {'old-debug': (args.mylang, []), 'old-release': (args.mylang, ['--release']),
             'debug': (args.core, []), 'release': (args.core, ['--release']),
             'verify': (args.core, ['--release', '--verify-facts'])}
    binaries = {}
    summary = dict(qualified=False, binaries={}, comparisons=0, mismatches=[], error=None)
    try:
        for mode, (compiler, flags) in modes.items():
            output = args.cache / mode
            run([compiler, 'build', source, '-o', output, '--cache-dir', args.cache / f'cache-{mode}', *flags],
                args.evidence, f'build-{mode}')
            binaries[mode] = output
            summary['binaries'][mode] = hashlib.sha256(output.read_bytes()).hexdigest()
        for receiver in ('bytes', 'buffer', 'empty'):
            for index in INDICES if receiver != 'empty' else ('-1', '0'):
                records = {mode: run([binary, index, receiver], args.evidence, f'{receiver}-{index}-{mode}', True)
                           for mode, binary in binaries.items()}
                for mode in ('debug', 'release', 'verify'):
                    old = records['old-debug' if mode == 'debug' else 'old-release']
                    new = records[mode]
                    # Both compilers must preserve the same complete located trap,
                    # including normalized index, source frames and trap JSON.
                    if any(old[key] != new[key] for key in ('status', 'stdout', 'stderr')):
                        summary['mismatches'].append(dict(receiver=receiver, index=index, mode=mode, old=old, new=new))
                    summary['comparisons'] += 1
        summary['qualified'] = not summary['mismatches'] and summary['comparisons'] == 54
        print(f"index comparisons={summary['comparisons']} mismatches={len(summary['mismatches'])}", flush=True)
        return 0 if summary['qualified'] else 1
    except (OSError, RuntimeError) as error:
        summary['error'] = str(error)
        raise
    finally:
        (args.evidence / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
