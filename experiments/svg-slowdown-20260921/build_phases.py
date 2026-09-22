#!/usr/bin/env python3
"""Link low-frequency phase timers around otherwise unchanged guest objects."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
WORK = ROOT / '.tmp/svg-slowdown-20260921/phases'
BASE = ROOT / '.tmp/full-svg-benchmark-20260921'
SPECS = {'main::main': ('pair', 2), 'sexpr::parse': ('pair', 3),
         'schematic::build': ('six', 5), 'svg::render': ('uint64_t', 3),
         'layout::build': ('uint64_t', 4), 'layout_routes::build': ('uint64_t', 6)}


def run(args):
    p = subprocess.run(list(map(str, args)), capture_output=True, text=True, cwd=ROOT)
    if p.returncode:
        raise RuntimeError(f'{args[:5]} ...\n{p.stdout}\n{p.stderr}')
    return p.stdout


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    records = {}
    for arm in ('mylang-o3', 'mylang-o3-bounded'):
        receipt = json.loads((BASE / (arm + '.qbe-manifest.json')).read_text())
        funcs = {f['name']: f for f in receipt['functions']}
        guests = [Path(f['object']) for f in receipt['functions']]
        extras = [p for p in guests[0].parent.glob('*.o') if p not in guests]
        assert len(extras) == 2
        cache = 'mylang-cache-bounded' if arm.endswith('bounded') else 'mylang-cache'
        assets = next((BASE / cache / 'runtime').iterdir())
        provider = WORK / (arm + '-provider.o')
        run(['zig', 'cc', '-O3', '-fPIC', '-ffunction-sections', '-fdata-sections',
             '-I', assets, '-c', ROOT / 'src/schematic/native_schematic.c', '-o', provider])
        text = '''#define _POSIX_C_SOURCE 200809L
#include "qbe_runtime.h"
#include <stdio.h>
#include <time.h>
typedef struct { uint64_t a,b; } pair;
typedef struct { uint64_t a,b,c,d,e,f; } six;
static uint64_t now(void) { struct timespec t; clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t); return (uint64_t)t.tv_sec*1000000000+t.tv_nsec; }
extern void __real_myl_native_heap_destroy(myl_native_heap *);
void __wrap_myl_native_heap_destroy(myl_native_heap *h) {
 fprintf(stderr,"HEAP allocations=%zu collections=%zu live=%zu bytes=%zu\\n",h->allocations,h->collections,h->objects_live,h->bytes);
 __real_myl_native_heap_destroy(h);
}
'''
        wraps = ['myl_native_heap_destroy']
        for name, (result, count) in SPECS.items():
            symbol = funcs[name]['symbol']
            params = ','.join(f'uint64_t a{i}' for i in range(count))
            args = ','.join(f'a{i}' for i in range(count))
            text += f'extern {result} __real_{symbol}({params});\n'
            text += f'{result} __wrap_{symbol}({params}) {{\n'
            text += ' MylQbeContext *ctx=(MylQbeContext *)(uintptr_t)a0;\n'
            text += ' size_t ac=ctx->heap.allocations, gc=ctx->heap.collections; uint64_t steps=ctx->steps, begin=now();\n'
            text += f' {result} result=__real_{symbol}({args});\n'
            text += ' uint64_t elapsed=now()-begin;\n'
            text += f' fprintf(stderr,"PHASE {name} ns=%llu allocations=%zu collections=%zu steps=%llu heap_bytes=%zu objects_live=%zu\\n",(unsigned long long)elapsed,ctx->heap.allocations-ac,ctx->heap.collections-gc,(unsigned long long)(ctx->steps-steps),ctx->heap.bytes,ctx->heap.objects_live);\n'
            text += ' return result;\n}\n'
            wraps.append(symbol)
        source = WORK / (arm + '-wrappers.c')
        source.write_text(text)
        obj = source.with_suffix('.o')
        run(['zig', 'cc', '-O3', '-fPIC', '-I', assets, '-c', source, '-o', obj])
        common = ['cc', '-no-pie', '-O3', '-fPIC', *guests, *extras, provider,
                  receipt['runtime_object'], '-lm', '-Wl,--gc-sections']
        control = WORK / (arm + '-control')
        run([*common, '-o', control])
        probe = WORK / (arm + '-phases')
        run([*common, obj, *[f'-Wl,--wrap={w}' for w in wraps], '-o', probe])
        records[arm] = {'control': str(control), 'probe': str(probe),
                        'guest_objects_reused_unchanged': len(guests),
                        'runtime_archive': receipt['runtime_object'],
                        'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                        'probe_sha256': hashlib.sha256(probe.read_bytes()).hexdigest()}
    (OUT / 'phase-builds.json').write_text(json.dumps(records, indent=2) + '\n')
    print(json.dumps(records, indent=2))


if __name__ == '__main__':
    main()
