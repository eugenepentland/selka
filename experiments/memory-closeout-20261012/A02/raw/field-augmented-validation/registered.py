from pathlib import Path
import hashlib,json,os,re,subprocess,time
root=Path.cwd();out=root/'.tmp/memory-closeout/A02/field-augmented-validation';prefix=out/'install';phrase='zero RC A02 field augmentation'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
paths=['src/core/build_list_methods.zig','src/sema_places.zig','src/core/a02_field_augmented_test.zig','src/core/a02_field_augmented_fixture.my','src/core/root_test.zig']
r={'base':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'source_sha256':{p:sha(root/p) for p in paths},'zig':os.environ['ZIG'],'zig_sha256':sha(os.environ['ZIG']),'components':os.environ['MYLANG_COMPONENT_DIR'],'component_boundary':'Support6 independent owned pin supplies components; final default/retirement package qualification is separate','steps':[],'complete':False}
def run(argv,name):
    start=time.monotonic();p=subprocess.run(list(map(str,argv)),capture_output=True,text=True,timeout=1200)
    (out/(name+'.stdout')).write_text(p.stdout);(out/(name+'.stderr')).write_text(p.stderr)
    r['steps'].append({'name':name,'argv':list(map(str,argv)),'status':p.returncode,'elapsed_admitted_seconds':time.monotonic()-start,'stdout':p.stdout,'stderr':p.stderr})
    (out/'registered.json').write_text(json.dumps(r,indent=2)+'\n');print(name,p.returncode,flush=True)
    return p.returncode
status=run([os.environ['ZIG'],'build','core-test-binary','-Dtest-filter='+phrase,'-j'+os.environ['MYLANG_DEV_JOBS'],'--maxrss',os.environ['MYLANG_DEV_MAXRSS'],'--prefix',prefix,'-Dcomponent-owned-compiler-pin='+os.environ['MM_A02_OWNED_PIN'],'-Dcomponent-seed-source='+os.environ['MM_A02_OWNED_SOURCE']],'build')
for p in sorted((root/'.zig-cache').glob('**/options.zig'), key=lambda p:p.stat().st_mtime):
    match=re.search(r'pub const core_path:.*?= "([^"]+)";',p.read_text())
    if match:
        binary=Path(match.group(1))
        if binary.exists():r['compiler']={'path':str(binary),'sha256':sha(binary),'options':str(p)}
if status==0:
    r['test_binary_sha256']=sha(prefix/'focus/core-tests')
    status=run([prefix/'focus/core-tests','--guardian-filter='+phrase],'test')
r['complete']=True;r['pass']=status==0
assert all(sha(root/p)==digest for p,digest in r['source_sha256'].items())
(out/'registered.json').write_text(json.dumps(r,indent=2)+'\n')
raise SystemExit(status)
