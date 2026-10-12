#!/usr/bin/env python3
"""Qualify exact borrowed two-parent selections on one frozen compiler."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
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
args.output = ROOT / '.tmp/memory-closeout/A04/selections' / args.phase
evidence = HERE / args.phase
assert not evidence.exists(), 'choose a fresh phase'
evidence.mkdir()
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
identity = subprocess.check_output(['git', 'rev-parse', args.source_commit], cwd=ROOT, text=True).strip()
spec = importlib.util.spec_from_file_location('selection_qualify', ROOT / 'experiments/zero-rc-closeout-20261011/qualify.py')
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
report = {'compiler': str(args.compiler), 'compiler_sha256': digest(args.compiler), 'source_commit': identity,
          'default_ownership': args.default_ownership, 'ownership_support_sha256': ownership.digest(),
          'harness_sha256': digest(Path(__file__)), 'cases': {}, 'negatives': {},
          'limitations': 'Intermediate semantic/counter/structural qualification; no runtime/RSS or final milestone claim.'}
env = dict(os.environ, MYL_CORE_LEAKCHECK='1', ZIG=str(args.zig), MYLANG_ZIG=str(args.zig))
for name in ('MYLANG_COUNTERS', 'MYLANG_OPTIONS', 'MYLANG_CORE_SANITIZE'):
    env.pop(name, None)


def save():
    (evidence / 'results.json').write_text(json.dumps(report, indent=2) + '\n')


source = ROOT / 'tests/lang/a04_borrow_selections.my'
lanes = [(mode, [*ownership.flags(args), *flags]) for mode, flags in q.common.MODES.items()]
if not args.default_ownership:
    lanes.append(('ordinary', ['--release']))
with admission('build'):
    for mode, flags in lanes:
        try:
            row = dict(ownership.lane(q, args, env, 'complete', source, flags, mode, 0, answer=''), status='passed')
            compiler_stderr = (args.output / 'complete' / mode / 'build.stderr').read_text()
            assert not compiler_stderr, 'compiler stderr must be empty; guest counters do not audit compiler storage'
        except (AssertionError, OSError, subprocess.SubprocessError) as error:
            row = {'status': 'failed', 'error': str(error), 'source_sha256': digest(source)}
        report['cases'][mode] = row
        target = evidence / 'raw' / mode
        target.mkdir(parents=True)
        for pattern in ('*.my', '*.json', '*.stdout', '*.stderr'):
            for artifact in (args.output / 'complete' / mode).glob(pattern):
                shutil.copyfile(artifact, target / artifact.name)
        save()
        print(mode, row['status'], flush=True)
with admission('build'):
    for name, code in [('first_argument_invalidated', 'E_SINGLE_OWNER_OVERLAP'),
                       ('optional_receiver_invalidated', 'E_SINGLE_OWNER_OVERLAP'),
                       ('first_parent_invalidated', 'E_SINGLE_OWNER_OVERLAP'),
                       ('second_parent_invalidated', 'E_SINGLE_OWNER_OVERLAP'),
                       ('fresh_escape', 'E_SINGLE_OWNER_BORROW'), ('selected_view', 'E_ZERO_RC_VIEW_ESCAPE'),
                       ('affine_optional', 'E_GENERIC_REQUIREMENT'), ('pending_result_optional', 'E_GENERIC_REQUIREMENT')]:
        source = HERE / (name + '.my')
        command = [str(args.compiler), 'check', str(source), *ownership.flags(args)]
        result = subprocess.run(command, capture_output=True, text=True, cwd=ROOT, env=env, timeout=60)
        report['negatives'][name] = {'source_sha256': digest(source), 'command': command, 'exit_status': result.returncode,
                                     'stdout': result.stdout, 'stderr': result.stderr, 'expected': code,
                                     'status': 'passed' if result.returncode == 1 and code in result.stderr else 'failed'}
        save()
        print(name, report['negatives'][name]['status'], flush=True)
assert digest(args.compiler) == report['compiler_sha256'], 'compiler changed'
report['summary'] = {'native_lanes': len(report['cases']), 'negative_cases': len(report['negatives']),
                     'failed': sum(row['status'] != 'passed' for group in ('cases', 'negatives') for row in report[group].values())}
save()
print(report['summary'], flush=True)
raise SystemExit(bool(report['summary']['failed']))
