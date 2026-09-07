"""Provision scheduled fixture sessions from frozen cohorts; never launch agents."""
from pathlib import Path
import tempfile
from . import cohort, seeded_regressions, session, task_pack
from .storage import digest, snapshot, write_json


def prepare_fixture(cohort_directory, session_id, directory, *, arm='main'):
    return _prepare(cohort_directory, session_id, directory, arm=arm, kind='fixture')


def prepare_calibration(cohort_directory, session_id, directory, *, arm='main'):
    return _prepare(cohort_directory, session_id, directory, arm=arm, kind='calibration')


def _prepare(cohort_directory, session_id, directory, *, arm, kind):
    if arm not in ('main', 'language-focused'):
        raise ValueError('unknown study arm')
    manifest = cohort.load(cohort_directory)
    if manifest['record_kind'] != kind:
        raise ValueError('agent cohort launch prerequisites are not implemented here')
    rows = [row for row in manifest['schedule'] if row['session_id'] == session_id]
    if len(rows) != 1:
        raise ValueError('session is not in the frozen schedule')
    row = rows[0]
    cohort_directory = Path(cohort_directory)
    baseline_key = f"{row['application']}/{row['tier']}/{row['language']}"
    baseline = cohort_directory / 'baselines' / baseline_key
    pack = cohort_directory / 'tasks' / row['block']
    pack_manifest = task_pack.load(pack)
    if pack_manifest['task'] != row['block']:
        raise ValueError('scheduled task and pack identity differ')
    directory = Path(directory)
    if directory.exists():
        raise FileExistsError(directory)
    # Atomic per-assignment reservation prevents duplicate provisioning through
    # different output paths, without serializing independent scheduled sessions.
    reservations = cohort_directory / (kind + '-reservations') / arm
    reservations.mkdir(parents=True, exist_ok=True)
    reservation_directory = reservations / session_id
    reservation_directory.mkdir(exist_ok=False)
    directory.mkdir(exist_ok=False)
    # The envelope is coordinator-owned. Only session/work (or session/practice)
    # is mounted by the gateway, never this envelope and its mutation receipts.
    reservation = {'version': 'cohort-session-reservation-v1', 'cohort_sha256': manifest['sha256'],
                   'row': row, 'arm': arm, 'status': 'provisioning', 'record_kind': kind}
    write_json(directory / 'reservation.json', reservation)
    write_json(reservation_directory / 'reservation.json',
               dict(reservation, directory=str(directory.resolve())))
    with tempfile.TemporaryDirectory(prefix='cohort-provision-') as temporary:
        source = Path(temporary) / 'source'
        mutation = None
        if (row['block'], row['language']) in seeded_regressions.RECIPES:
            mutation = seeded_regressions.create(baseline, source,
                manifest['receipts']['baselines'][baseline_key], task=row['block'], language=row['language'])
        else:
            snapshot(baseline, source)
        if (source / '.trial-public').exists():
            raise ValueError('reserved public task directory already exists in baseline')
        public = task_pack.provision_public(pack, source / '.trial-public')
        protected = ['.trial-public/' + name for name in public['files']]
        if manifest['version'] in ('application-cohort-v2', 'application-cohort-v3', 'application-cohort-v4', 'application-cohort-v5'):
            practice = cohort_directory / 'practice' / row['language']
            retained = source / '.trial-practice-guide'
            retained.mkdir(exist_ok=False)
            for name, origin in [('GUIDE.md', practice / 'starter/GUIDE.md'), ('CONTRACT.md', practice / 'contract.md')]:
                (retained / name).write_bytes(origin.read_bytes())
                protected.append('.trial-practice-guide/' + name)
        if row['language'] == 'zig' and arm == 'main':
            protected.extend(['guardian.toml', 'main.zig'])
        budgets = manifest['budgets']
        prepared = session.prepare(directory / 'session', source, language=row['language'],
            block=row['block'], cohort=manifest['sha256'], participant=session_id,
            model=manifest['model_settings']['model'], arm=arm, kind=kind,
            preparation_seconds=budgets['preparation_seconds'], task_seconds=budgets['task_seconds'],
            max_submissions=budgets['max_submissions'], protected=protected, pair_id=row['pair_id'],
            environment_sha256=(manifest['environments'][f"{arm}/{row['block']}/{row['language']}"]['sha256']
                                if manifest['version'] in ('application-cohort-v3', 'application-cohort-v4', 'application-cohort-v5') else None),
            trial_configuration_sha256=(manifest['configurations'][f"{arm}/{row['block']}/{row['language']}"]['sha256']
                                        if manifest['version'] in ('application-cohort-v4', 'application-cohort-v5') else None),
            coordinator_sha256=manifest['coordinator']['sha256'] if manifest['version'] == 'application-cohort-v5' else None,
            max_reported_tokens_per_phase=manifest['model_settings'].get('max_reported_tokens_per_phase'))
    if cohort.load(cohort_directory) != manifest:
        raise ValueError('cohort changed during session provisioning')
    result = dict(reservation, status='prepared', session_sha256=digest(prepared),
                  source=prepared['baseline'], mutation=mutation, public=public,
                  pack_sha256=pack_manifest['sha256'], model_settings=manifest['model_settings'],
                  model_budgets={key: budgets[key] for key in ('max_output_tokens', 'max_turns')},
                  comparative_claim=False)
    write_json(directory / 'reservation.json', result)
    write_json(reservation_directory / 'reservation.json',
               dict(result, directory=str(directory.resolve())))
    return result


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cohort', type=Path, required=True)
    parser.add_argument('--session-id', required=True)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--arm', choices=('main', 'language-focused'), default='main')
    parser.add_argument('--kind', choices=('fixture', 'calibration'), default='fixture')
    args = parser.parse_args()
    prepare = prepare_fixture if args.kind == 'fixture' else prepare_calibration
    result = prepare(args.cohort, args.session_id, args.directory, arm=args.arm)
    print(result['row']['session_id'], result['status'], result['source']['sha256'])


if __name__ == '__main__':
    main()
