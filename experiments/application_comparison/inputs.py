"""Exact-byte input receipts and strict coordinator case-file decoding."""
import base64
import binascii
import hashlib
from .storage import canonical

MAX_INPUT_BYTES = 2 * 1024 * 1024


def payload(request, request_bytes=None):
    if request_bytes is not None:
        if request is not None or not isinstance(request_bytes, bytes):
            raise ValueError('raw input requires bytes and no JSON request')
        raw = request_bytes
    else:
        raw = canonical(request)
    if len(raw) > MAX_INPUT_BYTES:
        raise ValueError('case input exceeds coordinator byte limit')
    receipt = {'encoding': 'raw' if request_bytes is not None else 'json',
               'size': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
               'base64': base64.b64encode(raw).decode('ascii')}
    return raw, receipt


def decode_case(case):
    if not isinstance(case, dict) or 'expected' not in case:
        raise ValueError('case requires expected output')
    if set(case) == {'request', 'expected'}:
        payload(case['request'])
        return case['request'], None, case['expected']
    if set(case) != {'request_base64', 'expected'}:
        raise ValueError('case requires exactly one JSON or base64 input')
    encoded = case['request_base64']
    if not isinstance(encoded, str) or len(encoded) > 4 * ((MAX_INPUT_BYTES + 2) // 3):
        raise ValueError('invalid base64 input')
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as error:
        raise ValueError('invalid base64 input') from error
    if base64.b64encode(raw).decode('ascii') != encoded:
        raise ValueError('noncanonical base64 input')
    payload(None, raw)
    return None, raw, case['expected']
