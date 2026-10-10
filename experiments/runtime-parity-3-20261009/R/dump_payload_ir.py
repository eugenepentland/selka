#!/usr/bin/env python3
"""Temporarily cut recursive list type display, restore source, then dump exact R IR."""
import hashlib,json,os,pathlib,subprocess
root=pathlib.Path(__file__).resolve().parents[3]
assert pathlib.Path(os.readlink('/proc/self/fd/9')).name.startswith('build')
source=root/'src/core/print.zig';before=source.read_bytes();work=root/'.mylang-cache/rp3/R/ir-diagnostic';work.mkdir(parents=True,exist_ok=True)
a=b'.list => |element| std.fmt.allocPrint(allocator, "list[{s}]", .{try typeName(allocator, m, element)}),'
b=b'.list => |element| std.fmt.allocPrint(allocator, "list[#{d}]", .{@backingInt(element)}),'
assert before.count(a)==1
try:
 source.write_bytes(before.replace(a,b));command=['zig','build','--prefix',str(work),'--summary','all'];subprocess.run(command,cwd=root,check=True)
finally:source.write_bytes(before)
compiler=work/'bin/mylang';command=[str(compiler),'dump-ir',str(root/'.mylang-cache/eda-src/src/main.my'),'--facts']
with (work/'eda.ir').open('wb') as out: done=subprocess.run(command,cwd=root,stdout=out)
receipt={'status':done.returncode,'command':command,'compiler_sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'print_source_restored_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'temporary_display_replacement':{'before':a.decode(),'after':b.decode()},'ir_sha256':hashlib.sha256((work/'eda.ir').read_bytes()).hexdigest(),'ir_path':str(work/'eda.ir')}
(root/'experiments/runtime-parity-3-20261009/R/r4e-ir-diagnostic.json').write_text(json.dumps(receipt,indent=2));assert done.returncode==0
