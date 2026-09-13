#!/usr/bin/env python3
"""Independently verify schema source receipts and their binding provenance."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('schema_receipt_bindings', ROOT / 'scripts/bindings.py')
bindings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bindings)


def compiler_identity(compiler):
    """The compiler's embedded build-time identity, reported rather than hashed from the binary."""
    report = subprocess.run([str(compiler), '--features'], capture_output=True, text=True, timeout=60)
    assert report.returncode == 0, report.stderr
    identity = json.loads(report.stdout)['compiler_sha256']
    assert isinstance(identity, str) and len(identity) == 64
    return identity


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = Path(parser.parse_args().compiler).resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-schema-receipt-') as temporary:
        root = Path(temporary)
        entry = root / 'main.my'
        entry.write_text('module main\nimport left\nimport right\n\ndef main() -> i64:\n    return 0\n')
        (root / 'left.my').write_text('module left\nimport shared\n')
        (root / 'right.my').write_text('module right\nimport shared\n')
        shared = root / 'shared.my'
        shared.write_text('module shared\nexport Item\n\nclass Item:\n    value: u64\n\ndef hidden() -> i64:\n    return 7\n')

        def run(path=entry, flags=('--schema-report',), expected=0):
            result = subprocess.run([str(compiler), 'schema-project', str(path), *flags], capture_output=True, text=True, timeout=30)
            assert result.returncode == expected, (result.returncode, result.stderr)
            if expected:
                assert result.stdout == ''
                return result.stderr
            return json.loads(result.stdout)

        first = run()
        assert bindings.validate_schema_report(first) is first
        assert first['source_sha256'] == digest(first['source'])
        assert first['schema_sha256'] == digest(first['schema'])
        assert first['schema'] == run(flags=())
        assert run() == first
        source = first['source']
        assert source['implementation']['compiler_sha256'] == compiler_identity(compiler)
        assert source['implementation']['zig_version'] == '0.17.0-dev.1683+5ceec001b'
        assert [s['module'] for s in source['sources']] == ['shared', 'left', 'right', 'main']
        for item in source['sources']:
            content = (root / item['path']).read_bytes()
            assert len(content) == item['bytes']
            assert hashlib.sha256(content).hexdigest() == item['sha256']
        assert source['sources'][1]['imports'] == [{'module': 'shared', 'alias': 'shared'}]
        assert source['sources'][2]['imports'] == source['sources'][1]['imports']
        clone = root / 'clone'
        clone.mkdir()
        for path in root.glob('*.my'):
            shutil.copy2(path, clone / path.name)
        assert run(clone / 'main.my') == first
        (root / 'unused.my').write_text('broken and unimported')
        assert run() == first
        original = shared.read_text()
        shared.write_text(original + '\n# private comment\n')
        changed = run()
        assert changed['schema_sha256'] == first['schema_sha256']
        assert changed['source_sha256'] != first['source_sha256']
        assert sum(a != b for a, b in zip(first['source']['sources'], changed['source']['sources'])) == 1
        shared.write_text(original.replace('value: u64', 'value: u32'))
        assert run()['schema_sha256'] != first['schema_sha256']
        shared.write_text(original)
        (root / 'left.my').write_text('module left\nimport shared as s\n')
        aliased = run()
        assert aliased['schema_sha256'] == first['schema_sha256'] and aliased['source_sha256'] != first['source_sha256']
        shared.write_text(original + '\ndef broken() -> i64:\n    return True\n')
        assert 'E_TYPE' in run(expected=1)
        shared.write_text(original)
        run(flags=('--schema-report', '--schema-report'), expected=2)
        # Integrity and ordering are verified before artifacts are generated/reused.
        for mutate in (
            lambda r: r['source']['sources'][0].update(bytes=0),
            lambda r: r['schema'].update(entry='other'),
            lambda r: r.update(source_sha256='0' * 64),
        ):
            bad = copy.deepcopy(first)
            mutate(bad)
            try:
                bindings.validate_schema_report(bad)
            except ValueError:
                pass
            else:
                raise AssertionError('corrupt receipt accepted')
        bad = copy.deepcopy(first)
        bad['source']['sources'].reverse()
        bad['source_sha256'] = digest(bad['source'])
        try:
            bindings.validate_schema_report(bad)
        except ValueError:
            pass
        else:
            raise AssertionError('invalid dependency ordering accepted')
        # Binding hits report the newly checked source, not a cached old snapshot.
        output = root / 'bindings.py'
        cache = root / 'cache'
        cold = bindings.build(compiler, entry, output, cache_dir=cache)
        before = output.read_bytes()
        shared.write_text(original + '\n# fresh provenance\n')
        warm = bindings.build(compiler, entry, output, cache_dir=cache)
        assert warm['cache'] == 'hit' and warm['generation'] == 'skipped'
        assert warm['request_sha256'] == cold['request_sha256'] and output.read_bytes() == before
        assert warm['schema_source_sha256'] != cold['schema_source_sha256']
        assert warm['schema_source'] == run()['source']
        assert warm['schema_source_sha256'] == digest(warm['schema_source'])
        assert warm['request']['schema_compiler_sha256'] == source['implementation']['compiler_sha256']
    print('schema receipt acceptance: independent source/compiler/schema hashes, shared dependencies, relocation, private/public/alias changes, rejection/integrity, and fresh binding-cache provenance passed')


if __name__ == '__main__':
    main()
