#!/usr/bin/env python3
"""Bind normal RF milestone evidence without calculating acceptance intervals."""
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
CACHE = ROOT / '.mylang-cache/goal110-g4-rf'
SOURCE = '6cf7bdce11bc205862bf75b9d9ce72e46caad0a2'
PRIOR = ROOT.parent / 'goal110-join-short-20261004/experiments/runtime-goal110-join-short-20261004'
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    manifest_path = CACHE / 'runner/manifest.json'
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    holdouts.check_manifest(manifest_path, digest(manifest_bytes), manifest)
    sessions = [json.loads((CACHE / f'confirmation-{label}.json').read_text()) for label in ('a', 'b')]
    assert sessions[0]['measurement_session_id'] != sessions[1]['measurement_session_id']
    for report in sessions:
        assert report['status'] == 'subset'
        assert len(report['samples']) == 1080 and len(report['qualification']) == 720
        assert report['rounds'] == 15 and report['warmup_rounds'] == 3
        assert report['identity'] == report['identity_after']
        assert report['binary_hashes'] == report['binary_hashes_after'] == manifest['binary_hashes']
        assert report['identity']['compiler_build_receipt']['receipt']['source_revision'] == SOURCE
        assert report['identity']['compiler_build_receipt']['receipt']['compiler_optimize'] == 'ReleaseFast'
    assert holdouts.verify(json.loads((CACHE / 'holdouts.json').read_text())) == 516
    text = json.loads((CACHE / 'text-checks.json').read_text())
    assert text['status'] == 'passed' and len(text['checks']) == 200
    semantic = json.loads((CACHE / 'integrated-semantics.json').read_text())
    assert semantic['focused_tests'] == {'passed': 42, 'failed': 0, 'skipped': 0}
    assert semantic['focused_command_exit_status'] == 0
    assert len(semantic['append_outcomes']) == 11
    assert all(row['ordinary'] == row['fast'] for row in semantic['append_outcomes'])
    reuse = json.loads((CACHE / 'native-reuse.json').read_text())
    for name, expected in reuse['source_files_sha256'].items():
        current = (ROOT / name).read_bytes()
        previous = subprocess.check_output(['git', '-C', str(ROOT), 'show', reuse['prior_native_source_revision'] + ':' + name])
        assert current == previous and digest(current) == expected, name
    for key in ('prior_native_receipt', 'prior_native_log'):
        assert digest(Path(reuse[key]).read_bytes()) == reuse[key + '_sha256']
    compiler = reuse['C_compiler_identity_verified']
    assert digest(Path(compiler['path']).read_bytes()) == compiler['sha256']
    gate = (CACHE / 'guardian-archive.log').read_text()
    assert 'whole-tree run' in gate and '88 check(s) passed' in gate

    entries = [(CACHE / name, name) for name in (
        'compiler-receipt.json', 'compiler-build.log', 'compiler-driver.log', 'guest-driver.log',
        'confirmation-a.json', 'confirmation-a.log', 'confirmation-b.json', 'confirmation-b.log',
        'focused-units.log', 'focused-units-invalid-cache-flag.log', 'integrated-semantics.json',
        'text-checks.json', 'holdouts.json', 'holdouts.log', 'native-reuse.json',
        'qualification-live-validation.json', 'pre-timing-validation.json', 'post-timing-validation.json',
        'artifact-inspection.json', 'my-llvm-join-short.asm', 'my-qbe-join-short.asm', 'guardian-archive.log')]
    entries += [(CACHE / 'runner/manifest.json', 'guest-manifest.json'),
                (CACHE / 'runner/build-log.json', 'guest-build-log.json'),
                (CACHE / 'runner/progress.json', 'guest-build-progress.json'),
                (PRIOR / 'native-checks-receipt.json', 'reused-native-checks-receipt.json'),
                (PRIOR / 'native-checks.log', 'reused-native-checks.log')]
    commands = json.loads((HERE / 'commands.json').read_text())
    guest_command = commands['guest_build']
    frozen = Path(guest_command[guest_command.index('--reuse-reference-manifest') + 1])
    assert digest(frozen.read_bytes()) == '94ea9f6343133da2fefdcb327458fbb5fcf6d7f099ba29385ebb5b0bd430d721'
    entries.append((frozen, 'frozen-reference-manifest.json'))
    for arm, path in manifest['identity']['binary_paths'].items():
        if arm.split('/')[1].startswith('my-'):
            entries.append((Path(path + '.qbe-manifest.json'), arm.replace('/', '-') + '-backend-manifest.json'))
    for relative in ('src/native_text.c', 'tests/native_text_methods_test.c', 'src/native_format.zig',
                     'src/number_text_test.zig', 'benchmarks/runtime/build_compiler.py',
                     'benchmarks/runtime/runner.py', 'benchmarks/runtime/expanded/run.py',
                     'benchmarks/runtime/expanded/registry.py', 'benchmarks/runtime/expanded/text/oracle.py',
                     'benchmarks/runtime/diagnostics/holdouts.py', 'scripts/test_native_memory.py'):
        entries.append((ROOT / relative, relative.replace('/', '-')))
    bindings = []
    for path, name in entries:
        raw = path.read_bytes()
        archived = gzip.compress(raw, mtime=0)
        target = HERE / (name + '.gz')
        target.write_bytes(archived)
        bindings.append({'raw': str(path), 'raw_sha256': digest(raw), 'archive': target.name,
                         'archive_sha256': digest(archived), 'bytes': len(raw)})
    evidence = {'status': 'normal_RF_timing_and_correctness_complete_acceptance_owned_by_coordinator',
                'source_revision': SOURCE,
                'candidate_id': 'goal110-integrated-6cf7bdce-releasefast',
                'compiler_optimize': 'ReleaseFast',
                'compiler_sha256': manifest['identity']['compiler_build_receipt']['receipt']['compiler_sha256'],
                'manifest_sha256': digest(manifest_bytes),
                'frozen_reference_manifest_sha256': digest(frozen.read_bytes()),
                'guest_count': 24,
                'sessions': [{'id': report['measurement_session_id'], 'started_utc': report['started_utc'],
                              'finished_utc': report['finished_utc'], 'samples': len(report['samples']),
                              'qualification_records': len(report['qualification'])} for report in sessions],
                'fresh_RF_text_records': 200, 'fresh_holdout_records': 516,
                'focused_final_source_Debug_tests': 42,
                'reused_optimized_native_source_matched_files': len(reuse['source_files_sha256']),
                'archive_bindings': bindings,
                'script_bindings': {name: digest((HERE / name).read_bytes()) for name in
                                    ('archive.py', 'guest-checks.py', 'commands.json')},
                'limits': ['Coordinator owns correctness receipt, acceptance intervals and dashboard; no extra bootstrap performed.',
                           'The two sessions independently calibrate iterations under the unchanged normal policy and use the same RF artifacts.',
                           'Text checks validate checksums, clock-field shape, success status/empty stderr and accounting/budget error markers; complete process streams are not retained.',
                           'Prior448 portable C sanitizer suites are source-matched reuse, not fresh final-pin RF executions.',
                           'Focused42 tests use the final source Debug test root; fresh200 RF text checks and516 holdouts use actual official RF guests.',
                           'No full repository test gate claimed; compiler build Guardian is diff-scoped, archive/commit gate is whole-tree.',
                           'Small equality and small sorting remain open; no complete eighty-row goal claim.']}
    (HERE / 'evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    for binding in bindings:
        data = (HERE / binding['archive']).read_bytes()
        assert digest(data) == binding['archive_sha256']
        assert digest(gzip.decompress(data)) == binding['raw_sha256']
    print(f'PASS G4 archive: {len(bindings)} raw/gzip bindings, three scripts, no acceptance bootstrap')


if __name__ == '__main__':
    main()
