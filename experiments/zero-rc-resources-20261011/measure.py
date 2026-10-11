#!/usr/bin/env python3
"""Qualify scoped resources in five pipelines, with a native exactly-once oracle."""
import argparse
import json
import os
from pathlib import Path
import sys
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE.parent / 'zero-rc-20261011'))
import measure as common


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('compiler', 'before', 'zig', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    for name in ('compiler', 'before', 'zig', 'output'):
        setattr(args, name, getattr(args, name).resolve())
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, ZIG=str(args.zig), MYLANG_ZIG=str(args.zig), MYL_CORE_LEAKCHECK='1')
    env.pop('MYLANG_COUNTERS', None)
    env.pop('MYLANG_OPTIONS', None)
    result = {'schema': 'zero-rc-stage4-v1', 'tools': {k: {'path': str(getattr(args, k)), 'sha256': common.digest(getattr(args, k))}
              for k in ('compiler', 'before', 'zig')}, 'harness_sha256': common.digest(__file__), 'cases': {}}
    for source in sorted((HERE / 'samples').glob('*.my')):
        configs = {}
        modes = dict(common.MODES)
        # The frozen compiler traps when closing read_only files (R_FILE).
        # Stage 4 fixes that independently; preserve its failed log separately.
        if source.stem not in ('nested_error', 'native_readonly'):
            modes['rc-baseline'] = ['--release']
        for mode, flags in modes.items():
            baseline = mode == 'rc-baseline'
            selected = HERE / 'baseline' / source.name if baseline else source
            directory = args.output / source.stem / mode
            directory.mkdir(parents=True, exist_ok=True)
            binary, llvm, counters = (directory / name for name in ('program', 'program.ll', 'counts-0.json'))
            linked = source.with_suffix('.c')
            common.command([args.before if baseline else args.compiler, 'build', selected,
                            *([] if baseline else ['--experimental-zero-rc']), '--zig', args.zig,
                            '--cache-dir', args.output / 'cache', '--counters', *flags,
                            *( ['--link', linked] if linked.exists() else [] ), '-o', binary, '--emit-llvm', llvm],
                           directory / 'build', env)
            if not baseline:
                common.clean_ir(llvm)
            stdout = common.command([binary], directory / 'run', dict(env, MYLANG_COUNTERS=str(counters)))
            assert stdout == source.with_suffix('.stdout').read_text(), (source, mode, stdout)
            assert not (directory / 'run.stderr').read_bytes()
            audit = common.audit.audit(counters)
            assert audit['managed_leak_free'] and (baseline or audit['observed_rc_free']), audit
            summary = common.census.summarize(json.loads(counters.read_text()))
            configs[mode] = {'source': str(selected.relative_to(ROOT)), 'source_sha256': common.digest(selected),
                             'binary_sha256': common.digest(binary), 'llvm_sha256': common.digest(llvm),
                             'audit': audit, 'whole_program': summary['whole_program'], 'stdout': stdout,
                             'linked_sha256': common.digest(linked) if linked.exists() else None}
            print('pass', source.stem, mode, flush=True)
        result['cases'][source.stem] = configs
        common.save(args.output / 'partial-results.json', result)
    for tool in result['tools'].values():
        assert common.digest(tool['path']) == tool['sha256']
    result['summary'] = {'samples': len(result['cases']), 'candidate_runs': len(result['cases']) * len(common.MODES),
                         'comparison_runs': sum('rc-baseline' in x for x in result['cases'].values())}
    common.save(HERE / 'results.json', result)
    print(json.dumps(result['summary']), flush=True)


if __name__ == '__main__':
    main()
