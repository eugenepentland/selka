# D9 WP-3e closeout: alias migration warnings and `mylang fix`

**Branch:** `codex/d9-stage3e`. This branch began from validated WP-3a
`7c1fc1f8`, then made real two-parent merges of the accepted integration at
`0f8903d2`, `3730b5ce`, and `c85e695b`. The last merge includes the accepted
WP-3d class-free Lox migration (`19144c19`), WP-3b COW, T1, Q1, and Q2. The
plan scheduled WP-3e after WP-3a landed on `main`; using validated branch
tips before landing was a scheduling-only deviation. The `main` checkout was
not edited, merged into, or pushed. The most recent main at branch start,
`b292660a`, is an ancestor through the accepted integration. No arena feature
was removed and the compiler was built in Debug mode.

## Result

With value semantics off, the checker now emits `W_ALIAS_DEPENDENT` at a
transfer with evidence of a later observable alias-dependent write. Its four
messages identify a **local alias**, **class graph**, **store**, or **across a
call**. The analysis uses typed path and managed-value facts, follows match
bindings and nested constructors, and excludes fresh buffers/values where no
alias survives. It runs in the shared library/program check path, including
`check-module`; the switch-on path suppresses migration warnings and applies
its normal value checks. This is advisory: migration still needs source review
for class identity and indirect ownership.

`mylang fix ENTRY.my|DIR --check` previews structured repairs without a
write; `mylang fix ENTRY.my|DIR` applies non-overlapping edits and rechecks.
For a mutable local copy such as `alias = pins` followed by `alias.append(2)`
and `len(pins)`, the warning carries an insertion of `pins = alias` after the
standalone write. The focused CLI test verifies preview leaves the file
unchanged, application removes the warning, and the result prints `2` in
both modes. Non-mechanical cases carry no speculative edit. SPEC
`FIX-MIGRATION-1` and `ALIAS-MIGRATION-1` through `-4` have tagged tests.

The fix engine is an adapted **subset**, not a merge of `devspeed`. The
provenance is `665f0b2f` for `src/fix_command.zig` and the two-line main
dispatch, and `bf05c5e5` for exact edit fields and diagnostic-v1 rendering.
This branch imported only those pieces into `src/fix_command.zig`,
`src/main.zig`, `src/diagnostic.zig`, and `src/diagnostic_output.zig`, plus
their focused tests and SPEC clauses. It did not import devspeed's fixture
tree, Python migration helper, unrelated parser/call changes, or installed
tool dependencies. The alias warning pass and its structured storeback fix
were implemented on this branch.

## Historical P1 census

The comparator is the P1 101-site corpus on `exp/e2-value-semantics`, with
its `sites.jsonl` and mut-marker patch. The repository examples and language
fixtures were frozen from this branch at `3730b5ce`, immediately before the
WP-3d source migration; the pinned Lox source was reconstructed separately
from its P1 hashes and patch. This prevents the later class/fixture rewrites
from silently erasing historical sites. Each source was checked under the
switch-off compiler, including each Lox module as a library. The complete
unique coordinate sets are preserved in `d9-stage3e-census-expected-2026-09-26.tsv`
(101 rows) and `d9-stage3e-census-observed-2026-09-26.tsv` (107 rows).
Scratch reconstruction, source-context warnings, and command transcripts are
in `.tmp-codex-stage3e/` in this worktree.

| Comparison | Result |
| --- | ---: |
| Exact basename/line matches | 93/101 (92.08%) |
| Verified source-context line shifts | 3 |
| Normalized matches | **96/101 (95.05%)** |
| Remaining historical sites not warned | 5 |
| Extra coordinates before/after line normalization | 14 / 11 |

The three verified shifts are
`examples/standard-time-random/main.my:15→14` and
`tests/lang/value_equality.my:93→92, :95→94`. Each warning refers to the
same statement and category as the historical row. The historical key uses
basename and line; the two `main.my` rows are distinct (`gc-default:10` and
`standard-time-random:15`).

The five substantive misses are:

