# S3-L: ephemeral dictionary projections

Branch: `codex/new-core-s3-language`, isolated locked worktree from `92590700`.
This package implements Wave A only. No push or merge into main.

Qualified: all four old-core gate steps are green; core tests pass 205/205;
strict debug/release conformance is 1,243 matching, zero mismatching and 275
unsupported; the 50-case dictionary fuzz qualification is clean. The resumed
results below contain complete commands, times, refusal tables and retirements.

## Decisions and implementation

The shared concrete and symbolic checkers enforce `E_VIEW_STORED` on builtin
view expressions outside direct iteration/comprehensions and immediate `len`,
`in`, `list`, `set`, and `sorted`. Checks use builtin declaration identity;
`DictItem` is an ordinary storable value and user declarations with view names
keep their ordinary behavior. `mut` arguments, discarded expressions, returns,
aggregate storage, rebinding and `.mapping` extraction are rejected too.

Messages show `list(<exact expression>)`, preserving keys/values/items and an
interior receiver. Structured edits are offered for inferred local bindings and
inferred list literals. Annotated parameter, return, field and collection element view types require
an accompanying declaration migration, so they receive the suggestion without an
uncertain automatic edit. The CLI fixture proves first fix, successful check,
and a clean second fix pass.

The concrete old checker previously rejected immediate view membership with
`E_MEMBERSHIP`. Keys membership uses dictionary hash lookup; values and items membership
scan projected entries using existing checked locals, loops, equality and break
nodes. It preserves needle-before-
container evaluation and does not allocate a snapshot. Runtime tests cover keys,
managed values, items, missing members and empty dictionaries. No core IR changes.

## Migration audit

Read the S3 plan, S0/S1/S2 design notes, S2 plan rules/status and exit report, the
new-core stage/exit plan, and one-count D2 before editing.

`rg -n '\.(keys|values|items)\(' examples bench benchmarks -g '*.my'` found four
sites: the three knucleotide parity programs and expanded runtime collections.
All are direct comprehensions, immediate list/sorted snapshots or direct loops.
There are no stored-view sites in examples or benchmark source.

Read-only audits of the canonical external value-semantics Lox checkout
`.tmp/lox-bench/wt-mylang/benchmarks/lox/ports/mylang` and later
`.tmp/lox-fixes/tree/benchmarks/lox/ports/mylang` found no dictionary projection
calls, including resolver.my and heap.my. No external checkout was edited and
no stop condition was triggered.

Mixed language/backend tests now use explicit lists and assert independent
snapshot behavior. Four stored-view-only language modules are preserved intact
under `test/fixtures/view-storage/`; their 35 former test names are recorded in
`converted-tests.txt` and the CLI rejects all four corpora with `E_VIEW_STORED`.
Their active language modules now test snapshot value/aggregate/return/rebinding
behavior. This intentionally removes runtime execution of the retired held-view
protocol; it does not claim those 35 old runtime tests still run.

Two core builder refusal tests now expect shared-checker `SourceError` before
lowering. Immediate-view core fixture cases remain. Stored source fixtures use
lists. SPEC retires stored-view protocol bullets, keeps the defensive catalog
acyclicity rule, and documents D2; dictionary user guides describe snapshots.

## Validation

All builds use build-slot and full gates use gate-slot. test-core uses the gate
slot; performance timing uses CPU 10 only. The runtime baseline checkout is
untouched. Full validation results and commit are added below when complete.

Initial compiler install: Guardian 88 checks pass; compiler build 3 s, complete
12/12 build steps. Focused D2 rejection cases passed; allowed membership revealed
and repaired the prior checker gap above. Gate logs retain intermediate failures.


## Required stop checkpoint

S2 §6, inherited by S3 §6, requires **stop and report when a rebuild takes over
10 seconds**. A focused CLI build reported the compiler step as 12 seconds.
`over-10s-transcript-excerpt.txt` records the exact command, compiler subtree and
provenance. The original focused log was reused before the coordinator noticed
this stop condition; the preserved excerpt is explicitly identified as a tool
transcript excerpt rather than the original complete log.

