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
import threading
import time
from typing import Callable
import uuid

LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()

BLOB_MAX_BYTES = 64 * 1024 * 1024
METADATA_MAX_BYTES = 1024 * 1024
CORPUS_MAX_ENTRIES = 1024
_IDENTITY = re.compile(r'[0-9a-f]{64}')
_FORMAT = {'version': 1, 'layout': 'shared-cas-v1', 'digest': 'sha256'}
_CATEGORIES = ('blobs', 'success', 'corpus', 'pins', 'conflicts', 'invalidated')
_GC_METADATA_MAX_BYTES = 64 * 1024 * 1024


class FormatError(RuntimeError):
    """An unknown store layout cannot safely serve or collect cache evidence."""


class DeterminismError(RuntimeError):
    """An exact deterministic action produced conflicting completed evidence."""


class RetentionError(RuntimeError):
    """Retention metadata or inventory bounds prevent safe collection."""


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
    """Versioned local CAS; collection is explicit and requires an idle store."""

    def __init__(self, root: Path):
        self.root = Path(root).resolve()
        self._leases = threading.local()
        self.root.mkdir(parents=True, exist_ok=True)
        if not stat.S_ISDIR(self.root.lstat().st_mode):
            raise FormatError('cache root must be a real directory')
        value = self.root.lstat()
        self._root_identity = (value.st_dev, value.st_ino)
        marker = self.root / 'format.json'
        if os.path.lexists(marker):
            self._check_format()
        else:
            # Existing receipts have no layout declaration: do not guess which
            # producer owns them. Initializers serialize on a permanent inode.
            known = {'locks', 'format.json'}
            def known_entry(entry):
                return entry.name in known or re.fullmatch(r'\.format\.json-[A-Za-z0-9_]+', entry.name)
            with os.scandir(self.root) as entries:
                if any(not known_entry(entry) for entry in entries):
                    raise FormatError('unversioned nonempty cache; use a new empty versioned cache root')
            self._directory('locks')
            descriptor = self._lock_descriptor(self.root / 'locks/retention.lock')
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX)
                if os.path.lexists(marker):
                    self._check_format()
                else:
                    with os.scandir(self.root) as entries:
                        for entry in entries:
                            if not known_entry(entry):
                                raise FormatError('unversioned nonempty cache; use a new empty versioned cache root')
                            if entry.name.startswith('.format.json-'):
                                if not entry.is_file(follow_symlinks=False):
                                    raise FormatError('format initialization leftover is not a regular file')
                                os.unlink(entry.path)
                    _atomic(marker, _envelope(_FORMAT))
            finally:
                os.close(descriptor)
        for category in ('locks', *_CATEGORIES):
            self._directory(category)

    def _check_format(self):
        self._check_root()
        value = _decode(_bounded_read(self.root / 'format.json', METADATA_MAX_BYTES))
        if value != _FORMAT or type(value.get('version')) is not int:
            raise FormatError('unsupported or corrupt shared cache format')

    def _check_root(self):
        value = self.root.lstat()
        if not stat.S_ISDIR(value.st_mode) or (value.st_dev, value.st_ino) != self._root_identity:
            raise FormatError('cache root was replaced or redirected')

    def _directory(self, category):
        self._check_root()
        path = self.root
        for name in category.split('/'):
            path = path / name
            path.mkdir(exist_ok=True)
            if not stat.S_ISDIR(path.lstat().st_mode):
                raise FormatError('cache category must be a real directory: ' + str(path))
        return path

    @staticmethod
    def _lock_descriptor(path):
        descriptor = os.open(path, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            os.close(descriptor)
            raise FormatError('cache lock must be a regular file')
        return descriptor

    def _lease_state(self):
        state = getattr(self._leases, 'state', None)
        if state is not None and state['pid'] != os.getpid():
            # A forked child closes its inherited reference without unlocking
            # the parent's shared open-file description.
            os.close(state['fd'])
            self._leases.state = state = None
        return state

    @contextmanager
    def lease(self):
        """Keep all cache inputs alive through a complete operation; nest safely.

        This is a local shared flock, independent of server admission. Process
        exit releases it; explicit GC skips rather than waits for active leases.
        """
        state = self._lease_state()
        if state is not None:
            state['depth'] += 1
            try:
                yield self
            finally:
                state['depth'] -= 1
            return
        self._check_root()
        descriptor = self._lock_descriptor(self.root / 'locks/retention.lock')
        try:
            fcntl.flock(descriptor, fcntl.LOCK_SH)
            self._check_format()
            self._leases.state = {'pid': os.getpid(), 'fd': descriptor, 'depth': 1}
            try:
                yield self
            finally:
                self._leases.state = None
        finally:
            os.close(descriptor)

    def _path(self, category, identity, suffix=''):
        name = _identity(identity) + suffix
        return self._directory(category) / name

    @contextmanager
    def _lock(self, category, identity):
        path = self._path('locks/' + category, identity, '.lock')
        self._directory('locks/' + category)
        with self.lease():
            descriptor = self._lock_descriptor(path)
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX)
                yield
            finally:
                os.close(descriptor)

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
        with self.lease():
            data = _bounded_read(self._path('blobs', digest), BLOB_MAX_BYTES)
            if data is None or hashlib.sha256(data).hexdigest() != digest:
                return None
            return data

    def _all_blobs(self, blobs):
        return all(self.read_blob(digest) is not None for digest in blobs)

    def _success_metadata(self, key):
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
        return payload

    def _success(self, key):
        payload = self._success_metadata(key)
        return payload if payload is not None and self._all_blobs(payload['blobs']) else None

    def load_success(self, key) -> dict | None:
        """Return the exact saved result only when its entire manifest is valid."""
        _identity(key)
        with self._lock('success', key):
            if any(os.path.lexists(self._path(category, key, '.json')) for category in ('conflicts', 'invalidated')):
                return None
            payload = self._success(key)
            return payload['result'] if payload is not None else None

    def _remove_own(self, path, encoded):
        if _bounded_read(path, METADATA_MAX_BYTES) == encoded:
            path.unlink(missing_ok=True)

    def publish_success(self, key, result: dict, blobs: list[str],
                        validate: Callable[[], bool]) -> bool:
        """Publish completed deterministic evidence with guarded equality checks.

        Conflicting results poison this action until explicitly investigated.
        Both new and existing successes
        require the caller's guard before and after checking their evidence.
        Guard failure raises InputsChanged; only this call's publication is
        removed. A crash can leave disposable committed evidence, not a promise
        of durable application checkpointing.
        """
        _identity(key)
        if type(result) is not dict:
            raise ValueError('success result must be a JSON object')
        blobs = sorted(_digests(blobs))
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
            if os.path.lexists(self._path('conflicts', key, '.json')):
                raise DeterminismError('action has an unresolved deterministic conflict: ' + key)
            existing = self._success_metadata(key)
            if existing is not None:
                if not validate():
                    raise InputsChanged('inputs changed while checking success')
                if _encoded(existing['result']) != _encoded(result) or sorted(existing['blobs']) != blobs:
                    conflict = {'version': 1, 'kind': 'determinism-conflict', 'key': key,
                                'old_result': hashlib.sha256(_encoded(existing['result'])).hexdigest(),
                                'new_result': hashlib.sha256(_encoded(result)).hexdigest(),
                                'old_blobs': existing['blobs'], 'new_blobs': blobs}
                    conflict_path = self._path('conflicts', key, '.json')
                    conflict_bytes = _envelope(conflict)
                    try:
                        _atomic(conflict_path, conflict_bytes)
                        if not validate():
                            raise InputsChanged('inputs changed after conflict publication')
                    except BaseException:
                        self._remove_own(conflict_path, conflict_bytes)
                        raise
                    raise DeterminismError('same action produced different completed evidence: ' + key)
                self._finish_refresh(key, validate, path, _bounded_read(path, METADATA_MAX_BYTES))
                return True
            try:
                _atomic(path, encoded)
                if not validate():
                    raise InputsChanged('inputs changed after publication')
                if not self._all_blobs(blobs):
                    self._remove_own(path, encoded)
                    return False
                self._finish_refresh(key, validate, path, encoded)
                return True
            except BaseException:
                self._remove_own(path, encoded)
                raise

    def discard_success(self, key):
        """Remove only this exact action's disposable success record."""
        _identity(key)
        with self._lock('success', key):
            self._path('success', key, '.json').unlink(missing_ok=True)
            self._path('invalidated', key, '.json').unlink(missing_ok=True)

    def invalidate_success(self, key):
        """Require fresh work while retaining completed deterministic comparison.

        A failed refresh cannot revive the old hit. The comparison survives only
        normal cache retention limits; an explicitly pinned receipt keeps it.
        The caller must hold the matching shared-store coordinator_lock across
        invalidation, work and publication, including failure cleanup. Per-call
        success locks protect atomic records, not this complete refresh protocol.
        """
        with self._lock('success', key):
            value = {'version': 1, 'kind': 'invalidated-success', 'key': key}
            _atomic(self._path('invalidated', key, '.json'), _envelope(value))

    def _finish_refresh(self, key, validate, receipt_path, receipt_bytes):
        marker = self._path('invalidated', key, '.json')
        if not os.path.lexists(marker):
            return
        self._retention_record('invalidated', key)
        previous = _bounded_read(marker, METADATA_MAX_BYTES)
        try:
            marker.unlink()
            if not validate():
                raise InputsChanged('inputs changed while restoring invalidated success')
        except BaseException:
            try:
                _atomic(marker, previous)
            except BaseException:
                # If restoring negative evidence fails, remove the old proof.
                # Losing comparison history is preferable to authorizing reuse.
                self._remove_own(receipt_path, receipt_bytes)
                raise
            raise

    def clear_conflict(self, key):
        """Explicitly discard poisoned evidence after investigating its mismatch."""
        _identity(key)
        with self._lock('success', key):
            self._path('success', key, '.json').unlink(missing_ok=True)
            self._path('conflicts', key, '.json').unlink(missing_ok=True)
            self._path('invalidated', key, '.json').unlink(missing_ok=True)

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

    def pin(self, pin_id, *, success=None, corpus=None, blobs=None):
        """Retain explicit receipt/catalog snapshots and their payloads until unpin.

        Pins only affect disposable cache retention, not validity or durability.
        The resolved payload list is frozen even if a catalog later changes.
        """
        success, corpus, blobs = (_digests(value if value is not None else []) for value in (success, corpus, blobs))
        with self._lock('pins', pin_id):
            resolved = set(blobs)
            for key in success:
                if os.path.lexists(self._path('conflicts', key, '.json')):
                    raise DeterminismError('cannot pin a conflicted action: ' + key)
                record = self._success(key)
                if record is None:
                    raise RetentionError('cannot pin missing or corrupt receipt: ' + key)
                resolved.update(record['blobs'])
                if len(resolved) > CORPUS_MAX_ENTRIES:
                    raise RetentionError('pin payload list exceeds bounded manifest')
            for family in corpus:
                if not self._path('corpus', family, '.json').exists():
                    raise RetentionError('cannot pin missing corpus: ' + family)
                resolved.update(self._corpus(family))
                if len(resolved) > CORPUS_MAX_ENTRIES:
                    raise RetentionError('pin payload list exceeds bounded manifest')
            resolved = _digests(sorted(resolved))
            if not self._all_blobs(resolved):
                raise RetentionError('cannot pin missing or corrupt payloads')
            payload = {'version': 1, 'kind': 'retention-pin', 'key': _identity(pin_id),
                       'success': success, 'corpus': corpus, 'blobs': resolved}
            _atomic(self._path('pins', pin_id, '.json'), _envelope(payload))

    def unpin(self, pin_id):
        """Release explicit retention; complete receipts remain ordinary GC roots."""
        with self._lock('pins', pin_id):
            self._path('pins', pin_id, '.json').unlink(missing_ok=True)

    def _retention_record(self, category, key):
        """Read bounded checksum/schema metadata without hashing payload bodies."""
        value = _decode(_bounded_read(self._path(category, key, '.json'), METADATA_MAX_BYTES))
        common = type(value) is dict and type(value.get('version')) is int and value['version'] == 1
        try:
            if not common:
                raise ValueError('invalid record envelope')
            if category == 'success':
                fields = {'version', 'kind', 'key', 'publication', 'result', 'blobs'}
                if (set(value) != fields or value['kind'] != 'fuzz-success'
                        or value['key'] != key or type(value['result']) is not dict):
                    raise ValueError('invalid success schema')
                _identity(value['publication'])
                _digests(value['blobs'])
            elif category == 'corpus':
                if (set(value) != {'version', 'kind', 'family', 'blobs'}
                        or value['kind'] != 'fuzz-corpus' or value['family'] != key):
                    raise ValueError('invalid corpus schema')
                _digests(value['blobs'])
            elif category == 'pins':
                if (set(value) != {'version', 'kind', 'key', 'success', 'corpus', 'blobs'}
                        or value['kind'] != 'retention-pin' or value['key'] != key):
                    raise ValueError('invalid pin schema')
                for field in ('success', 'corpus', 'blobs'):
                    _digests(value[field])
            elif category == 'invalidated':
                if (set(value) != {'version', 'kind', 'key'} or value['kind'] != 'invalidated-success'
                        or value['key'] != key):
                    raise ValueError('invalid invalidation schema')
            else:
                fields = {'version', 'kind', 'key', 'old_result', 'new_result', 'old_blobs', 'new_blobs'}
                if set(value) != fields or value['kind'] != 'determinism-conflict' or value['key'] != key:
                    raise ValueError('invalid conflict schema')
                for field in ('old_result', 'new_result'):
                    _identity(value[field])
                for field in ('old_blobs', 'new_blobs'):
                    _digests(value[field])
            return value
        except (KeyError, ValueError, TypeError):
            raise RetentionError('corrupt retention record; explicitly discard before collecting: '
                                 + str(self._path(category, key, '.json')))

    def _inventory(self, max_entries):
        rows, lock_bytes, foreign, lock_files, metadata_bytes = [], 0, 0, 0, 0
        count = 0

        def entries(directory):
            nonlocal count
            with os.scandir(directory) as stream:
                for entry in stream:
                    count += 1
                    if count > max_entries:
                        raise RetentionError('cache inventory exceeds max_entries; nothing collected')
                    yield entry

        for category in _CATEGORIES:
            for entry in entries(self._directory(category)):
                suffix = '' if category == 'blobs' else '.json'
                key = entry.name[:-len(suffix)] if suffix else entry.name
                metadata = entry.stat(follow_symlinks=False)
                valid_name = entry.name.endswith(suffix) and _IDENTITY.fullmatch(key)
                temporary = re.fullmatch(r'\.[0-9a-f]{64}(?:\.json)?-[A-Za-z0-9_]+', entry.name)
                if not stat.S_ISREG(metadata.st_mode) or not (valid_name or temporary):
                    if category in ('pins', 'conflicts'):
                        raise RetentionError('unknown protected retention entry: ' + str(Path(entry.path)))
                    foreign += 1
                    continue
                if valid_name and category != 'blobs':
                    metadata_bytes += metadata.st_size
                    if metadata_bytes > _GC_METADATA_MAX_BYTES:
                        raise RetentionError('GC metadata exceeds bounded 64MiB inventory; nothing collected')
                value = self._retention_record(category, key) if valid_name and category != 'blobs' else None
                rows.append({'path': Path(entry.path), 'category': category, 'key': key,
                             'size': metadata.st_size, 'time': metadata.st_mtime,
                             'record': value, 'temporary': bool(temporary)})
        for entry in entries(self._directory('locks')):
            metadata = entry.stat(follow_symlinks=False)
            if stat.S_ISREG(metadata.st_mode):
                if entry.name != 'retention.lock':
                    raise RetentionError('unknown permanent lock entry; nothing collected')
                lock_bytes += metadata.st_size
                lock_files += 1
            elif stat.S_ISDIR(metadata.st_mode):
                for child in entries(Path(entry.path)):
                    value = child.stat(follow_symlinks=False)
                    if not stat.S_ISREG(value.st_mode) or not re.fullmatch(r'[0-9a-f]{64}\.lock', child.name):
                        raise RetentionError('unknown lock entry; nothing collected')
                    lock_files += 1
                    rows.append({'path': Path(child.path), 'category': 'locks', 'key': child.name[:-5],
                                 'size': value.st_size, 'time': value.st_mtime,
                                 'record': None, 'temporary': False})
            else:
                raise RetentionError('unknown lock directory; nothing collected')
        return rows, lock_bytes, foreign, count, lock_files

    def gc(self, *, max_bytes=None, max_age=None, dry_run=True, max_entries=100000):
        """Plan or collect idle local evidence, keeping pins and the lease inode.

        max_bytes bounds managed payload/metadata and idle per-key lock bytes,
        not the fixed format/lease files or filesystem allocation overhead.
        Every per-key waiter already holds a shared lease before opening its
        inode, so exclusive GC can safely unlink idle per-key lock files.
        max_age is seconds since last write;
        lookups do not refresh age. Collection never treats retention as proof.
        """
        if max_bytes is not None and (type(max_bytes) is not int or max_bytes < 0):
            raise ValueError('max_bytes must be a nonnegative integer')
        if max_age is not None and (type(max_age) not in (int, float) or not math.isfinite(max_age) or max_age < 0):
            raise ValueError('max_age must be finite nonnegative seconds')
        if type(dry_run) is not bool or type(max_entries) is not int or not 0 < max_entries <= 1000000:
            raise ValueError('invalid GC dry_run or inventory bound')
        if self._lease_state() is not None:
            return {'version': 1, 'skipped_active': True, 'dry_run': dry_run}
        self._check_root()
        descriptor = self._lock_descriptor(self.root / 'locks/retention.lock')
        try:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return {'version': 1, 'skipped_active': True, 'dry_run': dry_run}
            self._check_format()
            rows, lock_bytes, foreign, count, lock_files = self._inventory(max_entries)
            return self._collect(rows, lock_bytes, foreign, count, lock_files, max_bytes, max_age, dry_run)
        finally:
            os.close(descriptor)

    def _collect(self, rows, lock_bytes, foreign, count, lock_files, max_bytes, max_age, dry_run):
        now = time.time()
        protected, pinned_blobs = set(), set()
        for row in rows:
            if row['category'] == 'pins' and not row['temporary']:
                value = row['record']
                protected.update(('success', key) for key in value['success'])
                protected.update(('corpus', key) for key in value['corpus'])
                pinned_blobs.update(value['blobs'])
            elif row['category'] == 'conflicts' and not row['temporary']:
                pinned_blobs.update(row['record']['old_blobs'] + row['record']['new_blobs'])
                protected.add(('success', row['key']))
        protected.update(('invalidated', key) for category, key in tuple(protected) if category == 'success')
        invalidated = {row['key']: row for row in rows if row['category'] == 'invalidated' and not row['temporary']}
        successes = {row['key']: row for row in rows if row['category'] == 'success' and not row['temporary']}
        removed = set()
        before = sum(row['size'] for row in rows)
        remaining_bytes = before
        refs = {}
        blobs = {row['key']: row for row in rows if row['category'] == 'blobs' and not row['temporary']}
        for digest in pinned_blobs:
            refs[digest] = 1
        for row in rows:
            if row['category'] in ('success', 'corpus') and row['record']:
                for digest in row['record']['blobs']:
                    refs[digest] = refs.get(digest, 0) + 1

        def remove(row):
            nonlocal remaining_bytes
            if row['path'] in removed:
                return
            removed.add(row['path'])
            remaining_bytes -= row['size']
            if row['category'] in ('success', 'corpus') and row['record']:
                for digest in row['record']['blobs']:
                    refs[digest] -= 1
            if row['category'] == 'success' and row['key'] in invalidated:
                remove(invalidated[row['key']])

        def cohort_time(row):
            partner = invalidated.get(row['key']) if row['category'] == 'success' else None
            return max(row['time'], partner['time']) if partner else row['time']

        def expired(row):
            return max_age is not None and now - cohort_time(row) > max_age

        candidates = sorted((row for row in rows if (row['category'] in ('success', 'corpus')
                             or row['category'] == 'invalidated' and row['key'] not in successes)
                             and (row['category'], row['key']) not in protected),
                            key=lambda row: (cohort_time(row), str(row['path'])))
        for row in rows:
            if row['temporary'] or row['category'] == 'locks':
                remove(row)
        for row in candidates:
            if expired(row):
                remove(row)
        # Sweep eligible orphans before evicting useful receipt roots.
        for row in rows:
            if row['category'] == 'blobs' and not refs.get(row['key'], 0):
                if max_bytes is not None or max_age is None or expired(row):
                    remove(row)
        if max_bytes is not None:
            for row in candidates:
                if remaining_bytes <= max_bytes:
                    break
                remove(row)
                for digest in row['record'].get('blobs', ()) if row['record'] else ():
                    if not refs.get(digest, 0) and digest in blobs:
                        remove(blobs[digest])
        selected = [row for row in rows if row['path'] in removed]
        after = remaining_bytes
        if not dry_run:
            # Receipts go first: an interrupted collector can leave orphan bytes,
            # but must never leave a retained receipt pointing to deleted bytes.
            order = {'success': 0, 'corpus': 0, 'pins': 1, 'conflicts': 1, 'invalidated': 2, 'locks': 3, 'blobs': 4}
            selected.sort(key=lambda row: (order[row['category']], str(row['path'])))
            for row in selected:
                row['path'].unlink()
        return {'version': 1, 'skipped_active': False, 'dry_run': dry_run,
                'scanned_entries': count, 'foreign_entries': foreign, 'lock_bytes': lock_bytes,
                'lock_files': lock_files, 'format_bytes': (self.root / 'format.json').stat().st_size,
                'removed_lock_files': sum(row['category'] == 'locks' for row in selected),
                'retained_lock_files': lock_files - sum(row['category'] == 'locks' for row in selected),
                'bytes_before': before, 'bytes_after': after, 'removed_bytes': before - after,
                'removed_entries': len(selected), 'retained_entries': len(rows) - len(selected),
                'protected_entries': sum(row['category'] in ('pins', 'conflicts')
                                         or (row['category'], row['key']) in protected
                                         or row['category'] == 'blobs' and row['key'] in pinned_blobs for row in rows),
                'budget_unmet': max_bytes is not None and after > max_bytes,
                'paths': [str(row['path'].relative_to(self.root)) for row in sorted(selected, key=lambda row: str(row['path']))]}
