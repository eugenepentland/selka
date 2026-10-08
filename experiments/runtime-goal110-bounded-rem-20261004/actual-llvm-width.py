#!/usr/bin/env python3
"""Untimed actual LLVM boundary pairs for unsigned bias width and exact M."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'benchmarks/runtime'))
import runner
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts

REVISION = '5e97db47f08f667d97419abafd098df263a2aec3'
LEAF = 1 << 59
MAGNITUDE = 15 * LEAF
WIDE_DIVISOR = 4700000000000000000
WIDE_BIAS = 9400000000000000000


def stamp():
    return datetime.now(timezone.utc).isoformat()


def variants(template):
    wide = template.replace('module remainder_semantics', 'module wide_bias').replace('% 1009', '% ' + str(WIDE_DIVISOR)).replace(
        'return len(values) + values[0] + values[-1]', 'return values[0]')
    endpoint = template.replace('module remainder_semantics', 'module exact_magnitude').replace('seed + offset + i * 13', 'seed * 15 + i * 0')
    return {'wide_bias': {'source': wide, 'cases': [
        {'name': 'wide_' + str(seed), 'count': 32, 'seed': seed, 'offset': 0,
         'expected': seed % WIDE_DIVISOR} for seed in (-1, 17, -LEAF, LEAF)]},
        'exact_magnitude': {'source': endpoint, 'cases': [
            {'name': 'exact_' + str(seed), 'count': 32, 'seed': seed, 'offset': 0,
             'dividend': seed * 15, 'expected': 32 + 2 * ((seed * 15) % 1009)}
            for seed in (-LEAF, LEAF)]}}


def reader():
    path = HERE / 'actual-llvm-semantics.py'
    spec = importlib.util.spec_from_file_location('actual_llvm_outcomes', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # Its full-stream/trap parser is unchanged. This driver supplies distinct
    # mathematical Python oracles for the two independently identified recipes.
    module.expected = lambda case: case['expected']
    return module


def build(identity, source, directory, policy):
    directory.mkdir()
    command = list(identity['commands']['collections/my-llvm'])
    command[2] = str(source)
    binary = directory / 'remainder-width'
    command[command.index('-o') + 1] = str(binary)
    command[command.index('--cache-dir') + 1] = str(directory / 'mycache')
    if policy == 'accounted':
        command.append('--step-accounting')
    actual = [identity['build_wrapper'], 'build', *command]
    environment = {key: str(directory / key.lower()) for key in
                   ('TMPDIR', 'ZIG_LOCAL_CACHE_DIR', 'ZIG_GLOBAL_CACHE_DIR')}
    for path in environment.values():
        Path(path).mkdir()
    done = subprocess.run(actual, cwd=ROOT, env={**runner.runtime_environment(), **environment},
                          capture_output=True, text=True, timeout=1800)
    assert done.returncode == 0, done.stdout + done.stderr
    sidecar = Path(str(binary) + '.qbe-manifest.json')
    doc = json.loads(sidecar.read_text())
    assert doc['backend'] == 'llvm' and str(doc['optimization']) == '3' and doc['lto']
    return {'command': actual, 'environment': environment, 'exit_status': done.returncode,
            'stdout': done.stdout, 'stderr': done.stderr, 'binary': str(binary),
            'binary_sha256': runner.digest(binary), 'backend_manifest': str(sidecar),
            'backend_manifest_sha256': runner.digest(sidecar)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu', type=int, default=4)
    args = parser.parse_args()
    manifest_path = args.manifest.resolve()
    manifest_hash = runner.digest(manifest_path)
    manifest = json.loads(manifest_path.read_text())
    holdouts.check_manifest(manifest_path, manifest_hash, manifest)
    identity = manifest['identity']
    assert identity['source_revision'] == REVISION
    assert identity['compiler_build_receipt']['receipt']['compiler_optimize'] == 'Debug'
    fixture = HERE / 'remainder_semantics.my'
    inputs = (Path(__file__), HERE / 'actual-llvm-semantics.py', fixture,
              ROOT / 'benchmarks/runtime/runner.py', ROOT / 'benchmarks/runtime/diagnostics/holdouts.py')
    bindings = {str(path): runner.digest(path) for path in inputs}
    work = args.work.resolve()
    work.mkdir()
    report = {'schema': 'mylang-goal110-bounded-rem-actual-llvm-width-v1', 'status': 'in_progress',
              'source_revision': REVISION, 'manifest': str(manifest_path), 'manifest_sha256': manifest_hash,
              'manifest_identity': identity, 'source_and_helper_sha256': bindings, 'cpu': args.cpu,
              'started_utc': stamp(), 'magnitude': MAGNITUDE, 'wide_divisor': WIDE_DIVISOR,
              'wide_bias': WIDE_BIAS, 'variants': {}, 'purpose': 'Actual LLVM-O3/fullLTO ELF correctness; no timing.'}
    outcomes = reader()
    for name, variant in variants(fixture.read_text()).items():
        source = work / (name + '.my')
        source.write_text(variant['source'])
        doc = {'source': str(source), 'source_sha256': runner.digest(source), 'builds': {}, 'outcomes': []}
        for policy in ('accounted', 'unaccounted'):
            print('Building actual LLVM ' + name + '/' + policy, flush=True)
            doc['builds'][policy] = build(identity, source, work / (name + '-' + policy), policy)
        for case in variant['cases']:
            results = {policy: outcomes.outcome(Path(item['binary']), case, args.cpu)
                       for policy, item in doc['builds'].items()}
            assert results['accounted']['run'] == results['unaccounted']['run'], (case, results)
            assert results['unaccounted']['run']['value'] == case['expected']
            doc['outcomes'].append({'input': case, **results})
            print('PASS actual LLVM ' + case['name'], flush=True)
        assert runner.digest(source) == doc['source_sha256']
        report['variants'][name] = doc
    assert bindings == {path: runner.digest(path) for path in bindings}
    holdouts.check_manifest(manifest_path, manifest_hash, manifest)
    for variant in report['variants'].values():
        for item in variant['builds'].values():
            assert runner.digest(item['binary']) == item['binary_sha256']
            assert runner.digest(item['backend_manifest']) == item['backend_manifest_sha256']
    report.update(status='complete', finished_utc=stamp())
    with args.output.open('x') as output:
        output.write(json.dumps(report, indent=2) + '\n')
    print('PASS12 actual LLVM executions/6 full accounted-unaccounted wide/exact-M pairs; no timing')


if __name__ == '__main__':
    main()
