# Frontend closeout, October 9

This batch implements the remaining bounded steps in the October 9
follow-through plan on `codex/frontend-followthrough-20261009`, starting at
`cf7c620dcd69c4d8097a73b732ad043bcd4433fe`. Implementation is committed as
`fb868aace` (55 source/test/documentation files, +1,528/-281 lines), with the
noalloc followup in `48e741592` (10 files, +58/-11). The corrected compiler passes
the full repository, formatting, source-quality and frozen external qualification.
The remaining bounded steps of the updated October 9 plan are complete.

## Result

- Parser recovery reports independent declaration and statement errors across
  newline/dedent boundaries. Original source and token spans retain comments
  and spelling; recovered partial ASTs are never published to later passes or
  structural fixes. Lexer/header failures and unmatched delimiters remain
  conservative. See [recovery report](recovery/REPORT.md).
- Developer dumps, coverage and Core check share configured entry resolution,
  source budgets and policy with builds. The EDA `src.` import-root discrepancy
  is fixed; successful typed dumps now cover its selected executable graph.
- Nominal specialization replay resolves identities against the fresh catalog
  and checks complete provider schemas. Reordering unrelated declarations can
  reuse a body; schema changes invalidate it. Ambiguous, absent or otherwise
  unproven identities still miss. Callable labels and mutation positions remain
  part of the identity. See [cache report](cache/REPORT.md).
- Explicitly written `noalloc` is checked against ownership-expanded Core,
  including internal callees, cold blocks, runtime scratch, COW and unresolved
  calls. Existing `effects(...)` lists retain guest-level semantics. Inferred
  capability, mutation, origin and cache facts remain because their consumers
  still need them. See [effect audit](effects/REPORT.md).
- A source-shaped checked range retains endpoints, setup and loop plan until
  Core lowering. Every statement remains 80 bytes; each range eliminates three
  synthetic statements. Semantic payload format changes once, to v4. The
  generic and concrete directory-path checks share one validator while needed
  symbolic and concrete checking remains. See [range report](range/REPORT.md).
- Selected typed cost inventories and a worked Juice/counter example reuse the
  existing cost tooling. See [cost report](cost/REPORT.md) and the
  [user workflow](../../docs/tooling/cost-workflow.md).

## Compiler and evidence identity

`candidate-qualified.json` binds 614 compiler/source files, including the root
build helpers, and the locally preserved immutable executable
`artifacts/mylang-qualified`, SHA-256
`21319448ba51241f917c040004d1a3c7123e5516d5f0a766d7cff557294793f2`.
`0bbfeb740:experiments/frontend-closeout-20261009/install-5.log` records the successful 9/9-step install. The installed compiler
used by the final gate has this same hash. Earlier `0bbfeb740:experiments/frontend-closeout-20261009/candidate-1.json` and
`0bbfeb740:experiments/frontend-closeout-20261009/candidate-final.json` describe preserved intermediate checkpoints, not the final
qualified compiler. Compiled artifacts and
generated caches are local products; raw captures, inputs, failed attempts and
source-bound receipts are retained in the evidence commits.

The before compiler is the previously qualified first-batch artifact, SHA-256
`5e072ee17b825cfbd40ed5533c3bce9f166ce4ae576395020cd5e435cc45ed11`.
No comparison uses failed or empty EDA dump output as a reference. The current
Core IR schema is unchanged from this batch's base; it is not asserted equal
to the obsolete S5 schema hash.

## Measurements

The identical cold/relocated `Box[T]` workload originally checked a specialization
twice and retained none. The final compiler checks it once, stores it once and
reuses it for the relocated request. This measures avoided checking, not an
uncontended elapsed speedup. The complete original-fixture cache suite passes
68/68, including module identity isolation, reorder and schema invalidation.

The range differential covers 86 existing files in raw/facts modes. Both
compilers accept 100 commands and reject the other 72; all 100 successful
outputs are byte-identical. Six accepted representative programs also match
raw Core, facts, release LLVM and native output/status. The endpoint/dynamic/
generic probe returns the expected 249 in both compilers. A larger custom probe
triggers the same pre-existing release CFG refusal in both; its source and
failure are retained separately, without changing Core to hide it.

The refreshed selected graphs contain 382 Lox, 1,213 EDA, 110 stdlib and three
operation-workload checked bodies. These are selected entry graphs, not the
historical all-source FP2 universe. The EDA graph exposes 66 string additions
inside typed loops, of which four have depth two or more. Opaque nodes, unused
generic templates, caller-loop context and several lowered operations remain
explicitly uncounted.

The worked operation scenario processes 128 records and prints `2144` in both
ordinary and counted runs. `checksum` has six static may-allocate sites, two
unresolved. Its four invocations account for 24 managed allocations, with three
more outside that function; all managed blocks are freed. The ordinary whole
process instruction samples are 206326, 206327 and 206327 on this machine.
These are source-bound observations, not a before/after performance claim.
Runtime scratch outside managed counters and unknown LLVM outcomes stay unknown.

## Qualification

