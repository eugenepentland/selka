# Splitting `sema.zig` and `qbe.zig` — 2026-09-23

This report covers item 6 of the
[development-speed audit](development-speed-audit-2026-09-23.md) (§3, §5):
split the two largest compiler files along the seams the lanes already use,
so an agent reads less and parallel lanes touch different files. It is a
behaviour-preserving refactor on branch `devloop/split-sema-qbe`, from
`base/split` (`b5255e75`), with `main` `4e332f70` (tooling only) merged in
before the final gate.

**Decisions in one paragraph.** `src/sema.zig` (6,874 lines) becomes a
1,701-line hub plus nine modules; `src/qbe.zig` (3,168) becomes 1,825 lines
plus three. Every moved function keeps its body; the only edits are the ones
the module boundary forces (below), and a normalizing diff proves it for all
1,880 declarations. `emit-qbe`, `emit-project-qbe`, `check` and
`check-project` give byte-identical output, stderr and exit status on 446
programs, and `check`/`emit-qbe` on 1,981 source snippets from the Zig tests,
1,378 of them rejections. The gate is green with the base's test counts plus
the 11 unit tests this split adds (one per new module that had nothing to
move). `src/main.zig` was not split: its argument parser is a 40-field struct
that Guardian's type-size cap forbids making `pub`, so a move needs a
redesign, not a move.

## How a module attaches

Guardian forbids `@import` cycles, and a checker (or emitter) is mutually
recursive: expressions check lambda bodies, statements check expressions. A
module therefore cannot import `sema.zig`; it is generic over the checker
type instead. `src/qbe_managed.zig` already had the shape used here:

- Each moved method becomes a file-level `fn name(comptime Checker: type,
  self: *Checker, …)` — `Emitter` in the QBE modules. Its body is unchanged
  apart from a 4-space dedent.
- A call to a function **in the same module** is written `name(Checker, self,
  …)`. A call to anything else stays `self.name(…)` and goes through the hub.
- Each module has `pub fn Checks(comptime Checker: type) type` (`Lower` in
  QBE) holding one forwarding wrapper per function the rest of the checker
  calls. The hub declares `pub const name = <module>_checks.name;` for each,
  so every existing `self.name(…)` call site is untouched.
- Hub methods a module calls became `pub`, with a `///` doc.

The wrappers are thin on purpose. Guardian scores cognitive complexity and
length over a whole `fn` including nested ones, so a `Checks` struct that
contained the bodies would score the sum of all of them (cap 25, 400 lines).
`anytype` is capped at two parameters per file, which rules out `self:
anytype`.

**Adding code after the split.** A helper used only inside its module needs
nothing else. A function another module or the hub calls also needs a wrapper
in the module's `Checks`/`Lower` and one alias line in the hub, in that
module's alias block. A type or message two modules use lives in
`src/sema_shared.zig`.

## Seam map

Group boundaries follow the Checker's own method order, which is already
grouped by topic, and the regions lanes edited (last-touch `git blame` of the
two weeks before `b5255e75`).

### `src/sema.zig`

| module | lines | what it checks | recent commits touching it |
|---|---:|---|---:|
| `sema.zig` (hub) | 1,701 | `Checker` fields; function and lambda bodies; ownership and result-obligation bookkeeping; `todo` holes; call resolution; `require`/`resolve`/arity helpers; literals; arena-escape rules; Option narrowing; parameter binding; the `check`/`checkCached` driver | 65 |
| `sema_expressions.zig` | 869 | the work queue: `queueExpression`, `checkedExpression`, `expressionWithTemporaries`, argument hints, `len`, lambda values, consumed temporaries | 38 |
| `sema_collections.zig` | 1,099 | collection syntax, list/dict/text literals, comprehensions, f-strings, access and slices, list/dict/text/bytes/byte-buffer/Option methods, resources | 34 |
| `sema_calls.zig` | 774 | names, fields, function values, conversions, `Environment`/`Network`/filesystem methods, host calls, record updates, `checkCall`, deprecations, `mut` markers | 27 |
| `sema_statements.zig` | 534 | `with`, `match`, discards, `if`, `return`, `assert`, bindings, assignments, the statement dispatcher | 21 |
| `sema_builtins.zig` | 876 | float intrinsics, `int`/`float`, prelude calls, `sorted`/`list.sort` keywords and key lambdas, `open`/file methods, `print`/`Stream`, `Some`/`None`/`Ok`/`Err` | 19 |
| `sema_places.zig` | 794 | tuples and destructuring, field assignment, augmented assignment, fixed-array/table writes | 17 |
| `sema_operators.zig` | 445 | unary/binary operators, table/dict/text literals, conditionals, membership, indexing | 16 |
| `sema_loops.zig` | 446 | `while`, `for` over collections and prelude iterables, `for`-range, loop-variable rebinding, `break`/`continue` | 16 |
| `sema_specialize.zig` | 397 | generic specialization, its semantic-cache reuse and publication, type-argument inference | 4 |
| `sema_shared.zig` | 50 | what two or more modules need: `Work`, `Pending`, `StatementFlow`, `LambdaCapture`, `markerPositionDeclared`, `isMutableBytes`, ten diagnostic codes and messages, and two other constants | — |

