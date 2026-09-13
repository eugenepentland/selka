#!/usr/bin/env python3
"""Offline dependency locks reject drift, collisions and namespace/version ambiguity."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='package-tests-') as directory:
        root = Path(directory)
        library = root / 'library'
        library.mkdir()
        lib = library / 'numbers.my'
        source = 'module numbers\nexport answer\n\ndef answer() -> i64:\n    return 42\n'
        lib.write_text(source)
        config, lock, receipt = (root / name for name in ('packages.json', 'lock.json', 'receipt.json'))
        config.write_text(json.dumps({'packages': [{'name': 'numbers', 'root': 'library'}]}))

        def invoke(*arguments, status=0):
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/packages.py'), *map(str, arguments)],
                                    capture_output=True, text=True, timeout=90)
            assert result.returncode == status, (result.stdout, result.stderr)
            return result

        invoke('lock', config, '--output', lock)
        frozen = lock.read_bytes()
        for app in ('app1', 'app2'):
            folder = root / app
            folder.mkdir()
            entry = folder / 'main.my'
            entry.write_text('module main\nimport numbers\n\ndef main() -> i64:\n    return numbers.answer()\n')
            assert invoke('build', entry, '--lock', lock, '--compiler', compiler,
                          '--command', 'run-project', '--receipt', receipt).stdout == '42\n'
            report = json.loads(receipt.read_text())
            assert report['version'] == 'package-build-v1'
            assert 'dependencies' in report
            assert list(folder.iterdir()) == [entry]
        lib.write_text(source.replace('42', '43'))
        assert 'changed' in invoke('build', entry, '--lock', lock, '--compiler', compiler, status=2).stderr
        assert lock.read_bytes() == frozen
        lib.write_text(source)
        (entry.parent / 'numbers.my').write_text(source)
        assert 'duplicate' in invoke('build', entry, '--lock', lock, '--compiler', compiler, status=2).stderr
        (entry.parent / 'numbers.my').unlink()
        manifest = json.loads(frozen)
        manifest['packages'] *= 2
        lock.write_text(json.dumps(manifest))
        assert 'incompatible' in invoke('build', entry, '--lock', lock, '--compiler', compiler, status=2).stderr
        lock.write_bytes(frozen)
        lib.unlink()
        lib.symlink_to(entry)
        assert invoke('build', entry, '--lock', lock, '--compiler', compiler, status=2).stderr
    print('offline package lock checks passed')


if __name__ == '__main__':
    main()
