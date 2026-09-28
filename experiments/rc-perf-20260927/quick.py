#!/usr/bin/env python3
"""Fast RC-vs-GC instruction loop for the D9 WP-4 43-program corpus.

A development instrument, not acceptance evidence. It keeps the mandated corpus,
build commands and output checks (pc.py) but drops what makes the acceptance
sweep slow:

* one run per program and side: retired user instructions are deterministic to
  about +-0.5% here (hash probing over ASLR addresses), far below the gaps being
  closed; medians of three buy nothing during development;
* runs execute in parallel: instruction counts do not depend on load. Each run
  is pinned to one CPU from a pool (P- and E-cores retire identical counts when
  pinned; an unpinned hybrid run that migrates over-counts atom+core);
* GC counts and outputs are measured once per (binary hash, argv) and cached;
* `--size dev` shrinks the Lox inputs (about a fifth of the instructions); RC
  output is compared with the accepted GC binary's output at the same size.
  Dev ratios reproduce full-size ratios (binary_trees 20.20x/32.82x dev vs
  20.21x/32.78x full). `--size smoke` is a quick differential check only:
  outputs at several sizes catch wrong answers that one size can mask (Lox
  method_call on RC/QBE is wrong at N<=10000 but right at the full N=50000).

usage:
  quick.py setup
  quick.py build   --compiler PATH --tag NAME [--only a,b] [--arms qbe,llvm] [--jobs 3] [--stats | --sites]
                   [--runtime rc|gc]
  quick.py measure --tag NAME [--size full|dev] [--only a,b] [--arms qbe,llvm] [--jobs 8] [--out FILE]
  quick.py counts  --tag NAME [--size full|dev] [--only a,b]      (needs a --stats build)
  quick.py sites   --tag NAME [--size full|dev] [--only a,b] [--top N]  (needs a --sites build; RC-SITES-1)
  quick.py compare A.json B.json                                   (per-row instruction change)

WORK is <tree>/.tmp-rc-quick (override RC_QUICK_WORK). GC baselines come from the
accepted WP-4pre Debug compiler's private binaries (setup copies them).

`build --runtime gc` builds the corpus with `--gc-runtime` instead, so a
compiler change that touches collector code can be measured against another
compiler's collector build: `measure` reports each tag against the same accepted
GC baseline, and `compare GC-A.json GC-B.json` gives the per-row instruction
change between the two collector builds.
"""
import argparse, concurrent.futures, hashlib, json, math, os, shutil, subprocess, sys, tempfile, time
from pathlib import Path

TREE = Path(__file__).resolve().parents[2]
WORK = Path(os.environ.get('RC_QUICK_WORK', str(TREE / '.tmp-rc-quick')))
ACCEPTED = Path('/home/epentland/ai/canopy/mylang-worktrees/d9-rc-performance/.tmp-rc-performance')
os.environ['PC_WORK'] = str(WORK)
os.environ.setdefault('TMPDIR', str(WORK / 'tmp'))
import importlib.util, queue
CPUS = queue.Queue()
for _cpu in os.environ.get('RC_QUICK_CPUS', ','.join(str(c) for c in sorted(os.sched_getaffinity(0)))).split(','):
    CPUS.put(_cpu)
_spec = importlib.util.spec_from_file_location('pc', TREE / 'experiments/perf-gc-dict-20260925/scripts/pc.py')
pc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pc)

# Dev sizes: exponential scripts step down, linear ones divide by five.
DEV_SIZE = {'binary_trees': 8, 'fib': 25, 'trees': 4}


