#!/usr/bin/env python3
"""Profile qualified current SVG binaries and measure isolated audit probes."""
import argparse
import bisect
from collections import Counter
import gzip
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/svg-gap-audit-20260921'
CURRENT = ROOT / '.tmp/svg-arenas-20260921'
BASE = ROOT / '.tmp/full-svg-benchmark-20260921'
CASES = ('fixture', 'changed-net', 'changed-value')
DOCS = ('lib/modules/straps-synth-lmx2595.sexp', 'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
REFS = json.loads((ROOT / 'experiments/full-svg-benchmark/qualification.json').read_text())['cases']
CPU = 6
SEED = 20260923
RETAINED = {name: CURRENT / name for name in ('gc-o3', 'gc-lto', 'gc-lto-bounded', 'arena-lto')}
RETAINED.update({name: BASE / name for name in ('rust-o3', 'go-fast', 'zig-o3')})
RETAINED['combined-typed'] = WORK / 'host/aggregate-inline-typed-host'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def invoke(binary, case='fixture', bounded=False, native=False, extra=(), env_extra=None,
           diagnostic=False, input_override=None):
    project = BASE / 'projects' / case
    output, issue = WORK / 'result.svg', WORK / 'result.issue'
    output.write_bytes(b''); issue.write_bytes(b'')
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('MYLANG_') or key in ('LD_PRELOAD', 'GOGC', 'GOMEMLIMIT', 'GODEBUG', 'GOMAXPROCS', 'NETLISP_LIB_DIR', 'NETLISP_STDLIB_DIR'):
            del env[key]
    env['MYLANG_MEMORY_LIMIT'] = '268435456'
    docs = [str(project / path) for path in DOCS]
    if input_override:
        docs[0] = str(input_override)
    command = ['taskset', '-c', str(CPU), str(binary)]
    if native:
        command += [*docs, str(output)]
    else:
        env.update(MYLANG_SCHEMATIC_DECLARED='io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue',
                   MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
        env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': path for i, path in enumerate(docs)})
        command += ['--print-result']
        if bounded:
            command += ['--max-steps=100000000']
    command += list(extra)
    env.update(env_extra or {})
    if 'LD_PRELOAD' in env:
        # Preload only the target, not taskset: an inherited CPU timer can fire
        # after exec resets signal handlers and before the target constructor.
        assignments = [f'{key}={env.pop(key)}' for key in ('LD_PRELOAD', 'MYLANG_AUDIT_SAMPLES') if key in env]
        command[3:3] = ['/usr/bin/env', *assignments]
    started = time.perf_counter_ns()
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=90)
    elapsed = (time.perf_counter_ns() - started) / 1e6
    assert result.returncode == 0 and result.stdout == (b'' if native else b'0\n'), (binary, case, result)
    assert not issue.read_bytes(), (binary, issue.read_bytes())
    if not diagnostic:
        assert not result.stderr, (binary, result.stderr)
    if not input_override:
        assert sha(output) == REFS[case]['mylang-o3']['svg_sha256'], (binary, case)
    return elapsed, result.stderr.decode(), sha(output)


def sample(count, combined=False):
    library = WORK / 'sample.so'
    source = ROOT / 'experiments/svg-slowdown-20260921/sample.c'
    subprocess.run(['cc', '-shared', '-fPIC', '-O2', str(source), '-o', str(library), '-ldl'], check=True)
    names = ['combined-typed'] if combined else ['gc-o3', 'gc-lto', 'gc-lto-bounded', 'arena-lto']
    hashes = {name: sha(RETAINED[name]) for name in names}
    for name in names:
        (WORK / f'samples-{name}.txt').write_text('')
    rng = random.Random(SEED)
    for number in range(count):
        rng.shuffle(names)
        for name in names:
            invoke(RETAINED[name], bounded=name.endswith('bounded'), env_extra={
                'LD_PRELOAD': str(library), 'MYLANG_AUDIT_SAMPLES': str(WORK / f'samples-{name}.txt')})
        if (number + 1) % 200 == 0:
            print(f'{number + 1} sampled runs per binary', flush=True)
    summaries = {}
    for name in names:
        assert sha(RETAINED[name]) == hashes[name]
        manifest_path = (WORK / 'codegen/gc-lto-none-aggregate-inline.qbe-manifest.json' if name == 'combined-typed'
                         else Path(str(RETAINED[name]) + '.qbe-manifest.json'))
        manifest = json.loads(manifest_path.read_text())
        friendly = {f['symbol']: f['name'] for f in manifest['functions']}
        symbols = []
        for line in subprocess.check_output(['nm', '-n', '-S', '--defined-only', str(RETAINED[name])], text=True).splitlines():
            fields = line.split()
            if len(fields) == 4 and fields[2] in ('t', 'T'):
                symbols.append((int(fields[0], 16), int(fields[1], 16), fields[3]))
        addresses = [item[0] for item in symbols]
        totals, pcs = Counter(), Counter()
        outside = overflow = runs = samples = unmapped = 0
        raw = (WORK / f'samples-{name}.txt').read_text()
        with gzip.open(OUT / f'samples-{name}.txt.gz', 'wt') as stream:
            stream.write(raw)
        for line in raw.splitlines():
            fields = line.split()
            if fields[0] == 'run':
                runs += 1
                samples += int(fields[3]); outside += int(fields[5]); overflow += int(fields[7])
                continue
            pc, hits = int(fields[0], 16), int(fields[1])
            pcs[pc] += hits
            index = bisect.bisect_right(addresses, pc) - 1
            if index < 0 or pc >= symbols[index][0] + symbols[index][1]:
                unmapped += hits
            else:
                symbol = symbols[index][2]
                totals[friendly.get(symbol, symbol)] += hits
        assert overflow == 0 and samples > 0
        summaries[name] = {'binary_sha256': hashes[name], 'runs': runs, 'samples': samples,
                           'outside_main_executable': outside, 'unmapped_inside': unmapped,
                           'functions': [{'name': function, 'samples': hits, 'percent_all_samples': hits * 100 / samples}
                                         for function, hits in totals.most_common()],
                           'top_pcs': [{'address': hex(pc), 'samples': hits} for pc, hits in pcs.most_common(30)]}
    result = {'method': 'Unmodified binaries with LD_PRELOAD SIGPROF CPU-time sampling; requested 500us, kernel tick limited; self-PC only, no stack attribution or hardware cycles. Actual counts include outside/unmapped samples. Every output hash checked. No wall-time claims from profiled runs.',
              'sampler_source_sha256': sha(source), 'sampler_sha256': sha(library), 'summary': summaries}
    (OUT / ('sampling-combined.json' if combined else 'sampling.json')).write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({name: {'samples': d['samples'], 'functions': d['functions'][:12]} for name, d in summaries.items()}, indent=2))


