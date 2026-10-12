import json,os,pathlib,subprocess,sys
root=pathlib.Path(__file__).resolve().parent
(root/"tmp").mkdir(exist_ok=True)
os.environ["TMPDIR"]=str(root/"tmp")
previous=json.loads((root/"tests-release.json").read_text()) if "--retry" in sys.argv and (root/"tests-release.json").exists() else []
rows=[r for r in previous if r["status"]==0]
for p in sorted((root.parent/'eda/source/src').glob('*_test.my')):
 if not p.name.startswith('render_'):continue
 if any(r['module']==p.name for r in rows):continue
 r=subprocess.run([sys.argv[1],'test',str(p),'--experimental-zero-rc','--release','--verify-facts','--jobs','4','--max-steps','1000000000','--max-frames','40000','--max-memory','2G','--timeout-ms','120000','--cache-dir',str(root/'test-cache'),'--json'],capture_output=True,text=True)
 rows.append(dict(module=p.name,status=r.returncode,stdout=r.stdout,stderr=r.stderr))
 print(p.name,r.returncode,r.stderr[:500],flush=True)
(root/'tests-release.json').write_text(json.dumps(rows,indent=2))
