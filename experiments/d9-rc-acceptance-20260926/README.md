# D9 WP-4 matched runtime acceptance

`compare.py` prepares and measures private binaries for the accepted GC
implementation and the experimental RC implementation. It selects exactly 27
historical parity keys, three schematic inputs and 13 Lox VM scripts for each
backend. It imports the unchanged historical `pc.py` for guest build commands,
workload sizes, output validation and instruction counters. Guests use
ReleaseFast; LLVM uses optimization level 3 and full LTO. Both compilers must
be Debug builds.

The GC compiler is the accepted WP-4pre installation from `f6bea5d9`, with
SHA-256 `8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`.
The driver rejects a different GC executable rather than silently comparing
against the experimental runtime's GC path. RC builds explicitly pass
`--rc-runtime`; inherited `MYLANG_*` selection is removed by `pc.py`.

On this machine the frozen GC installation is
`../d9-physical-borrow-after-astra/.tmp-physical/install-accepted/bin/mylang`.
The compiler commit supplied to the driver is a provenance label; its content
hash, input hashes, exact commands and output checks are retained independently.
Use a freshly installed and frozen Debug compiler for the eventual RC side.

From this worktree, prepare an empty scratch directory and build each side:

```console
bash docs/audits/d9-stage3d-migrations/apply-lox.sh "$PWD/.tmp-rc-performance" --optimized
python3 experiments/d9-rc-acceptance-20260926/compare.py build gc --compiler "$GC_COMPILER" --compiler-commit f6bea5d9
python3 experiments/d9-rc-acceptance-20260926/compare.py build rc --compiler "$RC_COMPILER" --compiler-commit "$RC_COMMIT"
python3 experiments/d9-rc-acceptance-20260926/compare.py measure
```

The Lox preparation replays the pinned migration and source optimization
patches. A separate reconstruction was compared byte for byte with the accepted
stage-3 corpus: all 28 `.my` and `.json` files match. Both compilers consume this
same source tree. Each side owns 58 executables and its own object cache.
Builds use the repository's slot allocator; temporary files stay on disk under
`.tmp-rc-performance/tmp`.

Each measurement checks both outputs, verifies private binary hashes, then
alternates GC and RC order for three instruction-counter and three peak-RSS
runs pinned to CPU 2. Every run must exit successfully. The driver retains raw
observations and independently computes medians. Results are resumable only
when compiler, input, harness and private artifact identities still match.

For **each backend**, acceptance requires all 43 rows, instruction geomean
at most 1.0, no row above 1.3, and a lower median across the programs' median
peak RSS values. The stricter per-backend RSS interpretation avoids hiding a
regression on one backend in a combined median. Failed checks or thresholds
fail the driver; partial results never count as acceptance.

This harness does not establish RC correctness or acceptance by itself. The
full language/arena/legacy gates and actual borrow-inference count-traffic
comparison remain separate requirements.

## Prepared GC baseline

The first GC build is complete: all 58 private executables built and all 86
program/backend output checks passed. Every private executable was independently
rehashed after completion. [The compressed manifest](gc-builds.json.gz) retains
compiler, source, harness and binary identities plus exact build commands and
checks. These are baseline preparation results; RC instruction or RSS ratios
have not yet been measured. The manifest's source commit is `9f396a35`, and the
standalone harness is committed at `a5af97b6`.
