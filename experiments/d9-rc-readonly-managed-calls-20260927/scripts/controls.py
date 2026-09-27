from pathlib import Path
import hashlib,json,os,subprocess

ROOT=Path.cwd(); W=ROOT/'.tmp-managed-readonly'
COMPILERS={'before':W/'install-before/bin/mylang',
           'after':W/'install-draft/bin/mylang'}
ENV={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
ENV.update(TMPDIR=str(W/'tmp'),ZIG_LOCAL_CACHE_DIR=str(W/'guest-zig-cache'))
DATA={'compilers':{},'builds':[],'runs':[],'driver_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(): (W/'controls.json').write_text(json.dumps(DATA,indent=2)+'\n')
def execute(command,options=''):
    env=dict(ENV)
    if options:env['MYLANG_OPTIONS']=options
    p=subprocess.run(list(map(str,command)),env=env,capture_output=True,text=True,timeout=600)
    return {'command':list(map(str,command)),'options':options,'status':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
def build(side,backend,mode,source,name):
    binary=W/'bin'/name;binary.parent.mkdir(exist_ok=True)
    command=[ROOT/'scripts/build-slot.sh','build',COMPILERS[side],'build',source,'--mode=ReleaseFast',
             '--backend='+backend,'--cache-dir='+str(W/('cache-controls-'+side)),'-o',binary]
    if backend=='llvm':command+=['--llvm-opt=3','--lto']
    if mode=='rc':command+=['--rc-runtime=stats']
    row=execute(command,'--gc-stress' if mode=='gc' else '')
    row.update(side=side,backend=backend,runtime=mode,source=str(source),source_sha256=sha(source))
    DATA['builds'].append(row);save();assert row['status']==0,row
    manifest=json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())
    assert manifest['backend']==backend,manifest
    row.update(binary=str(binary),binary_sha256=sha(binary),manifest=manifest);save()
    return binary
def run(binary,side,backend,mode,name,options=''):
    row=execute([binary],options)
    row.update(side=side,backend=backend,runtime=mode,case=name)
    counts=[json.loads(s.split(' ',1)[1]) for s in row['stderr'].splitlines() if s.startswith('MYLANG_RC_COUNTS ')]
    if mode=='rc':
        assert len(counts)==1,row
        n=counts[0];row['counts']=n
        assert not n['saturated'] and n['hold_acquire']==n['hold_release'],row
        assert n['heap_allocate']==n['retire'] and n['owner_release']==n['owner_acquire']+n['heap_allocate'],row
    DATA['runs'].append(row);save()
    return row
for side,c in COMPILERS.items():DATA['compilers'][side]={'path':str(c),'sha256':sha(c)}
source=ROOT/'tests/lang/rc_readonly_managed_calls.my'
for side in COMPILERS:
    for backend in ('qbe','llvm'):
        for mode in ('gc','rc'):
            binary=build(side,backend,mode,source,f'guest-{side}-{backend}-{mode}')
            row=run(binary,side,backend,mode,'guest','--gc-stress' if mode=='gc' else '')
            assert row['status']==0 and row['stdout']=='True\nTrue\nTrue\n',row
            print('passed',side,backend,mode,flush=True)
DATA['complete']=True;save()
