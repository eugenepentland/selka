from pathlib import Path
import gzip, hashlib, json, re, subprocess

R = Path.cwd()
W = R / '.tmp-rc'
O = R / 'experiments/d9-rc-byte-dict-record-gate-20260927'
SOURCE = '368f0357cd107895cc45863d379a6fdcd3dd3018'
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() == SOURCE
assert subprocess.run(['git', 'diff', '--quiet', 'HEAD']).returncode == 0
assert (W / 'byte-dict-record-gate-status.log').read_text().splitlines() == ['test 0', 'test-qbe 0', 'test-qbe-build 0', 'fmt-check 0']
assert (W / 'byte-dict-record-sweep-status.log').read_text().splitlines() == ['qbe 0', 'llvm 0']
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
compiler = W / 'install-byte-dict-record/bin/mylang'
digest = sha(compiler)
assert digest == (W / 'byte-dict-record-compiler.sha256').read_text().split()[0]
O.mkdir(exist_ok=True)

def packed(source, name):
    (O / name).write_bytes(gzip.compress(source.read_bytes(), mtime=0))

identity = {'source_commit': SOURCE, 'compiler_mode': 'Debug', 'compiler_path': str(compiler),
            'compiler_sha256': digest, 'commands': {}, 'sweeps': {}}
for step in ('final-build', 'test', 'test-qbe', 'test-qbe-build', 'fmt-check'):
    p = W / ('byte-dict-record-' + step + '.log')
    summaries = re.findall(r'^Build Summary:.*$', p.read_text(), re.M)
    assert len(summaries) == 1 and 'failed' not in summaries[0], (step, summaries)
    identity['commands'][step] = {'exit_code': 0, 'summary': summaries[0]}
    packed(p, step + '.log.gz')
for backend in ('qbe', 'llvm'):
    p = W / ('byte-dict-record-sweep-' + backend + '.json')
    x = json.loads(p.read_text())
    assert all(x[k] == 0 for k in ('failed', 'skipped', 'cached', 'dropped', 'unloaded'))
    assert x['passed'] == x['executed'] == 1035 and x['programs'] == 176
    identity['sweeps'][backend] = {k: v for k, v in x.items() if k != 'tests'}
    packed(p, 'sweep-' + backend + '.json.gz')
    packed(W / ('byte-dict-record-sweep-' + backend + '.log'), 'sweep-' + backend + '.log.gz')
for kind in ('gate', 'sweep'):
    (O / (kind + '.sh')).write_bytes((W / (kind + '-byte-dict-record.sh')).read_bytes())
    packed(W / ('byte-dict-record-' + kind + '-status.log'), kind + '-status.log.gz')
guardian = W / 'byte-dict-record-guardian.log'
assert '88 check(s) passed' in guardian.read_text()
identity['guardian_checks'] = 88
packed(guardian, 'guardian.log.gz')
(O / 'README.md').write_text('# Joined byte, dictionary and record-read correctness gate\n\nFrozen source `368f0357` combines guarded immutable-byte loops `2af700c7`,\ncertified empty dictionary drops `bca4ac31`, bounded named-record field reads\n`c1224f30`, and loop-guard instruction-context correction `238db806`.\nEach slice joined through a real two-parent merge. The record-read merge\npreserves both refinements and initializers, uses the grouped record plan in\nthe readonly verifier, and retains both test imports and the byte-loop proof.\n\nThe Debug install succeeds (19/19 steps). All four required gate commands\npass: main 94/94 steps with 2,383 executed tests; QBE 51/51 with 455 tests;\nnative build 29/29; formatting 2/2. Whole-tree Guardian passes all 88 checks.\nBoth forced counted RC sweeps pass 1,035 assertions across 176 programs,\nwith zero failures, skips, cached verdicts, dropped files or unloaded files.\nLLVM uses --release, which selects LLVM O3 and full LTO. Tracked source and\nHEAD remained frozen throughout the gate and both sweeps.\n\nIdentity, exact summaries, raw compressed logs, terminal statuses, drivers\nand artifact hashes are archived here. Exit-zero Zig failed-command footers\nare retained; terminal statuses and final summaries determine the result.\nThe collector is a one-shot script for the frozen source; it does not run\ntests. The verifier checks archived receipts and optionally the live compiler.\n\nThis establishes combined correctness, not performance acceptance. The\nseparate byte/dictionary/Lox comparisons use their documented isolated bases.\nNo new combined 30- or 43-program performance claim is made. GC remains the\ndefault; main and the pending devspeed branch are unchanged.\n')
(O / 'archive.py').write_bytes(Path(__file__).read_bytes())
identity['artifacts'] = {p.name: sha(p) for p in sorted(O.iterdir()) if p.is_file() and p.name != 'identity.json'}
(O / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
print(json.dumps(identity['commands'], indent=2))
print(json.dumps(identity['sweeps'], indent=2))
