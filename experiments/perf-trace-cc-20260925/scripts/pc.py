#!/usr/bin/env python3
"""Base-vs-new runtime check of guest programs built by two (or more) mylang compilers.

usage:
  pc.py build   --side NAME=PATH/TO/mylang [--side ...] [--only SUBSTR,...] [--arms qbe,llvm] [--jobs 4]
  pc.py measure --sides base,new [--only SUBSTR,...] [--arms qbe,llvm] [--phases perf,rss,time]
                [--perf-reps 3] [--rounds 5] [--cpu 10] --out results.json
  pc.py summary results.json [--ref base] [--cmp new]

Every build of one side goes to WORK/bin/<side>/<build_key>.<arm> with the side's own
object cache (WORK/cache-<side>), so no side reuses another's objects. `build` also
records the binary sha256, the emitted IL's sha256 (function IL + entry + runtime data
from `emit-qbe`/`emit-project-qbe`), and checks each program's output once
(`.expected` for parity and the micro programs, the Lox benchmark's expected files,
and for the schematic a clean run whose SVG hash is recorded and compared across sides).

WORK defaults to <repo>/.tmp-pc (gitignored scratch; override with PC_WORK).
"""
import argparse, concurrent.futures, hashlib, json, os, random, re, statistics, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXP = HERE.parent
TREE = EXP.parents[1]
WORK = Path(os.environ.get('PC_WORK', str(TREE / '.tmp-pc')))
PARITY = TREE / 'bench/parity'
SCHEMATIC_GUEST = TREE / 'src/schematic/guest'
SCHEMATIC_PROVIDER = TREE / 'src/schematic/native_schematic.c'
SCHEMATIC_PROJECTS = Path(os.environ.get('PC_SCHEMATIC_PROJECTS',
                                         '/home/epentland/ai/canopy/mylang/.tmp/full-svg-benchmark-20260921/projects'))
# The SVG every native port (Go, Zig, Rust) and the 2026-09-22 audit's mylang arms produced per input
# (experiments/schematic-parity-gap-20260922/results/results-base.json).
SCHEMATIC_SVG = {'fixture': '68157ea785ee3766c039714d1d081ea1c7a55def6cf9124660495f8b797ed388',
                 'changed-net': 'e3679477d2861edb64ed6985006bbe1aa9963e7d75b2f984df7b40116e88dc90',
                 'changed-value': '19fdda810d0a0ede38c9780a7084f0da2a7153fb38a3862982a5596291f53ed6'}
SCHEMATIC_DOCS = ('lib/modules/straps-synth-lmx2595.sexp', 'lib/pinouts/lmx2595rhar.sexp', 'lib/interfaces/spi.sexp')
LOX_PORT = WORK / 'lox/benchmarks/lox/ports/mylang'   # scripts/prepare_lox.sh builds it
LOX_BENCH = WORK / 'lox/bench'                         # copy of the Lox benchmark's bench/ (scripts, expected, sizes)
ZIG = os.environ.get('MYLANG_ZIG', '/home/epentland/.local/bin/zig')
ARM_FLAGS = {'qbe': [], 'llvm': ['--backend', 'llvm', '--llvm-opt', '3', '--lto']}
# The schematic runner's shipped policy is frame accounting (`--max-frames=1024` at build time).
SCHEMATIC_FLAGS = ['--max-frames=1024']
MEMORY_LIMIT = '8G'
RUN_TIMEOUT = 600
BUILD_CPUS = os.environ.get('PC_BUILD_CPUS', '0,1,4-9,12-19')   # timing CPUs 2,3,10,11 kept free


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def clean_env(extra: dict | None = None) -> dict:
    env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    env['MYLANG_MEMORY_LIMIT'] = MEMORY_LIMIT
    if extra:
        env.update(extra)
    return env


# ------------------------------------------------------------------ programs

