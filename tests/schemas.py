#!/usr/bin/env python3
"""Check public schemas against independent expected contracts through the CLI."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='selka-schema-') as temporary:
        root = Path(temporary)
        entry = root / 'main.selka'
        entry.write_text('import data\nimport other\n\nfunc main() -> i64:\n    return 0\n')
        other = root / 'other.selka'
        other.write_text('\n\npublic record Point:\n    x: bool\n')
        data = root / 'data.selka'
        source = '''
import time









public record Point:
    x: u64
    y: FixedArray[bool, 2]
    table: [Status]u16

public enum Status:
    ready
    failed

public enum Choice:
    empty
    point(value: Point)

public result Outcome:
    ok: Choice,
    err: Status

public record Identity:
    value: i8

public record Node:
    next: Identity

public resource File: filesystem

public func copy(x: Point) -> Point:
    return x

result Time:
    ok: i64,
    err: i64

public func sample(clock: Clock) -> i64:
    match time.now(clock):
        case Ok(value):
            return value.unix_nanoseconds
        case Err(_):
            return 0

record Hidden:
    secret: i32
'''
        data.write_text(source)

        def run(expected=0, flag=None):
            result = subprocess.run([compiler, 'schema-project', str(entry)] + ([flag] if flag else []), capture_output=True, text=True, timeout=30)
            assert result.returncode == expected, (result.returncode, result.stderr)
            if expected:
                assert result.stdout == '', result.stdout
                return result.stderr
            return result.stdout

        raw = run()
        assert raw == run()
        document = json.loads(raw)
        assert document['version'] == 'language-schema-v1'
        types = {t['name']: t for t in document['types']}
        functions = {f['name']: f for f in document['functions']}
        assert len(types) == len(document['types'])
        assert list(types) == sorted(types)
        assert list(functions) == sorted(functions)
        assert document['exports'] == sorted(document['exports'])
        assert not any(x in raw for x in ('Hidden', 'secret', '.raw', '"i32"', 'data::Time', 'type#'))
        assert types['data::Identity']['fields'] == [{'name': 'value', 'type': 'i8'}]
        assert types['data::Point']['fields'] == [
            {'name': 'x', 'type': 'u64'}, {'name': 'y', 'type': '[2]bool'}, {'name': 'table', 'type': '[data::Status]u16'}]
        assert types['other::Point']['fields'] == [{'name': 'x', 'type': 'bool'}]
        assert types['[2]bool']['length'] == 2
        assert types['[data::Status]u16']['key'] == 'data::Status'
        assert types['data::Choice']['cases'] == [{'name': 'empty'}, {'name': 'point', 'payload': 'data::Choice.point'}]
        assert types['data::Outcome']['kind'] == 'result' and types['data::Outcome']['requires_handling']
        assert types['u64']['maximum'] == '18446744073709551615'
        assert types['i64']['minimum'] == '-9223372036854775808'
        assert types['data::Node']['fields'][0]['type'] == 'data::Identity'
        assert types['data::File']['authority'] == 'filesystem'
        assert types['clock_cap']['opaque']
        assert functions['data::sample']['parameters'] == [{'name': 'clock', 'type': 'clock_cap', 'mode': 'value'}]
        assert 'effects' not in functions['data::sample']
        assert types['data::Choice.point']['fields'] == [{'name': 'value', 'type': 'data::Point'}]
        assert functions['data::copy']['parameters'] == [{'name': 'x', 'type': 'data::Point', 'mode': 'value'}]
        for definition in types.values():
            for key in ('element', 'key'):
                if key in definition:
                    assert definition[key] in types
            for field in definition.get('fields', []):
                assert field['type'] in types
            for case in definition.get('cases', []):
                if 'payload' in case:
                    assert case['payload'] in types
        # Private declaration order, source comments, and import discovery order
        # do not change the public contract or expose internal numeric type IDs.
        data.write_text(source.replace('record Hidden:\n    secret: i32\n', '# changed\nrecord Secret:\n    bits: i32\n'))
        entry.write_text('import other as o\nimport data as d\n\nfunc main() -> i64:\n    return 1\n')
        assert run() == raw
        data.write_text(source.replace('y: FixedArray[bool, 2]', 'y: FixedArray[bool, 3]'))
        assert run() != raw
        # Every body must check, including an unexported and uncalled function.
        data.write_text(source + '\nfunc broken() -> i64:\n    return True\n')
        assert 'E_TYPE' in run(1)
        data.write_text(source.replace('    x: u64\n    y:', '    x: u64\n    x:'))
        assert 'duplicate' in run(1).lower()
        data.write_text(source.replace('public record Point:', 'record Point:'))
        assert 'E_PRIVATE_INTERFACE' in run(1)
        data.write_text(source)
        run(2, '--evaluation-request')
        # Public record backing is part of the schema; private helpers are not.
        record_source = """public record Positive:
    value: int

func hidden(x: int) -> Positive:
    return Positive(value=x)

public func make(x: int) -> Positive:
    return hidden(x)
"""
        data.write_text(record_source)
        entry.write_text('import data\n\nfunc main() -> i64:\n    return data.make(7).value\n')
        record_raw = run()
        record_schema = json.loads(record_raw)
        record_types = {d['name']: d for d in record_schema['types']}
        assert record_types['data::Positive']['fields'] == [{'name': 'value', 'type': 'i64'}]
        assert not record_types['data::Positive']['opaque']
        assert 'codec' not in record_types['data::Positive']
        assert 'hidden' not in record_raw
        data.write_text(record_source.replace('func hidden', 'func implementation').replace('return hidden(x)', 'return implementation(x)'))
        assert run() == record_raw
        data.write_text(record_source.replace('value: int', 'amount: int').replace('Positive(value=x)', 'Positive(amount=x)'))
        entry.write_text('import data\n\nfunc main() -> i64:\n    return data.make(7).amount\n')
        assert run() != record_raw
        # An empty public interface remains empty even though main uses integers.
        entry.write_text('\n\nfunc main() -> i64:\n    return 0\n')
        empty = json.loads(run())
        assert empty['exports'] == empty['functions'] == empty['types'] == []
    print('schema acceptance: public structure, nominal identity, privacy, cyclic handle graph, capabilities, borrowing, public record structure, determinism, and rejection passed')


if __name__ == '__main__':
    main()
