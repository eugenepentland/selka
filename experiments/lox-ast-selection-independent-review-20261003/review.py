#!/usr/bin/env python3
"""Inspect the pending AST-only migration and historical reproduction; no guest runs."""
import argparse
import datetime
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent.parent / 'lox-next-measurement-independent-review-20261003'))
import audit


def packed(path):
    data = audit.read(path)
    return json.loads(gzip.decompress(data) if str(path).endswith('.gz') else data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    assert not args.out.exists(), 'historical observations must remain unchanged'
    root = args.root.resolve()
    work = root / '.tmp-lox-round3'
    exp = root / 'experiments/lox-ast-constant-20261003'
    previous = Path(__file__).parent.parent / 'lox-round3-independent-review-20261003'
    assert audit.sha(previous / 'final-review.json') == 'bd8e734c304940db87fb769eedcc409affd806c194a190e1e77086cb62ed0722'
    prior = audit.load(previous / 'final-review.json')
    manifest = audit.load(work / 'binaries.json')
    assert audit.sha(work / 'binaries.json') == prior['manifest_sha256']
    maps = {name: source['all_files'] for name, source in manifest['candidate_sources'].items()}
    replay_path = work / 'canonical-replay-fixed.json'
    replay = audit.load(replay_path)
    assert replay['source37'] == maps['ast'] and replay['exact_selected_ast_source']
    port = work / 'canonical-replay-fixed/lox/benchmarks/lox/ports/mylang'
    replay_report = audit.sources({'path': str(port), 'all_files': maps['ast'],
                                  'hashes': {k: v for k, v in maps['ast'].items() if k.endswith('.my')}})
    assert audit.read(exp / 'canonical-replay.json') == audit.read(replay_path)
    migration = root / 'docs/audits/d9-stage3d-migrations'
    patch = migration / 'lox-runtime-perf-20261003-ast-carrier.patch'
    assert audit.sha(patch) == 'b1fc1359603b549f7a06ed00a958d0d5dcf6f91515b78e2d4bad8719942d6f9b'
    author = root.parent / 'codex-lox-parity-vm-20261003'
    assert audit.read(patch) == audit.read(author / 'experiments/lox-tree-ast-carrier-20261003/ast-carrier.patch')
    helper_path = Path(__file__).parent.parent / 'lox-callee-table-checkpoint-independent-review-20261003/audit.py'
    spec = importlib.util.spec_from_file_location('checkpoint', helper_path)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    baseline_bytes = {name: audit.read(work / 'baseline' / name) for name in maps['baseline']}
    ast_bytes, changed = helper.patch_replay(audit.read(patch), baseline_bytes)
    assert changed == ['interpreter.my']
    assert {name: hashlib.sha256(data).hexdigest() for name, data in ast_bytes.items()} == maps['ast']
    original_apply = subprocess.run(['git', 'show', '44cd43078c51fc33ba1b52b86ffa48ce4f35b28c:docs/audits/d9-stage3d-migrations/apply-lox.sh'],
                                    cwd=root, capture_output=True, check=True).stdout
    insertion = b'    (cd "$port" && patch --batch --fuzz=0 -p1 < "$script_dir/lox-runtime-perf-20261003-ast-carrier.patch")\n'
    assert original_apply.endswith(b'fi\n')
    assert audit.read(migration / 'apply-lox.sh') == original_apply[:-3] + insertion + b'fi\n'
    replay_logs = {name: audit.sha(work / name) for name in ['canonical-replay-fixed.log', 'canonical-replay.log']}
    assert 'No such file or directory' in audit.read(work / 'canonical-replay.log').decode()

    # The historical helper must continue to reproduce source80/source84, independent of new canonical overlays.
    legacy = root / 'experiments/lox-callee-table-checkpoint-20261003'
    historical = work / 'historical-fresh-rebuild'
    old, historical_report = audit.manifest(historical / 'binaries.json')
    expected_old = audit.load(legacy / 'sources.json')
    assert {n: d['all_files'] for n, d in old['candidate_sources'].items()} == expected_old
    assert expected_old['combined'] == maps['baseline']
    assert old['compiler_sha256'] == manifest['compiler_sha256'] and old['adjacent_qbe_sha256'] == manifest['qbe_sha256']
    archive = exp / 'baseline-source.tar.gz'
    assert audit.sha(archive) == old['historical_source84_archive_sha256'] == 'ecb25e84109b7f8ee451b44eb25275a9b7f82a37dd8f0a46fa7438d3c1391486'
    archive_files = {}
    with tarfile.open(fileobj=io.BytesIO(audit.read(archive))) as source_tar:
        for member in source_tar.getmembers():
            if member.isdir():
                continue
            assert member.isfile()
            name = member.name.removeprefix('./')
            assert name not in archive_files
            archive_files[name] = source_tar.extractfile(member).read()
    assert {n: hashlib.sha256(b).hexdigest() for n, b in archive_files.items()} == maps['baseline']
    old_baseline_bytes = {n: audit.read(historical / 'baseline' / n) for n in expected_old['baseline']}
    forward, _ = helper.patch_replay(audit.read(migration / 'lox-runtime-perf-20261003-callee-table.patch'), old_baseline_bytes)
    assert forward == archive_files
    assert audit.sha(legacy / 'prepare.py') == old['preparer_sha256']
    legacy_text = audit.read(legacy / 'prepare.py').decode()
    assert "run(['bash', migration / 'apply-lox.sh'" not in legacy_text
    assert "data.extractall(source, filter='data')" in legacy_text
    commands = audit.load(historical / 'prepare-commands.json')
    assert audit.sha(historical / 'prepare-commands.json') == old['prepare_commands_sha256']
    assert len(commands) == 6 and all(command['status'] == 0 for command in commands)
    assert commands[0]['argv'][:5] == ['patch', '--batch', '--fuzz=0', '-R', '-p1']
    assert '--locked' in commands[-2]['argv'] and '-buildvcs=false' in commands[-1]['argv']
    for command in commands:
        assert audit.sha(command['log']) == command['log_sha256']
        assert command['environment']['TMPDIR'] == command['environment']['GOTMPDIR'] == str(historical / 'tmp')
        assert command['environment']['RUSTC'] == old['reference_toolchains']['rustc']['path']
    for tool in old['reference_toolchains'].values():
        assert audit.sha(tool['path']) == tool['sha256']
        if 'sysroot_executable' in tool:
            assert audit.sha(tool['sysroot_executable']) == tool['sysroot_executable_sha256']
    builds = [audit.builds(historical / (name + '-build.json'), source, set(old['binary_sha256'].values()))
              for name, source in old['candidate_sources'].items()]
    measured = audit.load(root / '.tmp-lox-next/binaries.json')
    matches = {name: digest == measured['binary_sha256'][name] for name, digest in old['binary_sha256'].items()}
    assert all(matches[n] for n in matches if n != 'go') and not matches['go']
    comparison = audit.load(work / 'historical-fresh-comparison.json')
    assert comparison == {'guest_byte_matches': matches, 'all37_sources_exact': True, 'go_is_separate_behavior_identity': True}
    helper.smoke(historical / 'smoke.json', old)
    copies = {'ast-selection-rebuild-comparison.json': work / 'historical-fresh-comparison.json',
              'ast-selection-rebuild-manifest.json': historical / 'binaries.json',
              'ast-selection-rebuild-commands.json': historical / 'prepare-commands.json'}
    for name, original in copies.items():
        assert audit.read(legacy / name) == audit.read(original)
    assert gzip.decompress(audit.read(legacy / 'ast-selection-rebuild-smoke.json.gz')) == audit.read(historical / 'smoke.json')

    # Fresh selected d14 accounted directory tests are distinct from prior native probes and historical4cbae tests.
    public = root / 'experiments/lox-ast-selected-public-20261003'
    qualification = audit.load(public / 'qualification.json')
    full = packed(public / 'qualification.json.gz')
    checks = audit.load(public / 'checks.json')
    assert audit.sha(public / 'qualification.json') == checks['qualification_sha256']
    assert checks['fresh_public_test_runner_status'] == checks['receipt_recheck_status'] == 0
    assert full['verified_after'] and qualification['verified_after']
    for name, identity in qualification['full_receipts'].items():
        compressed = audit.read(public / (name + '.gz'))
        raw = gzip.decompress(compressed)
        assert hashlib.sha256(compressed).hexdigest() == identity['gzip_sha256'] and len(compressed) == identity['gzip_bytes']
        assert hashlib.sha256(raw).hexdigest() == identity['raw_sha256'] and len(raw) == identity['raw_bytes']
    assert qualification['compiler_sha256'] == manifest['compiler_sha256'] and qualification['qbe_sha256'] == manifest['qbe_sha256']
    assert full['before']['source37'] == full['after']['source37'] == qualification['source37'] == maps['ast']
    assert full['before']['baseline37'] == full['after']['baseline37'] == qualification['baseline37'] == maps['baseline']
    assert full['before']['artifacts_sha256'] == full['after']['artifacts_sha256']
    assert not ({2, 3, 10, 11} & set(full['before']['affinity']))
    for path, digest in full['after']['artifacts_sha256'].items():
        assert audit.sha(path) == digest
    declared_names = sorted(stem + '::' + name for path, data in ast_bytes.items() if path.endswith('.my')
                            for stem in [Path(path).stem] for name in re.findall(r'^public def (test_\w+)\(', data.decode(), re.M))
    assert len(declared_names) == 84 and declared_names == qualification['public_names']
    public_runs = []
    for compact, run in zip(qualification['runs'], full['runs'], strict=True):
        assert compact['key'] == run['key'] and compact['argv'] == run['argv'] and run['status'] == 0
        assert run['fresh_cache'] and run['provider_identity'] == '' and '--cases' not in run['argv']
        assert '--max-steps' in run['argv'] and audit.option(run['argv'], '--max-steps') == '1000000000'
        assert audit.option(run['argv'], '--timeout-ms') == '120000'
        assert not any(arg.startswith('--drop-') for arg in run['argv'])
        assert ('--release' in run['argv']) if run['key'].startswith('llvm') else audit.option(run['argv'], '--mode') == 'ReleaseFast'
        assert ('--rc-runtime' in run['argv']) if run['key'].endswith('-rc') else '--gc-stress' in run['argv']
        packed_path = public / (run['key'] + '.json.gz')
        assert hashlib.sha256(gzip.decompress(audit.read(packed_path))).hexdigest() == run['stdout_sha256']
        assert audit.sha(run['stdout']) == run['stdout_sha256'] and audit.sha(run['stderr']) == run['stderr_sha256']
        tests = packed(packed_path)
        counts = {key: tests[key] for key in ['passed', 'failed', 'skipped', 'cached', 'executed', 'dropped', 'unloaded', 'programs']}
        assert counts == compact['counts'] == run['counts'] == {'passed': 84, 'failed': 0, 'skipped': 0, 'cached': 0, 'executed': 84, 'dropped': 0, 'unloaded': 0, 'programs': 10}
        assert sorted(test['name'] for test in tests['tests']) == declared_names
        assert all(test['status'] == 'passed' and test['actual'] is True and test['provider'] == '' for test in tests['tests'])
        for path, digest in run['native_test_artifacts_sha256'].items():
            assert audit.sha(path) == digest
        public_runs.append({'key': run['key'], 'argv': run['argv'], 'fresh_passes': 84,
                            'provider_identity': '', 'artifact_hashes_checked': len(run['native_test_artifacts_sha256'])})
    assert len(public_runs) == 4 and full['fresh_public_passes'] == qualification['fresh_selected_d14_ast84_public_passes'] == 336
    native_review = Path(__file__).parent.parent / 'lox-ast-carrier-independent-review-20261003/review.json'
    assert audit.sha(native_review) == 'abff435a0ecf2c7e6147c5658f239e35847519d98a724f60f7cc9157f6df4172'
    native = audit.load(native_review)
    for relative, digest in native['author_experiment_file_hashes'].items():
        assert audit.sha(author / relative) == digest
    assert native['bounded_exact_comparisons'] + native['new_focused_exact_comparisons'] == 1264
    assert native['rc_native_stress_refusal_pairs'] == 8 and native['native_smoke_cells_explicitly_unrun'] == 80

    checkpoint = audit.load(exp / 'checkpoint.json')
    assert checkpoint['control_source_commit'] == manifest['checkpoint_commit']
    assert checkpoint['canonical_source_role'] == 'ast' and checkpoint['canonical_public_tests'] == 84
    assert checkpoint['selected_source_patch_sha256'] == audit.sha(patch)
    assert checkpoint['canonical_replay_sha256'] == audit.sha(replay_path)
    assert checkpoint['complete_measurement_rows'] == {'source_smoke': 208, 'instruction_screen_one_round': 208,
                                                       'fresh_reproduction_smoke': 260, 'full_wall': 780, 'full_counters': 780}
    assert checkpoint['selected_fresh_public_passes'] == 336 and checkpoint['selected_native_program_pairs'] == 1264
    assert checkpoint['selected_rc_refusal_pairs'] == 8 and checkpoint['selected_native_stress_smoke_omissions'] == 80
    for field in ['historical_partial_review', 'independent_completed_review', 'composed_source_qualification']:
        record = checkpoint[field]
        assert audit.sha(exp / record['record']) == record['sha256']
    for name, digest in checkpoint['payload_sha256'].items():
        assert audit.sha(exp / name) == digest
    for name, gate in [('selection', checkpoint['guardian_selection']), ('public', checks['guardian'])]:
        assert gate['status'] == 0 and gate.get('passed', gate.get('passed_checks')) == 88
        if name == 'selection':
            assert audit.sha(exp / 'guardian-ast-selection.log') == gate['log_sha256']
        else:
            assert audit.sha(public / 'guardian.log') == gate['log_sha256']
    docs = {str(path.relative_to(root)): audit.sha(path) for path in [
        root / 'docs/audits/lox-ast-carrier-checkpoint-2026-10-03.md', exp / 'README.md', exp / 'checkpoint.json',
        legacy / 'README.md', root / 'docs/audits/lox-callee-table-checkpoint-2026-10-03.md']}
    assert 'Fresh accounted' in audit.read(root / 'docs/audits/lox-ast-carrier-checkpoint-2026-10-03.md').decode()
    selected_commit = '37df3ffbfab1f2ea4f269c769eb5b013c5270be3'
    committed_files = [migration / 'apply-lox.sh', patch, legacy / 'prepare.py', *[root / name for name in docs]]
    for path in committed_files:
        committed = subprocess.run(['git', 'show', selected_commit + ':' + str(path.relative_to(root))],
                                   cwd=root, capture_output=True, check=True).stdout
        assert committed == audit.read(path)
    for path, digest in list(audit.READS.items()):
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, ('changed during review', path)
    result = {'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'outcome': 'pass with inherited semantic/measurement limits; no actionable migration or reproduction defect',
              'selected_canonical_commit': selected_commit,
              'migration_script_sha256': audit.sha(migration / 'apply-lox.sh'), 'selected_patch_sha256': audit.sha(patch),
              'canonical_replay': replay_report, 'canonical_replay_receipt_sha256': audit.sha(replay_path),
              'relative_path_replay_failure_preserved_not_counted': replay_logs,
              'historical_source80_source84': historical_report, 'historical_preparer_sha256': old['preparer_sha256'],
              'historical_six_successful_outer_commands': True, 'historical_builds': builds,
              'historical_byte_matches': matches, 'historical_smoke_unique_rows': 156,
              'historical_smoke_exact_output_and_collector_statistics': True, 'fresh_go_is_behavior_only': True,
              'fresh_selected_accounted_public_tests': public_runs, 'fresh_selected_public_passes': 336,
              'prior_unaccounted_native_program_pairs': 1264, 'prior_native_refusal_pairs': 8, 'native_stress_smoke_unrun': 80,
              'prior_source_review_sha256': audit.sha(native_review), 'prior_completed_measurement_review_sha256': audit.sha(previous / 'final-review.json'),
              'frozen_checkpoint_doc_sha256': docs, 'checkpoint_payloads_verified': len(checkpoint['payload_sha256']),
              'root_selection_guardian_passes': 88, 'stable_read_input_count': len(audit.READS),
              'stable_read_identity_sha256': hashlib.sha256(json.dumps(audit.READS, sort_keys=True).encode()).hexdigest(),
              'guest_public_native_test_or_perf_executions': 0, 'source_root_main_archive_or_feedback_mutations': 0,
              'limits': ['Prior complete1976 measurement rows and fresh260 behavior rows remain inherited, not new observations here.',
                         'Fresh historical156 smoke/stat rows qualify reproduction behavior, not new timings or reference replacement.',
                         'Fresh d14 public336 retain instruction accounting and provider-free directory scope; they are distinct from inherited unaccounted native1264 plus8 refusals.',
                         'Historical4cbae public336 and historical failed fixture prefixes are preserved and not added to selected fresh pass counts.',
                         'LLVM release/QBE ReleaseFast test modes are exact argv observations; O3/full LTO belongs to release guest builds, not an inferred test mode.',
                         'Native helper PCs, frames, tight step cutoffs, raw performance stdout/CSV retention and toolchain hermeticity retain previous stated limits.',
                         'AST selection is supported by complete modest tree gains; unused-engine wall movement is not attributed to a VM optimization, and Rust/Go parity remains unmet.']}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'out': str(args.out), 'sha256': hashlib.sha256(args.out.read_bytes()).hexdigest(),
                      'stable_inputs': len(audit.READS), 'historical_behavior_rows': 156, 'fresh_selected_public_passes': 336}))


if __name__ == '__main__':
    main()
