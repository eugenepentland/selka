# External CFG provenance sidecar, read-only design

This design was approved and implemented after the provisional V merge
`3d61a8409`. It replaces the rejected marker draft. No instruction field, operation meaning, IR type or runtime ABI changes.

The retained `mut-frame-references-02/summary.json` compiles actual two-module
bounds, assertion and overflow failures under old, S3, V d4 and standalone E.
All three V release cases lose the exact callee and caller source call position.
Old/S3 retain both functions; standalone E matches old. The actual immutable
compiler hashes are recorded; the V executable is d4, not a later package build.

## Carrier and bounds

An arena-owned `inline_origins.Table` stores sparse block origins keyed by real
function index and block ID, sparse instruction overrides keyed by real function
index and instruction reference, and interned `Frame` chains. Each frame holds
the exact source callee function index, original source call span and optional
parent frame. Absence means the actual emitted function. An instruction override
takes precedence over its block origin. A present null override means the physical
caller, whereas no entry falls back to its block; this distinction survives
cross-block counting insertion and duplication. Untouched functions allocate no
metadata entries. Existing source spans remain unchanged.

The sparse instruction overrides preserve prior leaf clones inside CFG bodies;
they also prevent mixing two leaf call sites in one physical block. Exact generic
function indices distinguish specializations sharing all physical source spans.
Function indices are resolved to names and source locations before emission;
they never appear in emitted bytes or cache identity.

Depth is capped at 32 frames. Before mutating IR, each inliner checks that the
callee's ancestry can compose with the actual call site's ancestry; otherwise it
retains the real callee. Sidecar storage is proportional to cloned blocks and
instructions, with no dense metadata allocated for unchanged functions. Any
unrepresentable transform must conservatively retain the original call.

## Optimizer propagation

- `passes.Result` adds one default-empty sidecar field. Release passes share its
  mutable table; debug and hand-built callers can use the empty default.
- CFG splice assigns the callee frame to cloned blocks and composes pre-existing
  nested block/instruction frames beneath it. Caller continuation keeps the
  caller's former block origin and existing instruction overrides.
- Leaf splice attaches exact callee ancestry to copied instruction references;
  the original call and caller continuation retain their original attribution.
- `version.duplicate` copies source block and instruction origins through its
  existing maps. Header-derived guard, entry and stay blocks inherit the source
  header instruction's effective origin.
- `own.Editor` preserves origins through block splitting, instruction-anchor
  insertion and copy/failure blocks. New unique checks inherit the update's
  effective origin, including a leaf override. Edge releases inherit the source
  edge origin. Unchanged references retain their existing metadata.
- Fact marking/folding, vector planning and ordinary forwarding copies need no
  new instruction contract. Emission's verification assertions use the current
  block/instruction frame, including unreachable-block assertions.

## Emission and API

F's independent review recommends grouping the cohesive optimizer output in
`emit_llvm.Analysis{facts,vectors,provenance}`. `Options` replaces its separate
facts/vectors fields with one default-empty analysis, leaving six fields. Source
lookup remains separate in `Locator`. Update production pipeline and every
optimized native fixture passing a `passes.Result`; leave plain hand IR callers
default empty.

Before rendering a block or instruction, select its effective frame. Every trap,
assertion, trace and verification site uses the innermost exact function name.
The function scope remains the physical owning function. Calls and traps get
`DILocation` in the exact callee scope with nested `inlinedAt` links for each
original call span. Scope creation and local debug nodes follow deterministic
first use, so unrelated global table IDs cannot ripple into LLVM text.

Estimated production scope: new `inline_origins.zig`, `inline.zig`, V's
`inline_cfg.zig`, `passes.zig`, `version.zig`, `own.zig`, `emit_llvm.zig`,
`pipeline.zig`, `test_support.zig`, plus fixture result plumbing. No change to
`ir.zig`, old compiler files or runtime layout/signatures.

## Required validation

Before final qualification: old/split/whole exact native reports for all three
reducers in debug/release/verify; two calls to one callee with distinct positions;
generic specializations sharing a declaration/body and primitive trap type;
nested leaf/CFG helpers; unswitched/versioned loops; ownership/fact assertions and
leaks. Verify sidecar ancestry bounds and empty-default behavior. Recheck unit
repeatability/edit ripple, synthetic prepass cost, union_find/grid/all46, actual
split apps, full core64, conformance, own exact-source full-old and strict fuzz.

F independently reviewed the hybrid and API, including explicit guard/header
attribution, root overrides and ownership/unreachable assertions. The production
path and optimized fixture helpers retain all optimizer output. An analyzed
native fixture explicitly refuses a second ownership pass without mutable source
metadata.

The injected native uniqueness failure additionally exposed LLVM merging cold
trap calls across source scopes despite correct metadata. `ownership-frame-reducer`
retains exact LLVM/DWARF/native evidence: `notail` stays red and `nomerge` restores
the original caller. Trapping calls now carry `nomerge`, with no ABI change.

Nine focused tests pass, covering every listed metadata boundary including the
32-frame bound, present-null override, nested generic/function ancestry, actual
unswitched ownership loops and injected reachability/unique assertions. Fresh
combined package qualification and final performance gates remain pending.
