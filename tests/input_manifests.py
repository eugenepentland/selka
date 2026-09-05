#!/usr/bin/env python3
"""Generate typed inputs and execute their checked imported values at all widths."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = parser.parse_args().compiler
    with tempfile.TemporaryDirectory(prefix='mylang-input-manifest-') as temporary:
        root = Path(temporary)
        manifest = root / 'inputs.json'
        entries = []
        conditions = []
        for signed in (True, False):
            for width in (8, 16, 32, 64):
                ty = ('i' if signed else 'u') + str(width)
                limits = (-(1 << (width - 1)), (1 << (width - 1)) - 1) if signed else (0, (1 << width) - 1)
                for label, value in zip(('low', 'high'), limits):
                    name = f'{label}_{ty}'
                    entries.append({'name': name, 'type': ty, 'value': str(value)})
                    literal = str(value) + ('' if ty == 'i64' else ty)
                    conditions.append(f'v::{name}()=={literal}')
        for name, value in (('enabled', 'true'), ('disabled', 'false')):
            entries.append({'name': name, 'type': 'bool', 'value': value})
            conditions.append(f'v::{name}()=={value}')
        document = {'version': 1, 'module': 'config.values', 'values': entries}
        manifest.write_text(json.dumps(document))

        def generate(status=0):
            result = subprocess.run([compiler, 'input-module', str(manifest)], text=True, capture_output=True, timeout=90)
            assert result.returncode == status, (result.returncode, result.stderr)
            if status:
                assert result.stdout == ''
            return result

        generated = generate().stdout
        assert generated == generate().stdout
        assert hashlib.sha256(manifest.read_bytes()).hexdigest() in generated
        config = root / 'config'
        config.mkdir()
        source = config / 'values.my'
        source.write_text(generated)
        entry = root / 'main.my'
        entry.write_text('module main; import config.values as v; fn main()->i64{if ' + '&&'.join(conditions) + '{return 7;}return 0;}')
        result = subprocess.run([compiler, 'eval-project', str(entry)], text=True, capture_output=True, timeout=90)
        assert result.returncode == 0 and result.stdout == '7\n', result.stderr
        def evaluate_inputs(status=0, *extra):
            result = subprocess.run([compiler, 'eval-project', str(entry), f'--inputs={manifest}', *extra],
                                    text=True, capture_output=True, timeout=90)
            assert result.returncode == status, (result.returncode, result.stderr)
            if status:
                assert result.stdout == ''
            return result

        source.write_text('deliberately stale invalid generated source')
        assert evaluate_inputs().stdout == '7\n'
        assert source.read_text() == 'deliberately stale invalid generated source'
        source.unlink()
        config.rmdir()
        assert evaluate_inputs().stdout == '7\n'
        assert not source.exists()
        entries[0]['value'] = '-127'
        manifest.write_text(json.dumps(document))
        assert evaluate_inputs().stdout == '0\n'
        entries[0]['value'] = '-128'
        manifest.write_text(json.dumps(document))
        receipt = json.loads(evaluate_inputs(0, '--evaluation-report').stdout)
        generated_now = generate().stdout
        generated_input = next(s for s in receipt['request']['sources'] if s['module'] == 'config.values')
        assert generated_input['sha256'] == hashlib.sha256(generated_now.encode()).hexdigest()
        assert evaluate_inputs(2, f'--inputs={manifest}').stdout == ''
        original_entry = entry.read_text()
        entry.write_text('module main; fn main()->i64{return 0;}')
        assert 'not imported' in evaluate_inputs(2).stderr
        entry.write_text(original_entry)
        document['module'] = 'main'
        manifest.write_text(json.dumps(document))
        assert 'not the entry module' in evaluate_inputs(2).stderr
        document['module'] = 'config.values'
        manifest.write_text(json.dumps(document))
        for bad in ('{"version":1,"version":1,"module":"config","values":[]}',
                    '{"version":1,"module":"config","values":[],"extra":0}',
                    '{"version":1,"module":"../config","values":[]}',
                    '{"version":1,"module":"config","values":[{"name":"x","type":"i64","value":1}]}'):
            manifest.write_text(bad)
            generate(status=2)
        document['values'] = entries + [entries[0]]
        manifest.write_text(json.dumps(document))
        assert 'DuplicateInputName' in generate(status=2).stderr
        document['values'] = [{'name': f'v{i}', 'type': 'i64', 'value': '1'} for i in range(1025)]
        manifest.write_text(json.dumps(document))
        assert 'TooManyInputs' in generate(status=2).stderr
        manifest.write_bytes(b' ' * (1024 * 1024 + 1))
        assert 'ManifestTooLarge' in generate(status=2).stderr
        print('typed input manifests: deterministic generation, source digest, all integer width extrema, '
              'booleans, checked imported evaluation, strict JSON/duplicate/path/value rejection, and budgets passed')


if __name__ == '__main__':
    main()
