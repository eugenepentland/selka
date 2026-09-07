"""Complete fixture preparation/task orchestration; scored launch stays disabled."""
from pathlib import Path
from . import environment_receipt, model_loop, session
from .participant_gateway import Gateway
from .preparation_gateway import PreparationGateway
from .storage import digest, locked, read_json, snapshot, source_files, write_json


def run_fixture(root, complete, **settings):
    return _run(root, complete, _kind='fixture', **settings)


def run_calibration(root, complete, **settings):
    return _run(root, complete, _kind='calibration', **settings)


def _run(root, complete, *, _kind, tools, task_adapter, task_case, practice_source,
                practice_adapter, practice_case, practice_prompt, task_prompt,
                transport_identity, max_turns=100, max_output_tokens=4096, max_reported_tokens=None, environment=None, trial_configuration=None, coordinator=None):
    root = Path(root)
    manifest = session.load(root)
    if 'max_reported_tokens_per_phase' in manifest and max_reported_tokens != manifest['max_reported_tokens_per_phase']:
        raise ValueError('reported token limit differs from frozen session')
    if manifest['phase'] != 'prepared' or manifest['record_kind'] != _kind:
        raise ValueError('driver requires a fresh prepared fixture session')
    if _kind == 'calibration' and any(manifest.get(key) is None for key in
            ('coordinator_sha256', 'trial_configuration_sha256', 'environment_sha256')):
        raise ValueError('calibration requires fully bound provenance')
    if manifest.get('coordinator_sha256') is not None:
        if coordinator is None or coordinator.get('sha256') != manifest['coordinator_sha256']:
            raise ValueError('session requires frozen coordinator receipt')
        if getattr(__loader__, 'receipt_sha256', None) != coordinator['sha256']:
            raise ValueError('session requires fresh verified coordinator imports')
    if manifest.get('trial_configuration_sha256') is not None:
        from .trial_configuration import validate
        if trial_configuration is None or trial_configuration.get('sha256') != manifest['trial_configuration_sha256']:
            raise ValueError('session requires its frozen trial configuration')
        validate(trial_configuration)
        if any(trial_configuration[key] != value for key, value in
               [('tools', tools), ('task_adapter', task_adapter), ('practice_adapter', practice_adapter), ('environment', environment)]):
            raise ValueError('session arguments differ from frozen trial configuration')
    if manifest.get('environment_sha256') is not None and (environment is None or
            environment.get('sha256') != manifest['environment_sha256']):
        raise ValueError('session requires its frozen environment receipt')
    if not all(isinstance(prompt, str) and prompt for prompt in (practice_prompt, task_prompt)):
        raise ValueError('separate practice and task prompts are required')
    if source_files(root / 'practice'):
        raise ValueError('driver requires an empty practice workspace')
    directory = root / 'driver'
    directory.mkdir(exist_ok=False)
    with locked(directory):
        try:
            if coordinator is not None:
                from . import coordinator_receipt
                write_json(directory / 'coordinator-before.json', coordinator_receipt.verify(coordinator, transport_identity=transport_identity))
            environment_checks = {'status': 'not-requested'}
            if environment is not None:
                # Persist first, then validate: failures retain the supplied evidence.
                write_json(directory / 'environment.json', environment)
                environment = read_json(directory / 'environment.json')
                required_tools = environment_receipt.session_tools(tools, task_adapter, practice_adapter)
                before = environment_receipt.verify(environment, require_system=True, required_tools=required_tools)
                write_json(directory / 'environment-before.json', before)
                environment_checks = {'status': 'before-verified', 'sha256': environment['sha256']}
            captured = snapshot(practice_source, directory / 'initial-practice')
            gateway = Gateway(root, tools, adapter=task_adapter, public_case=task_case)
            practice = PreparationGateway(gateway, practice_adapter, practice_case)
            config = {'version': _kind + '-session-driver-v1', 'session_sha256': digest(manifest),
                      'practice_source': captured, 'gateway': gateway.configuration(),
                      'practice_gateway': practice.configuration(), 'model': manifest['model'],
                      'transport': transport_identity, 'max_turns_per_phase': max_turns,
                      'max_output_tokens_per_response': max_output_tokens, 'max_reported_tokens_per_phase': max_reported_tokens,
                      'practice_prompt': practice_prompt, 'task_prompt': task_prompt,
                      'environment': environment_checks,
                      'trial_configuration_sha256': manifest.get('trial_configuration_sha256'),
                      'coordinator_sha256': manifest.get('coordinator_sha256')}
            write_json(directory / 'configuration.json', config)
            # Provision from the captured curriculum, not a mutable original.
            (root / 'practice').rmdir()
            snapshot(directory / 'initial-practice', root / 'practice')
            settings = dict(model=manifest['model'], transport_identity=transport_identity,
                            max_turns=max_turns, max_output_tokens=max_output_tokens, max_reported_tokens=max_reported_tokens)
            session.start_preparation(root)
            preparation = model_loop.run_preparation(practice, complete, prompt=practice_prompt, **settings)
            history = read_json(root / 'model-preparation/transcript.json')
            task = model_loop.run_task(gateway, complete, prompt=task_prompt, history=history, **settings)
            final = session.load(root)
            if environment is not None:
                if final['phase'] != 'sealed':
                    raise ValueError('environment post-check requires stopped participant clocks')
                after = environment_receipt.verify(environment, require_system=True, required_tools=required_tools)
                write_json(directory / 'environment-after.json', after)
                environment_checks = {'status': 'before-and-after-verified', 'sha256': environment['sha256'],
                                      'verification_seconds': before['capture_seconds'] + after['capture_seconds']}
            if coordinator is not None:
                write_json(directory / 'coordinator-after.json', coordinator_receipt.verify(coordinator, transport_identity=transport_identity))
            usage = {key: preparation['reported_usage'][key] + task['reported_usage'][key]
                     for key in ('input_tokens', 'output_tokens', 'total_tokens')}
            report = {'version': _kind + '-session-result-v1', 'record_kind': _kind,
                      'configuration_sha256': digest(config), 'session_sha256': digest(final),
                      'pair_id': final.get('pair_id', final['block']), 'language': final['language'],
                      'preparation': preparation, 'task': task, 'seal_reason': final['seal_reason'],
                      'preparation_seconds': final['preparation']['elapsed_seconds'],
                      'task_seconds': final['participant_seconds'], 'reported_usage': usage,
                      'usage_complete': preparation['usage_complete'] and task['usage_complete'],
                      'environment': environment_checks, 'comparative_claim': False}
            write_json(directory / 'result.json', report)
            return report
        except Exception as error:
            write_json(directory / 'interrupted.json', {'type': type(error).__name__, 'message': str(error),
                       'phase': session.load(root)['phase'], 'recovery': 'explicit investigation required'})
            raise
