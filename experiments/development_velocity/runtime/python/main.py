"""Frozen process transport; application behavior lives in app.py."""
import json
import math
import sys

from app import run


def unique(pairs):
    result = {}
    for name, value in pairs:
        if name in result:
            raise ValueError('duplicate object key')
        result[name] = value
    return result


def finite(value):
    raise ValueError('nonfinite JSON')


def integer_token(value):
    result = int(value)
    if not -(2 ** 63) <= result < 2 ** 63:
        raise ValueError('integer token range')
    return result


def decimal_token(value):
    result = float(value)
    if not math.isfinite(result):
        raise ValueError('decimal token range')
    return result


def depth(value, level=1):
    if isinstance(value, str):
        value.encode('utf-8')
    if isinstance(value, dict):
        for key in value:
            key.encode('utf-8')
    if isinstance(value, (list, dict)):
        if level > 32:
            raise ValueError('nesting depth')
        for child in value.values() if isinstance(value, dict) else value:
            depth(child, level + 1)


def main():
    try:
        raw = sys.stdin.buffer.read(1048577)
        if len(raw) > 1048576:
            raise ValueError('input byte limit')
        value = json.loads(raw.decode('utf-8'), object_pairs_hook=unique, parse_constant=finite,
                           parse_int=integer_token, parse_float=decimal_token)
        depth(value)
        if type(value) is not dict or set(value) != {'requests'} or type(value['requests']) is not list or len(value['requests']) > 64:
            raise ValueError('invalid envelope')
    except (ValueError, UnicodeError, RecursionError):
        output = {'error': 'invalid-envelope'}
    else:
        results = []
        for request in value['requests']:
            try:
                results.append(run(request))
            except (ValueError, TypeError, KeyError):
                results.append({'error': 'invalid-request'})
        output = {'results': results}
    print(json.dumps(output, ensure_ascii=True, separators=(',', ':'), allow_nan=False))


if __name__ == '__main__':
    main()
