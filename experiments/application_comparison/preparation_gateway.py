"""Practice-only verification and checked transition into the measured task."""
import copy
from . import session
from .execution import verify_adapter
from . import public_verification
from .storage import digest, locked, read_json, snapshot, verify_snapshot, write_json


class PreparationGateway:
    def __init__(self, task_gateway, adapter, public_case):
        self.task_gateway = task_gateway
        self.root = task_gateway.root
        self.adapter = copy.deepcopy(adapter)
        self.public_case = copy.deepcopy(public_case)
        verify_adapter(self.adapter)
        public_verification.validate(self.public_case)
        if self.adapter['language'] != session.load(self.root)['language']:
            raise ValueError('practice adapter language mismatch')
        self.directory = self.root / 'preparation-checks'
        self.directory.mkdir(exist_ok=True)
        self.config = self.configuration()
        with locked(self.directory):
            path = self.directory / 'configuration.json'
            if path.exists() and read_json(path) != self.config:
                raise ValueError('practice verification configuration changed')
            write_json(path, self.config)
            if not (self.directory / 'checks.json').exists():
                write_json(self.directory / 'checks.json', [])

    def configuration(self):
        verify_adapter(self.adapter)
        return {'adapter': self.adapter['sha256'], 'public_case': digest(self.public_case)}

    def dispatch(self, name, arguments):
        with locked(self.directory):
            if read_json(self.directory / 'configuration.json') != self.configuration():
                raise ValueError('practice verification configuration changed')
            manifest = session.load(self.root)
            if manifest['phase'] != 'preparing':
                raise ValueError('practice phase is not active')
            def remaining():
                return manifest['budgets']['preparation_seconds'] - session.elapsed(manifest['preparation_started'], session.clock())
            checks = read_json(self.directory / 'checks.json')
            if name == 'command':
                return self.task_gateway.dispatch(name, arguments)
            if name == 'check' and arguments == {}:
                if remaining() <= 0:
                    raise ValueError('preparation budget exhausted')
                directory = self.directory / f'{len(checks):04}'
                directory.mkdir(exist_ok=False)
                captured = snapshot(self.root / 'practice', directory / 'source')
                record = public_verification.run(directory / 'source', captured, self.adapter,
                                                 self.public_case, directory / 'execution', remaining)
                passed = record['passed']
                checks.append({'source': captured, 'passed': passed, 'finished': session.clock(),
                               'execution_sha256': digest(record)})
                write_json(self.directory / 'checks.json', checks)
                return {'practice_check': len(checks) - 1, 'passed': passed,
                        'cases': public_verification.summary(record),
                        'diagnostics': public_verification.diagnostics(record, directory / 'execution')}
            if name == 'finish' and isinstance(arguments, dict) and set(arguments) == {'reason'}:
                reason = arguments['reason']
                if reason not in ('completed', 'abandoned'):
                    raise ValueError('invalid practice completion reason')
                outcome = 'budget' if remaining() <= 0 else 'failed'
                if reason == 'completed' and outcome != 'budget':
                    if not checks or not checks[-1]['passed']:
                        raise ValueError('practice completion requires a passing check')
                    verify_snapshot(self.root / 'practice', checks[-1]['source'])
                    outcome = 'passed'
                started = session.start_task(self.root, outcome)
                return {'phase': started['phase'], 'preparation_outcome': outcome}
            raise ValueError('unknown practice operation')
