# S2-Lb: D1 in the shared frontend and old core

Base: `9ee2a484`; branch: `codex/new-core-s2-iteration`. This package implements
the accepted design §12 D1 decision in the old oracle. It does not edit `src/core/`.

## Behavior and guards

`iteration_place.zig` prepares entry ownership, saves each index once, rebuilds
stable rooted paths, and refreshes them before the body and at the continued/final
back edge. The root is counted as read on each iteration. Read-only sources retain
the entry-borrow fast path. Direct collection forms of `sum`, `any`, and `all` use
the same helpers; their closed numeric/Boolean folds cannot write the source or
call user callbacks. Generator folds and comprehensions can call user code and
use the live-place path.

| Source | Guard |
| --- | --- |
| Live list / mutable byte buffer | Current length must be at least the last observed length; update the bound after growth. |
| Dictionary / set / immutable str or bytes | Current length must equal entry length (Unicode scalars for text, octets for bytes). |
| Each indexed managed ancestor | Current length must equal that ancestor's entry length. |
| Fixed-array terminal | Length is static; read the local directly or refresh the field/index path. |

Growth observed on one step followed by shrink on a later step traps, including
a return to entry length. A transient grow-and-shrink entirely within one body is
not detected when the observed length is unchanged. `break` bypasses the next
guard. `reversed` keeps its fixed bound and exact terminal guard.

Syntactic root assignment in the body selects an independent entry snapshot;
field write-back stays live. A mut callee's whole-root write-back stays live too,
including same-length replacement. The six integration-only cases in
[mut_callee_rebinding.my](mut_callee_rebinding.my) require S2-La's ABI change and
must run after the two language lanes merge. The coordinator extended the two
original cases with forwarded mut parameters and function-value calls. All
forms expect totals 9 and 18, with the prior named copies unchanged. They are kept outside `tests/lang` because the
standalone Lb base has the previous callee-rebinding behavior.

Fixed arrays initially appeared to be exempt because their inherited tests
expected entry snapshots. The controlling design §12 D1 decision has no array
exception. `PY-ARRAY-ITER-1/2` and those tests now require live reads and preserve
copies made before the loop. A managed-element array entry snapshot uses an
independent semantic home, so normal lowering copies/owns its child values.

Managed indexing wraps the base initializer. Rebuilding reproduces that
initializer; the original index-expression block is retained in the entry spill,
including calls and negative-index normalization. Compound and negative
side-effecting index tests each require the counter to increment exactly once.
Temporary initializer lookup is bounded to the current function's statement
range, because local IDs restart while statement IDs do not.

## Preliminary candidate evidence

- [RC](logs/guest-live-rc-08.json), [GC-stress](logs/guest-live-gc-08.json), and
  [LLVM release](logs/guest-live-release-08.json): 22 fresh passes each, zero failures.
- [Structural guards](logs/d1-guards-08.log): 20/20 focused tests, comprising
  eight named D1 cases and twelve unnamed root blocks. Every D1 case runs under RC
  and GC-stress. Covers terminal shrink, observed growth then shrink, list/dict
  indexed ancestors, a managed ancestor of a fixed array, and shared dict/set growth.
- [Optimized trap probes](logs/guards-release-08.json): four LLVM O3/full-LTO
  runs all trap `R_LIST_ITERATION_MUTATION`.
- [Fresh-core conformance](logs/conformance-d1-08.log): 72 tests across the four
  changed guest files; debug and release each have 5 matches, 0 mismatches, and
  67 unsupported. Fourteen live-list cases are refused; fixed arrays, dicts,
  bytes, and string indexing account for the remaining unsupported cases.
- [Whole-tree Guardian](logs/guardian-08.log): all 88 checks pass in 1.44 s.
- [Package-exit coverage](logs/coverage-exit.log): 2,275 of 3,536 functions
  accepted (64%); 18 live-list mutations refused. The external Lox files are
  uncheckable alone (24 value-class diagnostics, two missing entries), so the
  sweep supplies no accepted Lox functions. It uses a private disk TMPDIR and
  takes 8.29 s.

The coordinator owns the combined full conformance run after the language lanes
merge, including the mut-callee root-rebinding interaction.

## Commands and build costs