def sha_file(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix('.pending')
    tmp.write_text(json.dumps(value, indent=1, sort_keys=True) + '\n')
    tmp.replace(path)


def corpus():
    """The 43 WP-4 programs: historical parity keys, three schematic cases, 13 Lox VM scripts."""
    historical = json.loads((TREE / 'experiments/perf-gc-dict-20260925/results.json').read_text())
    parity = {key.rsplit('|', 1)[0] for key in historical['samples'] if key.startswith('parity/')}
    chosen = [p for p in pc.programs() if p['id'] in parity or p['id'].startswith(('schematic/', 'lox/vm/'))]
    assert len(chosen) == 43, len(chosen)
    return chosen


def select(progs, only):
    keys = [k for k in (only or '').split(',') if k]
    return [p for p in progs if not keys or any(k in p['id'] for k in keys)]


def sized(prog, size):
    if prog['kind'] != 'lox' or size == 'full':
        return prog
    out = dict(prog)
    if size == 'smoke':
        out['size'] = json.loads((pc.LOX_BENCH / 'sizes.json').read_text())[prog['script']]['smoke']
    else:
        out['size'] = DEV_SIZE.get(prog['script'], max(1, prog['size'] // 5))
    return out


def lox_script(prog):
    scripts = WORK / 'lox-scripts'
    scripts.mkdir(parents=True, exist_ok=True)
    source = (pc.LOX_BENCH / 'scripts' / f"{prog['script']}.lox").read_text()
    first, rest = source.split('\n', 1)
    assert first.startswith('var N = ')
    path = scripts / f"{prog['script']}.n{prog['size']}.lox"
    if not path.exists():
        path.write_text(f"var N = {prog['size']};\n{rest}")
    return path


def run_spec(prog, binary, tag, declared):
    if prog['kind'] == 'lox':
        return {'argv': [str(binary), f"--engine={prog['engine']}", str(lox_script(prog))], 'env': pc.clean_env(),
                'cwd': str(WORK)}
    return pc.run_spec(prog, binary, tag, declared)


def binary_path(tag, prog, arm):
    return WORK / 'bin' / tag / f"{prog['build_key']}.{arm}"


# ------------------------------------------------------------------ setup / build

def command_setup(opts):
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / 'tmp').mkdir(exist_ok=True)
    if not (WORK / 'lox').exists():
        shutil.copytree(ACCEPTED / 'lox', WORK / 'lox', symlinks=True)
    gc_dir = WORK / 'bin' / 'gc'
    gc_dir.mkdir(parents=True, exist_ok=True)
    for f in (ACCEPTED / 'bin' / 'gc').iterdir():
        if not (gc_dir / f.name).exists():
            shutil.copy2(f, gc_dir / f.name)
    shutil.copy2(ACCEPTED / 'gc-builds.json', WORK / 'gc-builds.json')
    gc = json.loads((WORK / 'gc-builds.json').read_text())
    for key, build in gc['builds'].items():
        assert sha_file(gc_dir / key) == build['sha256'], ('GC baseline hash', key)
    print('setup ok:', len(gc['builds']), 'accepted GC binaries,', WORK)
    return 0


def declared(tag):
    path = WORK / 'bin' / tag / 'declared.json'
    return json.loads(path.read_text())['declared'] if path.exists() else None


def command_build(opts):
    compiler = str(Path(opts.compiler).resolve())
    progs = select(corpus(), opts.only)
    arms = opts.arms.split(',')
    if opts.runtime == 'gc':
        assert not (opts.sites or opts.stats), '--stats and --sites are RC builds'
        runtime = '--gc-runtime'
    else:
        runtime = '--rc-runtime=sites' if opts.sites else '--rc-runtime=stats' if opts.stats else '--rc-runtime'
    jobs = {}
    for prog in progs:
        for arm in arms:
            out = binary_path(opts.tag, prog, arm)
            key = out.name
            if key in jobs:
                continue
            cmd, cwd = pc.build_command(prog, compiler, arm, out, WORK / f'cache-{opts.tag}')
            cmd.append(runtime)
            jobs[key] = {'bin': out, 'cmd': [str(TREE / 'scripts/build-slot.sh'), 'build', *cmd], 'cwd': cwd}
    failed = 0
    started = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=opts.jobs) as pool:
        futures = {pool.submit(pc.do_build, job): key for key, job in jobs.items()}
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            print(('ok  ' if result['ok'] else 'FAIL'), futures[future], f"{result['seconds']}s", flush=True)
            if not result['ok']:
                failed += 1
                print(result['stderr'][-2000:])
    if any(p['kind'] == 'schematic' for p in progs):
        schematic = next(p for p in progs if p['kind'] == 'schematic')
        cmd, cwd = pc.emit_command(schematic, compiler)
        cmd.append(runtime)
        emitted = subprocess.run(cmd, cwd=cwd, env=pc.clean_env(), capture_output=True, timeout=1200)
        assert emitted.returncode == 0, emitted.stderr.decode()[-2000:]
        write_json(WORK / 'bin' / opts.tag / 'declared.json', {'declared': pc.declared_of(emitted.stdout)})
    write_json(WORK / 'bin' / opts.tag / 'compiler.json', {'compiler': compiler, 'sha256': sha_file(compiler),
                                                          'runtime': runtime})
    print(f'built {len(jobs) - failed}/{len(jobs)} in {time.time() - started:.0f}s')
    return 1 if failed else 0


# ------------------------------------------------------------------ measure

def perf_run(spec):
    """One execution: summed user instructions, stdout bytes, status, SVG bytes."""
    cpu = CPUS.get()
    try:
        with tempfile.NamedTemporaryFile(dir=WORK / 'tmp', suffix='.perf') as counts:
            cmd = ['taskset', '-c', cpu, 'perf', 'stat', '-x,', '-o', counts.name, '-e', 'instructions:u', '--',
                   *spec['argv']]
            try:
                done = subprocess.run(cmd, capture_output=True, env=spec['env'], cwd=spec['cwd'], timeout=pc.RUN_TIMEOUT)
            except subprocess.TimeoutExpired:
                return {'status': -9, 'instructions': None, 'stdout': b'', 'stderr': 'timeout'}
            counted = [int(f[0]) for f in (line.split(',') for line in Path(counts.name).read_text().splitlines())
                       if len(f) > 2 and 'instructions' in f[2] and f[0].isdigit()]
            assert len(counted) <= 1, ('pinned run counted on two PMUs', counted)
            total = counted[0] if counted else 0
    finally:
        CPUS.put(cpu)
    result = {'status': done.returncode, 'instructions': total or None, 'stdout': done.stdout,
              'stderr': done.stderr[-400:].decode(errors='replace')}
    if 'svg' in spec:
        result['svg'] = spec['svg'].read_bytes() if spec['svg'].exists() else b''
    return result


def fingerprint(result):
    h = hashlib.sha256(result['stdout'])
    if 'svg' in result:
        h.update(result['svg'])
    return h.hexdigest()


def gc_baseline(prog, arm, size, gc_declared, cache):
    binary = binary_path('gc', prog, arm)
    key = f"{prog['id']}|{arm}|{prog.get('size', '')}|{sha_file(binary)}"
    if key not in cache:
        tag = f"gc-{arm}-{prog['id'].replace('/', '_')}"
        result = perf_run(run_spec(prog, binary, tag, gc_declared))
        assert result['status'] == 0 and result['instructions'], (key, result['stderr'])
        if prog['kind'] == 'schematic':
            assert hashlib.sha256(result['svg']).hexdigest() == pc.SCHEMATIC_SVG[prog['case']], key
        elif size == 'full':
            assert result['stdout'] == Path(prog['expected_path']).read_bytes(), key
        cache[key] = {'instructions': result['instructions'], 'fingerprint': fingerprint(result)}
    return cache[key]


def geomean(values):
    return math.exp(sum(math.log(v) for v in values) / len(values)) if values else float('nan')


def command_measure(opts):
    progs = [sized(p, opts.size) for p in select(corpus(), opts.only)]
    arms = opts.arms.split(',')
    gc_state = json.loads((WORK / 'gc-builds.json').read_text())
    gc_declared = gc_state.get('schematic_declared')
    rc_declared = declared(opts.tag)
    cache_path = WORK / 'gc-cache.json'
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    pairs = [(p, a) for p in progs for a in arms]
    started = time.time()
    # GC first (cached after the first pass), then RC, both in parallel.
    with concurrent.futures.ThreadPoolExecutor(max_workers=opts.jobs) as pool:
        gc = dict(zip([(p['id'], a) for p, a in pairs],
                      pool.map(lambda pa: gc_baseline(pa[0], pa[1], opts.size, gc_declared, cache), pairs)))
    write_json(cache_path, cache)

    def rc_one(pa):
        prog, arm = pa
        binary = binary_path(opts.tag, prog, arm)
        if not binary.exists():
            return {'status': 'missing'}
        tag = f"{opts.tag}-{arm}-{prog['id'].replace('/', '_')}"
        return perf_run(run_spec(prog, binary, tag, rc_declared))
    with concurrent.futures.ThreadPoolExecutor(max_workers=opts.jobs) as pool:
        rc = dict(zip([(p['id'], a) for p, a in pairs], pool.map(rc_one, pairs)))
    rows, bad = [], []
    for prog, arm in pairs:
        g, r = gc[(prog['id'], arm)], rc[(prog['id'], arm)]
        if r.get('status') != 0 or not r.get('instructions') or fingerprint(r) != g['fingerprint']:
            bad.append((prog['id'], arm, r.get('status'), r.get('stderr', '')[-200:]))
            continue
        rows.append({'id': prog['id'], 'arm': arm, 'gc': g['instructions'], 'rc': r['instructions'],
                     'ratio': r['instructions'] / g['instructions']})
    by = {(r['id'], r['arm']): r for r in rows}
    print(f"{'program':42} {'qbe':>9} {'llvm':>9}")
    for prog in progs:
        cells = [f"{by[(prog['id'], a)]['ratio']:9.3f}" if (prog['id'], a) in by else f"{'FAIL':>9}" for a in arms]
        print(f"{prog['id']:42} " + ' '.join(cells))
    summary = {}
    for arm in arms:
        ratios = [r['ratio'] for r in rows if r['arm'] == arm]
        summary[arm] = {'geomean': geomean(ratios), 'rows': len(ratios), 'within_1_3': sum(x <= 1.3 for x in ratios),
                        'worst': max(ratios) if ratios else None}
        nonlox = [r['ratio'] for r in rows if r['arm'] == arm and not r['id'].startswith('lox/')]
        summary[arm]['geomean_nonlox'] = geomean(nonlox)
        s = summary[arm]
        print(f"{arm}: geomean {s['geomean']:.3f} (non-Lox {s['geomean_nonlox']:.3f})  <=1.3: {s['within_1_3']}/{s['rows']}"
              f"  worst {s['worst']:.2f}" if ratios else f'{arm}: no rows')
    for b in bad:
        print('FAIL', *b)
    print(f'{len(pairs)} pairs in {time.time() - started:.0f}s (size={opts.size})')
    out = Path(opts.out) if opts.out else WORK / f'results-{opts.tag}-{opts.size}.json'
    write_json(out, {'tag': opts.tag, 'size': opts.size, 'rows': rows, 'summary': summary,
                     'failures': [list(map(str, b)) for b in bad],
                     'compiler': json.loads((WORK / 'bin' / opts.tag / 'compiler.json').read_text())
                     if (WORK / 'bin' / opts.tag / 'compiler.json').exists() else None})
    print('wrote', out)
    return 1 if bad else 0


def command_counts(opts):
    progs = [sized(p, opts.size) for p in select(corpus(), opts.only)]
    rc_declared = declared(opts.tag)
    for prog in progs:
        binary = binary_path(opts.tag, prog, 'qbe')
        spec = run_spec(prog, binary, f"{opts.tag}-counts", rc_declared)
        done = subprocess.run(spec['argv'], capture_output=True, env=spec['env'], cwd=spec['cwd'], timeout=pc.RUN_TIMEOUT)
        line = [l for l in done.stderr.decode(errors='replace').splitlines() if l.startswith('MYLANG_RC_COUNTS')]
        counts = json.loads(line[-1].split(' ', 1)[1]) if line else {}
        ops = sum(v for k, v in counts.items() if isinstance(v, int) and k not in ('version',))
        print(f"{prog['id']:42} ops={ops:>12,} " + ' '.join(f"{k}={v}" for k, v in counts.items()
                                                          if isinstance(v, int) and v and k != 'version'))
    return 0


def command_sites(opts):
    """Run a --sites build once per program, keeping each MYLANG_RC_SITES report."""
    progs = [sized(p, opts.size) for p in select(corpus(), opts.only)]
    rc_declared = declared(opts.tag)
    out_dir = WORK / f'sites-{opts.tag}-{opts.size}'
    out_dir.mkdir(parents=True, exist_ok=True)
    for prog in progs:
        binary = binary_path(opts.tag, prog, 'qbe')
        spec = run_spec(prog, binary, f"{opts.tag}-sites", rc_declared)
        report = out_dir / f"{prog['id'].replace('/', '_')}.json"
        env = dict(spec['env'], MYLANG_RC_SITES=str(report), MYLANG_RC_SITES_TOP=str(opts.top))
        done = subprocess.run(spec['argv'], capture_output=True, env=env, cwd=spec['cwd'], timeout=pc.RUN_TIMEOUT)
        doc = json.loads(report.read_text()) if report.exists() else {'events': 0, 'calls': 0}
        print(f"{prog['id']:42} status={done.returncode} events={doc['events']:>12,} calls={doc['calls']:>12,} -> {report}")
        if opts.top:
            print(done.stderr.decode(errors='replace').split('MYLANG_RC_SITES ', 1)[-1])
    return 0


def command_compare(opts):
    a, b = (json.loads(Path(p).read_text()) for p in (opts.a, opts.b))
    ra = {(r['id'], r['arm']): r for r in a['rows']}
    for r in b['rows']:
        old = ra.get((r['id'], r['arm']))
        if old:
            print(f"{r['id']:42} {r['arm']:5} {old['ratio']:8.3f} -> {r['ratio']:8.3f}  ({r['rc'] / old['rc'] - 1:+.1%} instr)")
    for arm in b['summary']:
        if arm in a['summary']:
            print(f"{arm}: geomean {a['summary'][arm]['geomean']:.3f} -> {b['summary'][arm]['geomean']:.3f}")
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('setup')
    b = sub.add_parser('build')
    b.add_argument('--compiler', required=True)
    b.add_argument('--tag', required=True)
    b.add_argument('--only')
    b.add_argument('--arms', default='qbe,llvm')
    b.add_argument('--jobs', type=int, default=3)
    b.add_argument('--stats', action='store_true')
    b.add_argument('--sites', action='store_true')
    b.add_argument('--runtime', choices=('rc', 'gc'), default='rc',
                   help='gc builds the corpus with --gc-runtime (to compare two compilers\' collector code)')
    m = sub.add_parser('measure')
    m.add_argument('--tag', required=True)
    m.add_argument('--size', choices=('full', 'dev', 'smoke'), default='dev')
    m.add_argument('--only')
    m.add_argument('--arms', default='qbe,llvm')
    m.add_argument('--jobs', type=int, default=8)
    m.add_argument('--out')
    c = sub.add_parser('counts')
    c.add_argument('--tag', required=True)
    c.add_argument('--size', choices=('full', 'dev', 'smoke'), default='dev')
    c.add_argument('--only')
    t = sub.add_parser('sites')
    t.add_argument('--tag', required=True)
    t.add_argument('--size', choices=('full', 'dev', 'smoke'), default='dev')
    t.add_argument('--only')
    t.add_argument('--top', type=int, default=0)
    k = sub.add_parser('compare')
    k.add_argument('a')
    k.add_argument('b')
    opts = ap.parse_args()
    return {'setup': command_setup, 'build': command_build, 'measure': command_measure,
            'counts': command_counts, 'sites': command_sites, 'compare': command_compare}[opts.cmd](opts)


if __name__ == '__main__':
    sys.exit(main())
