#!/usr/bin/env python3
"""Bounded advisory diagnostics; no return value authorizes cache reuse.

Summaries contain already-selected identities, never discovery or new hashing.
The canonical JSON string is an immutable snapshot owned by the caller. Persist
it separately from success receipts: missing telemetry must not affect reuse.
"""
import json
import math
import os
import tempfile
import re
from pathlib import Path

MAX_BYTES = 2 * 1024 * 1024
MAX_FILES = 8192
MAX_CHANGES = 64
MAX_OBSERVATIONS = 256
MAX_LINE = 8192


def _decode(value):
    if not isinstance(value, str) or len(value.encode('utf-8')) > MAX_BYTES:
        raise ValueError('summary bound')
    def pairs(items):
        result = {}
        for key, item in items:
            if key in result:
                raise ValueError('duplicate key')
            result[key] = item
        return result
    return json.loads(value, object_pairs_hook=pairs, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))


def _validate(record):
    if not isinstance(record, dict) or set(record) != {'version', 'group', 'files', 'common', 'artifacts'}:
        raise ValueError('summary shape')
    if type(record['version']) is not int or record['version'] != 1:
        raise ValueError('summary version')
    if not all(isinstance(record[k], dict) for k in ('group', 'common', 'artifacts')):
        raise ValueError('summary mappings')
    files = record['files']
    if not isinstance(files, list) or len(files) > MAX_FILES:
        raise ValueError('file bound')
    paths = set()
    for item in files:
        if not isinstance(item, dict) or not isinstance(item.get('path'), str) or not item['path']:
            raise ValueError('file identity')
        if not isinstance(item.get('sha256'), str) or not re.fullmatch('[0-9a-f]{64}', item['sha256']):
            raise ValueError('file digest')
        if item['path'] in paths:
            raise ValueError('duplicate path')
        paths.add(item['path'])
    _bounded(record)
    return record


def _bounded(value):
    """Reject excessive construction before serializing caller-owned data."""
    pending = [(value, 0)]
    nodes = size = 0
    while pending:
        item, depth = pending.pop()
        nodes += 1
        if nodes > 131072 or depth > 32:
            raise ValueError('diagnostic complexity bound')
        if isinstance(item, str):
            size += len(item)
            if size > MAX_BYTES:
                raise ValueError('diagnostic string bound')
        elif isinstance(item, dict):
            if len(item) > 16384 or not all(isinstance(key, str) for key in item):
                raise ValueError('diagnostic mapping bound')
            pending.extend((key, depth + 1) for key in item)
            pending.extend((child, depth + 1) for child in item.values())
        elif isinstance(item, (list, tuple)):
            if len(item) > 16384:
                raise ValueError('diagnostic list bound')
            pending.extend((child, depth + 1) for child in item)
        elif type(item) is float and not math.isfinite(item):
            raise ValueError('nonfinite diagnostic number')
        elif item is not None and type(item) not in (bool, int, float):
            raise ValueError('diagnostic JSON type')


def dependency_summary(group, files, common, artifacts=None):
    """Freeze selected identities as canonical JSON, or None if unavailable."""
    try:
        if not isinstance(files, list) or len(files) > MAX_FILES:
            return None
        record = dict(version=1, group=group, files=files, common=common,
                      artifacts={} if artifacts is None else artifacts)
        _bounded(record)
        encoded = json.dumps(record, sort_keys=True, separators=(',', ':'), allow_nan=False)
        detached = _validate(_decode(encoded))
        detached['files'].sort(key=lambda item: item['path'])
        return json.dumps(detached, sort_keys=True, separators=(',', ':'), allow_nan=False)
    except (ValueError, TypeError, RecursionError, OverflowError, UnicodeError):
        return None


def read_summary(path):
    """Read bounded strict diagnostic JSON; missing/corrupt records are unknown."""
    try:
        with Path(path).open('rb') as source:
            raw = source.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            return None
        record = _validate(_decode(raw.decode('utf-8')))
        return dependency_summary(record['group'], record['files'], record['common'], record['artifacts'])
    except (OSError, ValueError, TypeError, RecursionError):
        return None