The coordinator confirmed the stop applies even under contention. All further
implementation edits, builds, gate reruns and source commits are held. Only the
already-running initial full old-core test is allowed to finish for evidence.
No S3-L package commit exists, no integration has been performed, and the
required full gates/conformance/spec commit remain incomplete.

Completed focused evidence at this checkpoint:

- `focused-d2.log`: 19/19 passing, 43 ms test run; compiler step 6 s.
- `focused-fix.log`: 5/5 passing, 3 s test run; includes CLI fix idempotence and
  four archived stored-view corpora rejected with E_VIEW_STORED.
- `membership-runtime.json` plus `.err`: exit 0 and one passing native runtime
  membership/snapshot test; managed values, items, missing values and empty
  views included. Stdout verdict and process exit both checked.
- `compiler-install-green.log`: 12/12 build steps, Guardian 88/88 checks.

Guardian repairs are retained in the two initial failure logs: 13 unverified
SPEC migration tags plus one 246-character source line above the 240-character
cap; after updating SPEC and splitting the line, one orphan retired
LIVE-VIEW-SNAPSHOT-1 tag remained and was migrated to the retained catalog rule.
This was useful enforcement with no observed Guardian bug.

Initial full old gate has already identified prelude fixture lookup issues
(repaired before the hold), an archived corpus temporary-file name mismatch
(repaired and focused CLI rechecked), and a now-obsolete RC inline-take assertion
for a migrated list snapshot (unrepaired at the hold). The final initial gate
verdict will be appended once the process completes. The gate did not run the
latest full source state, since focused fixes occurred during this initial run;
a green rerun is still required if the user authorizes resumption.


### Final outcome of the already-running initial gate

The initial `scripts/build-slot.sh gate -- zig build test --summary all`
finished with **exit 1**. Its retained Build Summary is 105/115 successful
steps, 9 failed steps, and 8 failing tests. `gate-test.log` is the complete
output; `gate-test-status.txt` records its process status.

The eight initial failures are two CLI fixtures, two inline-take marker
assertions, two plain-record scalar update assertions, the python-core snapshot
expected total, and the builtin-view declaration-identity helper. The CLI
fixtures and declaration-identity helper were corrected before the stop; the
latest focused CLI passes both fixture cases, while the identity helper still
needs a rerun. Four marker assertions remain in
`src/qbe_rc_inline_take_test.zig:55,66` and
`src/qbe_rc_plain_record_write_test.zig:86,134`. The python-core fixture needs
its snapshot key-length/value sum changed from 32 to 33. These last five
corrections remain unapplied, as required by the stop.

The initial language-corpus step also stopped at its earlier prelude fixture
lookup errors. Those were repaired before the stop and later module compilation
covered 342 programs with all equal to whole-program compilation. The completed
initial gate also reports 68 native-boundary agreements and passing doctests.
None of these partial successes qualify the full old gate.

Coordinator-owned Guardian feedback commit completed under the gate slot after
the old gate released it: `c147da6`,
`feedback: mylang — S3 Wave A rebuild-stop checkpoint`. Only FEEDBACK.md changed
(3 added lines); Guardian's whole-tree gate reported 0 blocking checks.
`guardian-feedback-commit.log` preserves that admin-only result. No mylang source
commit, further build/gate, or integration merge was performed after the hold.


## Resumed qualification after user review

The user approved D2 and S3-0 and authorized resumption. This section supersedes
that checkpoint's hold and outstanding-fix status; the earlier logs remain
historical evidence. The amended rebuild threshold applies only to an
uncontended `zig build core` under a build slot with no gate running. Old-core
compiler rebuilds have no 10-second stop threshold. Integration records the
amendment in `427f2f25`.

The resumed checker builds one immediate-consumer table per check and shares it
across ordinary and symbolic checking. Each view validation reads its own table
entry rather than rescanning program statements and expressions. Source view
types fail `E_VIEW_STORED` at their declaration name in parameters, returns,
record fields and collection elements, including unused generic declarations,
phantom type arguments and zero-length arrays. This uses builtin declaration
identity, so ordinary user records named `DictValues` remain legal.

