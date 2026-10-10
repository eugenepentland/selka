#!/usr/bin/env python3
"""Simulated-engine orchestration tests; these do not qualify code coverage."""
import base64
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

import fuzz_coverage as coverage

# This engine imitates the supported log grammar, not coverage instrumentation.
SIMULATED_ENGINE = '''#!{python}
import json,sys
from pathlib import Path
args=sys.argv[1:]
options=dict(arg[1:].split('=',1) for arg in args if arg.startswith('-'))
target=Path(args[-1])
mode={mode!r}
(Path(__file__).parent/'calls.jsonl').open('a').write(json.dumps(args)+'\\n')
if 'minimize_crash' in options:
    Path(options['exact_artifact_path']).write_bytes(b'bad')
    raise SystemExit(0)
if mode=='silent':
    raise SystemExit(0)
if mode=='unknownflag':
    print('WARNING: unrecognized flag reload; use -help=1')
if mode!='uninstrumented':
    print('INFO: Loaded 1 modules   (17 inline 8-bit counters): 17 [0x1,0x12),')
if target.is_file():
    print('Running: '+str(target))
    if target.read_bytes()==b'bad' or mode=='crash':
        raise SystemExit(77)
    if mode!='unfinished':
        print('Executed '+str(target)+' in 0 ms')
        print('*** NOTE: fuzzing was not performed, you have only')
    raise SystemExit(0)
if mode=='crash':
    Path(options['artifact_prefix']+'crash-example').write_bytes(b'original-bad')
    raise SystemExit(77)
if mode=='manycrashes':
    for index in range(4):
        Path(options['artifact_prefix']+'crash-'+str(index)).write_bytes(b'bad'+bytes([index]))
    raise SystemExit(77)
if mode=='signal':
    import os,signal
    os.kill(os.getpid(),signal.SIGTERM)
if mode=='symlink':
    (target/'unsafe').symlink_to(Path(__file__))
(target/'discovery').write_bytes(b'found')
runs=int(options['runs'])
if mode=='wrongcount':
    runs-=1
if mode!='unfinished':
    print('#'+str(runs)+'\\tDONE cov: 5 ft: 8 corp: 2/8b lim: 4096 exec/s: 0 rss: 30Mb')
    print('Done '+str(runs)+' runs in 0 second(s)')
print('stat::number_of_executed_units: '+str(runs))
if mode=='duplicatestats':
    print('stat::number_of_executed_units: '+str(runs))
'''


