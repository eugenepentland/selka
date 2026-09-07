"""Private pilot authoring packs with an explicit, bounded public projection."""
from pathlib import Path
from . import pilot_cases
from .inputs import decode_case
from .storage import digest, inventory, path_identity, read_json, snapshot, source_files, verify_snapshot, write_json

ROOT = Path(__file__).resolve().parent
ARTIFACTS = ('pilot_cases.py', 'planner_pilot_oracle.py', 'eda_pilot_oracle.py',
             'planner_oracle.py', 'eda_oracle.py', 'oracle_transport.py', 'task_pack.py',
             'inputs.py', 'storage.py')


def receipt(directory):
    files = inventory(source_files(directory))
    return {'files': files, 'sha256': digest(files)}


def create(directory, *, task, hidden_seed):
    if task not in pilot_cases.TASKS or not isinstance(hidden_seed, str) or not hidden_seed.strip():
        raise ValueError('known task and private seed required')
    identities = {name: path_identity(ROOT / name) for name in ARTIFACTS}
    brief = (ROOT / 'pilot_tasks' / (task + '.md')).read_bytes()
    public = pilot_cases.build(task, seed='public-pilot-checks-v1', public=True)
    hidden = pilot_cases.build(task, seed=hidden_seed)
    directory = Path(directory)
    directory.mkdir(exist_ok=False)
    (directory / 'public').mkdir()
    (directory / 'hidden').mkdir()
    (directory / 'public' / 'brief.md').write_bytes(brief)
    write_json(directory / 'public' / 'cases.json', public)
    write_json(directory / 'hidden' / 'cases.json', hidden)
    if identities != {name: path_identity(ROOT / name) for name in ARTIFACTS}:
        raise ValueError('authoring code changed while creating pack')
    manifest = {'version': 'pilot-task-pack-v1', 'task': task,
                'status': 'draft-unreviewed', 'scored_launch_enabled': False,
                'hidden_seed': hidden_seed, 'authoring_code': identities,
                'public': receipt(directory / 'public'), 'hidden': receipt(directory / 'hidden')}
    write_json(directory / 'pack.json', dict(manifest, sha256=digest(manifest)))
    return load(directory)


def load(directory):
    directory = Path(directory)
    manifest = read_json(directory / 'pack.json')
    fields = {'version', 'task', 'status', 'scored_launch_enabled', 'hidden_seed',
              'authoring_code', 'public', 'hidden', 'sha256'}
    if not isinstance(manifest, dict) or set(manifest) != fields:
        raise ValueError('invalid task pack fields')
    body = {key: value for key, value in manifest.items() if key != 'sha256'}
    if (manifest['version'] != 'pilot-task-pack-v1' or digest(body) != manifest['sha256'] or
            manifest['task'] not in pilot_cases.TASKS or manifest['status'] != 'draft-unreviewed' or
            manifest['scored_launch_enabled'] is not False):
        raise ValueError('invalid or changed draft task pack')
    if (not isinstance(manifest['hidden_seed'], str) or not manifest['hidden_seed'].strip() or
            not isinstance(manifest['authoring_code'], dict) or set(manifest['authoring_code']) != set(ARTIFACTS)):
        raise ValueError('missing task pack provenance')
    for category, expected_files in [('public', {'brief.md', 'cases.json'}), ('hidden', {'cases.json'})]:
        if set(manifest[category]['files']) != expected_files:
            raise ValueError('invalid task pack file inventory')
        verify_snapshot(directory / category, manifest[category])
        cases = read_json(directory / category / 'cases.json')
        if not isinstance(cases, list) or not cases:
            raise ValueError('task pack requires cases')
        names = set()
        for item in cases:
            if (not isinstance(item, dict) or set(item) != {'name', 'case'} or
                    not isinstance(item['name'], str) or not item['name'] or item['name'] in names):
                raise ValueError('invalid or duplicate task case')
            names.add(item['name'])
            decode_case(item['case'])
    return manifest


def provision_public(directory, destination):
    manifest = load(directory)
    captured = snapshot(Path(directory) / 'public', destination)
    if captured != manifest['public']:
        raise ValueError('public pack changed during provisioning')
    return captured


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    create_parser = commands.add_parser('create')
    create_parser.add_argument('--task', choices=pilot_cases.TASKS, required=True)
    create_parser.add_argument('--seed-file', type=Path, required=True)
    create_parser.add_argument('--directory', type=Path, required=True)
    verify_parser = commands.add_parser('verify')
    verify_parser.add_argument('--directory', type=Path, required=True)
    public_parser = commands.add_parser('provision-public')
    public_parser.add_argument('--directory', type=Path, required=True)
    public_parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    if args.command == 'create':
        manifest = create(args.directory, task=args.task, hidden_seed=args.seed_file.read_text().strip())
    else:
        manifest = load(args.directory)
        if args.command == 'provision-public':
            provision_public(args.directory, args.destination)
    # Never print private seeds, answers or source paths to participant logs.
    print(manifest['task'], manifest['status'], manifest['sha256'])


if __name__ == '__main__':
    main()
