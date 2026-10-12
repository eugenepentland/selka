#!/usr/bin/env python3
"""Run isolated draft checks inside one externally owned build admission lease."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--zig', type=Path, required=True)
parser.add_argument('--source-revision', required=True)
parser.add_argument('--output-dir', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[4]
if os.environ.get('MYLANG_ADMISSION_KIND') != 'build' or not os.environ.get('MYLANG_ADMISSION_DIR'):
    raise SystemExit('run this harness through scripts/build-slot.sh build')
out = args.output_dir.resolve()
out.mkdir(parents=True, exist_ok=True)
suffix = args.source_revision[:9]
scratch = root / '.tmp/memory-closeout/A10'
package = scratch / ('component-retirement-' + suffix)
launch = scratch / ('launch-retirement-' + suffix)
verification = scratch / ('verification-retirement-' + suffix)
draft = root / 'experiments/memory-closeout-20261012/A10/rollout' / suffix
commands = []


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(name, command):
    start = time.monotonic()
    result = subprocess.run([str(x) for x in command], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    path = out / (name + '.log')
    path.write_bytes(result.stdout)
    row = dict(name=name, argv=[str(x) for x in command], cwd=str(root), status=result.returncode,
               elapsed_seconds=time.monotonic() - start, log=path.name, log_sha256=sha(path))
    commands.append(row)
    (out / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    print(name + ': ' + str(result.returncode), flush=True)
    if result.returncode:
        raise SystemExit(result.stdout.decode(errors='replace'))


run('format', [args.zig, 'fmt', '--check', package / 'selfhost', package / 'build.zig', launch / 'src/component_launch.zig',
               launch / 'src/component_protocol_test.zig', launch / 'src/cache_plan_protocol_test.zig'])
for label, directory, patch, reverse in [
    ('C2-apply', scratch / 'rollout-draft/base', 'C2-default.patch', False),
    ('C3-cli-apply', scratch / 'rollout-draft/C2', 'C3-cli-selector-retirement.patch', False),
    ('C3-package-reverse', package, 'C3-component-retirement.patch', True),
    ('C3-root-default-reverse', package, 'C3-root-component-default-request.patch', True),
    ('C3-launch-reverse', launch, 'C3-component-launch.patch', True),
    ('C3-verification-reverse', verification, 'C3-verification-package-request.patch', True),
]:
    command = ['git', 'apply', '--check', '--directory=' + str(directory.relative_to(root))]
    if reverse:
        command.append('--reverse')
    run(label, [*command, draft / patch])
builder = package / 'selka-components'
run('component-builder', [args.zig, 'build-exe', package / 'selfhost/components.zig', '-OReleaseSafe', '-fllvm', '-flld', '-femit-bin=' + str(builder)])
run('component-orchestration', ['python3', '-B', package / 'selfhost/test_components.py', '--builder', builder, '--zig', args.zig, '-v'])
run('index-protocol', [args.zig, 'test', launch / 'src/component_protocol_test.zig', '-femit-bin=' + str(launch / 'index-all-tests')])
run('planner-protocol', [args.zig, 'test', launch / 'src/cache_plan_protocol_test.zig', '-femit-bin=' + str(launch / 'planner-all-tests')])
run('verification-package', ['python3', '-B', '-m', 'unittest', 'discover', '-s', verification / 'scripts', '-p', 'verify_cache_test.py', '-k', 'CheckedComponentPackage', '-v'])
report = dict(status='PASS isolated UNAPPLIED drafts only; no C2/C3 or package qualification', source_revision=args.source_revision,
              guest_abi='mylang-checked-owned-v1', historical_seed_sha256=sha(root / 'selfhost/component-seed.json'),
              zig_sha256=sha(args.zig.resolve()), builder_sha256=sha(builder),
              patch_sha256={p.name: sha(p) for p in sorted(draft.glob('*.patch'))}, commands=commands,
              notes=['Native component coordinator tests use fake compiler/archive fixtures; no real C3 pin created.',
                     'Launch tests use synthetic deployment scripts; real package ABI/protocol proof remains required.',
                     'An earlier draft warm-manifest test used a fixed-size memcpy for unequal string lengths and trapped; corrected to allocated replacement before this exact run.',
                     'Elapsed values describe harness work only, not performance benchmark samples.'])
(out / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
