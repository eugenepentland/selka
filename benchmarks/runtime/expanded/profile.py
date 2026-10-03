#!/usr/bin/env python3
"""Secondary whole-process CPU sampling against a frozen expanded baseline.

Samples include launch/fixture initialization, kernel, formatting, and teardown.
Explicit runtime/libc rules label known primitive implementation symbols.
Application bodies and unmatched symbols remain unclassified even when their
source uses those primitives. Classification describes sampled hotspots; it
does not measure how well the benchmark inventory represents everyday code.
Counts are unweighted observed fixed-rate cpu-clock samples; perf's frequency mode
can adjust periods, so this is sampling evidence, not cycle time.
"""
import argparse
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import statistics
import subprocess
import sys
import time

from registry import HERE, checksum, inventory
from verify import ARMS, verify
sys.path.insert(0, str(HERE.parent))
from runner import timing_lock

APPLICATIONS = ('word_count', 'csv_aggregate', 'json_transform', 'packet_decode', 'lox_eval')
RULES_PATH = HERE / 'profile_rules.json'
SCRIPT_LINE = re.compile(r'^\s*(?:0x)?([0-9a-fA-F]+)\s+(.+?)\s+\((.*)\)\s*$')
LIBC_DSO = re.compile(r'(?:^|/)libc(?:\.so(?:\.[0-9]+)*|-[0-9.]+\.so)$')
GUEST_LAUNCH = 'exec "$@" >"$PROFILE_GUEST_STDOUT" 2>"$PROFILE_GUEST_STDERR"'
COUNTERS = ('cycles:u', 'instructions:u', 'branches:u', 'branch-misses:u', 'cache-references:u', 'cache-misses:u')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, allow_nan=False) + '\n')
    temporary.replace(path)


def compressed(path, data):
    with gzip.open(path, 'wb') as output:
        output.write(data.encode() if isinstance(data, str) else data)
    return {'path': str(path), 'sha256': digest(path)}


def symbol_base(symbol):
    symbol = re.sub(r'\+0x[0-9a-fA-F]+$', '', symbol)
    return re.sub(r'\.(?:isra|constprop|part|llvm)\.[0-9]+$', '', symbol)


def load_rules(path):
    document = json.loads(Path(path).read_text())
    if document.get('schema') != 'runtime-profile-rules-v1':
        raise ValueError('invalid rules schema')
    ids = set()
    for rule in document['rules']:
        if rule['id'] in ids or rule['scope'] not in ('guest', 'libc'):
            raise ValueError('duplicate/invalid primitive rule')
        ids.add(rule['id'])
        if not rule['pattern'].startswith('^') or not rule['pattern'].endswith('$'):
            raise ValueError('primitive rules must match entire symbols')
        if not rule['microcases'] or any(inventory()[case]['level'] != 'micro' for case in rule['microcases']):
            raise ValueError('primitive rule must link existing microcases')
        rule['compiled'] = re.compile(rule['pattern'])
    return document


def parse_script(text):
    samples = []
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        match = SCRIPT_LINE.fullmatch(line)
        if not match:
            raise ValueError('unrecognized perf sample line: ' + line[:200])
        address, symbol, dso = match.groups()
        samples.append((int(address, 16), symbol, dso))
    return samples


def manifest_symbols(binary):
    path = Path(str(binary) + '.qbe-manifest.json')
    if not path.exists():
        return {}, None
    document = json.loads(path.read_text())
    names = {row['symbol']: row['name'] for row in document.get('functions', [])
             if isinstance(row.get('symbol'), str) and isinstance(row.get('name'), str)}
    return names, {'path': str(path), 'sha256': digest(path), 'mapped_function_count': len(names)}


