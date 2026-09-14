#!/usr/bin/env python3
"""Execute typed guest assertions and domain codecs through the native test CLI."""
import argparse
import json
from pathlib import Path
import subprocess
import shutil
import tempfile

SOURCE = '''module main
export Pair
export Tone
export Choice
export Outcome
export Positive
export Decoded
export test_record
export test_array
export test_enum
export test_union
export test_result
export test_domain
export test_trap
export test_frames
export test_step
export test_table
export test_memory


class Pair:
    number: i64
    good: bool


enum Tone:
    low,
    high


union Choice:
    none,
    value: Pair


result Outcome:
    ok: Pair,
    err: i64


result Decoded:
    ok: Positive,
    err: i64


domain Positive: i64:
    codec i64:
        decode: from_wire,
        encode: to_wire

    private def raw(n: i64) -> Positive:
        return wrap[Positive](n)

    def from_wire(n: i64) -> Decoded:
        if n < 0:
            return Err(-10)
        return Ok(Positive.raw(n * 2))

    def to_wire(p: Positive) -> i64:
        return unwrap(p) + 1


def main() -> i64:
    return 0


def test_record(n: i64) -> Pair:
    return Pair(number=n, good=True)


def test_array(a: [2]u64) -> [2]u64:
    return a


def test_enum(t: Tone) -> Tone:
    return t


def test_table(t: [Tone]u16) -> [Tone]u16:
    return t


def test_union(c: Choice) -> Choice:
    return c


def test_result(r: Outcome) -> Outcome:
    return r


def test_domain(n: Positive) -> Positive:
    return n


def test_trap() -> bool:
    return divtrunc(1, 0) == 0


def descend(n: i64) -> bool:
    if n == 0:
        return True
    return descend(n - 1)


def test_frames() -> bool:
    return descend(3)


def test_step() -> bool:
    return True


def test_memory() -> bool:
    values: list[int] = []
    for r in range(200000):
        values.append(r)
    return len(values) == 200000
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--qbe', default='qbe')
    parser.add_argument('--zig', default='zig')
    args = parser.parse_args()
    args.qbe = str(Path(shutil.which(args.qbe) or args.qbe).resolve())
    args.zig = str(Path(shutil.which(args.zig) or args.zig).resolve())
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='native-test-execution-') as directory:
        directory = Path(directory)
        project = directory / 'project'
        project.mkdir()
        entry, settings = project / 'main.my', directory / 'cases.json'
        entry.write_text(SOURCE)
        cases = {
            'main::test_record': {'arguments': {'n': '-9223372036854775808'},
                                  'expected': {'number': '-9223372036854775808', 'good': True}},
            'main::test_array': {'arguments': {'a': ['0', '18446744073709551615']},
                                 'expected': ['0', '18446744073709551615']},
            'main::test_enum': {'arguments': {'t': 'high'}, 'expected': 'high'},
            'main::test_table': {'arguments': {'t': {'high': '65535', 'low': '0'}},
                                 'expected': {'low': '0', 'high': '65535'}},
            'main::test_union': {'arguments': {'c': {'case': 'value', 'value': {'number': '7', 'good': False}}},
                                 'expected': {'case': 'value', 'value': {'number': '7', 'good': False}}},
            'main::test_result': {'arguments': {'r': {'case': 'err', 'value': '-7'}},
                                  'expected': {'case': 'err', 'value': '-7'}},
            'main::test_domain': {'arguments': {'n': '8'}, 'expected': '17'},
            'main::test_memory': {'skip': 'exercised below under explicit byte ceilings'},
        }

        def invoke(pattern='*', code=0, extra=()):
            settings.write_text(json.dumps(cases))
            process = subprocess.run([str(compiler), 'test', str(entry), '--json', '--force',
                '--qbe', str(args.qbe), '--zig', str(args.zig), '--cache-dir', str(directory / 'cache'),
                '--cases', str(settings), '--filter', pattern, *extra],
                cwd=project, capture_output=True, text=True, timeout=180)
            assert process.returncode == code, (process.returncode, process.stdout, process.stderr)
            if code == 2:
                return process.stderr + process.stdout
            report = json.loads(process.stdout)
            assert report['version'] == 'native-tests-v1', report
            return {row['name']: row for row in report['tests']}

        rows = invoke(code=1)
        assert len(rows) == 11, rows
        assert rows['main::test_memory']['status'] == 'skipped', rows['main::test_memory']
        for name, row in rows.items():
            if name == 'main::test_memory':
                continue
            if name == 'main::test_trap':
                assert row['status'] == 'failed' and 'R_DIVISION_BY_ZERO' in row['reason'], row
                line = SOURCE.splitlines().index('    return divtrunc(1, 0) == 0') + 1
                assert f'main.my:{line}:' in row['reason'] and 'in main::test_trap' in row['reason'], row
            else:
                assert row['status'] == 'passed', row
        # Decode, public invocation and encode must each execute once under one quota.
        assert invoke('*domain', extra=('--max-calls=3',))['main::test_domain']['actual'] == '17'
        limited = invoke('*domain', code=1, extra=('--max-calls=2',))['main::test_domain']
        assert 'CodecCallLimit' in limited['reason'], limited
        cases['main::test_domain']['arguments']['n'] = '-1'
        rejected = invoke('*domain', code=1)['main::test_domain']
        assert 'DomainCodecRejected' in rejected['reason'] and 'main::Positive' in rejected['reason'], rejected
        cases['main::test_domain']['arguments']['n'] = '8'
        step = invoke('*step', code=1, extra=('--max-steps=1',))['main::test_step']
        assert 'R_STEP_LIMIT' in step['reason'], step
        frame = invoke('*frames', code=1, extra=('--max-frames=1',))['main::test_frames']
        assert 'R_FRAME_LIMIT' in frame['reason'], frame
        # The byte ceiling alone decides: the same growth passes under a roomy one
        # and traps under a tight one, reported as a failure rather than a crash.
        del cases['main::test_memory']
        steps = '--max-steps=8000000'
        roomy = invoke('*memory', extra=('--max-memory=32M', steps))['main::test_memory']
        assert roomy['status'] == 'passed', roomy
        tight = invoke('*memory', code=1, extra=('--max-memory=1M', steps))['main::test_memory']
        assert tight['status'] == 'failed' and 'R_MEMORY_BUDGET' in tight['reason'], tight
        assert 'in main::test_memory' in tight['reason'], tight
        assert '--max-memory BYTES' in invoke('*memory', code=2, extra=('--max-memory=huge',))
        cases['main::test_memory'] = {'skip': 'exercised above under explicit byte ceilings'}
        for invalid in ('01', '-0', '9223372036854775808', 1, True):
            cases['main::test_record']['arguments'] = {'n': invalid}
            assert 'InvalidTestValue' in invoke('*record', code=2)
        cases['main::test_record']['arguments'] = {'wrong': '1'}
        assert 'InvalidTestArguments' in invoke('*record', code=2)
        entry.write_text('module main\nexport Secret\nexport test_opaque\n\n\n'
                         'domain Secret: i64:\n    pass\n\n\n'
                         'def main() -> i64:\n    return 0\n\n\n'
                         'def test_opaque(s: Secret) -> bool:\n    return True\n')
        cases = {'main::test_opaque': {'arguments': {'s': '1'}}}
        assert 'UnsupportedTestType' in invoke(code=2)
    print('Native test execution: typed trees, domain codecs, exact call budgets, byte ceilings, source traps and strict arguments passed')


if __name__ == '__main__':
    main()
