# Owned aggregates returned by indirect calls

The ownership pass already classified indirect-call results as owned, but its
`ownedRecord` predicate omitted `call_indirect`. Consequently an internal callback
returning a result plus a mutable-list writeback could not transfer the aggregate's
fields. The compiler inserted a retain and rejected otherwise admitted source with
`E_ZERO_RC_LOWERING`. Adding `call_indirect` beside `call` in that predicate fixes
the inconsistency; the return ABI, source checks and existing transfer proofs do
not change.

The exact ABI boundary is established by existing code:

- `build_fn.mapCallable` builds the same by-value return/mut-writeback record and
  owning parameter mask as direct functions; `build.invoke` uses `callTarget`.
- `verify_ir` admits indirect calls only with an internal function signature,
  matching return type and matching arguments. Function references require the
  exact target signature, including ownership masks.
- `single_owner.checkMode` checks every function body, including callback targets.
  Ordinary owning results use a move at return; returning a borrowed list or a
  record holding that borrow still refuses. Borrowed views have a distinct type.
- Compiler-generated borrowed-provider and borrowed-selection markers are direct
  helper calls and keep their existing exclusions. No foreign borrowed-return
  contract or generated marker is reclassified by this change.

Base: `78213cabec272c321a24850fc7e5099a319b51b6`. The before compiler from that
base rejects the exact new fixture at `return callback(mut values)`; its command,
hash and diagnostic are in `baseline.json`. The after compiler SHA256 is
`37742e49746da007fd9caea88680369945d1b3e2852c71940029370142f1be30`.
`registered.json` pins source, compiler, toolchain and owned component identities.
The new source fixture was formatted before hashing/building; existing frozen
fixtures and parent-owned formatting changes were left untouched.

The registered suite passes 2/2 tests. It covers five checked native modes with
two callback choices, scalar result plus mutable list, managed record result plus
mutable list, independent results from borrowed input, subsequent owner
replacement/clear, and discarded result cleanup. Two callback implementations
returning borrowed values still refuse `E_SINGLE_OWNER_BORROW`.

| Native matrix | Five checked modes | Ordinary release/debug |
| --- | --- | --- |
| New fixture, growing callback | 5/5 | 2/2 |
| New fixture, replacing callback | 5/5 | 2/2 |
| Unchanged `rc_pin_elide`, all 26 public Boolean tests | 5/5 | 2/2 |

All 21 matrix runs preserve their assertions and expected output. Every checked
run has zero RC events, zero exit-live managed bytes and no legacy RC helper
references in emitted LLVM. Direct drops remain valid operations. Raw counters,
commands, source/LLVM/binary hashes and outputs are under `native/`.
`source-identities.json` records the original fixture and assertion-only wrapper;
all original public bodies and their expected answers are unchanged.

`diagnostic.json` and `indirect.facts.txt` retain three actual indirect aggregate
calls after optimization, with no retain instructions. Qualification therefore
does not rely on folding every callback to a direct call. Shared admission
tickets were 1226 (baseline/format/focused build/tests) and 1233 (native matrices
and diagnostic). These are correctness checks, not performance measurements or
final installed-package/default/retirement qualification.
