#!/usr/bin/env python3
"""Compiler and emitter identity for one qualification stage.

`src/qbe.zig` is the IL emitter the LLVM arm consumes, and more than one writer
has been editing it while this qualification ran, so a stage that straddles a
change to it is not a statement about one compiler.  Each harness records this
identity at the start and the end of its run; if the two differ, the stage is
void and is re-run.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent


def digest(path):
    """The SHA-256 of one file, or None when it is absent."""
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError:
        return None


def identity(mylang):
    """The compiler binary, emitter source and translator a stage's result depends on."""
    here = Path(__file__).resolve().parent
    return {"compiler_sha256": digest(mylang),
            "qbe_zig_sha256": digest(REPO / "src" / "qbe.zig"),
            "native_types_zig_sha256": digest(REPO / "src" / "native_types.zig"),
            "translator": {name: digest(here / name) for name in
                           ("qbe_llvm.py", "llvm_emit.py", "runtime_signatures.py",
                            "amd64_sysv.py")}}