def classify(samples, binary, rules, names, min_samples=200):
    grouped = Counter((symbol, dso) for _, symbol, dso in samples)
    rows, primitive_samples = [], 0
    for (symbol, dso), count in grouped.most_common():
        base = symbol_base(symbol)
        scope = 'guest' if dso in (str(binary), Path(binary).name) else 'libc' if LIBC_DSO.search(dso) else None
        matched = [rule for rule in rules['rules'] if rule['scope'] == scope and rule['compiled'].fullmatch(base)]
        rule_ids = [rule['id'] for rule in matched]
        cases = sorted({case for rule in matched for case in rule['microcases']})
        if matched:
            primitive_samples += count
        rows.append({'dso': dso, 'symbol': symbol, 'source_name': names.get(base),
                     'samples': count, 'classification': 'primitive' if matched else 'unclassified',
                     'primitive_rules': rule_ids, 'microcases': cases})
    total = len(samples)
    fraction = primitive_samples / total if total else 0.0
    return {'total_samples': total, 'primitive_samples': primitive_samples,
            'unclassified_samples': total - primitive_samples, 'primitive_sample_fraction': fraction,
            'sample_denominator': 'all captured user CPU-clock samples, including whole-process startup/teardown',
            'symbol_groups': rows, 'low_sample_count': total < min_samples}


def scale_iterations(plan, rows, seconds, maximum):
    durations = [row['kernel_ns'] for row in rows]
    if not durations or any(type(value) not in (int, float) or not math.isfinite(value) or value <= 0 for value in durations):
        raise ValueError('missing/nonpositive baseline durations')
    median = statistics.median(durations)
    wanted = max(1, math.ceil(seconds * 1e9 * plan['iterations'] / median))
    count = min(maximum, wanted)
    return count, {'baseline_median_kernel_ns': median, 'baseline_iterations': plan['iterations'],
                   'target_seconds': seconds, 'estimated_kernel_seconds': count * median / plan['iterations'] / 1e9,
                   'iteration_cap': maximum, 'iteration_cap_limited': wanted > maximum}