Keys `in` and `not in` now use the dictionary hash-membership operation. The
checked-tree test finds exactly two contains operations and no generated loops.
Values and items membership scan projected entries, preserving evaluation order
and avoiding snapshots. Full native coverage checks keys, managed values, items,
missing members and empty dictionaries.

As explicitly requested, the inline-take `held` source function and its two
assertions, and the plain-record `Held` / `held_field` / `named_held` source
cases and their assertions were deleted. They were not converted to list cases.
The python-core snapshot item total is 33. Additional source cases made invalid
by declaration rejection were retired:

- `qbe_rc_field_transfer_test`: `ObservedHolder` / `held_root` and its marker assertion.
- `qbe_rc_variant_read_test`: `Held` / `HeldItem` / `held` and its marker assertion.
- `qbe_rc_native_variant_runtime_test`: the `Choice.held` arm and matching C test block.
- `rc_glue_limits_test`: `Tokens`, `Held`, `HeldChoice`, and the C Tokens held-view block.

The qbe stored-view lowering case and nested/recursive view annotation cases
now assert D2 rejection. Existing defensive manually constructed catalog graph
checks and runtime Pair-loan/count-limit checks remain. No new manual held-view
API or runtime fixture was introduced to replace the retired source cases.
The dictionary fuzz generator's one stored values projection now materializes
a list snapshot; the strict dictionary fuzz kind remains the same.

Each resumed build or gate output uses a distinct `resume-NN-*` log. Both the
gate and build locks are held for full old-core steps and test-core. The outer
gate fd is retained separately before the inner build wrapper reopens fd9.
An initial naive nested-wrapper launch (`resume-10`) was canceled while waiting
for another build, before a timed compile began. The qualified core rebuild
(`resume-11`) also holds every remaining build-slot lock through the
coordinator's `exclusive_core.py`; its timing excludes lock admission wait.

Whole-tree Guardian `resume-09-guardian.log` passes all 88 checks. Resumed repairs
addressed a seventh runtime parameter by passing the existing Reuse bundle,
conditional cleanup complexity, a test computation loop, a tried return value,
and a repeated import literal. `resume-08-focused-d2.log` passes 24/24 selected
unit tests, including declaration spans and hash membership without loops.
The exclusive core rebuild passes in 1.58 seconds with 317,664 KB peak RSS
(compiler step 1 second); the helper's 34.429-second other-build wait is outside
the timed command.

Final gate verdicts, exact command records, conformance, coverage and fuzz
results follow after the running checks finish.


The first resumed eight-shard core gate (`resume-12`) returned exit 1 in
68.88 seconds: 204 of 205 tests passed. Its sole failure was an obsolete
interior stored-view fixture expecting a core `Unsupported` refusal. That test
now expects shared-checker `SourceError` and verifies that the core refusal
record stays untouched. The existing record-field refusal test now carries
the primary `NEW-CORE-IR-2` tag. This changes test expectations only.

Checked coverage (`resume-17`) returns exit 0 in 17.15 seconds, peak RSS
39,004 KB, with all four child commands exiting 0. It accepts 3,213 of 3,595
qualified function names, compared with 3,185 of 3,627 at S2: 28 more accepted
and 32 fewer total names following the documented retirement/migration.
No stored dictionary-view refusal reason remains. The raw corpus outputs and
all remaining refusal occurrences are retained in `resume-17-coverage/`;
`resume-17-coverage.log` reports the deduplicated tables. No performance-row
measurement or core IR change is part of S3-L.


### Final qualification results

`resumed-commands.json` records the complete argv, retained-lock wrappers,
command exit status, output paths, wall time and peak RSS. Each row below
exits 0. Times exclude wrapper admission; concurrent build-slot work overlapped
the old gate, conformance and fuzz. The core rebuild alone excluded every other
build and gate. test-core retained the gate and build slots, and its longest
shard was 72.37 seconds, within the 90-second pace rule.

