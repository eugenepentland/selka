#!/usr/bin/env python3
"""Qualify later compiler/combined probes on the retained semantic mutations."""
import importlib.util
import json
from pathlib import Path

from audit import ROOT, OUT, WORK, CURRENT, BASE, sha

spec = importlib.util.spec_from_file_location('algorithm_qualification', OUT / 'algorithm/qualify.py')
algorithm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(algorithm)
algorithm.WORK = WORK / 'extended-qualification'
algorithm.WORK.mkdir(exist_ok=True)

ARMS = {
    'aggregate-inline': (WORK / 'codegen/gc-lto-none-aggregate-inline', False),
    'aggregate-inline-bounded': (WORK / 'codegen/gc-lto-both-aggregate-inline', True),
    'combined-control': (WORK / 'host/aggregate-inline-metadata-control', False),
    'combined-typed': (WORK / 'host/aggregate-inline-typed-host', False),
    'combined-control-bounded': (WORK / 'host/aggregate-inline-bounded-metadata-control', True),
    'combined-typed-bounded': (WORK / 'host/aggregate-inline-bounded-typed-host', True),
    'stack-ceiling': (WORK / 'frames/gc-lto-none-stack-ceiling', False),
    'stack-ceiling-bounded': (WORK / 'frames/gc-lto-both-stack-ceiling', True),
}

def main():
    projects = {case: BASE / 'projects' / case for case in ('fixture', 'changed-net', 'changed-value')}
    projects.update({case: WORK / 'algorithm' / f'variant-project-{case}' for case in algorithm.qualify_variants.variants()})
    results = {}
    for case, project in projects.items():
        expected = algorithm.invoke(str(CURRENT / 'gc-lto'), project)
        assert expected[0] == (13 if case == 'empty_net_rejected' else 0)
        for name, (binary, bounded) in ARMS.items():
            for stress in (False, True):
                extra = ('--max-steps=100000000',) if bounded else ()
                actual = algorithm.invoke(str(binary), project, stress=stress, extra=extra)
                assert actual == expected, (name, case, stress, actual[:3], expected[:3])
        results[case] = {'status': expected[0], 'svg_sha256': algorithm.sha(expected[3]),
                         'issue_sha256': algorithm.sha(expected[4]), 'all_normal_and_stress_match': True}
    budgets = {}
    for name, (binary, bounded) in ARMS.items():
        if not bounded:
            continue
        budgets[name] = {}
        for option, marker in (('--max-steps=1', b'R_STEP_LIMIT'), ('--max-frames=1', b'R_FRAME_LIMIT')):
            result = algorithm.invoke(str(binary), BASE / 'projects/fixture', extra=(option,))
            assert result[0] != 0 and marker in result[2], (name, option, result[:3])
            budgets[name][option] = {'status': result[0], 'marker': marker.decode()}
    (OUT / 'extended-qualification.json').write_text(json.dumps({
        'binaries': {name: {'path': str(binary.relative_to(ROOT)), 'sha256': sha(binary)} for name, (binary, _) in ARMS.items()},
        'cases': results, 'budget_rejections': budgets,
        'scope': 'Ten schematic inputs and GC stress; this is not a general compiler safety proof. The stack ceiling still bypasses correct native stack admission accounting.'}, indent=2) + '\n')
    print(f'{len(ARMS)} probes pass {len(projects)} cases normally and under GC stress; bounded probes reject low step/frame budgets.')


if __name__ == '__main__':
    main()
