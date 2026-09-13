#!/usr/bin/env python3
"""Exercise typed serialization and rejection through checked public module types."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='mylang-typed-json-') as temporary:
        root = Path(temporary)
        entry = root / 'main.my'
        module = root / 'data.my'
        path = root / 'value.json'
        entry.write_text('module main\nimport data\n\n\ndef main() -> i64:\n    return 0\n')
        source = '''module data
export Point
export Flag
export Choice
export Outcome
export Empty
export Secret
export Maybe
export File
export Zero


class Point:
    x: u64
    flags: [Flag]bool
    samples: [2]i16


enum Flag:
    yes,
    no


union Choice:
    none,
    point: Point


result Outcome:
    ok: Choice,
    err: i8


class Empty:
    pass


domain Secret: i64:
    def make(x: i64) -> Secret:
        return wrap<Secret>(x)


union Maybe:
    none,
    some: Secret


class Zero:
    data: [0]Secret


resource File: filesystem


class Private:
    hidden: bool
'''
        module.write_text(source)

        def run(expected=0, extra=()):
            result = subprocess.run([compiler, 'check-value-project', str(entry), '--value=' + str(path), *extra], capture_output=True, text=True, timeout=30)
            assert result.returncode == expected, (result.returncode, expected, result.stderr)
            if expected:
                assert not result.stdout, result.stdout
                return result.stderr
            return result.stdout

        def check(ty, value, expected=None):
            payload = {'version': 'typed-json-v1', 'type': ty, 'value': value}
            path.write_text(json.dumps(payload))
            output = run()
            assert json.loads(output) == (payload if expected is None else expected)
            path.write_text(output)
            assert run() == output
            return output

        def reject(ty, value, code, pointer=None):
            path.write_text(json.dumps({'version': 'typed-json-v1', 'type': ty, 'value': value}))
            message = run(1)
            assert code in message
            if pointer is not None:
                assert 'JSON pointer ' + json.dumps(pointer) in message, message

        for signed in (True, False):
            for bits in (8, 16, 32, 64):
                ty = ('i' if signed else 'u') + str(bits)
                low = -(1 << (bits - 1)) if signed else 0
                high = (1 << (bits - (1 if signed else 0))) - 1
                for value in (low, high):
                    check(ty, str(value))
                for value in (low - 1, high + 1):
                    reject(ty, str(value), 'CodecIntegerOutOfRange')
        for value in (True, False):
            check('bool', value)
        for value in ('', '+1', '01', '-0', ' 1', '1 ', '1e2', '0x10', '1_0', '--1'):
            reject('i64', value, 'InvalidCodecInteger')
        for value in (1, 1.0, True, None, [], {}):
            reject('i64', value, 'ValueTypeMismatch')
        for value in ('true', 0, None):
            reject('bool', value, 'ValueTypeMismatch')
        for case in ('yes', 'no'):
            check('data::Flag', case)
        reject('data::Flag', 'unknown', 'UnknownCodecCase')
        reject('data::Flag', 0, 'ValueTypeMismatch')
        check('data::Empty', {})
        point = {'samples': ['-32768', '32767'], 'flags': {'no': False, 'yes': True}, 'x': '18446744073709551615'}
        output = check('data::Point', point)
        canonical_point = json.loads(output)['value']
        assert list(canonical_point) == ['x', 'flags', 'samples']
        assert list(canonical_point['flags']) == ['yes', 'no']
        check('data::Choice', {'case': 'none'})
        check('data::Choice', {'value': point, 'case': 'point'})
        check('data::Outcome', {'case': 'ok', 'value': {'case': 'point', 'value': point}})
        check('data::Outcome', {'case': 'err', 'value': '-128'})
        reject('data::Choice', {'case': 'other'}, 'UnknownCodecCase', '/value/case')
        reject('data::Choice', {'case': 'none', 'value': None}, 'UnexpectedCodecField')
        reject('data::Choice', {'case': 'point'}, 'IncompleteCodecValue', '/value/value')
        reject('data::Choice', {'case': 'point', 'value': point, 'extra': 0}, 'UnexpectedCodecField')
        reject('data::Point', {**point, 'extra': 0}, 'UnexpectedCodecField')
        reject('data::Point', {key: value for key, value in point.items() if key != 'x'}, 'IncompleteCodecValue')
        reject('data::Point', {**point, 'samples': ['1']}, 'IncompleteCodecValue', '/value/samples/1')
        reject('data::Point', {**point, 'flags': {'yes': True}}, 'IncompleteCodecValue', '/value/flags/no')
        reject('data::Point', {**point, 'flags': {'yes': True, 'maybe': False}}, 'IncompleteCodecValue')
        for ty, value in [('Secret', '1'), ('Maybe', {'case': 'none'}), ('Zero', {'data': []}), ('File', '1')]:
            reject('data::' + ty, value, 'NoImplicitCodec')
        reject('clock_cap', '1', 'NoImplicitCodec', '/type')
        reject('data::Private', {'hidden': True}, 'UnknownPublicValueType', '/type')
        reject('missing::Point', point, 'UnknownPublicValueType')
        reject('data::Outcome', {'case': 'ok', 'value': {'case': 'point', 'value': {**point, 'samples': ['1', '40000']}}}, 'CodecIntegerOutOfRange', '/value/value/value/samples/1')
        reject('data::Point', {**point, 'samples': ['1', '2', '3']}, 'IncompleteCodecValue', '/value/samples/2')
        reject('data::Point', {**point, 'flags': {'yes': 'wrong', 'no': False}}, 'ValueTypeMismatch', '/value/flags/yes')
        path.write_text(json.dumps({'version': 'typed-json-v2', 'type': 'bool', 'value': True}))
        assert 'JSON pointer "/version"' in run(1)
        # Long names produce an explicitly marked, valid quoted pointer prefix.
        long_name = 'x' * 5000
        module.write_text('module data\nexport Long\n\n\nclass Long:\n    ' + long_name + ': bool\n')
        path.write_text(json.dumps({'version': 'typed-json-v1', 'type': 'data::Long', 'value': {long_name: 'wrong'}}))
        message = run(1)
        assert 'ValueTypeMismatch' in message and '(path truncated)' in message
        pointer = message.split(' at JSON pointer ', 1)[1].split(' (path truncated)', 1)[0]
        assert len(json.loads(pointer)) == 4096 and json.loads(pointer).startswith('/value/')
        module.write_text(source)
        # Duplicate decoded keys, including escaped aliases, reject at any depth.
        for raw in (
            '{"version":"typed-json-v1","version":"typed-json-v1","type":"bool","value":true}',
            '{"version":"typed-json-v1","type":"data::Empty","value":{"x":true,"\\u0078":false}}',
            '{"version":"typed-json-v1","type":"data::Choice","value":{"case":"none","case":"none"}}',
        ):
            path.write_text(raw)
            assert 'DuplicateField' in run(1)
        for payload in (
            {'version': 'typed-json-v2', 'type': 'bool', 'value': True},
            {'version': 'typed-json-v1', 'type': 'bool', 'value': True, 'extra': 0},
            {'version': 'typed-json-v1', 'type': 'bool'},
        ):
            path.write_text(json.dumps(payload))
            run(1)
        path.write_text('{"version":"typed-json-v1","type":"bool","value":' + '[' * 80 + 'true' + ']' * 80 + '}')
        assert 'CodecDepthLimit' in run(1)
        check('bool', True)
        raw = path.read_text()
        path.write_text(raw + ' ' * (1024 * 1024 - len(raw)))
        run()
        path.write_text(path.read_text() + ' ')
        assert 'CodecByteLimit' in run(1)
        # Materialization limits count containers and scalar values, not just leaves.
        module.write_text('module data\nexport Big\n\n\nclass Big:\n    data: [65534]bool\n')
        check('data::Big', {'data': [True] * 65534})
        module.write_text('module data\nexport Big\n\n\nclass Big:\n    data: [65535]bool\n')
        reject('data::Big', {'data': [True] * 65535}, 'CodecValueLimit')
        for count in (63, 64):
            declarations = ''.join(f'\n\nclass R{i}:\n    next: ' + (f'R{i+1}' if i + 1 < count else 'bool') + '\n' for i in range(count))
            module.write_text('module data\n' + ''.join(f'export R{i}\n' for i in range(count)) + declarations)
            value = True
            for _ in range(count):
                value = {'next': value}
            if count == 63:
                check('data::R0', value)
            else:
                reject('data::R0', value, 'CodecDepthLimit')
        module.write_text(source)
        check('data::Point', point)
        module.write_text(source.replace('    x: u64\n', '    x: u64\n    added: bool\n'))
        assert 'IncompleteCodecValue' in run(1)
        module.write_text(source + '\n\ndef invalid() -> i64:\n    return True\n')
        assert 'E_TYPE' in run(1)
        module.write_text(source)
        run(2, ['--evaluation-request'])
        run(2, ['--value=' + str(path)])
        fixture = Path(__file__).resolve().parents[1] / 'examples' / 'domain-codecs' / 'data.my'
        domains = fixture.read_text().replace('module data\n', 'module data\nexport Pair\nexport Choice\nexport Key\nexport Table\n')
        domains += ('\n\nclass Pair:\n    items: [2]Positive\n\n\nunion Choice:\n    none,\n    some: Positive\n'
                    '\n\nenum Key:\n    a,\n    b\n\n\nclass Table:\n    items: [Key]Positive\n')
        module.write_text(domains)
        check('data::Positive', {'n': '7'})
        pair = {'items': [{'n': '7'}, {'n': '9'}]}
        check('data::Pair', pair)
        check('data::Choice', {'case': 'none'})
        check('data::Choice', {'case': 'some', 'value': {'n': '7'}})
        check('data::Table', {'items': {'a': {'n': '7'}, 'b': {'n': '9'}}})
        reject('data::Pair', {'items': [{'n': '7'}, {'n': '0'}]}, 'DomainCodecRejected', '/value/items/1')
        message = run(1)
        assert 'codec rejection:' in message and '"value":"-1"' in message, message
        reject('data::Choice', {'case': 'some', 'value': {'n': '0'}}, 'DomainCodecRejected', '/value/value')
        reject('data::Table', {'items': {'a': {'n': '7'}, 'b': {'n': '0'}}}, 'DomainCodecRejected', '/value/items/b')
        reject('data::Positive', {'n': True}, 'ValueTypeMismatch', '/value/n')
        check('data::Pair', pair)
        for flag, code in (
            ('--max-codec-calls=3', 'CodecCallLimit'),
            ('--max-codec-values=15', 'CodecWorkLimit'),
            ('--max-codec-steps=1', 'R_STEP_LIMIT'),
            ('--max-codec-frames=1', 'R_FRAME_LIMIT'),
            ('--max-codec-bytes=1', 'CodecMemoryLimit'),
        ):
            message = run(1, [flag])
            assert code in message, message
        assert json.loads(run(0, ['--max-codec-calls=4', '--max-codec-values=16']))['value'] == pair
        for flag in ('--max-codec-steps', '--max-codec-frames', '--max-codec-calls', '--max-codec-bytes', '--max-codec-values'):
            for value in ('0', '-1', '', '18446744073709551616'):
                run(2, [flag + '=' + value])
            run(2, [flag + '=1', flag + '=2'])
            misplaced = subprocess.run([compiler, 'check-project', str(entry), flag + '=1'], capture_output=True)
            assert misplaced.returncode == 2 and not misplaced.stdout
        # A declared decoder may deliberately canonicalize wire data. Execute both
        # methods rather than merely validating or echoing the incoming document.
        module.write_text(domains.replace('x.n <= 0', 'x.n < 10').replace('Positive.raw(x.n)', 'Positive.raw(x.n // 10 * 10)'))
        check('data::Positive', {'n': '19'}, {'version': 'typed-json-v1', 'type': 'data::Positive', 'value': {'n': '10'}})
        module.write_text(domains)
        path.unlink()
        run(2)
    print('typed JSON acceptance: scalar ranges, aggregate/variant/table round trips, nominal visibility, opaque rejection, strict keys, byte/value/depth boundaries, schema changes, explicit domain execution/shared budgets, and CLI failures passed')


if __name__ == '__main__':
    main()
