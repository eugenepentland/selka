"""Capture an onboarding starter and its public contract without coordinator solutions."""
from pathlib import Path
from . import practice_cases, public_verification
from .storage import digest, inventory, read_json, snapshot, verify_snapshot, write_json

ROOT = Path(__file__).resolve().parent


def create(directory, *, language):
    if language not in ('my', 'python', 'zig'):
        raise ValueError('unknown practice language')
    directory = Path(directory)
    directory.mkdir(exist_ok=False)
    starter = snapshot(ROOT / 'practice' / language / 'starter', directory / 'starter')
    if 'GUIDE.md' not in starter['files']:
        raise ValueError('practice starter requires its guide')
    checks = practice_cases.cases()
    public_verification.validate(checks)
    write_json(directory / 'cases.json', checks)
    (directory / 'contract.md').write_bytes((ROOT / 'contracts/practice-v1.md').read_bytes())
    public = inventory({name: (directory / name).read_bytes() for name in ('cases.json', 'contract.md')})
    manifest = {'version': 'practice-pack-v1', 'language': language, 'status': 'draft-unreviewed',
                'starter': starter, 'public_files': public, 'scored_launch_enabled': False}
    write_json(directory / 'pack.json', dict(manifest, sha256=digest(manifest)))
    return load(directory)


def load(directory):
    directory = Path(directory)
    manifest = read_json(directory / 'pack.json')
    fields = {'version', 'language', 'status', 'starter', 'public_files', 'scored_launch_enabled', 'sha256'}
    if not isinstance(manifest, dict) or set(manifest) != fields:
        raise ValueError('invalid practice manifest')
    body = {key: value for key, value in manifest.items() if key != 'sha256'}
    if (digest(body) != manifest['sha256'] or manifest['version'] != 'practice-pack-v1' or
            manifest['language'] not in ('my', 'python', 'zig') or manifest['status'] != 'draft-unreviewed' or
            manifest['scored_launch_enabled'] is not False):
        raise ValueError('invalid or changed draft practice pack')
    verify_snapshot(directory / 'starter', manifest['starter'])
    files = inventory({name: (directory / name).read_bytes() for name in ('cases.json', 'contract.md')})
    if files != manifest['public_files']:
        raise ValueError('practice public files changed')
    public_verification.validate(read_json(directory / 'cases.json'))
    return manifest
