#!/usr/bin/env python3
"""Qualify host probes and record callback counts; no sustained timing."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / '.tmp/svg-slowdown-20260921/host'
FULL = ROOT / '.tmp/full-svg-benchmark-20260921'
OUT = Path(__file__).resolve().parent
DECLARED = ('io::circuit_input,io::pinout_input,io::interface_input,'
            'io::length,io::byte,io::put,io::issue')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def invoke(name, case='fixture', extra=()):
    project = FULL / 'projects' / case
    output = WORK / f'{name}-{case}.svg'
    issue = WORK / f'{name}-{case}.issue'
    output.write_bytes(b'')
    issue.write_bytes(b'')
    env = dict(os.environ)
    env.update(MYLANG_SCHEMATIC_DECLARED=DECLARED,
               MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
    docs = ('lib/modules/straps-synth-lmx2595.sexp',
            'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
    env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(project / path)
                for i, path in enumerate(docs)})
    result = subprocess.run(['taskset', '-c', '6', str(WORK / name), '--print-result', *extra], cwd=ROOT,
                            env=env, capture_output=True)
    return result, output.read_bytes(), issue.read_bytes()


def main():
    cases = {}
    for case in ('fixture', 'changed-net', 'changed-value'):
        cases[case] = {}
        reference = None
        for name in ('original-control', 'control', 'scalar-fast'):
            result, svg, issue = invoke(name, case)
            assert (result.returncode, result.stdout, result.stderr, issue) == (0, b'0\n', b'', b'')
            if reference is None:
                reference = svg
            assert svg == reference
            cases[case][name] = {'svg_bytes': len(svg), 'svg_sha256': digest(svg)}
    normal, normal_svg, normal_issue = invoke('counts')
    assert (normal.returncode, normal.stdout, normal_issue) == (0, b'0\n', b'')
    counts = {}
    for line in normal.stderr.decode().splitlines():
        prefix, name, value = line.split()
        assert prefix == 'host_calls'
        counts[name] = int(value)
    stressed, stressed_svg, stressed_issue = invoke('scalar-fast', extra=('--gc-stress',))
    assert (stressed.returncode, stressed.stdout, stressed.stderr, stressed_issue) == (0, b'0\n', b'', b'')
    assert stressed_svg == normal_svg
    evidence = {
        'passed': True,
        'cases': cases,
        'call_counts': counts,
        'total_calls': sum(counts.values()),
        'gc_stress_scalar_fast_equals_control': True,
        'limitation': ('Diagnostic scalar fast path assumes this provider default node budget. '
                       'It does not yet preserve unusually restrictive max_values settings; '
                       'generic production eligibility/fallback and adversarial budget tests remain required. '
                       'All measured cases use unchanged provider defaults.'),
        'semantics': ('scalar-fast retains production registry/signature/capability initialization, call/work budgets, '
                      'no-reentry and scalar output validation; only scalar node sizing and generic recursive traversal '
                      'are replaced; non-scalar declarations use the unchanged generic path'),
    }
    (OUT / 'qualification.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()
