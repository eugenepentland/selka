# A03 handoff

- Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
- Branch: `codex/memory-closeout-20261012-A03`.
- Owned files: this directory only; no production changes.
- Harness commit: `d23f84d0c`; the following evidence/admission commit is the
  current branch head when this handoff is delivered.
- Implemented: isolated failure-preserving census adapter; 81-case pinned
  manifest preserving the original 30 IDs and all historical 48 matrix cases.
- Completed tests: all 81 C0 release cases / 131 executions; zero RC, no managed
  exit leaks, matching outputs/exits and 81 clean LLVM/symbol audits. Original 30
  freshly measure 23 allocating / 7 allocation-free at inputs 4 and 11. No
  migrated workload refuses; original unmigrated source checks admit 21/refuse 9.
- Fresh controls: JSON hits add 3 allocations/320 bytes at 1/16/128 siblings;
  misses add 0. Record explicit copies use 27,000 blocks versus field transfers
  at 21,000 for 1,000 unpacks; both managed peaks are 1,536 bytes. These are
  source-variant comparisons on C0, not a compiler-only before/after saving.
- Baseline compiler: A09 full C0 Debug installation, SHA-256
  `324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
- Tooling checks: Python AST parse and manifest uniqueness/coverage assertions;
  first commit's Guardian hook passed all 88 checks. No Guardian feedback write.
- Final dependency: coordinator-frozen integrated compiler and exact SHA.
- Evidence paths: `manifest.json`, `C0-release/{REPORT.md,results.json.gz,
  raw-json.tar.gz,controls.json,sha256.json}` and `C0-smoke/`. Full scratch raw
  outputs/binaries/LLVM: `.tmp/memory-closeout/A03/C0-batched/`; earlier `C0/`
  and `C0-smoke/` remain intact. `C0-batched.log` reports every release lane.
- Scheduling: coordinator-approved leases of at most ten compiler invocations,
  reacquired after 60 seconds at safe boundaries; separate queue-wait receipts.
  SIGUSR1 saves a checkpoint after the active lane. No nested admission.
- Shared-file requests: none.
- Known limitations: managed counters do not measure RSS/native overhead;
  source checks of the original unmigrated corpus are reported separately.
  LLVM/symbol audit does not replace A07's runtime ABI layout proof.

The final compiler must run all five modes (405 builds / 655 executions) on the
same 81-case manifest. Per coordinator direction, C0 was measured release-first;
its result correctly marks `complete_matrix: false`. No remaining production
defect was observed by A03; the integrated candidate dependency remains open.
A baseline-only success does not qualify default promotion or legacy retirement.
