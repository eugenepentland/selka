# D9 Lox VM instruction-pointer publication, 2026-09-26

The optimized class-free port now keeps the active frame's instruction pointer
local until a handler can report a Lox runtime error or enter another call.
Closure and stack-base roots already live in the saved frame for its entire
activation. Publishing only the IP at these boundaries avoids reconstructing
and writing a call-frame record for every constant, stack operation and jump.
Error-capable handlers publish the same pre-operand IP as before; calls publish
the post-operand return IP. Calls, returns and garbage collection retain their
existing frame and closure roots.

This updates `d9-stage3d-migrations/lox-source-perf.patch`, applied by
`apply-lox.sh WORK --optimized`. Reconstructing the patch from the pinned port
produces byte-identical modules to the tested source. The compiler changes
`8a31f237` (mut-record scalar updates) and `2b889ba5` (cold failure-result
initialization) are separate prerequisites for the measured result.

## Measurement

All compilers were Debug builds. Guest modes match: QBE ReleaseFast, or LLVM
ReleaseFast with optimization level 3 and full LTO. CPU 11, median of three
`perf stat -e instructions:u` runs, Lox VM equality N=30,000:

| Backend | Exact `60b668cf` class baseline | Class-free candidate | Ratio |
| --- | ---: | ---: | ---: |
| QBE | 1,018,578,412 | 1,103,706,548 | 1.0836× |
| LLVM | 346,981,117 | 416,046,170 | 1.1991× |

Every run exits zero and prints `30000`. The
[raw measurements](evidence/d9-lox-ip-publication-perf.json) include compiler,
guest-binary and source hashes. The frozen compiler SHA starts `5139b78f`;
inspection confirms it includes the cold-return emitter change even though
that change was not yet committed when the snapshot was taken. These figures
therefore measure the combined candidate, not the isolated compiler change.

This case now meets the per-program limit. It does **not** establish the
43-program stage 3 gate, and the recursive-box correctness/performance work
remains outstanding. The default switch stays isolated.

## Correctness validation

- All 63 port tests pass in value and compatibility modes, using the existing
  10-million-step port-test allowance. An initial run with the command's
  smaller default allowance stopped in unchanged runtime initialization;
  no test, runtime budget policy or expected result was changed.
- All 13 pinned VM smoke scripts match exact output on QBE and LLVM in each
  mode (52 runs). Compatibility uses the integrated default candidate's
  explicit `--legacy-sharing`; the stage 3b-only compiler lacks the later
  legacy scalar-record mutation support.
- `verify-lox-traces.py` covers 23 error paths, each with normal and stressed
  Lox collection: globals, properties, numeric operators, inheritance,
  calls, methods, super calls, arity failures and stack overflow. Loops and
  nested calls precede each failure to expose stale instruction pointers.
  All 46 traces match the exact baseline on each backend in value mode,
  compatibility mode, and value mode with additional native GC stress:
  [276 raw comparisons](evidence/d9-lox-ip-publication-traces.json.gz).

The source change is a pinned external-port patch; it does not change the
compiler or runtime. The joined compiler/source branch must still run its
full gate before acceptance.
