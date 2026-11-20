"""Process-local inotify transport; every borrower retains independent authority.

This shares kernel watches, never a snapshot's selectors or successful result.
All events are delivered before any borrower can validate its own state. An
unreadable/lost transport revokes every borrower; forked borrowers cannot drain
an inherited queue. No state is serialized or shared between processes.
"""
from __future__ import annotations

import ctypes
import os
import struct
import sys
import threading
import verification_code_identity as code_identity


_EVENT = struct.Struct('iIII')
_OVERFLOW = 0x4000
_IGNORED = 0x8000
_MASK_ADD = 0x20000000
_global_lock = threading.RLock()
_current = None
_MAX_DEFERRED = 16384


def _after_fork():
    global _global_lock, _current
    _global_lock = threading.RLock()
    _current = None


os.register_at_fork(after_in_child=_after_fork)


class WatchPoolError(RuntimeError):
    pass


class Lease:
    def __init__(self, pool, event, failure):
        self.pool = pool
        self.event = event
        self.failure = failure
        self.watches = set()
        self.installing = set()
        self.deferred = []
        self.invalid_reason = None
        self.closed = False

    @property
    def fd(self):
        return -1 if self.closed else self.pool.fd

    def add(self, path, mask, install):
        """Install local selector state under the same lock as event delivery."""
        try:
            return self.pool.add(self, path, mask, install)
        except BaseException:
            self.close()
            raise

    def drain(self):
        self.pool.check(self)  # Never acquire a lock inherited from another thread.
        with self.pool.lock:
            self.pool.check(self)
            self.pool.drain()
            self.pool.check(self)
            # The consumer has now finished populating mutable selectors. Events
            # received by another borrower during installation stayed local and
            # bounded, rather than getting lost or invalidating unrelated paths.
            self.installing.clear()
            pending, self.deferred = self.deferred, []
            try:
                for descriptor, mask, name in pending:
                    self.event(descriptor, mask, name, False)
            except BaseException:
                self.invalid_reason = 'inotify deferred delivery interrupted; input history is incomplete'
                self.failure(self.invalid_reason)
                raise

    def close(self):
        self.pool.close(self)


class _Pool:
    def __init__(self, libc):
        self.pid = os.getpid()
        self.libc = libc
        self.fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if self.fd < 0:
            raise WatchPoolError('inotify_init1 failed: ' + os.strerror(ctypes.get_errno()))
        self.lock = threading.RLock()
        self.clients = set()
        self.owners = {}
        self.removing = set()
        self.failure = None

    def check(self, client=None):
        if self.pid != os.getpid():
            raise WatchPoolError('forked process cannot use inherited inotify authority')
        if self.failure is not None:
            raise WatchPoolError(self.failure)
        if self.fd < 0 or client is not None and client.closed:
            raise WatchPoolError('inotify transport is closed')
        if client is not None and client.invalid_reason is not None:
            raise WatchPoolError(client.invalid_reason)

    def invalidate(self, message):
        self.failure = str(message)
        for client in tuple(self.clients):
            client.failure(self.failure)
        # Revoke the descriptor as well as the leases. Old borrowers must not
        # later rm_watch/close a descriptor number reused by a fresh pool.
        descriptor, self.fd = self.fd, -1
        if descriptor >= 0:
            try:
                os.close(descriptor)
            except OSError:
                pass

    def revoke(self, message):
        self.invalidate(message)
        raise WatchPoolError(self.failure)

    def attach(self, event, failure):
        self.check()
        with self.lock:
            self.check()
            self.drain()  # Earlier events belong exclusively to earlier clients.
            client = Lease(self, event, failure)
            self.clients.add(client)
            return client

    def add(self, client, path, mask, install):
        self.check(client)
        with self.lock:
            self.check(client)
            self.drain()
            descriptor = self.libc.inotify_add_watch(self.fd, os.fsencode(path), mask | _MASK_ADD)
            if descriptor < 0:
                raise WatchPoolError(f'cannot watch {path}: {os.strerror(ctypes.get_errno())}')
            # The kernel deduplicates inode watches on this shared descriptor,
            # including paths reached through distinct hardlinks.
            self.owners.setdefault(descriptor, set()).add(client)
            client.watches.add(descriptor)
            client.installing.add(descriptor)
            return install(descriptor)

    def drain(self):
        try:
            self._drain()
        except WatchPoolError:
            raise
        except BaseException:
            self.invalidate('inotify event delivery interrupted; input history is incomplete')
            raise

    def _drain(self):
        self.check()
        while True:
            try:
                data = os.read(self.fd, 1 << 16)
            except BlockingIOError:
                return
            except InterruptedError:
                continue
            except OSError as error:
                self.revoke('cannot read inotify: ' + str(error))
            if not data:
                self.revoke('inotify unexpectedly closed')
            at = 0
            while at < len(data):
                if len(data) - at < _EVENT.size:
                    self.revoke('truncated inotify event')
                descriptor, mask, _cookie, length = _EVENT.unpack_from(data, at)
                at += _EVENT.size
                if length > len(data) - at:
                    self.revoke('truncated inotify event name')
                name = data[at:at + length].split(b'\0', 1)[0]
                at += length
                if mask & _OVERFLOW:
                    self.revoke('inotify queue overflow; input history is incomplete')
                if descriptor in self.removing:
                    if mask & _IGNORED:
                        self.removing.remove(descriptor)
                    continue
                clients = self.owners.get(descriptor)
                if not clients:
                    self.revoke('unknown inotify watch; input history is incomplete')
                for client in tuple(clients):
                    if descriptor in client.installing:
                        if len(client.deferred) >= _MAX_DEFERRED:
                            client.invalid_reason = 'inotify deferred event bound exceeded; input history is incomplete'
                            client.failure(client.invalid_reason)
                        else:
                            client.deferred.append((descriptor, mask, name))
                        continue
                    try:
                        client.event(descriptor, mask, name, False)
                    except Exception as error:
                        self.revoke('inotify consumer could not retain event: ' + str(error))

    def close(self, client):
        # Do this before taking any inherited mutex: another parent thread may
        # have held it across fork. Never rm_watch on the parent's kernel queue.
        if self.pid != os.getpid():
            client.closed = True
            if self.fd >= 0:
                os.close(self.fd)
                self.fd = -1
            return
        with self.lock:
            if client.closed:
                return
            client.closed = True
            self.clients.discard(client)
            for descriptor in client.watches:
                owners = self.owners.get(descriptor)
                if owners is None:
                    continue
                owners.discard(client)
                if owners:
                    continue
                self.owners.pop(descriptor)
                # Retire the wd before rm_watch queues IN_IGNORED. Drain that
                # event before the next add can recycle the same descriptor.
                self.removing.add(descriptor)
                if self.fd >= 0:
                    self.libc.inotify_rm_watch(self.fd, descriptor)
            client.watches.clear()
            if not self.clients:
                if self.fd >= 0:
                    os.close(self.fd)
                self.fd = -1
            elif self.failure is None:
                try:
                    self.drain()
                except WatchPoolError:
                    pass  # All survivors now carry the explicit failure.


def acquire(libc, event, failure):
    """Acquire a local consumer, refusing every inherited or failed authority."""
    global _current
    with _global_lock:
        if (_current is None or _current.pid != os.getpid()
                or _current.fd < 0 or _current.failure is not None):
            _current = _Pool(libc)
        return _current.attach(event, failure)


_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)
