"""Archive the precise generated fast arms and original complete fallback."""
import hashlib, json, os, re, subprocess
from pathlib import Path

root = Path.cwd()
work = root / '.tmp-mut-argument/span-emission'
work.mkdir(exist_ok=True)
compiler = root / '.tmp-mut-argument/span-candidate/bin/mylang'
result = {'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(), 'runs': []}
for source in ('experiments/d9-rc-fresh-field-profile-20260927/binary_trees_n12.my', 'tests/lang/rc_fresh_spans.my'):
    command = [str(root / 'scripts/build-slot.sh'), 'build', str(compiler), 'emit-qbe', source, '--rc-runtime', '--drop-step-checks', '--drop-frame-checks']
    run = subprocess.run(command, capture_output=True, text=True, env=dict(os.environ, TMPDIR=str(work)), check=True)
    manifest = json.loads(run.stdout)
    row = {'command': command, 'source_sha256': hashlib.sha256((root / source).read_bytes()).hexdigest(), 'functions': []}
    for function in manifest['functions']:
        if function['name'] not in ('make', 'check', 'branch', 'literal_chain', 'callback'):
            continue
        il = function['il']
        (work / (function['name'] + '.ssa')).write_text(il)
        spans = re.findall(r'\n@rcspan[0-9]+\n(.*?)\n@rcspanslow[0-9]+\n', il, re.S)
        row['functions'].append({'name': function['name'], 'symbol': function['symbol'], 'spans': [
            {'calls': re.findall(r'call \$([^ (]+)', span), 'live_guard_writes': span.count(' storew 1,'), 'clear_guard_writes': span.count(' storew 0,')}
            for span in spans]})
        if function['name'] in ('make', 'branch', 'literal_chain'):
            assert spans, function['name']
        if function['name'] in ('check', 'callback'):
            assert not spans, function['name']
    result['runs'].append(row)
for backend in ('qbe', 'llvm'):
    binary = root / f'.tmp-mut-argument/span-run/trees-{backend}-after-rc'
    symbol = next(f['symbol'] for row in result['runs'] for f in row['functions'] if f['name'] == 'make')
    command = ['objdump', '-d', '--no-show-raw-insn', '--disassemble=' + symbol, str(binary)]
    run = subprocess.run(command, capture_output=True, text=True, check=True)
    (work / (backend + '-make.asm')).write_text(run.stdout)
(work / 'emission.json').write_text(json.dumps(result, indent=2) + '\n')
