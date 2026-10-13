"""Run under one shared build admission; no runtime timing measurements."""
from pathlib import Path
import hashlib,json,os,re,subprocess
ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
SCRATCH=Path('/home/epentland/ai/canopy/mylang/.tmp/lox-eda-parity/P3/c2-001')
COMPILER=Path('/home/epentland/ai/canopy/mylang-text-gaps-main-20261012/.tmp/lox-eda-parity/coordinator/common-002/install/bin/mylang')
assert os.environ.get('MYLANG_ADMISSION_KIND')=='build'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(COMPILER)=='9bedb835438615d79ed8f2985352877a8c844eebeb74cd95a1d276332b6b0c6a'
sources={str(p):sha(p) for arm in ['baseline','candidate-v2'] for p in sorted((SCRATCH/arm/'eda').glob('*.my'))}
commands=[]
def run(name,command,env=None):
 assert all(sha(Path(p))==v for p,v in sources.items()),'private source changed'
 proc=subprocess.run(list(map(str,command)),capture_output=True,text=True,env=env,timeout=120)
 (HERE/(name+'.stdout')).write_text(proc.stdout);(HERE/(name+'.stderr')).write_text(proc.stderr)
 commands.append({'name':name,'command':list(map(str,command)),'returncode':proc.returncode,'stdout':proc.stdout,'stderr':proc.stderr})
 (HERE/'probe-commands.json').write_text(json.dumps(commands,indent=2)+'\n')
 assert all(sha(Path(p))==v for p,v in sources.items()),'private source changed'
 return proc
manifest={'compiler':str(COMPILER),'compiler_sha256':sha(COMPILER),'source_sha256':sources,'arms':{},'boundaries':{}}
for arm in ['baseline','candidate-v2']:
 for kind in ['parser','overflow']:
  source=SCRATCH/arm/'eda'/f'{kind}_probe.my';binary=SCRATCH/f'{arm}-{kind}-v2'
  command=[COMPILER,'build',source,'--experimental-zero-rc','--release','--verify-facts','--counters','--cache-dir',SCRATCH/'cache-final-probes','--emit-llvm',SCRATCH/f'{arm}-{kind}-v2.ll','-o',binary]
  p=run(arm+'-'+kind+'-build',command)
  assert p.returncode==0,(arm,kind,p.stderr)
  if kind=='parser':
   raw=HERE/(arm+'-counters.json');env={**os.environ,'MYLANG_COUNTERS':str(raw),'MYL_CORE_LEAKCHECK':'1'}
   p=run(arm+'-parser-run',[binary],env)
   assert p.returncode==0 and p.stdout=='16000\n' and not p.stderr,(arm,p.stdout,p.stderr)
   d=json.loads(raw.read_text());t=d['totals'];assert t['live_bytes_at_exit']==0
   assert all(t.get(k,0)==0 for k in ['runtime_retains','runtime_releases','shared_retains','shared_releases','share_marks'])
   assert all(d['kinds'][k]['count']==0 for k in ['retain','release','unique_test'])
   manifest['arms'][arm]={'binary_sha256':sha(binary),'llvm_sha256':sha(SCRATCH/f'{arm}-{kind}-v2.ll'),'counter_sha256':sha(raw),'totals':t,'functions':d['functions'],'stdout':p.stdout}
  else:
   for mode in ['line-overflow','line-safe','column-overflow','column-second-overflow','column-string-overflow','newline-resets-column','escaped-newline-overflow','position-max','position-min']:
    p=run(arm+'-'+mode,[binary,mode])
    match=re.search(r'error\[([^]]+)\]: ([^\n]+)',p.stderr)
    expected = 0 if mode in ['line-safe','newline-resets-column','position-max'] else 1
    assert p.returncode==expected,(arm,mode,p.returncode,p.stderr)
    assert expected==0 or match is not None,(arm,mode,p.stderr)
    manifest['boundaries'].setdefault(mode,{})[arm]={'returncode':p.returncode,'stdout':p.stdout,'error':match.groups() if match else None,'raw_stderr':p.stderr}
for mode,values in manifest['boundaries'].items():
 a=values['baseline'];b=values['candidate-v2'];assert (a['returncode'],a['stdout'],a['error'])==(b['returncode'],b['stdout'],b['error']),(mode,values)
a=manifest['arms']['baseline']['totals'];b=manifest['arms']['candidate-v2']['totals']
for key in ['allocs','alloc_bytes','reallocs','realloc_added_bytes','peak_live_bytes','live_bytes_at_exit','buffer_copies','buffer_copy_bytes','list_copies','list_copy_bytes']:
 assert a[key]==b[key],(key,a[key],b[key])
(HERE/'probe-results.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('parser output, managed allocation metrics, and all nine checked cursor boundaries match')