All commands use this worktree's `.zig-cache` and disk `.tmp/s2-lb`, with
`ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache`, and run through
`scripts/build-slot.sh build` or the single shared `gate` slot. Build slots keep
reserved timing CPUs free; this package performs no timing workload.

The first plain install regenerated runtime assets and took 19.14 s; the next
edited install took 21.60 s despite compiler compilation taking only a few
seconds. This crossed the development-loop threshold and was reported. The
coordinator pointed to CLAUDE.md's established inner loop:

```
scripts/build-slot.sh build -- zig build affected-compiler --summary all
zig-out/focus/mylang test tests/lang/live_place_iteration.my --json --force
zig-out/focus/mylang test tests/lang/live_place_iteration.my --gc-runtime --gc-stress --json --force
zig-out/focus/mylang test tests/lang/live_place_iteration.my --release --json --force
```

That target installs the current compiler and QBE under `zig-out/focus` with
embedded runtime assets. [Final edited compiler rebuild](logs/build-focused-08.log)
takes 3.17 s (compiler 2 s); [preceding rebuild](logs/build-focused-07.log) takes
3.58 s. The final full gate still uses the required plain install graph. Runtime
asset regeneration is recorded separately from the compiler rebuild.

The [initial full gate](logs/gate-test-01.log) took 1061.50 s and ended with exactly
two failed tests: an inherited CLI fixture appended forever while expecting a
field-writeback snapshot, and an emitted-IL assertion forbade the existing closed
field store-back transfer in a live loop. The CLI fixture now grows finitely,
sees total 10, and preserves its named copy. The existing transfer certificate
is permitted because the live back edge re-reads the restored field. Both RC and
GC-stress language suites in that initial gate passed 1596 tests across 240 programs.
Zig prints `failed command` for some successful test stderr; the authoritative
result is its final Build Summary.

Old-core gates for preliminary candidate `f831003c`:

| Command | Result | Wall time |
| --- | --- | --- |
| `zig build test --summary all` | [115/115 steps; 2,962/33,142 tests passed, 30,180 skipped](logs/gate-test-02.log) | 894.39 s |
| `zig build test-qbe --summary all` | [51/51 steps; 518/518 tests passed](logs/gate-test-qbe.log) | 70.45 s |
| `zig build test-qbe-build --summary all` | [29/29 steps; cached test verdicts](logs/gate-test-qbe-build.log) | 0.23 s |
| `zig build fmt-check --summary all` | [2/2 steps](logs/gate-fmt-check.log) | 0.21 s |

The final full gate's RC and GC-stress guest suites each report 1,601 fresh
passes, zero cached/failed/skipped cases, across 240 programs. The 30,180 skipped
tests in the Zig build summary are reported separately; they are not counted as
fresh passes. The final plain install and runtime-generation steps are cached.

The [pre-commit `test-core` checkpoint](logs/gate-test-core.log) follows these
gates in the isolated nested `gate -- build` slots, with timing started after
slot admission: 5/5 steps, 147/147 tests passed, 85.89 s (under the 5-minute
limit). Its test binary compiles in 1 s; the new-core compiler is cached.

Guardian's final whole-tree run passes all 88 checks; subsequent required gates
reuse that green result. Initial complexity violations (27, then 26, against the
limit of 25) required extracting the foreach helpers. A duplicate canonical D1
spec tag was resolved by retaining one `spec:` and using `spec-case:` for the
remaining cases. The coordinator records this feedback in the shared Guardian
repository.

## Final D1 coverage correction

A read-only audit against controlling design §12.8 found two remaining source
paths: dedicated unfiltered list/set comprehensions bypassed the helper, and
generated gather bodies had clause/filter spans that excluded their produced
expressions. `iteration_effects.zig` now follows syntax IDs through the complete
statement/expression tree. The dedicated comprehension uses the same source,
guard and bound update as ordinary loops. Produced values, filters and nested
clauses see source writes regardless of sharing. Assignment expressions are
unavailable, so a comprehension cannot syntactically rebind its source root;
callee whole-root write-back remains live.

