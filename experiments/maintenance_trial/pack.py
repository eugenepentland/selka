"""Thin coordinator adapter using the existing study snapshot/identity primitives."""
import argparse
import importlib.util
import json
from pathlib import Path
import random
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from experiments.application_comparison.storage import (
    digest, inventory, path_identity, read_json, snapshot, source_files, verify_snapshot, write_json,
)
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('ledger_public', HERE / 'public/check.py')
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)
BUDGET = {'tool_invocations': 20, 'edited_submissions': 5, 'wall_seconds': 900}


def authoring_receipt():
    files = source_files(HERE, max_files=64, max_bytes=2 * 1024 * 1024)
    return inventory({name: data for name, data in files.items() if '__pycache__' not in name.split('/')})


def source_receipt(directory):
    files = source_files(directory, max_files=3, max_bytes=3 * 65536)
    if set(files) != set(checks.FILES):
        raise ValueError('only ledger.my, model.my and report.my may be submitted')
    hashes = inventory(files)
    return {'files': hashes, 'sha256': digest(hashes)}


def prepare(directory, compiler, stage, participant, model, kind, previous=None):
    if stage > 1:
        if previous is None:
            raise ValueError('later stages require the same participant previous seal')
        prior = read_json(previous / 'seal.json')
        prior_setup = read_json(previous / 'setup.json')
        verify_snapshot(previous / 'sealed', prior['source'])
        if (prior_setup['stage'] != stage - 1 or prior_setup['participant'] != participant or
                prior_setup['model'] != model or prior_setup['kind'] != kind or
                prior_setup['compiler'] != path_identity(compiler)):
            raise ValueError('stage continuation identity mismatch')
        baseline = previous / 'sealed'
    else:
        if previous is not None:
            raise ValueError('stage one starts from the frozen baseline')
        baseline = HERE / 'public/baseline'
    directory.mkdir(exist_ok=False)
    public = directory / 'public'
    public.mkdir()
    start = snapshot(baseline, public / 'work')
    for name in ('check.py', 'cases.json'):
        shutil.copyfile(HERE / 'public' / name, public / name)
    contract = (HERE / 'public/contract.md').read_text()
    common = contract.split('Stage 1 —')[0]
    brief = 'Stage ' + str(stage) + ' —' + contract.split('Stage ' + str(stage) + ' —')[1].split('\nStage ')[0]
    brief = brief.split('\nYour coordinator')[0]
    (public / 'TASK.md').write_text(common + brief + '\n\nCheck: python3 check.py --compiler COMPILER --stage ' + str(stage) + '\n')
    fixed = {name: (public / name).read_bytes() for name in ('check.py', 'cases.json', 'TASK.md')}
    authoring = authoring_receipt()
    setup = {'version': 'maintenance-sequence-v1', 'stage': stage, 'participant': participant,
             'model': model, 'kind': kind, 'compiler': path_identity(compiler), 'budget': BUDGET,
             'start': start, 'public_fixed': inventory(fixed), 'authoring': authoring,
             'previous_source': None if previous is None else prior['source']['sha256'],
             'status': 'prepared-unreviewed', 'scored_launch_enabled': False}
    write_json(directory / 'setup.json', setup)
    return setup


def seal(directory, reason, transcript):
    if (directory / 'seal.json').exists():
        raise ValueError('submission already sealed')
    setup = read_json(directory / 'setup.json')
    public = directory / 'public'
    fixed = {name: (public / name).read_bytes() for name in setup['public_fixed']}
    if inventory(fixed) != setup['public_fixed']:
        raise ValueError('public instructions or tests changed')
    source_receipt(public / 'work')
    captured = snapshot(public / 'work', directory / 'sealed')
    shutil.copyfile(transcript, directory / 'transcript.jsonl')
    result = {'reason': reason, 'source': captured, 'transcript': path_identity(directory / 'transcript.jsonl'),
              'budget_review': 'coordinator-required', 'structure_review': 'coordinator-required'}
    write_json(directory / 'seal.json', result)
    return result


