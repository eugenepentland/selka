#!/usr/bin/env python3
"""Measure one frozen microbenchmark cell inside a shared timing lease.

The coordinator invokes this with scripts/build-slot.sh timing; this program
does not acquire another admission lock. Refusals and failed guests remain in
the arm inventory. Counted executions are separate from timing and RSS.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import random
import re
import signal
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[4]
REGISTRY_PATH = ROOT / 'benchmarks/runtime/expanded/registry.py'
module_spec = importlib.util.spec_from_file_location('micro_registry', REGISTRY_PATH)
registry = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(registry)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def runtime_environment():
    env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_')}
    for key in ('GODEBUG', 'RUSTFLAGS', 'CFLAGS', 'CXXFLAGS', 'LDFLAGS', 'LD_PRELOAD'):
        env.pop(key, None)
    env.update(GOMAXPROCS='1', GOGC='100', GOMEMLIMIT='off', GOAMD64='v1',
               GOFLAGS='', GOEXPERIMENT='', GOTOOLCHAIN='local')
    return env


def execute(argv, timeout, env, cwd=None):
    start = time.perf_counter_ns()
    child = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             cwd=cwd, env=env, start_new_session=True)
    try:
        stdout, stderr = child.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        stdout, stderr = child.communicate()
        return {'status': 'timeout', 'argv': argv, 'timeout_seconds': timeout,
                'stdout': stdout.decode(errors='replace'),
                'stderr': stderr.decode(errors='replace')}
    return {'status': 'ok' if child.returncode == 0 else 'failed',
            'argv': argv, 'exit_status': child.returncode,
            'stdout': stdout.decode(errors='replace'),
            'stderr': stderr.decode(errors='replace'),
            'process_wall_ns': time.perf_counter_ns() - start}


def validate(result, expected, protocol):
    if result['status'] != 'ok':
        return result
    if result['stderr']:
        return {**result, 'status': 'unexpected_stderr'}
    if protocol == 'kernel':
        match = re.fullmatch(r'([0-9]+) ([0-9]+)\n', result['stdout'])
        if not match or int(match[1]) != expected or int(match[2]) <= 0:
            return {**result, 'status': 'output_mismatch', 'expected_checksum': expected}
        return {**result, 'checksum': int(match[1]), 'kernel_ns': int(match[2])}
    if result['stdout'] != expected:
        return {**result, 'status': 'output_mismatch', 'expected_stdout': expected}
    return result


def summarize(values):
    return {'median': statistics.median(values), 'min': min(values), 'max': max(values)} if values else None


def counters(path):
    raw = json.loads(Path(path).read_text())
    assert raw['version'] == 'mylang-counters-v1'
    totals, kinds = raw['totals'], raw['kinds']
    metrics = {key: totals[key] for key in
               ('allocs', 'reallocs', 'alloc_bytes', 'realloc_added_bytes',
                'peak_live_bytes', 'live_bytes_at_exit', 'runtime_retains', 'runtime_releases')}
    for key in ('shared_retains', 'shared_releases'):
        metrics[key] = totals.get(key, 0)
    metrics['cumulative_allocated_bytes'] = totals['alloc_bytes'] + totals['realloc_added_bytes']
    for key in ('retain', 'release', 'unique_test', 'release_unique'):
        metrics[key] = kinds[key]['count']
    metrics['rc_events'] = sum(metrics[k] for k in ('retain', 'release', 'runtime_retains',
                                                  'runtime_releases', 'shared_retains', 'shared_releases'))
    metrics['direct_destructions'] = metrics['release_unique']
    return metrics


def cpu_snapshot():
    result = {}
    for line in Path('/proc/stat').read_text().splitlines():
        fields = line.split()
        if fields and re.fullmatch(r'cpu[0-9]+', fields[0]):
            values = list(map(int, fields[1:9]))
            result[fields[0]] = {'total': sum(values), 'idle': values[3] + values[4]}
    return result


def balanced_order(names, round_index, cell):
    """Full n-round blocks put every arm in every position once; alternate direction."""
    offset = int(hashlib.sha256(cell.encode()).hexdigest()[:8], 16) % len(names)
    base = names[offset:] + names[:offset]
    block, shift = divmod(round_index, len(base))
    if block % 2:
        base = list(reversed(base))
    return base[shift:] + base[:shift]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('spec', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--cpu', type=int, default=8)
    parser.add_argument('--timeout', type=float, default=120)
    args = parser.parse_args()
    assert args.cpu in os.sched_getaffinity(0)
    assert not args.output.exists(), 'never overwrite a receipt'
    journal = args.output.with_suffix('.progress.jsonl')
    assert not journal.exists(), 'never reuse an incomplete measurement as a fresh run'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    spec = json.loads(args.spec.read_text())
    names = list(spec['arms'])
    paths = {str(args.spec), __file__, *spec.get('files', [])}
    for entry in list(spec['arms'].values()) + list(spec.get('counted', {}).values()):
        if entry.get('binary'):
            paths.add(entry['binary'])
            assert digest(entry['binary']) == entry['sha256'], entry['binary']
    identities = {p: digest(p) for p in sorted(paths)}
    state = {n: {'status': 'ok'} if v['status'] == 'ok' else v for n, v in spec['arms'].items()}
    document = {'schema': 'text-gap-screen-v1', 'spec': spec, 'started_utc': stamp(),
                'identities': identities, 'cpu': args.cpu, 'timeout_seconds': args.timeout,
                'loadavg_before': os.getloadavg(), 'ordering': 'rotated blocks, reversed every n rounds; full blocks balance positions exactly', 'environment': runtime_environment(),
                'arm_status': state, 'pilots': [], 'warmups': [], 'samples': [], 'rss': [],
                'counted': {}}
    # Record only relevant controlled environment entries; no unrelated credentials.
    document['environment'] = {k: document['environment'][k] for k in
                               ('GOMAXPROCS', 'GOGC', 'GOMEMLIMIT', 'GOAMD64', 'GOFLAGS',
                                'GOEXPERIMENT', 'GOTOOLCHAIN')}
    before_cpu = cpu_snapshot()
    os.sched_setaffinity(0, {args.cpu})

    def checkpoint(kind, value):
        with journal.open('a') as stream:
            stream.write(json.dumps({'kind': kind, **value}) + '\n')

    checkpoint('header', document)

    def expected(iterations):
        return registry.checksum(spec['case'], spec['size'], iterations, spec['seed']) if spec['protocol'] == 'kernel' else spec['expected_stdout']

    def run(name, iterations, rss=False, counted=False):
        entry = spec['counted' if counted else 'arms'][name]
        argv = [entry['binary']]
        if spec['protocol'] == 'kernel':
            argv += [spec['case'], str(spec['size']), str(iterations), str(spec['seed'])]
        else:
            argv += entry.get('args', [])
        want = expected(iterations)
        env = runtime_environment()
        counter_path = args.output.parent / (args.output.stem + '.' + name + '.counters.json')
        if counted:
            assert not counter_path.exists()
            env['MYLANG_COUNTERS'] = str(counter_path.resolve())
        with tempfile.NamedTemporaryFile() as rss_file:
            command = ['/usr/bin/time', '-f', '%M', '-o', rss_file.name, *argv] if rss else argv
            result = validate(execute(command, args.timeout, env, spec.get('cwd')), want, spec['protocol'])
            if result['status'] == 'ok' and rss:
                value = Path(rss_file.name).read_text().strip()
                if not value.isdigit() or int(value) <= 0:
                    result = {**result, 'status': 'invalid_rss', 'rss_output': value}
                else:
                    result['peak_rss_kib'] = int(value)
        if counted and result['status'] == 'ok':
            if not counter_path.exists():
                result = {**result, 'status': 'missing_counters'}
            else:
                result['counter_path'] = str(counter_path)
                result['counter_sha256'] = digest(counter_path)
                result['metrics'] = counters(counter_path)
                if result['metrics']['live_bytes_at_exit'] != 0:
                    result['status'] = 'managed_leak'
                if entry.get('zero_rc') and (result['metrics']['rc_events'] or result['metrics']['unique_test'] or json.loads(counter_path.read_text())['totals'].get('share_marks', 0)):
                    result['status'] = 'unexpected_rc'
        return {'arm': name, 'iterations': iterations, **result}

    def attempt(name, iterations, phase, rnd=None, rss=False):
        if state[name]['status'] != 'ok':
            return None
        result = {**run(name, iterations, rss=rss), 'phase': phase}
        if rnd is not None:
            result['round'] = rnd
        checkpoint(phase, result)
        if result['status'] != 'ok':
            state[name] = result
            return None
        return result

    count = spec.get('screen_iterations', 1)
    if spec['protocol'] == 'kernel' and 'screen_iterations' not in spec:
        count, reason = 31, 'target'
        fastest = slowest = None
        for pilot in range(10):
            results = [v for name in balanced_order(names, pilot, spec['cell'] + '/pilot') if (v := attempt(name, count, 'pilot', pilot))]
            document['pilots'].append({'iterations': count, 'arms': results})
            if not results:
                reason = 'no_admitted_arm'
                break
            fastest = min(v['kernel_ns'] for v in results)
            slowest = max(v['kernel_ns'] for v in results)
            if slowest > spec['max_slowest_kernel_ms'] * 1e6:
                reason = 'one_iteration_exceeds_budget' if count == 1 else 'slowest_arm_budget'
                if count > 1 and pilot < 9:
                    count = max(1, min(count - 1, int(count * spec['max_slowest_kernel_ms'] * 1e6 / slowest * .9)))
                    continue
                break
            if fastest >= spec['target_fastest_kernel_ms'] * 1e6:
                reason = 'target'
                break
            if count >= spec['max_iterations']:
                reason = 'iteration_cap'
                break
            growth = min(20, spec['target_fastest_kernel_ms'] * 1e6 / fastest,
                         spec['max_slowest_kernel_ms'] * 1e6 / slowest)
            if growth < 1.05:
                reason = 'near_target_growth'
                break
            if pilot == 9:
                reason = 'pilot_limit'
                break
            count = min(spec['max_iterations'], max(count + 1, int(count * growth)))
        document['calibration'] = {'iterations': count, 'fastest_ns': fastest, 'slowest_ns': slowest,
                                   'reason': reason, 'limited': fastest is None or fastest < spec['target_fastest_kernel_ms'] * 1e6}
    if 'screen_iterations' in spec:
        document['calibration'] = {'iterations': count, 'reason': 'inherited_fresh_baseline', 'source': spec['screen_iteration_source']}
    document['iterations'] = count
    document['expected'] = expected(count)
    for rnd in range(-spec['warmups'], spec['rounds']):
        order = balanced_order(names, rnd if rnd >= 0 else rnd + spec['warmups'], spec['cell'] + ('/samples' if rnd >= 0 else '/warmups'))
        phase = 'warmups' if rnd < 0 else 'samples'
        for name in order:
            value = attempt(name, count, phase, rnd)
            if value:
                document[phase].append(value)
    for rnd in range(spec['rss_rounds']):
        order = balanced_order(names, rnd, spec['cell'] + '/rss')
        for name in order:
            value = attempt(name, count, 'rss', rnd, rss=True)
            if value:
                document['rss'].append(value)
    # Counting has separate statuses and never invalidates or supplies wall/RSS samples.
    for name, entry in spec.get('counted', {}).items():
        result = run(name, count, counted=True) if entry['status'] == 'ok' else entry
        document['counted'][name] = result
        checkpoint('counted', {'arm': name, **result})
    document['summary'] = {}
    for name in names:
        samples = [v for v in document['samples'] if v['arm'] == name]
        memory = [v['peak_rss_kib'] for v in document['rss'] if v['arm'] == name]
        complete = state[name]['status'] == 'ok' and len(samples) == spec['rounds'] and len(memory) == spec['rss_rounds']
        document['summary'][name] = {'complete': complete, 'status': state[name],
                                     'kernel_ns_per_iteration': summarize([v['kernel_ns'] / count for v in samples]) if complete and spec['protocol'] == 'kernel' else None,
                                     'process_wall_ns': summarize([v['process_wall_ns'] for v in samples]) if complete else None,
                                     'peak_rss_kib': summarize(memory) if complete else None}
    document['identities_after'] = {p: digest(p) for p in sorted(paths)}
    assert identities == document['identities_after'], 'inputs changed during measurement'
    document['cpu_ticks_before'] = before_cpu
    document['cpu_ticks_after'] = cpu_snapshot()
    document['loadavg_after'] = os.getloadavg()
    document['finished_utc'] = stamp()
    args.output.write_text(json.dumps(document, indent=2) + '\n')
    print(spec['cell'], {n: v['complete'] for n, v in document['summary'].items()}, flush=True)


if __name__ == '__main__':
    main()
