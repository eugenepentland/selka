"""Exercise the real transport/launcher against a local server, never the API."""
import http.server
import json
from pathlib import Path
import tempfile
import threading
import subprocess
import sys
import unittest
from experiments.application_comparison import adjudication, cohort, cohort_sessions, cohort_summary, coordinator_receipt, coordinator_run, practice_pack, task_pack, trial_configuration
from experiments.application_comparison.responses_transport import ResponsesTransport
from experiments.application_comparison.storage import read_json, write_json

ROOT = Path(__file__).resolve().parents[2] / 'experiments/application_comparison'


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.server.requests.append(body)
        index = len(self.server.requests)
        if index == 8:
            self.send_response(500)
            self.end_headers()
            return
        response = {'model': 'fixture-model', 'id': f'r{index}', 'status': 'completed',
            'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2},
            'output': [{'type': 'function_call', 'call_id': f'c{index}', 'name': 'finish',
                        'arguments': '{"reason":"abandoned"}'}]}
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())


class CalibrationLaunchTests(unittest.TestCase):
    def test_credentials_are_explicit_and_never_saved_on_invalid_request(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / 'launch'
            for key in (None, '', 'secret\n', 'x' * 4097):
                with self.subTest(key_length=None if key is None else len(key)), self.assertRaises(ValueError):
                    coordinator_run.run({'operation': 'calibration'}, destination, api_key=key)
                self.assertFalse(destination.exists())
            with self.assertRaisesRegex(ValueError, 'unsupported calibration request fields'):
                coordinator_run.run({'operation': 'calibration', 'api_key': 'private'}, destination, api_key='private')
            self.assertFalse(destination.exists())

    def test_fresh_calibration_uses_transport_and_preserves_unscored_kind(self):
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        server.requests = []
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                toolchain = root / 'toolchain'
                toolchain.mkdir()
                (toolchain / 'lib').mkdir()
                (toolchain / 'zig').write_text('fixture compiler; never executed')
                host = root / 'host'
                host.write_text('fixture runtime; never executed')
                task = 'planner-input-boundary'
                task_pack.create(root / 'task', task=task, hidden_seed='local-calibration-only')
                practices, configurations = {}, {}
                for language in cohort.LANGUAGES:
                    practices[language] = root / ('practice-' + language)
                    practice_pack.create(practices[language], language=language)
                    for arm in ('main', 'language-focused'):
                        configurations[f'{arm}/{task}/{language}'] = trial_configuration.freeze(language, 'planner', arm,
                            zig=toolchain, guardian=host, byte_io=host, compiler=host, navigate=host)
                endpoint = f'http://127.0.0.1:{server.server_port}/v1/responses'
                identity = ResponsesTransport('fixture', endpoint=endpoint).identity
                provenance = coordinator_receipt.capture(identity)
                frozen = root / 'cohort'
                freeze_settings = dict(kind='calibration',
                    blocks=[dict(id=task, application='planner', tier='small', family='local-boundary')],
                    seed='local-calibration', model_settings={'model': 'fixture-model', 'max_reported_tokens_per_phase': 100},
                    budgets=dict(preparation_seconds=1200, task_seconds=1800, max_submissions=20, max_output_tokens=37, max_turns=6),
                    baseline_paths={f'planner/small/{language}': ROOT / 'baselines/planner' / language for language in cohort.LANGUAGES},
                    task_paths={task: root / 'task'}, practice_paths=practices, configurations=configurations, coordinator=provenance)
                cohort.freeze(frozen, **freeze_settings)
                envelope = root / 'attempt'
                cohort_sessions.prepare_calibration(frozen, task + '-r1-python', envelope)
                request = {'operation': 'calibration', 'cohort': str(frozen), 'envelope': str(envelope),
                    'coordinator': provenance, 'transport_identity': identity, 'endpoint': endpoint}
                # Rejection must occur before any HTTP request or session execution.
                changed = dict(request, endpoint=endpoint + '/changed')
                rejected = root / 'changed-transport'
                secret = 'sentinel-private-credential-never-persist'
                failure = coordinator_run.run(changed, rejected, api_key=secret, wall_seconds=60)
                self.assertEqual(failure['outcome'], 'failed')
                self.assertIsNone(failure['model_calls'])
                self.assertIn('transport differs', (rejected / 'stderr').read_text())
                for artifact in rejected.iterdir():
                    if artifact.is_file():
                        self.assertNotIn(secret.encode(), artifact.read_bytes())
                no_budget = root / 'no-budget-cohort'
                cohort.freeze(no_budget, **dict(freeze_settings, model_settings={'model': 'fixture-model'}))
                rejected = root / 'missing-limit'
                failure = coordinator_run.run(dict(request, cohort=str(no_budget)), rejected,
                                              api_key='fixture', wall_seconds=60)
                self.assertEqual(failure['outcome'], 'failed')
                self.assertIn('frozen reported-token limit', (rejected / 'stderr').read_text())
                self.assertEqual(server.requests, [])
                self.assertFalse((envelope / 'session/driver').exists())
                output = root / 'launch'
                result = coordinator_run.run(request, output, api_key='fixture', wall_seconds=60)
                self.assertEqual(result['outcome'], 'completed', (output / 'stderr').read_text())
                self.assertEqual(result['model_calls'], 2)
                self.assertEqual(len(server.requests), 2)
                self.assertEqual(read_json(output / 'request.json'), request)
                report = read_json(output / 'stdout')['result']
                self.assertEqual(report['version'], 'calibration-session-result-v1')
                self.assertEqual(report['seal_reason'], 'abandoned')
                self.assertFalse(report['comparative_claim'])
                self.assertEqual(report['task']['reported_token_limit'], 100)
                roots = [envelope / 'session']
                for language in ('my', 'zig'):
                    other = root / language
                    provision = subprocess.run([sys.executable, '-m', 'experiments.application_comparison.cohort_sessions',
                        '--kind', 'calibration', '--cohort', str(frozen), '--session-id', f'{task}-r1-{language}',
                        '--directory', str(other)], cwd=ROOT.parents[1], capture_output=True, text=True, timeout=60)
                    self.assertEqual(provision.returncode, 0, provision.stderr)
                    launched = root / ('launch-' + language)
                    request_file = root / (language + '-request.json')
                    write_json(request_file, dict(request, envelope=str(other)))
                    command = [sys.executable, '-m', 'experiments.application_comparison.coordinator_run',
                        '--request', str(request_file), '--directory', str(launched), '--wall-seconds', '60']
                    if language == 'my':
                        missing = subprocess.run(command, cwd=ROOT.parents[1], capture_output=True, text=True,
                            env={'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8'}, timeout=60)
                        self.assertNotEqual(missing.returncode, 0)
                        self.assertIn('requires an API key', missing.stderr)
                        self.assertFalse(launched.exists())
                    run = subprocess.run(command, cwd=ROOT.parents[1], capture_output=True, text=True,
                        env={'PATH': '/usr/bin:/bin', 'LANG': 'C.UTF-8', 'OPENAI_API_KEY': 'fixture'}, timeout=70)
                    self.assertEqual(run.returncode, 0, run.stderr)
                    result = read_json(launched / 'result.json')
                    self.assertEqual(result['outcome'], 'completed', (launched / 'stderr').read_text())
                    self.assertEqual(result['model_calls'], 2)
                    roots.append(other / 'session')
                self.assertEqual(len(server.requests), 6)
                grading = root / 'grading'
                grade_request = {'operation': 'grade-calibration', 'cohort': str(frozen),
                    'roots': [str(path) for path in roots], 'directory': str(grading),
                    'coordinator': provenance, 'transport_identity': identity}
                grade_launch = root / 'grade-launch'
                result = coordinator_run.run(grade_request, grade_launch, wall_seconds=60)
                self.assertEqual(result['outcome'], 'completed', (grade_launch / 'stderr').read_text())
                self.assertEqual(result['model_calls'], 0)
                self.assertEqual(len(server.requests), 6)
                for path in ('result.json', 'verified/result.json', 'verified/pack/result.json'):
                    graded = read_json(grading / path)
                    self.assertEqual(graded['record_kind'], 'calibration')
                    self.assertFalse(graded['comparative_claim'])
                summary = cohort_summary.summarize(frozen, [grading])
                self.assertEqual(summary['record_kind'], 'calibration')
                self.assertFalse(summary['comparative_claim'])
                for language in cohort.LANGUAGES:
                    values = summary['languages'][language]
                    self.assertEqual((values['assigned'], values['graded'], values['accepted']), (2, 1, 0))
                    self.assertEqual(values['status_counts'], {'graded': 1, 'not-launched': 1})
                    self.assertEqual(values['reported_tokens'], 4)
                    self.assertEqual(values['token_observations'], 1)
                    self.assertFalse(values['token_telemetry_complete'])
                    self.assertEqual(values['preparation']['observed'], 1)
                    self.assertEqual(values['task']['observed'], 1)
                    self.assertEqual(values['preparation_stops'],
                                     {'counts': {'preparation-ended': 1}, 'observed': 1, 'missing': 1})
                    self.assertEqual(values['task_stops'],
                                     {'counts': {'sealed': 1}, 'observed': 1, 'missing': 1})
                    self.assertEqual(values['seal_reasons']['counts'], {'abandoned': 1})
                for pair in summary['paired'].values():
                    self.assertEqual(pair['neither_accepted'], 1)
                    self.assertEqual(pair['incomplete'], 1)
                rejected = root / 'fixture-grade-rejection'
                result = coordinator_run.run(dict(grade_request, operation='grade-fixture',
                    directory=str(root / 'forbidden-grading')), rejected, wall_seconds=60)
                self.assertEqual(result['outcome'], 'failed')
                self.assertIn('v5 fixture cohort', (rejected / 'stderr').read_text())
                self.assertFalse((root / 'forbidden-grading').exists())
                interrupted = root / 'interrupted-attempt'
                cohort_sessions.prepare_calibration(frozen, task + '-r2-python', interrupted)
                failed_launch = root / 'interrupted-launch'
                result = coordinator_run.run(dict(request, envelope=str(interrupted)), failed_launch,
                                            api_key='fixture', wall_seconds=60)
                self.assertEqual(result['outcome'], 'failed')
                self.assertEqual(len(server.requests), 8)
                self.assertTrue((interrupted / 'session/model-preparation/result.json').exists())
                self.assertFalse((interrupted / 'session/driver/result.json').exists())
                summary = cohort_summary.summarize(frozen, [grading])
                failed = next(row for row in summary['attempts'] if row['session_id'] == task + '-r2-python')
                self.assertEqual(failed['status'], 'infrastructure-failure')
                self.assertEqual(failed['interruption_phase'], 'working')
                self.assertEqual(failed['preparation_stop'], 'preparation-ended')
                self.assertIsNotNone(failed['preparation_seconds'])
                self.assertIsNone(failed['task_seconds'])
                self.assertIsNone(failed['reported_tokens'])
                self.assertEqual(failed['partial_reported_tokens'], 2)
                self.assertFalse(failed['usage_complete'])
                totals = summary['languages']['python']
                self.assertEqual(totals['reported_tokens'], 4)
                self.assertEqual(totals['partial_reported_tokens'], 2)
                self.assertEqual(totals['preparation']['observed'], 2)
                self.assertEqual(totals['task']['observed'], 1)
                reviews = root / 'reviews'
                review = adjudication.record(interrupted / 'session', reviews, category='transport-interruption',
                    reviewer='fixture-reviewer', reason='Local fixture returned HTTP 500 during the task.',
                    evidence_paths=[failed_launch / 'stderr'])
                reviewed = cohort_summary.summarize(frozen, [grading], reviews=reviews)
                self.assertEqual(reviewed['reviews_head_sha256'], review['sha256'])
                classified = next(row for row in reviewed['attempts'] if row['session_id'] == task + '-r2-python')
                self.assertEqual(classified['review_category'], 'transport-interruption')
                self.assertEqual(classified['review_status'], 'current')
                self.assertEqual(classified['status'], failed['status'])
                self.assertEqual(reviewed['languages']['python']['review_categories']['counts'], {'transport-interruption': 1})
                self.assertEqual(reviewed['languages']['python']['assigned'], totals['assigned'])
                self.assertEqual(reviewed['languages']['python']['accepted'], totals['accepted'])
                self.assertEqual(reviewed['paired'], summary['paired'])
                for body in server.requests:
                    self.assertEqual(body['model'], 'fixture-model')
                    self.assertEqual(body['max_output_tokens'], 37)
                    self.assertNotIn('local-calibration-only', json.dumps(body))
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main()