def percentile(values, fraction):
    values = sorted(values)
    point = (len(values) - 1) * fraction
    lower = int(point); upper = min(lower + 1, len(values) - 1)
    return values[lower] + (values[upper] - values[lower]) * (point - lower)


def measure(manifest_path):
    config = json.loads(Path(manifest_path).read_text())
    arms = config['arms']
    qualification = {}
    for name, arm in arms.items():
        binary = ROOT / arm['binary']
        assert sha(binary) == arm['sha256'], name
        results = {case: invoke(binary, case, bounded=arm.get('bounded', False), native=arm.get('native', False))[2] for case in CASES}
        if not arm.get('native') and arm.get('stress', True):
            invoke(binary, extra=('--gc-stress',), bounded=arm.get('bounded', False))
        qualification[name] = {'binary_sha256': sha(binary), 'svg_sha256': results,
                               'gc_stress': not arm.get('native') and arm.get('stress', True)}
    rng = random.Random(SEED)
    rows = []
    for number in range(-3, 31):
        jobs = [(name, case) for name in arms for case in CASES]
        rng.shuffle(jobs)
        values = {case: {} for case in CASES}
        for name, case in jobs:
            arm = arms[name]
            values[case][name] = invoke(ROOT / arm['binary'], case,
                                      bounded=arm.get('bounded', False), native=arm.get('native', False))[0]
        if number >= 0:
            rows.append({'round': number, 'order': jobs, 'ms': values})
    summary = {}
    for case in CASES:
        medians = {name: statistics.median(row['ms'][case][name] for row in rows) for name in arms}
        comparisons = {}
        for numerator, denominator in config['pairs']:
            bootstrap = []
            for _ in range(4000):
                sample_rows = rng.choices(rows, k=len(rows))
                bootstrap.append(statistics.median(row['ms'][case][numerator] for row in sample_rows) /
                                 statistics.median(row['ms'][case][denominator] for row in sample_rows))
            comparisons[f'{numerator}/{denominator}'] = {'ratio': medians[numerator] / medians[denominator],
                'paired_bootstrap_95': [percentile(bootstrap, .025), percentile(bootstrap, .975)]}
        summary[case] = {'median_ms': medians, 'comparisons': comparisons}
    for name, arm in arms.items():
        assert sha(ROOT / arm['binary']) == arm['sha256'], name
    output = OUT / config.get('output', 'measurements.json')
    output.write_text(json.dumps({'method': 'Fresh process through complete SVG file output and shutdown; compilation, preparation and verification excluded. All outputs checked. Randomized interleaved same-CPU runs.',
                                 'cpu': CPU, 'seed': SEED, 'rounds': 31, 'warmups': 3, 'mylang_memory_limit_bytes': 268435456,
                                 'timed_runs': len(rows) * len(arms) * len(CASES), 'arms': arms, 'qualification': qualification,
                                 'summary': summary, 'samples': rows}, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('sample', 'measure'))
    parser.add_argument('--count', type=int, default=1200)
    parser.add_argument('--combined', action='store_true')
    parser.add_argument('--manifest', default=str(OUT / 'arms.json'))
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    if args.action == 'sample':
        sample(args.count, args.combined)
    else:
        measure(args.manifest)