Before the split every one of those 93 commits touched `sema.zig`, so every
pair of them shared a file. Re-attributing each edited line to its new home,
41 of the 93 touch a single file and 65% of commit pairs still share one —
mostly the hub, whose `Checker` fields, shared helpers and top-level messages
many lanes extend. (Blame sees only the last touch of a line, so this is an
estimate, not a replay.)

### `src/qbe.zig`

| module | lines | contents | recent commits touching it |
|---|---:|---|---:|
| `qbe.zig` (hub) | 1,825 | `generate*`, units, the two-pass allocation analysis, `Emitter` fields, `lower`/`emitAt`/`emitOp` dispatch, loads/stores, layouts and ABI types, value read/write helpers, calls | 47 |
| `qbe_frame.zig` | 706 | slot and temporary allocation, zero-fill, frame linking and its admission checks, returns and owned-local cleanup, argument vectors, frame sizing | 18 |
| `qbe_roots.zig` | 299 | which ops and callees can allocate, root liveness, root push/restore at safepoints | 14 |
| `qbe_il_passes.zig` | 611 | text passes over emitted IL: labels, positions, halt paths, unused roots/slots/heap pointer (with their 5 tests) | 9 |

`qbe.zig` still takes 47 of 51 recent commits: nearly every lane adds an
operation, and that means a case in `emitOp`/`emitAt` and often an `Emitter`
field. The split cuts what a lane reads, not that conflict; the next lever
there is a dispatch table so a new operation lives in its own lowering
module (as `qbe_managed`, `qbe_io` and `qbe_files` already do).

### `src/main.zig` (not split)

`main.zig` is 3,097 lines of file-level functions. The natural first seam is
argument parsing (`Parsed`, `ArgumentParser`, the `*Option` helpers, about
550 lines), but `Parsed` has 40 fields and `ArgumentParser` over 20. Moving
them out makes them `pub`, and Guardian caps a `pub` struct at 7 fields. That
is a rule at odds with a pure move; meeting it means regrouping the fields,
which is a design change for its own lane.

## Before and after

| file | before | after |
|---|---:|---:|
| `src/sema.zig` | 6,874 | 1,701 |
| `src/qbe.zig` | 3,168 | 1,825 |
| new `sema_*.zig` (10 files) | — | 6,284 |
| new `qbe_*.zig` (3 files) | — | 1,616 |
| total | 10,042 | 11,426 |

No file in the split set is over 2,000 lines; the largest module is
`sema_collections.zig` at 1,099. The 1,384 added lines are the forwarding
wrappers with their docs (118 wrappers), the hub aliases, 93 new doc
comments for methods and types that became `pub`, the named types below, and
the 11 tests.

## Changes other than moves

All of these are forced by the module boundary or by Guardian:

- A method returning or taking an anonymous `struct { … }` gets it named at
  file level, so the wrapper and the implementation agree on one type:
  `ExpectedOption`, `StreamMethod` (builtins), `ListAccess` (collections),
  `NumericOperands` (operators).
- `markerPositionDeclared`, a self-less helper two modules call, moved from
  `Checker` to `sema_shared.zig`. `integer_literal.Literal` is re-aliased at
  file level in `sema_expressions.zig`, since the `Checker`-level alias is out
  of scope there.
- Three lines that the added `comptime` parameter pushed past the 240-column
  hard limit are wrapped (two signatures, one struct literal).
- `drop_local`, `frame_map_guard_column` and `heap_call` moved with the code
  that owns them; `qbe.zig` re-exports `frame_map_guard_column`, which
  `qbe_frame_map_test.zig` reads as `qbe.frame_map_guard_column`.
- `loweredAllocates` stays in `qbe.zig` next to `unitAllocates`: split across
  files they trip Guardian's twin-drift rule, and together they are one
  question (does this IL allocate).
- Each new module registers in an existing `test { … }` block of
  `src/root_test.zig`; a new block would count as an extra test.
- **Tests.** Every commit must add test lines (Guardian's
  change-classification), and a move adds none unless tests move with it. The
  IL passes brought their own five tests. Each other module got one unit test
  of code that moved into it: the `Some`/`float()` shadowing rule, Python's
  `/=` and `%=` mapping, byte-buffer operand kinds, scoped `dir()` paths,
  byte-literal expansion, text-method hints, loop-variable rebinding, the
  wildcard arm, relocation misses, frame temporary sizing and pure callees.
  Three of them drive a module function through a stub struct holding only
  the fields that function reads, which the generic modules allow and
  `sema.zig` did not: a check can now be tested without a whole program.

