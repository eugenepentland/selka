#!/usr/bin/env python3
"""Qualify all five preserved tuple test oracles on a frozen compiler."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'scripts'))
sys.path.insert(0, str(HERE.parent))
from build_admission import admission
import ownership_commands as ownership

parser = argparse.ArgumentParser(description=__doc__)
ownership.add_option(parser)
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--source-commit', required=True)
parser.add_argument('--phase', required=True)
args = parser.parse_args()
args.compiler = args.compiler.resolve()
args.zig = Path(os.environ['ZIG'])
args.output = ROOT / '.tmp/memory-closeout/A04/tuples' / args.phase
evidence = HERE / args.phase
assert not evidence.exists(), 'choose a fresh phase'
evidence.mkdir()
args.output.mkdir(parents=True)
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
spec = importlib.util.spec_from_file_location('tuple_qualify', ROOT / 'experiments/zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
source = ROOT / 'tests/lang/tuples.my'
text = source.read_text()
names = re.findall(r'^public func (test_\w+)\(\) -> bool:', text, re.M)
assert names == json.loads((HERE / 'source-identities.json').read_text())['public_tests']
adapter = args.output / 'all-tests.my'
body = '\n\nfunc main() -> int:\n'
for number, name in enumerate(names, 1):
    body += f'    if not {name}():\n        return {number}\n'
adapter.write_text(text + body + '    return 0\n')
report = {'compiler': str(args.compiler), 'compiler_sha256': digest(args.compiler),
          'source_commit': subprocess.check_output(['git', 'rev-parse', args.source_commit], cwd=ROOT, text=True).strip(),
          'source_sha256': digest(source), 'adapter_sha256': digest(adapter),
          'default_ownership': args.default_ownership, 'harness_sha256': digest(Path(__file__)),
          'public_tests': names, 'source_checks': {}, 'native': {},
          'limitation': 'Intermediate worker qualification; final integrated five-mode rerun remains required.'}
env = dict(os.environ, MYL_CORE_LEAKCHECK='1', ZIG=str(args.zig), MYLANG_ZIG=str(args.zig))
for name in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
    env.pop(name, None)


def save():
    (evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')


with admission('build'):
    checks = [('checked', ownership.flags(args))]
    if not args.default_ownership:
        checks.append(('ordinary', []))
    for mode, flags in checks:
        command = [str(args.compiler), 'check', str(source), *flags, '--no-cache']
        done = subprocess.run(command, capture_output=True, text=True, cwd=ROOT, env=env, timeout=60)
        report['source_checks'][mode] = {'command': command, 'exit_status': done.returncode,
                                        'stdout': done.stdout, 'stderr': done.stderr,
                                        'status': 'passed' if done.returncode == 0 and not done.stderr else 'failed'}
        save()
        print('source', mode, report['source_checks'][mode]['status'], flush=True)
    lanes = [(mode, [*ownership.flags(args), *flags]) for mode, flags in q.common.MODES.items()]
    if not args.default_ownership:
        lanes.append(('ordinary', ['--release']))
    for mode, flags in lanes:
        try:
            row = dict(ownership.lane(q, args, env, 'all-tests', adapter, flags, mode, 0, answer=''), status='passed')
            assert not (args.output / 'all-tests' / mode / 'build.stderr').read_text(), 'compiler stderr must be empty'
        except (AssertionError, OSError, subprocess.SubprocessError) as error:
            row = {'status': 'failed', 'error': str(error)}
        report['native'][mode] = row
        target = evidence / 'raw' / mode
        target.mkdir(parents=True)
        for pattern in ('*.my', '*.json', '*.stdout', '*.stderr'):
            for artifact in (args.output / 'all-tests' / mode).glob(pattern):
                shutil.copyfile(artifact, target / artifact.name)
        save()
        print('native', mode, row['status'], flush=True)
assert digest(args.compiler) == report['compiler_sha256'], 'compiler changed'
report['failed'] = sum(row['status'] != 'passed' for group in ('source_checks', 'native') for row in report[group].values())
save()
raise SystemExit(bool(report['failed']))
