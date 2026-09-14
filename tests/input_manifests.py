#!/usr/bin/env python3
"""Generate typed input modules and check them into a project without touching its sources."""
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
        signatures = set()
        for signed in (True, False):
            for width in (8, 16, 32, 64):
                ty = ('i' if signed else 'u') + str(width)
                limits = (-(1 << (width - 1)), (1 << (width - 1)) - 1) if signed else (0, (1 << width) - 1)
                for label, value in zip(('low', 'high'), limits):
                    name = f'{label}_{ty}'
                    entries.append({'name': name, 'type': ty, 'value': str(value)})
                    literal = str(value) + ('' if ty == 'i64' else ty)
                    conditions.append(f'v.{name}() == {literal}')
                    signatures.add((f'config.values::{name}', ty))
        for name, value, literal in (('enabled', 'true', 'True'), ('disabled', 'false', 'False')):
            entries.append({'name': name, 'type': 'bool', 'value': value})
            conditions.append(f'v.{name}() == {literal}')
            signatures.add((f'config.values::{name}', 'bool'))
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
        entry.write_text('module main\nimport config.values as v\n\n\ndef main() -> i64:\n    if ' +
                         ' and '.join(conditions) + ':\n        return 7\n    return 0\n')
        # The generated module is ordinary source: building and running the project natively
        # is what proves every integer-width extreme and both booleans survive generation.
        executed = subprocess.run([compiler, 'run-project', str(entry), '--print-result'],
                                  text=True, capture_output=True, timeout=300)
        assert executed.returncode == 0 and executed.stdout == '7\n', executed.stderr

        def schema(status=0, *extra):
            result = subprocess.run([compiler, 'schema-project', str(entry), f'--inputs={manifest}', *extra],
                                    text=True, capture_output=True, timeout=90)
            assert result.returncode == status, (result.returncode, result.stderr)
            if status:
                assert result.stdout == ''
            return result

        # A declared input is checked in place of the module's file, so a stale file is
        # ignored and a missing one is supplied -- and neither is written back to disk.
        source.write_text('deliberately stale invalid generated source')
        declared = json.loads(schema().stdout)
        assert source.read_text() == 'deliberately stale invalid generated source'
        source.unlink()
        config.rmdir()
        assert json.loads(schema().stdout) == declared
        assert not source.exists()
        # The checked schema names every generated export with the type the manifest declared.
        assert {(f['name'], f['result']) for f in declared['functions'] if f['name'].startswith('config.values::')} == signatures
        report = json.loads(schema(0, '--schema-report').stdout)
        generated_input = next(s for s in report['source']['sources'] if s['module'] == 'config.values')
        assert generated_input['sha256'] == hashlib.sha256(generate().stdout.encode()).hexdigest()
        assert generated_input['path'] == 'config/values.my'
        assert schema(2, f'--inputs={manifest}').stdout == ''
        original_entry = entry.read_text()
        entry.write_text('module main\n\n\ndef main() -> i64:\n    return 0\n')
        assert 'not imported' in schema(2).stderr
        entry.write_text(original_entry)
        document['module'] = 'main'
        manifest.write_text(json.dumps(document))
        assert 'not the entry module' in schema(2).stderr
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

        bindings = []
        for i in range(17):
            file = root / f'data{i}.json'
            file.write_text(json.dumps({'version': 1, 'module': f'data.m{i}',
                                        'values': [{'name': 'value', 'type': 'i64', 'value': str(i)}]}))
            bindings.append(file)

        def multi_entry(count):
            entry.write_text('module main\n' + ''.join(f'import data.m{i}\n' for i in range(count)) +
                             '\n\ndef main() -> i64:\n    return ' +
                             ' + '.join(f'm{i}.value()' for i in range(count)) + '\n')

        def multi(files, status=0, *extra):
            command = [compiler, 'schema-project', str(entry), *[f'--inputs={file}' for file in files], *extra]
            result = subprocess.run(command, text=True, capture_output=True, timeout=90)
            assert result.returncode == status, (result.returncode, result.stderr)
            if status:
                assert result.stdout == ''
            return result

        multi_entry(16)
        ordered = json.loads(multi(bindings[:16]).stdout)
        reversed_inputs = json.loads(multi(list(reversed(bindings[:16]))).stdout)
        assert ordered == reversed_inputs, 'binding flag order changed the schema'
        assert len(ordered['functions']) == 16
        report = json.loads(multi(bindings[:16], 0, '--schema-report').stdout)
        assert len(report['source']['sources']) == 17
        assert 'usage:' in multi(bindings, status=2).stderr
        duplicate = root / 'duplicate.json'
        duplicate.write_bytes(bindings[0].read_bytes())
        assert 'duplicate input module data.m0' in multi([bindings[0], duplicate], status=2).stderr
        multi_entry(8)
        for file in bindings[:9]:
            data = file.read_bytes()
            file.write_bytes(data + b' ' * (1024 * 1024 - len(data)))
        assert len(json.loads(multi(bindings[:8]).stdout)['functions']) == 8
        assert 'byte budget exceeded' in multi(bindings[:9], status=2).stderr
        main_bytes = b'module main\n\n\ndef main() -> i64:\n    return 0\n'
        entry.write_bytes(main_bytes + b' ' * (4 * 1024 * 1024 - len(main_bytes)))
        assert multi([]).returncode == 0
        with entry.open('ab') as stream:
            stream.write(b' ')
        assert 'E_PROJECT_BYTES' in multi([], status=1).stderr
        print('typed input manifests: deterministic generation, source digest, all integer width extrema, '
              'booleans, native execution of the generated module, checked declared inputs over untouched '
              'sources, strict JSON/duplicate/path/value rejection, and budgets passed')


if __name__ == '__main__':
    main()
