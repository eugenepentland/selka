# Checked readonly stack equality candidate

This source-only candidate changes one VM handler. `equal_stack(stack, top)`
reads the right operand and then the left operand through a readonly list
parameter, calls the existing `value.values_equal(left, right)`, and returns a
plain bool. The caller then decrements `stack_top` and writes that bool through
the original indexed-write/COW protocol. It keeps the existing tagged Value
layout, dispatch, opcodes, equality implementation, collector and algorithms.
It changes no compiler or runtime code. Central timing remains outstanding;
the static counts below are not a performance or parity claim.

The parent selected AST source is commit
`37df3ffbfab1f2ea4f269c769eb5b013c5270be3`. Its all37-file map matches the frozen
root round3 AST manifest. `source-hashes.json` distinguishes that control,
the initial84-test runtime experiment, and the final86-test source. The final
overlay changes `vm.my`, adds two driver tests and their existing native
provider fixture entries. All other34 files are byte-identical to the selected
AST source. Only the root agent may integrate the overlay or time the guests.

The static investigation used the actual selected LLVM and QBE ELFs, not a
new compiler build. In the selected LLVM fib profile, `vm::run` accounts for
72.16% of samples, `heap::peek` 3.95%, and `heap::push` 3.30%. In string_equality,
the dispatch loop dominates both backends. Recorded profiles are sampling
diagnostics from the parent's `.tmp-lox-gap-profile`; this lane recorded no
new performance samples.

`heap.peek` already returns its plain16-byte Value in two registers and owns
no reference. Its subtract-overflow checks and positive-read bounds guard are
necessary: signed negative indexing and extreme-index traps remain language
behavior. `heap.push` already borrows the stack field and tests its RC flags
and owner count before the cold `myl_qbe_rc_unique_field` call. Removing that
test without a separate proof would break saved Runtime/list snapshots. The
existing direct stack writes in `run` retain the same protocol. Moving a read
past uniqueness or a write past checked `stack_top` arithmetic could change
trap order, so this candidate does neither. No broader safe shortcut was found
for peek/push or the local-slot write during this investigation.

For OP_EQUAL, the original LLVM code copies each checked16-byte stack element
into a local and again into comparison operands. The RC element-borrow rule in
`qbe_borrow.zig` accepts inert reads anchored in a list parameter, but refuses
the corresponding field-capture shape in `run`. The new helper exposes that
existing legal anchor. Its left operand is read by address through comparison;
one conservative copy of the right operand remains. There is no loan/drop of
the plain Value payload. The caller keeps the Runtime and stack field rooted
through the whole helper and retires the right root only after it returns.

`static-evidence.json` records exact assembly/IL hashes and diagnostic counts:

| Artifact | Control | Candidate |
|---|---:|---:|
| LLVM `vm.run` instructions | 5586 | 5555 |
| QBE `vm.run` instructions | 8606 | 8373 |
| QBE private equality helper instructions | 0 | 126 |
| Diagnostic IL `vm.run` blits | 110 | 106 |
| Diagnostic IL helper blits | 0 | 1 |

LLVM fully inlines the helper; QBE adds a helper call and retains its call to
`value.values_equal`. Including the new helper yields107 fewer static QBE
instructions, but its hot call overhead could outweigh that reduction. The
three fewer aggregate blits across run+helper are a concrete removed cost,
not a prediction of dynamic instruction or wall-time improvement. Whole-function
counts include cold checks and error paths. Diagnostic IL was emitted with
step/frame checks dropped solely for inspection; the actual four native guest
builds keep the normal checked native configuration. Those IL-only options
were never used in correctness execution or as a benchmark build recipe.

The helper preserves checked arithmetic and both bounds normalizers, including
negative indexing, conditional length casts, and their right-before-left order.
`value.values_equal` retains its original left-before-right tag/payload matching,
IEEE float equality (including NaN and signed zero), boolean/nil distinctions
and object identity. Its source and emitted dependency record are pure and it
has no calls, allocation, managed payloads or callbacks. No stack mutation or
COW step runs before both checked reads succeed. The original dispatch IP
publication sites are unchanged, and the bool write still uses the original
checked subtraction, bounds and COW path.

The comparison now precedes right-slot root retirement. For valid typed Values
this cannot change observable Lox behavior: the comparison cannot allocate,
collect, call out, mutate or report a Lox error. The new tests cover NaN, signed
zero, different tags, interned string identity, object identity, allocating
operand calls, and both Runtime and stack-list snapshots while comparisons
alternate with allocations under Lox collector stress.
The retirement's repeated `top - 1` cannot introduce a newly delayed arithmetic
failure: the right read already completed that identical checked subtraction
successfully, and the helper cannot modify `top` or the Runtime. The final
indexed write and its COW failure remain after retirement as before.