def programs() -> list[dict]:
    out = []
    for group in ('suite', 'lib', 'micro'):
        for expected in sorted((PARITY / group).glob('*.expected')):
            src = PARITY / group / f'{expected.stem}.my'
            if src.exists():
                out.append({'id': f'parity/{group}/{expected.stem}', 'kind': 'single', 'src': str(src),
                            'build_key': f'parity-{group}-{expected.stem}', 'arms': ['qbe', 'llvm'],
                            'expected_path': str(expected)})
    for expected in sorted((EXP / 'programs').glob('*.expected')):
        out.append({'id': f'result/{expected.stem}', 'kind': 'single', 'src': str(expected.with_suffix('.my')),
                    'build_key': f'result-{expected.stem}', 'arms': ['qbe', 'llvm'], 'expected_path': str(expected)})
    for case in ('fixture', 'changed-net', 'changed-value'):
        if (SCHEMATIC_PROJECTS / case).exists():
            # The task brief said the LLVM build fails on both compilers; on 2026-09-25 it built and
            # produced the reference SVG on both, so it is measured too.
            out.append({'id': f'schematic/{case}', 'kind': 'schematic', 'case': case, 'build_key': 'schematic',
                        'arms': ['qbe', 'llvm']})
    if LOX_PORT.exists() and (LOX_BENCH / 'sizes.json').exists():
        sizes = json.loads((LOX_BENCH / 'sizes.json').read_text())
        for engine in ('vm', 'tree'):
            for script in sorted((LOX_BENCH / 'scripts').glob('*.lox')):
                if script.stem not in sizes:
                    continue
                out.append({'id': f'lox/{engine}/{script.stem}', 'kind': 'lox', 'script': script.stem, 'engine': engine,
                            'size': sizes[script.stem]['tree'], 'build_key': 'lox', 'arms': ['qbe', 'llvm'],
                            'expected_path': str(LOX_BENCH / 'expected' / f'{script.stem}.tree.out')})
    return out


def select(progs: list[dict], only: str | None) -> list[dict]:
    if not only:
        return progs
    keys = [k for k in only.split(',') if k]
    return [p for p in progs if any(k in p['id'] for k in keys)]


def build_command(prog: dict, compiler: str, arm: str, output: Path, cache: Path) -> tuple[list[str], str]:
    flags = ARM_FLAGS[arm] + ['--cache-dir', str(cache)]
    if prog['kind'] == 'single':
        return [compiler, 'build', prog['src'], '-o', str(output), *flags], str(Path(prog['src']).parent)
    if prog['kind'] == 'schematic':
        return [compiler, 'build', str(SCHEMATIC_GUEST / 'main.my'), '--project', '--provider', str(SCHEMATIC_PROVIDER),
                '--zig', ZIG, '-o', str(output), *SCHEMATIC_FLAGS, *flags], str(TREE)
    return [compiler, 'build', 'main.my', '--project', '-o', str(output), *flags], str(LOX_PORT)


def emit_command(prog: dict, compiler: str) -> tuple[list[str], str]:
    if prog['kind'] == 'single':
        return [compiler, 'emit-qbe', prog['src'], '--no-cache'], str(Path(prog['src']).parent)
    if prog['kind'] == 'schematic':
        return [compiler, 'emit-project-qbe', str(SCHEMATIC_GUEST / 'main.my'), '--no-cache'], str(TREE)
    return [compiler, 'emit-project-qbe', 'main.my', '--no-cache'], str(LOX_PORT)


def il_text(emitted: bytes) -> str:
    """The code-bearing part of an emit-qbe document: every function's IL, the entry and runtime data."""
    doc = json.loads(emitted)
    parts = [f"== {f.get('name')}\n{f.get('il', '')}" for f in doc.get('functions', [])]
    return '\n'.join(parts) + '\n== entry\n' + (doc.get('entry') or '') + '\n== runtime_data\n' + (doc.get('runtime_data') or '')


def declared_of(emitted: bytes) -> str:
    return ','.join(d['name'] for d in json.loads(emitted)['host']['declarations'])


def lox_script(prog: dict) -> Path:
    scripts = WORK / 'lox-scripts'
    scripts.mkdir(parents=True, exist_ok=True)
    source = (LOX_BENCH / 'scripts' / f"{prog['script']}.lox").read_text()
    first, rest = source.split('\n', 1)
    assert first.startswith('var N = ')
    path = scripts / f"{prog['script']}.tree.lox"
    path.write_text(f"var N = {prog['size']};\n{rest}")
    return path


