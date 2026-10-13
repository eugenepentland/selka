#!/usr/bin/env python3
"""Prepare private exact-prefix fixtures and standalone admitted five-mode commands."""
import argparse, pathlib, shutil, hashlib, json, shlex
p=argparse.ArgumentParser();p.add_argument('source');p.add_argument('compiler');p.add_argument('scratch');a=p.parse_args()
source=pathlib.Path(a.source).resolve();scratch=pathlib.Path(a.scratch).resolve();evidence=pathlib.Path(__file__).resolve().parent
assert not scratch.exists(), 'Use a fresh private scratch directory'
scratch.mkdir(parents=True);receipts=[];commands=['#!/usr/bin/env bash','set -euo pipefail','source /home/epentland/.config/mylang/dev-env.sh']
for label,module,appendix,count in [('gangable','kicad_sch_compose.my',evidence.parent/'followup-004/fixture-candidate-appendix.my.txt',3),('component','export_kicad_sch.my',evidence/'fixture-candidate-appendix.my.txt',4)]:
 dst=scratch/label;shutil.copytree(source,dst);prefix=(dst/module).read_bytes();suffix=appendix.read_bytes();(dst/module).write_bytes(prefix+suffix)
 receipts.append({'label':label,'module':module,'prefix_sha256':hashlib.sha256(prefix).hexdigest(),'appendix_sha256':hashlib.sha256(suffix).hexdigest(),'expected_tests':count})
 for mode,flags in [('verified-release',['--release','--verify-facts']),('release',['--release']),('debug',['--unoptimized']),('optimized-debug',['--optimize-debug']),('no-facts',['--release','--no-facts'])]:
  cmd=['scripts/build-slot.sh','build',a.compiler,'test',str(dst/module),'--experimental-zero-rc',*flags,'--jobs','4','--max-steps','1000000000','--max-frames','40000','--max-memory','2G','--timeout-ms','120000','--cache-dir',str(scratch/'cache'/label/mode),'--json']
  commands.append(shlex.join(cmd)+' > '+shlex.quote(str(scratch/(label+'-'+mode+'.log')))+' 2>&1')
(scratch/'fixtures.json').write_text(json.dumps({'source':str(source),'compiler':a.compiler,'fixtures':receipts},indent=2)+'\n');(scratch/'run.sh').write_text('\n'.join(commands)+'\n')
print(scratch/'run.sh')
