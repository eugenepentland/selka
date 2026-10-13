#!/usr/bin/env python3
"""Pin exact C2 scalar-only runtime and one initialization-only variant."""
import pathlib,hashlib,json,subprocess,re
root=pathlib.Path.cwd();base=root/'experiments/lox-eda-parity-20261013/P7-stack';work=root/'.tmp/lox-eda-parity/P7-stack';commit='fbeba4eed7b549a3feef14c8b8dd620e41494139'
def digest(data):return hashlib.sha256(data).hexdigest()
driver=subprocess.check_output(['git','show',commit+':src/core/driver.zig']).decode();files=re.findall(r'@embedFile\("([^"]+)"\)',driver.split('pub const runtime_source = ',1)[1].split(';',1)[0]);assert len(files)==14
old={p:subprocess.check_output(['git','show',commit+':src/core/'+p]) for p in files};changed='runtime/core_owned_copy.c';current=(root/'src/core'/changed).read_bytes();assert digest(old[changed])=='e0df96ef27050a5f74ba36ac9f761633b7fd0eaa3dcb81ee392f37cb21648b21'
expected=old[changed].replace(b'    core_copy_stack stack = {0};\n    stack.items = stack.local;',b'    /* Push fully initializes every slot in the live [0, count) prefix. */\n    core_copy_stack stack;\n    stack.items = stack.local;\n    stack.count = 0;');assert expected==current
rows={};generator=work/'generator';(generator/'runtime').mkdir(parents=True,exist_ok=True)
for name in ['baseline','candidate']:
 folder=work/name;folder.mkdir(parents=True,exist_ok=True);inputs={p:(current if name=='candidate' and p==changed else old[p]) for p in files};source=b'\n'.join(inputs.values());(folder/'core_rt.c').write_bytes(source);(folder/'harness.c').write_bytes((root/'src/core/runtime/owned_copy_stack_fixture.c').read_bytes());(generator/(name+'.c')).write_bytes(source);rows[name]={'runtime_sha256':digest(source),'inputs':{p:digest(v) for p,v in inputs.items()}}
for p in ['count_runtime.zig','runtime/core_count.h','runtime/core_count.c']:(generator/p).write_bytes(subprocess.check_output(['git','show',commit+':src/core/'+p]))
lines=['const std = @import("std");','const counting = @import("count_runtime.zig");','test "generate exact counted runtime variants" {','    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);','    defer arena.deinit();']
for name in rows:lines.append('    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = '+json.dumps(str(work/name/'counted_rt.c'))+', .data = try counting.source(arena.allocator(), @embedFile('+json.dumps(name+'.c')+')) });')
lines.append('}');(generator/'generate.zig').write_text('\n'.join(lines)+'\n')
(base/'runtime-variants.json').write_text(json.dumps({'baseline_commit':commit,'runtime_file_order':files,'variants':rows,'fixture_sha256':digest((root/'src/core/runtime/owned_copy_stack_fixture.c').read_bytes()),'prepare_sha256':digest(pathlib.Path(__file__).read_bytes())},indent=2)+'\n');print('prepared exact C2 baseline and stack initialization-only candidate')
