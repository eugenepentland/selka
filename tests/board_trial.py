"""Grade VM and standalone Zig observations without passing expected answers to either."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CASES = ROOT / 'experiments/board_trial/cases.json'


def invoke(runner, path, raw):
    path.write_text(raw)
    return subprocess.run([str(runner), "--project", str(ROOT / "src/board_trial/guest"), str(path)], capture_output=True, text=True, timeout=90)


def compare(runner, path, cases):
    requests = [{key: case[key] for key in ('name', 'input', 'unavailable')} for case in cases]
    result = invoke(runner, path, json.dumps(requests))
    assert result.returncode == 0, (result.returncode, result.stderr)
    rows = json.loads(result.stdout)
    assert len(rows) == len(cases), (len(rows), len(cases))
    for case, row in zip(cases, rows, strict=True):
        assert row['name'] == case['name'], row
        for mode in ('guest', 'baseline'):
            observation = row[mode]
            actual = dict(observation['outcome'], calls=observation['calls'])
            assert actual == case['expected'], (case['name'], mode, actual, case['expected'])


def transformed(cases):
    result = []
    for original in cases:
        case = deepcopy(original)
        board = case['input']['board']
        if case['name'].startswith('generated_snapshot_'):
            for rect in [board['outline'], *(r['rect'] for r in board['regions']),
                         *(f['rect'] for f in board['features'])]:
                rect[0] += 100_000
                rect[1] -= 200_000
        elif case['name'].startswith('face_matrix_'):
            board['components'] = [n + 100 for n in board['components']]
            board['nets'] = [n + 200 for n in board['nets']]
            for region in board['regions']:
                region['allow_nets'] = [n + 200 for n in region['allow_nets']]
            for feature in board['features']:
                key = 'id' if feature['kind'] == 'component' else 'net'
                feature[key] += 100 if key == 'id' else 200
        else:
            continue
        case['name'] += '_transformed'
        result.append(case)
    assert len(result) == 60
    return result


def reject_transport(runner, path, first):
    base = {key: first[key] for key in ('name', 'input', 'unavailable')}
    mutations = [
        lambda r: r.update(expected={}),
        lambda r: r.update(unavailable=0),
        lambda r: r['input'].update(version=True),
        lambda r: r['input'].update(extra=0),
        lambda r: r['input']['board'].update(components=[1, 2, 3, 4, 5]),
        lambda r: r['input']['board'].update(nets=[True]),
        lambda r: r['input']['board'].update(nets=[-1]),
        lambda r: r['input']['board'].update(nets=[2**64]),
        lambda r: r['input']['board'].update(outline=[0, 0, 1.0, 1]),
        lambda r: r['input']['board'].update(outline=[0, 0, 2**63, 1]),
        lambda r: r['input']['board'].update(features=r['input']['board']['features'] * 9),
        lambda r: r['input']['board'].update(features=[{'kind': []}]),
        lambda r: r['input']['board']['regions'][0].update(face='inner'),
        lambda r: r['input']['board']['regions'][0].update(blocks=[[]]),
        lambda r: r['input']['board']['regions'][0].update(allow_nets=[10] * 5),
        lambda r: r['input']['board']['features'][0].update(layer='front'),
    ]
    invalid = []
    for mutate in mutations:
        request = deepcopy(base)
        mutate(request)
        invalid.append(json.dumps([request]))
    invalid.append(json.dumps([base]).replace('"version": 1', '"version": 1, "version": 1'))
    invalid.append('{}')
    for raw in invalid:
        result = invoke(runner, path, raw)
        assert result.returncode != 0 and not result.stdout, (raw, result.stdout, result.stderr)
        assert any(name in result.stderr for name in ('InvalidSnapshot', 'SnapshotCapacity', 'DuplicateField')), result.stderr
    return len(invalid)


def check_diagnostics(compiler, directory):
    source = ROOT / 'src/board_trial/guest'
    identity = ('module main\nimport validation\nimport ids\n\n\ndef mix(n: ids.NetId) -> ids.ComponentId:\n    return n\n\n\n'
                'def main() -> i64:\n    return 0\n')
    units = ('module main\nimport validation\nimport units\n\n\ndef mix(n: units.Millimetres) -> units.Micrometres:\n    return n\n\n\n'
             'def main() -> i64:\n    return 0\n')
    original = (source / 'model.my').read_text()
    state = original.replace('    via: Via\n', '    via: Via,\n    pad: Via\n')
    assert state != original
    cases = [
        ('identity', 'main.my', identity, 'E_TYPE', 'ids::ComponentId, found ids::NetId'),
        ('units', 'main.my', units, 'E_TYPE', 'units::Micrometres, found units::Millimetres'),
        ('state', 'model.my', state, 'E_INCOMPLETE_MATCH', 'variant `pad`'),
    ]
    for name, file, text, code, message in cases:
        root = directory / name
        shutil.copytree(source, root)
        (root / file).write_text(text)
        result = subprocess.run([str(compiler), 'check-project', str(root / 'main.my'), '--diagnostics=json'],
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 1 and not result.stdout, result
        records = [json.loads(line) for line in result.stderr.splitlines()]
        diagnostics = [row['diagnostic'] for row in records if row['kind'] == 'diagnostic']
        assert len(diagnostics) == (3 if name == 'state' else 1), diagnostics
        for diagnostic in diagnostics:
            assert diagnostic['code'] == code and message in diagnostic['message'], diagnostic
            assert diagnostic['location']['bytes']['end'] > diagnostic['location']['bytes']['start'], diagnostic
            if name == 'state':
                assert diagnostic['notes'][0]['location']['path'] == 'model.my', diagnostic
        if name == 'state':
            assert [row['location']['path'] for row in diagnostics] == ['bounds.my', 'checks.my', 'policy.my'], diagnostics



def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    args = parser.parse_args()
    cases = json.loads(CASES.read_text())
    assert len(cases) == 87
    with tempfile.TemporaryDirectory(prefix='mylang-board-') as directory:
        path = Path(directory) / 'requests.json'
        compare(args.runner.resolve(), path, cases)
        compare(args.runner.resolve(), path, transformed(cases))
        rejected = reject_transport(args.runner.resolve(), path, cases[0])
        check_diagnostics(args.compiler.resolve(), Path(directory))
    print(f'board trial: 87 fixed + 60 transformed cases, both VM and Zig match; {rejected} malformed transports reject; 3 seeded static errors caught')


if __name__ == '__main__':
    main()
