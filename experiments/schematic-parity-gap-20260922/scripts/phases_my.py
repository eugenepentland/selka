#!/usr/bin/env python3
"""Per-phase CPU timing of the non-LTO O3 mylang schematic arm through linker --wrap interposition.

phases_my.py build   -> relinks arms/o3's own objects twice: control (no wrappers) and probe (wrappers)
phases_my.py measure -> interleaved rounds; prints per-phase median ns and wall medians for original/control/probe
"""
import json, os, random, re, statistics, subprocess, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bench_svg

W = Path(os.environ.get('AUDIT_WORK', '/home/epentland/ai/canopy/mylang/.tmp/perf-audit-20260922'))
TREE = Path(os.environ.get('AUDIT_TREE', str(W / 'tree')))
CPU = os.environ.get('BENCH_CPU', '6')
ARM = os.environ.get('PHASES_ARM', 'o3')
OUT = W / ('phases' if ARM == 'o3' else 'phases-' + ARM)
PHASES = ['main::main', 'io::load', 'sexpr::parse', 'schematic::build', 'circuit::collectPins', 'circuit::normalize',
          'validate::model', 'ports::collect', 'svg::render', 'layout::build', 'layout_graph::build', 'layout_routes::build', 'io::flush']


def sh(cmd, **kw):
    r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise SystemExit(f'failed: {" ".join(str(c) for c in cmd)}\n{r.stderr[-3000:]}')
    return r


def signatures():
    m = json.loads((W / 'arms/gc-lto-emitted.json').read_text())
    out = {}
    for f in m['functions']:
        if f['name'] not in PHASES:
            continue
        il = f['il']
        hdr = next(l for l in il.split('\n') if l.startswith('export function') or l.startswith('function '))
        mm = re.match(r'(?:export )?function (\S+) \$(\w+)\((.*)\) \{', hdr)
        ret, sym, params = mm.groups()
        count = len([p for p in params.split(',') if p.strip()])
        if ret.startswith(':'):
            tl = next(l for l in il.split('\n') if l.startswith(f'type {ret} '))
            size = int(re.search(r'\{ b (\d+) \}', tl).group(1))
            ctype = f'struct s{size}'
        else:
            ctype = {'l': 'uint64_t', 'w': 'uint32_t', 'd': 'double'}[ret]
        out[f['name']] = (sym, ctype, count)
    return out


def build():
    OUT.mkdir(exist_ok=True)
    receipt = json.loads((W / f'arms/{ARM}.qbe-manifest.json').read_text())
    objects = [Path(f['object']) for f in receipt['functions']]
    folder = objects[0].parent
    extras = sorted(p for p in folder.glob('*.o') if p not in objects)
    assert len(extras) == 2, extras
    runtime_dirs = list((W / f'arms/cache-{ARM}/runtime').iterdir())
    assert len(runtime_dirs) == 1, runtime_dirs
    headers = runtime_dirs[0]
    provider = OUT / 'provider.o'
    sh(['zig', 'cc', '-O3', '-fPIC', '-ffunction-sections', '-fdata-sections', '-I', headers, '-c', TREE / 'src/schematic/native_schematic.c', '-o', provider])
    sigs = signatures()
    src = ['#define _POSIX_C_SOURCE 200809L', '#include <stdint.h>', '#include <stdio.h>', '#include <time.h>',
           'struct s16 { uint64_t a,b; }; struct s24 { uint64_t a,b,c; }; struct s48 { uint64_t a,b,c,d,e,f; };',
           'static uint64_t now(void){ struct timespec t; clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t); return (uint64_t)t.tv_sec*1000000000u+(uint64_t)t.tv_nsec; }']
    wraps = []
    for name, (sym, ctype, count) in sigs.items():
        params = ','.join(f'uint64_t a{i}' for i in range(count))
        args = ','.join(f'a{i}' for i in range(count))
        src.append(f'extern {ctype} __real_{sym}({params});')
        src.append(f'{ctype} __wrap_{sym}({params}) {{ uint64_t b=now(); {ctype} r=__real_{sym}({args}); uint64_t e=now();'
                   f' fprintf(stderr,"PHASE {name} ns=%llu\\n",(unsigned long long)(e-b)); return r; }}')
        wraps.append(sym)
    (OUT / 'wrappers.c').write_text('\n'.join(src) + '\n')
    sh(['zig', 'cc', '-O3', '-fPIC', '-c', OUT / 'wrappers.c', '-o', OUT / 'wrappers.o'])
    common = ['cc', '-no-pie', '-O3', '-fPIC', *objects, *extras, provider, receipt['runtime_object'], '-lm', '-Wl,--gc-sections']
    sh([*common, '-o', OUT / 'control'])
    sh([*common, OUT / 'wrappers.o', *[f'-Wl,--wrap={w}' for w in wraps], '-o', OUT / 'probe'])
    declared = (W / f'arms/{ARM}.declared').read_text()
    for name in ('control', 'probe'):
        (OUT / f'{name}.declared').write_text(declared)
    print('built', OUT / 'control', OUT / 'probe', 'wrapped', len(wraps))


