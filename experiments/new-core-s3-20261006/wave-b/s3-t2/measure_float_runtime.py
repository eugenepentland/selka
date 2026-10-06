#!/usr/bin/env python3
"""Measure the independent formatter cold build, reuse and version-key invalidation.

The first build-obj runs with a fresh Zig global cache. Version invalidation uses
an explicitly simulated version suffix, while still executing the same Zig.
Each program build retains its own stdout/stderr; tool timings are JSON lines.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--core', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--cache', type=Path, required=True)
    args = parser.parse_args()
    args.core = args.core.resolve()
    args.evidence = args.evidence.resolve()
    args.cache = args.cache.resolve()
    args.evidence.mkdir(parents=True, exist_ok=True)
    if args.cache.exists():
        raise SystemExit('cold runtime cache must not exist')
    args.cache.mkdir(parents=True)
    actual_zig = shutil.which('zig')
    version = subprocess.check_output([actual_zig, 'version'], text=True).strip()
    wrapper = args.evidence / 'zig_timing_wrapper.py'
    timing = args.evidence / 'tool-timings.jsonl'
    wrapper.write_text('''#!/usr/bin/env python3
import json, os, subprocess, sys, time
argv = sys.argv[1:]
if argv == ['version']:
    print(os.environ['S3_ACTUAL_ZIG_VERSION'] + os.environ.get('S3_SIMULATED_ZIG_SUFFIX', ''))
    raise SystemExit(0)
env = os.environ.copy()
if argv[:1] == ['build-obj']:
    env['ZIG_GLOBAL_CACHE_DIR'] = env['S3_FLOAT_ZIG_CACHE']
start = time.monotonic()
child = subprocess.run([os.environ['S3_ACTUAL_ZIG'], *argv], env=env)
with open(env['S3_FLOAT_TOOL_TIMINGS'], 'a') as log:
    log.write(json.dumps({'phase': env['S3_FLOAT_PHASE'], 'args': argv, 'seconds': time.monotonic()-start, 'status': child.returncode})+'\\n')
raise SystemExit(child.returncode)
''')
    wrapper.chmod(0o755)
    base = os.environ.copy()
    base.update(S3_ACTUAL_ZIG=actual_zig, S3_ACTUAL_ZIG_VERSION=version,
                S3_FLOAT_ZIG_CACHE=str(args.cache / 'fresh-zig-global'),
                S3_FLOAT_TOOL_TIMINGS=str(timing), MYL_CORE_RUNTIME_REPORT='1')
    results = []
    for phase, suffix in [('cold', ''), ('reuse', ''), ('version-invalidated', '-s3-cache-test')]:
        source = args.evidence / f'{phase}.my'
        source.write_text('def main(out: Stream) -> int:\n    out.print(str(-0.0), f"{0.125:.2f}", "1e-300".parse_float() != None)\n    return 0\n')
        output = args.cache / phase
        env = base | {'S3_FLOAT_PHASE': phase, 'S3_SIMULATED_ZIG_SUFFIX': suffix}
        command = [str(args.core), 'build', str(source), '-o', str(output), '--release', '--verify-facts', '--zig', str(wrapper), '--cache-dir', str(args.cache / 'runtime')]
        started = time.monotonic()
        result = subprocess.run(command, text=True, capture_output=True, env=env)
        wall = time.monotonic() - started
        (args.evidence / f'{phase}-build.stdout').write_text(result.stdout)
        (args.evidence / f'{phase}-build.stderr').write_text(result.stderr)
        if result.returncode:
            raise SystemExit(f'{phase} build failed: {result.stderr}')
        ran = subprocess.run([str(output)], text=True, capture_output=True, env=env | {'MYL_CORE_LEAKCHECK': '1'})
        assert (ran.returncode, ran.stdout, ran.stderr) == (0, '-0.0 0.12 True\n', ''), (phase, ran.returncode, ran.stdout, ran.stderr)
        results.append({'phase': phase, 'program_build_seconds': wall, 'cache_report': result.stderr.strip()})
    tools = [json.loads(line) for line in timing.read_text().splitlines()]
    for result in results:
        objects = [tool for tool in tools if tool['phase'] == result['phase'] and tool['args'][:1] == ['build-obj']]
        result['formatter_compiles'] = len(objects)
        result['formatter_seconds'] = sum(tool['seconds'] for tool in objects)
    assert [result['formatter_compiles'] for result in results] == [1, 0, 1], results
    report = {'actual_zig_version': version, 'first_unit_uses_fresh_global_cache': True,
              'version_invalidation_uses_simulated_suffix': True, 'results': results}
    (args.evidence / 'summary.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
