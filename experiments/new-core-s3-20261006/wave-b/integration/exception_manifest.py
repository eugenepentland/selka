#!/usr/bin/env python3
"""List S3's exact named user-module and retired-arena exceptions."""
import argparse,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
ARENAS={'arena_managed','arena_scopes','arena_class_escape','arena_regions','rc_arena_values'}
S4={'migrated/propagation'}

def main():
 p=argparse.ArgumentParser(description=__doc__); p.add_argument('--output',type=Path,required=True); a=p.parse_args()
 if a.output.exists(): p.error('output exists; retain it and use a new path')
 entries=[]
 for path in sorted((ROOT/'tests/lang').rglob('*.my')):
  source=path.read_text(); name=path.relative_to(ROOT/'tests/lang').with_suffix('').as_posix()
  for fn in re.findall(r'^(?:public )?def (test_\w+)\(',source,re.M):
   if name in S4: why='S4: imports propagation_case_1 through propagation_case_9, user modules'
   elif name in ARENAS or 'arena' in fn: why='N6: retired arena test'
   else: continue
   entries.append({'file':str(path.relative_to(ROOT)),'test':fn,'reason':why})
 result={'scope':'Top-level source test declarations; mirrors conformance file and *arena* filters','s4_files':sorted(S4),'arena_files':sorted(ARENAS),'tests':entries,'s4_tests':sum(x['reason'].startswith('S4:') for x in entries),'arena_tests':sum(x['reason'].startswith('N6:') for x in entries)}
 a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(result,indent=2)+'\n'); print(json.dumps({k:v for k,v in result.items() if k!='tests'},indent=2))
if __name__=='__main__':main()
