"""Bind fixture session execution to its immutable cohort and private reservation."""
from pathlib import Path
from . import cohort, session, session_driver, task_pack
from .storage import digest, read_json


def run_fixture(cohort_directory, envelope, complete, **settings):
    return _run(cohort_directory, envelope, complete, _kind='fixture', **settings)


def run_calibration(cohort_directory, envelope, complete, **settings):
    return _run(cohort_directory, envelope, complete, _kind='calibration', **settings)


def _run(cohort_directory, envelope, complete, *, _kind, tools=None, task_adapter=None,
                practice_adapter=None, transport_identity, practice_source=None, practice_case=None, practice_prompt=None):
    cohort_directory, envelope = Path(cohort_directory), Path(envelope)
    manifest = cohort.load(cohort_directory)
    reservation = read_json(envelope / 'reservation.json')
    if manifest['record_kind'] != _kind or reservation.get('status') != 'prepared':
        raise ValueError('scheduled driver requires prepared fixture reservation')
    if reservation.get('cohort_sha256') != manifest['sha256']:
        raise ValueError('reservation cohort identity mismatch')
    row = reservation.get('row')
    if row not in manifest['schedule'] or reservation.get('arm') not in ('main', 'language-focused'):
        raise ValueError('reservation is not a scheduled condition')
    registry = cohort_directory / (_kind + '-reservations') / reservation['arm'] / row['session_id'] / 'reservation.json'
    if read_json(registry) != dict(reservation, directory=str(envelope.resolve())):
        raise ValueError('reservation registry or output location changed')
    prepared = session.load(envelope / 'session')
    if (digest(prepared) != reservation['session_sha256'] or prepared['phase'] != 'prepared' or
            prepared['baseline'] != reservation['source'] or prepared['pair_id'] != row['pair_id'] or
            prepared['language'] != row['language'] or prepared['participant'] != row['session_id']):
        raise ValueError('prepared session no longer matches reservation')
    settings = manifest['model_settings']
    if set(settings) not in ({'model'}, {'model', 'max_reported_tokens_per_phase'}):
        raise ValueError('driver does not yet implement additional frozen model settings')
    budgets = manifest['budgets']
    if (prepared['model'] != settings['model'] or reservation['model_settings'] != settings or
            prepared['budgets'] != {key: budgets[key] for key in ('preparation_seconds', 'task_seconds', 'max_submissions')} or
            reservation['model_budgets'] != {key: budgets[key] for key in ('max_turns', 'max_output_tokens')}):
        raise ValueError('scheduled model or budgets changed')
    pack = cohort_directory / 'tasks' / row['block']
    pack_manifest = task_pack.load(pack)
    if pack_manifest['sha256'] != reservation['pack_sha256'] or pack_manifest['public'] != reservation['public']:
        raise ValueError('scheduled public pack changed')
    coordinator = manifest.get('coordinator')
    if coordinator is not None and coordinator['transport_identity'] != transport_identity:
        raise ValueError('cohort transport identity mismatch')
    configuration = None
    if manifest['version'] in ('application-cohort-v4', 'application-cohort-v5'):
        if any(value is not None for value in (tools, task_adapter, practice_adapter)):
            raise ValueError('cohort-bound configuration cannot be overridden')
        configuration = manifest['configurations'][f"{reservation['arm']}/{row['block']}/{row['language']}"]
        if (_kind == 'calibration' and row['language'] == 'my' and reservation['arm'] == 'main' and
                configuration['version'] != 'application-trial-configuration-v2'):
            raise ValueError('main my calibration requires compiler/navigation tooling configuration v2')
        tools, task_adapter, practice_adapter = (configuration[key] for key in ('tools', 'task_adapter', 'practice_adapter'))
    if row['language'] == 'zig' and reservation['arm'] == 'main':
        from .guardian_adapter import require
        require(task_adapter)
    if manifest['version'] in ('application-cohort-v2', 'application-cohort-v3', 'application-cohort-v4', 'application-cohort-v5'):
        if any(value is not None for value in (practice_source, practice_case, practice_prompt)):
            raise ValueError('cohort-bound practice cannot be overridden')
        practice = cohort_directory / 'practice' / row['language']
        practice_source = practice / 'starter'
        practice_case = read_json(practice / 'cases.json')
        practice_prompt = (practice / 'contract.md').read_text() + '\n' + (practice / 'starter/GUIDE.md').read_text()
    elif any(value is None for value in (practice_source, practice_case, practice_prompt)):
        raise ValueError('legacy fixture requires explicit practice inputs')
    cases = read_json(pack / 'public/cases.json')
    prompt = (pack / 'public/brief.md').read_text()
    prompt += '\nEdit the project in /work. Use check to verify all public cases, then finish.\n'
    if manifest['version'] in ('application-cohort-v2', 'application-cohort-v3', 'application-cohort-v4', 'application-cohort-v5'):
        prompt += 'Your original practice guide and contract remain available under .trial-practice-guide/.\n'
    environment = None
    if manifest['version'] in ('application-cohort-v3', 'application-cohort-v4', 'application-cohort-v5'):
        environment = manifest['environments'][f"{reservation['arm']}/{row['block']}/{row['language']}"]
    driver = session_driver.run_fixture if _kind == 'fixture' else session_driver.run_calibration
    return driver(envelope / 'session', complete, tools=tools,
        task_adapter=task_adapter, task_case=cases, practice_source=practice_source,
        practice_adapter=practice_adapter, practice_case=practice_case, practice_prompt=practice_prompt,
        task_prompt=prompt, transport_identity=transport_identity,
        coordinator=coordinator, environment=environment, trial_configuration=configuration, max_turns=budgets['max_turns'], max_output_tokens=budgets['max_output_tokens'], max_reported_tokens=settings.get('max_reported_tokens_per_phase'))
