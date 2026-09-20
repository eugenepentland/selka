#!/usr/bin/env python3
"""Bounded diagnostic arms; does not modify the production adapter or runtime.

Requires a frozen qbe-units manifest and a completed adapter build receipt/cache.
Each arm links the SAME runtime, metadata, entry, and formatter. See README.md.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import qbe_llvm


def run(args):
    p = subprocess.run(list(map(str, args)), capture_output=True, text=True)
    if p.returncode:
        raise RuntimeError(f"{args}\n{p.stderr}")


def fix_memset(ir):
    """All emitted memset calls have a zero byte and ignore the result."""
    count = 0
    def replace(m):
        nonlocal count
        count += 1
        return (f"  %audit_memset_{count} = inttoptr i64 {m[1]} to ptr\n"
                f"  call void @llvm.memset.p0.i64(ptr %audit_memset_{count}, i8 0, i64 {m[2]}, i1 false)")
    ir = re.sub(r"  call void @memset\(i64 ([^,]+), i64 0, i64 ([^)]+)\)", replace, ir)
    if count:
        ir = ir.replace("declare void @memset(i64, i64, i64)",
                        "declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)")
    return ir


def word_aggregates(ir):
    """Same bytes/alignment, different LLVM aggregate element type/guest ABI."""
    return re.sub(r"\[(\d+) x i8\]", lambda m: f"[{int(m[1]) // 8} x i64]"
                  if int(m[1]) % 8 == 0 else m[0], ir)


def static_scratch(ir):
    """Move constant scratch from the one-shot stack-admission block to entry.

    Diagnostic only: changes physical frame placement, so stack-floor behaviour
    needs its own gate before production use. Never moves loop allocations.
    """
    lines = ir.splitlines()
    moved, kept, block = [], [], ''
    for line in lines:
        if line.endswith(':'):
            block = line[:-1]
        if block.startswith('bb_stackadmit') and re.fullmatch(
                r'  %\w+ = alloca i8, i64 \d+, align (4|8|16)', line):
            moved.append(line)
        else:
            kept.append(line)
    i = next(i for i, line in enumerate(kept) if line.endswith(':')) + 1
    kept[i:i] = moved
    return '\n'.join(kept) + '\n'


def recover_gep(ir):
    """Recover byte GEPs only from an actual ptrtoint origin after mem2reg.

    Same 64-bit modular address addition, no inbounds or alias promises. This
    deliberately leaves integer addresses arriving from arguments/loads alone.
    """
    ptrs, out = {}, []
    for line in ir.splitlines():
        if line.startswith('define '):
            ptrs = {}
        m = re.match(r'  (%[\w.]+) = ptrtoint ptr (%[\w.]+) to i64', line)
        if m:
            ptrs[m[1]] = m[2]
        m = re.fullmatch(r'  (%[\w.]+) = add(?: nuw| nsw)* i64 (%[\w.]+), (-?\d+|%[\w.]+)', line)
        if m:
            name, left, right = m.groups()
            if left not in ptrs and right in ptrs:
                left, right = right, left
            if left in ptrs:
                pointer = name + '.audit_gep'
                out.append(f'  {pointer} = getelementptr i8, ptr {ptrs[left]}, i64 {right}')
                line = f'  {name} = ptrtoint ptr {pointer} to i64'
                ptrs[name] = pointer
        out.append(line)
    return '\n'.join(out) + '\n'


def merge_modules(modules):
    definitions, globals_, declarations = [], {}, {}
    names = set()
    for ir in modules:
        match = re.search(r"^define .*?^}", ir, re.M | re.S)
        assert match
        body = match[0].replace("dllexport ", "dso_local ").replace(" #0 {", " {")
        names.add(re.search(r"@(\w+)\(", body)[1])
        definitions.append(body)
        for line in ir.splitlines():
            if line.startswith("@"):
                name = line.split(" = ")[0]
                assert name not in globals_ or globals_[name] == line
                globals_[name] = line
            if line.startswith("declare "):
                name = re.search(r"@(\S+)\(", line)[1]
                assert name not in declarations or declarations[name] == line, name
                declarations[name] = line
    return ('target triple = "x86_64-unknown-linux-gnu"\n' +
            "\n".join(globals_.values()) + "\n" +
            "\n".join(d for n, d in declarations.items() if n not in names) +
            "\n" + "\n\n".join(definitions) + "\n")


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--manifest', required=True)
    p.add_argument('--receipt', required=True)
    p.add_argument('--formatter', required=True)
    p.add_argument('--work', required=True)
    p.add_argument('--arms', default='control,memset,words,whole,whole-memset,whole-words')
    args = p.parse_args()
    work = Path(args.work).resolve(); work.mkdir(parents=True, exist_ok=True)
    manifest = json.loads(Path(args.manifest).read_text())
    receipt = json.loads(Path(args.receipt).read_text())
    funcs = sorted(manifest['functions'], key=lambda f: f['symbol'])
    sigs = {}
    for f in funcs:
        u = qbe_llvm.parse_unit(f['il'], f['name'])
        sigs[u.name] = qbe_llvm.signature_map(u)
    modules = [qbe_llvm.translate_text(f['il'], f['name'], sigs) for f in funcs]
    guest_objects = {f['object'] for f in receipt['functions']}
    cache = Path(next(iter(guest_objects))).parent
    extras = sorted(str(x) for x in cache.glob('*.o') if str(x) not in guest_objects)
    assert len(extras) == 2, extras
    common = extras + [args.formatter, receipt['runtime_object']]
    provenance = {'manifest': str(Path(args.manifest).resolve()), 'arms': {},
                  'common': {x: hashlib.sha256(Path(x).read_bytes()).hexdigest() for x in common}}
    if (work / 'builds.json').exists():
        previous = json.loads((work / 'builds.json').read_text())
        assert previous['common'] == provenance['common']
        provenance['arms'].update(previous['arms'])
    for arm in args.arms.split(','):
        out = work / arm; out.mkdir(exist_ok=True)
        if arm == 'qbe-stack':
            objects = []
            for i, f in enumerate(funcs):
                lines, moved, block = [], [], ''
                for line in f['il'].splitlines():
                    if line.startswith('@'):
                        block = line
                    if block.startswith('@stackadmit') and re.fullmatch(r' %\w+ =l alloc(?:4|8|16) \d+', line):
                        moved.append(line)
                    else:
                        lines.append(line)
                at = lines.index('@entry') + 1
                lines[at:at] = moved
                src = out / f'{i:03}.ssa'; src.write_text('\n'.join(lines)+'\n')
                asm = src.with_suffix('.s'); obj = src.with_suffix('.o')
                run(['zig-out/bin/qbe', '-t', 'amd64_sysv', '-o', asm, src])
                run(['zig', 'cc', '-c', '-g0', asm, '-o', obj])
                objects.append(obj)
            binary = work / (arm + '.bin')
            run(['zig', 'cc', '-O2', '-fPIC', *objects, *common, '-lm', '-Wl,--gc-sections', '-o', binary])
            provenance['arms'][arm] = {'path': str(binary), 'sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
            (work / 'builds.json').write_text(json.dumps(provenance, indent=2) + '\n')
            print(arm, binary, flush=True)
            continue
        texts = modules
        if 'memset' in arm:
            texts = [fix_memset(ir) for ir in texts]
        if 'words' in arm:
            texts = [word_aggregates(ir) for ir in texts]
        if 'stack' in arm:
            texts = [static_scratch(ir) for ir in texts]
        if arm.startswith('whole'):
            texts = [merge_modules(texts)]
        objects = []
        for i, ir in enumerate(texts):
            src = out / f'{i:03}.ll'; src.write_text(ir)
            obj = src.with_suffix('.o')
            if 'twopass' in arm or 'gep' in arm:
                opt = src.with_suffix('.opt.ll')
                run(['zig', 'cc', '-S', '-emit-llvm', '-O2', '-fPIC', '-g0', src, '-o', opt])
                if 'gep' in arm:
                    opt.write_text(recover_gep(opt.read_text()))
                src = opt
            run(['zig', 'cc', '-c', '-O2', '-fPIC', '-g0', src, '-o', obj])
            objects.append(obj)
        binary = work / (arm + '.bin')
        run(['zig', 'cc', '-O2', '-fPIC', *objects, *common, '-lm', '-Wl,--gc-sections', '-o', binary])
        provenance['arms'][arm] = {'path': str(binary), 'sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
        (work / 'builds.json').write_text(json.dumps(provenance, indent=2) + '\n')
        print(arm, binary, flush=True)


if __name__ == '__main__':
    main()