def run_spec(prog: dict, binary: Path, tag: str, declared: str | None = None) -> dict:
    if prog['kind'] == 'single':
        return {'argv': [str(binary)], 'env': clean_env(), 'cwd': str(Path(prog['src']).parent)}
    if prog['kind'] == 'schematic':
        project = SCHEMATIC_PROJECTS / prog['case']
        out = WORK / 'runs' / f"{prog['case']}-{tag}.svg"
        issue = out.with_suffix('.issue')
        out.parent.mkdir(parents=True, exist_ok=True)
        env = clean_env({'MYLANG_SCHEMATIC_DECLARED': declared or '', 'MYLANG_SCHEMATIC_OUTPUT': str(out),
                         'MYLANG_SCHEMATIC_ISSUE': str(issue)})
        env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': str(project / p) for i, p in enumerate(SCHEMATIC_DOCS)})
        return {'argv': [str(binary), '--print-result'], 'env': env, 'cwd': str(TREE), 'svg': out, 'issue': issue}
    return {'argv': [str(binary), f"--engine={prog['engine']}", str(lox_script(prog))], 'env': clean_env(),
            'cwd': str(WORK)}


# ------------------------------------------------------------------ build + check

def state_path(side: str) -> Path:
    return WORK / 'state' / f'{side}.json'


def load_state(side: str) -> dict:
    path = state_path(side)
    return json.loads(path.read_text()) if path.exists() else {'builds': {}, 'il': {}, 'checks': {}}


def do_build(job: dict) -> dict:
    job['bin'].parent.mkdir(parents=True, exist_ok=True)
    if job['bin'].exists():
        job['bin'].unlink()
    started = time.perf_counter()
    done = subprocess.run(['taskset', '-c', BUILD_CPUS, *job['cmd']], cwd=job['cwd'], capture_output=True, text=True,
                          env=clean_env(), timeout=3600)
    ok = done.returncode == 0 and job['bin'].exists()
    return {'cmd': job['cmd'], 'ok': ok, 'seconds': round(time.perf_counter() - started, 2),
            'sha256': sha(job['bin'].read_bytes()) if ok else None, 'size': job['bin'].stat().st_size if ok else None,
            'stderr': done.stderr[-3000:]}


def captured(spec: dict) -> tuple[bytes, bytes, int]:
    try:
        done = subprocess.run(spec['argv'], capture_output=True, env=spec['env'], cwd=spec['cwd'], timeout=RUN_TIMEOUT)
        return done.stdout, done.stderr, done.returncode
    except subprocess.TimeoutExpired:
        return b'', b'timeout', -9


def check(prog: dict, spec: dict) -> dict:
    stdout, stderr, status = captured(spec)
    result = {'status': status, 'stdout_sha256': sha(stdout), 'stderr': stderr[-500:].decode(errors='replace')}
    if prog['kind'] == 'schematic':
        svg = spec['svg'].read_bytes() if spec['svg'].exists() else b''
        issue = spec['issue'].read_bytes() if spec['issue'].exists() else b''
        result['svg_sha256'] = sha(svg)
        result['svg_bytes'] = len(svg)
        # A built guest no longer prints its entry result; the exit status carries it.
        result['ok'] = status == 0 and stdout in (b'', b'0\n') and not issue and sha(svg) == SCHEMATIC_SVG[prog['case']]
    else:
        result['ok'] = status == 0 and stdout == Path(prog['expected_path']).read_bytes()
    return result