class LibFuzzerWorker(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='coverage-worker-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.corpus = self.root / 'initial'
        self.corpus.mkdir()
        (self.corpus / 'seed').write_bytes(b'initial')
        self.engine = self.make_engine()

    def make_engine(self, mode='normal'):
        engine = self.root / ('engine-' + mode)
        engine.write_text(SIMULATED_ENGINE.format(python=sys.executable, mode=mode))
        engine.chmod(0o755)
        return engine

    def calls(self):
        return [json.loads(line) for line in (self.root / 'calls.jsonl').read_text().splitlines()]

    def explore(self, mode='normal', name='output', **kwargs):
        return coverage.explore(self.make_engine(mode), self.corpus, self.root / name, 17, 32, **kwargs)

    def bundle(self, values, name='bundle.json'):
        path = self.root / name
        payload = {'version': 1, 'kind': 'raw-inputs', 'inputs': [
            {'sha256': coverage.digest(value), 'data': base64.b64encode(value).decode()} for value in values]}
        path.write_text(json.dumps(payload))
        return path

    def test_completed_fixed_seed_retains_discoveries_and_exact_engine_identity(self):
        result = self.explore()
        self.assertTrue(result['complete'])
        self.assertTrue(result['success'])
        self.assertEqual(result['explored'], 32)
        self.assertEqual(result['replayed'], 0)
        self.assertEqual(result['engine']['coverage_schema'], 'libfuzzer-inline8-log-v1')
        self.assertEqual(result['engine']['stats']['observed_pcs'], 5)
        self.assertEqual(result['engine']['sha256'], coverage.digest(self.make_engine().read_bytes()))
        restored = coverage.load_bundle(self.root / 'output/corpus.json')
        self.assertEqual(set(restored.values()), {b'initial', b'found'})
        self.assertEqual((self.corpus / 'seed').read_bytes(), b'initial')
        self.assertEqual(len(list(self.corpus.iterdir())), 1)
        options = self.calls()[0]
        for expected in ('-seed=17', '-runs=32', '-reload=0', '-print_final_stats=1',
                         '-max_len=4096', '-rss_limit_mb=1024', '-malloc_limit_mb=256'):
            self.assertIn(expected, options)
        self.assertEqual(json.loads((self.root / 'output/result.json').read_text()), result)

    def test_independent_shards_each_start_from_pristine_initial_corpus(self):
        for seed in (11, 12):
            coverage.explore(self.engine, self.corpus, self.root / f'shard-{seed}', seed, 32)
        for call in self.calls():
            directory = Path(call[-1])
            original = directory / coverage.digest(b'initial')
            self.assertEqual(original.read_bytes(), b'initial')
            self.assertFalse((directory / coverage.digest(b'found')).exists())
        self.assertEqual((self.corpus / 'seed').read_bytes(), b'initial')

    def test_successful_exit_without_explicit_completion_does_not_certify(self):
        for mode in ('silent', 'unfinished', 'wrongcount', 'uninstrumented', 'unknownflag'):
            with self.subTest(mode=mode):
                result = self.explore(mode, name=mode)
                self.assertFalse(result['complete'])
                self.assertFalse(result['success'])
                self.assertIsNotNone(result['failure'])

    def test_duplicate_final_stats_fail_closed(self):
        with self.assertRaisesRegex(coverage.CoverageError, 'duplicate'):
            self.explore('duplicatestats')
        self.assertFalse((self.root / 'output/result.json').exists())

    def test_signal_is_not_a_completed_campaign(self):
        result = self.explore('signal')
        self.assertFalse(result['success'])
        self.assertFalse(result['complete'])
        self.assertIn(str(-signal.SIGTERM), result['failure'])

    def test_timeout_cannot_certify_even_with_complete_looking_log(self):
        real_run = coverage.run_engine
        def timed_out(*args):
            status, _ = real_run(*args)
            return status, True
        with patch.object(coverage, 'run_engine', side_effect=timed_out):
            result = self.explore()
        self.assertFalse(result['success'])
        self.assertEqual(result['failure'], 'timeout')

    def test_crash_retains_original_and_bounded_minimized_input_without_success(self):
        result = self.explore('crash')
        self.assertFalse(result['success'])
        self.assertFalse(result['complete'])
        self.assertEqual(result['artifacts']['crashes'], ['artifacts/crash-example'])
        self.assertEqual(result['artifacts']['minimized'], ['artifacts/minimized-0'])
        self.assertEqual(set(coverage.load_bundle(self.root / 'output/corpus.json').values()),
                         {b'initial', b'original-bad', b'bad'})
        self.assertIn('-runs=256', self.calls()[1])
        self.assertIn('-max_total_time=5', self.calls()[1])
        self.assertEqual((self.root / 'output/artifacts/crash-example').read_bytes(), b'original-bad')

    def test_minimization_attempts_are_bounded_and_all_originals_retained(self):
        result = self.explore('manycrashes')
        self.assertEqual(len(result['artifacts']['crashes']), 4)
        self.assertEqual(len(result['artifacts']['minimized']), coverage.MAX_MINIMIZATIONS)
        self.assertEqual(len(self.calls()), 1 + 2 * coverage.MAX_MINIMIZATIONS)

    def test_bundle_replays_raw_bytes_on_different_engine_without_exploration(self):
        bundle = self.bundle([b'initial', b'found'])
        alternate = self.make_engine('alternate')
        result = coverage.replay(alternate, bundle, self.root / 'replayed')
        self.assertTrue(result['success'])
        self.assertEqual(result['explored'], 0)
        self.assertEqual(result['replayed'], 2)
        self.assertEqual(result['engine']['sha256'], coverage.digest(alternate.read_bytes()))
        for call in self.calls():
            self.assertIn('-runs=0', call)
            self.assertIn('-reload=0', call)
            self.assertTrue(Path(call[-1]).is_file())
            self.assertFalse(any(arg.startswith('-seed=') for arg in call))
        self.assertEqual(set(coverage.load_bundle(self.root / 'replayed/corpus.json').values()),
                         {b'initial', b'found'})

    def test_failed_fixed_input_retains_original_even_when_engine_saves_no_artifact(self):
        result = coverage.replay(self.engine, self.bundle([b'bad']), self.root / 'replayed')
        self.assertFalse(result['success'])
        self.assertEqual(result['replayed'], 0)
        original = result['artifacts']['crashes'][0]
        self.assertEqual((self.root / 'replayed' / original).read_bytes(), b'bad')
        self.assertEqual(len(result['artifacts']['minimized']), 1)

    def test_replay_exit_zero_without_execution_marker_is_not_success(self):
        result = coverage.replay(self.make_engine('unfinished'), self.bundle([b'initial']), self.root / 'replayed')
        self.assertFalse(result['success'])
        self.assertFalse(result['complete'])
        self.assertEqual(result['replayed'], 0)

    def test_empty_bundle_is_vacuous_replay_and_spawns_no_process(self):
        result = coverage.replay(self.engine, self.bundle([]), self.root / 'replayed')
        self.assertTrue(result['success'])
        self.assertEqual(result['replayed'], 0)
        self.assertFalse((self.root / 'calls.jsonl').exists())

    def test_bundle_checks_digest_encoding_schema_duplicates_and_bounds(self):
        original = json.loads(self.bundle([b'initial']).read_text())
        invalids = []
        bad = json.loads(json.dumps(original)); bad['inputs'][0]['sha256'] = '0' * 64; invalids.append(bad)
        bad = json.loads(json.dumps(original)); bad['inputs'][0]['data'] = '!!'; invalids.append(bad)
        bad = json.loads(json.dumps(original)); bad['version'] = True; invalids.append(bad)
        bad = json.loads(json.dumps(original)); bad['inputs'].append(bad['inputs'][0]); invalids.append(bad)
        bad = json.loads(json.dumps(original)); bad['coverage'] = {}; invalids.append(bad)
        for payload in invalids:
            path = self.root / 'malformed.json'
            path.write_text(json.dumps(payload))
            with self.assertRaises(coverage.CoverageError):
                coverage.load_bundle(path)
        path.write_text('{"version":1,"version":1,"kind":"raw-inputs","inputs":[]}')
        with self.assertRaises(coverage.CoverageError):
            coverage.load_bundle(path)
        with patch.object(coverage, 'MAX_BUNDLE_BYTES', 8):
            with self.assertRaises(coverage.CoverageError):
                coverage.load_bundle(self.bundle([b'initial'], 'bounded.json'))

    def test_symlink_and_nonregular_corpus_entries_are_rejected_without_workers(self):
        unsafe = self.corpus / 'unsafe'
        unsafe.symlink_to(self.engine)
        with self.assertRaises(OSError):
            self.explore()
        unsafe.unlink()
        os.mkfifo(unsafe)
        with self.assertRaises(coverage.CoverageError):
            self.explore()
        self.assertFalse((self.root / 'calls.jsonl').exists())

    def test_oversized_corpus_and_discovery_symlink_fail_closed(self):
        with patch.object(coverage, 'MAX_CORPUS_BYTES', 2):
            with self.assertRaises(coverage.CoverageError):
                self.explore()
        with self.assertRaises(OSError):
            self.explore('symlink')
        self.assertFalse((self.root / 'output/result.json').exists())

    def test_output_reuse_cannot_overwrite_prior_evidence(self):
        self.explore()
        before = (self.root / 'output/result.json').read_bytes()
        with self.assertRaisesRegex(coverage.CoverageError, 'empty'):
            self.explore()
        self.assertEqual((self.root / 'output/result.json').read_bytes(), before)

    def test_invalid_seed_budget_and_resource_options_do_not_start_engine(self):
        for seed, runs in ((0, 32), (-1, 32), (True, 32), (17, 0), (17, coverage.MAX_RUNS + 1)):
            with self.assertRaises(coverage.CoverageError):
                coverage.explore(self.engine, self.corpus, self.root / 'invalid', seed, runs)
        for options in ({'timeout': 0}, {'timeout': 61}, {'max_len': 0}, {'max_len': coverage.MAX_INPUT_BYTES + 1}):
            with self.assertRaises(coverage.CoverageError):
                self.explore(**options)
        self.assertFalse((self.root / 'calls.jsonl').exists())

    def test_initial_corpus_cannot_be_truncated_before_replay_certification(self):
        with self.assertRaisesRegex(coverage.CoverageError, 'truncated'):
            self.explore(max_len=3)
        self.assertFalse((self.root / 'calls.jsonl').exists())

    def test_minimized_candidate_must_reproduce_before_being_labeled_minimized(self):
        real_run = coverage.run_engine
        def passes_proof(command, log, wall):
            if log.name.startswith('minimize-proof-'):
                log.write_text('fixed input did not reproduce\n')
                return 0, False
            return real_run(command, log, wall)
        with patch.object(coverage, 'run_engine', side_effect=passes_proof):
            result = self.explore('crash')
        self.assertFalse(result['success'])
        self.assertEqual(result['artifacts']['minimized'], [])
        self.assertIn(b'original-bad', coverage.load_bundle(self.root / 'output/corpus.json').values())

    def test_manifest_only_reads_selected_inputs_and_rejects_missing_or_changed(self):
        selected = coverage.digest(b'initial')
        (self.corpus / selected).write_bytes(b'initial')
        (self.corpus / '.unlisted').write_bytes(b'not-an-input')
        (self.corpus / 'unlisted').write_bytes(b'not-an-input')
        result = self.explore(initial_digests=[selected])
        self.assertTrue(result['success'])
        self.assertEqual(set(coverage.load_bundle(self.root / 'output/corpus.json').values()),
                         {b'initial', b'found'})
        for values in ([selected, selected], ['invalid'], [{}]):
            with self.assertRaises(coverage.CoverageError):
                self.explore(name='bad-manifest', initial_digests=values)
        (self.corpus / selected).unlink()
        with self.assertRaises(OSError):
            self.explore(name='missing-manifest', initial_digests=[selected])
        (self.corpus / selected).write_bytes(b'changed')
        with self.assertRaisesRegex(coverage.CoverageError, 'mismatch'):
            self.explore(name='changed-manifest', initial_digests=[selected])

    def test_manifest_aggregate_bound_stops_reads_before_later_entries(self):
        values = [b'aa', b'bb', b'cc', b'dd']
        names = [coverage.digest(data) for data in values]
        with patch.object(coverage, 'MAX_CORPUS_BYTES', 3):
            with patch.object(coverage, 'read_bounded', side_effect=values) as reads:
                with self.assertRaisesRegex(coverage.CoverageError, 'corpus exceeds'):
                    coverage.manifest_inputs(self.corpus, names)
        self.assertEqual(reads.call_count, 2)
        self.assertEqual([call.args[0].name for call in reads.call_args_list], names[:2])

    def test_successful_engine_exit_also_kills_remaining_descendants(self):
        launcher = self.root / 'launcher'
        child_pid = self.root / 'child-pid'
        launcher.write_text('#!' + sys.executable + '\n'
                           'import subprocess,sys\nfrom pathlib import Path\n'
                           'child=subprocess.Popen([sys.executable,"-c","import time;time.sleep(60)"])\n'
                           f'Path({str(child_pid)!r}).write_text(str(child.pid))\n')
        launcher.chmod(0o755)
        status, timed_out = coverage.run_engine([str(launcher)], self.root / 'success.log', 3)
        self.assertEqual(status, 0)
        self.assertFalse(timed_out)
        self.assert_stopped(int(child_pid.read_text()))

    def test_timeout_kills_spawned_engine_process_group(self):
        sleeper = self.root / 'sleeper'
        child_pid = self.root / 'child-pid'
        sleeper.write_text('#!' + sys.executable + '\n'
                           'import subprocess,sys,time\n'
                           'from pathlib import Path\n'
                           'child=subprocess.Popen([sys.executable,"-c","import time;time.sleep(60)"])\n'
                           f'Path({str(child_pid)!r}).write_text(str(child.pid))\n'
                           'time.sleep(60)\n')
        sleeper.chmod(0o755)
        status, timed_out = coverage.run_engine([str(sleeper)], self.root / 'sleep.log', 0.5)
        self.assertTrue(timed_out)
        self.assertEqual(status, -signal.SIGKILL)
        self.assert_stopped(int(child_pid.read_text()))

    def assert_stopped(self, pid):
        # An orphan can briefly remain a zombie until the host reaps it.
        path = Path('/proc') / str(pid) / 'stat'
        deadline = time.monotonic() + 2
        while path.exists() and time.monotonic() < deadline:
            state = path.read_text().split(') ', 1)[1].split()[0]
            if state == 'Z':
                return
            time.sleep(0.01)
        self.assertFalse(path.exists(), 'engine descendant survived worker cleanup')

    def test_worker_termination_cleans_engine_group_and_publishes_no_success(self):
        for signum in (signal.SIGTERM, signal.SIGHUP, signal.SIGKILL):
            with self.subTest(signal=signum):
                self.worker_cancel(signum)

    def worker_cancel(self, signum):
        sleeper = self.root / ('sleeper-' + str(signum))
        engine_pid = self.root / ('engine-pid-' + str(signum))
        output = self.root / ('cancelled-' + str(signum))
        sleeper.write_text('#!' + sys.executable + '\n'
                           'import os,time\nfrom pathlib import Path\n'
                           f'Path({str(engine_pid)!r}).write_text(str(os.getpid()))\n'
                           'time.sleep(60)\n')
        sleeper.chmod(0o755)
        command = [sys.executable, str(Path(coverage.__file__)), 'explore', '--engine', str(sleeper),
                   '--corpus', str(self.corpus), '--output', str(output), '--seed', '17', '--runs', '32']
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 3
            while not engine_pid.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(engine_pid.exists())
            child.send_signal(signum)
            stdout, stderr = child.communicate(timeout=3)
            expected = -signal.SIGKILL if signum == signal.SIGKILL else 128 + signum
            self.assertEqual(child.returncode, expected, (stdout, stderr))
            self.assert_stopped(int(engine_pid.read_text()))
            self.assertFalse((output / 'result.json').exists())
        finally:
            if child.poll() is None:
                child.kill()
            child.communicate()

    def test_cli_rejects_arbitrary_engine_flags_and_requires_explicit_engine(self):
        worker = Path(coverage.__file__)
        command = [sys.executable, str(worker), 'explore', '--corpus', str(self.corpus),
                   '--output', str(self.root / 'cli'), '--seed', '17', '--runs', '32']
        missing = subprocess.run(command, capture_output=True)
        self.assertEqual(missing.returncode, 2)
        override = subprocess.run(command + ['--engine', str(self.engine), '-runs=0'], capture_output=True)
        self.assertEqual(override.returncode, 2)
        passed = subprocess.run(command + ['--engine', str(self.engine)], capture_output=True)
        self.assertEqual(passed.returncode, 0, passed.stderr.decode())
        self.assertEqual(Path(passed.stdout.decode().strip()), self.root / 'cli/result.json')


if __name__ == '__main__':
    unittest.main()