def run_command(command, timeout, environment=None):
    """A timeout terminates the entire perf/guest process group."""
    process = subprocess.Popen(command, env=environment, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def guest_environment():
    environment = {key: value for key, value in os.environ.items() if not key.startswith('MYLANG_')}
    for key in ('GODEBUG', 'GOEXPERIMENT', 'MYLANG_OPTIONS', 'MYLANG_GC_STRESS', 'MYLANG_GC_STEP', 'MYLANG_STRESS', 'MYLANG_STEPS', 'RUSTFLAGS', 'CFLAGS', 'CXXFLAGS', 'RUSTC_BOOTSTRAP', 'CGO_CFLAGS', 'CGO_CPPFLAGS', 'CGO_CXXFLAGS', 'CGO_LDFLAGS', 'LDFLAGS'):
        environment.pop(key, None)
    environment.update(GOMAXPROCS='1', GOGC='100', GOMEMLIMIT='off', GOAMD64='v1', GOFLAGS='', GOEXPERIMENT='', GOTOOLCHAIN='local')
    return environment


def validate_guest(stdout, stderr, status, expected):
    if status != 0 or stderr:
        raise ValueError(f'guest/perf status={status}, guest stderr={stderr!r}')
    match = re.fullmatch(r'([0-9]+) ([0-9]+)\n', stdout)
    if not match or int(match[1]) != expected or int(match[2]) <= 0:
        raise ValueError('invalid guest output/checksum: ' + repr(stdout))
    return {'checksum': int(match[1]), 'kernel_ns': int(match[2]), 'exit_status': status}


def capture(perf, binary, plan, arm, baseline_rows, directory, args, rules):
    count, calibration = scale_iterations(plan, baseline_rows, args.seconds, args.max_iterations)
    expected = checksum(plan['case'], plan['size'], count, plan['seed'])
    directory.mkdir(parents=True, exist_ok=True)
    stdout_path, stderr_path, perf_path = (directory / name for name in ('guest.stdout', 'guest.stderr', 'perf.data'))
    command = [perf, 'record', '-e', 'cpu-clock:u', '-F', str(args.frequency_hz), '-o', str(perf_path), '--',
               'taskset', '-c', str(args.cpu), '/bin/sh', '-c', GUEST_LAUNCH, 'profile-guest',
               str(binary), plan['case'], str(plan['size']), str(count), str(plan['seed'])]
    environment = guest_environment()
    environment.update(PROFILE_GUEST_STDOUT=str(stdout_path), PROFILE_GUEST_STDERR=str(stderr_path))
    with timing_lock():
        started = time.perf_counter_ns()
        done = run_command(command, args.timeout_seconds, environment)
        wall = time.perf_counter_ns() - started
    diagnostics = {'record_stdout': done.stdout, 'record_stderr': done.stderr, 'record_exit_status': done.returncode}
    atomic_json(directory / 'perf-diagnostics.json', diagnostics)
    result = validate_guest(stdout_path.read_text(), stderr_path.read_text(), done.returncode, expected)
    script_command = [perf, 'script', '-i', str(perf_path), '-F', 'ip,sym,dso']
    script = run_command(script_command, args.timeout_seconds)
    dump_command = [perf, 'script', '-D', '-i', str(perf_path)]
    dump = run_command(dump_command, args.timeout_seconds)
    diagnostics.update(script_stderr=script.stderr, script_exit_status=script.returncode,
                       dump_stderr=dump.stderr, dump_exit_status=dump.returncode)
    atomic_json(directory / 'perf-diagnostics.json', diagnostics)
    if script.returncode or dump.returncode:
        raise ValueError('perf script decoding failed')
    raw_script = compressed(directory / 'samples.txt.gz', script.stdout)
    raw_records = compressed(directory / 'records.txt.gz', dump.stdout)
    samples = parse_script(script.stdout)
    names, manifest = manifest_symbols(binary)
    grouped = classify(samples, binary, rules, names, args.min_samples)
    lost = len(re.findall(r'\bPERF_RECORD_LOST(?:_SAMPLES)?\b', dump.stdout))
    throttled = len(re.findall(r'\bPERF_RECORD_THROTTLE\b', dump.stdout))
    warnings = []
    if grouped['low_sample_count']:
        warnings.append(f'low sample count: {len(samples)} < {args.min_samples}')
    if lost:
        warnings.append(f'raw trace contains {lost} lost-event records; captured samples cannot represent missing events')
    if throttled:
        warnings.append(f'raw trace contains {throttled} throttle records; requested sampling frequency was not maintained')
    if calibration['iteration_cap_limited']:
        warnings.append('iteration cap prevented requested kernel duration')
    calibration['observed_kernel_seconds'] = result['kernel_ns'] / 1e9
    calibration['observed_target_reached'] = result['kernel_ns'] >= args.seconds * 1e9
    if not calibration['observed_target_reached']:
        warnings.append('observed instrumented kernel duration did not reach requested target')
    if diagnostics['record_stderr'].strip() or script.stderr.strip() or dump.stderr.strip():
        # Normal perf informational output remains in diagnostics; specific loss
        # or throttle notices also flag compromised sampling quality.
        combined = '\n'.join((done.stderr, script.stderr, dump.stderr))
        if re.search(r'\b(?:lost|throttl\w*)\b', combined, re.I):
            warnings.append('perf diagnostics mention loss/throttling; inspect diagnostics')
    quality_problem = grouped['low_sample_count'] or lost or throttled or any('loss/throttling' in warning for warning in warnings)
    grouped['sampling_quality_ok'] = not bool(quality_problem)
    raw_perf = compressed(directory / 'perf.data.gz', perf_path.read_bytes())
    perf_path.unlink()
    hardware = capture_counters(perf, binary, plan, count, expected, directory, args, environment)
    return {'case': plan['case'], 'arm': arm, 'group': plan['group'], 'profile': plan['profile'], 'size': plan['size'],
            'seed': plan['seed'], 'iterations': count, 'status': 'complete', **result, 'process_wall_ns': wall,
            'calibration': calibration, 'record_command': command, 'script_command': script_command, 'dump_command': dump_command,
            'binary_sha256': digest(binary), 'manifest': manifest, 'raw_script': raw_script,
            'raw_records': raw_records, 'raw_perf': raw_perf, 'perf_diagnostics': diagnostics,
            'hardware_counters': hardware, 'warnings': warnings, **grouped}


def parse_counters(text):
    """Perf stat CSV counts are whole-process user-mode evidence, never kernel-only."""
    result = {}
    for line in text.splitlines():
        fields = line.split('\t')
        if len(fields) < 3 or fields[2] not in COUNTERS:
            continue
        count = fields[0].strip()
        available = re.fullmatch(r'[0-9]+(?:\.[0-9]+)?', count) is not None
        result[fields[2]] = {'available': available, 'count': float(count) if available else None,
                            'raw_count': count, 'raw_fields': fields}
    return result


def capture_counters(perf, binary, plan, count, expected, directory, args, environment):
    output = directory / 'counters.tsv'
    stdout_path, stderr_path = directory / 'counters-guest.stdout', directory / 'counters-guest.stderr'
    stdout_path.unlink(missing_ok=True)
    stderr_path.unlink(missing_ok=True)
    counter_env = {**environment, 'PROFILE_GUEST_STDOUT': str(stdout_path), 'PROFILE_GUEST_STDERR': str(stderr_path)}
    command = [perf, 'stat', '-x', '\t', '-o', str(output), '-e', ','.join(COUNTERS), '--',
               'taskset', '-c', str(args.cpu), '/bin/sh', '-c', GUEST_LAUNCH, 'profile-counters',
               str(binary), plan['case'], str(plan['size']), str(count), str(plan['seed'])]
    with timing_lock():
        done = run_command(command, args.timeout_seconds, counter_env)
    raw = output.read_text() if output.exists() else ''
    counters = parse_counters(raw)
    available = done.returncode == 0 and set(counters) == set(COUNTERS) and all(row['available'] for row in counters.values())
    guest = validate_guest(stdout_path.read_text(), stderr_path.read_text(), done.returncode, expected) if stdout_path.exists() else None
    return {'status': 'available' if available else 'unavailable_or_partial', 'command': command,
            'exit_status': done.returncode, 'stderr': done.stderr, 'stdout': done.stdout,
            'counts': counters, 'raw': compressed(directory / 'counters.tsv.gz', raw), 'guest': guest,
            'scope': 'Separate instrumented whole-process user-mode counters, including setup/teardown; not benchmark timing or kernel-only counts.'}


def artifact_snapshot(baseline, rules_path, perf):
    verify(baseline, artifacts=True, focused=True)
    paths = {str(Path(__file__).resolve()), str(Path(rules_path).resolve()), str(Path(perf).resolve())}
    for binary in baseline['identity']['binary_paths'].values():
        manifest = Path(binary + '.qbe-manifest.json')
        if manifest.exists():
            paths.add(str(manifest))
    return {path: digest(path) for path in sorted(paths)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--arms', nargs='+', choices=ARMS, default=list(ARMS))
    parser.add_argument('--cases', nargs='+', choices=inventory(), default=list(APPLICATIONS))
    parser.add_argument('--profiles', nargs='+', choices=('small', 'large'), default=['large'])
    parser.add_argument('--cpu', type=int, default=2)
    parser.add_argument('--seconds', type=float, default=4.0)
    parser.add_argument('--frequency-hz', type=int, default=99)
    parser.add_argument('--timeout-seconds', type=float, default=10.0)
    parser.add_argument('--max-iterations', type=int, default=10000000)
    parser.add_argument('--min-samples', type=int, default=200)
    parser.add_argument('--rules', type=Path, default=RULES_PATH)
    parser.add_argument('--perf', default='perf')
    args = parser.parse_args()
    if (not math.isfinite(args.seconds) or not math.isfinite(args.timeout_seconds) or
            args.seconds <= 0 or args.timeout_seconds <= args.seconds or not 1 <= args.max_iterations <= 10000000
            or args.min_samples < 1 or not 1 <= args.frequency_hz <= 999):
        parser.error('invalid profiling duration/count limits')
    if any(len(set(values)) != len(values) for values in (args.arms, args.cases, args.profiles)):
        parser.error('duplicate arms/cases')
    try:
        if args.cpu not in os.sched_getaffinity(0):
            raise ValueError('requested CPU unavailable')
        args.baseline = args.baseline.resolve()
        args.output_dir = args.output_dir.resolve()
        baseline_bytes = args.baseline.read_bytes()
        baseline = json.loads(baseline_bytes)
        perf = shutil.which(args.perf)
        if not perf:
            raise ValueError('perf executable missing')
        rules = load_rules(args.rules)
        before = artifact_snapshot(baseline, args.rules, perf)
        preflight_command = [perf, 'stat', '-e', 'cpu-clock:u', '--', 'taskset', '-c', str(args.cpu), '/bin/true']
        with timing_lock():
            preflight = run_command(preflight_command, 10)
        if preflight.returncode:
            raise ValueError('perf CPU-clock preflight failed: ' + preflight.stderr)
        report = {'schema': 'mylang-runtime-profile-v3', 'purpose': 'hotspot diagnostics', 'status': 'incomplete',
                  'scope': 'selected_diagnostics',
                  'baseline': str(args.baseline), 'baseline_sha256': hashlib.sha256(baseline_bytes).hexdigest(),
                  'baseline_identity': baseline['identity'], 'baseline_binary_hashes': baseline['binary_hashes'],
                  'artifacts_before': before, 'arms': args.arms, 'cases': args.cases, 'profiles_requested': args.profiles,
                  'sampling': {'event': 'cpu-clock:u', 'frequency_hz': args.frequency_hz, 'cpu': args.cpu, 'count_weight': 1,
                               'min_samples': args.min_samples, 'target_seconds': args.seconds, 'timeout_seconds': args.timeout_seconds,
                               'scope': 'whole process including taskset/exec launcher, fixtures, formatting, teardown, and runtime threads',
                               'caveat': 'Unweighted captured CPU-clock samples are fixed-rate sampling evidence; frequency mode can adjust periods. They are not cycles or kernel-only timings.'},
                  'runtime_environment': {key: guest_environment().get(key) for key in ('GOMAXPROCS', 'GOGC', 'GOMEMLIMIT', 'GOAMD64', 'GOFLAGS', 'GOEXPERIMENT', 'GOTOOLCHAIN', 'RUSTFLAGS', 'CFLAGS', 'CXXFLAGS', 'RUSTC_BOOTSTRAP', 'CGO_CFLAGS', 'CGO_CPPFLAGS', 'CGO_CXXFLAGS', 'CGO_LDFLAGS', 'LDFLAGS')},
                  'removed_runtime_environment_prefix': 'MYLANG_',
                  'rules_sha256': digest(args.rules), 'rule_policy': rules['policy'],
                  'started_utc': datetime.now(timezone.utc).isoformat(), 'preflight': {'command': preflight_command, 'stderr': preflight.stderr},
                  'profiles': []}
        output = args.output_dir / 'profiles.json'
        atomic_json(output, report)
        for case in args.cases:
            for profile in args.profiles:
                selected_plans = [plan for plan in baseline['plans'] if plan['case'] == case and plan['profile'] == profile]
                if len(selected_plans) != 1:
                    raise ValueError('missing/duplicate diagnostic plan: ' + case + '/' + profile)
                plan = selected_plans[0]
                for arm in args.arms:
                    print(f'Profiling {case}/{profile}/{arm}', flush=True)
                    binary = Path(baseline['identity']['binary_paths'][plan['group'] + '/' + arm])
                    rows = [row for row in baseline['samples'] if row['case'] == case and row['size'] == plan['size'] and row['arm'] == arm]
                    try:
                        result = capture(perf, binary, plan, arm, rows, args.output_dir / (case + '-' + profile + '-' + arm), args, rules)
                    except (ValueError, OSError, subprocess.TimeoutExpired) as error:
                        result = {'case': case, 'arm': arm, 'profile': profile, 'status': 'failed', 'error': str(error)}
                    report['profiles'].append(result)
                    atomic_json(output, report)
        after = artifact_snapshot(baseline, args.rules, perf)
        if before != after or args.baseline.read_bytes() != baseline_bytes:
            raise ValueError('profiling artifacts/baseline changed during sampling')
        report['artifacts_after'] = after
        report['baseline_identity_after'] = baseline['identity']
        report['baseline_binary_hashes_after'] = baseline['binary_hashes']
        report['finished_utc'] = datetime.now(timezone.utc).isoformat()
        report['status'] = 'complete' if all(row['status'] == 'complete' for row in report['profiles']) else 'failed'
        atomic_json(output, report)
        print(f'{report["status"]}: {len(report["profiles"])} hotspot diagnostic profiles')
        return 0 if report['status'] == 'complete' else 1
    except (ValueError, OSError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
