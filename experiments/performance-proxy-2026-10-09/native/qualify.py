import json, os, shutil, subprocess, time
from pathlib import Path
import argparse
parser=argparse.ArgumentParser(description="Native Juice collector smoke qualification; run through build-slot.sh build")
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--compiler', type=Path, default=Path(__file__).resolve().parents[3]/'zig-out/bin/mylang')
parser.add_argument('--valgrind', default=os.environ.get('JUICE_VALGRIND','valgrind'))
args=parser.parse_args()
root=Path(__file__).resolve().parents[3]
out=args.output.resolve()
out.mkdir(parents=True,exist_ok=False)
exe=args.compiler.resolve()
vg=args.valgrind
results={'scope':'native CLI smoke tests; no elapsed-time calibration','records':{},'checks':{}}
def run(*args):
 p=subprocess.run([str(exe),'juice',*map(str,args)],capture_output=True,text=True)
 print(p.stderr+p.stdout,flush=True)
 p.check_returncode()
 return p
def record(project,name,collector='perf',static=False):
 args=['record',project/'juice.toml','--name',name,'--cache-dir',out/'cache','--collector',collector,'--repeats','2']
 if collector!='perf':args+=['--valgrind',vg]
 if static:args+=['--static']
 start=time.monotonic();p=run(*args);record_path=Path(p.stdout.strip())
 results['records'][name]={'path':str(record_path.relative_to(out)),'diagnostic_seconds':time.monotonic()-start}
 return record_path,json.loads(record_path.read_text())
def compare(a,b,name,mode='application'):
 path=out/(name+'.json');run('compare',a,b,'--mode',mode,'--output',path)
 return json.loads(path.read_text())
native=out/'native';shutil.copytree(root/'examples/juice/native',native)
a,ad=record(native,'native-base')
b,bd=record(native,'native-repeat')
same=compare(a,b,'identical')
results['checks']['perf_repeat']=all(v['direction']=='unchanged' for v in same['workloads'].values())
source=native/'kernel.c';source.write_text(source.read_text().replace('#define SLOW 1','#define SLOW 0'))
c,cd=record(native,'native-improved')
change=compare(a,c,'algorithm-improvement')
results['checks']['perf_algorithm']=all(v['juice']<50 for v in change['workloads'].values())
for kind in ('callgrind','cachegrind'):
 path,data=record(native,kind,kind)
 cell=next(iter(data['workloads'].values()))
 results['checks'][kind]=cell['metrics']['instructions']['median']>0 and bool(cell['functions']) and bool(cell['lines'])
my=out/'mylang';shutil.copytree(root/'examples/juice/mylang',my)
a,ad=record(my,'mylang-base',static=True)
program=(my/'main.my').read_text();start=program.index('    values: list[int]');end=program.index('\ndef number(')
replacement='    result = 0\n    for i in range(count):\n        result += i % 97\n    return result\n'
(my/'main.my').write_text(program[:start]+replacement+'\n'+program[end:])
b,bd=record(my,'mylang-improved',static=True)
change=compare(a,b,'mylang-improvement')
results['checks']['mylang_counters']=all(v['semantic']['status']=='compatible' and v['semantic']['totals']['allocs']['candidate']<v['semantic']['totals']['allocs']['base'] for v in change['workloads'].values())
results['checks']['mylang_static']=ad['build']['static_cost']['version']=='cost-v1'
results['checks']['self_compiler']=ad['build_config']['compiler']['path']==str(exe)
(out/'qualification.json').write_text(json.dumps(results,indent=2)+'\n')
assert all(results['checks'].values()),results