The final repository gate passes **94/94 steps**, with **2,256 executed Zig test
entries** and 20,987 shard skips (`full-gate-3.log`, exit 0). Doctests run 218
examples and check 59, with zero failures or mistagged blocks; 23 documented
exclusions remain. Gate body time is 122.58 seconds; outer time including
admission is 128.43 seconds. This is a shared-machine correctness run, not an
uncontended speed measurement.

Whole-tree Guardian passes 88/88 on the final source (`0bbfeb740:experiments/frontend-closeout-20261009/commit-followup.log`).
The earlier explicit whole-tree checkpoint is `0bbfeb740:experiments/frontend-closeout-20261009/guardian-full-3.log`. Focused
checks include 210 range/parser/semantic/navigation/quality cases, 68 cache cases,
eight Core allocation regressions, 13 native followup cases, and four census walker
tests. These overlapping suites are not summed into a unique-test total.
Formatting passes 15/15 steps (`0bbfeb740:experiments/frontend-closeout-20261009/fmt-qualified.log`, 5.92 seconds body). The
corrected compiler's frozen external qualification passes all
450 commands (84 Lox, 366 EDA) with exact case/mode/verdict membership. Native
comparisons pass all 974 Lox answers and 34 byte-identical EDA outputs. The six
property-bearing EDA commands retain the prior seed, 8679566789041942096.

A direct comparison with the previous qualified compiler on the same migrated
sources confirms unchanged source inventories and exact contract/provider hashes.
All 366 EDA reports and 81/84 Lox reports are byte-identical. Only the three
configured Lox source/settings fingerprints change; their preimage equivalence
remains unproved, as in the first batch. No case names, providers, statuses or
verdicts were relaxed. The complete report audit and original S5 differences
are preserved in [qualified external evidence](external-final2/REPORT.md).
The earlier successful corpus capture is retained in `0bbfeb740:experiments/frontend-closeout-20261009/external`; it does not
replace qualification of the corrected compiler. The fresh source guard verifies
all 614 source hashes and the qualified executable after the complete capture.

Full-gate attempt 2 completed in 115.45 seconds after approximately 980 seconds
of shared admission wait. It reports 85/94 steps, 2,247 selected passes, seven
selected failures and one failing doctest. Resource result boxing violates
written noalloc, and the scalar-count UTF-8 error diagnostic itself allocates.
These are retained failures. The final correction uses pooled static text for
the fixed UTF-8 error instead of allocating it. Native tests preserve its exact
error payload and static checks prove zero allocation sites in the bounded body.
Seven resource fixture/example mains now use the accurate guest-level
`effects(filesystem)` contract; their ownership assertions remain unchanged.
The documentation counterpart is updated, and an explicit noalloc regression
rejects the real capability-block allocation. No allocating helper was added to
the allocation-free allowlist. The corrected full gate passes as recorded above.

## Failed attempts and timing limits

The first broad Core implementation mistakenly treated every effect ceiling
excluding managed allocation as a full runtime allocation promise. Integration
exposed that compatibility error. The final shared predicate selects written
`noalloc` only; temporary fixture and wrapper ceiling edits were reverted.
Explicit noalloc negatives remain strict and ordinary callback/mutation
contracts retain their original assertions.

`0bbfeb740:experiments/frontend-closeout-20261009/full-gate-1.log` is rejected evidence: 55 failures and one interrupted test,
not a passing gate. A network integration test remained in socket accept after
its client compiler failed. After observing the wait, the coordinator stopped
only its own stuck test process; the interruption receipt records both signals.
The 466-second command duration includes that blocked test and is not an
uncontended compiler performance measurement. The rejected broader candidate
and its raw range/cost/cache observations remain preserved.

Guardian also caught duplicate primary SPEC tags, missing documentation,
overlong lines and test structure issues during integration. These were fixed
without policy/baseline changes. Full-gate admission waits are disclosed
separately from test-body time. Other sessions, shared caches and protected
benchmark worktrees were not stopped, altered or pruned.

## Scope retained for future work

This closes the current plan's bounded implementation steps;
it does not assert that every frontend representation or conservative cache miss
has been eliminated. Range is the first lowering family. Lossless editing still
uses source plus tokens rather than a second whole-program CST. Concrete
noalloc instances receive backend checking; abstract generic contracts and
opaque foreign/callback allocation remain conservative. Effects with live
consumers, named constraints, domains, aliases and functional replacement remain.
Guest HTTP libraries and borrowed views stay separate work.

The historical October 8 timing campaign remains 15/21 accepted jobs and
177/333 samples. The quiet matrix and six pending jobs are neither rerun nor
relabeled complete. `preservation-check.json` verifies the five historical
checkpoint files and branch HEAD against the preserved inventory. No merge to
main or push is part of this closeout.

Guardian feedback is appended and committed in guardian-zig as `675dac5`.
Four evidenced ROI subjects were labeled locally; other findings were left
unclassified. Large evidence commits are separated by directory, below the
64 MiB diff-reader ceiling, with successful and rejected captures retained.

## Archived full evidence

Full captures and the original version of this report remain in commit `0bbfeb740`,
reachable from `main` and `codex/frontend-followthrough-20261009`.
Retrieve any archived path with `git show 0bbfeb740:PATH` (paths are repository-relative).
