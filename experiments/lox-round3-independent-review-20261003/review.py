#!/usr/bin/env python3
"""Independently inspect round3 source identities and completed factorial results."""
import argparse
import datetime
import hashlib
import importlib.util
import inspect
import json
import io
from pathlib import Path
import sys
import tarfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent.parent / 'lox-next-measurement-independent-review-20261003'))
import audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    assert not args.out.exists(), 'choose a fresh receipt; historical reviews remain unchanged'
    root = args.root.resolve()
    work = root / '.tmp-lox-round3'
    manifest_path = work / 'binaries.json'
    expected_manifest = 'd1b04d2b3084aad01b32898fced996a072f9181f746afef839ac7012ef596d3b'
    assert audit.sha(manifest_path) == expected_manifest
    manifest = audit.load(manifest_path)
    assert manifest['checkpoint_commit'] == '44cd43078c51fc33ba1b52b86ffa48ce4f35b28c'
    assert manifest['checkpoint_archive_manifest'] == '94d85a11474d68c281d6b0e9010046ed5ebc8dd7ded019d43761b5d7c63b7272'
    archive = root.parents[1] / 'evidence/lox-parity-20261003/callee-table/MANIFEST.sha256'
    assert audit.sha(archive) == manifest['checkpoint_archive_manifest']
    assert audit.sha(manifest['compiler']) == manifest['compiler_sha256'] == 'd14a704083bcc5f5174932a751f7d9dda73100dbd62403626b42b52436cad040'
    assert audit.sha(manifest['qbe']) == manifest['qbe_sha256'] == '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'
    prepared = audit.load(manifest['prepared_receipt']['path'])
    composition = audit.load(manifest['composition_receipt']['path'])
    for key in ['prepared_receipt', 'composition_receipt']:
        assert audit.sha(manifest[key]['path']) == manifest[key]['sha256']
    assert prepared['parent_commit'] == '95b2426043620822e55470737cd244e060c4914b'
    source_reports = {name: audit.sources(source) for name, source in manifest['candidate_sources'].items()}
    maps = {name: source['all_files'] for name, source in manifest['candidate_sources'].items()}
    assert prepared['source_maps'] == {name: maps[name] for name in ['baseline', 'ast', 'constant']}
    accepted = audit.load(root / '.tmp-lox-next/binaries.json')
    assert maps['baseline'] == accepted['candidate_sources']['combined']['all_files']
    assert maps['baseline'] == audit.load(root / '.tmp-lox-next/canonical-replay.json')['all_files']
    ast_lane = root.parent / 'codex-lox-parity-vm-20261003'
    constant_lane = root.parent / 'codex-lox-vm-dispatch-20261003'
    ast_source = audit.load(ast_lane / 'experiments/lox-tree-ast-carrier-20261003/source.json')
    const_source = audit.load(constant_lane / 'experiments/lox-vm-constant-20261003/qualification.json')
    const_build = audit.load(constant_lane / 'experiments/lox-vm-constant-20261003/build.json')
    assert maps['ast'] == ast_source['candidate_hashes'] and maps['baseline'] == ast_source['baseline_hashes']
    assert maps['constant'] == const_source['source_sha256']
    for label in ['baseline', 'ast', 'constant']:
        data = prepared['inputs'][label]
        assert data['all_files'] == maps[label]
        for name, digest in maps[label].items():
            assert audit.sha(Path(data['source']) / name) == digest
    assert composition['input_hashes'] == {key: maps[label] for key, label in [('base', 'baseline'), ('tree', 'ast'), ('vm', 'constant')]}
    assert composition['output_hashes'] == maps['combined']
    expected_combined = dict(maps['baseline'])
    for label in ['ast', 'constant']:
        for name, digest in maps[label].items():
            if digest != maps['baseline'][name]:
                assert name not in expected_combined or expected_combined[name] in [maps['baseline'][name], digest]
                expected_combined[name] = digest
    assert expected_combined == maps['combined']
    changed = [n for n in maps['baseline'] if maps['combined'][n] != maps['baseline'][n]]
    assert changed == ['driver_cases.json', 'driver_tests.my', 'interpreter.my', 'vm.my']
    replay_helper = Path(__file__).parent.parent / 'lox-callee-table-checkpoint-independent-review-20261003/audit.py'
    spec = importlib.util.spec_from_file_location('checkpoint_replay', replay_helper)
    replay = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(replay)
    source_bytes = {n: audit.read(work / 'baseline' / n) for n in maps['baseline']}
    reconstructed, _ = replay.patch_replay(audit.read(work / 'combined.patch'), source_bytes)
    assert {n: hashlib.sha256(v).hexdigest() for n, v in reconstructed.items()} == maps['combined']
    assert audit.sha(work / 'combined.patch') == composition['patch_sha256']
    helpers = {}
    for name, digest in prepared['helper_sha256'].items():
        assert audit.sha(root / name) == digest
        helpers[name] = digest
    for name in ['experiments/lox-ast-constant-20261003/analyze.py', 'experiments/lox-perf-improvements-20261002/analyze.py']:
        helpers[name] = audit.sha(root / name)
    for name, digest in prepared['reference_files'].items():
        assert audit.sha(work / 'reference' / name) == digest
    prior_references = accepted['reference_source_hashes']
    expected_bench = {name: digest for name, digest in prior_references.items() if name.startswith('benchmarks/lox/bench/')}
    assert prepared['reference_files'] == expected_bench and len(expected_bench) == 53
    assert len(prior_references) == 127
    for name, digest in prior_references.items():
        assert audit.sha(root / '.tmp-lox-next/reference' / name) == digest
    assert manifest['reference_commit'] == accepted['reference_commit'] == '4e48a09220c2e018eba8c4b1eb3fe1137a3dae73'
    assert len(manifest['binaries']) == 10 and len(manifest['sidecars']) == 16
    for name, binary in manifest['binaries'].items():
        assert audit.sha(binary) == manifest['binary_sha256'][name]
    for path, data in manifest['sidecars'].items():
        assert audit.sha(path) == data['sha256']
    for name, inherited in manifest['inherited_binaries'].items():
        assert audit.sha(inherited['original']) == inherited['sha256'] == manifest['binary_sha256'][name]
        assert audit.read(manifest['binaries'][name]) == audit.read(inherited['original'])
        assert inherited['sha256'] == accepted['binary_sha256'][inherited['source_arm']]
        if name.startswith('baseline-'):
            for suffix in ['.qbe-manifest.json', '.qbe-receipt']:
                assert audit.read(manifest['binaries'][name] + suffix) == audit.read(inherited['original'] + suffix)
    build_reports = []
    measured = set(manifest['binary_sha256'].values())
    original_source = accepted['candidate_sources']['combined']
    build_reports.append(audit.builds(Path(original_source['build_receipt']), original_source, measured))
    for label, data in manifest['build_receipts'].items():
        assert audit.sha(data['path']) == data['sha256']
        build_reports.append(audit.builds(Path(data['path']), manifest['candidate_sources'][label], measured))
    ast_builds = audit.load(ast_lane / 'experiments/lox-tree-ast-carrier-20261003/selectedd14-builds.json')
    for backend in ['llvm', 'qbe']:
        assert manifest['binary_sha256']['ast-' + backend] == ast_builds[backend + '-rc']['binary_sha256']
        runs = [r for r in const_build['runs'] if r['argv'][3] == 'build' and '--rc-runtime' in r['argv'] and r['argv'][r['argv'].index('--backend') + 1] == backend]
        assert len(runs) == 1
        assert audit.sha(runs[0]['argv'][runs[0]['argv'].index('-o') + 1]) == manifest['binary_sha256']['constant-' + backend]
    # The producer CLI defaults to both engines when no explicit option is present.
    producer = audit.read(root / 'experiments/lox-performance-audit-20261002/audit.py').decode()
    assert "parser.add_argument('--engines', default='vm,tree')" in producer
    original_option = audit.option
    audit.option = lambda argv, key: 'vm,tree' if key == '--engines' and key not in argv else original_option(argv, key)
    fresh_report = None
    fresh_work = work / 'fresh-rebuild'
    if (fresh_work / 'binaries.json').exists():
        fresh, fresh_identity = audit.manifest(fresh_work / 'binaries.json')
        assert audit.sha(fresh_work / 'binaries.json') == '00ec53962dc576e3567a0f83f4df6711c3e428d22d16c82ca4d64a24501d36aa'
        assert fresh['baseline_source_commit'] == manifest['checkpoint_commit']
        assert fresh['compiler_sha256'] == manifest['compiler_sha256']
        assert fresh['adjacent_qbe_sha256'] == manifest['qbe_sha256']
        helper = root / 'experiments/lox-ast-constant-20261003/prepare.py'
        assert audit.sha(helper) == fresh['preparer_sha256']
        helpers[str(helper.relative_to(root))] = fresh['preparer_sha256']
        expected_sources = audit.load(helper.with_name('sources.json'))
        assert expected_sources == maps == {name: d['all_files'] for name, d in fresh['candidate_sources'].items()}
        archive_path = helper.with_name('baseline-source.tar.gz')
        assert audit.sha(archive_path) == 'ecb25e84109b7f8ee451b44eb25275a9b7f82a37dd8f0a46fa7438d3c1391486'
        archive_sources = {}
        with tarfile.open(fileobj=io.BytesIO(audit.read(archive_path))) as source_tar:
            for member in source_tar.getmembers():
                if member.isdir():
                    continue
                assert member.isfile() and member.name not in archive_sources
                name = member.name.removeprefix('./')
                archive_sources[name] = hashlib.sha256(source_tar.extractfile(member).read()).hexdigest()
        assert archive_sources == maps['baseline']
        for path, digest in fresh['helper_sha256'].items():
            assert audit.sha(path) == digest
        prefixes = ('benchmarks/lox/bench/', 'benchmarks/lox/ports/rust/', 'benchmarks/lox/ports/go/')
        expected_refs = {k: v for k, v in prior_references.items() if k.startswith(prefixes)}
        assert fresh['reference_source_hashes'] == expected_refs and len(expected_refs) == 106
        commands_path = fresh_work / 'prepare-commands.json'
        assert audit.sha(commands_path) == fresh['prepare_commands_sha256']
        commands = audit.load(commands_path)
        assert len(commands) == 10 and all(c['status'] == 0 for c in commands)
        for command in commands:
            assert audit.sha(command['log']) == command['log_sha256']
            assert command['environment']['RUSTC'] == fresh['reference_toolchains']['rustc']['path']
            assert command['environment']['TMPDIR'] == command['environment']['GOTMPDIR'] == str(fresh_work / 'tmp')
        assert '-buildvcs=false' in commands[-1]['argv'] and '--release' in commands[-2]['argv'] and '--locked' in commands[-2]['argv']
        for name, tool in fresh['reference_toolchains'].items():
            assert audit.sha(tool['path']) == tool['sha256']
            if name in ['cargo', 'rustc']:
                assert audit.sha(tool['sysroot_executable']) == tool['sysroot_executable_sha256']
        fresh_builds = [audit.builds(fresh_work / (name + '-build.json'), d, set(fresh['binary_sha256'].values()))
                        for name, d in fresh['candidate_sources'].items()]
        byte_identity = {name: digest == manifest['binary_sha256'][name] for name, digest in fresh['binary_sha256'].items()}
        assert all(match for name, match in byte_identity.items() if name != 'go') and not byte_identity['go']
        smoke = fresh_work / 'smoke.json'
        observed_smoke = json.loads(smoke.read_bytes())
        if observed_smoke.get('verified_after'):
            # This receipt is directly in its workspace, rather than measurements/.
            # Keep every earlier independently authored check, changing only that base.
            checker_source = inspect.getsource(audit.measurement)
            assert checker_source.count('path.parent.parent') == 2
            namespace = dict(vars(audit))
            exec(checker_source.replace('path.parent.parent', 'path.parent'), namespace)
            fresh_doc, fresh_smoke = namespace['measurement'](smoke, fresh)
            assert len(fresh_doc['samples']) == 260 and fresh_doc['phase'] == 'check'
            assert fresh_doc['rounds'] == 1 and fresh_doc['cpu'] == 0 and fresh_doc['tier'] == 'smoke'
            fresh_report = {'manifest': fresh_identity, 'helper_sha256': fresh['preparer_sha256'],
                            'source_archive_sha256': audit.sha(archive_path), 'archive37_matches_accepted84': True,
                            'successful_commands': 10, 'reference_files': 106,
                            'reference_toolchains': fresh['reference_toolchains'], 'native_builds': fresh_builds,
                            'guest_byte_identity_to_measurements': byte_identity, 'behavior_only_smoke': fresh_smoke}
        else:
            fresh_report = {'scope': 'fresh smoke partial; excluded from completed coverage',
                            'observed_samples': len(observed_smoke['samples']), 'target_samples': 260}
    completed, docs, pending = [], {}, []
    for path in sorted((work / 'measurements').glob('*.json')):
        current = json.loads(path.read_bytes())
        if not isinstance(current, dict) or 'samples' not in current or 'phase' not in current:
            continue
        if current.get('verified_after'):
            doc, report = audit.measurement(path, manifest)
            expected_arms = {name + '-' + backend for name in ['baseline', 'ast', 'constant', 'combined'] for backend in ['llvm', 'qbe']}
            if path.stem not in ['source-smoke', 'source-screen-instructions']:
                expected_arms |= {'rust', 'go'}
                assert doc['rounds'] == 3 and doc['tier'] == 'timed' and len(doc['samples']) == 780
            else:
                assert doc['rounds'] == 1 and len(doc['samples']) == 208
            assert set(doc['binary_sha256']) == expected_arms
            completed.append(report)
            docs[path.stem] = doc
        else:
            pending.append({'path': str(path), 'observed_samples': len(current['samples']),
                            'target_samples': len(current['cases']) * len(current['binary_sha256']) * current['rounds'],
                            'scope': 'partial snapshot, excluded from completed coverage'})
    assert 'source-smoke' in docs and len(docs['source-smoke']['samples']) == 208
    analyses = []
    for path in sorted((work / 'measurements').glob('*analysis.json')):
        observed = json.loads(path.read_bytes())
        if 'comparisons' not in observed:
            continue
        input_path = Path(observed['receipt'])
        assert input_path.stem in docs
        assert observed['coverage_verified'] and observed['receipt_sha256'] == audit.sha(input_path)
        assert observed['screen_only'] == (len(docs[input_path.stem]['binary_sha256']) == 8)
        controls = lambda backend: ['baseline-' + backend] + ([] if observed['screen_only'] else ['rust', 'go'])
        expected_comparisons = {name + '-' + backend + '-over-' + control
                                for name in ['ast', 'constant', 'combined'] for backend in ['llvm', 'qbe']
                                for control in controls(backend)}
        assert set(observed['comparisons']) == expected_comparisons
        assert observed['metric'] == ('instructions' if docs[input_path.stem]['phase'] == 'counters' else 'wall_s')
        analyses.append(audit.analysis(path, docs[input_path.stem]))
    metadata_path = Path(__file__).with_name('go-metadata.json')
    go_metadata = audit.load(metadata_path)
    assert go_metadata['status'] == 0 and go_metadata['matching_reported_build_metadata'] and go_metadata['vcs_entries_absent']
    assert audit.sha(go_metadata['argv'][0]) == go_metadata['tool_sha256']
    for path, digest in go_metadata['binary_sha256'].items():
        assert audit.sha(path) == digest
    for path, digest in list(audit.READS.items()):
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, ('changed during review', path)
    result = {'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'outcome': 'identities and completed phases pass; partial observations remain excluded',
              'manifest_sha256': expected_manifest, 'accepted_checkpoint_commit': manifest['checkpoint_commit'],
              'checkpoint_archive_manifest_sha256': manifest['checkpoint_archive_manifest'], 'source37_reports': source_reports,
              'combined_changed_files': changed, 'combined_patch_sha256': composition['patch_sha256'],
              'binary_sha256': manifest['binary_sha256'], 'original_baseline_sidecars_exactly_inherited': True,
              'constant_qualified85_guests_match_author_production84': True, 'build_reports': build_reports,
              'round3_benchmark_files': 53, 'inherited_reference_files_verified': 127, 'helper_sha256': helpers,
              'completed_phases': completed, 'completed_unique_rows': sum(len(d['samples']) for d in docs.values()),
              'fresh_reproduction': fresh_report,
              'completed_observations_including_reproduction': sum(len(d['samples']) for d in docs.values()) +
                  (fresh_report['behavior_only_smoke']['actual_samples'] if fresh_report and 'behavior_only_smoke' in fresh_report else 0),
              'go_metadata_review_sha256': audit.sha(metadata_path),
              'analyses': analyses, 'pending': pending, 'stable_read_input_count': len(audit.READS),
              'stable_read_identity_sha256': hashlib.sha256(json.dumps(audit.READS, sort_keys=True).encode()).hexdigest(),
              'guest_test_or_perf_executions': 0, 'source_root_or_archive_mutations': 0,
              'limits': ['Producer compares complete raw stdout with pinned expected bytes; retained measurement stdout is a hash, not a raw stream.',
                         'All completed stderr samples are complete ASCII below the producer tail limit; smoke statistics match exactly across all eight mylang arms.',
                         'Per-sample raw perf CSV is reused rather than archived; retained counter values and all four running rates are verified.',
                         'One-round tree-size instruction screening is diagnostic only; full native timing/counter phases need their own complete coverage.',
                         'Original round3 preparation has a source/hash receipt and recorded helper identities; the subsequently added fresh helper is independently inspected and qualified.',
                         'The later prepare.py reconstructs source37 factorial maps from an accepted baseline archive; fresh Go is a distinct identity used only for behavior qualification, never measured timing replacement.',
                         'Reference toolchain versions, shim and actual sysroot executable hashes are post-build observations; full toolchains and exhaustive ambient flags are not archived.',
                         'Static source/test qualification is inherited from independent author reviews; this measurement audit runs no tests or guests.',
                         'Rust/Go parity and adoption require full measurements; partial cells are never reported as passed.']}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'out': str(args.out), 'sha256': hashlib.sha256(args.out.read_bytes()).hexdigest(),
                      'completed_rows': result['completed_unique_rows'], 'pending': pending}))


if __name__ == '__main__':
    main()