| Historical site | Cause |
| --- | --- |
| `arena_class_escape.my:63` | The nested `Some(child)` match binding enters a cyclic class graph; the warning reports the reciprocal store at `:58` and later alias assignment at `:66`, but does not pinpoint this intermediate binding. |
| `heap.my:72` | P1's `copy_clean` flags a new `CallFrame` containing `function.code.code`; this pass has no later divergent source write to that new frame. |
| `resolver.my:200` | P1's `copy_clean` flags the class statement accessor before `r.program.stmts[id]` replacement; no later read through the old `node` is proven. |
| `resolver.my:247` | P1's `copy_clean` flags the block match binding before replacement with `slot_count`; no later divergent read through the old binding is proven. |
| `vm.my:151` | P1 flags a class match binding although the branch uses the class only for the constructor and method lookup; no alias-dependent mutation is observed. |

The 11 non-shift extras were reviewed against their source, not assumed to be
true positives:

| Classification | Count | Coordinates and reason |
| --- | ---: | --- |
| Observed meaning change omitted by P1 | 6 | `arena_class_escape.my:58` makes a reciprocal cycle and `:66` aliases `again` before `back.value` writes and `kept` reads; `arena_managed.my:74` escapes a holder of `older`, which is then appended/read; `interpreter.my:488` takes `klass.methods` after retaining `klass` and then mutates the table; `option_niche.my:226` escapes a holder of a shared list before two paths are mutated/read; `vm.my:378` aliases retained `closure.upvalues` before captured entries are written. |
| Class retirement/potential alias only | 4 | `heap.my:124,:126` transfers an `obj` into `rt.objects`, and `vm.my:128,:136` moves a class-bearing function into a frame. These are relevant to class retirement, but these exact sites have no demonstrated later source write/read divergence. They should not be counted as proven 101-site semantic changes. |
| Unproven warning | 1 | `arena_class_escape.my:125` escapes `[made, made]` and only checks `len(kept) == 2`; the duplicate class reference is not subsequently mutated. |

Earlier broad warnings at fresh `byte_buffer` conversions, scalar-only `Point`,
fresh option literals, and read-only resolver accesses were removed. The
warning pass intentionally does not inflate recall by marking every class
transfer or copy-clean edge. A finite queue/visited-set graph search replaced
recursive descendant exploration: checking the complete class-free Lox
module graph fell from more than 150 seconds to **0.30 seconds** on the same
Debug compiler run, without changing the 96/101 normalized census result.

## Migrated Lox behavior

The exact class-free port is reconstructed by WP-3d's
`docs/audits/d9-stage3d-migrations/apply-lox.sh` at `19144c19`; it verifies
the 26 pinned source hashes and applies the tracked patch. With this branch's
Debug compiler, `mylang test PORT --max-steps=10000000 --no-cache` passed
**63/63 across 10 programs** in legacy mode and again with
`--value-semantics`. Debug QBE binaries built from the same port in each mode
passed **13/13** pinned smoke-size VM scripts via the tracked
`verify-lox.py`; the verifier compares exact stdout bytes and zero exit
status against the pinned expected files. Thus both modes produce the same
expected output on all 13 scripts. The verifier is a standalone audit script,
not an installed migration tool.

The dual-mode scalar-only record `mut` writeback rule, committed here as
`18d66f92` and integrated into WP-3d as `d305a5df`, makes the fixed Lox
source valid under the switch-off checker too. A dedicated SPEC
`VALUE-SEMANTICS-11` CLI test verifies that a scalar-only record parameter
writes its caller in both modes. The port's five genuine overlap sites were
also rewritten as explicit object-table/slot writes in WP-3d's tracked patch.

## Gate and remaining limits

The serialized four-step gate passed with this report present. Every step ran
through `scripts/build-slot.sh` under `.d9-closeout-gate.lock`: `zig build
test` had 654/654 cached guest cases across 114 programs and 231/231 CLI
integration tests; `test-qbe` passed 426/426 tests, including 231 checked
golden sources/fixtures with zero mismatches; `test-qbe-build` and
`fmt-check` passed. Guardian passed 88/88 on the builds and whole-tree commit
checks. The logs are `.tmp-codex-stage3e/final-gate-*.log`. The first gate
attempt found one stale pre-existing CLI assertion that expected empty stderr
for an alias-dependent legacy example. The assertion now checks for
`W_ALIAS_DEPENDENT`; its focused test and the complete second gate passed.

The mechanically safe fix covers same-type mutable named locals;
class-graph, nested store, and complex across-call migrations may need a
manual object-table or `mut`/storeback rewrite. The historical classifier has
five unreported P1 coordinates and five unproven extra warnings as listed
above; neither limitation changes the measured 96/101 acceptance result.
