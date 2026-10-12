#!/usr/bin/env python3
"""Run the complete A05 matrix in bounded shared-admission batches."""
# spec: NEW-CORE-ZERO-RC-LIBRARY-1 NEW-CORE-ZERO-RC-RESOURCES-1
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MODES = ['release', 'debug', 'verified', 'optimized-debug', 'no-facts']


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--compiler-revision', required=True)
    p.add_argument('--compiler-sha256', required=True)
    p.add_argument('--zig', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--ordinary-command', action='store_true')
    a = p.parse_args()
    if not re.fullmatch('[0-9a-f]{40}', a.compiler_revision):
        p.error('a complete integrated compiler revision is required')
    compiler = a.compiler.resolve()
    actual = hashlib.sha256(compiler.read_bytes()).hexdigest()
    if actual != a.compiler_sha256:
        p.error('compiler hash differs from the frozen manifest')
    a.output = a.output.resolve()
    a.output.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location('qualify', HERE / 'qualify.py')
    qualify = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(qualify)
    positives = sorted(path.stem for path in (HERE / 'samples').glob('*.my'))
    positives += ['sort', 'math', 'integer_extrema', 'pool', 'time_random', 'time_random_provider',
                  'memo_fixture', 'dictionary_get_readonly', 'guest_application_cache', 'guest_capability_fields',
                  'guest_rc_capability_values', 'guest_rc_contract_results',
                  'guest_test_capabilities', 'guest_stdlib']
    negatives = sorted(qualify.NEGATIVE_CASES)
    batches = [positives[i:i + 2] for i in range(0, len(positives), 2)]
    batches += [negatives[i:i + 10] for i in range(0, len(negatives), 10)]
    report = {'compiler': str(compiler), 'compiler_revision': a.compiler_revision,
              'compiler_sha256': actual, 'positive_cases': positives, 'negative_cases': negatives,
              'modes': MODES, 'batches': [], 'passed': False}
    for index, cases in enumerate(batches):
        output = a.output / ('batch-' + str(index).zfill(2))
        cmd = [str(ROOT / 'scripts/build-slot.sh'), 'build', sys.executable, '-B',
               str(HERE / 'qualify.py'), '--compiler', str(compiler),
               '--compiler-revision', a.compiler_revision, '--zig', str(a.zig),
               '--output', str(output), '--modes', *MODES, '--cases', *cases]
        if a.ordinary_command:
            cmd.append('--ordinary-command')
        ran = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=1800)
        row = {'index': index, 'cases': cases, 'argv': cmd, 'status': ran.returncode,
               'stdout': ran.stdout, 'stderr': ran.stderr, 'receipt': str(output / 'results.json')}
        report['batches'].append(row)
        (a.output / 'matrix.json').write_text(json.dumps(report, indent=2) + '\n')
        print('batch', index, cases, 'status', ran.returncode, flush=True)
    report['passed'] = all(row['status'] == 0 for row in report['batches'])
    (a.output / 'matrix.json').write_text(json.dumps(report, indent=2) + '\n')
    return not report['passed']


if __name__ == '__main__':
    raise SystemExit(main())
