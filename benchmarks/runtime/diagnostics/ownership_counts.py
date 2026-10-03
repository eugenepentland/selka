#!/usr/bin/env python3
"""Whole-process ownership diagnostics; instrumented times are never compared."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from build_compiler import digest, validate_receipt
from runner import runtime_environment
from backend_receipts import capture as backend_receipts
sys.path.insert(0, str(HERE / 'expanded'))
from registry import GROUPS, checksum, inventory, plans_for

EVENTS = ('owner_acquire', 'owner_release', 'hold_acquire', 'hold_release',
          'owner_limit', 'hold_limit', 'heap_allocate', 'arena_allocate',
          'retire', 'clone_shell', 'unique_check')


def validate(done, expected):
    if done.returncode:
        raise ValueError('counting guest failed: ' + done.stderr)
    output = re.fullmatch(r'([0-9]+) ([0-9]+)\n', done.stdout)
    if not output or int(output[1]) != expected or int(output[2]) <= 0:
        raise ValueError('counting checksum or output mismatch')
    prefix = 'MYLANG_RC_COUNTS '
    if not done.stderr.startswith(prefix) or done.stderr.count('\n') != 1:
        raise ValueError('missing, repeated or contaminated counting record')
    counts = json.loads(done.stderr[len(prefix):])
    if set(counts) != {'version', 'runtime', 'saturated', *EVENTS}:
        raise ValueError('unexpected counting schema')
    if counts['version'] != 1 or counts['runtime'] != 'rc-v5-counting' or counts['saturated'] is not False:
        raise ValueError('unsupported or saturated counting artifact')
    if any(type(counts[key]) is not int or not 0 <= counts[key] < 2**64 for key in EVENTS):
        raise ValueError('invalid event count')
    return {'checksum': expected, 'events': {key: counts[key] for key in EVENTS}}


def atomic(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler-receipt', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--iterations', type=int, default=8)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    if args.iterations < 1 or not 1 <= args.seed <= 1000000:
        parser.error('invalid iteration count or seed')
    work = args.work.resolve()
    (work / 'bin').mkdir(parents=True, exist_ok=True)
    (work / 'tmp').mkdir(exist_ok=True)
    receipt = json.loads(args.compiler_receipt.read_text())
    compiler = Path(receipt['compiler_path'])
    validate_receipt(receipt, compiler, artifacts=True)
    qbe = Path(receipt['source_root']) / 'zig-out/bin/qbe'
    wrapper = ROOT / 'scripts/build-slot.sh'
    sources = {group: HERE / 'ports/main.my' if group == 'legacy'
               else HERE / 'expanded' / group / 'main.my' for group in GROUPS}
    paths = [*sources.values(), HERE / 'ports/native_clock.c', Path(__file__),
             Path(__file__).with_name('backend_receipts.py'),
             HERE / 'expanded/registry.py', HERE / 'oracle.py',
             *(HERE / 'expanded' / group / 'oracle.py' for group in GROUPS if group != 'legacy')]
    identity = {'source_revision': receipt['source_revision'], 'compiler_receipt': receipt,
                'compiler_receipt_sha256': digest(args.compiler_receipt),
                'qbe_sha256': digest(qbe), 'wrapper_sha256': digest(wrapper),
                'inputs': {str(path): digest(path) for path in paths},
                'instrumentation': 'rc-v5-counting', 'guest_mode': 'ReleaseFast'}
    environment = {**runtime_environment(), 'TMPDIR': str(work / 'tmp'),
                   'ZIG_LOCAL_CACHE_DIR': str(work / 'zig-local'),
                   'ZIG_GLOBAL_CACHE_DIR': str(work / 'zig-global')}
    clock = work / 'native_clock.o'
    binaries = {group + '/' + arm: work / 'bin' / (group + '-' + arm)
                for group in GROUPS for arm in ('my-llvm', 'my-qbe')}
    commands = {'clock': [str(wrapper), 'build', 'cc', '-O2', '-c',
                          str(HERE / 'ports/native_clock.c'), '-o', str(clock)]}
    for name, binary in binaries.items():
        group, arm = name.split('/')
        command = [str(wrapper), 'build', str(compiler), 'build', str(sources[group]),
                   '-o', str(binary), '--cache-dir', str(work / 'guest-cache'),
                   '--link', str(clock), '--zig', receipt['zig']['path'], '--qbe', str(qbe),
                   '--mode', 'ReleaseFast', '--backend', 'llvm' if arm == 'my-llvm' else 'qbe',
                   '--rc-runtime=stats', '--keep-symbols']
        if arm == 'my-llvm':
            command += ['--llvm-opt', '3', '--lto']
        commands[name] = command
    identity['build_commands'] = commands
    manifest_path = work / 'manifest.json'
    logs = []
    if args.skip_build:
        saved = json.loads(manifest_path.read_text())
        if saved['identity'] != identity:
            raise ValueError('changed counting build identity')
        if saved['binary_hashes'] != {key: digest(path) for key, path in binaries.items()}:
            raise ValueError('changed counting guest bytes')
        if saved['native_clock_sha256'] != digest(clock):
            raise ValueError('changed counting clock object')
        if saved['effective_backends'] != backend_receipts(binaries):
            raise ValueError('changed counting backend artifacts')
        logs = saved['build_logs']
    else:
        for name, command in commands.items():
            print('Building counting ' + name, flush=True)
            done = subprocess.run(command, cwd=ROOT, env=environment, text=True,
                                  capture_output=True, timeout=1800)
            logs.append({'name': name, 'command': command, 'exit_status': done.returncode,
                         'stdout': done.stdout, 'stderr': done.stderr})
            atomic(work / 'build-log.json', logs)
            if done.returncode:
                raise RuntimeError('counting build failed: ' + name + ': ' + done.stderr)
        atomic(manifest_path, {'identity': identity, 'build_logs': logs,
                              'binary_hashes': {key: digest(path) for key, path in binaries.items()},
                              'native_clock_sha256': digest(clock),
                              'effective_backends': backend_receipts(binaries)})
    cpus = sorted(os.sched_getaffinity(0) - {2, 3, 10, 11})
    if not cpus:
        raise ValueError('no CPU remains after reserving timing CPUs')
    affinity = ','.join(map(str, cpus))
    started = datetime.now(timezone.utc).isoformat()
    hashes = {key: digest(path) for key, path in binaries.items()}
    clock_hash = digest(clock)
    backends = backend_receipts(binaries)
    rows = []
    for plan in plans_for(list(inventory())):
        case, size = plan['case'], plan['size']
        expected = checksum(case, size, args.iterations, args.seed)
        for arm in ('my-llvm', 'my-qbe'):
            binary = binaries[plan['group'] + '/' + arm]
            # Guest diagnostics use no compiler slot and stay off timing CPUs.
            command = ['taskset', '-c', affinity, str(binary), case, str(size),
                       str(args.iterations), str(args.seed)]
            done = subprocess.run(command, env=environment, text=True, capture_output=True, timeout=180)
            rows.append({**plan, 'seed': args.seed, 'iterations': args.iterations, 'arm': arm,
                         'command': command, **validate(done, expected)})
    validate_receipt(receipt, compiler, artifacts=True)
    if hashes != {key: digest(path) for key, path in binaries.items()}:
        raise ValueError('counting binary changed during collection')
    if clock_hash != digest(clock) or backends != backend_receipts(binaries):
        raise ValueError('counting clock or backend artifacts changed during collection')
    if identity['inputs'] != {str(path): digest(path) for path in paths}:
        raise ValueError('diagnostic inputs changed during collection')
    atomic(args.output, {'schema': 'runtime-ownership-diagnostic-v1', 'status': 'complete',
                        'started_utc': started, 'finished_utc': datetime.now(timezone.utc).isoformat(),
                        'identity': identity, 'binary_hashes': hashes, 'build_logs': logs, 'rows': rows,
                        'native_clock_sha256': clock_hash, 'effective_backends': backends,
                        'limits': ['Whole-process counts include setup and teardown, not only the timed kernel.',
                                   'Counting instrumentation can disable ordinary optimization paths.',
                                   'Counts are evidence about these counting artifacts, not production timing.',
                                   'The guest clock value is validated but intentionally not retained.']})
    print(f'PASS {len(rows)} checksum-verified ownership records: {args.output}')


if __name__ == '__main__':
    main()
