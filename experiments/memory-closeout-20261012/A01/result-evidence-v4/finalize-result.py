from pathlib import Path
import os,subprocess,sys,json,hashlib
root=Path.cwd()
scratch=root/'.tmp/memory-closeout/A01'
source=root/'src/symbolic_shapes.zig'
original=source.read_text()
old=original.replace('if (visit.value == .nominal and !visit.cyclic) visit.value.nominal.properties = result;', 'if (visit.value == .nominal) visit.value.nominal.properties = result;')
assert old!=original
cmd=[os.environ['ZIG'],'build','test-units','-Dtest-filter=A01 recursive generic', '-j'+os.environ['MYLANG_DEV_JOBS'],'--maxrss',os.environ['MYLANG_DEV_MAXRSS']]
try:
    source.write_text(old)
    with (scratch/'result-cycle-red.log').open('w') as log:
        red=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
finally:
    source.write_text(original)
if red.returncode==0 or 'FAIL' not in (scratch/'result-cycle-red.log').read_text():
    raise SystemExit('Regression unexpectedly passed with incomplete cyclic memoization restored')
with (scratch/'result-cycle-green.log').open('w') as log:
    green=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
if green.returncode:raise SystemExit(green.returncode)
with (scratch/'results-support-install-v4.log').open('w') as log:
    build=subprocess.run([os.environ['ZIG'],'build','-p',str(scratch/'result-install-v4'),'-j'+os.environ['MYLANG_DEV_JOBS'],'--maxrss',os.environ['MYLANG_DEV_MAXRSS']],stdout=log,stderr=subprocess.STDOUT)
if build.returncode:raise SystemExit(build.returncode)
files=subprocess.check_output(['git','show','--format=','--name-only','HEAD','--','src'],text=True).splitlines()
identity={str(path):hashlib.sha256((root/path).read_bytes()).hexdigest() for path in files if not path.startswith('src/root_test')}
(scratch/'result-source-v4.json').write_text(json.dumps({'head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'files':identity,'compiler_sha256':hashlib.sha256((scratch/'result-install-v4/bin/mylang').read_bytes()).hexdigest(),'mutation_red_status':red.returncode,'restored_green_status':green.returncode},indent=2)+'\n')
q=subprocess.run([sys.executable,'-B','experiments/memory-closeout-20261012/A01/qualify.py','--compiler',str(scratch/'result-install-v4/bin/mylang'),'--zig',os.environ['ZIG'],'--output',str(scratch/'result-final-matrix-v4'),'--source-revision',subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'--admitted'])
raise SystemExit(q.returncode)
