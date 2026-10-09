# Frontend follow-through

The user authorized this updated implementation plan on October 9, 2026,
after reviewing the paused October 8 handoff. The starting point is the merged
readable frontend, `d21b2dfa9b36f1de285985a6b38e39847d6beca2`.
Work proceeds on `codex/frontend-followthrough-20261009`; main is not a work area.

## Sequence and acceptance

1. Finish and qualify the new language: reconcile active documentation, add a
   `.my` formatting gate with explicit fixture exclusions, complete arena
   removal with structured fixes, and migrate the full frozen Lox and EDA
   corpora. Preserve case/mode membership and distinguish intended source or
   diagnostic changes from behavior regressions. A small migration fixture is
   not full external qualification.
2. Improve editing and recovery: synchronize parsing at newline/dedent,
   report independent syntax faults, and preserve reliable spans and source
   ownership. Introduce lossless syntax incrementally where formatting,
   fixes and navigation need it.
3. Reduce avoidable incremental work: measure current misses, then support
   stable identities for resolved nominal types, type arguments and callable
   labels/mutation positions. Retain useful caches and conservative misses;
   do not identify types solely by their printed spelling.
4. Simplify effects around explicit contracts: retain capability checks and
   explicit mutation, audit consumers before deleting inferred facts, and
   implement Core allocation checks using the shared cost API, including
   internal callees and cold paths. Review changed verdicts explicitly.
5. Introduce source-shaped typed lowering one construct family at a time,
   then remove duplicated generic checking while retaining necessary concrete
   checks. Compare against the current compiler, not the obsolete S5 IR hash.
6. Extend cost visibility using existing cost reports, counters and Juice.
   Refresh selected FP2 workloads; keep static may-allocate sites distinct
   from measured allocations. Require evidence before introducing copy
   annotations or renaming operators.

Each batch needs focused checks, the repository full gate and formatting
gate, plus a report of changes, measurements, remaining limitations and
semantic decisions. Large representation or semantic changes get a reviewable
checkpoint before expanding into the next phase. Guest HTTP libraries and
borrowed views remain separate work.

## Historical work

FB1 and the cost CLI are already ancestors of main. They are not merge tasks.
The old FP2 measurements remain useful evidence, with their original omissions
and lower-bound qualifications. Do not merge its large evidence branch wholesale.
Keep named constraints. Reconsider alias and functional-replacement removal;
defer domains until nominality, codecs, layout and ABI replacements are proved.

The old timing audit remains 15/21 accepted jobs and 177/333 samples. It is
historical, unfinished evidence, not a passing gate for this compiler. Its six
pending jobs and quiet matrix are not prerequisites for this revised plan.
Use a fresh source-bound baseline for current performance work and disclose
old-budget comparisons and any proposed threshold changes. Never refreeze the
old oracle or alter rejected receipts.

Historical dirty worktrees and raw evidence remain in place. A read-only
checkpoint inventory is in
`experiments/frontend-followthrough-20261009/historical-evidence.json`.

## Initial ownership

- Coordinator: integration, arena removal, migration fixes, final validation.
- Docs agent: active language and cache reference reconciliation.
- Formatting agent: corpus selection, normalization and gate wiring.
- External qualification agent: verified frozen source snapshots, migration
  mappings, complete case/mode comparisons and reduced blocker examples.

All agents share the new branch with disjoint file ownership. Builds use the
shared build-slot wrapper and exclude reserved timing CPUs. Heavy gates and
measurements are serialized. Shared caches, other sessions' files, protected
benchmark trees and historical evidence are not cleanup targets.

## First batch checkpoint

Implementation `d8fe5b797` closes the first batch with 94/94 repository gate
steps, 15/15 formatting steps, 88 whole-tree Guardian checks and complete
Lox/EDA qualification. The full report and rejected attempts are preserved in
`experiments/frontend-followthrough-20261009/REPORT.md`. External migrations
are reviewed patches against the frozen pins; application worktrees are unchanged.

## Remaining phases implementation

The closeout implements phases 2–6 in bounded steps. Parser recovery keeps the
original source and span-bearing tokens as the lossless basis and refuses to
publish a partially recovered AST. Nominal specialization reuse validates fresh
resolved provider identities and schemas; absent identities remain misses.
Developer dumps, coverage and Core check now share configured entry resolution,
source budgets and policy with normal builds, resolving EDA's `src.` imports.

Explicitly written `noalloc` contracts receive the stronger Core allocation
check, including ownership expansion, cold paths and transitive calls. Existing
`effects(...)` lists retain their guest-level meaning. Inferred facts with live
capability, mutation, ownership and cache consumers remain in place.

Range loops are the first source-shaped checked lowering family. Their checked
endpoints and loop plan survive until Core lowering; the shared directory-path
validator removes one genuinely duplicated generic/concrete check. The semantic
payload format changes once, to v4. Further construct families and removal of
necessary symbolic generic checking are not implied by this step.

Selected Lox, EDA, stdlib and operation entry graphs refresh the typed cost
census. A worked Juice/counter example distinguishes static sites, managed
allocation events and whole-process instructions. It does not establish an
application speedup or justify new copy annotations.

Implementation, source-bound qualification, changed verdicts and limitations
are recorded in `experiments/frontend-closeout-20261009/REPORT.md`. That report
is the authoritative closeout record; earlier failed candidates remain evidence.