def command_build(opts) -> int:
    sides = dict(s.split('=', 1) for s in opts.side)
    arms = opts.arms.split(',')
    progs = select(programs(), opts.only)
    failures = 0
    for side, compiler in sides.items():
        compiler = str(Path(compiler).resolve())
        state = load_state(side)
        state['compiler'] = compiler
        state['compiler_sha256'] = sha(Path(compiler).read_bytes())
        jobs, seen = [], set()
        for prog in progs:
            for arm in prog['arms']:
                if arm not in arms:
                    continue
                key = f"{prog['build_key']}.{arm}"
                if key in seen:
                    continue
                seen.add(key)
                out = WORK / opts.bin_dir / side / key
                cmd, cwd = build_command(prog, compiler, arm, out, WORK / f'cache-{side}')
                cmd += opts.extra_flag
                jobs.append({'key': key, 'bin': out, 'cmd': cmd, 'cwd': cwd})
        print(f'[{side}] building {len(jobs)} binaries with {compiler}', flush=True)
        if opts.bin_dir != 'bin':
            # A side build (e.g. --keep-symbols for per-function identity): record builds only.
            with concurrent.futures.ThreadPoolExecutor(max_workers=opts.jobs) as pool:
                outcomes = {job['key']: o for job, o in zip(jobs, pool.map(do_build, jobs))}
            path = WORK / opts.bin_dir / f'{side}.json'
            path.write_text(json.dumps(outcomes, indent=1))
            failures += sum(not o['ok'] for o in outcomes.values())
            continue
        with concurrent.futures.ThreadPoolExecutor(max_workers=opts.jobs) as pool:
            for job, outcome in zip(jobs, pool.map(do_build, jobs)):
                state['builds'][job['key']] = outcome
                if not outcome['ok']:
                    failures += 1
                    print(f"[{side}] BUILD FAIL {job['key']}\n{outcome['stderr'][-1500:]}", flush=True)
        # IL identity: one emission per build key (the IL does not depend on the backend).
        emitted_keys = set()
        for prog in progs:
            if prog['build_key'] in emitted_keys:
                continue
            emitted_keys.add(prog['build_key'])
            cmd, cwd = emit_command(prog, compiler)
            done = subprocess.run(cmd, cwd=cwd, capture_output=True, env=clean_env(), timeout=1200)
            if done.returncode != 0:
                state['il'][prog['build_key']] = {'ok': False, 'stderr': done.stderr[-1000:].decode(errors='replace')}
                continue
            text = il_text(done.stdout)
            il_dir = WORK / 'il' / side
            il_dir.mkdir(parents=True, exist_ok=True)
            (il_dir / f"{prog['build_key']}.il").write_text(text)
            entry = {'ok': True, 'sha256': sha(text.encode())}
            if prog['kind'] == 'schematic':
                entry['declared'] = declared_of(done.stdout)
            state['il'][prog['build_key']] = entry
        for prog in progs:
            for arm in prog['arms']:
                key = f"{prog['build_key']}.{arm}"
                if arm not in arms or not state['builds'].get(key, {}).get('ok'):
                    continue
                declared = state['il'].get(prog['build_key'], {}).get('declared')
                spec = run_spec(prog, WORK / 'bin' / side / key, f'{side}-{arm}-check', declared)
                outcome = check(prog, spec)
                state['checks'][f"{prog['id']}|{arm}"] = outcome
                if not outcome['ok']:
                    failures += 1
                    print(f"[{side}] CHECK FAIL {prog['id']} {arm}: status {outcome['status']} {outcome['stderr'][:300]}",
                          flush=True)
        state_path(side).parent.mkdir(parents=True, exist_ok=True)
        state_path(side).write_text(json.dumps(state, indent=1))
        print(f'[{side}] done', flush=True)
    return 1 if failures else 0


# ------------------------------------------------------------------ measurement

def cpu_times() -> dict[int, tuple[int, int]]:
    out = {}
    for line in Path('/proc/stat').read_text().splitlines():
        m = re.match(r'cpu(\d+) (.*)', line)
        if m:
            f = [int(x) for x in m.group(2).split()]
            out[int(m.group(1))] = (sum(f), f[3] + f[4])
    return out


def busy(a, b, cpu: int) -> float:
    total = b[cpu][0] - a[cpu][0]
    return 0.0 if total <= 0 else round(1.0 - (b[cpu][1] - a[cpu][1]) / total, 3)


def sibling_of(cpu: int) -> int | None:
    text = Path(f'/sys/devices/system/cpu/cpu{cpu}/topology/thread_siblings_list').read_text().strip()
    cpus = []
    for piece in text.split(','):
        lo, _, hi = piece.partition('-')
        cpus += list(range(int(lo), int(hi or lo) + 1))
    others = [c for c in cpus if c != cpu]
    return others[0] if others else None


def perf_counts(spec: dict, cpu: int) -> dict:
    cmd = ['taskset', '-c', str(cpu), 'perf', 'stat', '-x,', '-e', 'instructions:u,cycles:u', '--', *spec['argv']]
    done = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=spec['env'], cwd=spec['cwd'],
                          timeout=RUN_TIMEOUT)
    counts = {'status': done.returncode}
    for line in done.stderr.decode(errors='replace').splitlines():
        fields = line.split(',')
        if len(fields) < 3 or 'cpu_atom' in fields[2]:
            continue
        name = 'instructions' if 'instructions' in fields[2] else 'cycles' if 'cycles' in fields[2] else None
        if name and fields[0].replace('.', '').isdigit():
            counts[name] = int(float(fields[0]))
    return counts


