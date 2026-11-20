"""Single-context handoff: a participant waits in its own context across `begin`.

No model participant. The poll, its telemetry record and the clock boundary are
exercised directly; the integration case freezes a fixture cohort and hands off
from another thread, exactly as a coordinator does from another process.
"""
from pathlib import Path
import tempfile
import threading
import unittest

from experiments.application_comparison import iteration_log, session
from experiments.application_comparison.storage import digest, path_identity, read_json, write_json
from experiments.development_velocity import runner, telemetry
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
HANDOFF = 'The timed application is now active. Read TASK.md with your bridge and implement it.'


class AwaitHandoff(unittest.TestCase):
    """The gateway half: phases, the stored text, the budgeted wait and the record."""

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='development-handoff-')
        self.addCleanup(temporary.cleanup)
        parent = Path(temporary.name)
        baseline = parent / 'baseline'
        baseline.mkdir()
        (baseline / 'main.py').write_text('def run(request):\n    return {}\n')
        self.root = parent / 'attempt'
        session.prepare(self.root, baseline, language='python', block='fixture',
                        cohort='handoff-fixture', participant='handoff-fixture',
                        model='fixture', kind='fixture', protected=['main.py'])
        session.start_preparation(self.root)
        self.gateway = telemetry.ObservedGateway(self.root, {'workflow': str(REPO / 'scripts')},
                                                 runner.LIMITS)
        # The wait is shortened here; production polls every 0.5 s for up to 540 s.
        self.gateway.handoff_poll_seconds = 0.02
        self.gateway.handoff_wait_seconds = 0.25

    def store_handoff(self, text=HANDOFF):
        write_json(self.root / 'handoff.json',
                   {'version': 'attempt-handoff-v1', 'text': text, 'sha256': digest(text)})

    def test_a_spent_wait_answers_ready_and_asks_for_another_call(self):
        response = self.gateway.dispatch('await-handoff', {})
        self.assertEqual(response, {'phase': 'ready', 'message': telemetry.HANDOFF_WAITING})
        self.assertEqual(session.load(self.root)['phase'], 'preparing')

    def test_a_started_clock_answers_working_with_the_text_begin_stored(self):
        self.store_handoff()
        self.gateway.handoff_wait_seconds = 30
        timer = threading.Timer(0.1, session.start_task, (self.root, 'passed'))
        self.addCleanup(timer.cancel)
        timer.start()
        response = self.gateway.dispatch('await-handoff', {})
        self.assertEqual(response, {'phase': 'working', 'message': HANDOFF})

    def test_a_begin_without_a_message_still_hands_off(self):
        session.start_task(self.root, 'passed')
        self.assertEqual(self.gateway.dispatch('await-handoff', {}),
                         {'phase': 'working', 'message': telemetry.DEFAULT_HANDOFF})

    def test_a_changed_handoff_message_fails_closed(self):
        self.store_handoff()
        record = read_json(self.root / 'handoff.json')
        write_json(self.root / 'handoff.json', dict(record, text=record['text'] + ' extra'))
        session.start_task(self.root, 'passed')
        with self.assertRaisesRegex(ValueError, 'handoff message identity mismatch'):
            self.gateway.dispatch('await-handoff', {})

    def test_the_poll_takes_no_arguments(self):
        with self.assertRaisesRegex(ValueError, 'await-handoff takes no arguments'):
            self.gateway.dispatch('await-handoff', {'record': 0})

    def test_the_poll_is_recorded_and_stays_outside_the_application_clock(self):
        self.gateway.dispatch('await-handoff', {})
        request = read_json(self.root / 'telemetry/000000/request.json')
        result = read_json(self.root / 'telemetry/000000/result.json')
        self.assertEqual((request['operation'], request['phase']), ('await-handoff', 'preparing'))
        self.assertEqual(result['response'], {'phase': 'ready', 'message': telemetry.HANDOFF_WAITING})
        self.assertEqual(result['request_sha256'], digest(request))
        self.assertGreaterEqual(result['elapsed_seconds'], 0.25)
        session.start_task(self.root, 'passed')
        session.seal(self.root, 'abandoned')
        profile = telemetry.summarize(self.root, arm='fixture')
        # The clock starts at `begin`; a poll recorded while preparing is not in it.
        self.assertEqual(profile['operations'], [])
        self.assertEqual(profile['operation_seconds_by_declared_purpose'], {})


class HandoffThroughTheBridge(unittest.TestCase):
    """The runner half: both arms accept the tool, `begin` stores the text, routing works."""

    def test_both_arms_expose_the_bridge_tool(self):
        for interface in ('files', 'store'):
            self.assertIn(runner.HANDOFF, runner.OPERATIONS[interface])
        self.assertNotIn(runner.HANDOFF, telemetry.STORE_VERBS)

    def test_a_participant_waits_through_begin_in_one_context(self):
        with tempfile.TemporaryDirectory(prefix='development-handoff-cohort-') as temporary:
            study = Path(temporary) / 'study'
            iteration_log.create(study, {'kind': 'tooling-fixture-not-agent-evaluation'})
            proof = Path(temporary) / 'proof.txt'
            proof.write_text('Test fixture readiness; never a scored launch authorization.\n')
            readiness = Path(temporary) / 'readiness.json'
            runner.write_json(readiness, {'runtime_verified': True, 'library_verified': True,
                                          'starters_verified': True, 'cases_reviewed': True,
                                          'tasks': list(runner.catalog.IDS),
                                          'proofs': [path_identity(proof)]})
            patched = patch.object(runner, 'source_identity', return_value={'fixture': 'stable'})
            patched.start()
            self.addCleanup(patched.stop)
            frozen = runner.freeze(study, 'handoff-fixture', readiness)
            root = Path(frozen['cohort'])
            item = frozen['dispatch_order'][0]
            task, pair, arm = (item[key] for key in ('task', 'pair', 'arm'))
            token = runner.prepare(root, task, pair, arm)['token']
            attempt = root / task / pair / arm
            self.assertEqual(runner.agent(root, token, 'finish', {'reason': 'abandoned'})['phase'], 'ready')
            runner.bind_context(root, task, pair, arm, '/root/handoff-fixture', 'c' * 64)
            # The coordinator begins from another context while the participant polls.
            started = []
            timer = threading.Timer(0.2, lambda: started.append(
                runner.begin(root, task, pair, arm, HANDOFF)))
            self.addCleanup(timer.cancel)
            timer.start()
            response = runner.agent(root, token, runner.HANDOFF, {})
            timer.join()
            self.assertEqual(response, {'phase': 'working', 'message': HANDOFF})
            self.assertEqual(started[0]['handoff_sha256'], digest(HANDOFF))
            stored = read_json(attempt / 'handoff.json')
            self.assertEqual((stored['version'], stored['text']), ('attempt-handoff-v1', HANDOFF))
            self.assertEqual(read_json(attempt / 'telemetry/000000/request.json')['operation'],
                             runner.HANDOFF)
            # Called again inside the clock it returns at once, the same message.
            self.assertEqual(runner.agent(root, token, runner.HANDOFF, {}),
                             {'phase': 'working', 'message': HANDOFF})
            runner.agent(root, token, 'finish', {'reason': 'abandoned'})
            with self.assertRaisesRegex(ValueError, 'not awaiting a task handoff'):
                runner.agent(root, token, runner.HANDOFF, {})


if __name__ == '__main__':
    unittest.main()
