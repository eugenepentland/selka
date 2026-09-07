"""Retain a reviewed stdlib parity decision bound to concrete trial inputs.

This checks declared coverage and input identity, not semantic equivalence or
reviewer authenticity. It never starts a participant or authorizes scored launch.
"""
from pathlib import Path
from .storage import digest, path_identity, read_json
from .environment_receipt import tree_identity


def validate_matrix(matrix):
    if not isinstance(matrix, dict) or matrix.get('version') != 'stdlib-parity-matrix-v1':
        raise ValueError('invalid stdlib parity matrix')
    if (matrix.get('status') != 'ready' or
            matrix.get('policy') != 'stdlib-parity-before-application-timing-v1'):
        raise ValueError('ready matrix under the current parity policy required')
    versions = matrix.get('comparator_versions')
    if (not isinstance(versions, dict) or set(versions) != {'python', 'zig'} or
            any(not isinstance(value, str) or not value.strip() for value in versions.values())):
        raise ValueError('explicit comparator versions required')
    applications = matrix.get('applications')
    if not isinstance(applications, list) or not applications or len(set(applications)) != len(applications):
        raise ValueError('distinct applications required')
    if any(app not in ('eda', 'planner') for app in applications):
        raise ValueError('unknown parity application')
    review = matrix.get('review', {})
    if not all(isinstance(review.get(key), str) and review[key].strip()
               for key in ('reviewer', 'completed_at')):
        raise ValueError('completed named readiness review required')
    rows = matrix.get('capabilities')
    if not isinstance(rows, list) or not rows:
        raise ValueError('capability inventory required')
    seen, covered, evidence = set(), set(), set()
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get('id'), str) or not row['id']:
            raise ValueError('capability identity required')
        if row['id'] in seen:
            raise ValueError('duplicate capability')
        seen.add(row['id'])
        if row.get('status') != 'ready':
            raise ValueError('unresolved required capability: ' + row['id'])
        if (not isinstance(row.get('applications'), list) or not row['applications'] or
                any(app not in applications for app in row['applications'])):
            raise ValueError('capability application coverage mismatch')
        covered.update(row['applications'])
        for key in ('required_behavior', 'my_api', 'notes'):
            if not isinstance(row.get(key), str) or not row[key].strip():
                raise ValueError('capability contract missing: ' + row['id'])
        if not isinstance(row.get('comparators'), dict) or set(row['comparators']) != {'python', 'zig'}:
            raise ValueError('both comparator mappings required')
        if any(not isinstance(value, str) or not value.strip() for value in row['comparators'].values()):
            raise ValueError('comparator description missing')
        if (not isinstance(row.get('evidence'), list) or not row['evidence'] or
                any(not isinstance(item, str) or not item for item in row['evidence'])):
            raise ValueError('capability acceptance evidence required')
        evidence.update(row['evidence'])
    if covered != set(applications):
        raise ValueError('incomplete application coverage')
    return evidence


def required_inputs(matrix):
    """Require every comparator and baseline, not just evidence selected by a caller."""
    return ({'compiler', 'byte_io', 'python', 'python_stdlib', 'zig', 'stdlib'} |
            {f'baseline:{app}:{language}' for app in matrix['applications']
             for language in ('my', 'python', 'zig')} |
            {f'contract:{app}' for app in matrix['applications']})


def input_identity(name, path):
    # Runtime trees legitimately contain symlinks. Reuse the environment scanner,
    # which records link targets and all in-tree content; full trial environment
    # receipts also cover mounted runtime dependencies outside these subtrees.
    if name in ('python_stdlib', 'zig'):
        return tree_identity(path)
    return path_identity(path)


def capture(matrix_path, *, inputs, output):
    """Bind reviewed coverage to supplied tools, source trees and evidence files."""
    matrix_path, output = Path(matrix_path).resolve(strict=True), Path(output)
    if output.exists():
        raise FileExistsError(output)
    matrix = read_json(matrix_path)
    evidence = validate_matrix(matrix)
    if not isinstance(inputs, dict) or not inputs or 'matrix' in inputs:
        raise ValueError('named trial inputs required; matrix is reserved')
    if not (evidence | required_inputs(matrix)).issubset(inputs):
        raise ValueError('matrix evidence and complete trial inventory must be supplied as named inputs')
    identities = {name: input_identity(name, path) for name, path in sorted(inputs.items())}
    identities['matrix'] = path_identity(matrix_path)
    body = {'version': 'stdlib-parity-readiness-v1', 'inputs': identities,
            'review_scope': 'declared capability coverage and pinned inputs; not independent proof or launch authorization',
            'scored_launch_authorized': False}
    receipt = dict(body, sha256=digest(body))
    verify(receipt)
    output.parent.mkdir(parents=True, exist_ok=True)
    # Publish exclusively: a prior receipt must never be silently replaced.
    with output.open('x') as stream:
        import json
        json.dump(receipt, stream, indent=2, sort_keys=True)
        stream.write('\n')
    return receipt


def verify(receipt):
    if not isinstance(receipt, dict) or set(receipt) != {'version', 'inputs', 'review_scope', 'scored_launch_authorized', 'sha256'}:
        raise ValueError('invalid readiness receipt fields')
    if (receipt['version'] != 'stdlib-parity-readiness-v1' or receipt['scored_launch_authorized'] is not False or
            digest({key: value for key, value in receipt.items() if key != 'sha256'}) != receipt['sha256']):
        raise ValueError('readiness receipt changed')
    identities = receipt['inputs']
    if not isinstance(identities, dict) or 'matrix' not in identities:
        raise ValueError('readiness matrix identity missing')
    for name, identity in identities.items():
        if not isinstance(identity, dict) or not isinstance(identity.get('path'), str):
            raise ValueError('invalid readiness input: ' + str(name))
        if input_identity(name, identity['path']) != identity:
            raise ValueError('readiness input changed: ' + name)
    matrix = read_json(identities['matrix']['path'])
    evidence = validate_matrix(matrix)
    if not (evidence | required_inputs(matrix)).issubset(identities):
        raise ValueError('readiness evidence inventory incomplete')
    return {'status': 'verified', 'sha256': receipt['sha256'], 'scored_launch_authorized': False}


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', type=Path, required=True)
    args = parser.parse_args()
    print(verify(read_json(args.verify)))


if __name__ == '__main__':
    main()
