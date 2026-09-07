"""Shared coordinator JSON transport specification; no application imports."""
import json
import math


def within_depth(raw):
    depth = 0
    quoted = escaped = False
    for byte in raw:
        if quoted:
            if escaped:
                escaped = False
            elif byte == 92:
                escaped = True
            elif byte == 34:
                quoted = False
        elif byte == 34:
            quoted = True
        elif byte in (91, 123):
            depth += 1
            if depth > 64:
                return False
        elif byte in (93, 125):
            depth -= 1
    # JSON syntax is checked separately; this scanner only bounds containers.
    return True


def respond(raw, handler):
    def object_pairs(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('duplicate key')
            result[key] = value
        return result

    def integer(text):
        number = int(text)
        if not -(1 << 63) <= number < (1 << 63):
            raise ValueError('integer range')
        return number

    def floating(text):
        number = float(text)
        if not math.isfinite(number):
            raise ValueError('nonfinite number')
        return number

    def constant(text):
        raise ValueError('nonfinite number')

    if len(raw) > 1024 * 1024 or not within_depth(raw):
        return {'error': 'invalid-request'}
    try:
        request = json.loads(raw.decode('utf-8'), object_pairs_hook=object_pairs,
                             parse_int=integer, parse_float=floating, parse_constant=constant)
    except (ValueError, UnicodeError, RecursionError):
        return {'error': 'invalid-request'}
    pending = [request]
    while pending:
        item = pending.pop()
        if isinstance(item, str) and any(0xD800 <= ord(char) <= 0xDFFF for char in item):
            return {'error': 'invalid-request'}
        if isinstance(item, dict):
            pending.extend(item.keys())
            pending.extend(item.values())
        elif isinstance(item, list):
            pending.extend(item)
    return handler(request)

