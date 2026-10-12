#!/usr/bin/env python3
"""Prepare an owned-runtime retirement patch without modifying production files."""
import difflib, hashlib, json, re, subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
DEST=ROOT/'.tmp/memory-closeout/A02/retirement-preview'

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


def main():
    DEST.mkdir(parents=True,exist_ok=True)
    patches=[];manifest=[]
    for name in ['core_rt.c','core_bytes.c']:
        path=ROOT/'src/core/runtime'/name
        before=path.read_text();after=owned_branches(before)
        if name=='core_rt.c':
            start=after.index(' * Blocks:');end=after.index(' * Output:',start)
            after=after[:start]+""" * Blocks use the proven owned ABI: a 32-byte header with storage kind at
 * offset 0, followed by i64 length, capacity and layout words. Each dynamic
 * block has one owner; destruction walks its guarded child layouts directly.
 * Static leaves carry a storage-kind tag. There is no memory reference count.
 * The allocator retains its ordinary fatal OOM and test-only budget behavior.
 *
"""+after[end:]
            start=after.index('/* A saturated count');end=after.index('#define MYL_STATIC_STORAGE',start)
            after=after[:start]+after[end:]
            start=after.index('/* SHARED-COUNTS-1');end=after.index('/* The zero-RC ABI',start)
            after=after[:start]+after[end:]
            after=after.replace('/* NEW-CORE-U2-RELEASE-1: specialized walks keep count operations in the runtime. */','/* Generated callbacks destroy dictionary key/value owners directly. */')
            start=after.index('/* One more owner of `block`');end=after.index('myl_block *myl_core_list_copy',start)
            after=after[:start]+"""/* Independent scalar-element storage. Managed children use the compiler's
   deep-copy adapter, which preserves the same owned layout and cleanup ABI. */
"""+after[end:]
            start=after.index('/* ---- one-count RC');end=after.index('typedef void (*core_child_visitor)',start)
            after=after[:start]+"""/* ---- direct owned-child destruction --------------------------------------- */
/* Every live child occurrence is visited; union guards exclude inactive arms. */
"""+after[end:]
            start=after.index('    /* A guardless pointer list');end=after.index('    int64_t count = element_count(block);',start)
            after=after[:start]+after[end:]
            after=exact(after,'        if (release) { release(element, context); continue; }\n','')
            after=after.replace(' * Nonnegative [2] is the legacy interpreted layout, used by C-created blocks.',' * Nonnegative [2] is the compact interpreted layout used by C-created blocks.')
            after=after.replace('`main` releases what it owns','`main` destroys what it owns').replace('runs no releases (RC-TRAP-TEARDOWN-1)','runs no managed cleanup (RC-TRAP-TEARDOWN-1)')
        else:
            start=after.index('/* A buffer handed over to an append');end=after.index('static myl_block *core_buffer_owned',start)
            after=after[:start]+"""/* An append consumes its exclusive buffer receiver. The builder performs the
   call between the read of a mut place and its writeback. */
"""+after[end:]
        assert 'MYL_ZERO_RC' not in after
        (DEST/name).write_text(after)
        relative=str(path.relative_to(ROOT))
        patches.extend(difflib.unified_diff(before.splitlines(True),after.splitlines(True),'a/'+relative,'b/'+relative))
        manifest.append({'path':relative,'before_sha256':hashlib.sha256(before.encode()).hexdigest(),'after_sha256':hashlib.sha256(after.encode()).hexdigest()})
    (HERE/'runtime-retirement.patch').write_text(''.join(patches))
    (HERE/'manifest.json').write_text(json.dumps({'status':'prepared only; apply after coordinator C2 approval with A05/A07 runtime and coordinator counter patches','base_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'files':manifest},indent=2)+'\n')
if __name__=='__main__':main()
