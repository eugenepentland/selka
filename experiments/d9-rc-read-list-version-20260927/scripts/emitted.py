exec(open('.tmp-mut-argument/read-version/validate.py').read().split('for side,c in compilers.items():')[0])
import gzip,importlib.util
spec=importlib.util.spec_from_file_location('pc',root/'experiments/perf-gc-dict-20260925/scripts/pc.py');pc=importlib.util.module_from_spec(spec);spec.loader.exec_module(pc)
rows=[]
for prog in [p for p in pc.programs() if p['id'] in ('parity/micro/list_append_sum','parity/suite/sieve','parity/micro/alloc_churn','schematic/fixture')]:
 row={'id':prog['id'],'sides':{}}
 for side,c in compilers.items():
  command,cwd=pc.emit_command(prog,str(c));command=[str(root/'scripts/build-slot.sh'),'build',*command,'--rc-runtime','--drop-step-checks','--drop-frame-checks','--drop-debug']
  p=subprocess.run(command,cwd=cwd,env=env,capture_output=True,text=True,timeout=600);assert p.returncode==0,p.stderr
  out=w/f"{prog['build_key']}-{side}-unaccounted.json.gz";out.write_bytes(gzip.compress(p.stdout.encode(),mtime=0));m=json.loads(p.stdout)
  row['sides'][side]={'path':str(out),'sha256':sha(out),'command':command,'cwd':cwd,'functions':[{'name':f['name'],'symbol':f['symbol'],'il_sha256':hashlib.sha256(f['il'].encode()).hexdigest(),'markers':f['il'].count('RC-READ-LIST-VERSION-1')} for f in m['functions']]}
 old={f['name']:f for f in row['sides']['before']['functions']};row['changed']=[f['name'] for f in row['sides']['after']['functions'] if f['il_sha256']!=old[f['name']]['il_sha256']];rows.append(row);(w/'unaccounted-emission.json').write_text(json.dumps(rows,indent=2)+'\n');print(prog['id'],row['changed'],sum(f['markers'] for f in row['sides']['after']['functions']),flush=True)
