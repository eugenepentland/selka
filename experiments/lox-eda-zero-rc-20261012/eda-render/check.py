import json,os,pathlib,subprocess,sys
root=pathlib.Path(__file__).resolve().parent
(root/"tmp").mkdir(exist_ok=True)
os.environ["TMPDIR"]=str(root/"tmp")
src=root.parent/'eda/source/src'
rows=[]
for p in sorted(src.glob('*.my')):
 if not p.name.startswith('render_'): continue
 r=subprocess.run([sys.argv[1],'check','--experimental-zero-rc',str(p),'--cache-dir',str(root/'cache')],capture_output=True,text=True)
 rows.append(dict(module=p.name,status=r.returncode,stderr=r.stderr,stdout=r.stdout))
 print(p.name,r.stderr,flush=True)
(root/'checks.json').write_text(json.dumps(rows,indent=2))
