"""Participant command, public-check and completion boundary. Model transport is pending.

All paths, mounts and limits are trusted coordinator inputs. Participants supply
only argv. A model integration must expose only reviewed dispatch operations;
using this class alongside unrestricted agent tools is not whole-agent isolation.
"""
import copy
import math
from pathlib import Path
from . import session
from .isolation import Limits, run
from .execution import verify_adapter
from . import public_verification
from .storage import canonical, digest, locked, path_identity, read_json, write_json


class Gateway:
    def __init__(self, root, tools, limits=None, *, adapter=None, public_case=None, retain_command_cache=False):
        if type(retain_command_cache) is not bool:
            raise ValueError("retain_command_cache must be boolean")
        self.retain_command_cache = retain_command_cache
        self.root = Path(root).resolve()
        if (adapter is None) != (public_case is None):
            raise ValueError('public checking requires both adapter and case')
        self.adapter = copy.deepcopy(adapter)
        self.public_case = copy.deepcopy(public_case)
        if self.adapter is not None:
            verify_adapter(self.adapter)
            public_verification.validate(self.public_case)
            manifest = session.load(self.root)
            if self.adapter['language'] != manifest['language']:
                raise ValueError('public check adapter language mismatch')
            if manifest['record_kind'] in ('agent', 'calibration') and manifest['arm'] == 'main' and manifest['language'] == 'zig':
                from .guardian_adapter import require
                require(self.adapter)
        self.tools = {name: path_identity(path) for name, path in tools.items()}
        self.limits = limits or Limits()
        self.limits.validate()
        self.log = self.root / 'gateway'
        self.log.mkdir(exist_ok=True)
        with locked(self.log):
            config_path = self.log / 'configuration.json'
            config = self.configuration()
            if config_path.exists():
                if digest(read_json(config_path)) != digest(config):
                    raise ValueError('participant gateway configuration changed')
            else:
                write_json(config_path, config)

    def configuration(self):
        return {**({'retain_command_cache': True} if self.retain_command_cache else {}),
                'tools': self.tools, 'limits': self.limits.__dict__,
                'adapter_sha256': self.adapter['sha256'] if self.adapter is not None else None,
                'public_case_sha256': digest(self.public_case) if self.public_case is not None else None}

    def dispatch(self, name, arguments):
        # Serialize all participant operations, while session APIs own their locks.
        with locked(self.log):
            if digest(read_json(self.log / 'configuration.json')) != digest(self.configuration()):
                raise ValueError('participant gateway configuration changed')
            if name == 'check' and arguments == {}:
                return self.check()
            if name == 'finish' and isinstance(arguments, dict) and set(arguments) == {'reason'}:
                if arguments['reason'] not in ('completed', 'abandoned'):
                    raise ValueError('invalid participant completion reason')
                manifest = session.load(self.root)
                if manifest['phase'] != 'working':
                    raise ValueError('completion requires active task')
                late = session.elapsed(manifest['task_started'], session.clock()) >= manifest['budgets']['task_seconds']
                sealed = session.seal(self.root, 'budget' if late else arguments['reason'])
                return {'phase': sealed['phase'], 'reason': sealed['seal_reason'],
                        'final_submission': sealed['final_submission']}
            return self.command(name, arguments)

    def check(self):
        if self.adapter is None:
            raise ValueError('public checking is not configured')
        manifest = session.load(self.root)
        if manifest['phase'] != 'working':
            raise ValueError('public check requires active task')
        verify_adapter(self.adapter)
        row = session.submit(self.root)
        directory = self.root / 'submissions' / f"{row['index']:03}"
        def remaining():
            return manifest['budgets']['task_seconds'] - session.elapsed(manifest['task_started'], session.clock())
        if row['scope_violations']:
            record = {'source_sha256': row['source']['sha256'], 'passed': False,
                      'scope_violations': row['scope_violations']}
        else:
            record = public_verification.run(directory / 'source', row['source'], self.adapter,
                                             self.public_case, directory / 'check', remaining)
        session.record_check(self.root, row['index'], record)
        return {'submission': row['index'], 'passed': record['passed'],
                'cases': public_verification.summary(record),
                'scope_violations': row['scope_violations'], 'diagnostics': public_verification.diagnostics(record, directory / 'check')}

    def command(self, name, arguments):
        if name != 'command' or not isinstance(arguments, dict) or set(arguments) != {'argv'}:
            raise ValueError('unknown participant operation or arguments')
        argv = arguments['argv']
        if (not isinstance(argv, list) or not argv or len(argv) > 256 or
                any(not isinstance(value, str) or '\x00' in value for value in argv) or
                len(canonical(argv)) > 65536):
            raise ValueError('invalid participant command')
        with locked(self.root):
            manifest = session.load(self.root)
            phase = manifest['phase']
            if phase not in ('preparing', 'working'):
                raise ValueError('participant phase is not active')
            started = manifest['preparation_started'] if phase == 'preparing' else manifest['task_started']
            budget = manifest['budgets']['preparation_seconds' if phase == 'preparing' else 'task_seconds']
            for identity in self.tools.values():
                if path_identity(identity['path']) != identity:
                    raise ValueError('participant tool changed')
            remaining = budget - session.elapsed(started, session.clock())
            if remaining <= 0:
                raise ValueError('participant phase deadline exhausted')
            limits = Limits(**dict(self.limits.__dict__, wall_seconds=min(self.limits.wall_seconds, remaining),
                                   cpu_seconds=min(self.limits.cpu_seconds, max(1, math.ceil(remaining)))))
            # Session event sequence names are unique under the same coordinator lock.
            directory = self.log / f"{len(manifest['events']):06}"
            directory.mkdir(exist_ok=False)
            request = {'operation': name, 'argv': argv, 'phase': phase, 'started': session.clock(),
                       'tools': self.tools, 'limits': limits.__dict__}
            write_json(directory / 'request.json', request)
            work = self.root / ('practice' if phase == 'preparing' else 'work')
            cache = directory / 'cache' if self.retain_command_cache else None
            if cache is not None:
                cache.mkdir()
            result = run(work, argv, tools={key: item['path'] for key, item in self.tools.items()}, limits=limits, cache=cache)
            if cache is not None:
                try:
                    result['retained_cache'] = path_identity(cache)
                except (OSError, ValueError) as error:
                    result['cache_retention_error'] = str(error)
            stdout, stderr = result.pop('stdout'), result.pop('stderr')
            (directory / 'stdout').write_bytes(stdout)
            (directory / 'stderr').write_bytes(stderr)
            finished = session.clock()
            result.update(finished=finished, request_sha256=digest(request),
                          within_phase_budget=session.elapsed(started, finished) <= budget)
            write_json(directory / 'result.json', result)
            session.save(self.root, manifest, 'participant-command', record=directory.name,
                         request_sha256=digest(request), result_sha256=digest(result))
            # Paths/receipts and trusted tool configuration remain coordinator-only.
            return {'outcome': result['outcome'], 'returncode': result['returncode'],
                    'within_phase_budget': result['within_phase_budget'],
                    'stdout': stdout.decode('utf-8', errors='replace'),
                    'stderr': stderr.decode('utf-8', errors='replace')}
