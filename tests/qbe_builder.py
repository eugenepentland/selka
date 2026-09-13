#!/usr/bin/env python3
"""Exercise real QBE object reuse, cache integrity, and transactional publication."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--zig', required=True)
    parser.add_argument('--qbe', required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='mylang-qbe-builder-') as directory:
        directory = Path(directory)
        source, output, cache = directory / 'source.my', directory / 'program', directory / 'cache'
        command = [sys.executable, str(root / 'scripts/qbe.py'), str(source), '-o', str(output),
                   '--compiler', str(Path(args.compiler).resolve()), '--zig', args.zig,
                   '--qbe', args.qbe, '--cache-dir', str(cache), '--report']

        def build(extra=(), failure=False):
            # Every build starts a new compiler and driver process.
            result = subprocess.run(command + list(extra), capture_output=True, timeout=240)
            if failure:
                assert result.returncode != 0, result.stdout
                return None
            assert result.returncode == 0, result.stderr.decode()
            report = json.loads(result.stdout)
            assert report['version'] == 'qbe-build-v1'
            assert all(report[name] >= 0 for name in ('frontend_seconds', 'codegen_seconds', 'link_seconds'))
            return report

        def keys(report):
            return {unit['name']: unit['key'] for unit in report['functions']}

        source.write_text('def square(x: i64) -> i64:\n    return x * x\n\n\ndef main() -> i64:\n    return square(4)\n')
        first = build()
        assert first['compiled_functions'] == 2 and first['reused_functions'] == 0, first
        assert subprocess.check_output([output]) == b'16\n'
        previous_stat = output.stat()
        repeat = build()
        assert not repeat['output_changed'], repeat
        assert output.stat().st_mtime_ns == previous_stat.st_mtime_ns
        assert repeat['compiled_functions'] == 0 and repeat['reused_functions'] == 2, repeat
        assert keys(first) == keys(repeat)
        source.write_text('def square(x: i64) -> i64:\n    return x * x + 1\n\n\ndef main() -> i64:\n    return square(4)\n')
        edited = build()
        assert edited['compiled_functions'] == 1 and edited['reused_functions'] == 1, edited
        assert sum(keys(first)[name] == key for name, key in keys(edited).items()) == 1
        assert subprocess.check_output([output]) == b'17\n'
        cold_output = directory / 'cold-program'
        cold = build(['--cache-dir', str(directory / 'cold-cache'), '-o', str(cold_output)])
        assert cold['compiled_functions'] == 2, cold
        assert subprocess.check_output([cold_output]) == subprocess.check_output([output])
        source.write_text('# changed order and formatting\ndef main() -> i64:\n    return  square( 4 )\n\n\ndef square( x : i64 ) -> i64:\n    return x*x + 1\n')
        reordered = build()
        assert reordered['compiled_functions'] == 0 and keys(reordered) == keys(edited), reordered
        corrupted = Path(reordered['functions'][0]['object'])
        corrupted.write_bytes(b'corrupt object')
        repaired = build()
        assert repaired['compiled_functions'] == 1 and repaired['reused_functions'] == 1, repaired
        assert subprocess.check_output([output]) == b'17\n'
        Path(repaired['functions'][0]['object']).with_suffix('.sha256').write_bytes(b'\xff')
        metadata_repaired = build()
        assert metadata_repaired['compiled_functions'] == 1, metadata_repaired
        # Removing a definition must remove its object from the current link manifest.
        source.write_text('def main() -> i64:\n    return 19\n')
        deleted = build()
        assert len(deleted['functions']) == 1, deleted
        manifest = json.loads(output.with_name(output.name + '.qbe-manifest.json').read_text())
        assert len(manifest['functions']) == 1
        assert subprocess.check_output([output]) == b'19\n'
        previous = output.read_bytes()
        previous_manifest = output.with_name(output.name + '.qbe-manifest.json').read_bytes()
        source.write_text('def main() -> i64:\n    return True\n')
        build(failure=True)
        assert output.read_bytes() == previous
        assert output.with_name(output.name + '.qbe-manifest.json').read_bytes() == previous_manifest
        source.write_text('def main() -> i64:\n    return 20\n')
        fake_qbe = directory / 'failing-qbe'
        fake_qbe.write_text('#!/bin/sh\nexit 1\n')
        fake_qbe.chmod(0o700)
        build(['--qbe', str(fake_qbe)], failure=True)
        assert output.read_bytes() == previous
        assert not list(directory.glob('.mylang-qbe-*'))
        # Stable qualified identities distinguish same-named functions across modules.
        (directory / 'left.my').write_text('module left\nexport value\n\n\ndef value() -> i64:\n    return 10\n')
        (directory / 'right.my').write_text('module right\nexport value\n\n\ndef value() -> i64:\n    return 20\n')
        source.write_text('module source\nimport left\nimport right\n\n\ndef main() -> i64:\n    return left.value() + right.value()\n')
        project = build(['--project'])
        assert len(project['functions']) == 3
        assert len({unit['symbol'] for unit in project['functions']}) == 3
        assert subprocess.check_output([output]) == b'30\n'
        source.write_text('module source\nimport right\nimport left\n\n\ndef main() -> i64:\n    return left.value() + right.value()\n')
        reordered_project = build(['--project'])
        assert reordered_project['compiled_functions'] == 0, reordered_project
        assert keys(project) == keys(reordered_project)
        # Diagnostic coordinates update independently of machine-code identity.
        source.write_text('def divide(x: i64) -> i64:\n    return divtrunc(10, x)\n\n\ndef main() -> i64:\n    return divide(0)\n')
        located = build()
        trapped = subprocess.run([output], capture_output=True)
        assert trapped.returncode != 0 and b'R_DIVISION_BY_ZERO' in trapped.stderr, trapped.stderr
        assert (str(source)+':2:').encode() in trapped.stderr, trapped.stderr
        source.write_text('\n\ndef divide(x: i64) -> i64:\n    return divtrunc(10, x)\n\n\ndef main() -> i64:\n    return divide(0)\n')
        relocated = build()
        assert relocated['compiled_functions'] == 0 and keys(located) == keys(relocated), relocated
        assert not relocated['metadata_reused'], relocated
        trapped = subprocess.run([output], capture_output=True)
        assert (str(source)+':4:').encode() in trapped.stderr, trapped.stderr
        # Signature changes require regeneration of the changed function and its caller.
        source.write_text('def square(x: i64) -> i64:\n    return x * x\n\n\ndef main() -> i64:\n    return square(4)\n')
        build()
        source.write_text('def square(x: i64, y: i64) -> i64:\n    return x * y\n\n\ndef main() -> i64:\n    return square(4, 5)\n')
        signature = build()
        assert signature['compiled_functions'] == 2, signature
        assert subprocess.check_output([output]) == b'20\n'
    print('QBE builder: body-only reuse, restart reuse, clean parity, reorder, deletion, corruption recovery, diagnostic relocation, and failure preservation passed')


if __name__ == '__main__':
    main()
