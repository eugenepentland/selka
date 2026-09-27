"""Sample exact joined production binaries only after matched medians finish."""
import collections,gzip,hashlib,importlib.util,json,os,subprocess
from pathlib import Path

root=Path.cwd();work=root/'.tmp-mut-argument/joined-flat-measure'
measure=json.loads((work/'results.json').read_text())
assert len(measure['counts'])==8 and all('medians' in row for row in measure['samples'].values())
os.environ['PC_WORK']=str(work);os.environ['TMPDIR']=str(work)
spec=importlib.util.spec_from_file_location('pc',root/'experiments/perf-gc-dict-20260925/scripts/pc.py')
pc=importlib.util.module_from_spec(spec);spec.loader.exec_module(pc)
pc.LOX_PORT=work/'lox-guest';pc.LOX_BENCH=root.parent/'d9-rc-performance/.tmp-rc-performance/lox/bench'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
path=work/'profiles-lowrate.json';result=json.loads(path.read_text()) if path.exists() else {'identity':measure['identity'],'profiles':{}}
assert result['identity']==measure['identity']
def save():path.write_text(json.dumps(result,indent=2)+'\n')
for backend in ('qbe','llvm'):
 for program in [p for p in measure['identity']['programs'] if p['id'] in ('schematic/fixture','lox/vm/binary_trees')]:
  label=program['build_key']+'-'+backend;binary=work/(label+'-production')
  assert sha(binary)==measure['builds'][label+'-production']['sha256']
  if label in result['profiles']:continue
  run=pc.run_spec(program,binary,'profile-'+label,measure['declared'])
  data=work/(label+'-lowrate.data')
  period='20000033'
  argv=run['argv']
  if program['kind']=='schematic':argv=['python3',str(root/'experiments/d9-rc-flat-borrow-joined-20260927/repeat.py'),'100',pc.SCHEMATIC_SVG[program['case']],*argv]
  command=['taskset','-c','2','perf','record','-e','instructions:u','-c',period,'-o',str(data),'--',*argv]
  done=subprocess.run(command,cwd=run['cwd'],env=run['env'],capture_output=True,check=True,timeout=3600)
  if program['kind']=='schematic':
   assert done.stdout in (b'',b'0\n') and not (run['issue'].exists() and run['issue'].read_bytes())
   assert sha(run['svg'])==pc.SCHEMATIC_SVG[program['case']]
  else:assert done.stdout==Path(program['expected_path']).read_bytes()
  script_cmd=['perf','script','-i',str(data),'-F','period,ip,sym,dso']
  sampled=subprocess.run(script_cmd,capture_output=True,check=True)
  report=subprocess.run(['perf','report','-i',str(data),'--stdio','--sort','symbol','--percent-limit','0.1'],capture_output=True,check=True)
  (work/(label+'-lowrate.samples.txt.gz')).write_bytes(gzip.compress(sampled.stdout,mtime=0))
  (work/(label+'-lowrate.report.txt')).write_bytes(report.stdout)
  symbols=collections.Counter();total=0
  for line in sampled.stdout.decode().splitlines():
   fields=line.split()
   if len(fields)<4 or not fields[0].isdigit():continue
   weight=int(fields[0]);symbol=' '.join(fields[2:-1]);symbols[symbol]+=weight;total+=weight
  result['profiles'][label]={'command':command,'cwd':str(run['cwd']),'env':{k:v for k,v in run['env'].items() if k.startswith('MYLANG_')},'binary_sha256':sha(binary),'data_sha256':sha(data),'stdout':done.stdout.decode(),'stderr':done.stderr.decode(),'script_command':script_cmd,'script_stderr':sampled.stderr.decode(),'report_stderr':report.stderr.decode(),'sampled_period':total,'symbols':[{'symbol':name,'period':weight,'fraction':weight/total} for name,weight in symbols.most_common()]}
  save();print(label,result['profiles'][label]['symbols'][:15],flush=True)
