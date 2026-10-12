#!/usr/bin/env python3
"""Deterministic overlapping-snapshot work fixture; no latency claims."""
from contextlib import ExitStack
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile


def profile(module_path, files=128, snapshots=8):
    """Count cold, unchanged and edited work using fixed overlapping scopes."""
    specification = importlib.util.spec_from_file_location('profile_snapshot', module_path)
    module = importlib.util.module_from_spec(specification)
    sys.modules[specification.name] = module
    specification.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix='snapshot-profile-') as scratch:
        root = Path(scratch)
        (root / 'common').mkdir()
        for index in range(files):
            (root / 'common' / f'{index:04d}').write_bytes(b'common fixture\n')
        for index in range(snapshots):
            directory = root / 'groups' / str(index)
            directory.mkdir(parents=True)
            (directory / 'input').write_bytes(b'unique fixture\n')
        with module.RetainedSession() as session, session.activate():
            with ExitStack() as stack:
                cold = [stack.enter_context(module.Snapshot(root, ['common/', f'groups/{index}/']))
                        for index in range(snapshots)]
                identities = [value.identity for value in cold]
                cold_work = session.statistics
            before = session.statistics
            with ExitStack() as stack:
                warm = [stack.enter_context(module.Snapshot(root, ['common/', f'groups/{index}/']))
                        for index in range(snapshots)]
                acquisition_work = {key: value - before[key] for key, value in session.statistics.items()}
                validation_before = session.statistics
                warm_valid = all(value.unchanged() for value in warm)
                validation_work = {key: value - validation_before[key]
                                   for key, value in session.statistics.items()}
                identity_equal = [value.identity for value in warm] == identities
                warm_work = {key: value - before[key] for key, value in session.statistics.items()}
                edited = root / 'common' / '0000'
                edited.write_bytes(b'changed bytes\n')
                edited.write_bytes(b'common fixture\n')
                before = session.statistics
                edited_valid = [value.unchanged() for value in warm]
                edited_work = {key: value - before[key] for key, value in session.statistics.items()}
    return {'schema': 1, 'module_sha256': hashlib.sha256(Path(module_path).read_bytes()).hexdigest(),
            'inventory_identity_sha256': hashlib.sha256(json.dumps(identities, sort_keys=True).encode()).hexdigest(),
            'files_per_shared_scope': files, 'snapshots': snapshots, 'fixture_root_components': len(root.parts), 'cold': cold_work,
            'warm': warm_work, 'warm_acquisition': acquisition_work,
            'warm_validation': validation_work, 'edited': edited_work, 'warm_valid': warm_valid,
            'warm_identity_equal': identity_equal, 'edited_valid': edited_valid,
            'timing': 'unqualified; deterministic work counts only'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--module', type=Path, default=Path(__file__).with_name('verification_snapshot.py'))
    arguments = parser.parse_args()
    print(json.dumps(profile(arguments.module), indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
