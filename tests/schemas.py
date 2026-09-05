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
    with tempfile.TemporaryDirectory(prefix='mylang-schema-') as temporary:
        root = Path(temporary)
        entry = root / 'main.my'
        entry.write_text('module main; import data; import other; fn main() -> i64 { return 0; }')
        other = root / 'other.my'
        other.write_text('module other; export Point; struct Point { x: bool }')
        data = root / 'data.my'
        source = '''module data;
export Point; export Status; export Choice; export Outcome; export Identity;
export Nodes; export NodeId; export Node; export Bytes; export File;
export view; export reference; export sample;
struct Point { x: u64, y: [2]bool, table: [Status]u16 }
enum Status { ready, failed }
union Choice { empty, point: Point }
result Outcome { ok: Choice, err: Status }
domain Identity: i8 { private fn raw(x: i8) -> Identity { return wrap<Identity>(x); } }
pool Nodes(NodeId): Node;
struct Node { next: NodeId }
buffer Bytes: u8;
resource File: filesystem;
fn view(x: &mut []Point) -> &mut []Point from x { return x; }
fn reference(x: &Point) -> &Point from x { return x; }
result Time { ok: i64, err: i64 }
fn sample(clock: clock_cap) -> i64 { match clock_now<Time>(clock) { Time.ok(x) => { return x; }, Time.err(code) => { return code; } } }
struct Hidden { secret: i32 }
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
        assert not any(x in raw for x in ('Hidden', 'secret', '.raw', '"i8"', '"i32"', 'data::Time', 'type#'))
        assert types['data::Identity']['opaque'] and 'element' not in types['data::Identity']
        assert types['data::Point']['fields'] == [
            {'name': 'x', 'type': 'u64'}, {'name': 'y', 'type': '[2]bool'}, {'name': 'table', 'type': '[data::Status]u16'}]
        assert types['other::Point']['fields'] == [{'name': 'x', 'type': 'bool'}]
        assert types['[2]bool']['length'] == 2
        assert types['[data::Status]u16']['key'] == 'data::Status'
        assert types['data::Choice']['cases'] == [{'name': 'empty'}, {'name': 'point', 'payload': 'data::Point'}]
        assert types['data::Outcome']['kind'] == 'result' and types['data::Outcome']['requires_handling']
        assert types['u64']['maximum'] == '18446744073709551615'
        assert types['i64']['minimum'] == '-9223372036854775808'
        assert types['data::Nodes']['element'] == 'data::Node'
        assert types['data::Nodes']['handle'] == 'data::NodeId'
        assert types['data::NodeId']['pool'] == 'data::Nodes'
        assert types['data::Bytes']['opaque'] and types['data::Bytes']['move_only']
        assert types['data::File']['authority'] == 'filesystem'
        assert types['clock_cap']['opaque']
        assert functions['data::sample']['effects'] == ['clock']
        assert functions['data::view']['parameters'] == [{'name': 'x', 'type': 'data::Point', 'mode': 'exclusive_slice'}]
        assert functions['data::view']['return_reference'] == {'parameter': 0, 'mutable': True, 'slice': True}
        assert functions['data::reference']['parameters'][0]['mode'] == 'shared_reference'
        for definition in types.values():
            for key in ('element', 'key', 'handle', 'pool'):
                if key in definition:
                    assert definition[key] in types
            for field in definition.get('fields', []):
                assert field['type'] in types
            for case in definition.get('cases', []):
                if 'payload' in case:
                    assert case['payload'] in types
        # Private declaration order, source comments, and import discovery order
        # do not change the public contract or expose internal numeric type IDs.
        data.write_text(source.replace('struct Hidden { secret: i32 }', '// changed\nstruct Secret { bits: i32 }'))
        entry.write_text('module main; import other as o; import data as d; fn main() -> i64 { return 1; }')
        assert run() == raw
        data.write_text(source.replace('y: [2]bool', 'y: [3]bool'))
        assert run() != raw
        # Every body must check, including an unexported and uncalled function.
        data.write_text(source + 'fn broken() -> i64 { return true; }')
        assert 'E_TYPE' in run(1)
        data.write_text(source.replace('x: u64, y:', 'x: u64, x:'))
        assert 'duplicate' in run(1).lower()
        data.write_text(source.replace('export Point;', ''))
        assert 'E_PRIVATE_INTERFACE' in run(1)
        data.write_text(source)
        run(2, '--evaluation-request')
        # An empty public interface remains empty even though main uses integers.
        entry.write_text('module main; fn main() -> i64 { return 0; }')
        empty = json.loads(run())
        assert empty['exports'] == empty['functions'] == empty['types'] == []
    print('schema acceptance: public structure, nominal identity, privacy, cyclic handle graph, effects, borrowing, determinism, and rejection passed')


if __name__ == '__main__':
    main()
