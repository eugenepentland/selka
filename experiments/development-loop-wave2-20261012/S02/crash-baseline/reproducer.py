import json,os,signal,subprocess,sys,time
from pathlib import Path
sys.path.insert(0,str(Path.cwd()/'scripts'))
from verification_process import _process_starttime,_signal_identity
base=Path.cwd()/'.tmp/crash-proof-direct';base.mkdir(exist_ok=True)
marker=base/'marker.json';marker.unlink(missing_ok=True)
worker=('import json,os,subprocess,time; from pathlib import Path; '
        'child=subprocess.Popen(["sleep","60"],start_new_session=True); '
        f'Path({str(marker)!r}).write_text(json.dumps({{"worker":os.getpid(),"detached":child.pid,"inner":os.getppid()}})); time.sleep(60)')
launcher=('import os,sys; from pathlib import Path; sys.path.insert(0,str(Path.cwd()/"scripts")); '
          'from verification_process import run_supervised; '
          f'raise SystemExit(run_supervised({[sys.executable,"-c",worker]!r},dict(os.environ)))')
caller=('import os,subprocess,sys; '
        f'p=subprocess.Popen({[sys.executable,"-c",launcher]!r},start_new_session=True); p.wait()')
with (base/'caller.log').open('wb') as out:
    parent=subprocess.Popen([sys.executable,'-c',caller],stdout=out,stderr=out,start_new_session=True)
    deadline=time.monotonic()+900
    while not marker.exists() and time.monotonic()<deadline: time.sleep(.02)
    assert marker.exists()
    rows=json.loads(marker.read_text());rows['launcher']=int(Path(f'/proc/{rows["inner"]}/stat').read_text().rsplit(') ',1)[1].split()[1])
    births={name:_process_starttime(pid) for name,pid in rows.items()}
    os.kill(parent.pid,signal.SIGKILL);parent.wait();time.sleep(.3)
    survived={name:_process_starttime(pid)==births[name] for name,pid in rows.items()}
    (base/'result.json').write_text(json.dumps({'parent_status':parent.returncode,'survived':survived,'pids':rows,'births':births},indent=2))
    _signal_identity(rows['launcher'],births['launcher'],signal.SIGTERM)
    deadline=time.monotonic()+3
    while _process_starttime(rows['launcher'])==births['launcher'] and time.monotonic()<deadline:time.sleep(.02)
    for name in ('worker','detached','inner','launcher'):
        _signal_identity(rows[name],births[name],signal.SIGKILL)
