# Per-function cost

`mylang cost ENTRY.my [FUNCTION]` runs the same reachable Core construction and
release passes as `mylang build ENTRY.my --release --stats`, then compiles the
identical emitted LLVM units to capture optimization remarks. It does not link
or execute the program.
It writes one row per emitted function and a total. `FUNCTION` is an exact Core
name or its unqualified name; matching specializations remain separate rows. An
unknown or unreachable name exits 2. `--json` writes a `cost-v1` document with
`functions` and `totals`. Filtering also filters the total.

```bash
mylang cost program.my
mylang cost program.my work --json
mylang cost program.my --debug
mylang cost program.my --verify-facts
```

The counts describe static sites, not executions, bytes, timings or instruction
counts. They belong to the physical emitted body: costs introduced by inlining
are attributed to the caller. Internal callees have separate rows, so allocation
counts do not double-count a call and its callee. Unreachable blocks proved by
release facts contribute no kept checks or allocation sites.

| Field | Meaning |
|---|---|
| `checks.kept` | Check-bearing Core instructions still checked at run time; verify builds include checks re-emitted to validate proofs |
| `checks.proved` | Proof events recorded by the fact passes, including proofs after loop versioning |
| `updates.in_place`, `updates.tested`, `updates.copied` | Ownership decisions: proved unique, run-time uniqueness branch, or unconditional copy |
| `allocation.sites` | Sites that may allocate heap or runtime scratch memory; growth and conditional copies count even when an execution does not allocate |
| `allocation.unresolved_calls` | Subset of allocation sites with a foreign or unresolved function target |
| `rc.retains`, `rc.releases` | RC operations inserted by ownership, after paired operations are elided |
| `inlined_calls` | Calls expanded by the Core inliner, excluding later LLVM inlining |
| `loops.vector_plans` | Loops given a Core vector emission plan; `--stats`'s legacy `vectorized` count has this meaning |
| `llvm_vectorized_loops` | Positive LLVM loop-vectorization remarks; `null` when no positive evidence is available |
| `loops.unknown` | Core loops whose LLVM outcome is unclassified; remains conservative when LLVM transforms loop structure |
| `loops.unswitched`, `loops.versioned`, `rc.elided_pairs`, `rc.stack_lists` | The corresponding optimization and ownership events also printed by `--stats` |

`--debug`, `--no-facts` and `--verify-facts` select the same passes as those build
modes; the default is release with trusted facts. The verifier's extra fact
assertions are not optimization proof events.

## LLVM remarks

Core vector plans do not establish that LLVM vectorized another loop. Cost and
`build --stats` request YAML with `-fsave-optimization-record` and an explicit
`-foptimization-record-file` from `zig cc`, using the build's exact target, CPU,
optimization flags and emitted units. The compiler records each remark compile's
wall time on stderr. The remark objects never replace build objects or enter the
link. Unsupported flags, failed collection and missing records leave the outcome
unknown. To read saved records for this exact module instead, use
`--llvm-remarks FILE.opt.yaml`.

Only successful `loop-vectorize` / `Vectorized` remarks whose `Function` matches
a reported Core name contribute to `llvm_vectorized_loops`. Missing, missed and
unrelated remarks leave the outcome unknown. `my.` is the emitter's symbol prefix
and is removed before matching. Remaining source loops stay unclassified because
LLVM can clone, inline or eliminate them. Debug's content-named synthetic helpers
may therefore remain unknown even when LLVM supplies a helper remark.

Capture currently recompiles the requested units to obtain fresh matched remarks.
It has no persisted remark cache; repeated collection cannot serve stale evidence.
Ordinary builds without `--stats` do not request this additional compile.

## The allocation definition

`src/core/cost.zig` exports the instruction-level allocation classification used
by this report and the build-time allocation promise. Stack-promoted lists and
allocation-free borrow/identity helpers do not allocate. Managed construction,
materialization, copy, growth, dictionary deletion bitmaps, stable sorting
scratch, compound-key lookup scratch, and other potentially allocating runtime helpers do. Runtime helpers
have an explicit audited allocation-free allowlist; an unknown helper is
conservative. Foreign and unresolved function-value calls may allocate.

A whole-program allocation check must visit every internal callee and every path,
including cold error paths. It runs before release optimization, after debug
ownership exposes conditional and unconditional copy-on-write allocations. This
prevents release-only stack promotion or unreachable-code proof from satisfying
an allocation promise that fails in debug builds. The report itself describes
the chosen optimized build, which may eliminate those sites.

## Costs alongside interfaces

`mylang list-interfaces ENTRY.my --cost` prints the ordinary public declaration
listing followed by the exact release `cost-v1` report from `mylang cost ENTRY.my`.
It is mutually exclusive with `--contracts`, which emits a JSON manifest. The
cost rows describe the entry's reachable emitted functions, including private functions and specializations; an uncalled
public declaration has no emitted cost row. Totals sum those emitted rows.

The option checks bodies and requires an executable entry. A body or Core error
fails the command before it prints a partial listing. Without `--cost`, the
existing declaration listing and its handling of bodies are unchanged. Use
`mylang cost` directly for JSON, function selection and alternative build modes.