def explain_miss(current, previous, reason='dependency identity changed'):
    """Compare trustworthy summaries; policy causes remain caller-owned."""
    result = dict(status='unknown', reason='prior or current dependency summary unavailable',
                  changes=[], truncated=False)
    try:
        new, old = _validate(_decode(current)), _validate(_decode(previous))
    except (ValueError, TypeError, RecursionError, UnicodeError):
        return result
    changes = []
    total = 0

    def add(kind, name):
        nonlocal total
        total += 1
        if len(changes) < MAX_CHANGES:
            changes.append(dict(kind=kind, name=name[:512]))

    for section in ('group', 'common', 'artifacts'):
        for name in sorted(new[section].keys() | old[section].keys()):
            if name not in new[section] or name not in old[section] or new[section][name] != old[section][name]:
                add(section + '_changed', name)
    before = {item['path']: item for item in old['files']}
    after = {item['path']: item for item in new['files']}
    for path in sorted(before.keys() | after.keys()):
        if path not in before:
            add('file_added', path)
        elif path not in after:
            add('file_deleted', path)
        elif before[path]['sha256'] != after[path]['sha256']:
            add('file_content_changed', path)
        elif before[path] != after[path]:
            add('file_identity_changed', path)
    result.update(status='observed', reason=reason if total else 'dependency summaries unchanged; receipt or policy cause unknown',
                  changes=changes, truncated=total > len(changes))
    return result


_DURATION = re.compile(r'^(?P<prefix>[| +\\`├─└│-]*)(?P<name>.+?) (?P<state>success|cached|failure) (?P<value>[0-9]+(?:\.[0-9]+)?)(?P<unit>ns|us|µs|ms|s|m|h)(?: MaxRSS:(?P<rss>[0-9.]+[KMGT]?))?$')
_TEST_DURATION = re.compile(r'^(?P<prefix>[| +\\`├─└│-]*)(?P<name>run test) (?P<counts>[0-9]{1,12} (?:pass|fail|skip)(?:, [0-9]{1,12} (?:pass|fail|skip))*) \((?P<total>[0-9]{1,12}) total\) (?P<value>[0-9]+(?:\.[0-9]+)?)(?P<unit>ns|us|µs|ms|s|m|h)(?: MaxRSS:(?P<rss>[0-9]+(?:\.[0-9]+)?[KMGT]?))?$')
_ANSI = re.compile(r'\x1b\[[0-9;]*m')


def execution_timings(log_path, *, capture_available=True):
    """Extract Zig summary observations, retaining nesting without summing it.

Bound bytes, line size and observations. Zig node names are observations, not
inventory action IDs; the coordinator supplies the enclosing action identity.
CPU time and aggregate concurrent RSS are unavailable from this format.
"""
    result = dict(status='unknown', observations=[], truncated=False, additive=False,
                  cpu_seconds=None, aggregate_peak_rss_bytes=None)
    if not capture_available:
        result['reason'] = 'current execution log unavailable'
        return result
    try:
        with Path(log_path).open('rb') as source:
            raw = source.read(MAX_BYTES + 1)
    except OSError:
        return result
    result['truncated'] = len(raw) > MAX_BYTES
    raw = raw[:MAX_BYTES]
    if result['truncated']:
        raw = raw.rsplit(b'\n', 1)[0] if b'\n' in raw else b''
    for line in raw.splitlines():
        if len(line) > MAX_LINE:
            result['truncated'] = True
            continue
        label = _ANSI.sub('', line.decode('utf-8', errors='replace'))
        test_match = _TEST_DURATION.fullmatch(label)
        counts = None
        if test_match:
            counts = {}
            for pair in test_match['counts'].split(', '):
                count, verdict = pair.split(' ')
                if verdict in counts:
                    counts = None
                    break
                counts[verdict] = int(count)
            if counts is None or sum(counts.values()) != int(test_match['total']):
                continue
            counts['total'] = int(test_match['total'])
        match = test_match or _DURATION.fullmatch(label)
        if not match:
            continue
        if not test_match and match['name'].startswith('run test') and (match['name'] != 'run test' or match['state'] == 'cached'):
            continue
        if len(result['observations']) >= MAX_OBSERVATIONS:
            result['truncated'] = True
            break
        seconds = float(match['value']) * {'ns': 1e-9, 'us': 1e-6, 'µs': 1e-6, 'ms': 1e-3, 's': 1, 'm': 60, 'h': 3600}[match['unit']]
        if not math.isfinite(seconds):
            continue
        result['observations'].append(dict(node=match['name'][:512], raw_label=label[:512],
                                           kind='test' if test_match else 'build' if match['name'].startswith('compile ') else 'unknown',
                                           state=('failure' if counts.get('fail', 0) else 'success') if test_match else match['state'],
                                           test_counts=counts,
                                           elapsed_seconds=seconds, tree_prefix=match['prefix'],
                                           peak_rss=match['rss'], source='zig-summary'))
    if result['observations']:
        result['status'] = 'observed'
    return result


def write_summary(path, summary):
    """Atomically publish advisory metadata; failure returns False, never raises."""
    temporary = None
    try:
        _validate(_decode(summary))
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8',
                                         dir=path.parent, delete=False) as output:
            temporary = output.name
            output.write(summary)
        os.replace(temporary, path)
        temporary = None
        return True
    except (OSError, ValueError, TypeError, RecursionError, UnicodeError):
        return False
    finally:
        if temporary is not None:
            try:
                os.unlink(temporary)
            except OSError:
                pass