The immutable string/bytes shortcut also skipped managed ancestor guards and
stable-field replacement. These places now refresh, with the existing exact
terminal length check (Unicode scalars for text, octets for bytes). Syntactic
root assignment keeps an entry snapshot, including immutable augmented root
assignments such as `text += ...`; list `+=` is still in-place extend and stays
live. The prior immutable-terminal exception had no basis in §12.8 and is removed.
Read-only sources retain the entry fast path. No emitter or C4 count code changes.

- [RC](logs/guest-live-rc-11.json), [GC-stress](logs/guest-live-gc-11.json), and
  [LLVM release](logs/guest-live-release-11.json): 37 fresh passes each, zero failures.
  Adds shared unfiltered/filtered/nested comprehensions, set comprehensions,
  generator `sum`/`any`/`all`, fixed arrays with managed children, immutable field
  replacement, non-ASCII scalar indexing, and immutable root snapshots.
- [Structural guards](logs/d1-guards-10.log): 22/22 tests (10 named D1 cases and
  12 unnamed roots), with each D1 case under RC and GC-stress.
- [Optimized traps](logs/guards-release-11.json): 8/8 expected structural traps;
  the new string/bytes ancestor cases run in both RC and GC-stress LLVM release.
- [Fresh-core conformance](logs/conformance-d1-11.log): 87 tests; debug and release
  each have 5 matches, 0 mismatches and 82 unsupported. The 22 live-list cases are
  refused rather than mismatched. Other refusals are fixed arrays (48), dicts (5),
  string indexing (4), bytes (2), and sets (1).
- [Warm edited compiler](logs/build-focused-11.log): 3.60 s, compiler 3 s.
  [Current core build](logs/build-core-11.log): 2.13 s, compiler 1 s.
- [Whole-tree Guardian](logs/guardian-11.log): 88 checks pass in 1.64 s.
- [Package-exit coverage](logs/coverage-exit-11.log): 2,280/3,558 accepted (64%),
  including 26 explicit live-list refusals, in 6.20 s. Uses the private disk
  `TMPDIR=.tmp/s2-lb/coverage-exit`. External Lox still has 24 value-class and two
  missing-main refusals; this package does not change its source.

Final follow-up old-core gates:

| Command | Result | Wall time |
| --- | --- | --- |
| `zig build test --summary all` | [115/115 steps; 2,964/33,166 tests passed, 30,202 skipped](logs/gate-test-03.log) | 920.23 s |
| `zig build test-qbe --summary all` | [51/51 steps; 518/518 tests passed](logs/gate-test-qbe-03.log) | 78.80 s |
| `zig build test-qbe-build --summary all` | [29/29 steps; cached test verdicts](logs/gate-test-qbe-build-03.log) | 0.25 s |
| `zig build fmt-check --summary all` | [2/2 steps](logs/gate-fmt-check-03.log) | 0.23 s |

Both RC and GC-stress guest suites report 1,616 fresh passes, zero
cached/failed/skipped cases, across 240 programs. The Zig summary's 30,202 skipped
tests are not fresh passes. Plain runtime asset regeneration takes 17 s;
the edited compiler cost remains the separate 3.60 s inner-loop measurement.
The isolated [pre-commit checkpoint](logs/gate-test-core-03.log) passes 5/5 steps
and 147/147 tests in 91.72 s, below the 5-minute limit. Nested `gate -- build`
slots exclude admission time and isolate the run; the test binary compiles in
1 s and the core compiler is cached. The missing-row diagnostic is an expected
negative test; the authoritative Build Summary is green.

## C4 handoff and scope

C4's shared frontend and old-core semantic half moved from runtime-levers WP-5
to S2-Lb: place-source desugars, per-path guards, and live root reads. Existing
hidden receiver and snapshot lifetime holds remain; no C4 RC hold/count emitter
or certificate implementation was changed. The new typed shape permits the
existing `RC-CLOSED-FIELD-TRANSFER-2` certificate in the covered live field
store-back case. Remaining C4 count re-plumbing stays paused.

The [corpus audit](corpus-audit.md) records the affected inherited fixtures and
the read-only external Lox scan. The `examples/corpus` applications contain no
foreach loops. No Lox foreach body relies on the previous snapshot answer;
conservative same-root writes refresh unchanged collection fields. External Lox
source is not modified by this package; the coordinator owns its integration
and source decisions.
