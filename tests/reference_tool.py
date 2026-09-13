#!/usr/bin/env python3
"""Check reference provenance, compiler/source freshness, and useful searchable API output."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    compiler = parser.parse_args().compiler.resolve()
    with tempfile.TemporaryDirectory(prefix='reference-tool-test-') as temporary:
        root = Path(temporary)
        output = root / 'reference'

        def run(*arguments, success=True, executable=compiler):
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/reference.py'), '--compiler', str(executable),
                                     '--output', str(output), *map(str, arguments)], capture_output=True, text=True, timeout=90)
            assert (result.returncode == 0) == success, (result.returncode, result.stdout, result.stderr)
            if success:
                assert len(result.stdout.splitlines()) == 3 and len(result.stdout) < 1500, result.stdout
                assert result.stderr == '', result.stderr
            else:
                assert result.stdout == '' and 'reference:' in result.stderr, result
            return result

        run()
        manifest = json.loads((output / 'manifest.json').read_text())
        features = json.loads((output / 'features.json').read_text())
        schema = json.loads((output / 'schema.json').read_text())
        # The reference pins the compiler's reported identity, not a digest of the executable.
        identity = features['compiler_sha256']
        assert isinstance(identity, str) and len(identity) == 64
        assert identity == manifest['compiler_sha256']
        assert identity == schema['source']['implementation']['compiler_sha256']
        for filename, expected in manifest['artifacts'].items():
            assert hashlib.sha256((output / filename).read_bytes()).hexdigest() == expected
        overview = (output / 'reference.md').read_text()
        api = (output / 'api.md').read_text()
        assert len(overview) < 12000 and 'stored-reference-fields' in overview
        assert 'std_json::' in api and 'std_collections::' in api and 'Generic templates' in api
        # API names come from compiler output, including template signatures, not source regexes.
        assert all(function['name'] in api for function in schema['schema']['functions'])
        assert all(template['name'] in api for template in schema['schema']['generic_templates'])
        initial = {path.name: (path.read_bytes(), path.stat().st_mtime_ns) for path in output.iterdir()}
        run('--check')
        assert initial == {path.name: (path.read_bytes(), path.stat().st_mtime_ns) for path in output.iterdir()}
        (output / 'api.md').write_text(api + '\nchanged\n')
        assert 'artifact changed' in run('--check', success=False).stderr
        (output / 'api.md').write_text(api)

        # Identity is the compiler's own build-time digest, so a padded copy of the same
        # executable is still the same compiler and the reference stays fresh.
        other_compiler = root / 'compiler'
        shutil.copy2(compiler, other_compiler)
        with other_compiler.open('ab') as stream:
            stream.write(b'changed')
        run('--check', executable=other_compiler)
        stale = dict(manifest, compiler_sha256='f' * 64)
        (output / 'manifest.json').write_text(json.dumps(stale, ensure_ascii=False, indent=2) + '\n')
        assert 'compiler identity changed' in run('--check', success=False).stderr

        run('--module', 'std_math')
        small_schema = json.loads((output / 'schema.json').read_text())
        assert [row['module'] for row in small_schema['source']['sources']] == ['std_math', 'reference']
        assert 'std_json::' not in (output / 'api.md').read_text()
        run('--module', 'std_math; import bogus', success=False)
        run('--module', 'std_does_not_exist', success=False)
        # Failed regeneration must leave the preceding reference intact.
        run('--check')

        entry = root / 'main.my'
        entry.write_text('module main; import values; fn main()->i64{return 0;}')
        dependency = root / 'values.my'
        dependency.write_text('module values; export Item; struct Item { value: i64 }')
        run('--entry', entry)
        run('--check')
        dependency.write_text(dependency.read_text() + '\n// private source change\n')
        assert 'stale reference' in run('--check', success=False).stderr
        run('--entry', entry)
        dependency.write_text('module values; export Item; struct Item { value: u64 }')
        assert 'stale reference' in run('--check', success=False).stderr
        run('--entry', entry)
        assert 'values::Item' in (output / 'api.md').read_text()
        dependency.write_text('module values; fn bad()->i64{return true;}')
        assert 'compiler schema-project failed' in run('--check', success=False).stderr
    print('reference tool: pinned embedded stdlib, compact receipt, selected modules, artifact integrity, and compiler/project freshness passed')


if __name__ == '__main__':
    main()
