from pathlib import Path
import os, json, subprocess, hashlib, re

root = Path.cwd()
w = root / '.tmp-named-record'
before = root.parent / 'd9-rc-integration/.tmp-rc/install-ownership-joined-fixed/bin/mylang'
after = w / 'install-final/bin/mylang'
env = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
env.update(TMPDIR=str(w/'tmp'), ZIG_LOCAL_CACHE_DIR=str(w/'guest-zig-cache'), MYLANG_MEMORY_LIMIT='128M')
header = '''record State:
    values: list[int]
    code: list[int]
    links: list[int]
    count: int
'''
sources = {
    'steps': header + '''def main(out: Stream) -> int:
    state = State([7], [8], [9], 2)
    out.print("before")
    state.count = state.count + 4
    out.print(state.count)
    return 0
''',
    'memory': header + '''def replace(state: mut State):
    state = State([17 for index in range(1000000)], [18], [19], 40)
def main(out: Stream) -> int:
    state = State([7], [8], [9], 2)
    out.print("before")
    replace(mut state)
    state.count = state.count + 4
    out.print(state.count)
    return 0
''',
    'overflow': header + '''def main(out: Stream) -> int:
    state = State([7], [8], [9], 9223372036854775807)
    out.print("before")
    state.count = state.count + 4
    out.print(state.count)
    return 0
''',
}
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
r = json.loads((w/'traps.json').read_text())
assert r['before_sha256'] == sha(before) and r['after_sha256'] == sha(after)
def save():
    (w/'traps.json').write_text(json.dumps(r, indent=2)+'\n')
for case, source in sources.items():
    if len([row for row in r['rows'] if row['case'] == case]) == 8:
        continue
    path = w/f'trap-{case}.my'
    path.write_text(source)
    d = subprocess.run([str(after), 'dump-bytecode', str(path)], env=env, text=True, capture_output=True)
    assert d.returncode == 0, d.stderr
    (w/f'trap-{case}-bytecode.txt').write_text(d.stdout)
    update = int(re.search(r'^\s+(\d+)\s+UPDATE_RECORD', d.stdout, re.M)[1])
    # Main has no guest calls on the steps path: these exact budgets straddle
    # the update and original final STORE. Zero is the ordinary success control.
    budgets = [update, update+1, update+2, 0] if case == 'steps' else [0]
    for arm, compiler in [('before', before), ('after', after)]:
        for backend in ['qbe', 'llvm']:
            for mode in ['gc', 'rc']:
                binary = w/f'trap-{case}-{arm}-{mode}-{backend}'
                cmd = [str(root/'scripts/build-slot.sh'), 'build', str(compiler), 'build', str(path), '-o', str(binary), '--cache-dir', str(w/'trap-cache'), f'--backend={backend}', '--mode=Debug']
                if backend == 'llvm': cmd += ['--llvm-opt=3', '--lto']
                if mode == 'rc': cmd += ['--rc-runtime=stats']
                d = subprocess.run(cmd, env=env, text=True, capture_output=True)
                row = dict(case=case, arm=arm, backend=backend, mode=mode, command=cmd, build_exit=d.returncode, build_stderr=d.stderr, runs=[])
                r['rows'].append(row); save()
                assert d.returncode == 0, row
                row['manifest'] = json.loads(Path(str(binary)+'.qbe-manifest.json').read_text())
                assert row['manifest']['backend'] == backend
                row['binary_sha256'] = sha(binary)
                for budget in budgets:
                    flags = ['--gc-stress'] if mode == 'gc' else []
                    if budget: flags.append(f'--max-steps={budget}')
                    runenv = env | {'MYLANG_OPTIONS': ' '.join(flags)}
                    if case == 'memory': runenv['MYLANG_MEMORY_LIMIT'] = '1M'
                    d = subprocess.run([str(binary)], env=runenv, text=True, capture_output=True, timeout=10)
                    entry = dict(budget=budget, exit=d.returncode, stdout=d.stdout, stderr=d.stderr, environment={k:v for k,v in runenv.items() if k.startswith('MYLANG_')})
                    row['runs'].append(entry); save()
                    expected = 'R_MEMORY_BUDGET' if case == 'memory' else 'R_OVERFLOW' if case == 'overflow' else 'R_STEP_LIMIT'
                    if case == 'steps' and budget == 0:
                        assert d.returncode == 0 and d.stdout == 'before\n6\n', entry
                    else:
                        assert d.returncode == 1 and expected in d.stderr and d.stdout == 'before\n', entry
                    if mode == 'rc':
                        counts = json.loads(next(s.removeprefix('MYLANG_RC_COUNTS ') for s in d.stderr.splitlines() if s.startswith('MYLANG_RC_COUNTS ')))
                        entry['counts'] = counts
                        assert counts['heap_allocate'] == counts['retire'] and counts['owner_acquire']+counts['heap_allocate'] == counts['owner_release'] and counts['hold_acquire'] == counts['hold_release'] and not counts['saturated'], entry
                    save()
                print('PASS', case, arm, mode, backend, flush=True)
for case in sources:
    for mode in ['gc', 'rc']:
        for backend in ['qbe', 'llvm']:
            rows = [x for x in r['rows'] if (x['case'],x['mode'],x['backend']) == (case,mode,backend)]
            assert [[(z['budget'],z['exit'],z['stdout']) for z in x['runs']] for x in rows][0] == [[(z['budget'],z['exit'],z['stdout']) for z in x['runs']] for x in rows][1]
print('MATCHED EXACT BOUNDARIES', flush=True)
