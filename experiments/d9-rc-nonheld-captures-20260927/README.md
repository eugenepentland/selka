# Exact nonheld capture evidence

This is a bounded compiler optimization, not Stage 4 acceptance. See the
[audit report](../../docs/audits/d9-rc-nonheld-captures-2026-09-27.md) for its
independent input-role and whole-local lifetime obligations.

Run the archive-only checks:

```sh
python3 experiments/d9-rc-nonheld-captures-20260927/verify.py
```

`identity.json` records the frozen joined baseline, candidate compiler and exact
source hashes. `source.patch.gz` contains production and permanent-test changes
against the recorded parent, excluding this report/archive. The parent contains
the approved design and real-merges the specified baseline.

`measurements.json.gz` holds 32 builds, 48 retired-instruction observations and
16 counted executions. The 32 native manifests authenticate QBE and actual LLVM
O3/full-LTO. `native-identity.json` records `.text` hashes separately from whole
binary hashes. `emission.json.gz` and complete before/after emitted programs
preserve the exact changed and unchanged functions. `accepted.json.gz` contains
24 fresh observations of the untouched accepted-GC binaries; their original
build identities are retained separately.

`guests.json.gz` and `controls.json.gz` include commands, exact compiler/binary
hashes, outputs, statuses and counted trap/normal cleanup. Control sources are
in `controls/`. Unit, Guardian, formatting and Debug build receipts are included.
Failed initial attempts are explicitly retained and excluded from passing totals.

The Python drivers preserve the executed commands; `controls-resume.py` is the
exact continuation script, while `controls.py` defaults to a fresh complete run; run them from the repository root
only after choosing fresh scratch paths and reviewing their explicit compiler
paths. They preserve private caches, build slots, CPU 10 timing, explicit GC
stress and actual LLVM release selection. Immutable binaries remain at the
paths in the receipts and are intentionally not checked in.
