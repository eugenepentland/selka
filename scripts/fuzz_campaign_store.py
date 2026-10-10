#!/usr/bin/env python3
"""Disposable, bounded evidence for independent fuzz campaign shards.

Success records belong to exact action keys. Corpus catalogs only retain raw
inputs for replay; they never authorize a success on a different target.
All locks are local filesystem locks, independent of server admission.
"""
from contextlib import contextmanager
import fcntl
import hashlib
import json
import math
import marshal
import os
from pathlib import Path
import re
import stat
import tempfile
import sys
from typing import Callable
import uuid

LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()

BLOB_MAX_BYTES = 64 * 1024 * 1024
METADATA_MAX_BYTES = 1024 * 1024
CORPUS_MAX_ENTRIES = 1024
_IDENTITY = re.compile(r'[0-9a-f]{64}')


class InputsChanged(RuntimeError):
    """The caller's live input guard refused publication."""


class CorpusError(RuntimeError):
    """Retained corpus evidence is incomplete or corrupt; replay must restart."""


def _identity(value):
    if type(value) is not str or _IDENTITY.fullmatch(value) is None:
        raise ValueError('identity must be a lowercase SHA-256 digest')
    return value


def _digests(values):
    if type(values) is not list or len(values) > CORPUS_MAX_ENTRIES:
        raise ValueError('blob list exceeds the bounded list contract')
    for value in values:
        _identity(value)
    if len(set(values)) != len(values):
        raise ValueError('duplicate blob identity')
    return list(values)


def _json_value(value, depth=0):
    if depth > 64:
        raise ValueError('JSON nesting exceeds the evidence bound')
    if value is None or type(value) in (str, bool, int):
        return
    if type(value) is float and math.isfinite(value):
        return
    if type(value) is list:
        for child in value:
            _json_value(child, depth + 1)
        return
    if type(value) is dict and all(type(key) is str for key in value):
        for child in value.values():
            _json_value(child, depth + 1)
        return
    raise ValueError('evidence must contain only finite JSON values')


def _encoded(value):
    _json_value(value)
    data = json.dumps(value, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=True, allow_nan=False).encode('ascii')
    if len(data) > METADATA_MAX_BYTES:
        raise ValueError('evidence metadata exceeds the size bound')
    return data


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON field')
        result[key] = value
    return result


def _nonfinite(value):
    raise ValueError('nonfinite JSON value: ' + value)


def _envelope(payload):
    checksum = hashlib.sha256(_encoded(payload)).hexdigest()
    return _encoded({'payload': payload, 'checksum': checksum})


def _bounded_read(path, maximum):
    try:
        flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK | os.O_NOFOLLOW
        descriptor = os.open(path, flags)
        with os.fdopen(descriptor, 'rb') as stream:
            metadata = os.fstat(stream.fileno())
            if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > maximum:
                return None
            data = stream.read(maximum + 1)
        return data if len(data) <= maximum else None
    except OSError:
        return None


def _decode(data):
    if data is None:
        return None
    try:
        record = json.loads(data, object_pairs_hook=_unique,
                            parse_constant=_nonfinite)
        if type(record) is not dict or set(record) != {'payload', 'checksum'}:
            return None
        _identity(record['checksum'])
        payload = record['payload']
        if hashlib.sha256(_encoded(payload)).hexdigest() != record['checksum']:
            return None
        return payload
    except (ValueError, TypeError, UnicodeError, RecursionError, OverflowError):
        return None


def _atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix='.' + path.name + '-',
                                           dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
            stream.flush()
        os.replace(temporary, path)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


