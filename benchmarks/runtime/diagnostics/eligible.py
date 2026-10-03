#!/usr/bin/env python3
"""Measure the committed P7 public eligibility witness with matching source/object/options."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import runner as common
from build_compiler import validate_receipt
from compare_candidate import bootstrap
from backend_receipts import capture as backend_receipts

ARMS = ('my-llvm', 'my-qbe')
SOURCE_HASH = 'b0712cc25c1e254c97d414404c3228b84e9f927bdfc8cee65289d175847e7654'
C_HASH = '2815fd2935246477b5398e115f787fb150e4de12f70f332533eabdd2894cbf07'


def stamp():
    return datetime.now(timezone.utc).isoformat()


def checksum(count, seed):
    if not 1 <= count <= 10000000 or not 1 <= seed <= 1000000:
        raise ValueError('P7 witness input outside its declared domain')
    cycles, tail = divmod(count, 31)
    return count * (3 * seed + 6) + 3 * (cycles * 465 + tail * (tail - 1) // 2)


def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')


def inputs(args):
    paths = (args.before, args.after, args.source, args.c_source, Path(__file__),
             HERE / 'backend_receipts.py', HERE.parent / 'runner.py', HERE.parent / 'build_compiler.py', HERE.parent / 'compare_candidate.py',
             HERE.parent.parent.parent / 'scripts/build-slot.sh')
    return {str(path.resolve()): common.digest(path) for path in paths}


def check_build(args, built):
    if inputs(args) != built['inputs']:
        raise ValueError('P7 witness capture inputs changed')
    if built['compilers']['after']['source_revision'] != args.after_source_revision:
        raise ValueError('P7 pinned after source changed')
    for label, receipt in built['compilers'].items():
        validate_receipt(receipt, receipt['compiler_path'], artifacts=True)
    for path, digest in built['artifact_hashes'].items():
        if common.digest(path) != digest:
            raise ValueError('P7 witness artifact changed')
    if backend_receipts(built['binaries']) != built['effective_backends']:
        raise ValueError('P7 effective backend receipts changed')


def build(args):
    before_inputs = inputs(args)
    if common.digest(args.source) != SOURCE_HASH or common.digest(args.c_source) != C_HASH:
        raise ValueError('P7 witness differs from the committed, validated source')
    receipts = {label: json.loads(path.read_text()) for label, path in (('before', args.before), ('after', args.after))}
    for receipt in receipts.values():
        validate_receipt(receipt, receipt['compiler_path'], artifacts=True)
    if receipts['before']['source_revision'] != 'd348026f52eb02792e8c0c1d07dae7f6c8e26bd7' or receipts['after']['source_revision'] != args.after_source_revision:
        raise ValueError('P7 comparison must use d348 and the explicitly pinned reviewed P7 source')
    if receipts['before']['compiler_optimize'] != receipts['after']['compiler_optimize']:
        raise ValueError('P7 host compiler modes must match')
    environment = common.runtime_environment()
    private = {name: str(args.work / leaf) for name, leaf in
               (('TMPDIR', 'tmp'), ('ZIG_LOCAL_CACHE_DIR', 'zig-local'), ('ZIG_GLOBAL_CACHE_DIR', 'zig-global'))}
    for path in private.values():
        Path(path).mkdir(parents=True, exist_ok=True)
    environment.update(private)
    directory = args.work / 'sources'
    directory.mkdir(parents=True, exist_ok=True)
    source, c_source = directory / 'eligible-bench.my', directory / 'eligible-bench.c'
    shutil.copyfile(args.source, source)
    shutil.copyfile(args.c_source, c_source)
    wrapper = HERE.parent.parent.parent / 'scripts/build-slot.sh'
    cc = str(Path(shutil.which(args.cc) or args.cc).resolve())
    clock = args.work / 'clock.o'
    logs, binaries = [], {}

    def command(argv):
        actual = [str(wrapper), 'build', *argv]
        done = subprocess.run(actual, capture_output=True, text=True, env=environment, timeout=1800)
        logs.append({'command': actual, 'exit_status': done.returncode, 'stdout': done.stdout, 'stderr': done.stderr})
        atomic(args.work / 'build-log.json', logs)
        if done.returncode:
            raise ValueError('P7 witness build failed:\n' + done.stdout + done.stderr)

    command([cc, '-O2', '-c', str(c_source), '-o', str(clock)])
    for label, receipt in receipts.items():
        for arm in ARMS:
            backend = arm.removeprefix('my-')
            binary = args.work / 'bin' / (label + '-' + arm)
            binary.parent.mkdir(parents=True, exist_ok=True)
            argv = [receipt['compiler_path'], 'build', str(source), '--zig', receipt['zig']['path'],
                    '--qbe', str(Path(receipt['source_root']) / 'zig-out/bin/qbe'), '--mode', 'ReleaseFast', '--backend', backend,
                    '--link', str(clock), '--cache-dir', str(args.work / (label + '-' + backend + '-cache')),
                    '--keep-symbols', '-o', str(binary)]
            if backend == 'llvm':
                argv.extend(['--llvm-opt', '3', '--lto'])
            print('Building P7 witness ' + label + '/' + arm, flush=True)
            command(argv)
            binaries[label + '/' + arm] = str(binary)
    if inputs(args) != before_inputs:
        raise ValueError('P7 inputs changed during compilation')
    artifacts = [source, c_source, clock, Path(cc), *map(Path, binaries.values())]
    built = {'schema': 'mylang-runtime-eligible-build-v1', 'inputs': before_inputs, 'compilers': receipts,
             'source_paths': [str(source), str(c_source)], 'cc': cc, 'cc_sha256': common.digest(cc),
             'private_cache_environment': private, 'build_logs': logs, 'binaries': binaries,
             'artifact_hashes': {str(path): common.digest(path) for path in artifacts},
             'effective_backends': backend_receipts(binaries)}
    atomic(args.work / 'build-manifest.json', built)
    check_build(args, built)
    return built


def invoke(label, binary, count, seed, cpu):
    environment = common.runtime_environment()
    environment.update(LOCAL_LIST_ITERATIONS=str(count), LOCAL_LIST_SEED=str(seed))
    command = ['taskset', '-c', str(cpu), binary]
    with common.timing_lock():
        started = time.perf_counter_ns()
        done = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=120)
        wall = time.perf_counter_ns() - started
    return {'arm': label, 'iterations': count, 'seed': seed, 'process_wall_ns': wall,
            **common.validate(done, checksum(count, seed))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--after-source-revision', required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--c-source', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--cc', default='cc')
    parser.add_argument('--cpu', type=int, default=2)
    parser.add_argument('--iterations', type=int, default=1000000)
    parser.add_argument('--seed', type=int, default=17)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    checksum(args.iterations, args.seed)
    for name in ('before', 'after', 'source', 'c_source', 'work'):
        setattr(args, name, getattr(args, name).resolve())
    args.work.mkdir(parents=True, exist_ok=True)
    if args.cpu not in os.sched_getaffinity(0):
        raise ValueError('P7 timing CPU unavailable')
    if not args.build_only and (args.output is None or args.output.resolve() in (args.before, args.after, args.source, args.c_source)
                               or 'results' in args.output.resolve().parts):
        raise ValueError('P7 output must preserve inputs and baseline results')
    built = json.loads((args.work / 'build-manifest.json').read_text()) if args.skip_build else build(args)
    check_build(args, built)
    if args.build_only:
        print('PASS P7 witness builds: four guests; no timings')
        return
    report = {'schema': 'mylang-runtime-eligible-v1', 'status': 'in_progress', 'build': built,
              'started_utc': stamp(), 'iterations': args.iterations, 'seed': args.seed,
              'rounds': 15, 'warmup_rounds': 3, 'qualification': [], 'samples': [], 'warmups': [],
              'limitations': ['Distinct public eligibility witness with no retained argv/list inputs; unchanged frozen acceptance rows are separate.',
                              'Before and after share exact source, C object, guest RF/options and host compiler mode; no guard-disable flags.',
                              'Fixed1000000iterations/seed17 by default; paired intervals are exploratory without multiple-comparison or repeated-tuning correction.']}
    for count in (1, 2, 31, 32, 65, 127):
        for seed in (1, 17, 999983):
            for label, binary in built['binaries'].items():
                report['qualification'].append(invoke(label, binary, count, seed, args.cpu))
    snapshot = common.cpu_snapshot()
    for rnd in range(-3, 15):
        order = list(built['binaries'])
        random.Random('eligible-v1/' + str(rnd)).shuffle(order)
        for label in order:
            row = invoke(label, built['binaries'][label], args.iterations, args.seed, args.cpu)
            row.update(round=rnd, order=order)
            report['warmups' if rnd < 0 else 'samples'].append(row)
    report['environment'] = common.cpu_environment(args.cpu, snapshot, common.cpu_snapshot())
    check_build(args, built)
    report['comparisons'] = []
    for arm in ARMS:
        values = {label: [row['kernel_ns'] for row in sorted(report['samples'], key=lambda row: row['round'])
                          if row['arm'] == label + '/' + arm] for label in ('before', 'after')}
        report['comparisons'].append({'arm': arm, 'after_to_before': statistics.median(values['after']) / statistics.median(values['before']),
                                     'paired_bootstrap_95_interval': bootstrap(values['after'], values['before'], 'eligible-v1/' + arm)})
    report.update(status='eligibility_complete', finished_utc=stamp())
    atomic(args.output, report)
    print('PASS P7 eligibility timing: ' + str(args.output))


if __name__ == '__main__':
    main()
