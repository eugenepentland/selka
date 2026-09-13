#!/usr/bin/env python3
"""Verify evaluation receipts against source bytes, executable bytes, and mutations."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


def compiler_identity(compiler):
    """The compiler's embedded build-time identity, reported rather than hashed from the binary."""
    report = subprocess.run([str(compiler), '--features'], capture_output=True, text=True, timeout=60)
    assert report.returncode == 0, report.stderr
    identity = json.loads(report.stdout)['compiler_sha256']
    assert isinstance(identity, str) and len(identity) == 64
    return identity


def invoke(compiler, entry, *options, status=0, request=False):
    flag = '--evaluation-request' if request else '--evaluation-report'
    result = subprocess.run([compiler, 'eval-project', str(entry), flag, *options],
                            text=True, capture_output=True, timeout=90)
    assert result.returncode == status, (result.returncode, result.stderr)
    if status:
        assert result.stdout == '', result.stdout
        return result
    report = json.loads(result.stdout)
    assert report['version'] == ('eval-request-document-v1' if request else 'eval-report-v1'), report
    if request:
        assert report['evaluation'] == 'not-executed' and 'result' not in report, report
    encoded = json.dumps(report['request'], ensure_ascii=False, separators=(',', ':')).encode()
    assert report['request_sha256'] == hashlib.sha256(encoded).hexdigest(), report
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True)
    compiler = str(Path(parser.parse_args().compiler).resolve())
    with tempfile.TemporaryDirectory(prefix='mylang-evaluation-reports-') as temporary:
        root = Path(temporary) / 'original'
        root.mkdir()
        entry = root / 'main.my'
        entry.write_text('module main\nimport helper as h\n\n\ndef main() -> i64:\n    return h.value()\n')
        helper = root / 'helper.my'
        helper.write_text('module helper\nexport value\n\n\n'
                          'def value() -> i64:\n    return 9223372036854775807\n')
        first = invoke(compiler, entry)
        assert first == invoke(compiler, entry), 'nondeterministic report'
        planned = invoke(compiler, entry, request=True)
        assert planned['request'] == first['request']
        assert planned['request_sha256'] == first['request_sha256']
        request = first['request']
        assert request['version'] == 'eval-request-v1'
        assert request['entry'] == 'main'
        assert request['policy'] == 'effect-free-parameter-free-v1'
        assert first['result'] == {'type': 'i64', 'decimal': '9223372036854775807'}
        assert request['implementation']['compiler_sha256'] == compiler_identity(compiler)
        assert request['implementation']['zig_version'] == '0.17.0-dev.1683+5ceec001b'
        assert request['budgets'] == {'max_steps': 1000000, 'max_frames': 256, 'max_bytes': 16777216}
        assert [source['module'] for source in request['sources']] == ['helper', 'main']
        for source in request['sources']:
            data = (root / source['path']).read_bytes()
            assert source['sha256'] == hashlib.sha256(data).hexdigest()
            assert source['bytes'] == len(data)
        assert request['sources'][0]['imports'] == []
        assert request['sources'][1]['imports'] == [{'module': 'helper', 'alias': 'h'}]
        copied = Path(temporary) / 'relocated'
        shutil.copytree(root, copied)
        assert first == invoke(compiler, copied / 'main.my'), 'absolute paths entered the request'
        (root / 'unrelated.my').write_text('invalid syntax is not a declared dependency')
        assert first == invoke(compiler, entry), 'unrelated input changed the request'
        for option in ('--max-steps=1000001', '--max-frames=257', '--max-eval-bytes=8388608'):
            changed = invoke(compiler, entry, option)
            assert changed['request_sha256'] != first['request_sha256']
            assert changed['result'] == first['result']
        helper.write_text(helper.read_text() + '# source-only change\n')
        changed = invoke(compiler, entry)
        assert changed['request_sha256'] != first['request_sha256']
        assert changed['result'] == first['result']
        assert changed['request']['sources'][1] == request['sources'][1]
        entry.write_text(entry.read_text().replace('as h\n', 'as other\n').replace('h.value()', 'other.value()'))
        aliased = invoke(compiler, entry)
        assert aliased['request_sha256'] != changed['request_sha256']
        assert aliased['result'] == first['result']
        assert aliased['request']['sources'][1]['imports'][0]['alias'] == 'other'
        helper.write_text('module helper\nexport value\n\n\ndef value() -> i64:\n    return 1 // 0\n')
        invoke(compiler, entry, '--max-steps=1', request=True)
        assert 'R_DIVISION_BY_ZERO' in invoke(compiler, entry, status=1).stderr
        assert 'R_EVAL_MEMORY' in invoke(compiler, entry, '--max-eval-bytes=1', status=1).stderr
        helper.write_text('module helper\nexport value\n\n\ndef value() -> i64:\n    return True\n')
        invoke(compiler, entry, status=1)
        invoke(compiler, entry, status=1, request=True)
        print('evaluation receipts: canonical request hash, executable/source identities, '
              'exact i64, relocation, dependency/budget mutations, and failure suppression passed')


if __name__ == '__main__':
    main()