class Store:
    """A cache rooted at one directory; no directory scans or latest pointers."""

    def __init__(self, root: Path):
        self.root = Path(root)

    def _path(self, category, identity, suffix=''):
        return self.root / category / (_identity(identity) + suffix)

    @contextmanager
    def _lock(self, category, identity):
        path = self._path('locks/' + category, identity, '.lock')
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('a+b') as stream:
            fcntl.flock(stream.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)

    def coordinator_lock(self, family):
        """Serialize a family coordinator outside the server admission lock."""
        _identity(family)
        return self._lock('coordinator', family)

    def put_blob(self, data: bytes) -> str:
        """Atomically retain immutable bytes, repairing a corrupt old copy."""
        if type(data) is not bytes or len(data) > BLOB_MAX_BYTES:
            raise ValueError('blob must be bytes within the size bound')
        digest = hashlib.sha256(data).hexdigest()
        with self._lock('blob', digest):
            if self.read_blob(digest) is None:
                _atomic(self._path('blobs', digest), data)
        return digest

    def read_blob(self, digest) -> bytes | None:
        """Return bounded, checksum-verified bytes; missing/corrupt is a miss."""
        data = _bounded_read(self._path('blobs', digest), BLOB_MAX_BYTES)
        if data is None or hashlib.sha256(data).hexdigest() != digest:
            return None
        return data

    def _all_blobs(self, blobs):
        return all(self.read_blob(digest) is not None for digest in blobs)

    def _success(self, key):
        payload = _decode(_bounded_read(self._path('success', key, '.json'),
                                        METADATA_MAX_BYTES))
        fields = {'version', 'kind', 'key', 'publication', 'result', 'blobs'}
        if type(payload) is not dict or set(payload) != fields:
            return None
        if type(payload['version']) is not int or payload['version'] != 1:
            return None
        if payload['kind'] != 'fuzz-success' or payload['key'] != key:
            return None
        if type(payload['result']) is not dict:
            return None
        try:
            _identity(payload['publication'])
            blobs = _digests(payload['blobs'])
        except ValueError:
            return None
        return payload if self._all_blobs(blobs) else None

    def load_success(self, key) -> dict | None:
        """Return the exact saved result only when its entire manifest is valid."""
        _identity(key)
        with self._lock('success', key):
            payload = self._success(key)
            return payload['result'] if payload is not None else None

    def _remove_own(self, path, encoded):
        if _bounded_read(path, METADATA_MAX_BYTES) == encoded:
            path.unlink(missing_ok=True)

    def publish_success(self, key, result: dict, blobs: list[str],
                        validate: Callable[[], bool]) -> bool:
        """Publish a completed shard with guarded first-writer semantics.

        A valid conflicting publication wins. Both new and existing successes
        require the caller's guard before and after checking their evidence.
        Guard failure raises InputsChanged; only this call's publication is
        removed. A crash can leave disposable committed evidence, not a promise
        of durable application checkpointing.
        """
        _identity(key)
        if type(result) is not dict:
            raise ValueError('success result must be a JSON object')
        blobs = _digests(blobs)
        # Freeze caller-owned mutable structures before acquiring the lock.
        result = json.loads(_encoded(result))
        payload = {'version': 1, 'kind': 'fuzz-success', 'key': key,
                   'publication': hashlib.sha256(uuid.uuid4().bytes).hexdigest(),
                   'result': result, 'blobs': blobs}
        encoded = _envelope(payload)
        path = self._path('success', key, '.json')
        with self._lock('success', key):
            if not validate():
                raise InputsChanged('inputs changed before publication')
            if not self._all_blobs(blobs):
                return False
            existing = self._success(key)
            if existing is not None:
                if not validate():
                    raise InputsChanged('inputs changed while checking success')
                return (self._all_blobs(existing['blobs'])
                        and existing['result'] == result and existing['blobs'] == blobs)
            try:
                _atomic(path, encoded)
                if not validate():
                    raise InputsChanged('inputs changed after publication')
                if not self._all_blobs(blobs):
                    self._remove_own(path, encoded)
                    return False
                return True
            except BaseException:
                self._remove_own(path, encoded)
                raise

    def discard_success(self, key):
        """Remove only this exact action's disposable success record."""
        _identity(key)
        with self._lock('success', key):
            self._path('success', key, '.json').unlink(missing_ok=True)

    def _corpus(self, family):
        path = self._path('corpus', family, '.json')
        try:
            path.stat()
        except FileNotFoundError:
            return []
        except OSError as error:
            raise CorpusError('cannot read corpus catalog') from error
        payload = _decode(_bounded_read(path, METADATA_MAX_BYTES))
        fields = {'version', 'kind', 'family', 'blobs'}
        if type(payload) is not dict or set(payload) != fields:
            raise CorpusError('invalid corpus catalog')
        valid = (type(payload['version']) is int and payload['version'] == 1
                 and payload['kind'] == 'fuzz-corpus' and payload['family'] == family)
        if not valid:
            raise CorpusError('foreign corpus catalog')
        try:
            blobs = _digests(payload['blobs'])
        except ValueError as error:
            raise CorpusError('invalid corpus manifest') from error
        if not self._all_blobs(blobs):
            raise CorpusError('missing or corrupt retained corpus blob')
        return blobs

    def load_corpus(self, family) -> list[str]:
        """Absent catalogs are empty; incomplete catalogs raise CorpusError."""
        _identity(family)
        with self._lock('corpus', family):
            return self._corpus(family)

    def discard_corpus(self, family):
        """Explicitly reset a broken catalog while holding coordinator_lock.

        Immutable blobs remain available for recovery from valid shard records.
        """
        _identity(family)
        with self._lock('corpus', family):
            self._path('corpus', family, '.json').unlink(missing_ok=True)

    def retain_corpus(self, family, blobs: list[str]) -> bool:
        """Atomically union bounded raw evidence, including failed campaigns."""
        _identity(family)
        incoming = _digests(blobs)
        with self._lock('corpus', family):
            if not self._all_blobs(incoming):
                return False
            union = sorted(set(self._corpus(family)) | set(incoming))
            if len(union) > CORPUS_MAX_ENTRIES:
                raise ValueError('corpus union exceeds the entry bound')
            payload = {'version': 1, 'kind': 'fuzz-corpus',
                       'family': family, 'blobs': union}
            _atomic(self._path('corpus', family, '.json'), _envelope(payload))
            return True
