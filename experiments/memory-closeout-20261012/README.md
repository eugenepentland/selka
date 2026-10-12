# Memory-management closeout, 12 October 2026

Execution in progress. None of the three release milestones is yet qualified.
The session has one coordinator and ten concurrent workers in independent sibling
worktrees. The original checkout and its unrelated edits are preserved.

C0 is `fbfcaa7a923186a8e773c3760f81c10aa345a432`, exactly `origin/development`
at kickoff. Both documented ancestor checks passed. Integration branch:
`codex/memory-closeout-20261012`.

| Milestone | Status |
| --- | --- |
| Qualified implementation | Pending integrated candidate and full verification |
| Zero-RC default | Pending implementation qualification |
| Active legacy RC retirement | Pending default qualification and installed component boundary |

The [kickoff record](kickoff.json) pins toolchain, Guardian, worktrees, host,
admission budget and preserved checkout. The [public export census](public-exports-C0.json)
records all 206 public declarations across the current standard-library modules;
A04/A05 supply contracts and executable coverage. [Item ledger](ledger.json).

The freshly rebuilt C0 compiler installation is recorded in A09's installation
manifest; it preserves `bin/`, `libexec/` and `tools/` together. Historical reports
remain immutable and are not new measurements. Each worker publishes its sources,
raw results and handoff under its own A01–A10 directory.

Publication is not authorized by this handoff. Work remains on local branches;
no push or self-hosting branch merge is part of this run.

## Current integration evidence

The fresh C0 census passed all 81 cases and 131 counted executions. Within the
original 30, 23 still allocate and 7 are allocation-free; all migrated cases run
without RC or managed exit-live bytes. This is baseline evidence, not final
candidate qualification. See [the C0 report](A03/C0-release/REPORT.md).

Integrated work includes bounded map scheduling, allocation-overflow guards,
managed-list permutation operations, command and cache mode plumbing, independent
library snapshots, borrowed comprehensions and sorting, repetition, bounded affine
resource lifetimes, and compiler regressions found by the larger survey. Focused
worker results identify their own revisions; they do not certify a later binary.

The user expanded this run to support Result lists. That implementation is still
in progress, along with remaining migrations and ownership paths. A frozen early
integration snapshot is undergoing the full verification coordinator to expose
cross-feature defects before C1. Normal defaults, active RC retirement and the
real independent component compiler pin remain pending.

The exploratory full gate on `245e892f8518943ee44a0cc6009ab4b4fa6bca43` failed after 45 fresh selected actions (no reuse). Raw output is in `coordinator/exploratory-verify-01/`; dictionary snapshot crashes explain the language, interface, no-allocation and Core dictionary failures. The newer scalar snapshot fix still requires integrated reruns, including the CLI fix case. Support3 is source `0d17e4e130706639c0f49e78b60502bfb2151ebc`, binary SHA256 `7b911f91acefccc9dbfd0d1bcfee46e1ec5acc7f47a7ca5954481d44393c7de7`. Native API testing exposed a preexisting uncacheable unit-object lifetime bug, reproduced independently with C0; A01 is fixing it. This installation is not C1.
