#!/usr/bin/env python3
"""Build, qualify and compare GC and arena-scoped SVG guests.

Compilation and verification are outside the timed fresh-process boundary.
The EDA NetLisp executable calls its real functional SVG implementation; its
algorithm, validation, memory policy and output differ from mylang's.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import statistics
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
import shutil

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/svg-arenas-20260921'
BASE = ROOT / '.tmp/full-svg-benchmark-20260921'
CPU = 6
SEED = 20260921
MEMORY_LIMIT = '268435456'
CASES = ('fixture', 'changed-net', 'changed-value')
MODES = {
    'o3': (), 'lto': ('--lto',), 'bounded': ('--step-accounting',),
    'lto-bounded': ('--lto', '--step-accounting'),
}
NEW = {f'{policy}-{mode}': flags for policy in ('gc', 'arena') for mode, flags in MODES.items()}
ARMS = {'netlisp': BASE / 'netlisp-llvm-fast',
        **{name: WORK / name for name in NEW}}
NATIVE_ARMS = {name: BASE / name for name in ('rust-o3', 'go-fast', 'zig-o3')}
ALL_ARMS = {**ARMS, **NATIVE_ARMS}
REFS = json.loads((ROOT / 'experiments/full-svg-benchmark/qualification.json').read_text())['cases']
DOCS = ('lib/modules/straps-synth-lmx2595.sexp',
        'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
sys.path.insert(0, str(ROOT / 'tests'))
from schematic_layout import geometry


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def environment():
    env = dict(os.environ)
    # Freeze build policy and dependencies without changing machine settings.
    for key in list(env):
        if key.startswith('MYLANG_QBE_LLVM_') or key in (
                'NETLISP_LIB_DIR', 'NETLISP_STDLIB_DIR', 'LD_PRELOAD',
                'GOGC', 'GOMEMLIMIT', 'GODEBUG', 'GOMAXPROCS'):
            del env[key]
    env['MYLANG_MEMORY_LIMIT'] = MEMORY_LIMIT
    return env


def prepare():
    project = BASE / 'projects' / 'fixture'
    required = [BASE / 'netlisp-llvm-fast', *(project / path for path in DOCS)]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise RuntimeError('missing frozen full-SVG prerequisites; run `python3 experiments/full-svg-benchmark/prepare_fixtures.py` and build its retained NetLisp arm: ' + ', '.join(missing))
    gc_dir, arena_dir = WORK / 'guest-gc', WORK / 'guest-arena'
    gc_dir.mkdir(parents=True, exist_ok=True); arena_dir.mkdir(parents=True, exist_ok=True)
    for source in sorted((ROOT / 'src/schematic/guest').glob('*.my')):
        shutil.copy2(source, gc_dir / source.name); shutil.copy2(source, arena_dir / source.name)
    main = (gc_dir / 'main.my').read_text()
    body = '''def main(host: Host) -> Result[None, int]:
    inputs = schematic_inputs.load(host)
    circuit = sexpr.parse(host, inputs.circuit)?
    pinout = sexpr.parse(host, inputs.pinout)?
    interface = sexpr.parse(host, inputs.interface)?
    drawing = schematic.build(host, circuit, pinout, interface)?
    svg.render(host, drawing)
    return Ok(None)
'''
    arena = '''def main(host: Host) -> Result[None, int]:
    with arena():
        inputs = schematic_inputs.load(host)
        circuit = sexpr.parse(host, inputs.circuit)?
        pinout = sexpr.parse(host, inputs.pinout)?
        interface = sexpr.parse(host, inputs.interface)?
        drawing = schematic.build(host, circuit, pinout, interface)?
        svg.render(host, drawing)
        return Ok(None)
'''
    assert main.count(body) == 1
    (arena_dir / 'main.my').write_text(main.replace(body, arena))
    for source in gc_dir.glob('*.my'):
        if source.name != 'main.my': assert source.read_bytes() == (arena_dir / source.name).read_bytes()
    shutil.copy2(gc_dir / 'main.my', OUT / 'svg-main-gc.my')
    shutil.copy2(arena_dir / 'main.my', OUT / 'svg-main-arena.my')


def build():
    WORK.mkdir(parents=True, exist_ok=True)
    prepare()
    records = {}
    for name, flags in NEW.items():
        command = [str(ROOT / 'zig-out/bin/mylang'), 'build',
                   str(WORK / ('guest-arena' if name.startswith('arena-') else 'guest-gc') / 'main.my'), '--project', '--provider',
                   'src/schematic/native_schematic.c', '--backend', 'llvm',
                   '--llvm-opt', '3', *flags, '--keep-symbols', '--cache-dir',
                   str(WORK / f'cache-{name}'), '--report', '-o', str(ARMS[name])]
        started = time.perf_counter()
        result = subprocess.run(command, env=environment(), cwd=ROOT,
                                capture_output=True, timeout=1200)
        (OUT / f'{name}-build.stdout').write_bytes(result.stdout)
        (OUT / f'{name}-build.stderr').write_bytes(result.stderr)
        assert result.returncode == 0, (name, result.stderr.decode(errors='replace'))
        records[name] = {'command': command, 'elapsed_seconds': time.perf_counter() - started,
                         'binary_sha256': sha(ARMS[name]),
                         'receipt': json.loads(Path(str(ARMS[name]) + '.qbe-manifest.json').read_text())}
        print(f'Built {name}', flush=True)
    source_paths = [*sorted((WORK / 'guest-gc').glob('*.my')), *sorted((WORK / 'guest-arena').glob('*.my')),
                    ROOT / 'src/qbe_host_runtime.c', ROOT / 'src/schematic/native_schematic.c',
                    ROOT / 'src/native_heap.c', ROOT / 'src/native_heap.h',
                    ROOT / 'src/native_arena.c', ROOT / 'src/native_arena.h',
                    ROOT / 'src/native_regions.c', ROOT / 'src/native_regions.h',
                    ROOT / 'src/native_bytes.c', ROOT / 'src/native_bytes.h',
                    ROOT / 'src/native_collections.c', ROOT / 'src/native_collections.h',
                    ROOT / 'src/qbe_arena.c', ROOT / 'src/qbe_arena.h', ROOT / 'src/qbe_arena.zig',
                    *sorted((ROOT / 'experiments/llvm-backend').glob('*.py')),
                    *sorted((ROOT / 'src').glob('qbe_build*.zig'))]
    evidence = {'compiler_sha256': sha(ROOT / 'zig-out/bin/mylang'),
                'memory_limit_bytes': int(MEMORY_LIMIT),
                'sources': {str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p): sha(p) for p in source_paths},
                'builds': records}
    (OUT / 'builds.json').write_text(json.dumps(evidence, indent=2) + '\n')


def execute(name, case, extra=(), validate=True):
    project = BASE / 'projects' / case
    output = WORK / 'measured.svg'
    issue = WORK / 'measured.issue'
    output.write_bytes(b'')
    issue.write_bytes(b'')
    env = environment()
    command = ['taskset', '-c', str(CPU), str(ALL_ARMS[name])]
    if name == 'netlisp':
        command += [str(project), 'straps-synth-lmx2595', str(output), *extra]
    elif name in NATIVE_ARMS:
        command += [str(project / path) for path in DOCS]
        command += [str(output), *extra]
    else:
        env.update(MYLANG_SCHEMATIC_DECLARED='io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue',
                   MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
        env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(project / path) for i, path in enumerate(DOCS)})
        command += ['--print-result']
        if name.endswith('bounded') and not any(arg.startswith('--max-steps=') for arg in extra):
            command += ['--max-steps=100000000']
        command += list(extra)
    started = time.perf_counter_ns()
    result = subprocess.run(command, env=env, cwd=ROOT, capture_output=True, timeout=90)
    elapsed_ms = (time.perf_counter_ns() - started) / 1e6
    if validate:
        assert (result.returncode, result.stdout, result.stderr, issue.read_bytes()) == (
            0, b'0\n' if name in NEW else b'', b'', b''), (name, case, result, issue.read_bytes())
        reference = 'netlisp-llvm-fast' if name == 'netlisp' else 'mylang-o3'
        assert sha(output) == REFS[case][reference]['svg_sha256'], (name, case, sha(output))
    return elapsed_ms, result, output.read_bytes()


def qualify(arms=ARMS, filename='qualification.json'):
    WORK.mkdir(parents=True, exist_ok=True)
    evidence = {}
    for name in arms:
        cases = {}
        for case in CASES:
            _, _, svg = execute(name, case)
            if name in NEW:
                geometry(ET.fromstring(svg))
                execute(name, case, ('--gc-stress',))
            cases[case] = {'svg_sha256': hashlib.sha256(svg).hexdigest(),
                           'svg_bytes': len(svg), 'matches_retained_reference': True,
                           'gc_stress_checked': name in NEW}
        evidence[name] = {'binary': str(arms[name].relative_to(ROOT)),
                          'binary_sha256': sha(arms[name]), 'cases': cases}
    for name in ('gc-bounded', 'gc-lto-bounded', 'arena-bounded', 'arena-lto-bounded'):
        limits = {}
        for option, code in [('--max-steps=1', b'R_STEP_LIMIT'), ('--max-frames=1', b'R_FRAME_LIMIT')]:
            _, result, _ = execute(name, 'fixture', (option,), validate=False)
            assert result.returncode != 0 and code in result.stderr, (name, option, result)
            limits[option] = {'exit_code': result.returncode, 'stderr': result.stderr.decode()}
        evidence[name]['budget_rejection'] = limits
    (OUT / filename).write_text(json.dumps(evidence, indent=2) + '\n')
    print(f'{len(arms)} binaries match retained SVGs; mylang passes geometry, GC stress and budget checks.', flush=True)


def native_qualify():
    """Bind the combined comparison to previously built and qualified binaries."""
    provenance_path = ROOT / 'experiments/full-svg-benchmark/native-provenance.json'
    provenance = json.loads(provenance_path.read_text())
    assert provenance['passed']
    assert {build['name'] for build in provenance['builds']} == set(NATIVE_ARMS)
    for record in provenance['builds']:
        assert sha(ROOT / record['source']) == record['source_sha256'], record['name']
        assert ROOT / record['binary'] == NATIVE_ARMS[record['name']]
        assert sha(NATIVE_ARMS[record['name']]) == record['binary_sha256'], record['name']
    qualified = json.loads((OUT / 'qualification.json').read_text())
    for name, binary in ARMS.items():
        assert sha(binary) == qualified[name]['binary_sha256'], name
    qualify(ALL_ARMS, 'native-qualification.json')
    (OUT / 'native-builds.json').write_text(json.dumps(provenance, indent=2) + '\n')


def percentile(values, fraction):
    values = sorted(values)
    point = (len(values) - 1) * fraction
    lower = int(point)
    upper = min(lower + 1, len(values) - 1)
    return values[lower] + (values[upper] - values[lower]) * (point - lower)


def measure(arms=ARMS, prefix=''):
    qualified = json.loads((OUT / f'{prefix}qualification.json').read_text())
    for name, path in arms.items():
        assert sha(path) == qualified[name]['binary_sha256'], f'{name} changed after qualification'
    rng = random.Random(SEED)
    rows = []
    for number in range(-3, 31):
        jobs = [(name, case) for name in arms for case in CASES]
        rng.shuffle(jobs)
        values = {case: {} for case in CASES}
        for name, case in jobs:
            values[case][name] = execute(name, case)[0]
        if number >= 0:
            rows.append({'round': number, 'order': jobs, 'ms': values})
    summaries = {}
    pairs = [(name, 'netlisp') for name in arms if name != 'netlisp']
    pairs += [(f'arena-{mode}', f'gc-{mode}') for mode in MODES]
    if 'zig-o3' in arms:
        pairs += [(name, 'zig-o3') for name in arms if name != 'zig-o3']
    for case in CASES:
        medians = {name: statistics.median(r['ms'][case][name] for r in rows) for name in arms}
        comparisons = {}
        for numerator, denominator in pairs:
            bootstrap = []
            for _ in range(4000):
                sample = rng.choices(rows, k=len(rows))
                bootstrap.append(statistics.median(r['ms'][case][numerator] for r in sample) /
                                 statistics.median(r['ms'][case][denominator] for r in sample))
            comparisons[f'{numerator}/{denominator}'] = {
                'ratio': medians[numerator] / medians[denominator],
                'paired_bootstrap_95': [percentile(bootstrap, .025), percentile(bootstrap, .975)]}
        summaries[case] = {'median_ms': medians, 'comparisons': comparisons}
    evidence = {'cpu': CPU, 'seed': SEED, 'rounds': 31, 'warmup_rounds': 3,
                'memory_limit_bytes': int(MEMORY_LIMIT),
                'scope': 'fresh process: input read, model, placement, routing, SVG private-file output, shutdown; excludes compilation and verification',
                'all_timed_outputs_hash_checked': True, 'timed_runs': len(rows) * len(arms) * len(CASES),
                'binary_sha256': {name: sha(path) for name, path in arms.items()},
                'summary': summaries, 'samples': rows}
    if 'zig-o3' in arms:
        evidence['native_builds_sha256'] = sha(OUT / 'native-builds.json')
        evidence['go_runtime_policy'] = 'default GC, memory limit and scheduler; GOGC/GOMEMLIMIT/GODEBUG/GOMAXPROCS overrides cleared'
    for name, path in arms.items():
        assert sha(path) == qualified[name]['binary_sha256'], f'{name} changed during measurement'
    (OUT / f'{prefix}measurements.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(summaries, indent=2), flush=True)



def allocation_workload_build():
    records = {}
    for policy in ('gc', 'arena'):
        source = OUT / f'{policy}.my'
        output = WORK / f'workload-{policy}'
        command = [str(ROOT / 'zig-out/bin/mylang'), 'build', str(source),
                   '--backend', 'llvm', '--llvm-opt', '3', '--keep-symbols',
                   '--cache-dir', str(WORK / f'workload-cache-{policy}'), '--report', '-o', str(output)]
        result = subprocess.run(command, cwd=ROOT, env=environment(), capture_output=True, timeout=1200)
        assert result.returncode == 0, result.stderr.decode(errors='replace')
        records[policy] = {'command': command, 'binary_sha256': sha(output)}
    (OUT / 'workload-builds.json').write_text(json.dumps(records, indent=2) + '\n')


def allocation_workload_qualify():
    results = {}
    for policy in ('gc', 'arena'):
        binary = WORK / f'workload-{policy}'
        normal = subprocess.run([str(binary), '--print-result'], cwd=ROOT, env=environment(), capture_output=True, timeout=60)
        stress = subprocess.run([str(binary), '--print-result', '--gc-stress'], cwd=ROOT, env=environment(), capture_output=True, timeout=60)
        normal_result = (normal.returncode, normal.stdout, normal.stderr)
        stress_result = (stress.returncode, stress.stdout, stress.stderr)
        assert normal_result == stress_result == (0, b'31064064\n', b''), (policy, normal, stress)
        results[policy] = {'stdout': normal.stdout.decode(), 'stderr': normal.stderr.decode(), 'exit_code': normal.returncode,
                           'binary_sha256': sha(binary)}
    (OUT / 'workload-qualification.json').write_text(json.dumps({'passed': True, 'arms': results}, indent=2) + '\n')


def allocation_workload_measure():
    qualified = json.loads((OUT / 'workload-qualification.json').read_text())
    for policy in ('gc', 'arena'):
        assert sha(WORK / f'workload-{policy}') == qualified['arms'][policy]['binary_sha256']
    rng = random.Random(SEED)
    rows = []
    for number in range(-3, 31):
        order = ['gc', 'arena']
        rng.shuffle(order)
        values = {}
        for policy in order:
            binary = WORK / f'workload-{policy}'
            started = time.perf_counter_ns()
            result = subprocess.run(['taskset', '-c', str(CPU), str(binary), '--print-result'],
                                    cwd=ROOT, env=environment(), capture_output=True, timeout=60)
            values[policy] = (time.perf_counter_ns() - started) / 1e6
            assert result.returncode == 0 and result.stdout.decode() == qualified['arms'][policy]['stdout'] and result.stderr == b''
        if number >= 0:
            rows.append({'round': number, 'order': order, 'ms': values})
    medians = {policy: statistics.median(row['ms'][policy] for row in rows)
               for policy in ('gc', 'arena')}
    evidence = {'cpu': CPU, 'seed': SEED, 'rounds': 31, 'warmups': 3,
                'memory_limit_bytes': int(MEMORY_LIMIT),
                'binary_sha256': {policy: sha(WORK / f'workload-{policy}') for policy in ('gc', 'arena')},
                'median_ms': medians, 'arena_over_gc': medians['arena'] / medians['gc'],
                'samples': rows}
    (OUT / 'workload-measurements.json').write_text(json.dumps(evidence, indent=2) + '\n')


def variant_qualify():
    from qualify_variants import main
    main()


def zig_control_build():
    output = WORK / 'zig-allocation-control'
    command = ['zig', 'build-exe', '-O', 'ReleaseFast', str(OUT / 'zig_allocation_control.zig'),
               '-femit-bin=' + str(output)]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=1200)
    assert result.returncode == 0, result.stderr.decode(errors='replace')
    (OUT / 'zig-control-build.json').write_text(json.dumps(
        {'command': command, 'binary_sha256': sha(output),
         'source_sha256': sha(OUT / 'zig_allocation_control.zig')}, indent=2) + '\n')


def zig_control_qualify():
    binary = WORK / 'zig-allocation-control'
    result = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, timeout=60)
    assert result.returncode == 0 and result.stderr == b'', result
    assert result.stdout == b''
    (OUT / 'zig-control-qualification.json').write_text(json.dumps(
        {'passed': True, 'stdout': result.stdout.decode()}, indent=2) + '\n')


def allocation_evidence():
    builds = json.loads((OUT / 'builds.json').read_text())
    facts = {'compiler_sha256': builds['compiler_sha256'], 'arms': {}}
    for name in NEW:
        manifest = json.loads(Path(str(ARMS[name]) + '.qbe-manifest.json').read_text())
        entry = next(item for item in manifest['functions'] if item['name'] == 'main::main')
        disassembly = subprocess.run(
            ['objdump', '-d', f'--disassemble={entry["symbol"]}', str(ARMS[name])],
            capture_output=True, text=True, check=True).stdout
        refs = sorted({line[line.index('<') + 1:line.index('>')]
                       for line in disassembly.splitlines() if '<' in line and '>' in line
                       and any(token in line.lower() for token in ('arena', 'region', 'heap', 'frame', 'root', 'gc'))})
        facts['arms'][name] = {'binary_sha256': sha(ARMS[name]), 'entry_symbol': entry['symbol'],
                              'allocator_related_calls': refs}
    (OUT / 'allocator-evidence.json').write_text(json.dumps(facts, indent=2) + '\n')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('build', 'qualify', 'evidence', 'measure',
                                                   'native-qualify', 'native-measure',
                                                   'workload-build', 'workload-qualify', 'workload-measure', 'variants',
                                                   'zig-control-build', 'zig-control-qualify'))
    args = parser.parse_args()
    {'build': build, 'qualify': qualify, 'evidence': allocation_evidence,
     'native-qualify': native_qualify,
     'native-measure': lambda: measure(ALL_ARMS, 'native-'),
     'measure': measure, 'workload-build': allocation_workload_build,
     'workload-qualify': allocation_workload_qualify,
     'workload-measure': allocation_workload_measure, 'variants': variant_qualify,
     'zig-control-build': zig_control_build, 'zig-control-qualify': zig_control_qualify}[args.action]()
