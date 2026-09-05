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
        entry.write_text('module main; import data; fn main() -> i64 { return 0; }')
        source = '''module data;
export Point; export Flag; export Choice; export Outcome; export Empty;
export Secret; export Maybe; export Bytes; export File; export Pool; export Handle;
export Zero;
struct Point { x: u64, flags: [Flag]bool, samples: [2]i16 }
enum Flag { yes, no }
union Choice { none, point: Point }
result Outcome { ok: Choice, err: i8 }
struct Empty {}
domain Secret: i64 { fn make(x: i64) -> Secret { return wrap<Secret>(x); } }
union Maybe { none, some: Secret }
struct Zero { data: [0]Secret }
buffer Bytes: u8;
resource File: filesystem;
pool Pool(Handle): i64;
struct Private { hidden: bool }
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

        def reject(ty, value, code):
            path.write_text(json.dumps({'version': 'typed-json-v1', 'type': ty, 'value': value}))
            assert code in run(1)

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
        reject('data::Choice', {'case': 'other'}, 'UnknownCodecCase')
        reject('data::Choice', {'case': 'none', 'value': None}, 'UnexpectedCodecField')
        reject('data::Choice', {'case': 'point'}, 'IncompleteCodecValue')
        reject('data::Choice', {'case': 'point', 'value': point, 'extra': 0}, 'UnexpectedCodecField')
        reject('data::Point', {**point, 'extra': 0}, 'UnexpectedCodecField')
        reject('data::Point', {key: value for key, value in point.items() if key != 'x'}, 'IncompleteCodecValue')
        reject('data::Point', {**point, 'samples': ['1']}, 'IncompleteCodecValue')
        reject('data::Point', {**point, 'flags': {'yes': True}}, 'IncompleteCodecValue')
        reject('data::Point', {**point, 'flags': {'yes': True, 'maybe': False}}, 'IncompleteCodecValue')
        for ty, value in [('Secret', '1'), ('Maybe', {'case': 'none'}), ('Zero', {'data': []}), ('Bytes', []), ('File', '1'), ('Pool', []), ('Handle', '1')]:
            reject('data::' + ty, value, 'NoImplicitCodec')
        reject('allocator', '1', 'NoImplicitCodec')
        reject('data::Private', {'hidden': True}, 'UnknownPublicValueType')
        reject('missing::Point', point, 'UnknownPublicValueType')
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
        module.write_text('module data; export Big; struct Big { data: [65534]bool }')
        check('data::Big', {'data': [True] * 65534})
        module.write_text('module data; export Big; struct Big { data: [65535]bool }')
        reject('data::Big', {'data': [True] * 65535}, 'CodecValueLimit')
        for count in (63, 64):
            declarations = ' '.join(f'struct R{i} {{ next: ' + (f'R{i+1}' if i + 1 < count else 'bool') + ' }' for i in range(count))
            module.write_text('module data; ' + ' '.join(f'export R{i};' for i in range(count)) + ' ' + declarations)
            value = True
            for _ in range(count):
                value = {'next': value}
            if count == 63:
                check('data::R0', value)
            else:
                reject('data::R0', value, 'CodecDepthLimit')
        module.write_text(source)
        check('data::Point', point)
        module.write_text(source.replace('x: u64, flags:', 'x: u64, added: bool, flags:'))
        assert 'IncompleteCodecValue' in run(1)
        module.write_text(source + 'fn invalid() -> i64 { return true; }')
        assert 'E_TYPE' in run(1)
        module.write_text(source)
        run(2, ['--evaluation-request'])
        run(2, ['--value=' + str(path)])
        path.unlink()
        run(2)
    print('typed JSON acceptance: scalar ranges, aggregate/variant/table round trips, nominal visibility, opaque rejection, strict keys, byte/value/depth boundaries, schema changes, and CLI failures passed')


if __name__ == '__main__':
    main()
