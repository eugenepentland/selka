"""Compare native and selected-body checking with the same qualified B4 host."""
import hashlib,json,subprocess,sys
from pathlib import Path
root=Path('/home/epentland/.codex/worktrees/selka-selfhost-pilots/mylang')
work=Path('/home/epentland/.cache/mylang-tmp/selka-selfhost-pilots')
prefix=work/'body-record-release'
gate=(work/'b4-full-gate-resources.log').read_text()
assert 'Build Summary: 131/131 steps succeeded' in gate
assert 'memory usage peaked' not in gate
assert '88 check(s) passed' in (work/'b4-final-format-guardian.log').read_text()
qualification=json.loads((work/'b4-release-host-qualification.json').read_text())
assert qualification['workflows']==283 and qualification['comparisons']==566
assert qualification['failed']==qualification['skipped']==0
report=work/'record-performance/b4-matched.json'
if report.exists():raise RuntimeError('refusing to overwrite completed timing')
host=hashlib.sha256((prefix/'bin/mylang').read_bytes()).hexdigest()
command=[sys.executable,str(root/'selfhost/tests/measure_performance_ratio.py'),'--isolated','--baseline-prefix',str(prefix),'--baseline-host-sha256',host,'--baseline-body-schema','4','--candidate-prefix',str(prefix),'--candidate-body-schema','4','--candidate-mode','BODY_CHECK=component','--zig','/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig','--output',str(report)]
result=subprocess.run(command,cwd=root,pass_fds=(30,))
if not report.is_file():raise RuntimeError('measurement did not produce complete evidence')
evidence=json.loads(report.read_text())
assert len(evidence['verdict']['rows'])==24
assert result.returncode==(0 if evidence['verdict']['passed'] else 1)
receipt={'command':command,'exit_status':result.returncode,'report':str(report),'sha256':hashlib.sha256(report.read_bytes()).hexdigest(),'verdict':evidence['verdict']}
(work/'record-performance/b4-sweep.json').write_text(json.dumps(receipt,indent=2)+'\n')
print('All 24 strict rows retained; failed budget rows remain failures.',flush=True)
sys.exit(result.returncode)
