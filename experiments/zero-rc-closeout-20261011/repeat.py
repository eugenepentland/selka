#!/usr/bin/env python3
"""Repeat frozen parallel-map binaries under counters and ThreadSanitizer."""
import argparse,hashlib,json,os,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--matrix',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--count',type=int,default=100)
 a=p.parse_args();a.matrix=a.matrix.resolve();a.output=a.output.resolve();a.output.mkdir(parents=True,exist_ok=True)
 matrix=json.loads((a.matrix/'results.json').read_text());result={}
 for name,answer in [('parallel_map','2016 item-0! 16\n'),('parallel_outcome','416\n')]:
  for mode in ('release','tsan'):
   binary=a.matrix/name/mode/'program';digest=hashlib.sha256(binary.read_bytes()).hexdigest()
   assert digest==matrix['cases'][name][mode]['binary_sha256']
   directory=a.output/name/mode;directory.mkdir(parents=True,exist_ok=True)
   peak=[]
   for i in range(a.count):
    counts=directory/(str(i)+'.json');env=dict(os.environ,MYLANG_THREADS='8',MYL_CORE_LEAKCHECK='1')
    env.pop('MYLANG_COUNTERS',None)
    if mode=='release':env['MYLANG_COUNTERS']=str(counts)
    ran=subprocess.run([binary],env=env,capture_output=True,text=True,timeout=120)
    assert ran.returncode==0 and ran.stdout==answer and not ran.stderr,(name,mode,i,ran.returncode,ran.stdout,ran.stderr)
    if mode=='release':
     data=json.loads(counts.read_text());t=data['totals']
     assert t['live_bytes_at_exit']==0
     assert all(t[k]==0 for k in ('runtime_retains','runtime_releases','shared_retains','shared_releases','share_marks'))
     assert all(data['kinds'][k]['count']==0 for k in ('retain','release','unique_test'))
     peak.append(t['peak_live_bytes'])
   result[name+'/'+mode]={'binary_sha256':digest,'executions':a.count,'min_peak':min(peak) if peak else None,'max_peak':max(peak) if peak else None}
   print('pass',name,mode,a.count,flush=True)
 report={'compiler_sha256':matrix['compiler_sha256'],'runs':result}
 (a.output/'results.json').write_text(json.dumps(report,indent=2)+'\n');(HERE/'repetitions.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
