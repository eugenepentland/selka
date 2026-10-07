# Retained zero-trip ownership reducer

The frozen M at 25d9 source failed its record Release case with status 232. This
private diagnostic copies the exact original pushed/undefLoopProgram fixture,
verifies it before/after own.run, emits LLVM, calls the actual copied M driver
and retains all four native outputs. Production sources were untouched.

command.json/log records the full diagnostic host build recipe. source.json
binds the original fixture and diagnostic source; diagnostic.zig.txt preserves
that exact source archive. To reconstruct it, copy frozen M at 25d9 src/core into
the private core directory adjacent to diagnostic.zig, copy the archived source
there, and use the command recipe with fresh generated build assets/options
from that source. The recipe's test selects the diagnostic only. Its exit 0
means the evidence was captured: it deliberately does not assert all native
cases, so native.json and summary.json determine the RED.

The four cases were list Debug 0, list Release 0, record Debug 0, record Release 232,
all with empty stdout/stderr and MYL_CORE_LEAKCHECK=1. A later raw execution of
the same retained binaries reproduced the same statuses. Debug/Release LLVM
bytes are identical within each shape, so only native optimization differs.
artifact-manifest.json binds LLVM, binaries and runtime artifacts. LLVM, logs,
JSON and streams are tracked; native caches/objects/binaries remain retained
on disk without being committed. Full-package qualification is separate.
