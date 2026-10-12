# A03 handoff

- Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
- Branch: `codex/memory-closeout-20261012-A03`.
- Owned files: this directory only; no production changes.
- Proposed commits: pending fresh execution evidence and required commit hook.
- Implemented: isolated failure-preserving census adapter; 81-case pinned
  manifest preserving the original 30 IDs and all historical 48 matrix cases.
- Tests so far: Python AST parse; manifest generation asserts 30 original IDs,
  48 historical samples, ten library fixtures and unique IDs. 655 executions
  are planned; none claimed complete until a results artifact exists.
- Baseline dependency: A09 fresh C0 full installation, currently building.
- Final dependency: coordinator-frozen integrated compiler and exact SHA.
- Evidence paths: `manifest.json`; future raw outputs under
  `.tmp/memory-closeout/A03/{C0,C1,C2,C3}` as applicable.
- Shared-file requests: none.
- Known limitations: managed counters do not measure RSS/native overhead;
  source checks of the original unmigrated corpus are reported separately.
  LLVM/symbol audit does not replace A07's runtime ABI layout proof.

The final compiler must rerun the matrix. A baseline-only success does not
qualify default promotion or legacy RC retirement.
