"""Coordinator commands. These are not an unrestricted participant tool API."""
import argparse
import json
from pathlib import Path
from . import session
from .execution import correct, evaluate
from .grading import grade
from .inputs import decode_case
from .isolation import run
from .storage import read_json


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('prepare')
    prepare.add_argument('root', type=Path)
    prepare.add_argument('--baseline', type=Path, required=True)
    prepare.add_argument('--language', choices=sorted(session.LANGUAGES), required=True)
    for name in ('block', 'cohort', 'participant', 'model'):
        prepare.add_argument('--' + name, required=True)
    prepare.add_argument('--kind', choices=('fixture', 'agent'), default='fixture')
    prepare.add_argument('--arm', choices=('main', 'language-focused'), default='main')
    prepare.add_argument('--protected', action='append', default=[])
    for name in ('start-preparation', 'start-task', 'submit', 'seal', 'status', 'check'):
        command = commands.add_parser(name)
        command.add_argument('root', type=Path)
        if name == 'start-task':
            command.add_argument('--practice-outcome', choices=('passed', 'failed', 'budget'), required=True)
        if name == 'seal':
            command.add_argument('--reason', choices=('completed', 'budget', 'abandoned'), required=True)
        if name == 'check':
            command.add_argument('--adapter', type=Path, required=True)
            command.add_argument('--public-cases', type=Path, required=True)
    grading = commands.add_parser('grade')
    grading.add_argument('roots', type=Path, nargs=3)
    grading.add_argument('--adapters', type=Path, required=True)
    grading.add_argument('--hidden-cases', type=Path, required=True)
    grading.add_argument('--output', type=Path, required=True)
    grading.add_argument('--grader-identity', required=True)
    doctor = commands.add_parser('doctor')
    doctor.add_argument('--work', type=Path, required=True)
    return result


def check(args):
    adapter = read_json(args.adapter)
    manifest = session.load(args.root)
    if adapter['language'] != manifest['language']:
        raise ValueError('wrong language adapter')
    request, raw, expected = decode_case(read_json(args.public_cases))
    row = session.submit(args.root)
    directory = args.root / 'submissions' / f"{row['index']:03}"
    if row['scope_violations']:
        record = {'source_sha256': row['source']['sha256'], 'passed': False,
                  'scope_violations': row['scope_violations']}
    else:
        record = evaluate(directory / 'source', row['source'], adapter, request, directory / 'check', request_bytes=raw)
        record['passed'] = correct(record['outcome'], expected)
    session.record_check(args.root, row['index'], record)
    return record


def dispatch(args):
    if args.command == 'prepare':
        return session.prepare(args.root, args.baseline, language=args.language, block=args.block,
                               cohort=args.cohort, participant=args.participant, model=args.model,
                               kind=args.kind, arm=args.arm, protected=args.protected)
    if args.command == 'start-preparation':
        return session.start_preparation(args.root)
    if args.command == 'start-task':
        return session.start_task(args.root, args.practice_outcome)
    if args.command == 'submit':
        return session.submit(args.root)
    if args.command == 'seal':
        return session.seal(args.root, args.reason)
    if args.command == 'status':
        return session.load(args.root)
    if args.command == 'check':
        return check(args)
    if args.command == 'grade':
        request, raw, expected = decode_case(read_json(args.hidden_cases))
        return grade(args.roots, read_json(args.adapters), request, expected, args.output,
                     grader_identity=args.grader_identity, request_bytes=raw)
    if args.command == 'doctor':
        result = run(args.work, ['/usr/bin/python3', '-I', '-S', '-c', 'import os;print(os.getpid())'])
        return dict(result, stdout=result['stdout'].decode(errors='replace'), stderr=result['stderr'].decode(errors='replace'))
    raise ValueError('unknown command')


def main():
    args = parser().parse_args()
    try:
        result = dispatch(args)
    except (OSError, ValueError) as error:
        print(json.dumps({'error': str(error)}))
        return 2
    print(json.dumps(result, indent=2, allow_nan=False))
    if args.command == 'check' and not result['passed']:
        return 1
    if args.command == 'doctor' and (not result['isolated'] or result['returncode'] != 0):
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
