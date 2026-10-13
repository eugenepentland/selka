# Read-only P7 exchange review

P3 reviewed the current P7 diff and supporting cleanup/SSA code. P3 changed no
P7 files and launched no native builds, checks, runs or timing. Source and
fixture identities are in `review-inputs.json`; the reviewed P7 source was
still being qualified, not a frozen final compiler. P7 owns fixes and admitted
runtime verification.

## Static finding: transfer matching crosses unrelated control-flow paths

At the reviewed revision, `src/core/flags.zig::transferredSlot` scans every read
in every block and returns true whenever a `place_read` has matching resolved
receiver/index references (and field). It checks neither dominance nor execution
order. `src/core/own.zig` uses this to mark stores `taken` and skip ordinary
ownership update preparation. `src/core/emit_llvm.zig::listSet` suppresses the
old-slot managed release when this matcher returns true.

Therefore, **for IR with an exchange read in one branch and an ordinary store
in a sibling branch sharing the same receiver/index SSA operands**, the matcher
returns true for the ordinary store even though that read is not executed on
the store's path. That is a concrete static matcher hazard. Whether each source
fixture lowers to precisely that SSA shape is pending native/IR verification;
no runtime leak is claimed by this review yet.

`sibling-overwrite.my` uses one shared unsigned parameter index and a mutable
list parameter. `sibling-overwrite-zero.my` uses constant zero in the mutable
helper. Both derive the branch condition from argv so the true and false arms
remain live. P7 will run each with no argv (ordinary overwrite) and one argv
(exchange) in checked and RC modes, inspect resolved receiver/index identities,
and check cleanup/counters. A same-block-only matcher fix would unnecessarily
reject existing cross-block nested transfers; the fix must preserve legitimate
transfers while excluding nondominating reads.

## Other requested paths

- **Fresh match:** `matchOwnsTemporary` now includes exchange and is shared by
  checking and lowering. Builder emits `union_take` for the fresh owned result.
  Existing P7 fixture covers wide mutable payload extraction and early return
  from a recursive payload match. No separate defect found by inspection.
- **Repeated exchange followed by ordinary overwrite:** sequential writes use
  the returned list's distinct SSA version, so the original read/store pair
  should not classify later stores as transferred. P7 fixture covers retained
  first result, discarded second result, ordinary overwrite after each, and
  1000 swaps. The sibling-path matcher finding above is not covered by that
  sequential fixture.
- **Discarded old result:** managed transferred reads are marked owned in
  `own.zig`; unused old results receive normal cleanup. Exchange only omits its
  returned IR ref when source result type is Unit, whose list element is a
  scalar placeholder. No managed old result is intentionally omitted there.
- **Wide enum detachment:** `listGet` loads a non-lent element via `loadValue`,
  which copies values over four words into an independent home/stack slot.
  `union_take` is not a lendable element use, and exchange's overwrite intervenes
  before matching the old result. Boxed payload transfer also loads independent
  storage before dropping its shell. No escaping slot/box pointer found.
  `wide-discard.my` adds direct discarded active-wide payload and wildcard
  match/early-return cleanup coverage; it is a recommendation, not a bug claim.
- **Result-list mut parameters:** ordinary checker exemption requires parameter
  origin, mutable binding and pending-list type; parameter mutability excludes
  host functions. Symbolic checker sets caller-writeback only on non-host mut
  list parameters. Neither change clears pending availability; ordinary
  overwrite checks still consult pending obligations. Three negative fixtures
  isolate unhandled remaining caller elements, generic remaining caller
  elements, and an old result held in an ordinary local. All should reject
  `E_RESULT_UNHANDLED`; their runtime/frontend outcomes are pending P7's lease.

P7 (`parity_measure`) accepted the two sibling fixtures and wide-discard for
its admitted verification. The three obligation negatives were sent as
additional coverage recommendations. Static mechanism and future native outcome must remain separately
labelled. No source fix or compiler correctness claim is made by P3.
