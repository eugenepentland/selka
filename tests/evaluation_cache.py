#!/usr/bin/env python3
"""Check real compiler cache reuse plus corruption, write-failure, and race handling."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('evaluation_cache_driver', Path(__file__).resolve().parents[1] / 'scripts/evaluate.py')
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='mylang-cache-test-') as temporary:
        root = Path(temporary)
        entry = root / 'main.my'
        entry.write_text('module main; fn main()->i64{return 7;}')
        directory = root / 'cache'
        with patch.object(cache, 'compiler_document', wraps=cache.compiler_document) as calls:
            first = cache.evaluate(compiler, entry, directory)
            assert first['cache'] == 'miss' and first['vm'] == 'executed', first
            assert [call.args[3] for call in calls.call_args_list] == [True, False]
            calls.reset_mock()
            second = cache.evaluate(compiler, entry, directory)
            assert second['cache'] == 'hit' and second['vm'] == 'skipped', second
            assert second['result'] == {'type': 'i64', 'decimal': '7'}
            assert [call.args[3] for call in calls.call_args_list] == [True], 'cache hit invoked evaluation'
        path = directory / (first['request_sha256'] + '.json')
        original = path.read_bytes()
        stored = cache.decode(original)
        request = {'request_sha256': first['request_sha256'], 'request': stored['report']['request']}
        corruptions = [b'not json', b'{"version":1,"version":2}', b'[]']
        for field, value in [('decimal', '9223372036854775808'), ('decimal', '-0'), ('type', 'u64')]:
            corrupt = copy.deepcopy(stored)
            corrupt['report']['result'][field] = value
            corrupt['report_sha256'] = cache.digest(corrupt['report'])
            corruptions.append(cache.encode(corrupt))
        wrong_request = copy.deepcopy(stored)
        wrong_request['report']['request']['budgets']['max_steps'] += 1
        wrong_request['report']['request_sha256'] = cache.digest(wrong_request['report']['request'])
        wrong_request['report_sha256'] = cache.digest(wrong_request['report'])
        corruptions.append(cache.encode(wrong_request))
        for data in corruptions:
            path.write_bytes(data)
            assert cache.load_cached(path, request) == (None, 'invalid-cache')
        path.write_bytes(original)
        with patch.object(cache.os, 'replace', side_effect=OSError('injected write failure')):
            try:
                cache.store_cached(path, stored['report'])
            except OSError:
                pass
            else:
                raise AssertionError('write failure was swallowed')
        assert path.read_bytes() == original
        assert not list(directory.glob('.evaluation-*')), 'temporary file leaked'
        corrupt = copy.deepcopy(stored)
        corrupt['report']['result']['decimal'] = '99'  # checksum deliberately retained
        path.write_bytes(cache.encode(corrupt))
        repaired = cache.evaluate(compiler, entry, directory)
        assert repaired['cache'] == 'miss' and repaired['reason'] == 'invalid-cache', repaired
        assert repaired['result']['decimal'] == '7'
        budget = cache.evaluate(compiler, entry, directory, ['--max-steps=1000001'])
        assert budget['cache'] == 'miss' and budget['request_sha256'] != first['request_sha256']
        entry.write_text('module main; fn main()->i64{return 8;}')
        changed = cache.evaluate(compiler, entry, directory)
        assert changed['cache'] == 'miss' and changed['result']['decimal'] == '8'
        existing = {file.name: file.read_bytes() for file in directory.iterdir()}
        entry.write_text('module main; fn main()->i64{return true;}')
        try:
            cache.evaluate(compiler, entry, directory)
        except cache.CompilerFailure as error:
            assert error.status == 1
        else:
            raise AssertionError('invalid source reused a cached result')
        assert existing == {file.name: file.read_bytes() for file in directory.iterdir()}
        entry.write_text('module main; fn main()->i64{return 1/0;}')
        try:
            cache.evaluate(compiler, entry, directory)
        except cache.CompilerFailure as error:
            assert error.status == 1 and 'R_DIVISION_BY_ZERO' in str(error)
        else:
            raise AssertionError('runtime failure was cached')
        assert existing == {file.name: file.read_bytes() for file in directory.iterdir()}
        entry.write_text('module main; fn main()->i64{return 10;}')
        invoke = cache.compiler_document

        def mutate_after_request(*args):
            result = invoke(*args)
            if args[3]:
                entry.write_text('module main; fn main()->i64{return 11;}')
            return result

        race_directory = root / 'racing-cache'
        with patch.object(cache, 'compiler_document', side_effect=mutate_after_request):
            try:
                cache.evaluate(compiler, entry, race_directory)
            except ValueError as error:
                assert 'changed between request and evaluation' in str(error)
            else:
                raise AssertionError('mixed snapshots were cached')
        assert not race_directory.exists()
        print('evaluation cache: real cold/warm VM invocation counts, source/budget misses, '
              'corruption repair, atomic failure cleanup, rejected source/runtime failures, '
              'and changed-input race rejection passed')


if __name__ == '__main__':
    main()
