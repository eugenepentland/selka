#!/usr/bin/env python3
"""Build the separate endpoint diagnostic with the exact matched RF guest flags."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts

REVISIONS = {'before': '6cf7bdce11bc205862bf75b9d9ce72e46caad0a2',
             'after': '5e97db47f08f667d97419abafd098df263a2aec3'}


def guest_policy(command):
    result = list(command)
    result[2] = '<source>'
    for flag in ('-o', '--cache-dir'):
        result[result.index(flag) + 1] = '<path>'
    return result


def reused_before(args, source, identity, manifest_hash, backend):
    path = args.reuse_before_build.resolve()
    assert runner.digest(path) == args.expected_before_build_sha256
    saved = json.loads(path.read_text())
    assert saved['status'] == 'complete' and saved['manifests']['before']['sha256'] == manifest_hash
    assert saved['manifests']['before']['identity'] == identity
    assert saved['source_and_helper_sha256'][saved['source']] == runner.digest(source)
    old = saved['builds']['before-' + backend]
    assert old['exit_status'] == 0
    assert runner.digest(old['binary']) == old['binary_sha256']
    assert runner.digest(old['backend_manifest']) == old['backend_manifest_sha256']
    assert runner.digest(saved['source']) == runner.digest(source)
    assert old['command'][:2] == [identity['build_wrapper'], 'build']
    assert guest_policy(old['command'][2:]) == guest_policy(identity['commands']['collections/my-' + backend])
    return {**old, 'reused_verified_build': {'report': str(path), 'report_sha256': args.expected_before_build_sha256,
                                          'source_sha256': runner.digest(source), 'policy_unchanged': True}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before-manifest', type=Path, required=True)
    parser.add_argument('--after-manifest', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reuse-before-build', type=Path, required=True)
    parser.add_argument('--expected-before-build-sha256', required=True)
    args = parser.parse_args()
    source = Path(__file__).with_name('append_endpoint.my')
    bindings = {str(path): runner.digest(path) for path in (source, Path(__file__), ROOT / 'benchmarks/runtime/runner.py',
                ROOT / 'benchmarks/runtime/diagnostics/holdouts.py')}
    args.work = args.work.resolve()
    args.work.mkdir(parents=True, exist_ok=True)
    report = {'schema': 'mylang-goal110-bounded-rem-supplement-build-v1', 'status': 'in_progress',
              'started_utc': datetime.now(timezone.utc).isoformat(), 'source': str(source),
              'source_and_helper_sha256': bindings, 'manifests': {}, 'builds': {}}
    for label, revision in REVISIONS.items():
        path = getattr(args, label + '_manifest').resolve()
        digest = runner.digest(path)
        manifest = json.loads(path.read_text())
        holdouts.check_manifest(path, digest, manifest)
        identity = manifest['identity']
        assert identity['source_revision'] == revision
        assert identity['compiler_build_receipt']['receipt']['compiler_optimize'] == {'before': 'ReleaseFast', 'after': 'Debug'}[label]
        report['manifests'][label] = {'path': str(path), 'sha256': digest, 'identity': identity}
        for backend in ('llvm', 'qbe'):
            arm = label + '-' + backend
            if label == 'before':
                report['builds'][arm] = reused_before(args, source, identity, digest, backend)
                print('Reused verified immutable supplementary ' + arm, flush=True)
                continue
            work = args.work / arm
            work.mkdir()
            binary = work / 'append-endpoint'
            template = identity['commands']['collections/my-' + backend]
            command = list(template)
            assert command[1] == 'build' and '--keep-symbols' in command
            command[2] = str(source)
            command[command.index('-o') + 1] = str(binary)
            command[command.index('--cache-dir') + 1] = str(work / 'mycache')
            environment = {key: str(work / key.lower()) for key in ('TMPDIR', 'ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR')}
            for directory in environment.values():
                Path(directory).mkdir()
            actual = [identity['build_wrapper'], 'build', *command]
            print('Building supplementary ' + arm, flush=True)
            done = subprocess.run(actual, cwd=ROOT, env={**runner.runtime_environment(), **environment},
                                  capture_output=True, text=True, timeout=1800)
            assert done.returncode == 0, done.stdout + done.stderr
            backend_path = Path(str(binary) + '.qbe-manifest.json')
            backend_doc = json.loads(backend_path.read_text())
            assert backend_doc['backend'] == backend
            if backend == 'llvm':
                assert str(backend_doc['optimization']) == '3' and backend_doc['lto']
            report['builds'][arm] = {'command': actual, 'environment': environment, 'exit_status': done.returncode,
                                    'stdout': done.stdout, 'stderr': done.stderr, 'binary': str(binary),
                                    'binary_sha256': runner.digest(binary), 'backend_manifest': str(backend_path),
                                    'backend_manifest_sha256': runner.digest(backend_path)}
        holdouts.check_manifest(path, digest, manifest)
    assert bindings == {path: runner.digest(path) for path in bindings}
    report.update(status='complete', finished_utc=datetime.now(timezone.utc).isoformat())
    with args.output.open('x') as target:
        target.write(json.dumps(report, indent=2) + '\n')
    print('PASS four source-bound supplementary RF guests; no timing performed')


if __name__ == '__main__':
    main()
