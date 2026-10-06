#!/usr/bin/env python3
"""Reference dense, sparse, mixed-length and churn workloads with real emitted probes.

Run inside the build slot, serialized on the CPU10 lock. LLVM probe bodies are
extracted from installed compiler row emission, with external linkage solely for
LTO into the reference C workload. Hashes remain the production hashes for all
layouts; no old runtime is linked into the new dictionary implementation.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
REF = ROOT / 'experiments/new-core-s2-design-20261005/dict-layout'
SCRATCH = ROOT / '.mylang-cache/s2-d/layout'
SCRATCH.mkdir(parents=True, exist_ok=True)

def run(argv, **kw):
    subprocess.run(list(map(str, argv)), check=True, **kw)

for row in ('dict_lookup', 'dict_lookup_str'):
    run([ROOT / 'zig-out/bin/mylang-core', 'build', ROOT / f'test/core/row_{row}.my',
         '-o', SCRATCH / row, '--release', '--emit-llvm', SCRATCH / f'{row}.ll',
         '--link', ROOT / 'benchmarks/runtime/ports/native_clock.c', '--cache-dir', SCRATCH / 'guest-cache'])
text = (SCRATCH / 'dict_lookup.ll').read_text() + (SCRATCH / 'dict_lookup_str.ll').read_text()
probes = re.findall(r'^define internal i64 (@myl\.dict\.\d+)\.find\(.*?^\}', text, re.M | re.S)
# The regex above identifies symbols; isolate full function definitions separately.
functions = re.findall(r'^define internal i64 @myl\.dict\.\d+\.find\(.*?^\}', text, re.M | re.S)
chosen = {}
for function in functions:
    kind = 's' if '%stored = load ptr' in function else 'i'
    if kind not in chosen:
        chosen[kind] = re.sub(r'define internal i64 @myl\.dict\.\d+\.find', f'define i64 @core_probe_{kind}', function, count=1)
if set(chosen) != {'i', 's'}:
    raise SystemExit('could not isolate both production probes')
(SCRATCH / 'probe.ll').write_text('declare i32 @llvm.cttz.i32(i32, i1)\ndeclare i64 @myl_core_dict_find(ptr, ptr, i64)\ndeclare zeroext i1 @myl_core_str_eq(ptr, ptr)\n' + '\n'.join(chosen.values()) + '\n')
common = (REF / 'common.h').read_text()
common = re.sub(r'static inline uint64_t str_hash\(Str \*s\) \{.*?\n\}',
                'static inline uint64_t str_hash(Str *s) { return dict_hash_bits(myl_core_str_hash((myl_block *)s)); }', common, flags=re.S)
(SCRATCH / 'common.h').write_text(common.replace('str_new(', 'bench_str_new('))
source = (REF / 'bench.c').read_text()
runtime = '\n'.join(f'#include "{ROOT / "src/core/runtime" / name}"' for name in ('core_rt.c', 'core_dict.c', 'core_text.c', 'core_sort.c'))
source = source.replace('#include "common.h"', runtime + '\nconst myl_core_site myl_core_sites[1] = {{0}};\nconst char myl_core_source_path[] = "layout-probe";\n#include "common.h"')
source = source.replace('#define PFX hyb_i\n#include "layout_hybrid.h"', '#define PFX hyb_i\n#define CORE_KEY_KIND 0\n#define CORE_PROBE core_probe_i\n#include "' + str(HERE / 'real_hybrid.h') + '"\n#undef CORE_KEY_KIND\n#undef CORE_PROBE')
source = source.replace('#define PFX hyb_s\n#include "layout_hybrid.h"', '#define PFX hyb_s\n#define CORE_KEY_KIND 2\n#define CORE_PROBE core_probe_s\n#include "' + str(HERE / 'real_hybrid.h') + '"\n#undef CORE_KEY_KIND\n#undef CORE_PROBE')
source = source.replace('str_new(', 'bench_str_new(')
source = source.replace('word->hash = 0;', 'word->hash = 0; word->kind &= ~MYL_TEXT_HASHED;')
source = source.replace('"hybrid"', '"emitted"')
(SCRATCH / 'bench.c').write_text(source)
run(['zig', 'cc', '-O3', '-march=native', '-flto', '-I', REF, SCRATCH / 'bench.c', SCRATCH / 'probe.ll', '-o', SCRATCH / 'bench'])
print('# Production Core runtime + extracted LLVM alwaysinline probe; zig cc -O3 -march=native -flto; CPU10', flush=True)
for size in (64, 4096, 65536):
    run(['taskset', '-c', '10', SCRATCH / 'bench', size, sys.argv[1] if len(sys.argv) > 1 else '7'])
