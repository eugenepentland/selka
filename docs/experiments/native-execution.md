# E: scalar native execution through C

Status: a native C route and shared scalar acceptance fixtures are implemented.
`emit-c` consumes checked/lowered instructions and emits standalone C. The builder
uses Guardian's exact pinned Zig snapshot to compile it into a host executable.
This establishes the roadmap's scalar native experiment, not native support for
every post-MVP language feature or any performance claim.

```sh
zig build
python3 scripts/native.py examples/sum.my -o /tmp/native-sum --mode ReleaseFast
/tmp/native-sum
# 4950
/tmp/native-sum --max-steps=1
# exits 1 with R_STEP_LIMIT and source location

# Generated C can also be inspected directly:
zig-out/bin/mylang emit-c examples/sum.my
```

## Supported semantics

Supported functions use signed/unsigned 8/16/32/64-bit integers and booleans,
initialized locals, assignment, scalar operators and casts, blocks, branches,
loops, short-circuiting, direct calls, forward/mutual recursion, discard, and returns.
All checked function signatures and instructions are inspected, including uncalled
functions. [Nominal scalar domains](native-domains.md) now also use scalar backing
with checked privacy and instruction-budget parity. [Closed enums](native-enums.md)
also support construction, equality, calls, and exhaustive matching.
[Packed tagged unions and results](native-variants.md) add supported payloads,
matching, transfers, acknowledgement, and propagation.
[Ordinary aggregates](native-aggregates.md) now support records, arrays, tables,
conversions, updates, and boxed variants. Unsupported
resource/capability/borrowing
operations fail explicitly with E_NATIVE_FEATURE before any generated C is printed.
Source type errors still use ordinary semantic diagnostics. There is no VM fallback.

The emitter generates direct C labels and branches for each concrete instruction.
Calls use explicit frames and return through a generated continuation switch.
No instruction array, opcode decoder, interpreter library, or guest-to-host recursive
call chain is linked into the executable. Integer/boolean operands and locals use
signed __int128 storage; checks enforce the actual guest width. Addition, subtraction,
and multiplication use overflow intrinsics before guest-range checks. Division and
remainder check zero, use truncation toward zero, and preserve the i64 minimum/-1
remainder result of zero. Comparison/boolean results preserve checked source types.

Explicit dynamic frame/operand storage avoids host-stack recursion and retains
unfinished caller operands. Scalars require no reference-counted resource cleanup.
All allocated frames/locals/operands release on normal exit, guest trap, or detected
host allocation failure. Native allocation strategy and host OOM timing may differ
from the VM; no identical physical allocation or cost claim is made.

Each generated guest instruction consumes one step, matching VM budget boundaries.
The executable accepts `--max-steps=N` and `--max-frames=N`, with VM defaults of
10,000,000 and 1,024. Invalid/duplicate/overflowing budgets exit 2. Successful main
prints its i64 result and exits 0. Guest traps exit 1 with the same trap code and
source line/column, plus up to 16 function frames. Native diagnostics are concise;
they do not duplicate the VM's source excerpt, underline, or explanatory wording.
The emitted source path is the path supplied to emit-c; the builder supplies an
absolute path. String data is escaped as octal bytes, including quotes/newlines.

## Toolchain and interface

`scripts/native.py` checks the exact `.zigversion` before invoking the compiler and
`zig cc -std=c11`. Debug uses -O0; ReleaseFast uses -O2. C code depends on the pinned
compiler's __int128/overflow intrinsic support and a hosted C runtime. Embedded,
freestanding, cross-target, and arbitrary C-compiler portability are not established.
The builder uses argument arrays without a shell and removes temporary C storage.
`--compiler` selects an already-built language compiler; its source checking and
native emission errors propagate. Host build failures exit 2. The output path is
explicit. `Compilation.emitC` supplies the embedding interface.

## Acceptance evidence

`src/native_test.zig` verifies deterministic generation, every allocation failure
through checking/lowering/emission, and explicit rejection of unsupported signatures
and operations. Actual CLI tests verify emission, source errors, native-feature
errors without partial C output, and wrong-command option rejection.

`tests/native_cases.py` now compiles and executes 51 single-file and 10 module
fixtures at -O0 and -O2 with undefined-behavior sanitization and no sanitizer
recovery. It performs 1,506 actual VM/native comparisons per compiler host mode
of exit status, stdout, trap locations, and module call frames. Scalar coverage includes:

- Existing arithmetic, sum, and GCD fixtures; all integer widths and checked casts.
- Signed overflow/negation, unsigned intermediate overflow, division/remainder by
  zero, signed division/remainder direction, and minimum-integer boundary behavior.
- Short-circuit skipped traps, boolean calls, nested argument evaluation and caller
  operands, frame/step limits, and each budget boundary of a nested-call program.
- 20,000 recursive calls completed with explicit frames under an increased guest
  frame limit, without native host recursion.

The harness also checks the actual native builder, rejection of a wrong Zig version,
quoted source paths, and invalid executable budgets. `zig build test` runs it for
each compiler host optimization mode alongside the Zig/CLI and verification-driver
tests. The current verification manifest's Debug/ReleaseFast test steps therefore
include actual scalar native parity; its separate memory-parity step still means
only general/arena VM memory parity.

The [aggregate acceptance](native-aggregates.md) adds records, arrays, variants,
and a separate native allocation-failure/cleanup driver with address sanitization.
These tests establish the declared fixture behavior, not exhaustive equivalence
for all inputs, a speed advantage, or whole-language native support. Post-MVP native expansion must add corresponding checked operations,
cleanup/effect behavior, and executable parity cases rather than silently running
the VM. Other unfinished roadmap tracks remain independent work.
