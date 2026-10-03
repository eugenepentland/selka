#!/usr/bin/env python3
"""Fresh accounted selected-AST and source-preserved tests; no provider claim."""
from pathlib import Path
import hashlib, json, os, re, subprocess

lane = Path(__file__).resolve().parents[2]
work = lane / '.tmp-lox-native-policy-20261003'
source = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003/.tmp-lox-round3/ast')
compiler = work / 'compiler-final/bin/mylang'
qbe = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/cfg-fix-release/bin/qbe')
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
files = lambda p: {str(f.relative_to(p)): sha(f) for f in sorted(p.rglob('*')) if f.is_file()}
frozen = json.loads((work / 'frozen-source-complete.json').read_text())
assert files(source) == frozen['source37']
assert sha(qbe) == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
environment = {k: v for k, v in os.environ.items() if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
environment.update(TMPDIR=str(work / 'tmp'), ZIG_GLOBAL_CACHE_DIR=str(work / 'global-cache'))
from prefixes import snapshot as prefixes_snapshot
prefixes_before = prefixes_snapshot()
report = dict(immutable_prefixes_before=prefixes_before, complete_source_descriptor_sha256=sha(work / "frozen-source-complete.json"), source37=frozen['source37'], compiler_sha256=sha(compiler), qbe_sha256=sha(qbe),
              provider_scope='Directory runs omit --cases; provider entries are structurally retained only.', runs=[], verified_after=False)
destination = work / 'public.json'
assert not destination.exists()
def observed(node):
    if isinstance(node, dict):
        for item in node.get('tests', []):
            if isinstance(item, dict) and 'name' in item and 'status' in item:
                yield item
        for key, value in node.items():
            if key != 'tests':
                yield from observed(value)
    elif isinstance(node, list):
        for item in node:
            yield from observed(item)
for target, entry, count in [('ast', source, 84)]:
    declarations = list(entry.glob('*.my')) if entry.is_dir() else [entry]
    names = {p.stem + '::' + name for p in declarations for name in re.findall(r'^public def (test_\w+)\(', p.read_text(), re.M)}
    assert len(names) == count
    for backend in ['qbe', 'llvm']:
        for runtime in ['rc', 'gc-stress']:
            name = '-'.join(['public', target, backend, runtime])
            argv = [str(lane / 'scripts/build-slot.sh'), 'build', str(compiler), 'test', str(entry),
                    '--json', '--force', '--jobs', '2', '--max-steps', '1000000000', '--timeout-ms', '120000',
                    '--cache-dir', str(work / ('cache-' + name))]
            argv += ['--release'] if backend == 'llvm' else ['--mode', 'Debug', '--qbe', str(qbe)]
            argv += ['--rc-runtime'] if runtime == 'rc' else ['--gc-stress']
            print('Testing', name, flush=True)
            stdout, stderr = work / (name + '.json'), work / (name + '.stderr')
            with stdout.open('xb') as out, stderr.open('xb') as err:
                result = subprocess.run(argv, cwd=lane, env=environment, stdout=out, stderr=err)
            row = dict(argv=argv, cwd=str(lane), environment={k: environment[k] for k in ['TMPDIR', 'ZIG_GLOBAL_CACHE_DIR']},
                       target=target, backend=backend, runtime=runtime, status=result.returncode,
                       stdout_sha256=sha(stdout), stderr_sha256=sha(stderr))
            report['runs'].append(row)
            destination.write_text(json.dumps(report, indent=2) + '\n')
            assert result.returncode == 0, stderr
            document = json.loads(stdout.read_text())
            tests = list(observed(document))
            assert len(tests) == count and {item['name'] for item in tests} == names
            assert all(item['status'] == 'passed' for item in tests)
            assert document['passed'] == document['executed'] == count
            assert document['failed'] == document['skipped'] == document['cached'] == 0
            row.update(names=sorted(names), summary={k: document[k] for k in ['passed', 'failed', 'skipped', 'cached', 'executed']})
            destination.write_text(json.dumps(report, indent=2) + '\n')
assert files(source) == frozen['source37'] and sha(compiler) == report['compiler_sha256'] and sha(qbe) == report['qbe_sha256']
assert all(sha(lane / p) == h for p, h in frozen['core'].items())
report['immutable_prefixes_after'] = prefixes_snapshot()
assert report['immutable_prefixes_after'] == prefixes_before
report['verified_after'] = True
destination.write_text(json.dumps(report, indent=2) + '\n')
print('336 selected AST fresh passes; no provider execution claim', flush=True)
