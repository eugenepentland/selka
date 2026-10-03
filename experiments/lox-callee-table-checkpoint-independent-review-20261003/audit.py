#!/usr/bin/env python3
"""Inspect reconstructed checkpoint evidence without executing its helper."""
import argparse
import datetime
import hashlib
import itertools
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent.parent / 'lox-next-measurement-independent-review-20261003'))
import audit as checker


def patch_replay(patch, original):
    lines = patch.decode().splitlines(keepends=True)
    result = dict(original)
    files = []
    at = 0
    while at < len(lines):
        if not lines[at].startswith('--- a/'):
            at += 1
            continue
        name = lines[at].split('\t')[0].strip()[6:]
        assert lines[at + 1].split('\t')[0].strip() == '+++ b/' + name
        assert name not in files
        files.append(name)
        source = original[name].decode().splitlines(keepends=True)
        output = []
        cursor = 0
        at += 2
        while at < len(lines) and lines[at].startswith('@@ '):
            hunk = re.match(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', lines[at])
            assert hunk
            start = max(0, int(hunk[1]) - 1)
            old_count = int(hunk[2]) if hunk[2] else 1
            new_count = int(hunk[4]) if hunk[4] else 1
            assert cursor <= start
            output.extend(source[cursor:start])
            old, new = [], []
            at += 1
            while at < len(lines) and lines[at][:1] in [' ', '+', '-'] and not lines[at].startswith('--- a/'):
                prefix = lines[at][0]
                if prefix in [' ', '-']:
                    old.append(lines[at][1:])
                if prefix in [' ', '+']:
                    new.append(lines[at][1:])
                at += 1
            assert len(old) == old_count and len(new) == new_count
            assert source[start:start + old_count] == old
            output.extend(new)
            cursor = start + old_count
        output.extend(source[cursor:])
        result[name] = ''.join(output).encode()
    return result, files


def smoke(path, manifest):
    doc = checker.load(path)
    command = checker.load(path.with_suffix('.command.json'))
    assert doc['phase'] == 'check' and doc['tier'] == 'smoke' and doc['rounds'] == 1
    assert doc['verified_after'] and command['status'] == 0 and command['sources_verified_after']
    assert command['source_hashes_before'] == command['source_hashes_after']
    assert command['source_hashes_before'] == {k: v['hashes'] for k, v in manifest['candidate_sources'].items()}
    assert checker.sha(path.parent / 'binaries.json') == command['manifest_sha256']
    assert checker.sha(path.with_suffix('.log')) == command['log_sha256']
    assert doc['manifest'] == manifest and doc['binary_sha256'] == manifest['binary_sha256']
    arms = set(manifest['binaries'])
    assert arms == {'baseline-llvm', 'baseline-qbe', 'combined-llvm', 'combined-qbe', 'rust', 'go'}
    cases = {c['id'] for c in doc['cases']}
    assert len(cases) == len(doc['cases']) == 26
    expected = set(itertools.product(cases, arms, [0]))
    actual = [(s['case'], s['arm'], s['round']) for s in doc['samples']]
    assert len(actual) == 156 and set(actual) == expected
    hashes = {c['id']: checker.sha(c['expected']) for c in doc['cases']}
    ref = path.parent / 'reference/benchmarks/lox/bench'
    sizes = checker.load(ref / 'sizes.json')
    assert cases == {e + '/' + p.stem for e in ['vm', 'tree'] for p in (ref / 'scripts').glob('*.lox')}
    for case in doc['cases']:
        assert case['size'] == sizes[case['name']]['smoke']
        original = checker.read(ref / 'scripts' / (case['name'] + '.lox')).decode().split('\n', 1)[1]
        assert checker.read(case['script']) == f"var N = {case['size']};\n{original}".encode()
        assert checker.sha(case['script']) == case['script_sha256']
    stats = {}
    for sample in doc['samples']:
        assert sample['status'] == 0 and sample['stdout_sha256'] == hashes[sample['case']]
        pattern = r'\[stats\] engine=(vm|tree) allocations=(\d+) collections=(\d+) freed=(\d+) live=(\d+)\n'
        found = re.fullmatch(pattern, sample['stderr'])
        assert found and found[1] == sample['case'].split('/')[0]
        current = dict(zip(('allocations', 'collections', 'freed', 'live'), map(int, found.groups()[1:])))
        assert current == sample['collector_stats']
        assert sample['case'] not in stats or current == stats[sample['case']]
        stats[sample['case']] = current
    checker.same(checker.summary(doc['samples']), doc['summary'])
    return {'path': str(path), 'sha256': checker.sha(path), 'command_sha256': checker.sha(path.with_suffix('.command.json')),
            'log_sha256': command['log_sha256'], 'samples': 156,
            'unique_complete_coverage': True, 'output_status_diagnostics_statistics_verified': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    assert not args.out.exists()
    root = args.root.resolve()
    work = root / '.tmp-lox-next/fresh-rebuild-reviewed'
    helper = root / 'experiments/lox-callee-table-checkpoint-20261003/prepare.py'
    expected_path = helper.with_name('sources.json')
    expected = checker.load(expected_path)
    measured = checker.load(root / '.tmp-lox-next/binaries.json')
    for name in ['baseline', 'combined']:
        assert len(expected[name]) == 37
        assert expected[name] == measured['candidate_sources'][name]['all_files']
    migration = root / 'docs/audits/d9-stage3d-migrations'
    patch = migration / 'lox-runtime-perf-20261003-callee-table.patch'
    original = {name: checker.read(Path(measured['candidate_sources']['baseline']['path']) / name)
                for name in expected['baseline']}
    replayed, changed = patch_replay(checker.read(patch), original)
    assert {k: hashlib.sha256(v).hexdigest() for k, v in replayed.items()} == expected['combined']
    canonical_path = root / '.tmp-lox-next/canonical-replay.json'
    canonical = checker.load(canonical_path)
    assert canonical['canonical_replay_matches_measured_source'] and canonical['source_files'] == 37
    assert canonical['all_files'] == expected['combined'] and canonical['patch_sha256'] == checker.sha(patch)
    for name, digest in expected['combined'].items():
        assert checker.sha(Path(canonical['source']) / name) == digest
    manifest, manifest_report = checker.manifest(work / 'binaries.json')
    assert manifest['preparer'] == str(helper) and manifest['preparer_sha256'] == checker.sha(helper)
    assert manifest['reference_commit'] == '4e48a09220c2e018eba8c4b1eb3fe1137a3dae73'
    prefixes = ('benchmarks/lox/bench/', 'benchmarks/lox/ports/rust/', 'benchmarks/lox/ports/go/')
    archived_references = {k: v for k, v in measured['reference_source_hashes'].items() if k.startswith(prefixes)}
    assert len(archived_references) == 106
    assert manifest['reference_source_hashes'] == archived_references
    assert manifest['adjacent_qbe_sha256'] == manifest_report['qbe_sha256']
    commands_path = work / 'prepare-commands.json'
    commands = checker.load(commands_path)
    assert len(commands) == 7 and all(c['status'] == 0 for c in commands)
    assert checker.sha(commands_path) == manifest['prepare_commands_sha256']
    for command in commands:
        assert checker.sha(command['log']) == command['log_sha256']
        env = command['environment']
        assert env['RUSTC'] == manifest['reference_toolchains']['rustc']['path']
        assert Path(env['RUSTC']).is_absolute()
        assert env['TMPDIR'] == env['GOTMPDIR'] == str(work / 'tmp')
    assert '--release' in commands[5]['argv'] and '--locked' in commands[5]['argv']
    assert '-buildvcs=false' in commands[6]['argv']
    assert commands[5]['environment']['CARGO_TARGET_DIR'] == str(work / 'rust-target')
    assert commands[6]['environment']['GOCACHE'] == str(work / 'go-build')
    assert commands[6]['environment']['GOMODCACHE'] == str(work / 'go-mod')
    assert commands[6]['environment']['GOTOOLCHAIN'] == 'local'
    for name, data in manifest['reference_toolchains'].items():
        assert checker.sha(data['path']) == data['sha256']
        if name in ['cargo', 'rustc']:
            assert checker.sha(data['sysroot_executable']) == data['sysroot_executable_sha256']
    build_reports = [checker.builds(work / (name + '-build.json'),
                                   manifest['candidate_sources'][name], set(manifest['binary_sha256'].values()))
                     for name in ['baseline', 'combined']]
    same_guests = {}
    for name, digest in manifest['binary_sha256'].items():
        same_guests[name] = digest == measured['binary_sha256'][name]
        if name != 'go':
            assert same_guests[name]
    smoke_files = []
    for path in work.glob('*.json'):
        data = json.loads(path.read_bytes())
        if isinstance(data, dict) and 'samples' in data and data.get('verified_after'):
            smoke_files.append(path)
    assert len(smoke_files) == 1, 'final six-arm smoke must complete before acceptance'
    smoke_report = smoke(smoke_files[0], manifest)
    failed_work = root / '.tmp-lox-next/fresh-rebuild'
    failed_path = failed_work / 'prepare-commands.json'
    failed = checker.load(failed_path)
    assert len(failed) == 6 and [c['status'] for c in failed] == [0, 0, 0, 0, 0, 127]
    assert not (failed_work / 'binaries.json').exists()
    for command in failed:
        assert checker.sha(command['log']) == command['log_sha256']
    for path, digest in list(checker.READS.items()):
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
    result = {
        'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'outcome': 'final helper and observed reconstruction/qualification pass with stated provenance limits',
        'helper': {'path': str(helper), 'sha256': checker.sha(helper), 'preparer_identity_checked_before_after': True},
        'expected_sources': {'path': str(expected_path), 'sha256': checker.sha(expected_path), 'files_per_source': 37},
        'in_memory_patch_replay': {'sha256': checker.sha(patch), 'changed_files': changed, 'matches_source84_exactly': True},
        'canonical_replay': {'path': str(canonical_path), 'sha256': checker.sha(canonical_path), 'all37_verified': True},
        'final_manifest': manifest_report,
        'reference_archive_scope': 'All106 benchmark/Rust/Go files match measured references; the21 unused Zig files are intentionally excluded.',
        'reference_toolchains': manifest['reference_toolchains'],
        'prepare_commands': {'path': str(commands_path), 'sha256': checker.sha(commands_path), 'successful_commands': 7},
        'native_rc_builds': build_reports,
        'byte_identity_to_measured_guests': same_guests,
        'fresh_smoke': smoke_report,
        'original_failed_prepare': {'path': str(failed_path), 'sha256': checker.sha(failed_path),
                                    'successful_commands_before_failure': 5, 'cargo_process_status': 127,
                                    'complete_manifest_absent': True, 'never_accepted_as_full_pass': True},
        'resolved_provenance_concern': 'Final helper sets absolute RUSTC for Cargo and records the effective relevant environment; relative override/tool-record mismatch is fixed.',
        'reviewer_guest_executions': 0, 'reviewer_perf_executions': 0, 'root_mutations': 0,
        'stable_read_input_count': len(checker.READS),
        'stable_read_inputs_identity_sha256': hashlib.sha256(json.dumps(checker.READS, sort_keys=True).encode()).hexdigest(),
        'limits': [
            'No new timing or reference replacement: five fresh guests match measured bytes; fresh Go has a distinct identity and only fresh smoke behavior is certified.',
            'Cargo/rustc shim hashes and actual sysroot executable hashes are recorded separately with observed versions; complete toolchain/stdlib archives are not claimed.',
            'Some ambient toolchain flags remain inherited rather than exhaustively recorded; observed guest/source identities and command evidence define this qualification.',
            'Compiler/QBE/source/helper checks are before/after, while recorded reference toolchain versions/hashes are post-build observations.',
            'Fresh smoke producer checks raw stdout then stores hashes and decoded stderr; all retained stats lines are exact ASCII and all expected-output hashes match.',
            'Independent audit checks preserved evidence and in-memory patch application; it does not rerun builds, source tests, reference tools or benchmark guests.'
        ]}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'out': str(args.out), 'sha256': hashlib.sha256(args.out.read_bytes()).hexdigest(),
                      'smoke_samples': 156, 'five_guests_byte_identical': True}, indent=2))


if __name__ == '__main__':
    main()
