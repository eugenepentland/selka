# Zero-RC Stage 4: resource scopes and foreign contracts

This prototype extends `--experimental-zero-rc` with files, root providers and
lexically scoped dependent capabilities. All 25 candidate executions passed
across five pipelines, with zero observed RC and zero live managed bytes at exit.
Five packaged-compiler lifetime refusals also passed.

```python
import filesystem

func write(fs: Filesystem):
    with fs.dir("logs") as logs:
        with logs.open("one.txt", "w") as file:
            _ = file.write("saved")
```

The root provider is an ordinary owning local. A dependent capability or open
file borrows its parent for the whole `with` body. Scope exits consume and
close children while the parent is still passed as a borrowed argument to the
cleanup call. This works on fallthrough, return, error propagation, break and
continue without a general inference algorithm or named lifetimes.

A child cannot be returned or stored outside its scope. Bind a provider to a
named local before opening a dependent scope. Capability scopes accept `dir`,
`host`, `read_only` and `only`; the filesystem paths receive execution coverage
here. Root clock/entropy/environment providers also have direct cleanup; broader
standard-library coverage belongs to Stage 6.

Native providers have explicit contracts: call buffers are borrowed only for
that callback; successful acquisition transfers one handle; successful completion
consumes it; failed completion leaves it open; release consumes an uncompleted
handle. Scope cleanup calls completion once (or release for a read-only handle),
then destroys the language wrapper. Arbitrary C imports remain scalar-only. The
frontend rejects managed arguments and results, so it cannot accidentally pass
a guest owner to C. Retired copied Host adapters are not reintroduced.

The native fixture asserts exactly five completed handles, no fallback releases,
and no live handles after normal return, early return, propagated failure,
break and continue. Any duplicate close, closed-handle use or malformed borrowed
write buffer aborts it. A second native fixture asserts exactly one fallback
release for a read-only file. The memory filesystem sample exercises nested
read-only cleanup.

Implementation costs and limits:

- Dependent capabilities copy their scope bytes rather than sharing them.
- The initial `try` lowering copies managed payloads before dropping the source
  Result/Option. There is no retain; this can allocate on propagation paths.
- Resource-result boxes detach owned pointer fields before destruction.
- Read-only file scopes now release the handle without requiring completion
  permission. The frozen Stage 3 compiler traps on this case; its failed run is
  preserved separately, and no before/after memory comparison is made for it.
- Raw acquired handles stored in Results/containers, escaping derived
  capabilities, asynchronous foreign retention and managed C signatures remain
  unsupported. Unsupported paths refuse compilation, without RC fallback.
- Managed-block counters do not measure provider-internal mallocs, temporary
  callback buffers, filesystem storage or total process RSS.

`measure.py` runs every sample under the five established pipelines, checks
stdout, emitted LLVM, whole-program RC counters and live managed bytes at exit.
It compares supported prior behavior with the frozen Stage 3 compiler in its
ordinary RC mode. Baseline sources use ordinary dependent capability locals;
candidate sources replace those with explicit scopes. `boundaries.py` checks
five exact diagnostic refusals through the packaged compiler.

## Results

| Sample | RC baseline allocations → zero-RC | Peak managed bytes before → after | Runtime retains/releases before → after |
| --- | ---: | ---: | ---: |
| Early return | 7 → 7 | 416 → 416 | 3/5 → 0/0 |
| Scalar foreign call | 0 → 0 | 0 → 0 | 0/0 → 0/0 |
| Native scoped exits | 24 → 31 | 576 → 608 | 18/21 → 0/0 |
| Native read-only file | unavailable → 4 | unavailable → 352 | unavailable → 0/0 |
| Nested propagated error | unavailable → 22 | unavailable → 800 | unavailable → 0/0 |

The native scoped-exit case allocates 480 more cumulative managed bytes
(1,824 → 2,304) and peaks 32 bytes higher. Explicit scope/payload copies account
for this cost; removing RC does not by itself guarantee lower memory use.
The two unavailable baselines hit the old read-only cleanup bug, so their
candidate values are absolute measurements, not claimed improvements.

887 full Core tests and 27 frontend tests passed before final qualification.
The matrix then exposed an entry-provider cleanup still emitting RC; the final
candidate replaces it with direct destruction and passes a dedicated regression
in both unoptimized and optimized verifying builds. All 88 whole-tree Guardian
checks passed. The final candidate also includes the Stage 5 runtime extension,
which has separate task qualification; these measurements exercise resources.
See [validation.json](validation.json) for exact compiler and evidence hashes.

## Reproduce

From the prototype worktree, use the pinned Zig toolchain and the frozen candidate:

```sh
python3 experiments/zero-rc-resources-20261011/measure.py \
  --compiler .tmp/zero-rc-resources-20261011/candidate-final/bin/mylang \
  --before .tmp/zero-rc-containers-20261011/candidate-final/bin/mylang \
  --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig \
  --output .tmp/zero-rc-resources-20261011/reproduction
python3 experiments/zero-rc-resources-20261011/boundaries.py \
  --compiler .tmp/zero-rc-resources-20261011/candidate-final/bin/mylang \
  --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig \
  --output .tmp/zero-rc-resources-20261011/refusals-reproduction
```
