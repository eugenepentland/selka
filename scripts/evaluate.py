#!/usr/bin/env python3
"""Cache successful restricted VM evaluations after fresh compiler request checks."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

MAX_DOCUMENT = 16 * 1024 * 1024


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key: {key}')
        result[key] = value
    return result


def reject_constant(value):
    raise ValueError(f'invalid JSON constant: {value}')


def decode(data):
    if len(data) > MAX_DOCUMENT:
        raise ValueError('evaluation document exceeds 16 MiB')
    return json.loads(data, object_pairs_hook=unique_object, parse_constant=reject_constant)


def encode(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(',', ':')).encode('utf-8')


def digest(value):
    return hashlib.sha256(encode(value)).hexdigest()


def validate(document, request_only):
    keys = {'version', 'request_sha256', 'request', 'evaluation' if request_only else 'result'}
    if not isinstance(document, dict) or set(document) != keys:
        raise ValueError('invalid evaluation document fields')
    version = 'eval-request-document-v1' if request_only else 'eval-report-v1'
    if document['version'] != version:
        raise ValueError('unsupported evaluation document version')
    request = document['request']
    key = document['request_sha256']
    if not isinstance(request, dict) or request.get('version') != 'eval-request-v1':
        raise ValueError('unsupported request version')
    if not isinstance(key, str) or not re.fullmatch('[0-9a-f]{64}', key) or digest(request) != key:
        raise ValueError('invalid request digest')
    if request_only:
        if document['evaluation'] != 'not-executed':
            raise ValueError('request falsely claims execution')
    else:
        result = document['result']
        if not isinstance(result, dict) or set(result) != {'type', 'decimal'} or result['type'] != 'i64':
            raise ValueError('invalid result type')
        value = result['decimal']
        if not isinstance(value, str) or len(value) > 20 or not re.fullmatch(r'0|-?[1-9][0-9]*', value):
            raise ValueError('invalid i64 decimal')
        if not -(1 << 63) <= int(value) < (1 << 63):
            raise ValueError('i64 result out of range')
    return document


def load_cached(path, request):
    try:
        with path.open('rb') as stream:
            stored = decode(stream.read(MAX_DOCUMENT + 1))
    except FileNotFoundError:
        return None, 'not-found'
    except (ValueError, UnicodeError, RecursionError):
        return None, 'invalid-cache'
    try:
        if not isinstance(stored, dict) or set(stored) != {'version', 'report', 'report_sha256'}:
            raise ValueError('invalid cache envelope')
        if stored['version'] != 'eval-cache-v1' or stored['report_sha256'] != digest(stored['report']):
            raise ValueError('invalid cache checksum/version')
        report = validate(stored['report'], False)
        if report['request_sha256'] != request['request_sha256'] or report['request'] != request['request']:
            raise ValueError('cache request mismatch')
        return report, 'matching-request'
    except (ValueError, TypeError, KeyError, UnicodeError, RecursionError):
        return None, 'invalid-cache'


def store_cached(path, report):
    data = encode({'version': 'eval-cache-v1', 'report': report, 'report_sha256': digest(report)})
    if len(data) > MAX_DOCUMENT:
        raise ValueError('cache record exceeds 16 MiB')
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.evaluation-', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


class CompilerFailure(Exception):
    def __init__(self, status, message):
        self.status = status if status in (1, 2) else 2
        super().__init__(message)


def compiler_document(compiler, entry, options, request_only, timeout):
    flag = '--evaluation-request' if request_only else '--evaluation-report'
    result = subprocess.run([compiler, 'eval-project', str(entry), flag, *options],
                            capture_output=True, timeout=timeout)
    diagnostics = result.stderr.decode('utf-8', errors='replace')
    if result.returncode:
        raise CompilerFailure(result.returncode, diagnostics or 'compiler evaluation failed\n')
    return validate(decode(result.stdout), request_only), diagnostics


def evaluate(compiler, entry, cache_dir, options=(), timeout=90):
    request, warnings = compiler_document(compiler, entry, options, True, timeout)
    if warnings:
        sys.stderr.write(warnings)
    path = cache_dir / (request['request_sha256'] + '.json')
    report, reason = load_cached(path, request)
    executed = report is None
    if executed:
        report, evaluation_warnings = compiler_document(compiler, entry, options, False, timeout)
        if evaluation_warnings and evaluation_warnings != warnings:
            sys.stderr.write(evaluation_warnings)
        if report['request_sha256'] != request['request_sha256'] or report['request'] != request['request']:
            raise ValueError('inputs or compiler changed between request and evaluation; retry')
        store_cached(path, report)
    return {'version': 'eval-cache-run-v1', 'cache': 'miss' if executed else 'hit',
            'reason': reason, 'frontend': 'checked', 'vm': 'executed' if executed else 'skipped',
            'request_sha256': request['request_sha256'], 'result': report['result']}


def positive(value):
    if not re.fullmatch('[0-9]+', value) or int(value) == 0 or int(value) > (1 << 64) - 1:
        raise argparse.ArgumentTypeError('expected a positive u64')
    return value


def positive_timeout(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError('expected a positive finite timeout')
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('entry', type=Path)
    parser.add_argument('--compiler', default='zig-out/bin/mylang')
    parser.add_argument('--cache-dir', type=Path, required=True)
    parser.add_argument('--max-steps', type=positive)
    parser.add_argument('--max-frames', type=positive)
    parser.add_argument('--max-eval-bytes', type=positive)
    parser.add_argument('--timeout', type=positive_timeout, default=90)
    args = parser.parse_args()
    options = [f'--{name.replace("_", "-")}={getattr(args, name)}'
               for name in ('max_steps', 'max_frames', 'max_eval_bytes') if getattr(args, name) is not None]
    try:
        result = evaluate(args.compiler, args.entry, args.cache_dir, options, args.timeout)
        print(encode(result).decode('utf-8'))
        return 0
    except CompilerFailure as error:
        sys.stderr.write(str(error))
        return error.status
    except (OSError, ValueError, TypeError, KeyError, RecursionError, subprocess.TimeoutExpired) as error:
        print(f'evaluation cache: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
