# LLVM generated-ownership-helper inlining investigation

The forced `noinline` hypothesis is rejected for the exact profiled
positive-compiler/joined-flat Lox LLVM artifact. An unchanged fresh-cache build
with `MYLANG_LLVM_DUMP` is byte-for-byte identical to the reference binary:
`d5d02bcc5c232d3dd325dfda2510787759cbba8d3e149aeb0d2e71b9b89ae12d`.
Compiler and all source-module hashes also match the root build record.

All 417 lowered QBE functions are exported. None of their LLVM modules contains
a function-definition or call-site `noinline` attribute. The largest `dbgloc`
position is 1627, within the 16-bit pseudo-probe range.

| Generated C ownership call | Static call sites | With `noinline` |
| --- | ---: | ---: |
| loan | 220 | 0 |
| retain | 482 | 0 |
| drop | 5337 | 0 |
| unloan | 5256 | 0 |
| take | 962 | 0 |
| publish | 84 | 0 |
| list_append | 53 | 0 |
| list_set | 43 | 0 |

These are static IR counts, not runtime ownership counts or performance
measurements. No source algorithms, workload sizes, checks, or compiler behavior
were changed. No new timing/counter run is needed to reject a branch that never
executes in the identical artifact.

The hot `myl_t_<hash>_rcg_*` symbols originate in generated C from
`src/rc_glue.zig`, compiled in the program's metadata unit. They are not QBE
function definitions processed by `qbe_build_llvm_lower.function`, so its
`!own.exported` rule cannot mark those definitions. Their actual lowered calls
already allow LLVM full-LTO inlining and retain `nomerge`/debug metadata.

`FrameMap.positionCalls` adds call-site `noinline` only at unprobed locations;
`FrameMap.attributes` preserves a containing function when positions exceed the
pseudo-probe representation. Neither rule fires here. These rules remain necessary
for other programs: the assembly frame-map reader requires a valid inlining probe
chain, and an unprobed `.loc` must belong to the physical function containing the
call. Removing those constraints could lose user frames and trap positions.

A generated glue symbol alone is also insufficient as a noncollecting leaf
certificate. Retain/loan/publish/take have semantic runtime slow paths for arenas,
pins, count saturation, and overlapping transfers; drop/unloan can drain and
finalize values. The two scoped LLVM files contain no authoritative type-shape or
runtime-effect summaries that would justify relaxing those safeguards.

The remaining ownership work is worth investigating through ownership-event
elimination, emitted glue size, and LLVM's normal inliner cost decisions. Broadly
removing `noinline`, adding a name-only exception, or disabling tail/frame safety
attributes is not justified by this evidence. No compiler patch was made.

`receipt.json` contains hashes for the immutable compiler/source/binary and every
LLVM/SSA/signature dump, representative calls, and the exact build recipe. Reproduce
with the frozen compiler and identical joined-flat source identified there:

```sh
python3 experiments/lox-llvm-ownership-inline-20261003/investigate.py \
  --work "$scratch" --compiler "$frozen_compiler" --source "$joined_flat" \
  --reference "$profiled_binary" --out "$scratch/receipt.json"
```

The recipe uses `scripts/build-slot.sh`, a fresh private object cache, private
output/TMPDIR, LLVM O3/full LTO, RC runtime, and all original semantic/budget checks.
