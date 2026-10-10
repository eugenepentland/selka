#!/usr/bin/env python3
"""Run the raw and additive frozen qualification directly, preserving exact results."""
import argparse,json,pathlib,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[3]
p=argparse.ArgumentParser();p.add_argument('--tag',required=True);a=p.parse_args()
area=ROOT/'experiments/runtime-parity-3-20261009/R';directories={}
for kind,expected in [('raw',1),('additive',0)]:
 evidence=area/('qual-'+a.tag+'-'+kind);directories[kind]=evidence
 command=['python3','experiments/new-core-s5-20261007/tools/qualify_merge.py','--shards','64','--compiler','zig-out/bin/mylang','--install','install','--evidence',str(evidence)]
 if kind=='additive':command+=['--frontend-reference','experiments/frontend-fixes-20261009/s5-frontend-reference.json']
 done=subprocess.run(command,cwd=ROOT);assert done.returncode==expected,(kind,done.returncode)
 summary=json.loads((evidence/'summary.json').read_text());assert len(summary['results'])==3 and all(s['status']==0 for s in summary['results'][:2]),summary
subprocess.run(['python3','experiments/runtime-parity-3-20261009/tools/validate_qualification.py','--raw',str(directories['raw']),'--additive',str(directories['additive'])],cwd=ROOT,check=True)
