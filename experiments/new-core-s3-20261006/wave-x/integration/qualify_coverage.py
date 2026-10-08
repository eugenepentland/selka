#!/usr/bin/env python3
"""Checked S3 function coverage with private scratch files and original embed assets.

Uses the inherited four-corpus registry and deduction by qualified function name.
Asset snapshots repair the inherited scratch-copy E_EMBED_MISSING failures; nested
user-module examples retain their front-end diagnostics and remain S4 context.
"""
import argparse,hashlib,importlib.util,json,os,shutil,subprocess,sys
from collections import Counter
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--evidence',type=Path,required=True)
 p.add_argument('--core',type=Path,default=ROOT/'zig-out/bin/mylang-core')
 a=p.parse_args(); area=a.evidence.resolve(); core=a.core.resolve()
 if area.exists() or not area.is_relative_to(ROOT/'experiments'): p.error('choose a fresh evidence directory under experiments')
 area.mkdir(parents=True); scratch=area/'scratch'; scratch.mkdir(); os.environ['TMPDIR']=str(scratch)
 spec=importlib.util.spec_from_file_location('coverage_sweep',ROOT/'experiments/new-core-s0-20261005/coverage.py')
 sweep=importlib.util.module_from_spec(spec); spec.loader.exec_module(sweep)
 original_entries=sweep.with_entry
 def entries(files,directory):
  if Path(directory).name=='coverage-entries':
   shutil.copytree(ROOT/'tests/lang',directory,dirs_exist_ok=True,ignore=shutil.ignore_patterns('.mylang-cache','.zig-cache','zig-out'))
  return original_entries(files,directory)
 sweep.with_entry=entries
 original_run=subprocess.run; children=[]; frontend=[]; refusals=Counter(); outcomes={}; error=None
 def run(command,**options):
  options['timeout']=300; result=original_run(command,**options); index=len(children)+1
  (area/f'corpus-{index}.txt').write_text(result.stdout); (area/f'corpus-{index}.err').write_text(result.stderr)
  children.append({'command':command,'status':result.returncode})
  if result.returncode: raise RuntimeError(f'coverage child {index} exited {result.returncode}')
  for line in result.stdout.splitlines():
   kind,_,rest=line.partition(' ')
   if kind=='frontend': frontend.append(rest)
   elif kind=='refused':
    reason,_,name=rest.partition('\t'); refusals[reason]+=1
    outcomes.setdefault(name,reason)
   elif kind=='ok': outcomes[rest.partition('\t')[0]]=None
  return result
 oldargv=sys.argv; sys.argv=[str(sweep.__file__),'--core',str(core)]; subprocess.run=run
 try:
  sweep.main()
  if len(children)!=4: raise RuntimeError('expected four coverage corpora')
 except Exception as failure:
  error=f'{type(failure).__name__}: {failure}'; print(error,file=sys.stderr)
 finally:
  subprocess.run=original_run; sys.argv=oldargv
 summary={'qualified':error is None,'error':error,'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'core_sha256':hashlib.sha256(core.read_bytes()).hexdigest(),'children':children,'frontend_context_failures':frontend,'raw_refusal_occurrences':dict(refusals),'remaining_qualified_names':{k:v for k,v in sorted(outcomes.items()) if v is not None},'globally_deduplicated_functions':len(outcomes),'globally_deduplicated_accepted':sum(v is None for v in outcomes.values()),'scope_note':'Printed inherited table sums per-corpus name sets. Summary also supplies global qualified-name deduplication. Test entry scratch includes original asset/support snapshots; nested user-module examples require S4 context.'}
 (area/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
 return int(error is not None)
if __name__=='__main__':raise SystemExit(main())
