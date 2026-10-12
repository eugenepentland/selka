"""Bounded coordinator-owned measurement windows over shared timing admission.

Only an in-process window can authorize commands to reuse its admission. Ambient
environment markers never grant that capability. The holder remains alive through
validation, execution, publication and reporting; queue time precedes the deadline.
"""
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass, field
import math
import os
import signal
import sys
import verification_code_identity as code_identity
import time

import build_admission


class WindowExpired(BaseException):
    """The explicitly requested measurement window exhausted its execution bound."""

    status = 124


class WindowLost(OSError):
    """The real admission holder exited before the measured request completed."""


@dataclass
class Window:
    seconds: float
    queued_at: float
    started_at: float
    pid: int
    holder: object
    open: bool = True
    rollbacks: list = field(default_factory=list)
    coordinator_lock_wait_seconds: float = 0.0

    def revoke(self):
        failure = None
        for rollback in reversed(self.rollbacks):
            try:
                rollback()
            except BaseException as error:
                failure = error
        if failure is not None:
            raise WindowLost("could not revoke interrupted measurement publications") from failure

    def check(self):
        if not self.open or os.getpid() != self.pid:
            raise RuntimeError("measurement admission belongs to another process or closed window")
        if self.holder.poll() is not None:
            raise WindowLost("measurement admission holder exited before completion")
        if time.monotonic() - self.started_at >= self.seconds:
            raise WindowExpired("measurement window expired after %.3f seconds" % self.seconds)

    def report(self):
        return {"version": 1, "kind": "exclusive-coordinator-request",
                "admission_wait_seconds": self.started_at - self.queued_at,
                "coordinator_lock_wait_seconds": self.coordinator_lock_wait_seconds,
                "elapsed_seconds": time.monotonic() - self.started_at,
                "deadline_seconds": self.seconds,
                "scope": "request start through final report assembly; report write, final output and session startup excluded",
                "slot_directory": str(build_admission.slot_directory())}


_CURRENT = ContextVar("verification_measurement_window", default=None)


def current():
    """Return only this process's still-valid admitted timing capability."""
    window = _CURRENT.get()
    if window is not None:
        window.check()
    return window


def validate(seconds):
    """An explicit finite positive duration is a bound, never a latency target."""
    if type(seconds) not in (int, float) or not math.isfinite(seconds) or seconds <= 0:
        raise ValueError("timing window seconds must be positive and finite")


@contextmanager
def timing_window(seconds, *, coordinator_lock_wait_seconds=0.0):
    """Acquire the real timing queue, bound the request, and always release it."""
    validate(seconds)
    if _CURRENT.get() is not None or any(os.environ.get(key) for key in build_admission.MARKERS):
        raise ValueError("run verification directly; timing windows cannot inherit outer admission")
    if signal.getitimer(signal.ITIMER_REAL) != (0.0, 0.0):
        raise ValueError("measurement window cannot replace an existing process deadline")
    queued_at = time.monotonic()
    window = None
    try:
        with build_admission.admission("timing") as holder:
            window = Window(float(seconds), queued_at, time.monotonic(), os.getpid(), holder)
            window.coordinator_lock_wait_seconds = coordinator_lock_wait_seconds
            previous_handler = signal.getsignal(signal.SIGALRM)
            def expired(_signum, _frame):
                raise WindowExpired("measurement window expired after %.3f seconds" % seconds)
            token = _CURRENT.set(window)
            complete = False
            try:
                signal.signal(signal.SIGALRM, expired)
                signal.setitimer(signal.ITIMER_REAL, seconds)
                yield window
                window.check()
                complete = True
            finally:
                signal.setitimer(signal.ITIMER_REAL, 0)
                signal.signal(signal.SIGALRM, previous_handler)
                window.open = False
                _CURRENT.reset(token)
                if not complete:
                    window.revoke()
    except build_admission.AdmissionLost as error:
        if window is not None and complete:
            window.revoke()
        raise WindowLost(str(error)) from error


def worker_environment(environment):
    """Give child developer harnesses the markers of our actual timing holder."""
    window = current()
    if window is None:
        return environment
    if (os.environ.get("MYLANG_ADMISSION_KIND") != "timing"
            or os.environ.get("MYLANG_ADMISSION_DIR") != str(build_admission.slot_directory())):
        raise RuntimeError("measurement holder lost its admission markers")
    return dict(environment, **{name: os.environ[name] for name in build_admission.MARKERS})


# The coordinator includes this actual loaded object in its implementation proof.
_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)
