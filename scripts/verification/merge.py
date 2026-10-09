"""Construct and verify Git candidates without changing a branch or authorizing a merge."""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.PIPE).decode().strip()


def candidate(repo, base, changes):
    """Merge each immutable commit into a synthetic commit; Git detects textual conflicts."""
    base_commit = git(repo, 'rev-parse', base+'^{commit}')
    commits = [git(repo, 'rev-parse', change+'^{commit}') for change in changes]
    current = base_commit
    for commit in commits:
        tree = git(repo, 'merge-tree', '--write-tree', current, commit).splitlines()[0]
        current = git(repo, '-c', 'user.name=Verification', '-c', 'user.email=verification@localhost',
                      'commit-tree', tree, '-p', current, '-p', commit, '-m', 'Unpublished verification candidate')
    return {'base': base_commit, 'tree': git(repo, 'rev-parse', current+'^{tree}'),
            'commit': current, 'changes': commits}


@contextlib.contextmanager
def checkout(repo, commit):
    with tempfile.TemporaryDirectory(prefix='selka-merge-') as temporary:
        root = Path(temporary) / 'candidate'
        git(repo, 'worktree', 'add', '--detach', str(root), commit)
        try:
            yield root
        finally:
            git(repo, 'worktree', 'remove', '--force', str(root))


def verify_candidate(repo, base, changes, manifest, *, cache_dir, executor=None, verifier=None):
    from .core import run_manifest
    verifier = verifier or run_manifest
    identity = candidate(repo, base, changes)
    relative = Path(manifest)
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('manifest must be relative to candidate root')
    # Core v2 snapshots intentionally exclude Git metadata: Git-sensitive gates
    # remain separate required production gates, never implicitly certified here.
    with checkout(repo, identity['commit']) as root:
        report = verifier(root / relative, cache_dir=Path(cache_dir), mode='full', executor=executor)
        if not report.get('full_manifest_passed'):
            raise ValueError('candidate verification failed or lacks complete required evidence')
        if git(root, 'status', '--porcelain', '--untracked-files=all'):
            raise ValueError('verification mutated candidate source')
        certificate = {'version': 1, **identity, 'target': base, 'manifest': relative.as_posix(), 'change_refs': list(changes), 'report': report}
        certificate['digest'] = digest(certificate)
        validate(repo, certificate)
        return certificate


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def validate(repo, certificate, *, expected_tree=None):
    document = dict(certificate)
    checksum = document.pop('digest', None)
    if checksum != digest(document) or document.get('version') != 1:
        raise ValueError('invalid merge certificate')
    if git(repo, 'rev-parse', document['target']+'^{commit}') != document['base']:
        raise ValueError('target base moved; verify a new candidate')
    references = document.get('change_refs', [])
    if len(references) != len(document['changes']) or any(git(repo, 'rev-parse', ref+'^{commit}') != commit for ref, commit in zip(references, document['changes'])):
        raise ValueError('participating change moved; verify a new candidate')
    rebuilt = candidate(repo, document['base'], document['changes'])
    if rebuilt['tree'] != document['tree'] or (expected_tree is not None and expected_tree != document['tree']):
        raise ValueError('candidate tree changed')
    from .core import inventory
    report = document['report']
    if not report.get('full_manifest_passed') or report.get('mode') != 'full':
        raise ValueError('certificate lacks full verification')
    relative = Path(document['manifest'])
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('invalid certificate manifest path')
    with checkout(repo, rebuilt['commit']) as root:
        data = json.loads((root / relative).read_text())
        if data.get('version') != 2:
            raise ValueError('certificates require version 2 declared input inventories')
        current = inventory((root / relative).parent, data)
    if current != report.get('inventory') or report.get('policy') != data['policy']:
        raise ValueError('verification inputs, tools, environment or policy changed')
    rows = report.get('steps', [])
    if len(rows) != len(current) or {row.get('id') for row in rows} != set(current) or not rows:
        raise ValueError('certificate missing required job evidence')
    for row in rows:
        job = current[row['id']]
        if (not job['complete'] or not row.get('passed') or
                row.get('status') not in ('executed', 'cached') or row.get('job_key') != digest(job)):
            raise ValueError('certificate has incomplete or incompatible job evidence')
    # Recheck after reading external identities: a concurrent target update fails closed.
    if git(repo, 'rev-parse', document['target']+'^{commit}') != document['base']:
        raise ValueError('target base moved; verify a new candidate')
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path('.'))
    parser.add_argument('--base')
    parser.add_argument('--validate', type=Path, help='validate an existing certificate without executing checks')
    parser.add_argument('--expected-tree')
    parser.add_argument('--change', action='append', default=[])
    parser.add_argument('--manifest')
    parser.add_argument('--cache-dir', type=Path)
    parser.add_argument('--output', type=Path)
    from .scheduler import add_arguments, executor_from_args
    add_arguments(parser)
    args = parser.parse_args()
    if args.validate:
        validate(args.repo.resolve(), json.loads(args.validate.read_text()), expected_tree=args.expected_tree)
        print('certificate is current; no merge or push authorized')
        return
    if not all((args.base, args.manifest, args.cache_dir, args.output)):
        parser.error('verification requires --base, --manifest, --cache-dir and --output')
    certificate = verify_candidate(args.repo.resolve(), args.base, args.change, args.manifest,
                                   cache_dir=args.cache_dir.resolve(), executor=executor_from_args(args))
    args.output.write_text(json.dumps(certificate, indent=2)+'\n')


if __name__ == '__main__':
    main()
