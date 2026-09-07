"""Append-only human failure reviews; never alters session outcomes or retries."""
import hashlib
import os
from pathlib import Path
import stat
import time
from .storage import digest, locked, read_json, write_json

CATEGORIES = ('participant-outcome', 'transport-interruption', 'harness-interruption', 'environment-invalid', 'unknown')
POLICY = Path(__file__).with_name('recovery-policy.md')


def file_receipt(path):
    path = Path(path).absolute()
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if not stat.S_ISREG(before.st_mode) or before.st_size > 16 * 1024**2:
            raise ValueError('review evidence must be a bounded regular file')
        hasher, size = hashlib.sha256(), 0
        while chunk := os.read(fd, 65536):
            size += len(chunk)
            if size > 16 * 1024**2:
                raise ValueError('review evidence exceeded byte limit')
            hasher.update(chunk)
        after = os.fstat(fd)
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (after.st_size, after.st_mtime_ns, after.st_ctime_ns):
            raise ValueError('review evidence changed while reading')
        return {'path': str(path), 'bytes': size, 'sha256': hasher.hexdigest()}
    finally:
        os.close(fd)


def read_records(directory):
    paths = sorted(Path(directory).glob('*.json'))
    if len(paths) > 10000:
        raise ValueError('review record limit exceeded')
    records, previous = [], None
    for index, path in enumerate(paths):
        if path.name != f'{index:06}.json':
            raise ValueError('review sequence is incomplete')
        file_receipt(path)
        record = read_json(path)
        body = {key: value for key, value in record.items() if key != 'sha256'}
        if (record.get('version') != 'attempt-review-v1' or record.get('sequence') != index or
                record.get('previous') != previous or record.get('sha256') != digest(body)):
            raise ValueError('review chain changed')
        records.append(record)
        previous = record['sha256']
    return records


def record(session_root, directory, *, category, reviewer, reason, evidence_paths):
    if category not in CATEGORIES:
        raise ValueError('unknown review category')
    if any(not isinstance(value, str) or not value.strip() or len(value) > limit
           for value, limit in ((reviewer, 200), (reason, 4000))):
        raise ValueError('bounded reviewer and evidence-based reason required')
    evidence_paths = list(evidence_paths)
    if not 1 <= len(evidence_paths) <= 32:
        raise ValueError('provide one to 32 evidence files')
    root = Path(session_root).resolve(strict=True)
    directory = Path(directory).absolute()
    if directory.resolve().is_relative_to(root):
        raise ValueError('review records must stay outside the participant session')
    # Do not validate current baseline contents here: drift may be the subject.
    state_file = root / 'session.json'
    state_receipt = file_receipt(state_file)
    state = read_json(state_file)
    if (state.get('version') != 'application-session-v2' or
            any(not isinstance(state.get(key), str) or not state[key]
                for key in ('participant', 'cohort', 'record_kind', 'phase'))):
        raise ValueError('review requires a recorded session identity')
    evidence = [file_receipt(path) for path in evidence_paths]
    if len({item['path'] for item in evidence}) != len(evidence):
        raise ValueError('duplicate review evidence')
    policy = file_receipt(POLICY)
    if file_receipt(state_file) != state_receipt:
        raise ValueError('session changed during review capture')
    directory.mkdir(parents=True, exist_ok=True)
    with locked(directory):
        records = read_records(directory)
        if len(records) >= 10000:
            raise ValueError('review record limit exceeded')
        body = {'version': 'attempt-review-v1', 'sequence': len(records),
                'previous': records[-1]['sha256'] if records else None, 'at_utc_ns': time.time_ns(),
                'session_root': str(root), 'session_id': state['participant'], 'cohort': state['cohort'],
                'record_kind': state['record_kind'], 'phase': state['phase'],
                'session_receipt': state_receipt, 'category': category, 'reviewer': reviewer,
                'reason': reason, 'evidence': evidence, 'policy': policy,
                'changes_outcome': False, 'authorizes_retry': False}
        result = dict(body, sha256=digest(body))
        write_json(directory / f'{len(records):06}.json', result)
        return result


def for_session(records, root, state):
    """Use the latest matching review only if its subject and evidence still match."""
    matches = [item for item in records if item['session_root'] == str(Path(root).resolve()) and
               item['session_id'] == state['participant'] and item['cohort'] == state['cohort'] and
               item['record_kind'] == state['record_kind']]
    if not matches:
        return {'review_status': 'unreviewed', 'review_category': None, 'review_sha256': None}
    item = matches[-1]
    if (item['category'] not in CATEGORIES or item['changes_outcome'] is not False or
            item['authorizes_retry'] is not False):
        raise ValueError('invalid human review semantics')
    current = False
    try:
        current = (file_receipt(Path(root) / 'session.json') == item['session_receipt'] and
                   all(file_receipt(receipt['path']) == receipt for receipt in item['evidence']))
    except (OSError, ValueError):
        pass
    return {'review_status': 'current' if current else 'stale',
            'review_category': item['category'] if current else None, 'review_sha256': item['sha256']}


def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--session', type=Path, required=True)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--category', choices=CATEGORIES, required=True)
    parser.add_argument('--reviewer', required=True)
    parser.add_argument('--reason', required=True)
    parser.add_argument('--evidence', type=Path, action='append', required=True)
    args = parser.parse_args()
    result = record(args.session, args.directory, category=args.category, reviewer=args.reviewer,
                    reason=args.reason, evidence_paths=args.evidence)
    print(result['sha256'])


if __name__ == '__main__':
    main()
