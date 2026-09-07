"""Measured gateway fixtures; never participant evidence."""
import argparse
import json
from pathlib import Path
import tempfile
import time
from gateway import begin, command
from pack import prepare, seal
from experiments.application_comparison.storage import read_json, write_json


def denied(callback):
    try:
        callback()
    except ValueError:
        return
    raise AssertionError('expected refusal')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(dir=root / '.zig-cache', prefix='gateway-fixture-') as temp:
        directory = Path(temp) / 'trial'
        prepare(directory, args.compiler.resolve(), 1, 'fixture-gateway', 'fixture', 'agent')
        begin(directory)
        first = command(directory, 'check', [])
        assert first['returncode'] == 1 and first['commands'] == 1 and first['edited_checks'] == 0
        changed = command(directory, 'run', ['/usr/bin/python3', '-c',
            "from pathlib import Path;p=Path('work/ledger.my');p.write_text(p.read_text().replace('while i < 3u64','while i < 4u64'))"])
        assert changed['returncode'] == 0
        denied(lambda: seal(directory, 'completed'))
        checked = command(directory, 'check', [])
        assert checked['returncode'] == 0 and checked['edited_checks'] == 1
        private = command(directory, 'run', ['/bin/sh', '-c', 'test ! -e /work/../setup.json && test ! -e /private/grader'])
        assert private['returncode'] == 0
        record = read_json(directory / 'commands/002/result.json')
        assert record['source_before'] != record['source_after'] and record['isolated']
        assert record['duration_seconds'] > 0
        assert (directory / 'commands/001/stdout').read_bytes()
        setup = read_json(directory / 'setup.json')
        # Fixture-only reduced bounds exercise the same frozen-budget enforcement path.
        setup['budget']['tool_invocations'] = 4
        write_json(directory / 'setup.json', setup)
        denied(lambda: command(directory, 'run', ['/bin/true']))
        setup['budget']['tool_invocations'] = 20
        setup['budget']['edited_submissions'] = 1
        write_json(directory / 'setup.json', setup)
        denied(lambda: command(directory, 'check', []))
        setup['budget']['edited_submissions'] = 5
        write_json(directory / 'setup.json', setup)
        state = read_json(directory / 'gateway.json')
        state['started_unix'] = time.time() - 901
        write_json(directory / 'gateway.json', state)
        denied(lambda: command(directory, 'check', []))
        final = seal(directory, 'budget')
        assert final['gateway_metrics']['tool_invocations'] == 7
        assert final['gateway_metrics']['executed_commands'] == 4
        assert final['gateway_metrics']['model_tokens'] is None
        records = [json.loads(line) for line in (directory / 'gateway.jsonl').read_text().splitlines()]
        assert sum(row['event'] == 'start' for row in records) == 4
        assert sum(row['event'] == 'end' for row in records) == 4
        assert sum(row['event'] == 'budget-rejection' for row in records) == 3
        for scenario in ('budget', 'abandoned'):
            other = Path(temp) / scenario
            prepare(other, args.compiler.resolve(), 1, 'fixture-gateway', 'fixture', 'agent')
            begin(other)
            if scenario == 'budget':
                command(other, 'check', [])
                setup = read_json(other / 'setup.json')
                setup['budget']['tool_invocations'] = 2
                write_json(other / 'setup.json', setup)
                edited = command(other, 'run', ['/usr/bin/python3', '-c',
                    "from pathlib import Path;p=Path('work/ledger.my');p.write_text(p.read_text().replace('while i < 3u64','while i < 4u64'))"])
                assert edited['returncode'] == 0
                denied(lambda: command(other, 'check', []))
            denied(lambda: seal(other, 'completed'))
            state = read_json(other / 'gateway.json')
            state['pending'] = 999
            write_json(other / 'gateway.json', state)
            denied(lambda: seal(other, scenario))
            state['pending'] = None
            write_json(other / 'gateway.json', state)
            captured = seal(other, scenario)
            assert captured['final_checked'] is False
            if scenario == 'budget':
                assert captured['last_checked'] is not None and captured['source'] != captured['last_checked']
            else:
                assert captured['last_checked'] is None
            continuation = Path(temp) / (scenario + '-next')
            setup = prepare(continuation, args.compiler.resolve(), 2, 'fixture-gateway', 'fixture', 'agent', other)
            assert setup['start'] == captured['source']
        print('Gateway fixtures: isolated commands, public checks, measured source/output receipts, all budgets, completed-check requirement, retained unchecked budget/abandoned sources and exact request counts passed')


if __name__ == '__main__':
    main()
