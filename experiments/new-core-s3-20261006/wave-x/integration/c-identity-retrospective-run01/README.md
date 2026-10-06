# Retrospective predecessor C/M/runner → S2 identity proof

This receipt qualifies **function definitions and semantic site tables only**
for the retained predecessor compiler source
`9637eb9a1aa4af8ee0ecd88838ceed09b228d812` against the S2 baseline
`92590700cb0bf5e4dc19cc1f0c836c3a41693f64`. It is neither final S3-X evidence
nor a claim of complete-module equivalence.

The corrected audit covers all **35 modules / 343 definitions**, with exactly
**70 timer guard pairs / 35 native entry grants** and **zero residual function
changes**. Removing the two authorized Host guard sites per row reproduces
each complete original semantic site table.

The earlier audit could silently overwrite function bodies because its symbol
search was not restricted to a definition's header and did not accept dotted
unquoted LLVM names. For `row_set_dedup`, it represented only 12 of the actual
13 definitions. This script keys each body from its own header, accepts quoted
and complete unquoted names, rejects duplicates, and verifies that every
`define` header has exactly one extracted body. Its receipt lists every actual
definition, including the three distinct `myl.dict.*.find` helpers in that row.

## Reproduce

Run this command from this directory, or invoke the script by its absolute
path from any working directory:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 proof.py
```

The default command reads only persisted local inputs, validates the historical
SHA authority and all raw diffs, and prints deterministic JSON. It does not
build a compiler, read another worktree's cache, or write evidence. The saved
[reproduction check](reproduction-check.json) ran this command from `/` and
confirmed that stdout equals [summary.json](summary.json) byte-for-byte.

For an additional receipt, use a fresh output filename; existing outputs are
refused:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 proof.py --output reproduced-summary.json
```

`--write-raw-diffs` was used only during initial capture. It creates raw diff
files exclusively and refuses to overwrite them; do not use it when replaying
this already captured directory.

## Inputs and authority

- [before/](before/) contains all 35 complete retained S2 LLVM modules.
- [after/](after/) contains all 35 complete retained predecessor LLVM modules.
- [raw-diffs/](raw-diffs/) contains full-module unified diffs, recomputed from
  those complete local bytes and verified on every replay.
- [historical-identity-summary.json](authority/historical-identity-summary.json)
  pins the before/after SHA-256 hashes. The new proof uses this receipt for
  input and exact Host boundary authority; it independently enumerates and
  compares all definitions instead of trusting the historical parser's
  coverage claim.
- [c-source-contract.json](authority/c-source-contract.json) records the
  predecessor source commit. [provenance.json](authority/provenance.json)
  pins both authority files, lists every input SHA, and records the original
  capture locations for provenance only. Those locations are unnecessary for
  reproduction.
- [proof-initial-run.txt](proof-initial-run.txt) records the initial proof
  command, status, and output. No baseline or compiler rebuild was performed.

## Narrow transformations

Each source main must contain exactly two adjacent
`myl_core_io_at` / `myl_core_host_check` pairs immediately before its two
existing `runtime_bench_now` calls. The script checks their exact historical
site indices and block names, records their full removed text and resolved
site/debug metadata, and proves both blocks are outside CFG cycles. Other
functions may contain no such pairs or unaccounted Host checks/location calls.

Each native `main` must contain exactly one inserted Host grant, used exactly
once as the source-main Host operand. That grant is removed and its sole
operand use restored to the original constant `1`. No other Host grant is
permitted in any function.

After these exact edits, only instruction-defined SSA values are alpha-renamed,
and site/debug IDs are resolved to their original semantic values. Parameters,
block labels, named types, CFG edges, opcodes, operands, calls, and flags remain
in the comparison. No helper or whole function is omitted.

## Scope limit

**Outside-function module content is unqualified.** Declarations, globals,
attributes, and other module-level content are retained in the complete LLVM
inputs and raw diffs. The script records hashes and byte counts for that
remainder as an inventory, but does not normalize it, excuse its differences,
or use its removal to claim complete-module identity. The complete semantic
site table is the one explicitly checked module-level structure.

The JSON therefore reports `qualified_within_function_and_site_scope: true`,
`full_module_identity_qualified: false`, and `final_s3_x_qualified: false`.
This static retrospective proof adds no runtime, performance, timing, native
test, build, or final exit-gate qualification.
