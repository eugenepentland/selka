#!/usr/bin/env python3
"""Pair versioned component probes with current ordinary guests; no acceptance claims."""
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

from prepare import HERE, RUNTIME, VARIANTS, prepare, sha
sys.path.insert(0, str(RUNTIME / 'expanded'))
from registry import checksum as original_checksum, inventory
sys.path.insert(0, str(RUNTIME))
import runner as common
from build_compiler import validate_receipt
from compare_candidate import bootstrap

ARMS = common.ARMS
MOD = 1000000007


def stamp():
    return datetime.now(timezone.utc).isoformat()


def checksum(variant, size, iterations, seed):
    if variant in ('dispatch_outside', 'escaped_allocation'):
        return original_checksum(VARIANTS[variant]['case'], size, iterations, seed)
    if variant == 'arithmetic_only':
        phases = [sum(((j + phase) * 17 + 23) // 7 % 1009 for j in range(size)) for phase in range(17)]
        cycles, remainder = divmod(iterations, 17)
        return (cycles * sum(phases) + sum(phases[:remainder])) % MOD
    if variant == 'collection_only':
        return (sum((seed + j * 13) % 1009 for j in range(size)) * iterations) % MOD
    if variant == 'text_without_score':
        numbers = [(seed + j * 137) % 1000003 for j in range(size)]
        lengths = [len(str(-n if j % 3 == 0 else n)) for j, n in enumerate(numbers)]
        ordered = [lengths[(seed + j) % size] for j in range(size)]
        cycles, remainder = divmod(iterations, size)
        return (cycles * sum(ordered) + sum(ordered[:remainder])) % MOD
    raise ValueError('unknown diagnostic variant')


def atomic(path, document):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(document, indent=2, allow_nan=False) + '\n')
    temporary.replace(path)


def inputs(args):
    return {str(path.resolve()): common.digest(path) for path in
            (args.manifest, Path(__file__), HERE / 'prepare.py', RUNTIME / 'runner.py',
             RUNTIME / 'build_compiler.py', RUNTIME / 'expanded/registry.py',
             RUNTIME / 'compare_candidate.py')}


def build(args, base):
    work = args.work
    before_inputs = inputs(args)
    source_receipt = prepare(args.manifest, work / 'sources')
    identity = base['identity']
    environment = common.runtime_environment()
    private = {'TMPDIR': str(work / 'tmp'), 'GOCACHE': str(work / 'gocache'),
               'ZIG_LOCAL_CACHE_DIR': str(work / 'zig-local'),
               'ZIG_GLOBAL_CACHE_DIR': str(work / 'zig-global')}
    for directory in private.values():
        Path(directory).mkdir(parents=True, exist_ok=True)
    environment.update(private)
    binaries, commands, logs = {}, {}, []
    for variant, meta in VARIANTS.items():
        directory = work / 'sources' / variant
        old_directory = RUNTIME / 'expanded' / meta['group']
        for arm in ARMS:
            name = variant + '/' + arm
            binary = work / 'bin' / (variant + '-' + arm)
            binary.parent.mkdir(parents=True, exist_ok=True)
            original_name = meta['group'] + '/' + arm
            original_binary = identity['binary_paths'][original_name]
            command = []
            for argument in identity['commands'][original_name]:
                if argument == original_binary:
                    argument = str(binary)
                elif argument.startswith('-femit-bin='):
                    argument = '-femit-bin=' + str(binary)
                elif argument.startswith(str(old_directory) + '/'):
                    argument = str(directory / Path(argument).name)
                elif argument == str(Path(identity['private_cache_environment']['TMPDIR']).parent / 'mycache'):
                    argument = str(work / 'mycache')
                command.append(argument)
            copy = None
            if arm == 'rust' and meta['group'] == 'text':
                target = work / 'cargo-target' / variant
                command[command.index('--target-dir') + 1] = str(target)
                copy = target / 'release/runtime_text'
            actual = [identity['build_wrapper'], 'build', *command]
            print('Building diagnostic ' + name, flush=True)
            done = subprocess.run(actual, cwd=directory, env=environment, capture_output=True, text=True, timeout=1800)
            logs.append({'name': name, 'command': actual, 'exit_status': done.returncode,
                         'stdout': done.stdout, 'stderr': done.stderr})
            atomic(work / 'build-log.json', logs)
            if done.returncode:
                raise ValueError('diagnostic build failed: ' + name + '\n' + done.stdout + done.stderr)
            if copy:
                shutil.copyfile(copy, binary)
                binary.chmod(0o755)
            binaries[name] = str(binary)
            commands[name] = actual
    if inputs(args) != before_inputs:
        raise ValueError('diagnostic build inputs changed during compilation')
    manifest = {'schema': 'mylang-runtime-components-build-v1', 'status': 'complete', 'inputs': before_inputs,
                'sources': source_receipt, 'base_identity': identity, 'base_binary_hashes': base['binary_hashes'],
                'private_cache_environment': private, 'commands': commands, 'build_logs': logs,
                'binaries': binaries, 'binary_hashes': {name: common.digest(path) for name, path in binaries.items()}}
    atomic(work / 'build-manifest.json', manifest)
    return manifest


def verify_build(args, base, built):
    if built['inputs'] != inputs(args) or built['base_identity'] != base['identity']:
        raise ValueError('diagnostic build inputs changed')
    receipt = base['identity']['compiler_build_receipt']['receipt']
    validate_receipt(receipt, base['identity']['tools']['mylang']['path'], artifacts=True)
    if common.digest(base['identity']['build_wrapper']) != base['identity']['wrapper_sha256']:
        raise ValueError('diagnostic build wrapper changed')
    for tool in base['identity']['tools'].values():
        if common.digest(tool.get('compiler_path', tool['path'])) != tool['sha256']:
            raise ValueError('diagnostic compiler/tool changed')
        if 'invocation_sha256' in tool and common.digest(tool['path']) != tool['invocation_sha256']:
            raise ValueError('diagnostic compiler invocation changed')
    for variant in built['sources']['variants'].values():
        for row in variant['files']:
            if common.digest(row['generated']) != row['generated_sha256'] or common.digest(row['diff']) != row['diff_sha256']:
                raise ValueError('diagnostic source or diff changed')
        for row in variant['dependencies']:
            if common.digest(row['generated']) != row['generated_sha256']:
                raise ValueError('diagnostic dependency source changed')
    for name, path in built['binaries'].items():
        if common.digest(path) != built['binary_hashes'][name]:
            raise ValueError('diagnostic executable changed')
    for name, path in base['identity']['binary_paths'].items():
        if common.digest(path) != base['binary_hashes'][name]:
            raise ValueError('ordinary executable changed')


def choices(variant, built, base):
    meta = VARIANTS[variant]
    selected = []
    for arm in ARMS:
        if meta['control'] == 'original':
            binary = base['identity']['binary_paths'][meta['group'] + '/' + arm]
        else:
            binary = built['binaries'][meta['control'] + '/' + arm]
        selected.extend([('control', arm, binary), ('probe', arm, built['binaries'][variant + '/' + arm])])
    return selected


def expected(variant, role, size, count, seed):
    if role == 'probe':
        return checksum(variant, size, count, seed)
    control = VARIANTS[variant]['control']
    return original_checksum(VARIANTS[variant]['case'], size, count, seed) if control == 'original' else checksum(control, size, count, seed)


def invoke(variant, role, arm, binary, size, count, seed, cpu, rss=False):
    return {'variant': variant, 'role': role, 'arm': arm, 'size': size, 'iterations': count, 'seed': seed,
            **common.invoke(Path(binary), VARIANTS[variant]['case'], size, count, seed, cpu,
                            expected(variant, role, size, count, seed), rss=rss)}


def measure(args, base, built):
    document = {'schema': 'mylang-runtime-components-v1', 'status': 'diagnostic_in_progress',
                'started_utc': stamp(), 'build': built, 'rounds': args.rounds, 'warmup_rounds': args.warmups,
                'plans': [], 'qualification': [], 'pilots': [], 'warmups': [], 'samples': [], 'memory': [],
                'limitations': ['Versioned workload changes are diagnostics, never original acceptance measurements.',
                                'Component timing differences are not additive or causal isolation: optimizers, value distributions and live memory change.',
                                'Arithmetic-only inputs use scalar j instead of collection values; setup stays outside timing.',
                                'Text-only uses ASCII integer output length, removing the entire byte fold as well as encode.',
                                'Returned allocation lists escape the construction function and are retained to consumption; physical allocation still requires assembly/counter evidence.',
                                'Paired intervals are exploratory, without multiple-comparison or repeated-tuning correction.']}
    for variant in VARIANTS:
        arms = choices(variant, built, base)
        for size, seed, count in ((2, 1, 1), (3, 42, 7), (17, 999983, 31)):
            for role, arm, binary in arms:
                document['qualification'].append(invoke(variant, role, arm, binary, size, count, seed, args.cpu))
        for profile, size in zip(('small', 'large'), inventory()[VARIANTS[variant]['case']]['sizes']):
            count = 31
            while True:
                rows = [invoke(variant, role, arm, binary, size, count, 42, args.cpu) for role, arm, binary in arms]
                document['pilots'].extend(rows)
                fastest, slowest = min(row['kernel_ns'] for row in rows), max(row['kernel_ns'] for row in rows)
                if fastest >= 50000000 or slowest >= 1000000000 or count >= 10000000:
                    reason = 'target' if fastest >= 50000000 else 'slowest_cap' if slowest >= 1000000000 else 'iteration_cap'
                    break
                growth = min(20, 50000000 / fastest, 1000000000 / slowest)
                if growth < 1.05:
                    reason = 'growth_below_5_percent'
                    break
                count = min(10000000, max(count + 1, int(count * growth)))
            document['plans'].append({'variant': variant, 'profile': profile, 'size': size, 'iterations': count,
                                      'calibration': {'fastest_ns': fastest, 'slowest_ns': slowest, 'reason': reason,
                                                      'target_ns': 50000000, 'slowest_cap_ns': 1000000000,
                                                      'iteration_cap': 10000000, 'limited': fastest < 50000000}})
    snapshot = common.cpu_snapshot()
    document['measurement_started_utc'] = stamp()
    for plan in document['plans']:
        variant, size, count = plan['variant'], plan['size'], plan['iterations']
        arms = choices(variant, built, base)
        print('Measuring diagnostic ' + variant + '/' + plan['profile'], flush=True)
        for rnd in range(-args.warmups, args.rounds):
            order = list(arms)
            random.Random(f'components-v1/{variant}/{size}/{rnd}').shuffle(order)
            for role, arm, binary in order:
                row = invoke(variant, role, arm, binary, size, count, 42, args.cpu)
                row.update(round=rnd, profile=plan['profile'], order=[role + '/' + arm for role, arm, _ in order])
                document['warmups' if rnd < 0 else 'samples'].append(row)
        for role, arm, binary in arms:
            document['memory'].append(invoke(variant, role, arm, binary, size, count, 42, args.cpu, rss=True))
        atomic(args.work / 'progress.json', document)
    document['environment'] = common.cpu_environment(args.cpu, snapshot, common.cpu_snapshot())
    verify_build(args, base, built)
    document['comparisons'] = []
    for plan in document['plans']:
        for arm in ARMS:
            selected = [row for row in document['samples'] if row['variant'] == plan['variant'] and row['size'] == plan['size'] and row['arm'] == arm]
            values = {role: [row['kernel_ns'] for row in sorted(selected, key=lambda row: row['round']) if row['role'] == role]
                      for role in ('control', 'probe')}
            control, probe = statistics.median(values['control']), statistics.median(values['probe'])
            document['comparisons'].append({'variant': plan['variant'], 'profile': plan['profile'], 'size': plan['size'],
                                            'arm': arm, 'control_ns_per_iteration': control / plan['iterations'],
                                            'probe_ns_per_iteration': probe / plan['iterations'], 'probe_to_control': probe / control,
                                            'paired_bootstrap_95_interval': bootstrap(values['probe'], values['control'],
                                                f"components-v1/{plan['variant']}/{plan['size']}/{arm}")})
    document.update(status='diagnostic_complete', finished_utc=stamp())
    return document


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--cpu', type=int, default=2)
    parser.add_argument('--rounds', type=int, default=15)
    parser.add_argument('--warmups', type=int, default=3)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    args.work = args.work.resolve()
    args.work.mkdir(parents=True, exist_ok=True)
    if args.rounds < 1 or args.warmups < 0 or args.cpu not in os.sched_getaffinity(0):
        raise ValueError('invalid diagnostic sampling settings or unavailable CPU')
    base = json.loads(args.manifest.read_text())
    validate_receipt(base['identity']['compiler_build_receipt']['receipt'], base['identity']['tools']['mylang']['path'], artifacts=True)
    built = json.loads((args.work / 'build-manifest.json').read_text()) if args.skip_build else build(args, base)
    verify_build(args, base, built)
    if args.build_only:
        print('PASS diagnostic builds: 30 guests; no timing collected')
        return
    if args.output is None:
        raise ValueError('--output is required for diagnostic measurements')
    if args.output.resolve() == args.manifest.resolve() or 'results' in args.output.resolve().parts:
        raise ValueError('diagnostic output must preserve baseline inputs/results')
    document = measure(args, base, built)
    atomic(args.output, document)
    print('PASS diagnostic evidence: ' + str(args.output))


if __name__ == '__main__':
    main()
