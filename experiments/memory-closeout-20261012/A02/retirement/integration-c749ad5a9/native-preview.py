import argparse,hashlib,json,os,re,shutil,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source-root',type=Path,required=True);p.add_argument('--scratch',type=Path,required=True);args=p.parse_args()
here=Path(__file__).resolve().parent;root=args.source_root.resolve();scratch=args.scratch.resolve();base=json.loads((here/'manifest.json').read_text())['base_commit']
def sha(b):return hashlib.sha256(b).hexdigest()
def call(argv,env=None):
 r=subprocess.run(list(map(str,argv)),capture_output=True,text=True,env=env,timeout=90);return {'argv':list(map(str,argv)),'status':r.returncode,'stdout':r.stdout,'stderr':r.stderr}
assembly=scratch/'native';assembly.mkdir(exist_ok=False)
overlay=Path('/home/epentland/ai/canopy/mylang-memory-20261012-A05/.tmp/memory-closeout/A05/retirement-C3-c749ad5a9')
driver=subprocess.check_output(['git','show',base+':src/core/driver.zig'],cwd=root,text=True).split('pub const runtime_source =',1)[1].split('/// One build:',1)[0]
inputs={};sources={}
for name in re.findall(r'@embedFile\("([^\"]+)"\)',driver):
 rel='src/core/'+name
 if name in ['runtime/core_rt.c','runtime/core_bytes.c']:path=scratch/rel;b=path.read_bytes();origin='A02 unapplied retirement candidate'
 elif (overlay/Path(name).name).exists():path=overlay/Path(name).name;b=path.read_bytes();origin='A05 paired unapplied retirement candidate'
 else:b=subprocess.check_output(['git','show',base+':'+rel],cwd=root);origin='unchanged pinned integration source'
 inputs[rel]={'sha256':sha(b),'origin':origin};sources[rel]=b
runtime=b'\n'.join(sources.values());(assembly/'core_rt.c').write_bytes(runtime)
result={'scope':'Scratch A02/A05 runtime retirement preview; MYL_ZERO_RC still selects peer owned branches. Not C3 production qualification.','base_commit':base,'zig':os.environ['ZIG'],'zig_sha256':sha(Path(os.environ['ZIG']).read_bytes()),'runtime_sha256':sha(runtime),'inputs':inputs,'selectors_remaining':{n:[i+1 for i,line in enumerate(b.decode().splitlines()) if 'MYL_ZERO_RC' in line] for n,b in sources.items() if b'MYL_ZERO_RC' in b},'fixtures':{},'pass':True}
for name in ['capacity','owned']:
 source=assembly/(name+'.c');shutil.copyfile(here/(name+'-fixture.c'),source);binary=assembly/name
 row={'source_sha256':sha(source.read_bytes())};result['fixtures'][name]=row
 row['build']=call([os.environ['ZIG'],'cc','-O2','-std=c11','-pthread','-DMYL_ZERO_RC=1',source,'-o',binary]);row['runs']=[];row['pass']=row['build']['status']==0
 if row['pass']:
  row['binary_sha256']=sha(binary.read_bytes());nm=call(['nm',binary]);(here/(name+'.nm')).write_text(nm['stdout']);row['forbidden_symbols']=[x for x in ['myl_core_retain','myl_core_release','myl_core_share','count_is_unique'] if x in nm['stdout']];row['pass'] &= not row['forbidden_symbols']
  for scenario in range(13) if name=='capacity' else [None]:
   run=call([binary,*([str(scenario)] if scenario is not None else [])],dict(os.environ,MYL_CORE_LEAKCHECK='1'));row['runs'].append(run)
   expected_status=1 if scenario is not None and scenario!=0 else 0
   expected_out='preserved\n' if scenario==0 else 'owned layout copy rotate reverse transfer drop preserved\n' if scenario is None else ''
   expected_err='' if expected_status==0 else 'error[R_MEMORY_BUDGET]: memory budget exhausted; raise it with --max-memory=SIZE\n' if scenario==9 else 'fatal: out of memory\n'
   run['pass']=(run['status']==expected_status and run['stdout']==expected_out and run['stderr']==expected_err);row['pass'] &= run['pass']
 result['pass'] &= row['pass'];(here/'native-results.json').write_text(json.dumps(result,indent=2)+'\n');print(name,row['pass'],flush=True)
raise SystemExit(0 if result['pass'] else 1)