def invoke(binary, declared, case='fixture'):
    arm = {'binary': str(binary), 'kind': 'mylang', 'bounded': False, 'declared': declared}
    project = bench_svg.BASE / 'projects' / case
    output, issue = bench_svg.WORK / 'phase.svg', bench_svg.WORK / 'phase.issue'
    output.write_bytes(b''); issue.write_bytes(b'')
    env = bench_svg.clean_env()
    docs = [str(project / p) for p in bench_svg.DOCS]
    env.update(MYLANG_SCHEMATIC_DECLARED=declared, MYLANG_SCHEMATIC_OUTPUT=str(output), MYLANG_SCHEMATIC_ISSUE=str(issue))
    env.update({f'MYLANG_SCHEMATIC_INPUT_{i}': p for i, p in enumerate(docs)})
    started = time.perf_counter_ns()
    r = subprocess.run(['taskset', '-c', CPU, str(binary), '--print-result'], env=env, capture_output=True, timeout=60)
    elapsed = (time.perf_counter_ns() - started) / 1e6
    assert r.returncode == 0 and r.stdout == b'0\n' and not issue.read_bytes(), (binary, r)
    digest = bench_svg.sha(output.read_bytes())
    phases = {}
    for line in r.stderr.decode().splitlines():
        assert line.startswith('PHASE '), line
        _, name, ns = line.split()
        phases.setdefault(name, []).append(int(ns.split('=')[1]))
    return elapsed, digest, phases


def measure(rounds=31, warmups=3):
    declared = (W / f'arms/{ARM}.declared').read_text()
    arms = {'original': W / f'arms/{ARM}', 'control': OUT / 'control', 'probe': OUT / 'probe', 'gc-lto': W / 'arms/gc-lto'}
    ref = invoke(arms['original'], declared)[1]
    for name, b in arms.items():
        assert invoke(b, declared)[1] == ref, name
    rng = random.Random(20260922)
    rows = []
    for number in range(-warmups, rounds):
        order = list(arms); rng.shuffle(order)
        row = {}
        for name in order:
            elapsed, digest, phases = invoke(arms[name], declared)
            assert digest == ref
            row[name] = {'wall_ms': elapsed, 'phases': phases}
        if number >= 0:
            rows.append(row)
    summary = {'wall_median_ms': {n: statistics.median(r[n]['wall_ms'] for r in rows) for n in arms}}
    phase_medians = {}
    for phase in PHASES:
        totals = [sum(r['probe']['phases'].get(phase, [0])) for r in rows]
        calls = rows[0]['probe']['phases'].get(phase, [])
        phase_medians[phase] = {'median_inclusive_us': statistics.median(totals) / 1000, 'calls': len(calls)}
    summary['phases'] = phase_medians
    (OUT / 'phases.json').write_text(json.dumps({'summary': summary, 'rows': rows}, indent=1) + '\n')
    print(json.dumps(summary['wall_median_ms'], indent=1))
    for phase, v in phase_medians.items():
        print(f"  {phase:24s} {v['median_inclusive_us']:9.1f} us  ({v['calls']} calls)")


if __name__ == '__main__':
    {'build': build, 'measure': measure}[sys.argv[1]]()
