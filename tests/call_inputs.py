#!/usr/bin/env python3
"""Check declared inputs across schema receipts, binding reuse, and fresh Python calls."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='mylang-call-inputs-') as directory:
        root = Path(directory)
        entry, manifest, output = (root / name for name in ('main.my', 'inputs.json', 'bindings.py'))
        entry.write_text('module main; import config; export read; fn read()->i64{return i64(config::value());} fn main()->i64{return 0;}')

        def write(value, ty='i64', module='config'):
            manifest.write_text(json.dumps({'version': 1, 'module': module, 'values': [{'name': 'value', 'type': ty, 'value': str(value)}]}))

        def generate(expected=0, extra=()):
            args = [sys.executable, str(ROOT / 'scripts/bindings.py'), str(entry), '--compiler', compiler,
                    '--output', str(output), '--cache-dir', str(root / 'cache'), '--inputs', str(manifest), *extra]
            result = subprocess.run(args, capture_output=True, text=True, timeout=30)
            assert result.returncode == expected, result.stderr
            return json.loads(result.stdout) if expected == 0 else result.stderr

        write(7)
        first = generate()
        assert first['cache'] == 'miss'
        assert not (root / 'config.my').exists()
        spec = importlib.util.spec_from_file_location('input_bindings', output)
        bindings = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = bindings
        spec.loader.exec_module(bindings)
        selected_inputs = [manifest]
        client = bindings.Client(compiler, entry, inputs=selected_inputs)
        selected_inputs.clear()
        assert client.call('main::read') == 7
        source_receipt = first['schema_source_sha256']
        identity = first['schema_sha256']
        inode = output.stat().st_ino
        write(9)
        assert client.call('main::read') == 9
        warm = generate()
        assert warm['cache'] == 'hit' and warm['generation'] == 'skipped'
        assert warm['schema_sha256'] == identity and warm['schema_source_sha256'] != source_receipt
        assert output.stat().st_ino == inode
        write(9, 'u8')
        try:
            client.call('main::read')
        except bindings.CallError as error:
            assert 'InvocationSchemaMismatch' in error.diagnostics
        else:
            raise AssertionError('changed input type must invalidate generated call schema')
        assert generate()['cache'] == 'miss'
        write(9)
        original = manifest.read_bytes()
        assert 'cannot replace an input manifest' in generate(2, ['--output', str(manifest)])
        assert manifest.read_bytes() == original
        assert 'distinct manifest paths' in generate(2, ['--inputs', str(manifest)])
        for bad in ([manifest, manifest], [manifest] * 17, str(manifest)):
            try:
                bindings.Client(compiler, entry, inputs=bad)
            except bindings.CodecError as error:
                assert error.code == 'InvalidCallInputs'
            else:
                raise AssertionError('invalid input selection accepted')
        manifest.write_text('{}')
        assert 'MissingField' in generate(2)
        try:
            client.call('main::read')
        except bindings.CallError as error:
            assert error.returncode == 2 and 'MissingField' in error.diagnostics
        else:
            raise AssertionError('malformed fresh input ignored')
        write(9, module='unused')
        assert generate(1)
    print('Call inputs: in-memory schema generation, fresh values/receipts, schema changes, artifact reuse, invalid inputs and manifest preservation passed')


if __name__ == '__main__':
    main()
