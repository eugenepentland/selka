#!/usr/bin/env python3
"""Exercise schema-pinned public calls using independent JSON requests through the CLI."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    fixture = Path(__file__).resolve().parents[1] / 'examples/domain-codecs/data.my'
    with tempfile.TemporaryDirectory(prefix='mylang-call-json-') as directory:
        root = Path(directory)
        entry = root / 'main.my'
        module = root / 'data.my'
        path = root / 'request.json'
        entry.write_text('module main;import data;fn main()->i64{return 0;}')
        source = fixture.read_text().replace('module data;', 'module data; export shift; export zero; export unsigned; export explode; export nodata;')
        source += '''
fn shift(x:Positive,n:i64)->Decoded{return Positive.from_wire(new Wire{n:Positive.to_wire(x).n+n});}
fn zero()->bool{return true;}
fn unsigned(x:u64)->u64{return x;}
fn explode(x:i64)->i64{return x/0;}
fn nodata()->unit{}
fn hidden()->i64{return 9;}
'''
        module.write_text(source)
        schema_run = subprocess.run([compiler, 'schema-project', str(entry)], capture_output=True, text=True, timeout=30)
        assert schema_run.returncode == 0, schema_run.stderr
        schema = json.loads(schema_run.stdout)
        # This is the generated Python binding's canonical schema identity, computed
        # independently from parsed JSON rather than copying an internal request ID.
        schema_hash = hashlib.sha256(json.dumps(schema, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()

        def write(name, arguments):
            request = {'version': 'typed-call-v1', 'schema_sha256': schema_hash, 'function': name, 'arguments': arguments}
            path.write_text(json.dumps(request, separators=(',', ':')))
            return request

        def run(expected=0, flags=()):
            result = subprocess.run([compiler, 'invoke-project', str(entry), '--request=' + str(path), *flags], capture_output=True, text=True, timeout=30)
            assert result.returncode == expected, (result.returncode, expected, result.stderr)
            if expected:
                assert not result.stdout
                return result.stderr
            return json.loads(result.stdout)

        write('data::shift', {'n': '5', 'x': {'n': '7'}})
        output = run()
        assert output == {'version': 'typed-json-v1', 'type': 'data::Decoded', 'value': {'case': 'ok', 'value': {'n': '12'}}}
        assert run() == output
        assert run(0, ['--max-codec-calls=3']) == output
        for flag, code in (
            ('--max-codec-calls=1', 'CodecCallLimit'),
            ('--max-codec-calls=2', 'CodecCallLimit'),
            ('--max-codec-steps=1', 'R_STEP_LIMIT'),
            ('--max-codec-frames=1', 'R_FRAME_LIMIT'),
            ('--max-codec-bytes=1', 'CodecMemoryLimit'),
            ('--max-codec-values=1', 'CodecWorkLimit'),
        ):
            assert code in run(1, [flag])
        # Target result errors are successful typed outputs; argument decoder
        # rejection is an invocation failure with a named-argument JSON pointer.
        write('data::shift', {'x': {'n': '7'}, 'n': '-10'})
        assert run()['value'] == {'case': 'err', 'value': '-1'}
        write('data::shift', {'x': {'n': '0'}, 'n': '5'})
        rejection = run(1)
        assert 'DomainCodecRejected' in rejection and '"/arguments/x"' in rejection and 'codec rejection:' in rejection
        write('data::shift', {'x': {'n': True}, 'n': '5'})
        assert '"/arguments/x/n"' in run(1)
        for arguments in ({}, [], {'wrong': {'n': '0'}, 'n': '5'}, {'x': {'n': '7'}, 'n': '5', 'extra': True}):
            write('data::shift', arguments)
            assert 'InvocationArguments' in run(1)
        for name, arguments, code in (
            ('data::hidden', {}, 'UnknownPublicFunction'),
            ('main::main', {}, 'UnknownPublicFunction'),
            ('data::Positive.raw', {'x': '1'}, 'UnknownPublicFunction'),
            ('data::nodata', {}, 'NotDataType'),
            ('data::explode', {'x': '1'}, 'InvocationTrap'),
        ):
            write(name, arguments)
            message = run(1)
            assert code in message and '"/function"' in message
            if name.endswith('explode'):
                assert 'R_DIVISION_BY_ZERO' in message and 'data.my:' in message and 'data::explode' in message
        write('data::unsigned', {'x': '18446744073709551615'})
        assert run() == {'version': 'typed-json-v1', 'type': 'u64', 'value': '18446744073709551615'}
        write('data::zero', {})
        assert run()['value'] is True
        module.write_text(source.replace('fn zero()->bool{return true;}', 'fn zero()->bool{return false;}'))
        assert run()['value'] is False  # same schema, freshly checked changed implementation
        module.write_text(source.replace('fn zero()->bool{return true;}', 'fn zero()->i64{return 0;}'))
        assert 'InvocationSchemaMismatch' in run(1)
        module.write_text(source + 'fn broken()->i64{return true;}')
        assert 'E_TYPE' in run(1)
        module.write_text(source)
        original = write('data::shift', {'x': {'n': '0'}, 'n': '5'})
        stale = dict(original, schema_sha256='0' * 64)
        path.write_text(json.dumps(stale))
        assert 'InvocationSchemaMismatch' in run(1)  # before the invalid domain argument
        for changed, code in (
            (dict(original, version='typed-call-v2'), 'UnsupportedInvocationVersion'),
            (dict(original, extra=True), 'UnknownField'),
        ):
            path.write_text(json.dumps(changed))
            assert code in run(1)
        write('data::shift', {'x': {'n': '7'}, 'n': '5'})
        path.write_text(path.read_text().replace('"n":"5"', '"n":"5","\\u006e":"6"'))
        assert 'DuplicateField' in run(1)
        write('data::zero', {})
        for flags in (['--value=' + str(path)], ['--request=' + str(path)], ['--max-codec-calls=0'], ['--max-codec-steps=1', '--max-codec-steps=2']):
            run(2, flags)
        missing = subprocess.run([compiler, 'invoke-project', str(entry)], capture_output=True)
        assert missing.returncode == 2 and not missing.stdout
        raw = path.read_text()
        path.write_text(raw + ' ' * (1024 * 1024 - len(raw)))
        assert run()['value'] is True
        path.write_text(path.read_text() + ' ')
        assert 'CodecByteLimit' in run(1)
    print('JSON call acceptance: independent schema pins, named arguments, domain codecs, typed errors, zero-argument/u64 calls, shared budgets, paths/traces, schema/body edits, rejection and CLI limits passed')


if __name__ == '__main__':
    main()