No Guardian baseline or `guardian.toml` changed, and `build.zig` is untouched.

## Identity evidence

**Moved code.** `moved_identity` (script in the appendix) takes every `fn`,
`const` and `var` of the base `sema.zig` and `qbe.zig` (1,880 declarations),
finds the same name among the new files, and compares after normalizing
whitespace, dropping comment lines and undoing the three mechanical rewrites
(the `comptime` parameter, `name(Checker, self, …)` ↔ `self.name(…)`, a
leading `pub`). 1,874 are identical. The six that differ are the `Checker`
and `Emitter` structs (members moved out, aliases in) and the four functions
whose anonymous struct became a named type.

**Compiler output.** The base compiler was built from a detached
`git archive` of `b5255e75` with its own Zig cache; the new one is this
branch's Debug build (the post-merge binary is byte-identical to the
pre-merge one). Both ran with `--no-cache` from the same working directory:

| corpus | command | runs | identical | accepted | rejected |
|---|---|---:|---:|---:|---:|
| every `.my` under `tests/`, `examples/`, `bench/parity/`, `experiments/perf-parity-plan-20260922/suite` | `emit-qbe` | 446 | 446 | 157 | 289 |
| | `emit-project-qbe` | 446 | 446 | 131 | 315 |
| | `check` | 446 | 446 | 289 | 157 |
| | `check-project` | 446 | 446 | 132 | 314 |
| every `\\` source string in `src/` and `test/` Zig tests | `check` | 1,981 | 1,981 | 601 | 1,378 |
| | `emit-qbe` | 1,981 | 1,981 | 601 | 1,378 |

"Identical" means stdout, stderr and exit status all byte-equal. Emitted
output totalled 71 MB. Two snippets (unbounded generic recursion) exceed the
90 s per-run limit under both compilers and count as identical timeouts. The
same corpus was run after the builtins (step 1), places (step 2), expressions
(step 6), specialization (step 9) and root-protocol (step 12) commits, each
time with no difference. Diagnostics are covered by the 1,378 + 157 + 314
rejections above, whose rendered text is compared byte for byte.

## Gate

Run at `bf89c177` (the split plus `main` `4e332f70`), each step under the
gate slot, and compared with `gate_diff.py` against the coordinator's
`tooling-*.log` for `4e332f70`:

| step | result | failures (base / split) | selected tests (base → split) |
|---|---|---|---|
| `zig build` (Guardian, 88 checks) | pass | — | — |
| `zig build test` | 83/83 steps, 267 s | 0 / 0 | `root_test` 1,579 → 1,590; `integration` 180 → 180; the three small roots 11, 21, 7 unchanged; total 1,798 → 1,809 |
| `zig build test-qbe` | 50/50 steps | 0 / 0 | 311 → 322 |
| `zig build test-qbe-build` | 32/32 steps | 0 / 0 | — |
| `zig build test-schematic` | 29/29 steps | 0 / 0 | — |
| `zig build test-byte-io` | 28/28 steps | 0 / 0 | — |
| `zig build fmt-check` | 2/2 steps | 0 / 0 | — |

Both differences are the 11 new module tests and nothing else. In
`root_test` they are the 11 added lines. In `test-qbe` they come from the
`test-c-ffi` binary: `src/c_abi_test.zig` reaches the compiler, and Zig
compiles the tests of every file it analyzes, so its count goes 52 → 63. The
five IL-pass tests moved from `qbe.zig` and are still counted once. Every
count differs from the base by exactly the tests this branch added, so no
existing test stopped being compiled or selected.

Guardian's advisory findings grew by two function-length warnings, the
`Checks` wrapper struct of `sema_builtins.zig` (159 lines) and the `Lower`
struct of `qbe_frame.zig` (128), both under the 400-line hard limit. The
file-size warnings for `sema.zig` and `qbe.zig` remain (above the advisory
1,000 lines) but are no longer the two largest.

## Appendix: scripts

The one-off tooling stayed in the session scratchpad, not the repository:
nothing needs it after the split, and `scripts/` belongs to another lane. What
each did, so the evidence can be reproduced:

- `extract.py` — moves a span of methods out of a struct into a module:
  rewrites intra-module calls, generates the `Checks`/`Lower` wrappers and hub
  aliases, makes the hub members it needs `pub` (docs supplied per name), and
  sorts file-level declarations into copied imports, moved, shared or
  re-exported.
- `move_top.py` — the same for file-level functions (the IL passes).
- `identity.py` — the output comparison above.
- `moved_identity.py` — the normalizing declaration diff above.
