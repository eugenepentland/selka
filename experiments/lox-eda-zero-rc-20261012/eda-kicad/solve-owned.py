#!/usr/bin/env python3
"""Apply only checker-directed owned-value snapshots, four checks per lease.
Moved values and unchanged overlap diagnostics stop for manual review.
"""
import hashlib,json,pathlib,shutil,subprocess,sys
base=pathlib.Path(__file__).resolve().parent;source=base.parent/'eda/source/src';repo=base.parents[2]
compiler=sys.argv[1];label=sys.argv[2]
if '--batch' in sys.argv:
 # Refresh transferred/dependency modules only before the checks in this lease.
 peer=pathlib.Path('/home/epentland/ai/canopy/mylang-lox-eda-20261012-eda/experiments/lox-eda-zero-rc-20261012/eda/source/src')
 for dependency in peer.iterdir():
  if dependency.is_file() and not dependency.name.startswith(('export_kicad','kicad_')):
   shutil.copyfile(dependency,source/dependency.name)
 name=sys.argv[4];records=[]
 for attempt in range(4):
  r=subprocess.run([compiler,'check',str(source/name),'--experimental-zero-rc'],capture_output=True,text=True,timeout=120)
  row={'module':name,'status':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'source_sha256':hashlib.sha256((source/name).read_bytes()).hexdigest()}
  records.append(row)
  if r.returncode==0:break
  temporary=base/(label+'.current.json');temporary.write_text(json.dumps({'modules':[row]}))
  fixed=subprocess.run([sys.executable,str(base/'apply-diagnostics.py'),str(temporary)],capture_output=True,text=True,check=True)
  edits=json.loads(fixed.stdout);row['snapshot_edits']=edits
  if not edits:break
 print(json.dumps(records));sys.exit(0)
names=sys.argv[3:] or sorted(p.name for p in source.glob('*.my') if p.name.startswith(('export_kicad','kicad_')) and p.name not in ('export_kicad_sch.my','export_kicad_sch_test.my'))
output=base/(label+'.json');assert not output.exists();rows=[]
for name in names:
 for iteration in range(40):
  r=subprocess.run([str(repo/'scripts/build-slot.sh'),'build',sys.executable,__file__,compiler,label,'--batch',name],capture_output=True,text=True,check=True)
  records=json.loads(r.stdout);rows.extend(records);output.write_text(json.dumps({'compiler':compiler,'records':rows},indent=2)+'\n');last=records[-1]
  if last['status']==0 or not last.get('snapshot_edits'):break
 print(name,'PASS' if last['status']==0 else last['stderr'].splitlines()[0],flush=True)
