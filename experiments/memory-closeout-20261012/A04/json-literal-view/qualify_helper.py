#!/usr/bin/env python3
"""Test a private read-only JSON comparison helper on the same frozen compiler."""
import argparse
import difflib
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(HERE.parent))
from build_admission import admission
import ownership_commands as ownership

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--compiler-sha256', required=True)
parser.add_argument('--source-commit', required=True)
parser.add_argument('--phase', required=True)
options = parser.parse_args()
compiler = options.compiler.resolve()
compiler_sha = options.compiler_sha256
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
assert digest(compiler) == compiler_sha
source_commit = subprocess.check_output(['git', 'rev-parse', options.source_commit], cwd=ROOT, text=True).strip()
# Keep the historical source pair fixed after production adopts the helper.
source = (HERE / 'readonly-helper-01/original-json.my').read_text()
old = '    if scanner.data[start:start + len(word)] != word:'
assert source.count(old) == 1
candidate = source.replace(old, '    if not literal_matches(scanner.data, start, word):')
marker = '# One of the three bare literals, matched exactly.\n'
helper = '# Compare a borrowed byte range before the caller updates its scanner.\nfunc literal_matches(data: bytes, start: int, word: bytes) -> bool:\n    return data[start:start + len(word)] == word\n\n\n'
candidate = candidate.replace(marker, helper + marker)
(HERE / 'readonly-helper.patch').write_text(''.join(difflib.unified_diff(source.splitlines(True), candidate.splitlines(True), fromfile='a/src/stdlib/json.my', tofile='b/src/stdlib/json.my')))
assert candidate == (HERE / 'readonly-helper-01/helper-json.my').read_text()
phase = HERE / options.phase
assert not phase.exists(), 'attempts are immutable'
phase.mkdir()
output = ROOT / '.tmp/memory-closeout/A04/json-literal-view' / options.phase
output.mkdir(parents=True)
fixture = output / 'fixture.my'
fixture.write_bytes((HERE / 'readonly-helper-01/raw/original/release/main.my').read_bytes())
args = SimpleNamespace(compiler=compiler, zig=Path(os.environ['ZIG']), output=output, default_ownership=False)
spec = importlib.util.spec_from_file_location('historical_qualify', ROOT / 'experiments/zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
env = dict(os.environ, MYL_CORE_LEAKCHECK='1', ZIG=str(args.zig), MYLANG_ZIG=str(args.zig))
for key in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
    env.pop(key, None)
report = {'compiler': str(compiler), 'compiler_sha256': compiler_sha, 'source_commit': source_commit, 'library_source_base': 'bed11cf3bf3102ffec44487e431a1573fdf02ad5',
          'harness_sha256': digest(Path(__file__)), 'fixture_sha256': digest(fixture), 'cases': {}, 'production_changed': False,
          'limits': 'Same compiler, controlled local library-source change; no runtime/RSS claim. All original fixture assertions retained.'}
for name, content in [('original', source), ('helper', candidate)]:
    (phase / (name + '-json.my')).write_text(content)
    lanes = [(mode, ['--experimental-zero-rc', *flags]) for mode, flags in q.common.MODES.items()]
    lanes.append(('ordinary', ['--release']))
    with admission('build'):
        for mode, flags in lanes:
            directory = output / name / mode
            directory.mkdir(parents=True)
            (directory / 'a04_json.my').write_text(content)
            try:
                row = dict(ownership.lane(q, args, env, name, fixture, flags, mode, 42, answer=''), status='passed')
            except (AssertionError, OSError, subprocess.SubprocessError) as error:
                row = {'status': 'failed', 'error': str(error)}
            row['library_source_sha256'] = hashlib.sha256(content.encode()).hexdigest()
            report['cases'][name + '/' + mode] = row
            raw = phase / 'raw' / name / mode
            raw.mkdir(parents=True)
            for pattern in ('*.my', '*.json', '*.stdout', '*.stderr'):
                for path in directory.glob(pattern):
                    shutil.copyfile(path, raw / path.name)
            (phase / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
            print(name, mode, row['status'], flush=True)
assert digest(compiler) == compiler_sha
report['summary'] = {'lanes': len(report['cases']), 'failed': sum(row['status'] != 'passed' for row in report['cases'].values())}
(phase / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
print(report['summary'], flush=True)
raise SystemExit(bool(report['summary']['failed']))