This is a source refactor, not a certificate of identical malformed/native
execution traces. An invalid union tag is not constructible by checked mylang
or Lox source; the emitted equality dispatch still has its original failure
edge, which returns false, but that edge would now run before retirement.
Equivalence of forged invalid-tag internal state was not proved or tested.
An accounted step-budget trap may now occur in the helper or during comparison
while the original handler would already have retired the right slot. The
normal cleanup/root protocol remains in force, but exact exhausted-budget PC,
private helper stack frames and step counts are not identical. QBE also adds a
checked native helper-frame admission, so an artificially tight native stack
budget may fail at that frame. No assertion, bounds, overflow, step or frame
check was relaxed. Acceptance coverage below asserts the public Lox protocol,
not identical source-expanded native diagnostics on those unproved inputs.

`qualification.json` binds the all37 source map, exact d14 compiler/QBE,
runtime objects, four actual ELFs, build receipts and full raw observations.
The completed, distinct checks are344 public tests and348 bounded native VM
comparisons. Every public mode passed86 fresh tests with zero cached, failed,
skipped or dropped entries. The commands use1e9 steps/120 seconds consistently:
LLVM public tests use `--release`; QBE public tests use `--mode ReleaseFast`.
`mylang test --gc-stress` selects the GC ABI as specified by
`src/main_runtime_mode.zig`; the checked RC and native-GC-stress test modes
are distinct. Public fixtures include both new named tests and their providers.

The native matrix compares complete status, stdout, stderr and Lox stats
against the selected AST RC control on each backend. It covers all23 existing
VM diagnostics, four corpus smoke programs (fib, strings, string_equality,
closures), and the two new equality programs. Each runs with RC, ordinary GC
and native GC stress, and with Lox GC normal/stress:29 cases×12 modes=348.
The direct host snapshot fixture is covered by public qualification; the
standalone native regression runs its equivalent compare/allocate Lox loop.
This bounded matrix is not a full13-program corpus or tree-native qualification.
The prior selected AST coverage is not counted again in this lane's totals.

There is retained failure evidence. The first `final-builds.json` receipt
contains two wrongly gc-labelled builds whose commands omitted `--gc-runtime`;
they built the default RC ABI and are byte-identical to RC. The first
`native-validation.json` has three partial rows, including a correctly recorded
status2 native-GC-stress refusal. Its process exited1. Those rows are excluded
from the completed348 matrix and are not GC pass evidence. The corrected
recipe and receipts use explicit `--gc-runtime`, distinct `qualified-*` paths
and fresh complete comparisons. `corrected-builds.json` records the original
receipt hash and reason; the old files were not rewritten. The corrected
LLVM/QBE GC ELFs and runtime objects differ from RC as required.

Final candidate RC paths are in
`/home/epentland/ai/canopy/mylang-worktrees/codex-lox-vm-stack-read-20261003/.tmp-lox-vm-stack-read-20261003`:

- `qualified-equal-llvm-rc`: `2ab3ee3a3d6e7e7a857ca1f279a62b7443392da22d87f64bb617df195e3e40a7`
- `qualified-equal-qbe-rc`: `0bedbcb6a92955eeb6e54dd6154a89f63e2b20406d0c2b1a07b067c3db1ed0d4`
- selected AST LLVM control: `180575c3fc2e46a16ed8dd290e289963a87603b5a7c0cf8bb0e03ba7cf794361`
- selected AST QBE control: `246f21781fd58c7141dbe0992101c842e62d732d9ce47e209d55821d02b11b25`

The correct four-flavor artifact paths, hashes and exact commands are in
`corrected-builds.json`. Its RC bytes match the initial84-test arm exactly;
only the driver tests/providers were added in the final86-test source.

To reproduce, first create an isolated checkout at37df3ffb. Run its
`docs/audits/d9-stage3d-migrations/apply-lox.sh SCRATCH --optimized`, copy
`SCRATCH/lox/benchmarks/lox/ports/mylang` into this experiment's private
`control`, and apply `readonly-stack-equality.patch` to a copy. The patch applies
to those exact37 selected AST files; a future canonical `--optimized` recipe
may include more overlays and must not silently replace this pinned control.
Verify the all37 maps against `source-hashes.json` before building. The frozen
selected compiler is d14a7040, with adjacent QBE99ad919d. `build.py` builds all
four qualified artifacts via shared build slots with private cache/output/TMPDIR;
`test.py` runs the fresh four public modes; `validate.py` compares the bounded
native matrix. The scripts intentionally refuse existing receipt/output paths
and the correction scripts require the retained initial failure receipts;
use a new scratch prefix and preserve historical metadata when adapting them.
`emit.py` reproduces diagnostic IL and `package.py` rechecks existing evidence
without executing a guest. No canonical source, main checkout, frozen control
artifact or Guardian feedback log was edited by this lane.
