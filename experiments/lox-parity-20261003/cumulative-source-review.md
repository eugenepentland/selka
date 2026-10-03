# Independent cumulative Lox source review, 2026-10-03

Reviewer: `/root/frames`. I did not author the October 3 source overlay. This
review found no actionable semantic issue in the requested paths. It inspected
source and existing receipts, and ran an independent in-memory patch replay and
identity checker. It did not build, execute tests, run benchmarks, edit another
worktree, or touch Guardian feedback.

The overlay SHA256 is
`233332c7b4fd1325f3ec1251406b0b433e87520f5abc4db9cfcc70e79813445b`.
The control is the optimized port at `fd86729e2820b9712fef3b5fcbcad7d346988018`.
The final source is
`/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003/.tmp-lox-parity/replay-final-absolute/lox/benchmarks/lox/ports/mylang`.
The pinned SPEC is v1.1, 2026-09-22, SHA256
`c818e2c812b6b7d9a3c3d4838c0526d54767369775298db23fb33f4055681f36`.

The [independent checker](/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/experiments/lox-parity-20261003/cumulative-source-review.py)
and [JSON evidence](/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/experiments/lox-parity-20261003/cumulative-source-review.json)
record exact paths, all 37 source/metadata hashes, commands, logs and receipts.
In-memory replay matches all 37 final files; the qualified sweep source also
matches all 37. Exactly six files change: `interpreter.my`, `vm.my`, `heap.my`,
`heap_test.my`, `driver_tests.my`, and `driver_cases.json`.

## Reviewed source paths and invariants

Line numbers below refer to that final source directory.

- `interpreter.my:32–37, 638–680`: flattening keeps only call depth and the return
  register in Interpreter. Program becomes readonly after parsing/resolution;
  Runtime and Output are the same named mutable values throughout recursion.
  No AST mutation occurs during evaluation. Runtime still owns every Lox root,
  matching SPEC §7.2. Public `interpret` status/error emission and driver/main
  behavior are preserved; those modules are otherwise unchanged.
- `heap.my:331–347`: environment updates retain ordinary checked indexed writes.
  The extracted object list and environment slots follow normal value/COW
  semantics, so both a copied Runtime and an independently saved Env payload
  detach on mutation. Enclosing and untouched slots are retained. No Lox heap
  allocation or collection is added. The new snapshot regression explicitly
  checks both levels of aliases.
- `interpreter.my:116–139, 245–306, 348–459`: callee then arguments remain evaluated
  left to right and stay on Runtime's operand stack. Pre-filling a host Env payload
  moves only host construction before the same Lox allocation point: arguments
  remain stack roots and enclosing remains reachable. The incoming object is
  still unpublished during its triggered collection, with the same slot count
  and cost. Binding explicitly roots the this-Env across the TreeFunction
  allocation. Class calls keep the literal Instance → this-Env → arity → depth →
  call-Env order from SPEC §9.5, including failure paths and no-init arity errors.
- `interpreter.my:391–436`: the selected callee descriptor contains only scalar
  fields. It ends the object projection before execution/heap mutation, while the
  actual callee stays rooted on the value stack. Classes remain reachable through
  the replacement instance; functions through the callee; initializer closures
  through the class or this-Env. Native arity checking and result replacement
  retain their prior behavior.
- `interpreter.my:280–295, 505–558`: Set rejects a non-instance before RHS
  evaluation, retains the original receiver on the stack, and reads its current
  fields after the RHS. It therefore retains both receiver identity and mutations
  performed by the RHS. Field shadowing, inherited method lookup/copy-down,
  source-order method publication and superclass environment restoration are
  preserved. `table.my` is byte-identical to the control.
- `interpreter.my:361–383, 539–543, 581–589`: blocks restore current_env on normal,
  return and error results. Function execution restores current_env and depth
  before propagating Err. Return-register unwinding does not allocate, so popping
  a returned Lox reference introduces no interval containing a collection before
  the caller publishes it. Initializers still return this.
- `vm.my:157–171, 244–280, 292–351, 499–643`: scalar closure arity checks retain
  arity-before-depth order. Upvalue traversal retains descending slot order,
  existing-slot reuse and insertion links; the predecessor is reloaded after an
  allocating capture. Closing retains threshold, writeback and root order.
  Operand extraction changes only IP, leaving code/constants/upvalue lists
  immutable for the activation. The fixed frame index remains valid through
  successful child calls/returns. Runtime-error reset immediately leads to
  RUNTIME_ERROR unwinding, without later stale-index writes. Runtime.frames still
  provides closure roots and traces; IP publication remains at the original
  handler/call positions. The existing 64-frame gate bounds native recursion.
- `heap.my:444–511`: free tags and costs are scalar reads. Every cost expression
  matches unchanged `object.my:92–115`, including variable-sized Env, Closure and
  String objects. Sweep still visits ascending indices, subtracts cost before the
  normal checked free write, appends each freed slot, clears survivor marks and
  counts freed objects. LIFO reuse, weak intern tombstones, incoming allocation
  charging, collection counts and threshold recalculation are unchanged. The two
  new sweep tests cover every object kind, snapshots, reuse order and collection
  during allocation.

SPEC §§0, 4–7, 8.5–8.6 and 9.4–9.6 were checked. These changes adjust ownership
carriers and scalar reads within the existing algorithms. They introduce none of
the prohibited boxing, dispatch, superinstruction, caching, constant-deduplication
or unsafe shortcuts. The opcode/data representation, module dependencies,
hash-table algorithm, roots and GC algorithm remain. Public error messages are
unchanged in the diff, and exact error lines/traces are covered by saved receipts.

## Qualification evidence checked

The source contains 80 public tests, up from 72, with none removed. The four new
driver tests cover argument/callee roots, recursive state/output, multi-slot
upvalues, and errors after child returns. All four have the required deterministic
native-provider fixture. All prior fixtures are byte-identical. The four new heap
tests cover environment snapshots, scalar arity snapshots and both sweep cases.

The sweep lane's `unit-qualified.json` is post-verified and matches final source
hashes and the immutable positive compiler. Its four logs match their hashes and
each records 80 fresh passes, zero cached/failed/skipped/dropped: LLVM release and
QBE ReleaseFast, each with RC or native GC stress. All 80 test names appear in
each run. This is 320 saved fresh passes, not an independent rerun.

The sweep lane's post-verified `validation.json` contains 696 unique observations
with exact actual/expected status, stdout and stderr equality, including stats:
104 corpus smoke, 224 focused regression, and 368 runtime-error observations.
All input hashes, four candidate binary hashes, two control binary hashes and
the manifest hash still match. Native stress accounts for 296 focused/error
observations; the validator sets `MYLANG_OPTIONS='--gc-stress'` for those arms.
The controls here are positive-joined-flat artifacts, separate from the older
fd867 source-diff control. The final LLVM/QBE binary hashes agree with the root
matrix manifest.

There are 104 explicitly unrun native-stressed corpus smoke cells. The saved
optional selector named `empty`, which is absent from this corpus; consequently
no native-stressed corpus smoke ran. The lane documents this and the current
validator rejects unknown selectors. These cells are not counted as passes.

## Limits

This is a manual source review with independent replay/receipt identity checks,
not a formal proof or newly executed test matrix. It does not independently
validate compiler internals or establish timing gains. No Rust/Go parity claim
is made; the parity goal remains unmet.
