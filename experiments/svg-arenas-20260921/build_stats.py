#!/usr/bin/env python3
"""Relink guest objects against a privately instrumented exact-stat runtime."""
import hashlib,json,shutil,subprocess
from pathlib import Path
from run import ARMS,OUT,ROOT,WORK
STATS_ARMS=('gc-o3','arena-o3')
UNITS=('qbe_runtime.c','native_heap.c','native_arena.c','native_collections.c','native_text.c','native_dictionary.c','qbe_stack.c','qbe_providers.c','qbe_resources.c','native_equal.c','native_bytes.c','qbe_bytes.c','native_regions.c','qbe_arena.c','native_print.c','qbe_io.c','native_scoped.c','qbe_grants.c','qbe_files.c','native_text_methods.c')
def run(argv):
 p=subprocess.run(list(map(str,argv)),cwd=ROOT,capture_output=True,text=True)
 if p.returncode: raise RuntimeError(f'{argv}\n{p.stdout}\n{p.stderr}')
def relink(name,manifest_path,provider):
 receipt=json.loads(Path(manifest_path).read_text()); guests=[Path(x['object']) for x in receipt['functions']]; assert all(p.exists() for p in guests)
 extras=[p for p in guests[0].parent.glob('*.o') if p not in guests]; assert len(extras)==2,(name,extras)
 cache=WORK/(f'cache-{name}' if not name.startswith('workload-') else f'workload-cache-{name.removeprefix("workload-")}')
 candidates=[path for path in (cache/'runtime').iterdir()
             if all((path/u).exists() and (path/u).read_bytes()==(ROOT/'src'/u).read_bytes() for u in UNITS)]
 assert len(candidates)==1, f'{name}: expected one cache runtime matching current production, got {candidates}'
 original=candidates[0]; assets=WORK/f'stats-runtime-{name}'
 if assets.exists(): shutil.rmtree(assets)
 shutil.copytree(original,assets)
 heap=assets/'native_heap.c'; text=heap.read_text(); include='#include "native_heap.h"\n'; assert text.count(include)==1
 text=text.replace(include,include+'extern void myl_stats_observe(myl_native_heap *);\n')
 text=text.replace('    heap->bytes += bytes;\n    heap->objects_live++;', '    heap->bytes += bytes;\n    myl_stats_observe(heap);\n    heap->objects_live++;'); heap.write_text(text)
 arena=assets/'native_arena.c'; text=arena.read_text(); include='#include "native_arena.h"\n'; assert text.count(include)==1
 text=text.replace(include,include+'extern void myl_stats_observe(myl_native_heap *);\n')
 needle='    if (heap->arena.reserved_bytes > heap->arena.peak_reserved_bytes)\n        heap->arena.peak_reserved_bytes = heap->arena.reserved_bytes;'
 assert text.count(needle)==1; arena.write_text(text.replace(needle,needle+'\n    myl_stats_observe(heap);'))
 runtime=assets/'qbe_runtime.c'; text=runtime.read_text(); include='#include "qbe_runtime.h"\n'; assert text.count(include)==1
 text=text.replace(include,include+'extern void myl_stats_report(myl_native_heap *);\n')
 needle='    if (!exit_without_sweep) myl_native_heap_destroy(&context->heap);'; assert text.count(needle)==1
 runtime.write_text(text.replace(needle,'    myl_stats_report(&context->heap);\n'+needle))
 merged=WORK/f'{name}-stats-runtime.o'; archive=WORK/f'{name}-stats-runtime.a'
 for stale in (merged,archive,WORK/f'stats-{name}'):
  if stale.exists(): stale.unlink()
 run(['zig','build-obj','-fPIC','-lc','-OReleaseFast','-I',assets,'-cflags','-std=c11','-O3','-g0','-fno-ident','-ffunction-sections','-fdata-sections','--',*[assets/u for u in UNITS],f'-femit-bin={merged}'])
 run(['zig','ar','rcs',archive,merged])
 symbols=subprocess.run(['nm','-u',merged],cwd=ROOT,capture_output=True,text=True,check=True).stdout
 assert 'myl_stats_observe' in symbols and 'myl_stats_report' in symbols
 stats=WORK/f'{name}-stats-report.o'; run(['zig','cc','-O3','-fPIC','-I',assets,'-c',OUT/'heap_stats_runtime.c','-o',stats])
 objects=[*guests,*extras]
 if provider:
  provider_o=WORK/f'{name}-provider.o'; run(['zig','cc','-O3','-fPIC','-I',assets,'-c',ROOT/'src/schematic/native_schematic.c','-o',provider_o]); objects.append(provider_o)
 output=WORK/f'stats-{name}'; run(['cc','-no-pie','-O3','-fPIC',*objects,archive,stats,'-lm','-Wl,--gc-sections','-o',output])
 return {'binary':str(output),'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'private_runtime':str(archive),'guest_objects_reused':len(guests)}
def main():
 records={name:relink(name,str(ARMS[name])+'.qbe-manifest.json',True) for name in STATS_ARMS}
 for policy in ('gc','arena'):
  name=f'workload-{policy}';records[name]=relink(name,str(WORK/name)+'.qbe-manifest.json',False)
 (OUT/'stats-builds.json').write_text(json.dumps(records,indent=2)+'\n')
if __name__=='__main__':main()
