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
            second = cache.evaluate(compiler, entry, directory, compare_to=directory / (first["request_sha256"] + ".json"))
            assert second['cache'] == 'hit' and second['vm'] == 'skipped', second
            assert second['result'] == {'type': 'i64', 'decimal': '7'}
            assert second['comparison']['same_request'] and second['comparison']['changes'] == []
            assert [call.args[3] for call in calls.call_args_list] == [True], 'cache hit invoked evaluation'
        path = directory / (first['request_sha256'] + '.json')
        original = path.read_bytes()
        stored = cache.decode(original)
        request = {'request_sha256': first['request_sha256'], 'request': stored['report']['request']}
        def modified(change):
            document = copy.deepcopy(stored['report'])
            change(document['request'])
            document['request_sha256'] = cache.digest(document['request'])
            return document

        implementation = modified(lambda r: r['implementation'].update(compiler_sha256='f' * 64))
        comparison = cache.compare_requests(stored['report'], implementation)
        assert [c['path'] for c in comparison['changes']] == ['/implementation/compiler_sha256']
        changed_fields = modified(lambda r: (r['budgets'].update(max_steps=1), r['implementation'].update(compiler_sha256='f' * 64)))
        limited = cache.compare_requests(stored['report'], changed_fields, 1)
        assert limited['truncated'] and len(limited['changes']) == 1
        assert cache.compare_requests(stored['report'], changed_fields) == cache.compare_requests(stored['report'], changed_fields)
        added = modified(lambda r: r['sources'].append({'module': 'helper', 'path': 'helper.my', 'sha256': 'a' * 64, 'bytes': 1, 'imports': []}))
        comparison = cache.compare_requests(stored['report'], added)
        assert {c['path'] for c in comparison['changes']} == {'/sources/helper', '/source_order/1'}
        reverse = copy.deepcopy(added)
        reverse['request']['sources'].reverse()
        reverse['request_sha256'] = cache.digest(reverse['request'])
        assert all(c['path'].startswith('/source_order/') for c in cache.compare_requests(added, reverse)['changes'])
        assert any(c['kind'] == 'removed' and c['path'] == '/sources/helper' for c in cache.compare_requests(added, stored['report'])['changes'])
        aliased = modified(lambda r: r['sources'][0]['imports'].append({'module': 'helper', 'alias': 'h'}))
        assert cache.compare_requests(stored['report'], aliased)['changes'][0]['path'] == '/sources/main/imports/0'
        reordered = copy.deepcopy(stored['report'])
        reordered['request'] = dict(reversed(list(reordered['request'].items())))
        reordered['request_sha256'] = cache.digest(reordered['request'])
        assert cache.compare_requests(stored['report'], reordered)['encoding_only']
        typed = modified(lambda r: r['budgets'].update(max_frames=True))
        numeric = copy.deepcopy(typed)
        numeric['request']['budgets']['max_frames'] = 1
        numeric['request_sha256'] = cache.digest(numeric['request'])
        assert cache.compare_requests(typed, numeric)['changes'][0]['path'] == '/budgets/max_frames'
        assert cache.load_reference(path)['request_sha256'] == request['request_sha256']
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
        budget = cache.evaluate(compiler, entry, directory, ['--max-steps=1000001'], compare_to=path)
        assert budget['cache'] == 'miss' and budget['request_sha256'] != first['request_sha256']
        assert [c['path'] for c in budget['comparison']['changes']] == ['/budgets/max_steps']
        entry.write_text('module main; fn main()->i64{return 8;}')
        changed = cache.evaluate(compiler, entry, directory, compare_to=path)
        assert changed['cache'] == 'miss' and changed['result']['decimal'] == '8'
        assert [c['path'] for c in changed['comparison']['changes']] == ['/sources/main/sha256']
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
