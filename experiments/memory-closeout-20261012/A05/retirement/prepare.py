#!/usr/bin/env python3
"""Create a reviewed retirement preview without modifying runtime sources."""
# spec: NEW-CORE-ZERO-RC-ABI-1 NEW-CORE-ZERO-RC-RESOURCES-1
import difflib
import hashlib
import json
from pathlib import Path
import re
import subprocess

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
DEST=ROOT/'.tmp/memory-closeout/A05/retirement-preview'
FILES=('core_dict.c','core_sort.c','core_io.c','core_host.c','core_durable.c')

def owned_branches(text):
    """Resolve only MYL_ZERO_RC directives; preserve unrelated preprocessing."""
    stack=[]; out=[]
    for line in text.splitlines(keepends=True):
        active=all(frame[1] for frame in stack)
        directive=re.match(r'^\s*#\s*(ifdef|ifndef)\s+MYL_ZERO_RC\s*$',line)
        if directive:
            stack.append([True,directive[1]=='ifdef']);continue
        generic=re.match(r'^\s*#\s*(if|ifdef|ifndef)\b',line)
        if generic:
            if active:out.append(line)
            stack.append([False,True]);continue
        if re.match(r'^\s*#\s*else\b',line):
            assert stack
            if stack[-1][0]:stack[-1][1]=not stack[-1][1]
            elif active:out.append(line)
            continue
        if re.match(r'^\s*#\s*elif\b',line):
            assert stack and not stack[-1][0], 'review a new MYL_ZERO_RC elif explicitly'
            if active:out.append(line)
            continue
        if re.match(r'^\s*#\s*endif\b',line):
            assert stack
            target=stack.pop()[0]
            if not target and all(frame[1] for frame in stack):out.append(line)
            continue
        if active:out.append(line)
    assert not stack
    return ''.join(out)

def exact(text, before, after):
    assert before in text,before
    return text.replace(before,after)

def fixture_preview():
    path=ROOT/'src/core/durable_fixture.c'
    before=path.read_text()
    after=before.replace('if (owner) core_io_retain(owner);','if (owner) (void)myl_core_result_take_pointer(result, 1);')
    after=after.replace('myl_core_release(provider);','(void)provider;').replace('myl_core_release(', 'myl_core_drop_owned(')
    items=[(path,before,after)]
    path=ROOT/'src/core/durable_test.zig';before=path.read_text();after=before
    start=after.index('/// Preserve fixture scenarios');end=after.index('fn nativeFixture(',start)
    after=after[:start]+after[end:]
    after=exact(after,'fn nativeFixture(a: std.mem.Allocator, owned: bool)', 'fn nativeFixture(a: std.mem.Allocator)')
    after=exact(after,'    const fixture = try fixtureSource(a, owned);\n    defer a.free(fixture);\n    try directory.dir.writeFile(io, .{ .sub_path = "fixture.c", .data = fixture });','    try directory.dir.writeFile(io, .{ .sub_path = "fixture.c", .data = @embedFile("durable_fixture.c") });')
    after=exact(after,'    if (owned) try environment.put("MYL_CORE_LEAKCHECK", "1");','    try environment.put("MYL_CORE_LEAKCHECK", "1");')
    start=after.index('        .argv = if (owned)');end=after.index('        .environ_map = &environment,',start)
    after=after[:start]+'        .argv = &.{ environment.get("ZIG") orelse "zig", "cc", "-O2", "-std=c11", "-pthread", source, "-o", binary },\n'+after[end:]
    start=after.index('// spec: NEW-CORE-DURABLE-STORAGE-1\ntest "durable storage');end=after.index('// spec-case: NEW-CORE-DURABLE-STORAGE-1',start)
    after=after[:start]+after[end:]
    after=exact(after,'nativeFixture(arena.allocator(), true)','nativeFixture(arena.allocator())')
    items.append((path,before,after))
    patch=[]
    for path,before,after in items:
        name=str(path.relative_to(ROOT))
        patch.extend(difflib.unified_diff(before.splitlines(True),after.splitlines(True),'a/'+name,'b/'+name))
    (HERE/'fixture-retirement.patch').write_text(''.join(patch))
    (HERE/'fixture-manifest.json').write_text(json.dumps({'status':'prepared only; coordinator reservation/apply required for durable_fixture.c, coupled to unconditional owned root runtime','files':[{'path':str(path.relative_to(ROOT)),'before_sha256':hashlib.sha256(before.encode()).hexdigest(),'after_sha256':hashlib.sha256(after.encode()).hexdigest()} for path,before,after in items]},indent=2)+'\n')

def main():
    DEST.mkdir(parents=True,exist_ok=True)
    patch=[];manifest=[]
    for name in FILES:
        path=ROOT/'src/core/runtime'/name
        before=path.read_text();after=owned_branches(before)
        if name=='core_dict.c':
            after=exact(after,'Compiler-directed deep copying uses the private storage helper. A COW\n       copy with owned children has no valid zero-RC contract.','Compiler-directed deep copying uses the private storage helper. This\n       scalar-only storage copy cannot duplicate managed children.')
            after=exact(after,'children to the same visitor used for both sharing and destruction.','children to the direct-destruction visitor.')
            after=exact(after,'    core_layout_release release = NULL;\n','')
            after=exact(after,'        if (release) { release(dict_entry(dict, i), context); continue; }\n','')
        elif name=='core_sort.c':
            begin=after.index('/* Borrow source and keys, return one sorted owning copy.')
            end=after.index('/* Both arguments are independent compiler-created owners.',begin)
            after=after[:begin]+after[end:]
        elif name=='core_io.c':
            after=exact(after,' * Authority and provider state use Core counted blocks; handles stay weakly',' * Authority and provider state use directly owned blocks; handles stay weakly')
            after=exact(after,'static void core_io_retain(myl_block *block) {\n    (void)block; /* Caller-checked dependencies borrow; root providers transfer. */\n}\n','')
            after=exact(after,'static void core_io_root_transferred(myl_block *provider) {\n    (void)provider;\n}\n','')
            for call in ('core_io_retain(pairs);','core_io_retain(provider);','core_io_retain(parent);','core_io_retain(scope);','core_io_retain(cap);','core_io_root_transferred(provider);','core_io_root_transferred(state);'):
                after=exact(after,call,'')
        elif name=='core_durable.c':
            after=exact(after,'    core_io_retain(cap);\n','')
        assert 'MYL_ZERO_RC' not in after
        for symbol in ('count_is_unique(', 'count_retain(', 'myl_core_release(', 'core_io_retain(', 'core_io_root_transferred(', 'myl_core_s2_sort_keyed('):
            assert symbol not in after,(name,symbol)
        dest=DEST/name;dest.write_text(after)
        relative=str(path.relative_to(ROOT))
        patch.extend(difflib.unified_diff(before.splitlines(True),after.splitlines(True),'a/'+relative,'b/'+relative))
        manifest.append({'path':relative,'before_sha256':hashlib.sha256(before.encode()).hexdigest(),'after_sha256':hashlib.sha256(after.encode()).hexdigest(),'changed':before!=after,'preview':str(dest)})
    (HERE/'runtime-retirement.patch').write_text(''.join(patch))
    (HERE/'manifest.json').write_text(json.dumps({'status':'prepared only; not applied to integration or worker sources','worker_revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'files':manifest},indent=2)+'\n')
    fixture_preview()
    print('Prepared',sum(x['changed'] for x in manifest),'runtime changes; production files unchanged')

if __name__=='__main__':main()
