from pathlib import Path
import gzip, hashlib, json, re, subprocess

R = Path.cwd()
W = R / '.tmp-rc'
O = R / 'experiments/d9-rc-entry-loops-gate-20260927'
SOURCE = '4e5c0cd638e55b86ef0d99112872e02ae41dbe89'
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() == SOURCE
assert subprocess.run(['git', 'diff', '--quiet', 'HEAD']).returncode == 0
assert (W / 'entry-loops-gate-status.log').read_text().splitlines() == ['test 0', 'test-qbe 0', 'test-qbe-build 0', 'fmt-check 0']
assert (W / 'entry-loops-sweep-status.log').read_text().splitlines() == ['qbe 0', 'llvm 0']
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
compiler = W / 'install-entry-loops/bin/mylang'
digest = sha(compiler)
assert digest == (W / 'entry-loops-compiler.sha256').read_text().split()[0]
O.mkdir(exist_ok=True)

def packed(source, name):
    (O / name).write_bytes(gzip.compress(source.read_bytes(), mtime=0))

identity = {'source_commit': SOURCE, 'compiler_mode': 'Debug', 'compiler_path': str(compiler),
            'compiler_sha256': digest, 'commands': {}, 'sweeps': {}}
for step in ('final-build', 'test', 'test-qbe', 'test-qbe-build', 'fmt-check'):
    p = W / ('entry-loops-' + step + '.log')
    summaries = re.findall(r'^Build Summary:.*$', p.read_text(), re.M)
    assert len(summaries) == 1 and 'failed' not in summaries[0], (step, summaries)
    identity['commands'][step] = {'exit_code': 0, 'summary': summaries[0]}
    packed(p, step + '.log.gz')
for backend in ('qbe', 'llvm'):
    p = W / ('entry-loops-sweep-' + backend + '.json')
    x = json.loads(p.read_text())
    assert all(x[k] == 0 for k in ('failed', 'skipped', 'cached', 'dropped', 'unloaded'))
    assert x['passed'] == x['executed'] == 1049 and x['programs'] == 179
    identity['sweeps'][backend] = {k: v for k, v in x.items() if k != 'tests'}
    packed(p, 'sweep-' + backend + '.json.gz')
    packed(W / ('entry-loops-sweep-' + backend + '.log'), 'sweep-' + backend + '.log.gz')
for kind in ('gate', 'sweep'):
    (O / (kind + '.sh')).write_bytes((W / (kind + '-entry-loops.sh')).read_bytes())
    packed(W / ('entry-loops-' + kind + '-status.log'), kind + '-status.log.gz')
guardian = W / 'entry-loops-guardian.log'
assert '88 check(s) passed' in guardian.read_text()
identity['guardian_checks'] = 88
packed(guardian, 'guardian.log.gz')
(O / 'README.md').write_text("# Joined entry and loop correctness gate\n\nFrozen source `4e5c0cd6` combines incoming record-field reads `fb4a19a9`,\nraw borrowed/immortal helper entries `0aaf0ddb`, and fast-loop operand\nisolation `ee6e44e3`, on the preceding `368f0357` correctness checkpoint.\nAll three slices joined through real two-parent merges. The combined source\npreserves the grouped record plans, readonly verification and final loop\noperand rewrite after ordinary lowering.\n\nThe Debug install succeeds (19/19 steps). All four required gate commands\npass: main 94/94 steps with 2,404 executed tests; QBE 51/51 with 458 tests;\nnative build 29/29; formatting 2/2. Whole-tree Guardian passes all 88 checks.\nBoth forced counted RC sweeps pass 1,049 assertions across 179 programs,\nwith zero failures, skips, cached verdicts, dropped files or unloaded files.\nLLVM uses --release, which selects LLVM O3 and full LTO. Tracked source and\nHEAD remained frozen throughout the gate and both sweeps.\n\nAn earlier install attempt failed because a partial cleanup of the root's\ninactive Zig object cache left hash metadata referencing deleted files.\nThe remaining inactive cache was cleared and the install and complete gate\nthen passed on the same source. The failed install log, status and explanation\nare retained separately. This was a cache-management error, not a compiler\nsource failure. Exit-zero Zig failed-command footers in successful logs are\nalso retained; terminal statuses and final summaries determine the result.\n\nIdentity, exact summaries, raw compressed logs, terminal statuses, drivers\nand artifact hashes are archived here. The collector is a one-shot script\nfor the frozen source; it does not run tests. The verifier checks archived\nreceipts and optionally the live immutable compiler.\n\nThis establishes combined correctness, not performance acceptance. Isolated\nslice measurements use their own documented bases. A fresh 31-program\ndiagnostic is in progress; the unchanged full 43 programs per backend and\nall instruction/RSS requirements remain mandatory. GC remains the default;\nmain and the pending devspeed branch are unchanged.\n")
for source, name in (
    ('entry-loops-cache-reclaim-failed-final-build.log', 'failed-cache-install.log.gz'),
    ('entry-loops-cache-reclaim-failed-gate-status.log', 'failed-cache-status.log.gz'),
    ('entry-loops-cache-reclaim-failure.json', 'failed-cache-explanation.json.gz'),
):
    packed(W / source, name)
identity['prior_install_failure'] = json.loads((W / 'entry-loops-cache-reclaim-failure.json').read_text())
assert identity['prior_install_failure']['exit_code'] == 1
assert identity['prior_install_failure']['source'] == SOURCE
(O / 'archive.py').write_bytes(Path(__file__).read_bytes())
identity['artifacts'] = {p.name: sha(p) for p in sorted(O.iterdir()) if p.is_file() and p.name != 'identity.json'}
(O / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
print(json.dumps(identity['commands'], indent=2))
print(json.dumps(identity['sweeps'], indent=2))
