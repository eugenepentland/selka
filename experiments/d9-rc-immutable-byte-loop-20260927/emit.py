from pathlib import Path
import os,subprocess,json,hashlib
r=Path.cwd();w=r/'.tmp-bytes';env=os.environ.copy();env.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(r/'.zig-cache-bytes-guests'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
compilers={'rc':r.parent/'d9-rc-integration/.tmp-rc/install-loops-fixed/bin/mylang','gc':r.parent/'d9-physical-borrow-after-astra/.tmp-physical/install-accepted/bin/mylang'}
rows={}
for side,compiler in compilers.items():
    source=r/'bench/parity/micro/bytes_scan.my'
    command=[str(r/'scripts/build-slot.sh'),'build',str(compiler),'emit-qbe',str(source),'--no-cache','--drop-step-checks','--drop-frame-checks','--drop-debug']
    if side=='rc':command+=['--rc-runtime']
    p=subprocess.run(command,env=env,capture_output=True)
    (w/(side+'-emit.json')).write_bytes(p.stdout)
    (w/(side+'-emit.log')).write_bytes(p.stderr)
    rows[side]={'command':command,'cwd':str(r),'compiler_sha256':sha(compiler),'source_sha256':sha(source),'status':p.returncode,'emission_sha256':hashlib.sha256(p.stdout).hexdigest()}
    (w/'emission-identity.json').write_text(json.dumps(rows,indent=2)+'\n')
    assert p.returncode==0,p.stderr.decode()
    d=json.loads(p.stdout)
    main=next(x['il'] for x in d['functions'] if x['name']=='main')
    (w/(side+'-main.ssa')).write_text(main)
    print(side,{'main_bytes':len(main),'loan_calls':main.count('call $myl_rc_native_loan'),'fast_labels':main.count('\n@fi')})