def hidden_cases(seed):
    randomizer = random.Random(seed)
    cases = []
    for floor, ceiling in ((-100, -100), (-5, 0), (0, 0), (0, 100), (100, 100)):
        for values in ([floor] * 4, [-100, 100, floor, ceiling], [100, -100, ceiling, floor]):
            cases.append({'input': values, 'floor': floor, 'ceiling': ceiling})
    for _ in range(33):
        floor, ceiling = sorted(randomizer.randint(-100, 100) for _ in range(2))
        cases.append({'input': [randomizer.randint(-100, 100) for _ in range(4)],
                      'floor': floor, 'ceiling': ceiling})
    return cases


def oracle(stage, case):
    # Independent scalar reference: does not call public expected() or guest code.
    count, amount = 0, 0
    for value in case['input']:
        if value < case['floor']:
            continue
        count += 1
        if stage >= 2 and value > case['ceiling']:
            value = case['ceiling']
        amount += value
    if stage == 3:
        return amount * 100 + count * 10 + (4 - count)
    return amount * 100 + count


def grade(directory, seed):
    if not seed.strip() or (directory / 'grade.json').exists():
        raise ValueError('fresh private seed and ungraded sealed submission required')
    setup, sealed = read_json(directory / 'setup.json'), read_json(directory / 'seal.json')
    verify_snapshot(directory / 'sealed', sealed['source'])
    if authoring_receipt() != setup['authoring']:
        raise ValueError('task authoring or grading code changed since preparation')
    compiler = Path(setup['compiler']['path'])
    if path_identity(compiler) != setup['compiler']:
        raise ValueError('compiler changed since preparation')
    cases, outcomes = hidden_cases(seed), []
    for index, case in enumerate(cases):
        for direct in (False, True):
            result = checks.observe(compiler, directory / 'sealed', setup['stage'], case, direct)
            expected = str(oracle(setup['stage'], case)) + '\n'
            outcomes.append({'case': index, 'direct': direct, 'expected': expected,
                             'passed': result['returncode'] == 0 and result['stdout'] == expected, **result})
    verify_snapshot(directory / 'sealed', sealed['source'])
    report = {'version': 'maintenance-grade-v1', 'kind': setup['kind'], 'stage': setup['stage'],
              'source': sealed['source'], 'private_seed': seed, 'cases_sha256': digest(cases),
              'behavior_passed': all(item['passed'] for item in outcomes), 'outcomes': outcomes,
              'budget_review': 'coordinator-required', 'structure_review': 'coordinator-required'}
    write_json(directory / 'grade.json', report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('prepare', 'seal', 'grade'))
    parser.add_argument('directory', type=Path)
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--stage', type=int, choices=(1, 2, 3))
    parser.add_argument('--participant')
    parser.add_argument('--model')
    parser.add_argument('--kind', choices=('fixture', 'agent'))
    parser.add_argument('--previous', type=Path)
    parser.add_argument('--reason', choices=('completed', 'budget', 'abandoned'))
    parser.add_argument('--transcript', type=Path)
    parser.add_argument('--seed-file', type=Path)
    args = parser.parse_args()
    if args.command == 'prepare':
        if not all((args.compiler, args.stage, args.participant, args.model, args.kind)):
            parser.error('prepare requires compiler, stage, participant, model and kind')
        result = prepare(args.directory, args.compiler.resolve(), args.stage, args.participant,
                         args.model, args.kind, args.previous)
        print(json.dumps({'stage': result['stage'], 'status': result['status']}))
    elif args.command == 'seal':
        if not args.reason or not args.transcript:
            parser.error('seal requires reason and transcript')
        result = seal(args.directory, args.reason, args.transcript)
        print(json.dumps({'source': result['source'], 'reason': result['reason']}))
    else:
        if not args.seed_file:
            parser.error('grade requires seed-file outside participant projection')
        result = grade(args.directory, args.seed_file.read_text())
        print(json.dumps({key: result[key] for key in ('kind', 'stage', 'behavior_passed')}))


if __name__ == '__main__':
    main()
