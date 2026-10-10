#!/usr/bin/env python3
"""Retained native measurement integrity, without PMU access or native builds."""
import concurrent.futures
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import juice_evidence as evidence


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encoded(value):
    return json.dumps(value, sort_keys=True).encode()


def fixture(root, name='first', adapter='native', collector='perf', runtime=False):
    work = {'name': 'w', 'family': 'test', 'tier': 'quick', 'args': [], 'units': 8,
            'unit': 'record', 'timeout_seconds': 30, 'expected_stdout': 'ok\n',
            'expected_stderr': '', 'exit_code': 0, 'check': [], 'outputs': [], 'weight': 1}
    tool = {'path': '/fixture/collector', 'sha256': sha(b'collector'), 'version': 'fixture1'}
    selected = {'kind': collector, 'tool': tool, 'event': 'instructions:u' if collector == 'perf' else 'Ir',
                'cpu': 2, 'scope': 'user instructions; process and inherited children; whole workload'}
    if runtime:
        selected.update(profile='runtime', event_group='{instructions:u,cycles:u,ref-cycles:u}')
    raw = {}
    samples = []
    ordinary = int(collector != 'perf')
    for index in range(ordinary + 2 + int(adapter == 'mylang')):
        kind = 'native' if index < ordinary else 'sample' if index < ordinary + 2 else 'counted'
        prefix = f'w-{index}-{kind}'
        raw[prefix + '.stdout'] = b'ok\n'
        raw[prefix + '.stderr'] = b''
        if kind != 'sample':
            continue
        metrics = {'instructions': 1000}
        if collector == 'perf':
            text = '1000;;instructions:u;1;100.00\n'
            if runtime:
                metrics.update(cycles=2000, reference_cycles=1500)
                text += '2000;;cycles:u;1;100.00\n1500;;ref-cycles:u;1;100.00\n'
            raw[prefix + '.perf'] = text.encode()
            functions, lines = [], []
        else:
            raw[prefix + '.collector.123'] = b'events: Ir\nfl=program.c\nfn=main\n1 1000\nsummary: 1000\n'
            raw[prefix + '.collector.log.123'] = b'collector log\n'
            functions = [{'file': 'program.c', 'function': 'main', 'object': '???', 'instructions': 1000}]
            lines = [dict(functions[0], line=1)]
        samples.append({'exit_code': 0, 'wall_seconds': 0.1, 'stdout_sha256': sha(b'ok\n'),
                        'stderr_sha256': sha(b''), 'functions': functions, 'lines': lines, 'metrics': metrics})
    build_spec = {'compiler': 'cc' if adapter == 'native' else 'mylang', 'counter_semantics': 'events-v1'}
    build_key = sha(('build-' + adapter).encode())
    binaries = {'plain': b'fixture-plain-binary'}
    if adapter == 'mylang':
        binaries['counted'] = b'fixture-counted-binary'
        raw['w-counters.json'] = encoded({'version': 'mylang-counters-v1', 'totals': {'calls': 3},
                                         'sites': [{'path': str(root / 'workspace/project/a.my'), 'count': 3}]})
    cell = {'units': 8, 'unit': 'record', 'samples': samples, 'functions': samples[0]['functions'],
            'lines': samples[0]['lines'], 'correctness': {'stdout': sha(b'ok\n'), 'stderr': sha(b''), 'files': {}},
            'metrics': {key: {'samples': [value, value], 'median': value, 'min': value,
                              'max': value, 'spread': 0} for key, value in samples[0]['metrics'].items()}}
    if adapter == 'mylang':
        cell['semantic'] = {'version': 'mylang-counters-v1', 'totals': {'calls': 3},
                            'sites': [{'path': 'a.my', 'count': 3}]}
        cell['counter_semantics'] = 'events-v1'
    record = {'version': 'juice-v1', 'identity_scheme': 'mylang-juice-native-v1', 'tool_id': sha(b'tool'),
              'name': name, 'status': 'complete', 'source_root': str(root / 'source'),
              'sources': {'program.c': sha(b'source')},
              'manifest': {'name': 'test', 'adapter': adapter, 'build': build_spec, 'environment': {}},
              'contract': {'name': 'test', 'inputs': {}, 'environment': {}, 'workloads': [work]},
              'collector': selected, 'workloads': {'w': cell},
              'build_config': {'spec': build_spec, 'dependencies': {}, 'compiler': tool},
              'build': {'key': build_key, 'cached': False, 'build_seconds': 0.2,
                        'artifacts': {key: sha(value) for key, value in binaries.items()},
                        'code': {'available': False, 'sections': {}, 'functions': {}}},
              'context': {'system': 'Linux', 'kernel': 'fixture', 'machine': 'x86_64',
                          'cpu': {'model': 'fixture'}, 'libraries': {'/fixture/lib.so': sha(b'library')},
                          'execution_path': str(root / 'workspace/run'), 'collector': selected},
              'evidence': {key: sha(value) for key, value in raw.items()}}
    if runtime:
        record['context']['scheduling_policy'] = {'policy': 'fixture'}
    directory = root / 'records' / name
    directory.mkdir(parents=True)
    path = directory / 'record.json'
    path.write_bytes(encoded(record))
    for filename, data in raw.items():
        (directory / filename).write_bytes(data)
    artifacts = {}
    for kind, data in binaries.items():
        artifact = root / 'builds' / build_key / kind
        artifact.parent.mkdir(parents=True, exist_ok=True)
        artifact.write_bytes(data)
        artifacts[kind] = artifact
    expected = {'workload': copy.deepcopy(work), 'repeats': 2, 'collector': copy.deepcopy(selected),
                'profile': 'runtime' if runtime else 'work', 'contract': copy.deepcopy(record['contract']),
                'sources': copy.deepcopy(record['sources']), 'build_config': copy.deepcopy(record['build_config'])}
    return path, artifacts, expected


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='juice-evidence-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.store = evidence.EvidenceStore(self.root / 'evidence')
        self.key = sha(b'action')
        self.path, self.artifacts, self.expected = fixture(self.root / 'capture')

    def publish(self, validate=lambda: True):
        return self.store.publish(self.key, self.path, self.artifacts, self.expected, validate)

    def mutate_record(self, callback):
        record = json.loads(self.path.read_bytes())
        callback(record)
        self.path.write_bytes(encoded(record))

    def test_roundtrip_retains_exact_record_raw_files_and_binaries(self):
        self.assertTrue(self.publish())
        retained = self.store.lookup(self.key, self.expected)
        self.assertEqual(retained.record_bytes, self.path.read_bytes())
        self.assertEqual(retained.record_digest, sha(self.path.read_bytes()))
        self.assertEqual(retained.read_file('w-0-sample.stdout'), b'ok\n')
        self.assertEqual(retained.read_artifact('plain'), self.artifacts['plain'].read_bytes())
        self.assertEqual(retained.recorded_libraries, {'/fixture/lib.so': sha(b'library')})
        retained.record['status'] = 'incomplete'
        self.assertEqual(retained.record['status'], 'complete')
        self.path.unlink()
        self.artifacts['plain'].unlink()
        restored = self.store.materialize(retained, self.root / 'restored')
        self.assertEqual(restored.read_bytes(), retained.record_bytes)
        verified = evidence.validate_record(restored, {'plain': self.root / 'restored/build/plain'}, self.expected)
        self.assertEqual(verified.record_digest, retained.record_digest)
        self.assertTrue(os.access(self.root / 'restored/build/plain', os.X_OK))

    def test_alias_independent_validation_and_materialization(self):
        direct = evidence.validate_record(self.path, self.artifacts, self.expected)
        self.assertIsNone(self.store.lookup(self.key, self.expected))
        restored = evidence.materialize(direct, self.root / 'comparison')
        self.assertEqual(restored.read_bytes(), self.path.read_bytes())
        self.assertEqual(evidence.artifact_paths(self.path), self.artifacts)

    def test_incomplete_error_empty_evidence_and_missing_trial_are_rejected(self):
        original = self.path.read_bytes()
        changes = [lambda r: r.update(status='incomplete'), lambda r: r.update(error='failure'),
                   lambda r: r.update(evidence={}), lambda r: r['workloads']['w'].update(samples=[])]
        for change in changes:
            with self.subTest(change=change):
                self.path.write_bytes(original)
                self.mutate_record(change)
                with self.assertRaises(evidence.EvidenceError):
                    self.publish()
                self.assertIsNone(self.store.lookup(self.key, self.expected))

    def test_wrong_contract_repeats_collector_profile_and_sources_miss(self):
        self.assertTrue(self.publish())
        variants = [('repeats', 3), ('profile', 'runtime'), ('collector', {}), ('sources', {})]
        for field, value in variants:
            changed = copy.deepcopy(self.expected)
            changed[field] = value
            self.assertIsNone(self.store.lookup(self.key, changed))
        changed = copy.deepcopy(self.expected)
        changed['contract']['environment'] = {'OTHER': '1'}
        self.assertIsNone(self.store.lookup(self.key, changed))
        with self.assertRaises(evidence.EvidenceError):
            self.store.lookup(self.key, dict(self.expected, threshold=10))

    def test_exact_native_build_bytes_and_artifact_set_required(self):
        with self.assertRaises(evidence.EvidenceError):
            evidence.validate_record(self.path, {}, self.expected)
        self.artifacts['plain'].write_bytes(b'changed binary')
        with self.assertRaises(evidence.EvidenceError):
            self.publish()
        self.assertIsNone(self.store.lookup(self.key, self.expected))

    def test_equal_digest_file_does_not_hide_corrupt_duplicate(self):
        (self.path.parent / 'w-0-sample.stderr').write_bytes(b'corruption')
        with self.assertRaises(evidence.EvidenceError):
            self.publish()

    def test_complete_inventory_rejects_omitted_or_extra_raw_files(self):
        self.mutate_record(lambda r: r['evidence'].pop('w-1-sample.perf'))
        with self.assertRaises(evidence.EvidenceError):
            self.publish()
        (self.path.parent / 'w-1-sample.perf').unlink()
        with self.assertRaises(evidence.EvidenceError):
            self.publish()

    def test_partial_raw_count_cannot_become_success_by_updating_checksum(self):
        raw = self.path.parent / 'w-0-sample.perf'
        raw.write_bytes(b'1000;;instructions:u;1;99.00\n')
        self.mutate_record(lambda r: r['evidence'].update({'w-0-sample.perf': sha(raw.read_bytes())}))
        with self.assertRaises(evidence.EvidenceError):
            self.publish()

    def test_inconsistent_samples_summary_and_failed_correctness_rejected(self):
        original = self.path.read_bytes()
        changes = [lambda r: r['workloads']['w']['samples'][0].update(exit_code=1),
                   lambda r: r['workloads']['w']['samples'][0]['metrics'].update(instructions=900),
                   lambda r: r['workloads']['w']['metrics']['instructions'].update(median=900),
                   lambda r: r['workloads']['w']['correctness'].update(stdout=sha(b'wrong'))]
        for change in changes:
            self.path.write_bytes(original)
            self.mutate_record(change)
            with self.assertRaises(evidence.EvidenceError):
                self.publish()

    def test_missing_corrupt_record_raw_or_binary_blob_is_miss(self):
        self.assertTrue(self.publish())
        retained = self.store.lookup(self.key, self.expected)
        for digest in (retained.record_digest, retained.files['w-0-sample.perf'], retained.build_artifacts['plain']):
            with self.subTest(digest=digest):
                blob = self.store.backend.root / 'blobs' / digest
                saved = blob.read_bytes()
                blob.write_bytes(b'corrupt')
                self.assertIsNone(self.store.lookup(self.key, self.expected))
                blob.write_bytes(saved)
                blob.unlink()
                self.assertIsNone(self.store.lookup(self.key, self.expected))
                blob.write_bytes(saved)
        self.assertIsNotNone(self.store.lookup(self.key, self.expected))

    def test_corrupt_alias_is_miss_and_repaired_by_new_valid_publication(self):
        self.assertTrue(self.publish())
        receipt = self.store.backend.root / 'success' / (self.key + '.json')
        receipt.write_text('{}')
        self.assertIsNone(self.store.lookup(self.key, self.expected))
        self.assertTrue(self.publish())
        self.assertIsNotNone(self.store.lookup(self.key, self.expected))

    def test_first_valid_writer_wins_nondeterministic_names_and_seconds(self):
        self.assertTrue(self.publish())
        first = self.store.lookup(self.key, self.expected)
        path, artifacts, expected = fixture(self.root / 'capture', name='second')
        record = json.loads(path.read_bytes())
        record['build']['build_seconds'] = 123
        record['workloads']['w']['samples'][0]['wall_seconds'] = 456
        path.write_bytes(encoded(record))
        self.assertTrue(self.store.publish(self.key, path, artifacts, expected, lambda: True))
        self.assertEqual(self.store.lookup(self.key, expected).record_digest, first.record_digest)

    def test_foreign_first_writer_is_not_replaced_by_an_accidentally_reused_key(self):
        self.assertTrue(self.publish())
        first = self.store.lookup(self.key, self.expected)
        path, artifacts, expected = fixture(self.root / 'foreign', name='foreign')
        record = json.loads(path.read_bytes())
        record['contract']['environment'] = {'MODE': 'different'}
        record['manifest']['environment'] = {'MODE': 'different'}
        expected['contract']['environment'] = {'MODE': 'different'}
        path.write_bytes(encoded(record))
        self.assertFalse(self.store.publish(self.key, path, artifacts, expected, lambda: True))
        self.assertIsNone(self.store.lookup(self.key, expected))
        self.assertEqual(self.store.lookup(self.key, self.expected).record_digest, first.record_digest)

    def test_summary_boolean_does_not_pass_as_numeric_zero(self):
        self.mutate_record(lambda r: r['workloads']['w']['metrics']['instructions'].update(spread=False))
        with self.assertRaises(evidence.EvidenceError):
            self.publish()

    def test_concurrent_publication_retains_one_complete_winner(self):
        second, artifacts, expected = fixture(self.root / 'capture', name='second')
        def commit(path):
            store = evidence.EvidenceStore(self.store.backend.root)
            return store.publish(self.key, path, artifacts, expected, lambda: True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(commit, [self.path, second]))
        self.assertEqual(results, [True, True])
        retained = self.store.lookup(self.key, self.expected)
        self.assertIn(retained.record_digest, [sha(self.path.read_bytes()), sha(second.read_bytes())])

    def test_guard_false_before_and_after_has_no_success(self):
        with self.assertRaises(evidence.InputsChanged):
            self.publish(lambda: False)
        self.assertIsNone(self.store.lookup(self.key, self.expected))
        checks = iter([True, True, False])
        with self.assertRaises(evidence.InputsChanged):
            self.publish(lambda: next(checks))
        self.assertIsNone(self.store.lookup(self.key, self.expected))

    def test_failed_second_writer_does_not_delete_first_success(self):
        self.assertTrue(self.publish())
        original = self.store.lookup(self.key, self.expected).record_digest
        checks = iter([True, False])
        with self.assertRaises(evidence.InputsChanged):
            self.publish(lambda: next(checks))
        self.assertEqual(self.store.lookup(self.key, self.expected).record_digest, original)

    def test_cancellation_before_atomic_publication_leaves_only_disposable_blobs(self):
        with patch.object(self.store.backend, 'publish_success', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.publish()
        self.assertIsNone(self.store.lookup(self.key, self.expected))
        self.assertTrue(self.publish())

    def test_discard_force_and_coordinator_lock_domains_do_not_deadlock(self):
        with self.store.coordinator_lock(self.key):
            self.assertTrue(self.publish())
            self.store.discard(self.key)
            self.assertIsNone(self.store.lookup(self.key, self.expected))
            self.assertTrue(self.publish())

    def test_traversal_case_ambiguity_duplicate_json_and_overlap_rejected(self):
        original = self.path.read_bytes()
        changes = [lambda r: r['evidence'].update({'../escape': sha(b'')}),
                   lambda r: r['evidence'].update({'W-0-SAMPLE.STDOUT': sha(b'ok\n')}),
                   lambda r: r['evidence'].update({'record.json': sha(b'')}),
                   lambda r: r['build']['artifacts'].update({'../../escape': sha(b'')})]
        for change in changes:
            self.path.write_bytes(original)
            self.mutate_record(change)
            with self.assertRaises(evidence.EvidenceError):
                self.publish()
        self.path.write_bytes(b'{"status":"complete","status":"complete"}')
        with self.assertRaises(evidence.EvidenceError):
            self.publish()
        self.path.write_bytes(original)
        with self.assertRaises(evidence.EvidenceError):
            evidence.validate_record(self.path, {'plain': self.path.parent / 'w-0-sample.stdout'}, self.expected)

    def test_symlink_fifo_and_symlink_parent_never_authorize_evidence(self):
        raw = self.path.parent / 'w-0-sample.stdout'
        raw.unlink()
        raw.symlink_to(self.path.parent / 'w-1-sample.stdout')
        with self.assertRaises(evidence.EvidenceError):
            self.publish()
        raw.unlink()
        os.mkfifo(raw)
        with self.assertRaises(evidence.EvidenceError):
            self.publish()
        raw.unlink()
        raw.write_bytes(b'ok\n')
        alias = self.root / 'alias'
        alias.symlink_to(self.path.parent, target_is_directory=True)
        with self.assertRaises(evidence.EvidenceError):
            evidence.validate_record(alias / 'record.json', self.artifacts, self.expected)

    def test_metadata_blob_and_aggregate_bounds_are_enforced(self):
        with patch.object(evidence, 'RECORD_MAX_BYTES', 32):
            with self.assertRaises(evidence.EvidenceError):
                self.publish()
        with patch.object(evidence, 'FILE_MAX_BYTES', 4):
            with self.assertRaises(evidence.EvidenceError):
                self.publish()
        with patch.object(evidence, 'TOTAL_MAX_BYTES', 32):
            with self.assertRaises(evidence.EvidenceError):
                self.publish()
        with patch.object(evidence, 'MAX_FILES', 2):
            with self.assertRaises(evidence.EvidenceError):
                self.publish()

    def test_mylang_counted_run_semantic_document_and_both_binaries_retained(self):
        path, artifacts, expected = fixture(self.root / 'mylang', adapter='mylang')
        self.assertTrue(self.store.publish(self.key, path, artifacts, expected, lambda: True))
        retained = self.store.lookup(self.key, expected)
        self.assertEqual(set(retained.build_artifacts), {'plain', 'counted'})
        self.assertEqual(retained.record['workloads']['w']['semantic']['sites'][0]['path'], 'a.my')
        (path.parent / 'w-counters.json').unlink()
        with self.assertRaises(evidence.EvidenceError):
            evidence.validate_record(path, artifacts, expected)

    def test_valgrind_profiles_reconcile_and_nonreconciling_costs_rejected(self):
        path, artifacts, expected = fixture(self.root / 'grind', collector='callgrind')
        self.assertTrue(self.store.publish(self.key, path, artifacts, expected, lambda: True))
        raw = path.parent / 'w-1-sample.collector.123'
        raw.write_bytes(raw.read_bytes().replace(b'1 1000', b'1 500'))
        record = json.loads(path.read_bytes())
        record['evidence'][raw.name] = sha(raw.read_bytes())
        path.write_bytes(encoded(record))
        with self.assertRaises(evidence.EvidenceError):
            evidence.validate_record(path, artifacts, expected)

    def test_runtime_group_requires_all_three_fully_counted_events(self):
        path, artifacts, expected = fixture(self.root / 'runtime', runtime=True)
        self.assertTrue(self.store.publish(self.key, path, artifacts, expected, lambda: True))
        raw = path.parent / 'w-0-sample.perf'
        raw.write_bytes(b'1000;;instructions:u;1;100\n2000;;cycles:u;1;100\n')
        record = json.loads(path.read_bytes())
        record['evidence'][raw.name] = sha(raw.read_bytes())
        path.write_bytes(encoded(record))
        with self.assertRaises(evidence.EvidenceError):
            evidence.validate_record(path, artifacts, expected)

    def test_atomic_materialization_refuses_existing_destination_and_partial_output(self):
        self.assertTrue(self.publish())
        retained = self.store.lookup(self.key, self.expected)
        destination = self.root / 'existing'
        destination.mkdir()
        (destination / 'owned').write_bytes(b'keep')
        with self.assertRaises(evidence.EvidenceError):
            self.store.materialize(retained, destination)
        self.assertEqual((destination / 'owned').read_bytes(), b'keep')
        with patch.object(Path, 'write_bytes', side_effect=OSError('interrupted write')):
            with self.assertRaises(OSError):
                self.store.materialize(retained, self.root / 'partial')

    def test_standalone_materialization_does_not_create_store_in_nonempty_parent(self):
        self.publish()
        parent = self.root / 'private-output'
        parent.mkdir()
        unrelated = parent / 'unrelated-input.txt'
        unrelated.write_bytes(b'keep existing private contents')
        with self.store.lease():
            retained = self.store.lookup(self.key, self.expected)
            path = evidence.materialize(retained, parent / 'retained')
        self.assertTrue(path.is_file())
        self.assertEqual(unrelated.read_bytes(), b'keep existing private contents')
        self.assertFalse((parent / 'format.json').exists())
        self.assertFalse((parent / 'locks').exists())
        self.assertFalse((self.root / 'partial').exists())


if __name__ == '__main__':
    unittest.main()
