import sys,json,shutil,struct,hashlib
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0,'/home/epentland/.codex/worktrees/selka-compiler-probes/mylang/selfhost/tests')
import run_body_dictionary_admission as A
import run_body_check_qualification as D
root=Path('/home/epentland/ai/canopy/.selka-agent-cache/lexer-b8')
prefix=root/'coherent-cf2-prefix';work=root/'candidate-replay-cf2';work.mkdir(exist_ok=True)
source=work/'sources';source.mkdir(exist_ok=True)
empty=work/'empty-path';empty.mkdir(exist_ok=True)
manifest,inventory=A.selection()
for p in A.FIXTURES.glob('*.my'): shutil.copyfile(p,source/p.name)
for name in manifest: shutil.copyfile(A.FIXTURES/Path(name).with_suffix('.input'),source/name)
args=SimpleNamespace(compiler=prefix/'bin/mylang',component_dir=prefix/'libexec/mylang/components',zig=Path('/home/epentland/.local/bin/zig').resolve())
q=SimpleNamespace(work=work,source=source,empty_path=empty,compiler=args.compiler)
before=D.packages(args.component_dir,body_schema=8)
private,real=D.private_fixture(args,q)
rows=[]
for name,spec in manifest.items():
    native=D.F.execute([args.compiler,'check-project',source/name,'--diagnostics=json','--no-cache'],D.environment('reference',args.component_dir,empty),work)
    A.native_contract(native,spec)
    captured,request,reply=D.capture_exchange(args,q,private,real,name)
    D.F.require(struct.unpack('<IIII',request[8:24])==(1,8,0,len(request)-64),'not genuine schema8 request')
    stem=Path(name).stem
    (work/(stem+'.request.bin')).write_bytes(request)
    (work/(stem+'.reply.bin')).write_bytes(reply)
    shadow=D.F.execute([args.compiler,'check-project',source/name,'--diagnostics=json','--no-cache'],D.environment('shadow',args.component_dir,empty),work)
    (work/(stem+'.shadow.stderr')).write_bytes(shadow[2])
    (work/(stem+'.reference.stderr')).write_bytes(native[2])
    (work/(stem+'.component.stderr')).write_bytes(captured[2])
    rows.append({'source':name,'source_sha256':D.F.digest(source/name),'native_status':native[0],'component_status':captured[0], 'shadow_status':shadow[0], 'component_exact':captured==native, 'shadow_exact':shadow==native, 'request':stem+'.request.bin','reply':stem+'.reply.bin','request_sha256':hashlib.sha256(request).hexdigest()})
    print(name,native[0],captured[0],shadow[0],captured==native,shadow==native,len(request),len(reply),flush=True)
D.F.require(D.packages(args.component_dir,body_schema=8)==before,'deployment changed')
receipt={'format':1,'schema':8,'purpose':'development frozen cf2 schema8 producer comparisons; qualification only after all exact', 'capture_only':False,'native_revision':'5a18be34b','producer_revision':'cf2e0048e', 'producer_engine_sha256':D.F.digest(root/'coherent-cf2-source/selfhost/components/body_check/engine.my'),'host_sha256':D.F.digest(args.compiler),'packages':before,'cases':rows}
(work/'requests.json').write_text(json.dumps(receipt,indent=2)+'\n')