def peak_rss_kb(spec: dict) -> int | None:
    done = subprocess.run(['/usr/bin/time', '-f', '%M', *spec['argv']], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                          env=spec['env'], cwd=spec['cwd'], text=True, timeout=RUN_TIMEOUT)
    try:
        return int(done.stderr.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None


def spawn_timed(spec: dict) -> dict:
    """One fresh process (inherits this process's pinning): wall, child CPU, exit status."""
    out = os.open(os.devnull, os.O_WRONLY)
    try:
        started = time.perf_counter_ns()
        pid = os.posix_spawn(spec['argv'][0], spec['argv'], spec['env'],
                             file_actions=[(os.POSIX_SPAWN_DUP2, out, 1), (os.POSIX_SPAWN_DUP2, out, 2)])
        _, status, usage = os.wait4(pid, 0)
        wall = (time.perf_counter_ns() - started) / 1e9
    finally:
        os.close(out)
    return {'wall_s': wall, 'cpu_s': usage.ru_utime + usage.ru_stime, 'status': os.waitstatus_to_exitcode(status)}


def command_measure(opts) -> int:
    sides = opts.sides.split(',')
    arms = opts.arms.split(',')
    phases = set(opts.phases.split(','))
    states = {s: load_state(s) for s in sides}
    progs = select(programs(), opts.only)
    rng = random.Random(opts.seed)
    cpu = opts.cpu
    sib = sibling_of(cpu)
    out_path = Path(opts.out)
    result = json.loads(out_path.read_text()) if out_path.exists() and opts.append else {}
    result.setdefault('meta', {}).update({'sides': {s: {'compiler': states[s].get('compiler'),
                                                         'compiler_sha256': states[s].get('compiler_sha256')}
                                                     for s in sides},
                                          'cpu': cpu, 'sibling': sib, 'perf_reps': opts.perf_reps,
                                          'rounds': opts.rounds, 'memory_limit': MEMORY_LIMIT})
    samples = result.setdefault('samples', {})
    original = os.sched_getaffinity(0)
    for prog in progs:
        for arm in prog['arms']:
            if arm not in arms:
                continue
            key = f"{prog['build_key']}.{arm}"
            specs = {}
            for s in sides:
                if not states[s]['builds'].get(key, {}).get('ok'):
                    continue
                declared = states[s]['il'].get(prog['build_key'], {}).get('declared')
                specs[s] = run_spec(prog, WORK / 'bin' / s / key, f'{s}-{arm}-m', declared)
            if len(specs) < len(sides):
                print(f"skip {prog['id']} {arm}: not built on every side", flush=True)
                continue
            entry = samples.setdefault(f"{prog['id']}|{arm}", {})
            t0 = cpu_times()
            load0 = os.getloadavg()[0]
            if 'perf' in phases:
                per = {s: [] for s in sides}
                for _ in range(opts.perf_reps):
                    order = sides[:]
                    rng.shuffle(order)
                    for s in order:
                        per[s].append(perf_counts(specs[s], cpu))
                for s in sides:
                    entry.setdefault(s, {})['perf'] = per[s]
            if 'rss' in phases:
                per = {s: [] for s in sides}
                for _ in range(opts.rss_reps):
                    for s in sides:
                        per[s].append(peak_rss_kb(specs[s]))
                for s in sides:
                    entry.setdefault(s, {})['rss_kb'] = per[s]
            if 'time' in phases and opts.rounds > 0:
                os.sched_setaffinity(0, {cpu})
                try:
                    for s in sides:          # one warm-up each
                        spawn_timed(specs[s])
                    per = {s: [] for s in sides}
                    for _ in range(opts.rounds):
                        order = sides[:]
                        rng.shuffle(order)
                        for s in order:
                            per[s].append(spawn_timed(specs[s]))
                finally:
                    os.sched_setaffinity(0, original)
                for s in sides:
                    entry.setdefault(s, {})['time'] = per[s]
            t1 = cpu_times()
            entry['context'] = {'cpu_busy': busy(t0, t1, cpu), 'sibling_busy': busy(t0, t1, sib) if sib is not None else None,
                                'load1_start': load0, 'load1_end': os.getloadavg()[0]}
            line = [prog['id'], arm]
            for s in sides[1:]:
                a, b = entry.get(sides[0], {}), entry.get(s, {})
                if 'perf' in a:
                    ia = statistics.median(x.get('instructions', 0) for x in a['perf'])
                    ib = statistics.median(x.get('instructions', 0) for x in b['perf'])
                    line.append(f'{s}/{sides[0]} instr {ib / ia:.4f}' if ia else 'instr n/a')
                if 'time' in a:
                    wa = statistics.median(x['wall_s'] for x in a['time'])
                    wb = statistics.median(x['wall_s'] for x in b['time'])
                    line.append(f'wall {wb / wa:.3f} ({wa * 1000:.0f} ms)')
            line.append(f"sib {entry['context']['sibling_busy']}")
            print('  '.join(line), flush=True)
            out_path.write_text(json.dumps(result, indent=1))
    return 0


# ------------------------------------------------------------------ summary

def med(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None


def geomean(values):
    values = [v for v in values if v]
    if not values:
        return None
    import math
    return math.exp(sum(math.log(v) for v in values) / len(values))


def command_summary(opts) -> int:
    data = json.loads(Path(opts.results).read_text())
    ref, cmp_ = opts.ref, opts.cmp
    rows = []
    for key, entry in data['samples'].items():
        prog, arm = key.split('|')
        a, b = entry.get(ref), entry.get(cmp_)
        if not a or not b:
            continue
        row = {'program': prog, 'arm': arm}
        for metric, getter in (('instructions', lambda e: med(x.get('instructions') for x in e.get('perf', []))),
                               ('cycles', lambda e: med(x.get('cycles') for x in e.get('perf', []))),
                               ('wall_s', lambda e: med(x['wall_s'] for x in e.get('time', []))),
                               ('rss_kb', lambda e: med(e.get('rss_kb', [])))):
            va, vb = getter(a), getter(b)
            row[f'{metric}_{ref}'] = va
            row[f'{metric}_{cmp_}'] = vb
            row[f'{metric}_ratio'] = (vb / va) if va and vb else None
        row['sibling_busy'] = entry.get('context', {}).get('sibling_busy')
        rows.append(row)
    print(json.dumps(rows, indent=1) if opts.json else '')
    if not opts.json:
        print(f"| program | arm | instr {ref} | instr ratio | cycles ratio | wall {ref} ms | wall ratio | RSS {ref} KB | RSS ratio |")
        print('|---|---|---:|---:|---:|---:|---:|---:|---:|')
        for r in rows:
            def f(x, p=4):
                return '—' if x is None else f'{x:.{p}f}'
            print(f"| {r['program']} | {r['arm']} | {r[f'instructions_{ref}'] or 0:,.0f} | {f(r['instructions_ratio'])} | "
                  f"{f(r['cycles_ratio'], 3)} | {(r[f'wall_s_{ref}'] or 0) * 1000:.1f} | {f(r['wall_s_ratio'], 3)} | "
                  f"{r[f'rss_kb_{ref}'] or 0:,.0f} | {f(r['rss_kb_ratio'], 3)} |")
        groups = {}
        for r in rows:
            family = r['program'].split('/')[0]
            for gk in (f"{family} {r['arm']}", f"all {r['arm']}"):
                groups.setdefault(gk, []).append(r)
        print('\n| group | n | instr geomean | cycles geomean | wall geomean | RSS geomean |')
        print('|---|---:|---:|---:|---:|---:|')
        for gk, rs in sorted(groups.items()):
            vals = [geomean([r[f'{m}_ratio'] for r in rs]) for m in ('instructions', 'cycles', 'wall_s', 'rss_kb')]
            print(f"| {gk} | {len(rs)} | " + ' | '.join('—' if v is None else f'{v:.4f}' for v in vals) + ' |')
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    b = sub.add_parser('build')
    b.add_argument('--side', action='append', required=True)
    b.add_argument('--only')
    b.add_argument('--arms', default='qbe,llvm')
    b.add_argument('--jobs', type=int, default=4)
    b.add_argument('--bin-dir', default='bin')
    b.add_argument('--extra-flag', action='append', default=[])
    m = sub.add_parser('measure')
    m.add_argument('--sides', default='base,new')
    m.add_argument('--only')
    m.add_argument('--arms', default='qbe,llvm')
    m.add_argument('--phases', default='perf,rss,time')
    m.add_argument('--perf-reps', type=int, default=3)
    m.add_argument('--rss-reps', type=int, default=3)
    m.add_argument('--rounds', type=int, default=5)
    m.add_argument('--cpu', type=int, default=10)
    m.add_argument('--seed', type=int, default=20260925)
    m.add_argument('--append', action='store_true')
    m.add_argument('--out', required=True)
    s = sub.add_parser('summary')
    s.add_argument('results')
    s.add_argument('--ref', default='base')
    s.add_argument('--cmp', default='new')
    s.add_argument('--json', action='store_true')
    opts = ap.parse_args()
    return {'build': command_build, 'measure': command_measure, 'summary': command_summary}[opts.cmd](opts)


if __name__ == '__main__':
    sys.exit(main())