| Check | Result | Seconds | Peak RSS, KB | Evidence prefix |
|---|---|---:|---:|---|
| core build | 3/3 steps | 1.58 | 317,664 | `resume-11-core-build` |
| test-core | 205/205 tests; 12/12 steps | 74.17 | 329,664 | `resume-15-test-core` |
| old test | 115/115 steps; 3,001 tests pass | 951.61 | 2,418,236 | `resume-13-old-test` |
| old QBE | 519/519 tests; 51/51 steps | 84.14 | 608,548 | `resume-19-old-qbe` |
| old QBE build | 29/29 steps | 3.00 | 608,572 | `resume-21-old-qbe-build` |
| format | 2/2 steps | 0.23 | 46,892 | `resume-22-old-fmt` |
| strict conformance | Debug and release each 1,243 match / 0 mismatch / 275 unsupported | 757.88 | 363,524 | `resume-16-conformance` |
| coverage | 3,213/3,595 accepted; four child exits 0 | 17.15 | 39,004 | `resume-17-coverage` |
| strict dictionary fuzz | 50 accepted; 750 comparisons; complete and qualified | 785.81 | 244,148 | `resume-18-fuzz-dict` |

The full old `test` also passes doctests, 68 QBE/LLVM native-boundary agreements,
342 module-compilation comparisons, and the 60/120-step incremental matrices
with zero mismatches. The 30,585 skipped entries in its summary are shard
selection skips, not failing or skipped language tests. The QBE build gate
checks its 29 build steps; that is not claimed as 29 runtime tests.

Full conformance uses `conformance_checked.py --set all --modes debug,release
--leakcheck --verify`, including stdout/status agreement. The full remaining
first-refusal and static-exclusion tables are in `resume-16-conformance.log`.
Relative to S2's 1,540 tests, 35 retired held-view runtime cases become the four
archived rejection corpora, 12 new snapshot tests replace their active files,
and one immediate membership test is added: 1,518 tests in the active sweep.
Matching tests rise by 19 and unsupported tests fall by 41. No dictionary-view
storage refusal remains; the 275 remaining unsupported tests belong to the
unchanged future S3 work and inherited exclusions.

Strict dictionary fuzz uses seed 20261006 and checks old/debug/release/verify
builds, stdout and status. All 50 cases are accepted in all modes; all 750
comparisons match across 1,000 native runs. Its 24 trapping comparisons match;
there are no crashes, timeouts, refusals, leaks, fact failures or incomplete
cases. `resume-18-fuzz-dict/summary.json` records `qualified: true`, `complete:
true` and an empty failure list.

The exact coverage name delta is in `coverage-name-delta.json`: 46 removed
names (six formerly accepted), 14 added names (all accepted), and 20 existing
refused names now admitted. No existing accepted name becomes refused. Only
`tests/lang` changes; its qualified-name count is 3,156 to 3,124. This accounts
for the full 32-name denominator reduction. `remaining-coverage-refusals.md`
contains every remaining deduplicated refusal reason, and the checked raw
corpus reports preserve the original outputs.

Guardian's explicit SPEC check covers 1,435/1,435 behaviors. The resumed task's
required feedback-only commit is `af909ac` in guardian-zig; its whole-tree
Guardian gate reports 88 checks and zero blocking findings. The earlier
checkpoint entry remains untouched. The S3-L source and evidence revision is
the commit containing this README on `codex/new-core-s3-language`; the
coordinator's Wave A report records its final hash and archives the package's
Guardian commit log. Final 35-row definition identity is coordinator-owned and
will be checked on the integrated head. Core IR, persisted format layouts,
external Lox and the runtime baseline were not changed by S3-L. Wave B is not
started; hand off this qualified package for the Wave A review stop.


The agent's initial package commit command accidentally invoked Guardian's
compound workflow, whose phase 2 launched a redundant `zig build test`.
The coordinator clarified that the normal Git pre-commit hook already runs the
required full Guardian gate. That duplicate process was canceled with exit 143
before any commit; its distinct log is `resume-24-compound-canceled.log`, with
provenance in the accompanying `.txt`. The earlier qualified old gate remains
valid. The membership helper's doc comment was then clarified to include hash
lookup for keys. This is a comment-only correction, so behavioral checks were
not repeated. The final package commit uses ordinary Git commit with the
88-check pre-commit hook enabled under retained gate and build locks.
