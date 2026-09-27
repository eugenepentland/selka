from pathlib import Path
import hashlib,json,os,subprocess

ROOT=Path.cwd(); W=ROOT/'.tmp-readonly'
COMPILERS={'before':ROOT.parent/'d9-rc-integration/.tmp-rc/install-ownership-joined-fixed/bin/mylang',
           'after':W/'install-after/bin/mylang'}
ENV={k:v for k,v in os.environ.items() if not k.startswith('MYLANG_') and k!='LD_PRELOAD'}
ENV.update(TMPDIR=str(W/'tmp'),ZIG_LOCAL_CACHE_DIR=str(ROOT/'.zig-cache-readonly-guests'))
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
source=ROOT/'tests/lang/rc_readonly_calls.my'
for side in COMPILERS:
    for backend in ('qbe','llvm'):
        for mode in ('gc','rc'):
            binary=build(side,backend,mode,source,f'guest-{side}-{backend}-{mode}')
            row=run(binary,side,backend,mode,'guest','--gc-stress' if mode=='gc' else '')
            assert row['status']==0,row
            print('passed',side,backend,mode,flush=True)
trap_source=W/'traps.my'
trap_source.write_text('''record Item:
    text: bytes
    number: int
def leaf(items: list[Item], index: int) -> int:
    return items[index].number
def middle(items: list[Item], index: int) -> int:
    return leaf(items, index) + 1
def main(index: int) -> int:
    items = [Item(b"a", 9223372036854775807)]
    return middle(items, index)
''')
for side in COMPILERS:
    for backend in ('qbe','llvm'):
        binary=build(side,backend,'rc',trap_source,f'trap-{side}-{backend}')
        for name,args,options in [('bounds',['1'],''),('overflow',['0'],''),('steps',['0'],'--max-steps=3'),('frames',['0'],'--max-frames=2')]:
            row=execute([binary,*args],options)
            row.update(side=side,backend=backend,runtime='rc',case=name)
            DATA['runs'].append(row);save()
            assert row['status']==1,row
            code={'bounds':'R_LIST_BOUNDS','overflow':'R_OVERFLOW','steps':'R_STEP_LIMIT','frames':'R_FRAME_LIMIT'}[name]
            row['expected_trap']=code
            assert code in row['stderr'] or code in row['stdout'],row
            print('trap',side,backend,name,flush=True)
assert all(sha(c)==DATA['compilers'][side]['sha256'] for side,c in COMPILERS.items())
DATA['complete']=True;save()
