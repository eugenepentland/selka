"""Verify grader tool/system receipts around a complete hidden fixture pack."""
from pathlib import Path
import copy
from . import environment_receipt, pack_grading
from .storage import digest, locked, read_json, write_json


def tools(adapters):
    return {language + ':' + name: item['path'] for language, adapter in adapters.items()
            for name, item in adapter['tools'].items()}


def capture(adapters):
    return environment_receipt.capture(tools=tools(adapters))


def from_configurations(configurations):
    """Derive grading mounts from three frozen task adapters, without recapturing."""
    from .trial_configuration import validate
    if set(configurations) != {'my', 'python', 'zig'}:
        raise ValueError('three frozen language configurations required')
    shared, mounted, adapters, conditions = None, {}, {}, set()
    for language, configuration in configurations.items():
        validate(configuration)
        if configuration['language'] != language:
            raise ValueError('grader configuration language mismatch')
        conditions.add((configuration['application'], configuration['arm']))
        receipt = configuration['environment']
        system = {key: value for key, value in receipt.items() if key not in ('sha256', 'capture_seconds', 'tools')}
        if shared is not None and shared != system:
            raise ValueError('grader configurations require identical system environments')
        shared = system
        adapters[language] = copy.deepcopy(configuration['task_adapter'])
        for name in adapters[language]['tools']:
            mounted[language + ':' + name] = copy.deepcopy(receipt['tools']['task:' + name])
    if len(conditions) != 1:
        raise ValueError('grader configurations must share application and arm')
    body = dict(copy.deepcopy(shared), tools=mounted)
    environment = dict(body, sha256=digest(body), capture_seconds=0)
    environment_receipt.validate(environment, require_system=True, required_tools=tools(adapters))
    return {'adapters': adapters, 'environment': environment, 'origin': 'derived-from-frozen-task-configurations',
            'configuration_sha256': {language: value['sha256'] for language, value in configurations.items()}}


def grade_fixture(pack, roots, adapters, directory, *, environment):
    return _grade(pack, roots, adapters, directory, environment=environment, kind='fixture')


def grade_calibration(pack, roots, adapters, directory, *, environment):
    return _grade(pack, roots, adapters, directory, environment=environment, kind='calibration')


def _grade(pack, roots, adapters, directory, *, environment, kind):
    directory = Path(directory)
    directory.mkdir(exist_ok=False)
    with locked(directory):
        write_json(directory / 'environment.json', environment)
        environment = read_json(directory / 'environment.json')
        try:
            before = environment_receipt.verify(environment, require_system=True, required_tools=tools(adapters))
            write_json(directory / 'environment-before.json', before)
            grader = pack_grading.grade_fixture if kind == 'fixture' else pack_grading.grade_calibration
            result = grader(pack, roots, adapters, directory / 'pack')
            after = environment_receipt.verify(environment, require_system=True, required_tools=tools(adapters))
            write_json(directory / 'environment-after.json', after)
            report = {'version': 'verified-' + kind + '-grading-v1', 'record_kind': kind,
                      'environment_sha256': environment['sha256'], 'pack_result_sha256': digest(result),
                      'verification_seconds': before['capture_seconds'] + after['capture_seconds'],
                      'grading': result, 'comparative_claim': False}
            write_json(directory / 'result.json', report)
            return report
        except Exception as error:
            write_json(directory / 'interrupted.json', {'type': type(error).__name__, 'message': str(error),
                       'recovery': 'inspect preserved intermediate grading; this attempt cannot be overwritten'})
            raise
