#!/usr/bin/env python3
"""Execute generated Python data bindings against the compiler's typed JSON codec."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bindings_generator', ROOT / 'scripts/bindings.py')
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='mylang-python-bindings-') as temporary:
        root = Path(temporary)
        entry = root / 'main.my'
        data = root / 'data.my'
        peer = root / 'peer.my'
        output = root / 'bindings.py'
        value_file = root / 'value.json'
        entry.write_text('module main; import data; import peer; fn main() -> i64 { return 0; }')
        peer.write_text('module peer; export Point; struct Point { x: u64 }')
        source = '''module data;
export Point; export Flag; export Choice; export Outcome; export Empty;
export Weird; export Signed; export Unsigned; export Opaque; export Maybe;
export Large;
struct Point { x: u64, flags: [Flag]bool, samples: [2]i16 }
enum Flag { yes, no }
union Choice { none, point: Point }
result Outcome { ok: Choice, err: i8 }
struct Empty {}
struct Weird { class: i8, __dict__: bool, f_x: i8, f_x5fx: bool }
struct Signed { a: i8, b: i16, c: i32, d: i64 }
struct Unsigned { a: u8, b: u16, c: u32, d: u64 }
domain Opaque: i64 { fn make(x: i64) -> Opaque { return wrap<Opaque>(x); } }
union Maybe { none, some: Opaque }
struct Large { values: [65534]bool }
struct Hidden { private_data: bool }
'''
        data.write_text(source)

        def generate(expected=0, flags=()):
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/bindings.py'), str(entry), '--compiler', compiler,
                                     '--output', str(output), *flags], capture_output=True, text=True, timeout=30)
            assert result.returncode == expected, (result.returncode, result.stderr)
            if expected:
                assert not result.stdout
                return result.stderr
            return json.loads(result.stdout)

        report = generate()
        original = output.read_bytes()
        assert report['sha256'] == hashlib.sha256(original).hexdigest()
        assert report['bytes'] == len(original)
        assert report['unsupported_types'] == ['data::Maybe', 'data::Opaque']
        assert 'Hidden' not in original.decode()
        assert generate() == report and output.read_bytes() == original
        # Private bodies, comments, aliases, and import order do not change bindings.
        data.write_text(source + '\n// private change\nfn unused() -> i64 { return 3; }')
        entry.write_text('module main; import peer as p; import data as d; fn main() -> i64 { return 1; }')
        assert generate() == report and output.read_bytes() == original
        bindings = load_module(output, 'generated_bindings_acceptance')
        assert bindings.SCHEMA_SHA256 == report['schema_sha256']
        assert bindings.GENERATOR_SHA256 == report['generator_sha256']
        assert bindings.TYPES['data::Point'] is not bindings.TYPES['peer::Point']
        assert bindings.FIELDS['data::Weird'] == {'class': 'f_class', '__dict__': 'f__x5f_x5fdict_x5f_x5f', 'f_x': 'f_f_x5fx', 'f_x5fx': 'f_f_x5fx5fx'}
        try:
            bindings.TYPES['new'] = bool
        except TypeError:
            pass
        else:
            raise AssertionError('public type registry is mutable')
        for name in ('data::Opaque', 'data::Maybe'):
            assert name not in bindings.TYPES
        comparisons = 0

        def compiler_check(text, expected=0):
            value_file.write_text(text)
            result = subprocess.run([compiler, 'check-value-project', str(entry), '--value=' + str(value_file)], capture_output=True, text=True, timeout=30)
            assert result.returncode == expected, (result.returncode, result.stderr)
            if expected:
                assert not result.stdout
            return result.stdout

        def parity(ty, wire):
            nonlocal comparisons
            text = json.dumps({'version': 'typed-json-v1', 'type': ty, 'value': wire})
            native = bindings.loads(text, expected_type=ty)
            encoded = bindings.dumps(native, type_name=ty)
            canonical = compiler_check(text)
            assert encoded == canonical, (ty, encoded, canonical)
            assert compiler_check(encoded) == encoded
            assert bindings.dumps(bindings.loads(canonical), type_name=ty) == canonical
            comparisons += 1
            return native

        for signed in (True, False):
            for width in (8, 16, 32, 64):
                ty = ('i' if signed else 'u') + str(width)
                for number in ((-(1 << (width - 1)) if signed else 0), (1 << (width - (1 if signed else 0))) - 1):
                    assert parity(ty, str(number)) == number
        for value in (True, False):
            assert parity('bool', value) is value
        for case in ('yes', 'no'):
            parity('data::Flag', case)
        parity('data::Empty', {})
        parity('data::Weird', {'class': '-128', '__dict__': True, 'f_x': '1', 'f_x5fx': False})
        point = {'samples': ['-32768', '32767'], 'flags': {'no': False, 'yes': True}, 'x': '18446744073709551615'}
        native = parity('data::Point', point)
        assert native.f_x == (1 << 64) - 1
        assert native.f_samples == (-32768, 32767)
        Flag = bindings.TYPES['data::Flag']
        assert native.f_flags[Flag.v_yes] is True
        try:
            native.f_x = 0
        except AttributeError:
            pass
        else:
            raise AssertionError('record fields are mutable')
        try:
            native.f_flags[Flag.v_no] = True
        except TypeError:
            pass
        else:
            raise AssertionError('decoded table is mutable')
        for wire in ({'case': 'none'}, {'case': 'point', 'value': point}):
            value = parity('data::Choice', wire)
            assert isinstance(value, bindings.TYPES['data::Choice'])
        for wire in ({'case': 'ok', 'value': {'case': 'point', 'value': point}}, {'case': 'err', 'value': '-128'}):
            parity('data::Outcome', wire)
        # Independently constructed host values cross into the compiler codec.
        constructed = bindings.TYPES['data::Point'](f_x=7, f_flags={Flag.v_yes: False, Flag.v_no: True}, f_samples=(3, 4))
        variant = bindings.CASES['data::Choice']['point'](constructed)
        text = bindings.dumps(variant)
        assert compiler_check(text) == text
        assert json.loads(text)['value']['value']['x'] == '7'
        comparisons += 1
        parity('data::Large', {'values': [True] * 65534})

        def reject(ty, wire):
            text = json.dumps({'version': 'typed-json-v1', 'type': ty, 'value': wire})
            compiler_check(text, 1)
            try:
                bindings.loads(text)
            except bindings.CodecError:
                return
            raise AssertionError(('binding accepted compiler rejection', text))

        for ty, wire in [('u8', '-1'), ('u8', '256'), ('i64', True), ('i64', 1), ('bool', 'true'), ('i64', '-0'), ('i64', '01'), ('i64', '+1'),
                         ('data::Flag', 'unknown'), ('data::Choice', {'case': 'none', 'value': None}), ('data::Choice', {'case': 'point'}),
                         ('data::Point', {**point, 'extra': True}), ('data::Point', {**point, 'samples': ['1']}),
                         ('data::Maybe', {'case': 'none'}), ('data::Opaque', '1'), ('data::Hidden', {'private_data': True})]:
            reject(ty, wire)
        for raw in (
            '{"version":"typed-json-v1","type":"bool","value":true,"value":false}',
            '{"version":"typed-json-v1","type":"data::Empty","value":{"x":true,"\\u0078":false}}',
            '{"version":"typed-json-v1","type":"bool","value":"\\ud800"}',
            '{"version":"typed-json-v1","type":"bool","value":NaN}',
        ):
            compiler_check(raw, 1)
            try:
                bindings.loads(raw)
            except bindings.CodecError:
                pass
            else:
                raise AssertionError('accepted malformed JSON')
        # Validate native types, including Python bool/int and nominal confusion.
        for value, ty in [(True, 'i64'), (256, 'u8'), (native, 'peer::Point'), (Flag.v_yes, 'bool'),
                          (bindings.TYPES['data::Point'](f_x=True, f_flags=native.f_flags, f_samples=(1, 2)), 'data::Point')]:
            try:
                bindings.dumps(value, type_name=ty)
            except bindings.CodecError as error:
                if ty == 'data::Point':
                    assert error.path == '/value/x'
            else:
                raise AssertionError('accepted invalid host value')
        raw = bindings.dumps(native)
        assert bindings.dumps(native, limits=bindings.Limits(max_bytes=len(raw))) == raw
        for operation in (
            lambda: bindings.dumps(native, limits=bindings.Limits(max_bytes=len(raw) - 1)),
            lambda: bindings.loads(raw, limits=bindings.Limits(max_bytes=len(raw) - 1)),
            lambda: bindings.dumps(native, type_name=[]),
            lambda: bindings.loads(raw, limits=bindings.Limits(max_values=1)),
            lambda: bindings.loads(raw, limits=bindings.Limits(max_tokens=1)),
            lambda: bindings.loads(raw, limits=bindings.Limits(max_depth=1)),
            lambda: bindings.loads(raw, expected_type='peer::Point'),
        ):
            try:
                operation()
            except bindings.CodecError:
                pass
            else:
                raise AssertionError('budget/type expectation ignored')
        # Escaped/plain names must follow identical wire semantics.
        escaped = json.dumps({'version': 'typed-json-v1', 'type': 'data::Flag', 'value': 'yes'}).replace('yes', '\\u0079e\\u0073')
        assert bindings.dumps(bindings.loads(escaped)) == compiler_check(escaped)
        # Generated module imports and executes with only its own directory and stdlib.
        result = subprocess.run([sys.executable, '-I', '-c', 'import runpy; b=runpy.run_path(' + repr(str(output)) + '); assert b["loads"](' + repr('{"version":"typed-json-v1","type":"bool","value":true}') + ') is True'], capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stderr
        # Generator failures preserve the existing file, and atomic failures clean up.
        data.write_text(source + 'fn broken() -> i64 { return true; }')
        assert 'E_TYPE' in generate(1)
        assert output.read_bytes() == original
        data.write_text(source)
        generate(2, ['--max-schema-bytes=1'])
        generate(2, ['--max-output-bytes=1'])
        assert output.read_bytes() == original
        with patch.object(generator.os, 'replace', side_effect=OSError('injected failure')):
            try:
                generator.store(output, b'changed')
            except OSError:
                pass
            else:
                raise AssertionError('atomic write failure swallowed')
        assert output.read_bytes() == original and not list(root.glob('.bindings-*'))
        # A confirmed child is reaped when the schema time/capture budget expires.
        fake = root / 'slow-compiler'
        pid_file = root / 'child.pid'
        for flood in (False, True):
            fake.write_text('#!' + sys.executable + '\nimport os, time\nfrom pathlib import Path\nPath(' + repr(str(pid_file)) + ').write_text(str(os.getpid()))\n' + ('os.write(1, b"x" * 65536)\n' if flood else '') + 'time.sleep(10)\n')
            fake.chmod(0o700)
            try:
                generator.checked_schema(fake, entry, 1 if flood else 0.1, 128 if flood else 65536)
            except ValueError as error:
                assert ('capture byte limit' if flood else 'timed out') in str(error)
            else:
                raise AssertionError('compiler generation budget ignored')
            if pid_file.exists():
                try:
                    os.kill(int(pid_file.read_text()), 0)
                except ProcessLookupError:
                    pass
                else:
                    raise AssertionError('compiler child survived budget failure')
                pid_file.unlink()
        assert output.read_bytes() == original
        # Public changes regenerate instead of reusing an old snapshot.
        data.write_text(source.replace('x: u64, flags:', 'x: u64, added: bool, flags:'))
        changed = generate()
        assert changed['schema_sha256'] != report['schema_sha256']
        assert output.read_bytes() != original
        print(f'Python bindings acceptance: {comparisons} compiler/Python wire comparisons, independent host construction, nominal/keyword identities, immutable decoding, rejection/budgets, standalone imports, determinism, schema freshness, and atomic failure cleanup passed')


if __name__ == '__main__':
    main()
