# Tree evaluator ownership experiments

These cumulative overlays apply to the unchanged optimized Lox port reconstructed
from mylang commit `fd86729e`. They preserve the benchmark's evaluator, object
representation, algorithms, allocation points, roots, and checked semantics.
There are no compiler or runtime changes in this lane. Central measurements and
the choice of integration candidate belong to the parent lane.

| Overlay | Change from the previous arm |
| --- | --- |
| `env.patch` | Indexed environment slot writeback preserves snapshots; prepare call arguments in a new environment before publishing it once. |
| `split-clean.patch` | Pass immutable Program separately from mutable Interpreter, keeping the resolved AST alive throughout execution. |
| `calls.patch` | Read a scalar TreeCallee descriptor before recursive execution or instance allocation. |
| `flat.patch` | Pass named mutable Runtime and Output parameters through recursion; Interpreter owns only depth and return scalars. |
| `final-flat.patch` | The frozen flat implementation with explanatory comments and all three new regression tests/providers. |
| `scalar.patch` | The final flat implementation plus scalar AST execution projections and indexed reads of child expressions/statements/methods. |

Each overlay includes every earlier change and applies independently to the same
baseline. Apply exactly one. Initial binaries named `env`, `split-clean`, `calls`,
and `flat` remain immutable for mechanism comparisons. `final-flat` and `scalar`
are the two fully qualified source snapshots.

## Why these carriers matter

The baseline Interpreter owns Program, Runtime, and Output together. Its recursive
functions extract Runtime/Output into temporary records, call a mutable helper,
and write the record back, at 59 source sites. Program contains four managed
lists; Runtime contains the object array, stacks, roots, tables, and collector
state. Separating immutable Program, then passing Runtime/Output as named `mut`
parameters, lets execution avoid those large record carriers without changing
the rule that a `mut` call argument must be a named mutable variable.

The reference Rust evaluator borrows `&Stmt`/`&Expr` and holds `&mut Runtime` and
`&mut Output`; Go likewise holds pointers to Runtime/Output and reads the AST.
The mylang source now expresses that separation within its existing value and
mutation semantics. It keeps its indexed AST and explicit value stack.

Token is not scalar: its `message` is managed bytes. The scalar arm projects only
operator kinds, diagnostic lines, object references, values, and child indices
from AST nodes. Recursive execution never owns a Token or an AST child list.
Program remains the immutable owner and native root of those arrays. Runtime's
permanent roots still retain interned AST names and literals for the Lox collector.
No AST transformation, dispatch cache, NaN boxing, or superinstruction is added.

Environment slot updates retain the original COW behavior. The new snapshot test
holds both a whole Runtime snapshot and an EnvObj payload snapshot across a live
slot update. Preparing parameter slots before `heap.allocate` leaves the callee,
arguments, and enclosing environment rooted at the same allocation/collection
point, and publishes an environment of exactly the same size and cost.

## Correctness evidence

Both final sources contain all original 72 public tests plus one environment
snapshot test and two driver tests. The driver tests cover callee selection before
allocating arguments, captured parameter updates shared between closures, nested
printing, early returns and scope restoration, constructors, bound methods, and
native calls. Their provider entries keep Clock behavior deterministic.

Each source passes 75/75 tests under LLVM `--release` and QBE
`--mode ReleaseFast`, with RC and separately with native `--gc-stress`: 600 passed
tests total. Those are the actual unit-test mode arguments; the explicit O3/full
LTO flags below describe release guest artifacts.

`validation.json.gz` records 2712 exact output/diagnostic/collector-stat
observations across all five initial RC arms and final-flat RC/GC. It includes all
13 smoke scripts on VM/tree, 14 focused regressions, and 23 historical runtime
errors per engine, with ordinary and Lox-stressed execution. Native final-flat GC
stress additionally covers closures/properties smoke and every focused regression
and diagnostic. Its 88 remaining native-stressed corpus observations are explicitly
unrun.

`validation-scalar-gc.json.gz` records 296 more exact observations for the separate
scalar GC artifacts: every focused regression and historical diagnostic, both
engines, both backends, and ordinary/Lox stress while native GC is stressed. Its
104 native-stressed smoke observations are explicitly unrun to bound the matrix.
The scalar RC artifacts already cover the full 13-script smoke corpus in the first
receipt. In every observed comparison, allocations, collections, freed, and live
Lox objects equal the unchanged control exactly.

`receipts.json` contains complete compiler/runtime/binary/module hashes, build and
test commands, exact patch replay checks, and compressed receipt hashes. Replay
of either final overlay matches all 26 modules and the provider file exactly.
No local timing or performance counters were collected in this lane.

## Reproduce

Use a baseline checkout at **`fd86729e`**, not a later optimized migration that
already includes these overlays. In that checkout, reconstruct a private source:

```sh
docs/audits/d9-stage3d-migrations/apply-lox.sh "$scratch/control" --optimized
cp -a "$scratch/control" "$scratch/scalar"
patch -d "$scratch/scalar/lox" -p1 -i "$experiment/scalar.patch"
python3 "$experiment/build.py" --work "$scratch" \
  --source "$scratch/scalar/lox/benchmarks/lox/ports/mylang" \
  --compiler "$frozen_compiler" --name scalar --runtime rc
python3 "$experiment/build.py" --work "$scratch" \
  --source "$scratch/scalar/lox/benchmarks/lox/ports/mylang" \
  --compiler "$frozen_compiler" --name scalar --runtime gc
```

`build.py` refuses to overwrite binaries and records source hashes before/after
each build. It uses private cache/output/TMPDIR paths and `scripts/build-slot.sh`.
LLVM guests use `--llvm-opt 3 --lto`; QBE uses its default optimization. Both
preserve symbols and all semantic/budget checks.

For correctness comparisons, `validate.py` consumes a manifest mapping executable
names to paths, including `control-llvm` and `control-qbe`. Runtime GC artifacts
must include `-gc-` in their names. They run with `MYLANG_OPTIONS=--gc-stress`;
the Lox collector is independently stressed by the guest `--gc-stress` flag.
Native-stressed smoke cases require an explicit `--native-cases` selection;
focused regressions and historical diagnostics always run. The recipes and each
actual executable invocation are retained in the receipts.

The rejected direct-record-field experiment failed with `E_MUTATION_MARKER`.
The checker was left unchanged; flat named parameters provide the legal source
alternative. An initial split arm with an unnecessary Program parameter was
replaced by `split-clean` before screening and is not a qualified candidate.
