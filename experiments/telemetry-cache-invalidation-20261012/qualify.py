import hashlib,json,os,pathlib,shutil,subprocess,time
root=pathlib.Path.cwd();out=root/'.tmp/telemetry-cache-probe/candidate';out.mkdir(exist_ok=True)
source=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
command=['python3','scripts/verify_cache.py','--zig',os.environ['ZIG'],'--timing-window-seconds','1800']
rows=[]
for name in ['qualification','warm-01','warm-02']:
 started=time.monotonic()
 with (out/(name+'.stdout')).open('w') as stdout,(out/(name+'.stderr')).open('w') as stderr:
  result=subprocess.run(command,stdout=stdout,stderr=stderr)
 path=root/'.mylang-cache/verification-v2/last-run.json';report=json.loads(path.read_text()) if path.exists() else {}
 shutil.copy2(path,out/(name+'.report.json'))
 row=dict(name=name,status=result.returncode,outer_seconds=time.monotonic()-started,success=report.get('success'),coverage=report.get('profile_coverage'),window=report.get('measurement_window'),gate_seconds=report.get('gate_admitted_seconds'))
 rows.append(row);print(json.dumps(row),flush=True)
 (out/'capture.json').write_text(json.dumps(dict(source=source,command=command,rows=rows),indent=2)+'\n')
 coverage=report.get('profile_coverage',{})
 if result.returncode or not report.get('success') or not report.get('inputs_stable') or not coverage.get('complete_verification') or coverage.get('counts',{}).get('outstanding')!=0:raise SystemExit(result.returncode or 1)
for filename in ['inventory.json','artifacts.json']:
 path=root/'zig-out/verification'/filename
 if path.exists():shutil.copy2(path,out/filename)
(out/'sha256.json').write_text(json.dumps({p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file() and p.name!='sha256.json'},indent=2)+'\n')
