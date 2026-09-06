#!/usr/bin/env python3
"""Execute generated callable bindings, including domain contracts and transport failures."""
import argparse
from dataclasses import replace
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def load(path):
    spec = importlib.util.spec_from_file_location('generated_calls', path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def fails(kind, code, operation):
    try:
        operation()
    except kind as error:
        assert error.code == code, (error.code, code)
        return error
    raise AssertionError('expected ' + code)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='mylang-python-calls-') as directory:
        root = Path(directory)
        entry, data, output = (root / name for name in ('main.my', 'data.my', 'bindings.py'))
        entry.write_text('module main; import data; fn main()->i64{return 0;}')
        source = (ROOT / 'examples/domain-codecs/data.my').read_text().replace(
            'module data;', 'module data; export shift; export zero; export unsigned; export explode; export view;')
        source += '''
fn shift(x:Positive,n:i64)->Decoded{return Positive.from_wire(new Wire{n:Positive.to_wire(x).n+n});}
fn zero()->bool{return true;}
fn unsigned(x:u64)->u64{return x;}
fn explode(x:i64)->i64{return x/0;}
fn view(x:&i64)->i64{return read_ref(x);}
'''
        data.write_text(source)
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/bindings.py'), str(entry),
                                 '--compiler', compiler, '--output', str(output)], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stderr
        bindings = load(output)
        client = bindings.Client(compiler, entry)
        wire = bindings.CALL_TYPES['data::Wire']
        positive = bindings.CALL_TYPES['data::Positive']
        ok = bindings.CALL_CASES['data::Decoded']['ok']
        err = bindings.CALL_CASES['data::Decoded']['err']
        shift = bindings.CALLS['data::shift']
        assert shift(client, p_x=positive(wire(7)), p_n=5) == ok(positive(wire(12)))
        assert client.call('data::shift', n=-10, x=positive(wire(7))) == err(-1)
        assert bindings.CALLS['data::zero'](client) is True
        assert bindings.CALLS['data::unsigned'](client, p_x=2**64-1) == 2**64-1
        assert bindings.UNSUPPORTED_FUNCTIONS['data::view'] == 'reference boundary'
        assert 'data::view' not in bindings.CALLS
        fails(bindings.CodecError, 'UnsupportedFunction', lambda: client.call('data::view', x=1))
        fails(bindings.CodecError, 'UnknownFunction', lambda: client.call('missing'))
        fails(bindings.CodecError, 'IncompleteCodecValue', lambda: client.call('data::shift', x=positive(wire(7))))
        fails(bindings.CodecError, 'CodecIntegerOutOfRange', lambda: client.call('data::unsigned', x=-1))
        fails(bindings.CodecError, 'ValueTypeMismatch', lambda: shift(client, p_x=wire(7), p_n=1))
        fails(bindings.CodecError, 'NoImplicitCodec', lambda: bindings.dumps(positive(wire(7)), type_name='data::Positive'))
        rejection = fails(bindings.CallError, 'CompilerFailure', lambda: shift(client, p_x=positive(wire(0)), p_n=1))
        assert 'DomainCodecRejected' in rejection.diagnostics and '/arguments/x' in rejection.diagnostics
        trap = fails(bindings.CallError, 'CompilerFailure', lambda: client.call('data::explode', x=1))
        assert 'R_DIVISION_BY_ZERO' in trap.diagnostics
        for field, expected in (('max_steps', 'R_STEP_LIMIT'), ('max_calls', 'CodecCallLimit'),
                                ('max_bytes', 'CodecMemoryLimit'), ('max_work_values', 'CodecWorkLimit')):
            limited = replace(client, limits=replace(client.limits, **{field: 1}))
            failure = fails(bindings.CallError, 'CompilerFailure', lambda: shift(limited, p_x=positive(wire(7)), p_n=5))
            assert expected in failure.diagnostics, failure.diagnostics
        tiny = replace(client, limits=replace(client.limits, json=bindings.Limits(max_bytes=1)))
        fails(bindings.CodecError, 'CodecByteLimit', lambda: tiny.call('data::zero'))
        data.write_text(source.replace('fn zero()->bool{return true;}', 'fn zero()->bool{return false;}'))
        assert client.call('data::zero') is False
        data.write_text(source.replace('fn zero()->bool{return true;}', 'fn zero()->i64{return 0;}'))
        stale = fails(bindings.CallError, 'CompilerFailure', lambda: client.call('data::zero'))
        assert 'InvocationSchemaMismatch' in stale.diagnostics
        data.write_text(source)
        fails(bindings.CallError, 'CompilerIO', lambda: replace(client, compiler=str(root / 'missing')).call('data::zero'))
        fake = root / 'fake compiler'

        def transport(body, code, limits=None):
            fake.write_text('#!' + sys.executable + '\n' + body + '\n')
            fake.chmod(0o700)
            selected = replace(client, compiler=str(fake), limits=limits or client.limits)
            return fails(bindings.CallError, code, lambda: selected.call('data::zero'))

        transport('import time; time.sleep(10)', 'CallTimeout', replace(client.limits, timeout_seconds=0.05))
        transport('print("x" * 8192)', 'CaptureLimit', replace(client.limits, capture_bytes=128))
        diagnostics = []
        fake.write_text('#!' + sys.executable + '\nimport sys; print("failure", file=sys.stderr); sys.exit(2)\n')
        failed = fails(bindings.CallError, 'CompilerFailure', lambda: replace(client, compiler=str(fake), diagnostics=diagnostics.append).call('data::zero'))
        assert failed.returncode == 2 and diagnostics == ['failure\n']
        fake.write_text('#!' + sys.executable + '\nprint(\'{"version":"typed-json-v1","type":"i64","value":"1"}\')\n')
        fails(bindings.CodecError, 'ValueTypeMismatch', lambda: replace(client, compiler=str(fake)).call('data::zero'))
    print('Python calls: generated nominal wrappers, domain validation/results, u64, schema freshness, limits, traps, timeout, capture and transport failures passed')


if __name__ == '__main__':
    main()
