#!/usr/bin/env python3
"""Read exact selected RC ELF/IL and compiler rules; execute no guests."""
from pathlib import Path
import base64, gzip, hashlib, json, os, re, subprocess

lane = Path(__file__).resolve().parents[2]
experiment = Path(__file__).resolve().parent
work = lane / '.tmp-lox-load-frame-diagnostic-20261003'
assert not work.exists()
work.mkdir()
assert not (set(os.sched_getaffinity(0)) & {2, 3, 10, 11})
root = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003')
source = root / '.tmp-lox-round3/ast'
control = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-borrow-assert-20261003/.tmp-lox-borrow-assert-20261003')
binary = control / 'fixed-qbe-ast'
builds = control / 'static-builds.json'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
assert sha(binary) == '246f21781fd58c7141dbe0992101c842e62d732d9ce47e209d55821d02b11b25'
manifest = control / 'cache-fixed-qbe/modules/2bb8a68b7e37056c8a8cea159cfcc1b88b00617e550c432d912e9206a5ece17b/out/vm.manifest.json'
document = json.loads(manifest.read_text())
selected = {f['name']: f for f in document['functions'] if f['name'] in ['vm::load_frame', 'vm::run']}
assert len(selected) == 2
base = '3b33df52044a10cb84b908f8b1641af439e8c729'
core = ['src/bytecode_inline.zig', 'src/qbe.zig', 'src/rc_calls.zig', 'src/qbe_rc_borrow.zig', 'src/rc_borrow_certificate.zig', 'src/rc_readonly_body.zig', 'src/qbe_rc_return.zig']
inputs = {binary, builds, manifest, Path(__file__).resolve()}
inputs.update(p for p in source.rglob('*') if p.is_file())
for row in selected.values():
    inputs.add(Path(document['store']) / row['il_digest'])
snapshot = lambda: {str(p): sha(p) for p in sorted(inputs)}
before = snapshot()
rows = {}
for name, row in selected.items():
    stem = name.replace('::', '-')
    il = Path(document['store']) / row['il_digest']
    text = il.read_text()
    (work / (stem + '.ssa')).write_bytes(il.read_bytes())
    argv = ['objdump', '-d', '--no-show-raw-insn', '--disassemble=' + row['symbol'], str(binary)]
    asm = subprocess.check_output(argv, text=True)
    (work / (stem + '.asm')).write_text(asm)
    positions = row['meta']['positions'].split()
    sites, pc = [], None
    for number, line in enumerate(text.splitlines(), 1):
        if (match := re.match(r' dbgloc (\d+)$', line)):
            pc = int(match[1])
        if line.startswith(' blit '):
            sites.append(dict(line=number, pc=pc, source_position=positions[pc - 1] if pc else None, instruction=line))
    rows[name] = dict(symbol=row['symbol'], source_bytecode_positions=len(positions),
        il_sha256=sha(il), asm_sha256=sha(work / (stem + '.asm')), objdump_argv=argv,
        static_native_instructions=len(re.findall(r'^\s*[0-9a-f]+:\s+', asm, re.M)),
        static_native_calls=len(re.findall(r':\s+call\s', asm)),
        metadata=row['meta'], blit_sites=sites)
for path in core:
    raw = subprocess.check_output(['git', 'show', base + ':' + path], cwd=lane)
    assert raw == (lane / path).read_bytes(), path
    (work / Path(path).name).write_bytes(raw)
after = snapshot()
assert after == before
summary = dict(base=base, source=str(source), binary=str(binary), binary_sha256=sha(binary),
    before=before, after=after, verified_after=True, functions=rows,
    source37={str(p.relative_to(source)): sha(p) for p in source.rglob('*') if p.is_file()},
    core={p: sha(lane / p) for p in core},
    limits='Read-only static selected RC inspection. No builds, guest execution, GC/artifact qualification, tracing or performance run.')
(experiment / 'inspection.json').write_text(json.dumps(summary, indent=2) + '\n')
raw = {str(p.relative_to(work)): dict(sha256=sha(p), bytes=p.stat().st_size, base64=base64.b64encode(p.read_bytes()).decode()) for p in sorted(work.iterdir()) if p.is_file()}
(experiment / 'raw.json.gz').write_bytes(gzip.compress(json.dumps(raw, separators=(',', ':')).encode(), compresslevel=9, mtime=0))
print(json.dumps(dict(verified_after=True, functions={name: {k: r[k] for k in ['source_bytecode_positions', 'static_native_instructions', 'static_native_calls']} for name, r in rows.items()}, raw_sha256=sha(experiment / 'raw.json.gz'))))
