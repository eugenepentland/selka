#!/usr/bin/env python3
"""Build and measure all four languages; preserve the original v1 baseline."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import random
import shutil
import subprocess
import sys
import uuid

from registry import HERE, GROUPS, EDGE_PROBES, checksum, inventory, plans_for

sys.path.insert(0, str(HERE.parent))
import runner as common

ARMS = common.ARMS
SCHEMA = 'mylang-runtime-expanded-v2'
ROOT = HERE.parents[2]
FROZEN_BASELINE = HERE / 'results/baseline_main_20261003.json'
FROZEN_BASELINE_SHA256 = 'b595d9638e243e18692b5cef491c2b5273949c93ebf22a0ae604a08704c1d3f7'


def stamp():
    return datetime.now(timezone.utc).isoformat()


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def configuration(args):
    _, templates, identity = common.configuration(args)
    source_root = HERE.parent
    paths = [source_root / name for name in ('runner.py', 'oracle.py', 'CONTRACT.md')]
    paths += list((source_root / 'ports').glob('*'))
    paths += [p for p in HERE.rglob('*') if p.is_file()
              and 'results' not in p.relative_to(HERE).parts
              and '__pycache__' not in p.parts
              and (p.suffix in ('.py', '.my', '.rs', '.go', '.zig', '.c', '.md', '.toml', '.lock', '.json'))]
    identity['sources'] = {str(p.relative_to(source_root)): common.digest(p) for p in sorted(set(paths)) if p.is_file()}
    identity['inventory'] = inventory()
    identity['source_root'] = str(source_root)
    binaries, commands, copies = {}, {}, {}
    for group in GROUPS:
        directory = source_root / 'ports' if group == 'legacy' else HERE / group
        for arm, template in templates.items():
            name = group + '/' + arm
            binary = args.work / 'bin' / (group + '-' + arm)
            binaries[name] = binary
            command = []
            for argument in template:
                if argument == str(args.work / arm):
                    argument = str(binary)
                elif argument.startswith('-femit-bin='):
                    argument = '-femit-bin=' + str(binary)
                elif argument.startswith(str(source_root / 'ports' / 'main.')):
                    argument = str(directory / Path(argument).name)
                command.append(argument)
            if arm.startswith('my-'):
                command.append('--keep-symbols')
            if group == 'text' and arm == 'rust':
                cargo = str(Path(shutil.which(args.cargo) or args.cargo).absolute())
                target = args.work / 'cargo-target'
                command = [cargo, 'build', '--release', '--locked', '--manifest-path',
                           str(directory / 'Cargo.toml'), '--target-dir', str(target)]
                copies[name] = str(target / 'release' / 'runtime_text')
                version = subprocess.run([cargo, '--version'], check=True, capture_output=True, text=True,
                                         env=common.runtime_environment(), timeout=30)
                actual_cargo = Path(cargo).resolve()
                if actual_cargo.name == 'rustup':
                    resolved = subprocess.run([str(actual_cargo), 'which', 'cargo'], check=True,
                                              capture_output=True, text=True, timeout=30,
                                              env=common.runtime_environment())
                    actual_cargo = Path(resolved.stdout.strip()).resolve(strict=True)
                identity['tools']['cargo'] = {'path': cargo, 'compiler_path': str(actual_cargo),
                                              'sha256': common.digest(actual_cargo), 'invocation_sha256': common.digest(cargo),
                                              'version': version.stdout.strip(), 'version_status': 0}
            commands[name] = command
    identity['commands'] = commands
    identity['actual_build_commands'] = {name: [identity['build_wrapper'], 'build', *command]
                                         for name, command in commands.items()}
    identity['post_build_copies'] = copies
    identity['binary_paths'] = {key: str(value) for key, value in binaries.items()}
    identity['target_policy']['rust_text'] = 'cargo release defaults, portable target; locked serde_json dependency'
    identity['target_policy']['mylang_symbols'] = '--keep-symbols preserves names for profiling; release optimization remains enabled'
    # Explicit RUSTC makes Cargo use the same audited compiler as the direct ports.
    identity['private_cache_environment']['RUSTC'] = identity['tools']['rust']['path']
    identity['reference_reuse'] = reference_reuse(args, identity)
    for name, receipt in identity['reference_reuse'].items():
        identity['actual_build_commands'][name] = ['copy-verified-reference', receipt['binary_path'], str(binaries[name])]
    return binaries, identity


def frozen_references():
    if common.digest(FROZEN_BASELINE) != FROZEN_BASELINE_SHA256:
        raise ValueError('immutable frozen baseline changed')
    baseline = json.loads(FROZEN_BASELINE.read_text())
    references = {}
    for plan in baseline['plans']:
        rows = [row for row in baseline['summary'] if (row['case'], row['size']) == (plan['case'], plan['size'])]
        fastest = min(rows, key=lambda row: (row['median_ns_per_op'], ARMS.index(row['arm'])))
        name = plan['group'] + '/' + fastest['arm']
        binary = baseline['identity']['binary_paths'][name]
        if common.digest(binary) != baseline['binary_hashes'][name]:
            raise ValueError('frozen winner executable changed: ' + name)
        references[(plan['case'], plan['size'])] = {
            'arm': fastest['arm'], 'name': name, 'binary_path': binary,
            'binary_sha256': baseline['binary_hashes'][name], 'baseline_sha256': FROZEN_BASELINE_SHA256,
            'target_ns_per_iteration': fastest['median_ns_per_op']}
    return references, baseline['identity']


def reference_reuse(args, identity):
    """Reuse executable bytes only after checking their original source/tool receipts."""
    if not args.reuse_reference_manifest:
        return {}
    path = args.reuse_reference_manifest.resolve()
    if common.digest(path) != args.expected_reference_manifest_sha256:
        raise ValueError('reference manifest SHA256 mismatch')
    saved = json.loads(path.read_text())
    receipts = {}
    for name, binary in saved['identity']['binary_paths'].items():
        group, arm = name.split('/')
        if arm.startswith('my-'):
            continue
        if common.digest(binary) != saved['binary_hashes'][name]:
            raise ValueError('reference executable differs from manifest: ' + name)
        tool = 'rust' if arm == 'rust' else 'zig' if arm.startswith('zig-') else arm
        for key in (tool, *(['cargo'] if group == 'text' and arm == 'rust' else [])):
            if saved['identity']['tools'][key] != identity['tools'][key]:
                raise ValueError('reference tool differs from manifest: ' + key)
        directory = 'ports' if group == 'legacy' else 'expanded/' + group
        extension = 'rs' if arm == 'rust' else 'zig' if arm.startswith('zig-') else 'go'
        inputs = [directory + '/main.' + extension]
        if group == 'text' and arm == 'rust':
            inputs += [directory + '/Cargo.toml', directory + '/Cargo.lock']
        for source in inputs:
            if saved['identity']['sources'][source] != identity['sources'][source]:
                raise ValueError('reference source differs from manifest: ' + source)
        receipts[name] = {'manifest_path': str(path), 'manifest_sha256': args.expected_reference_manifest_sha256,
                          'binary_path': binary, 'binary_sha256': saved['binary_hashes'][name],
                          'source_hashes': {source: saved['identity']['sources'][source] for source in inputs},
                          'tools': {key: saved['identity']['tools'][key] for key in (tool, *(['cargo'] if group == 'text' and arm == 'rust' else []))},
                          'original_build_command': saved['identity']['actual_build_commands'][name],
                          'provenance': 'Reused hash-verified reference executable; no new compilation claimed.'}
    if set(receipts) != {group + '/' + arm for group in GROUPS for arm in ARMS if not arm.startswith('my-')}:
        raise ValueError('reference manifest has incomplete executable coverage')
    return receipts


def build_environment(identity):
    env = common.runtime_environment()
    for key in list(env):
        if key.startswith(('CARGO_PROFILE_', 'CARGO_TARGET_')) or key in (
                'CARGO_BUILD_TARGET', 'CARGO_BUILD_RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS',
                'RUSTC_WRAPPER', 'RUSTC_WORKSPACE_WRAPPER'):
            env.pop(key)
    return {**env, **identity['private_cache_environment']}


def build(args, binaries, identity):
    manifest = args.work / 'manifest.json'
    if args.skip_build:
        saved = json.loads(manifest.read_text())
        common.verify_identity(saved['identity'], identity)
        common.verify_identity(saved['binary_hashes'], common.artifact_hashes(binaries, args.work))
        return saved['build_logs']
    (args.work / 'bin').mkdir(parents=True, exist_ok=True)
    (args.work / 'tmp').mkdir(exist_ok=True)
    env = build_environment(identity)
    logs = []
    commands = {'clock': identity['actual_clock_build'], **identity['actual_build_commands']}
    for name, command in commands.items():
        print('Building ' + name, flush=True)
        if name in identity['reference_reuse']:
            shutil.copy2(identity['reference_reuse'][name]['binary_path'], binaries[name])
            logs.append({'name': name, 'command': command, 'exit_status': 0, 'stdout': '', 'stderr': '',
                         'reused_reference': identity['reference_reuse'][name]})
            atomic_json(args.work / 'build-log.json', logs)
            continue
        done = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=1800)
        logs.append({'name': name, 'command': command, 'exit_status': done.returncode,
                     'stdout': done.stdout, 'stderr': done.stderr})
        atomic_json(args.work / 'build-log.json', logs)
        if done.returncode:
            raise RuntimeError(f'{name} build failed: {done.stdout}\n{done.stderr}')
        if name in identity['post_build_copies']:
            shutil.copy2(identity['post_build_copies'][name], binaries[name])
        if name != 'clock' and not binaries[name].is_file():
            raise RuntimeError('missing executable: ' + name)
    common.verify_identity(identity, configuration(args)[1])
    atomic_json(manifest, {'identity': identity, 'binary_hashes': common.artifact_hashes(binaries, args.work),
                           'build_logs': logs})
    return logs


def invoke(binaries, case, size, iterations, seed, cpu, arm, rss=False):
    group = inventory()[case]['group']
    result = common.invoke(binaries[group + '/' + arm], case, size, iterations, seed, cpu,
                           checksum(case, size, iterations, seed), rss=rss)
    if rss and result['peak_rss_kib'] <= 0:
        raise RuntimeError('nonpositive RSS: ' + case + '/' + arm)
    return result


def calibrate(args, binaries, plan):
    count, pilots, reason = 31, [], 'target'
    for attempt in range(10):
        rows = {arm: invoke(binaries, plan['case'], plan['size'], count, 42, args.cpu, arm) for arm in ARMS}
        pilots.append({**plan, 'iterations': count, 'arms': rows})
        fastest = min(row['kernel_ns'] for row in rows.values())
        slowest = max(row['kernel_ns'] for row in rows.values())
        if args.quick:
            reason = 'smoke'
            break
        if slowest > args.max_sample_ms * 1e6:
            reason = 'one_iteration_exceeds_budget' if count == 1 else 'slowest_arm_budget'
            if count > 1 and attempt < 9:
                count = max(1, min(count - 1, int(count * args.max_sample_ms * 1e6 / slowest * 0.9)))
                continue
            break
        if fastest >= args.target_ms * 1e6:
            break
        if count >= args.max_iterations:
            reason = 'iteration_cap'
            break
        growth = min(20, args.target_ms * 1e6 / fastest, args.max_sample_ms * 1e6 / slowest)
        if growth < 1.05:
            reason = 'slowest_arm_budget'
            break
        if attempt == 9:
            reason = 'pilot_limit'
            break
        count = min(args.max_iterations, max(count + 1, int(count * growth)))
    calibration = {'fastest_ns': fastest, 'slowest_ns': slowest, 'target_ns': int(args.target_ms * 1e6),
                   'slowest_cap_ns': int(args.max_sample_ms * 1e6), 'iteration_cap': args.max_iterations,
                   'reason': reason, 'limited': not args.quick and fastest < args.target_ms * 1e6,
                   'target_reached': fastest >= args.target_ms * 1e6,
                   'slowest_budget_exceeded': slowest > args.max_sample_ms * 1e6}
    return {**plan, 'iterations': count, 'expected': checksum(plan['case'], plan['size'], count, 42),
            'calibration': calibration}, pilots


def markdown(report):
    lines = ['Expanded runtime benchmark: **' + report['status'] + '**.', '',
             f"{len(report['coverage'])} cases; {report['rounds']} measured rounds; {report['warmup_rounds']} warmups; "
             f"{len(report['samples'])} measured samples across all six configurations.", '',
             report['identity']['target_policy']['policy_note'], '',
             'Times below are **ns per CLI iteration**, not necessarily per element. See the unit column and contracts. '
             'Application and native-library workloads include their documented algorithms. Ratios are medians of paired rounds against Go; '
             '95% intervals use 2,000 bootstrap resamples. No aggregate ranking pools different workloads.', '',
             '| Case / profile | Level | Unit | Arm | Median ns/iteration | Min–max | Ratio to Go | 95% interval |',
             '|---|---|---|---|---:|---:|---:|---:|']
    for row in report['summary']:
        meta = report['inventory'][row['case']]
        lo, hi = row['paired_bootstrap_95_interval']
        lines.append(f"| {row['case']} / {row['profile']} | {meta['level']} | {meta['unit']} | {row['arm']} | "
                     f"{row['median_ns_per_op']:.2f} | {row['min_ns_per_op']:.2f}–{row['max_ns_per_op']:.2f} | "
                     f"{row['median_paired_ratio_to_go']:.3f} | {lo:.3f}–{hi:.3f} |")
    limited = [f"{p['case']}/{p['profile']} ({p['calibration']['reason']})" for p in report['plans'] if p['calibration']['limited']]
    lines += ['', 'Calibration limits: ' + (', '.join(limited) if limited else 'none') + '.', '',
              'Per-core activity: ' + json.dumps(report['environment']['per_core_busy_percent_sampling']) + '.',
              'Governor: ' + str(report['environment']['frequency']['scaling_governor']) + '.',
              report['environment']['warning'], '',
              'Operation inventory coverage does not establish 80% of everyday CPU time. Separate application profiles are required.']
    lines += report['environment']['warnings']
    return '\n'.join(lines) + '\n'


def execute(args):
    started = stamp()
    if args.cpu not in os.sched_getaffinity(0):
        raise ValueError('requested CPU is unavailable')
    args.work.mkdir(parents=True, exist_ok=True)
    binaries, identity = configuration(args)
    logs = build(args, binaries, identity)
    if args.build_only:
        print('PASS all 24 executables built; no baseline measured.', flush=True)
        return
    before_hashes = common.artifact_hashes(binaries, args.work)
    references, frozen_identity = frozen_references()
    qualification = []
    for case in inventory():
        print('Qualifying ' + case, flush=True)
        for size, seed, count in EDGE_PROBES:
            for arm in ARMS:
                qualification.append({'case': case, 'size': size, 'seed': seed, 'iterations': count, 'arm': arm,
                                      **invoke(binaries, case, size, count, seed, args.cpu, arm)})
    selected = args.only or list(inventory())
    plans, pilots, samples, warmups, memory = [], [], [], [], []
    reference_samples, reference_warmups = [], []
    for plan in plans_for(selected):
        print(f"Calibrating {plan['case']}/{plan['profile']}", flush=True)
        calibrated, evidence = calibrate(args, binaries, plan)
        plans.append(calibrated)
        pilots.extend(evidence)
    before_cpu, before_load = common.cpu_snapshot(), os.getloadavg()
    measurement_started = stamp()
    for index, plan in enumerate(plans):
        print(f"Measuring {index + 1}/{len(plans)}: {plan['case']}/{plan['profile']} x{plan['iterations']}", flush=True)
        for rnd in range(-args.warmups, args.rounds):
            order = list(ARMS)
            reference = references[(plan['case'], plan['size'])]
            supplement = before_hashes[reference['name']] != reference['binary_sha256']
            if supplement:
                order.append('frozen-reference')
            random.Random(f"{plan['case']}/{plan['size']}/{rnd}").shuffle(order)
            for arm in order:
                if arm == 'frozen-reference':
                    row = {**plan, 'arm': reference['arm'], 'round': rnd,
                           **common.invoke(Path(reference['binary_path']), plan['case'], plan['size'],
                                           plan['iterations'], 42, args.cpu, plan['expected'])}
                    (reference_warmups if rnd < 0 else reference_samples).append(row)
                    continue
                row = {**plan, 'arm': arm, 'round': rnd,
                       **invoke(binaries, plan['case'], plan['size'], plan['iterations'], 42, args.cpu, arm)}
                (warmups if rnd < 0 else samples).append(row)
        for arm in ARMS:
            memory.append({**plan, 'arm': arm,
                           **invoke(binaries, plan['case'], plan['size'], plan['iterations'], 42, args.cpu, arm, rss=True)})
        # Recovery evidence is explicitly incomplete and never reused for an accepted run.
        atomic_json(args.work / 'progress.json', {'status': 'incomplete', 'completed_plans': index + 1,
                                                  'samples': samples, 'warmups': warmups, 'memory': memory})
    after_cpu, after_load = common.cpu_snapshot(), os.getloadavg()
    after_hashes = common.artifact_hashes(binaries, args.work)
    for reference in references.values():
        if common.digest(reference['binary_path']) != reference['binary_sha256']:
            raise ValueError('frozen reference binary changed during measurement')
    after_identity = configuration(args)[1]
    common.verify_identity(identity, after_identity)
    common.verify_identity(before_hashes, after_hashes)
    environment = {'platform': platform.platform(), 'cpu': args.cpu, 'cpuinfo': Path('/proc/cpuinfo').read_text(),
                   **common.cpu_environment(args.cpu, before_cpu, after_cpu),
                   'loadavg_before': before_load, 'loadavg_after': after_load}
    status = 'smoke' if args.quick else ('complete' if set(selected) == set(inventory()) else 'subset')
    report = {'schema': SCHEMA, 'status': status, 'profile': 'smoke' if args.quick else 'baseline',
              'measurement_session_id': str(uuid.uuid4()), 'timing_lock': str(common.TIMING_LOCK),
              'frozen_reference': {'baseline_path': str(FROZEN_BASELINE), 'baseline_sha256': FROZEN_BASELINE_SHA256,
                                   'original_identity': frozen_identity,
                                   'plans': [{**reference, 'case': case, 'size': size} for (case, size), reference in references.items()
                                             if case in selected]},
              'started_utc': started, 'measurement_started_utc': measurement_started, 'finished_utc': stamp(),
              'coverage': selected, 'inventory': inventory(), 'rounds': args.rounds, 'warmup_rounds': args.warmups,
              'identity': identity, 'identity_after': after_identity, 'binary_hashes': before_hashes,
              'binary_hashes_after': after_hashes, 'build_logs': logs, 'qualification': qualification,
              'plans': plans, 'pilots': pilots, 'samples': samples, 'warmups': warmups, 'memory': memory,
              'frozen_reference_samples': reference_samples, 'frozen_reference_warmups': reference_warmups,
              'environment': environment}
    report['summary'] = common.summarize(report)
    atomic_json(args.output, report)
    args.output.with_suffix('.md').write_text(markdown(report))
    print(f"PASS {status}: {len(samples)} samples; {len(qualification)} qualifications; {args.output}", flush=True)


def arguments():
    p = argparse.ArgumentParser(description=__doc__)
    rustc = shutil.which('rustc') or str(Path.home() / '.cargo/bin/rustc')
    cargo = shutil.which('cargo') or str(Path.home() / '.cargo/bin/cargo')
    for name, default in (('mylang', str(ROOT / 'zig-out/bin/mylang')), ('rustc', rustc), ('go', 'go'),
                          ('zig', 'zig'), ('cc', 'cc'), ('cargo', cargo)):
        p.add_argument('--' + name, default=default)
    p.add_argument('--cpu', type=int, default=2)
    p.add_argument('--candidate-id', required=True)
    p.add_argument('--compiler-receipt', type=Path, required=True)
    p.add_argument('--reuse-reference-manifest', type=Path)
    p.add_argument('--expected-reference-manifest-sha256')
    p.add_argument('--rounds', type=int, default=15)
    p.add_argument('--warmups', type=int, default=3)
    p.add_argument('--target-ms', type=float, default=50)
    p.add_argument('--max-sample-ms', type=float, default=1000)
    p.add_argument('--max-iterations', type=int, default=10000000)
    p.add_argument('--only', nargs='+', choices=inventory())
    p.add_argument('--skip-build', action='store_true')
    p.add_argument('--build-only', action='store_true')
    p.add_argument('--quick', action='store_true')
    p.add_argument('--work', type=Path, default=ROOT / '.mylang-cache/runtime-expanded/runner')
    p.add_argument('--output', type=Path, default=HERE.parent / 'candidates/candidate.json')
    args = p.parse_args()
    if args.rounds < 1 or args.warmups < 0 or not 30 <= args.target_ms <= args.max_sample_ms or args.max_iterations < 31:
        p.error('invalid rounds, warmups, or calibration bounds')
    if args.only and len(set(args.only)) != len(args.only):
        p.error('duplicate case selection')
    if bool(args.reuse_reference_manifest) != bool(args.expected_reference_manifest_sha256):
        p.error('reference reuse requires both manifest and its explicit expected SHA256')
    args.work, args.output = args.work.resolve(), args.output.resolve()
    if args.output.is_relative_to(HERE / 'results'):
        p.error('new candidate output must preserve historical expanded/results evidence')
    return args


if __name__ == '__main__':
    try:
        execute(arguments())
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print('FAILED (no new complete report): ' + str(error), file=sys.stderr)
        sys.exit(1)
