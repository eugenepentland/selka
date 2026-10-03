# Scalar reads in Lox sweep

This source-only experiment changes the two read-only object-table operations in
`heap.sweep`: checking for a free slot and computing an unreachable object's
abstract byte cost. Each helper receives readonly `Runtime` plus `ObjRef` and
returns a scalar. The caller no longer materializes owning `Obj` carriers for
those reads. The normal indexed `Obj.free` write, list COW, ascending sweep,
free-slot append/reuse order, mark reset, byte subtraction, arithmetic and bounds
checks, collection thresholds, and all allocation/collector statistics remain.
`blacken`, `allocate`, `object.cost`, and compiler/runtime implementation stay
unchanged. The local cost projection intentionally repeats `object.cost`'s
case expressions; `compare_ownership.py` verifies identical return expressions.

The control is root's **immutable positive-joined-flat** source, recorded by
`positive-joined-flat-build.json`, SHA256
`115f8796ceeca3df54f7d660f26094aea2ef8e9e2b34610fdf6ef08080107989`.
It already contains the joined tree/environment changes, scalar table probe and
closure-arity projection. It is not a fresh current `apply-lox.sh --optimized`
port. `qualification.json` records every control, initial-arm, and final-arm
file hash, including the driver provider JSON. The frozen positive compiler is
`da94c579e03ffaab2e9d43a6d9119b529bbb01dab5085e7a3986a6ecd98912c6`.
The source-only experiment worktree starts at `406c7eeb`; the preceding commit
`2636f862` separately records the negative LLVM noinline investigation.

`sweep.patch` and `initial-sweep.json` preserve the initial 78-test source and
LLVM/QBE binaries handed to root for measurement. Their historical metadata
retains the root/control provenance in `source` and has candidate module hashes
under `source_sha256.sweep`. `final-sweep.patch` adds two heap regressions to the
same runtime implementation. `build-final-sweep-{rc,gc}.json` instead describes
its exact 80-test source directly: `source` is the qualified directory and
`source_sha256` is a direct dictionary of all 26 modules. Earlier sources and
binaries remain immutable.

## Emitted mechanism

The archived LLVM-front-end SSA in `emitted/` compares unchanged and candidate
functions from fresh frozen-compiler builds. These counts are static call sites,
including alternative cleanup branches, rather than executed instruction or
ownership counts.

| Sweep `Obj` glue operation | Control sites | Candidate sites |
| --- | ---: | ---: |
| loan | 3 | 1 |
| retain | 1 | 0 |
| take | 2 | 1 |
| unloan | 19 | 3 |
| drop | 19 | 3 |
| indexed list set | 1 | 1 |

Sweep SSA decreases from 2,456 to 1,744 lines. Both new read helpers emit zero
ownership calls. The remaining sweep object loan/take/set implements the normal
indexed free write. Scalar helpers retain normal negative-index normalization,
bounds checks, union matching, and checked cost arithmetic. Exact ownership
sites and fail-call sites are in `emitted/ownership.json`; the original and
candidate SSA bodies are archived alongside it. Root owns performance
measurements and acceptance; this lane makes no wall-time gain claim.

## Qualification

Both regressions passed in every full-suite mode. One exercises every object
cost, Runtime and separately saved env snapshots, weak intern removal, and
free-slot reuse. The other triggers collection while allocating: the incoming
object is charged before sweep and published into a reclaimed variable-sized
env slot afterward. No source inputs or smoke/compare sizes change.

Four suites pass **80/80**, with no cached, failed, skipped or dropped tests:
LLVM `mylang test --release` and QBE `--mode ReleaseFast`, each with RC or native
`--gc-stress`. All use the established `--max-steps 1000000000 --timeout-ms
120000` qualification limits. Exact commands, complete output and source hashes
are in `unit-qualified.json`. Guest LLVM builds independently use `--llvm-opt 3
--lto`; RC and GC artifacts have distinct filenames, cache directories and
native runtime objects. QBE uses its default guest optimization.

`validation.json.gz` contains **696 passing** exact status/stdout/stderr
comparisons, including Lox collector statistics: all 13 corpus smoke programs
with RC in both evaluators, 14 focused programs in both evaluators, and 23 error
programs per evaluator. Each candidate backend runs ordinary and Lox-stressed
modes; native GC artifacts run the focused/error cases under native stress.
There are **104 explicitly unrun** native-stressed corpus smoke observations.
The historical command requested native smoke case `empty`, which does not
exist in this corpus; consequently none ran. The validator now rejects unknown
names. Reproduction omits that optional selector and preserves the same bounded
matrix. This is not a complete native-stressed corpus pass.

`partial-harness-history.json` preserves two initial harness mistakes: the test
subcommand rejected unsupported `--backend`, then its default step limit caused
three existing tests to fail while 77 and both new regressions passed. These
historical outputs are separate from the corrected full qualification.

## Reproduction

Supply the exact joined-flat control directory identified in
`qualification.json`. Preparation verifies every file before and after patch
application and refuses an existing destination. Private build caches, outputs,
and TMPDIR are selected by the scripts; all builds/tests enter the shared
`build-slot` wrapper, keeping the parent's timing CPUs free.

```bash
lane=experiments/lox-sweep-scalar-20261003
scratch="$PWD/.tmp-lox-sweep-replay"
compiler=/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-lowering-20261003/.tmp-lox-lowering/positive-release/bin/mylang
control=/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-20261003/.tmp-lox-parity/joined-flat
python3 "$lane/prepare.py" --control-source "$control" --dest "$scratch/source"
python3 "$lane/build.py" --source "$scratch/source" --work "$scratch" \
  --compiler "$compiler" --name final-sweep --runtime rc
python3 "$lane/build.py" --source "$scratch/source" --work "$scratch" \
  --compiler "$compiler" --name final-sweep --runtime gc
python3 "$lane/test.py" --source "$scratch/source" --work "$scratch" \
  --compiler "$compiler"
```

For exact output comparison, make a manifest like `validation-manifest.json`
with the recreated candidate paths and unchanged positive-joined-flat LLVM/QBE
controls. Then invoke `validate.py` through `scripts/build-slot.sh build`, using
the unchanged corpus `bench` directory, `regressions.json`, and a private output
path. The historical manifest and all build identities remain in this directory.
