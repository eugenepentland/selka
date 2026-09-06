# Native tagged unions and results

The C backend supports tagged unions and typed results whose complete payload
graph consists of integers, booleans, scalar domains, enums, and nested supported
variants. Values fitting 127 bits use packed storage;
[larger variants and aggregate payloads](native-aggregates.md) now use boxes. Construction, exhaustive matching,
copyable union assignment, result transfer, acknowledgement, and error propagation
work in single files and module projects. Frontend nominal, privacy, exhaustiveness,
and handling checks still run before emission.

Try `python3 scripts/native.py examples/native-results.my -o /tmp/native-results`;
the executable prints `20`.

Each packed variant reserves at least one low tag bit and enough higher bits for its
largest payload. Integer payloads retain their declared width; signed values are
explicitly reconstructed on extraction. Packing uses unsigned 128-bit operations
and leaves the signed storage slot's sign bit clear. The layout is an internal
backend choice, not an ABI, serialization format, or source-language size promise.
An iterative memoized walk computes layouts without recursive host calls.

Results preserve named ok/err identities even when declarations reverse their tag
order or change the success payload type. Propagation clears only the callee's
unfinished operands before returning its repacked error; caller operands survive.
Acknowledgement consumes the checked result, and local transfers retain frontend
use-after-move rules. Nested result payloads retain mandatory handling obligations.

Every emitted instruction still consumes its VM step, including representation
operations, transfer, acknowledgement, and propagation. Packed native variants need no
per-value heap allocation; boxed variants use reference-counted storage. The ordinary native frame and
operand storage still allocate; physical memory usage and OOM timing need not
match the VM.

Acceptance in tests/native_cases.py executes nested union/enum/bool payloads,
signed minima, maximum u64, signed domain extraction, copy/assignment, result tag
remapping, early propagation that skips a trap, caller operand retention, nested
result handling, cross-module source paths and frames, and a 127-bit nested value.
Both -O0 and -O2 use undefined-behavior sanitization. Small new cases compare
every instruction budget through completion. Zig tests exercise allocation failure
cleanup, frontend rejection of unhandled/moved results and incomplete matches,
unsupported owner payloads, and boxed fallback beyond a 127-bit layout.

Resources, capabilities, and borrowing still require further native implementation. Unsupported signatures and operations
produce E_NATIVE_FEATURE. This milestone does not complete the full native track.
