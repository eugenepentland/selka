#!/usr/bin/env python3
"""Ensure a killed coordinator cannot leave an unshare worker running."""
import ctypes
import os
import signal
import sys

libc = ctypes.CDLL(None, use_errno=True)
expected_parent = int(sys.argv[1])
if libc.prctl(1, signal.SIGKILL, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), 'cannot set parent-death signal')
if os.getppid() != expected_parent:
    sys.exit(125)
os.execv(sys.argv[2], sys.argv[2:])
