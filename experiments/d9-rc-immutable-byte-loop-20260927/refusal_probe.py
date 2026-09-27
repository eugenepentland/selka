from pathlib import Path
import subprocess,os,json,hashlib,difflib
r=Path.cwd();w=r/'.tmp-bytes';src=r/'src/qbe_rc_values.zig';old=src.read_text();needle='if (@import("qbe_rc_byte_version.zig").emptyOperand(E, self, index)) return;';assert old.count(needle)==1
new=old.replace(needle,'if (false and @import("qbe_rc_byte_version.zig").emptyOperand(E, self, index)) return;')
(w/'refusal-probe.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/src/qbe_rc_values.zig',tofile='b/src/qbe_rc_values.zig')))
e=os.environ.copy();e.update(TMPDIR=str(w/'tmp'),ZIG_LOCAL_CACHE_DIR=str(r/'.zig-cache-bytes'))
try:
 src.write_text(new)
 cmd=[str(r/'scripts/build-slot.sh'),'build','zig','build','-Doptimize=Debug','-Dcompiler-only=true','--prefix',str(w/'install-refusal-probe')]
 with (w/'refusal-build.log').open('w') as log:p=subprocess.run(cmd,env=e,stdout=log,stderr=subprocess.STDOUT)
 assert p.returncode==0
finally:src.write_text(old)
c=w/'install-refusal-probe/bin/mylang';cmd=[str(r/'scripts/build-slot.sh'),'build',str(c),'emit-qbe',str(r/'bench/parity/micro/bytes_scan.my'),'--no-cache','--drop-step-checks','--drop-frame-checks','--drop-debug','--rc-runtime'];p=subprocess.run(cmd,env=e,capture_output=True);(w/'refusal-emit.json').write_bytes(p.stdout);(w/'refusal-emit.log').write_bytes(p.stderr);assert p.returncode==0,p.stderr
m=next(x['il'] for x in json.loads(p.stdout)['functions'] if x['name']=='main');(w/'refusal-main.ssa').write_text(m);assert 'RC-READ-BYTES-VERSION-1' not in m and '\n@fi118' not in m and 'myl_qbe_fail_index_bounds' in m and 'myl_qbe_rc_slot_drop' in m
(w/'refusal.json').write_text(json.dumps(dict(command=cmd,compiler_sha256=hashlib.sha256(c.read_bytes()).hexdigest(),patch_sha256=hashlib.sha256((w/'refusal-probe.patch').read_bytes()).hexdigest(),source_restored=src.read_text()==old,fast_copy_discarded=True,fallback_bounds_and_drop_present=True),indent=2)+'\n')
print('REFUSAL RESTORATION PASS')
