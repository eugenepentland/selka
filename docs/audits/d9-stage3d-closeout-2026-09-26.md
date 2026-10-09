# D9 WP-3d closeout: class and Cell retirement

**Branch:** `codex/d9-stage3d`, validated implementation tip `f1265a0b`.
The design decision preceded implementation in
`d9-stage3d-class-cell-design-2026-09-26.md`. This branch integrates the
validated stage 3a+3c join (`a1e51689`), stage 3b COW work (`a0d8a12c`,
`7b4eeddf`, `0be261e4`), and the dual-mode `mut` record fix (`d305a5df`).
This scheduling used validated branches before they landed on `main`, with
real two-parent joins. The current main `b292660a` is already an ancestor;
no artificial extra merge was made. The main checkout was not edited.

## Result and design

Under `--value-semantics`, a `class` declaration now raises `E_VALUE_CLASS`,
and the builtin `Cell[T]` raises `E_VALUE_CELL`, with replacement guidance.
The switch-off mode retains both for the migration window. A user-defined
`Cell` remains legal. The checker rejects an unused class and a Cell type in
a signature as well as a constructed Cell. SPEC `VALUE-SEMANTICS-10`, focused
unit/CLI tests, and `docs/value-semantics.md` pin the behavior. The integrated
`VALUE-SEMANTICS-11` change makes an explicit `mut` record parameter write
back in both modes, including scalar-only records. Arenas remain supported.

The canonical P1 census has 80 class declarations. The source scan found
`network::Chunk[N]`, raising the working census to **81**. All 81 were
migrated to value records/unions or explicit object-table ids; two additional
classes in the active incremental fixture were migrated too (**83 active
declarations total**). The checked inventory is
`d9-stage3d-class-inventory-2026-09-26.json`. A literal repository-wide
`class` grep still finds **24 declarations in 22 files**. The inventory
classifies every one as a fixed historical/design/performance snapshot,
intentional class diagnostic input, or Python-syntax rejection probe.
None is an active owned program. This is the explicit exception to the plan's
literal “no class left in the repo” wording; rewriting measured baselines or
diagnostic inputs would erase their purpose.

The active migrations include the three standard-library carriers,
`bench/parity` binary tree and nbody programs, schematic output, 53
`tests/lang` declarations, the S-expression trial's Tally/Cursor/Lexer,
two T2 calculator AST declarations, the incremental fixture, and all 16
classes in the pinned external Lox port. Finite data uses records/recursive
unions. Identity-bearing Lox heap objects use `ObjRef` indices into an
object table and explicit read/modify/storeback. The T2 and Lox changes are
reviewable tracked patches with reconstruction scripts in
`d9-stage3d-migrations/`; the Lox script verifies the pinned source hash
before patching. No cosmetic keyword conversion was used for graph identity.

## Acceptance evidence

| Requirement | Evidence |
| --- | --- |
| No class in active owned programs | 81 canonical plus two active out-of-census declarations migrated; 24 historical/diagnostic declarations classified individually in the inventory. |
| Outputs preserved | S-expression 114/114 tests in each mode, four compare fixtures, 17/17 goldens; parity/schematic and `tests/lang` pass in the normal gate; 10-step incremental fixture comparison had zero mismatches. |
| Lox VM, 13 pinned scripts | The reconstructed value port passed 63/63 port tests in each switch mode; `verify-lox.py` passed 13/13 VM scripts at smoke size on the final compiler/binary, and earlier 13/13 at benchmark sizes. It compares exact stdout and exit status with pinned expected files. |
| Full gate | At `f1265a0b`, serialized under `.d9-closeout-gate.lock`: `zig build test` passed (guest corpus 654/654 across 114 programs; doctest 202 run, 54 checked, 11 skipped, zero failures), then `test-qbe`, `test-qbe-build`, and `fmt-check` all passed. Commit-hook Guardian was 88/88. Gate logs remain in `.tmp-stage3d/gate-*.log`. |
| Value-semantics guest migration status | The full switch-on corpus is not yet green: 595 passed, 20 failed, four dropped across 114 programs. Exact cases and actions are in `d9-stage3f-switch-corpus-handoff-2026-09-26.md`; these are assigned to WP-3f, with two performance/correctness cases called out separately. |

The first full-gate attempt was blocked by a concurrent native staging
directory race and a newly activated dual-mode `mut` record rule. The
joined race fix `78ec28ba` and record fix `d305a5df`, followed by fixture
adjustments at `f1265a0b`, produced the green gate above. Focused validation
of those adjustments: CLI 1/1, guest properties 16/16, capabilities 13/13,
value-semantics unit 28/28, time/random unit 14/14, and doctest 202 run/54
checked/zero failed. The main ref had not advanced beyond the ancestry
already present before the gate.

## Material tree-interpreter limitation

The Lox **VM** satisfies the specified 13-script acceptance. The migrated
**tree interpreter** produces the same bytes but has a major performance
regression with the switch on. A bounded Debug QBE sample used the pinned
`binary_trees.lox` with only its first line changed to `var N = 4;`, one
core (`taskset -c 2`) and matching stdout for all three binaries:

| Source and mode | Wall time | Instructions | Cycles | Peak RSS |
| --- | ---: | ---: | ---: | ---: |
| Pinned class source, legacy | 0.10 s | 192.6 M | 75.1 M | 9 MB |
| Migrated value source, legacy | 0.40 s | 1.084 B | 0.799 B | 13 MB |
| Migrated value source, switch on | **27.02 s** | **390.8 B** | **77.2 B** | **39 MB** |

A 10-second `perf` sample of the switch-on binary attributed 39.9% of cycles
to `scan_elements` and 29.6% to `share_at`; the hot stack passes through
`myl_native_cow_unique` → list clone → collection and old-reference scan.
The guest caller includes `heap::push` from `interpreter::evaluate`. The
migrated interpreter has 177 `__wb = it.rt; helper(mut __wb); it.rt = __wb`
storeback sites. Its `Runtime` record contains large `stack`, `objects`,
marker and other lists; extracting the whole field appears to mark all of
them shared, then a primitive stack mutation clones one and forces GC
scanning. This is a profile-backed hypothesis, not yet a proven compiler
root cause. WP-3b has the exact source, binary, perf data and these counters
for field projection/move/inout investigation. Its later scalar-only
recursive-box COW fix is separate and is not merged into this gated 3d tip.

This bounded N=4 sample is not directly comparable to the plan's N=10
baseline instructions. It is sufficient to show a material regression that
must remain visible during integration and stage 3f performance acceptance.

## Handoff

WP-3f must migrate the 18 remaining alias-dependent guest assertions,
resolve four checker refusals, and investigate `gc_footprint`'s step limit.
The deep recursive-value switch test's OOM is fixed in WP-3b `54edf716`
(focused 1/1 in 0.51 s) and needs that tip in the joined default-flip branch.
Its handoff inventory also lists embedded Zig-source tests and the CPython
velocity oracle requiring review. Keep the historical class inputs as
diagnostic/baseline fixtures. The Debug compiler, value-port reconstruction
and bounded profile inputs in `.tmp-stage3d-lox/` and `.tmp-stage3d/` remain
available read-only for the next integration pass.
