"""Grade registered fixture trios with cohort-derived tools in the verified coordinator."""
from pathlib import Path
from . import cohort, coordinator_receipt, session, verified_grading
from .storage import digest, locked, read_json, write_json


def run_fixture(cohort_directory, roots, directory, *, transport_identity):
    return _run(cohort_directory, roots, directory, transport_identity=transport_identity, kind='fixture')


def run_calibration(cohort_directory, roots, directory, *, transport_identity):
    return _run(cohort_directory, roots, directory, transport_identity=transport_identity, kind='calibration')


def _run(cohort_directory, roots, directory, *, transport_identity, kind):
    cohort_directory = Path(cohort_directory)
    manifest = cohort.load(cohort_directory)
    if manifest['version'] != 'application-cohort-v5' or manifest['record_kind'] != kind:
        raise ValueError(f'scheduled grading requires a v5 {kind} cohort')
    coordinator = manifest['coordinator']
    if getattr(__loader__, 'receipt_sha256', None) != coordinator['sha256']:
        raise ValueError('scheduled grading requires fresh verified coordinator imports')
    coordinator_receipt.verify(coordinator, transport_identity=transport_identity)
    roots = [Path(root).resolve(strict=True) for root in roots]
    participants = session.matched_trio(roots)
    block, arm = participants[0]['block'], participants[0]['arm']
    configurations = {}
    for root, participant in zip(roots, participants, strict=True):
        if participant['cohort'] != manifest['sha256'] or participant['coordinator_sha256'] != coordinator['sha256']:
            raise ValueError('graded session does not match frozen cohort')
        rows = [row for row in manifest['schedule'] if row['session_id'] == participant['participant']]
        if len(rows) != 1 or any(rows[0][key] != participant[key] for key in ('block', 'language', 'pair_id')):
            raise ValueError('graded session is not the scheduled attempt')
        registry = read_json(cohort_directory / (kind + '-reservations') / arm / participant['participant'] / 'reservation.json')
        if root != Path(registry['directory']).resolve(strict=True) / 'session':
            raise ValueError('grading requires the registered session directory')
        envelope = root.parent
        if (registry != dict(read_json(envelope / 'reservation.json'), directory=str(envelope)) or
                registry['status'] != 'prepared' or registry['cohort_sha256'] != manifest['sha256'] or
                registry['row'] != rows[0] or registry['source'] != participant['baseline']):
            raise ValueError('graded session reservation mismatch')
        configuration = manifest['configurations'][f"{arm}/{block}/{participant['language']}"]
        if (participant['trial_configuration_sha256'] != configuration['sha256'] or
                participant['environment_sha256'] != configuration['environment']['sha256']):
            raise ValueError('graded session configuration mismatch')
        configurations[participant['language']] = configuration
    derived = verified_grading.from_configurations(configurations)
    directory = Path(directory)
    directory.mkdir(exist_ok=False)
    with locked(directory):
        write_json(directory / 'configuration.json', {'cohort_sha256': manifest['sha256'],
                   'coordinator_sha256': coordinator['sha256'], 'pair_id': participants[0]['pair_id'],
                   'sessions': {item['language']: digest(item) for item in participants}, 'derived': derived})
        try:
            write_json(directory / 'coordinator-before.json', coordinator_receipt.verify(coordinator, transport_identity=transport_identity))
            grader = verified_grading.grade_fixture if kind == 'fixture' else verified_grading.grade_calibration
            result = grader(cohort_directory / 'tasks' / block, roots,
                derived['adapters'], directory / 'verified', environment=derived['environment'])
            if cohort.load(cohort_directory) != manifest:
                raise ValueError('cohort changed during grading')
            write_json(directory / 'coordinator-after.json', coordinator_receipt.verify(coordinator, transport_identity=transport_identity))
            report = {'version': 'scheduled-' + kind + '-grading-v1', 'record_kind': kind,
                      'cohort_sha256': manifest['sha256'], 'coordinator_sha256': coordinator['sha256'],
                      'verified_grading_sha256': digest(result), 'grading': result, 'comparative_claim': False}
            write_json(directory / 'result.json', report)
            return report
        except Exception as error:
            write_json(directory / 'interrupted.json', {'type': type(error).__name__, 'message': str(error)})
            raise
