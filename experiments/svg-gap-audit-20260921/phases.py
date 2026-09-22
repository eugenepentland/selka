#!/usr/bin/env python3
"""Coarse CPU phase diagnostics with matched relink controls, outside main timings."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import random
import statistics
import subprocess

from audit import ROOT, OUT, WORK, CURRENT, invoke, sha, SEED

SPECS = {'main::main': ('pair', 2), 'sexpr::parse': ('pair', 3),
         'schematic::build': ('six', 5), 'svg::render': ('uint64_t', 3),
         'layout::build': ('uint64_t', 4), 'layout_routes::build': ('uint64_t', 6)}
NAMES = ('gc-o3', 'gc-bounded', 'arena-o3')


def command(args):
    result = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True, text=True)
    assert result.returncode == 0, (args, result.stderr)


def build():
    folder = WORK / 'phases'
    folder.mkdir(exist_ok=True)
    records = {}
    for arm in NAMES:
        receipt = json.loads(Path(str(CURRENT / arm) + '.qbe-manifest.json').read_text())
        functions = {f['name']: f for f in receipt['functions']}
        guests = [Path(f['object']) for f in receipt['functions']]
        extras = [p for p in guests[0].parent.glob('*.o') if p not in guests]
        assert len(extras) == 2
        candidates = [p for p in (CURRENT / f'cache-{arm}/runtime').iterdir()
                      if all((p / unit).exists() and (p / unit).read_bytes() == (ROOT / 'src' / unit).read_bytes()
                             for unit in ('qbe_runtime.c', 'qbe_runtime.h', 'native_heap.c', 'native_heap.h',
                                          'native_arena.c', 'native_regions.c', 'qbe_arena.c'))]
        assert len(candidates) == 1, candidates
        assets = candidates[0]
        provider = folder / f'{arm}-provider.o'
        command(['zig', 'cc', '-O3', '-fPIC', '-ffunction-sections', '-fdata-sections',
                 '-I', assets, '-c', ROOT / 'src/schematic/native_schematic.c', '-o', provider])
        source = '''#define _POSIX_C_SOURCE 200809L
#include "qbe_runtime.h"
#include <stdio.h>
#include <time.h>
typedef struct { uint64_t a,b; } pair;
typedef struct { uint64_t a,b,c,d,e,f; } six;
static uint64_t now(void) { struct timespec t; clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t); return (uint64_t)t.tv_sec*1000000000+t.tv_nsec; }
'''
        wraps = []
        for name, (result, count) in SPECS.items():
            symbol = functions[name]['symbol']
            params = ','.join(f'uint64_t a{i}' for i in range(count))
            args = ','.join(f'a{i}' for i in range(count))
            source += f'extern {result} __real_{symbol}({params});\n'
            source += f'{result} __wrap_{symbol}({params}) {{\n'
            source += ' MylQbeContext *ctx=(MylQbeContext *)(uintptr_t)a0;\n'
            source += ' size_t ac=ctx->heap.allocations, gc=ctx->heap.collections; uint64_t steps=ctx->steps, begin=now();\n'
            source += f' {result} result=__real_{symbol}({args});\n'
            source += ' uint64_t elapsed=now()-begin;\n'
            source += f' fprintf(stderr,"PHASE {name} ns=%llu allocations=%zu collections=%zu steps=%llu heap_bytes=%zu objects_live=%zu\\n",(unsigned long long)elapsed,ctx->heap.allocations-ac,ctx->heap.collections-gc,(unsigned long long)(ctx->steps-steps),ctx->heap.bytes,ctx->heap.objects_live);\n'
            source += ' return result;\n}\n'
            wraps.append(symbol)
        path = folder / f'{arm}-wrappers.c'
        path.write_text(source)
        saved = OUT / f'phase-{arm}-wrappers.c'
        saved.write_text(source)
        obj = path.with_suffix('.o')
        command(['zig', 'cc', '-O3', '-fPIC', '-I', assets, '-c', path, '-o', obj])
        common = ['cc', '-no-pie', '-O3', '-fPIC', *guests, *extras, provider, receipt['runtime_object'], '-lm', '-Wl,--gc-sections']
        control, probe = folder / f'{arm}-control', folder / f'{arm}-probe'
        command([*common, '-o', control])
        command([*common, obj, *[f'-Wl,--wrap={w}' for w in wraps], '-o', probe])
        for binary in (control, probe):
            for case in ('fixture', 'changed-net', 'changed-value'):
                invoke(binary, case, bounded=arm.endswith('bounded'), diagnostic=binary == probe)
            invoke(binary, bounded=arm.endswith('bounded'), extra=('--gc-stress',), diagnostic=binary == probe)
        records[arm] = {'control': str(control), 'probe': str(probe), 'control_sha256': sha(control),
                        'probe_sha256': sha(probe), 'runtime_sha256': sha(receipt['runtime_object']),
                        'guest_objects_reused_unchanged': len(guests), 'source_sha256': sha(path),
                        'original_sha256': sha(CURRENT / arm), 'exact_svg_and_stress_qualified': True}
    (OUT / 'phase-builds.json').write_text(json.dumps(records, indent=2) + '\n')


def measure():
    builds = json.loads((OUT / 'phase-builds.json').read_text())
    rng = random.Random(SEED)
    rows = []
    for number in range(-3, 31):
        jobs = [(name, kind) for name in NAMES for kind in ('original', 'control', 'probe')]
        rng.shuffle(jobs)
        for name, kind in jobs:
            binary = CURRENT / name if kind == 'original' else Path(builds[name][kind])
            assert sha(binary) == builds[name][f'{kind}_sha256']
            elapsed, stderr, _ = invoke(binary, bounded=name.endswith('bounded'), diagnostic=kind == 'probe')
            phases = []
            for line in stderr.splitlines():
                assert line.startswith('PHASE '), line
                tokens = line.split()
                phases.append({'name': tokens[1], **{k: int(v) for k, v in (t.split('=') for t in tokens[2:])}})
            if kind == 'probe':
                assert len(phases) == 8, (name, phases)
            if number >= 0:
                rows.append({'round': number, 'arm': name, 'kind': kind, 'wall_ms': elapsed, 'phases': phases})
    summary = {}
    for name in NAMES:
        values = defaultdict(list)
        entries = []
        for row in rows:
            if row['arm'] != name or row['kind'] != 'probe':
                continue
            inclusive = defaultdict(int)
            for phase in row['phases']:
                inclusive[phase['name']] += phase['ns']
            exclusive = {'parse': inclusive['sexpr::parse'], 'model': inclusive['schematic::build'],
                         'placement': inclusive['layout::build'], 'routing': inclusive['layout_routes::build'],
                         'svg_emission': inclusive['svg::render'] - inclusive['layout::build'] - inclusive['layout_routes::build'],
                         'guest_total': inclusive['main::main']}
            for phase, duration in exclusive.items():
                values[phase].append(duration / 1e6)
            entries = row['phases']
        summary[name] = {'median_cpu_ms': {key: statistics.median(v) for key, v in values.items()},
                         'counts_example': entries,
                         'median_wall_ms': {kind: statistics.median(row['wall_ms'] for row in rows if row['arm'] == name and row['kind'] == kind)
                                            for kind in ('original', 'control', 'probe')}}
    result = {'method': 'Coarse linker wrappers around six guest functions (parser called three times), unchanged non-LTO guest objects/runtime, CPU clock; nested placement/routing subtracted from SVG. System-linker controls calibrated in randomized interleaved rounds. Not an exact decomposition of LTO wall-time.',
              'summary': summary, 'rounds': 31, 'warmups': 3, 'cpu': 6, 'samples': rows}
    (OUT / 'phases.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('build', 'measure'))
    args = parser.parse_args()
    {'build': build, 'measure': measure}[args.action]()
