#!/usr/bin/env python3
"""Verify fresh binding checks, actual generation skips, and artifact preservation."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('binding_cache_driver', ROOT / 'scripts/bindings.py')
driver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(driver)


def check_wrapper_report_compatibility(path, stored, request):
    """Optional wrapper metadata must be complete and valid after checksum verification."""
    legacy = json.loads(stored)
    legacy['payload']['report'].pop('callable_functions', None)
    legacy['payload']['report'].pop('unsupported_functions', None)

    def check(document, accepted):
        document['sha256'] = driver.digest(document['payload'])
        path.write_text(driver.canonical(document))
        loaded, reason = driver.load_cached(path, request)
        if accepted:
            assert reason == 'matching-request' and loaded is not None
            assert loaded == (document['payload']['source'].encode(), document['payload']['report'])
        else:
            assert reason == 'invalid-cache' and loaded is None

    check(legacy, True)
    extended = json.loads(driver.canonical(legacy))
    extended['payload']['report'].update(callable_functions=0, unsupported_functions={})
    check(extended, True)
    extended['payload']['report']['unsupported_functions'] = {'main::read': 'effectful function'}
    check(extended, True)
    for field, invalid in (
        ('callable_functions', True), ('callable_functions', -1), ('callable_functions', '0'),
        ('unsupported_functions', []), ('unsupported_functions', {'main::read': 1}),
        ('unsupported_functions', {'': 'effectful function'}), ('unsupported_functions', {'main::read': ''}),
    ):
        document = json.loads(driver.canonical(extended))
        document['payload']['report'][field] = invalid
        check(document, False)
    for field in ('callable_functions', 'unsupported_functions'):
        document = json.loads(driver.canonical(extended))
        del document['payload']['report'][field]
        check(document, False)
    document = json.loads(driver.canonical(extended))
    document['payload']['report']['unknown_metadata'] = 0
    check(document, False)
    path.write_bytes(stored)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = Path(parser.parse_args().compiler).resolve()
    with tempfile.TemporaryDirectory(prefix='mylang-binding-cache-') as temporary:
        root = Path(temporary)
        entry = root / 'main.my'
        entry.write_text('module main; export Point; struct Point { n: i64 } fn main()->i64{return 0;}')
        output = root / 'bindings.py'
        cache = root / 'cache'

        def build(**kwargs):
            return driver.build(compiler, entry, output, cache_dir=cache, **kwargs)

        with patch.object(driver, 'generate', wraps=driver.generate) as generation, patch.object(driver, 'checked_schema', wraps=driver.checked_schema) as frontend:
            first = build()
            assert first['cache'] == 'miss' and first['generation'] == 'executed' and first['installation'] == 'replaced'
            assert generation.call_count == frontend.call_count == 1
            original = output.read_bytes()
            identity = output.stat()
            generation.reset_mock()
            frontend.reset_mock()
            warm = build()
            assert warm['cache'] == 'hit' and warm['generation'] == 'skipped' and warm['installation'] == 'unchanged'
            assert generation.call_count == 0 and frontend.call_count == 1
            assert (output.stat().st_ino, output.stat().st_mtime_ns) == (identity.st_ino, identity.st_mtime_ns)
            entry.write_text(entry.read_text() + '\n// private source change\n')
            private = build()
            assert private['cache'] == 'hit' and private['schema_source_sha256'] != first['schema_source_sha256']
            assert private['request_sha256'] == first['request_sha256']
            assert generation.call_count == 0 and frontend.call_count == 2
            # Damage or remove only the destination; a verified hit reinstalls it.
            output.write_bytes(b'stale')
            assert build()['installation'] == 'replaced' and output.read_bytes() == original
            output.unlink()
            assert build()['installation'] == 'replaced' and output.read_bytes() == original
            assert generation.call_count == 0
        key = first['request_sha256']
        assert key == hashlib.sha256(driver.canonical(first['request']).encode()).hexdigest()
        path = cache / (key + '.json')
        stored = path.read_bytes()
        check_wrapper_report_compatibility(path, stored, first['request'])
        corruptions = [b'not json', b'[]', b'{"version":1,"version":2}']
        document = json.loads(stored)
        document['payload']['source'] += '# checksum mismatch'
        corruptions.append(driver.canonical(document).encode())
        document = json.loads(stored)
        document['payload']['report']['bytes'] = True
        document['sha256'] = driver.digest(document['payload'])
        corruptions.append(driver.canonical(document).encode())
        document = json.loads(stored)
        document['payload']['request']['max_output_bytes'] += 1
        document['sha256'] = driver.digest(document['payload'])
        corruptions.append(driver.canonical(document).encode())
        document = json.loads(stored)
        document['payload']['source'] = 'def broken('
        document['payload']['report']['bytes'] = len(document['payload']['source'])
        document['payload']['report']['sha256'] = hashlib.sha256(document['payload']['source'].encode()).hexdigest()
        document['sha256'] = driver.digest(document['payload'])
        corruptions.append(driver.canonical(document).encode())
        for corrupt in corruptions:
            path.write_bytes(corrupt)
            with patch.object(driver, 'generate', wraps=driver.generate) as generation:
                repaired = build()
                assert repaired['cache'] == 'miss' and repaired['reason'] == 'invalid-cache'
                assert generation.call_count == 1
            assert output.read_bytes() == original and path.read_bytes() == stored
        limited = build(max_output_bytes=driver.MAX_BYTES - 1)
        assert limited['cache'] == 'miss' and limited['request_sha256'] != key and limited['installation'] == 'unchanged'
        runtime = root / 'runtime.py'
        runtime.write_text(driver.RUNTIME.read_text() + '\n# changed runtime input\n')
        with patch.object(driver, 'RUNTIME', runtime):
            changed = build()
            assert changed['cache'] == 'miss' and changed['request_sha256'] != key
            assert output.read_bytes() != original
        assert build()['cache'] == 'hit' and output.read_bytes() == original
        # A different selected executable is a distinct dependency even when the
        # returned schema is identical. Modify only a private wrapper, not Zig.
        wrapper = root / 'compiler-wrapper'
        wrapper.write_text('#!' + sys.executable + '\nimport os, sys\nos.execv(' + repr(str(compiler)) + ', [' + repr(str(compiler)) + '] + sys.argv[1:])\n')
        wrapper.chmod(0o700)
        wrapped = driver.build(wrapper, entry, output, cache_dir=cache)
        assert wrapped['cache'] == 'miss' and wrapped['request']['compiler_sha256'] != first['request']['compiler_sha256']
        before_entries = set(cache.iterdir())
        saved_check = driver.checked_schema

        def replace_wrapper(*args):
            schema = saved_check(*args)
            wrapper.write_text(wrapper.read_text() + '# changed during check\n')
            return schema

        with patch.object(driver, 'checked_schema', side_effect=replace_wrapper):
            try:
                driver.build(wrapper, entry, output, cache_dir=cache)
            except ValueError as error:
                assert 'compiler changed' in str(error)
            else:
                raise AssertionError('compiler replacement was ignored')
        assert set(cache.iterdir()) == before_entries and output.read_bytes() == original
        entry.write_text('module main; export Point; struct Point { n: i64, flag: bool } fn main()->i64{return 0;}')
        shape = build()
        assert shape['cache'] == 'miss' and shape['schema_sha256'] != first['schema_sha256']
        valid_source = entry.read_text()
        valid_output = output.read_bytes()
        before_entries = set(cache.iterdir())
        entry.write_text(valid_source + 'fn broken()->i64{return true;}')
        with patch.object(driver, 'generate', wraps=driver.generate) as generation:
            try:
                build()
            except driver.CompilerFailure as error:
                assert error.status == 1
            else:
                raise AssertionError('invalid private source reused a cache entry')
            assert generation.call_count == 0
        assert set(cache.iterdir()) == before_entries and output.read_bytes() == valid_output
        entry.write_text(valid_source)
        # No-op installation also applies when the cache is disabled.
        identity = output.stat()
        uncached = driver.build(compiler, entry, output)
        assert uncached['cache'] == 'disabled' and uncached['generation'] == 'executed' and uncached['installation'] == 'unchanged'
        assert output.stat().st_mtime_ns == identity.st_mtime_ns
        # A cache write failure cannot replace the destination or leave temp files.
        entry.write_text(valid_source.replace('n: i64', 'n: u64'))
        with patch.object(driver.os, 'replace', side_effect=OSError('injected failure')):
            try:
                build()
            except OSError:
                pass
            else:
                raise AssertionError('cache write failure swallowed')
        assert output.read_bytes() == valid_output
        assert not list(cache.glob('.bindings-*')) and not list(root.glob('.bindings-*'))
    print('binding cache acceptance: checked cold/warm execution counts, no-op inode/timestamps, restoration, corrupt repair, schema/runtime/compiler/limit invalidation, concurrent compiler change, rejected sources, and write failure preservation passed')


if __name__ == '__main__':
    main()
