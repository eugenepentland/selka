# Selected compiler AST public qualification

This closes the selected AST candidate's public-test qualification gap. The
historical 336 public passes used a different compiler; this receipt executes
all 84 tests freshly on frozen d14a7040 and adjacent QBE 99ad919d, against root's
exact round3/ast source37. That source matches the already qualified selected
AST native source and the round3 composition's tree input; only interpreter.my
differs from accepted84. No root/source/binary/canonical files were edited.

All 336 public tests passed: 84 in each LLVM/QBE × RC/native-GC-stress arm, with
zero cached, failed, skipped, dropped or unloaded tests. Every actual report
contains exactly the 84 names declared by the frozen source. Four distinct empty
private cache paths ensure fresh execution. LLVM uses `--release`, QBE uses
`--mode ReleaseFast`, and runtime flags are `--rc-runtime` or `--gc-stress`.
The commands keep normal public-test step accounting; they do not drop checks.
All four directory commands omit `--cases` and every reported provider identity
is empty. The Clock fixtures are structurally preserved, with no provider-backed
execution claim from this receipt.

The runner snapshots all 37 files of candidate and accepted84 baseline, selected
compiler/QBE, prior selected native completion receipt/artifacts, root AST RC
ELFs/manifests/receipts/runtime archives, root source/build metadata and pinned
SPEC before and after. Existing native identities remain unchanged, including
root AST LLVM 180575c3 and QBE 246f2178. Fresh native-test archive/object/manifest
artifacts are also hashed and checked after execution. The existing unaccounted
1168+96 native comparisons and eight refusal probes were not rerun or counted
as new observations here.

`run.py` records full argv/environment, reports, test identities and artifact
hashes under the separate `.tmp-lox-ast-selected-public-20261003` workspace.
It runs through `scripts/build-slot.sh build` with private TMPDIR and excludes
CPUs 2, 3, 10, 11. `pack.py` rechecks completed data without running guests and
preserves deterministic gzip copies of all four complete JSON reports and the
full before/after receipt. `qualification.json` provides the compact result;
`checks.json` records the explicit Guardian gate. This qualification runs no
performance workloads and makes no speed or parity claim.
