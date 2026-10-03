# Lox VM source improvements, 2026-10-03

`vm.patch` is an overlay on the canonical `apply-lox.sh --optimized` port at
`fd86729e`. It retains the pinned Lox benchmark's architecture, algorithms,
object layouts, bytecode, dispatch and collector. It adds no inline cache,
special instruction, unchecked access, capacity change or runtime opt-out.
The original migration script and canonical patch are unchanged.

The patch shortens aggregate lifetimes around operand reads, retains the
current activation's scalar frame index, reads closure arity through one
scalar helper, and reads each visited open-upvalue node once. Every ordinary
index, integer operation, object tag assertion and COW write still uses the
checked compiler/runtime implementation. Three new regressions exercise
runtime snapshots, block/return upvalue closure with Lox GC stress, and exact
error traces after child activations return. Each new driver test has an
explicit Clock provider fixture.

## Why the source changes preserve behavior

`read_byte` changes only `ExecFrame.ip`. Reading its scalar result before
indexing `constants`, `upvalues` or the runtime stack avoids retaining a
collection across a mutable frame argument. It does not change the contents
or identity of those collections. The local assignment reads its scalar
value before writing the destination slot; the same normal checked indexed
write performs the store. The unchanged Lox compiler emits all operands.

`run` executes exactly one activation. At entry, its frame is at
`activation_count - 1`. Native calls leave that activation count unchanged;
successful child calls return to it before dispatch continues. Errors return
and reset/unwind immediately. Consequently, the retained scalar `frame_index`
selects exactly the same runtime frame for every error-IP publication. IP
publication remains at the existing boundaries, including after call operands
are decoded and before allocating/error-producing handlers run.

`closure_arity` checks the closure tag, obtains its function reference and
checks the function tag before returning the integer arity. The assertions
and indexed accesses match `function_arity(closure_function(...))`; no whole
closure/function carrier leaves the helper. A snapshot regression retains a
Runtime, updates its function object and verifies both old and new arities.

The open-upvalue list remains sorted by descending stack slot. Capture walks
the same nodes and returns an existing equal slot or inserts in the same
position. Close reads the same stack value, stores the closed upvalue into
the same object slot, then advances the root list in the same order. No Lox
allocation or mutation occurs between the repeated reads replaced by one
plain `UpvalueObj` view. Values and references in that view are scalars; root
publication and the allocating insertion path remain unchanged.

## Diagnostic results and rejected experiment

These are retired-instruction diagnostics on CPU 14, **not accepted wall
timings or a Rust/Go parity claim**. Root owns central timing/perf CPUs
2/3/10/11. The frozen compiler is
`/home/epentland/ai/canopy/mylang-worktrees/codex-lox-perf-audit-20261002/zig-out/bin/mylang`
(SHA256 `45d05b554849bf3c12553549d9138556ba0204f9d59ba3aaa2ecb2327eb39ac4`).
LLVM builds use O3/full LTO; both backends use checked RC and retained symbols.

| Variant | LLVM instruction ratio | QBE instruction ratio | Coverage |
| --- | ---: | ---: | --- |
| Rejected v1: flatten mutable ExecFrame IP | 1.026910 | 1.448145 | 156 samples |
| v2: operand shaping + activation index | 0.993287 | 0.939706 | 156 samples |
| v3: v2 + arity/upvalue reads (`vm.patch`) | 0.993485 | 0.937453 | 234 samples |

Ratios are geometric means of per-case median-three instructions relative
to the same `fd86729e` control. Each run covers all 13 VM cases at the pinned
`tree` sizes, with interleaved arms and exact expected stdout/status checks.
v3 also includes v2 arms for attribution: its incremental ratio is 1.000200
LLVM and 0.997603 QBE. The LLVM equality case regresses to 1.002459 in v2/v3;
all cases and negative observations are retained in `diagnostics.json`.
Each version also passed 104 smoke checks across VM/tree and both backends,
with exact stdout and equal allocations/collections/freed/live statistics.

`rejected-v1.patch` preserves the failed flattening experiment and `v2.patch`
preserves its narrower successor. The former is negative evidence and must
not be applied together with `vm.patch`. v2 is an alternate source overlay;
the final patch includes its changes plus v3 and the regressions.

Raw sources, binaries, manifests, commands, stdout/logs and samples are in
`.tmp-lox-parity-vm` in the lane worktree. `rejected-v1/MANIFEST.sha256` seals
the rejected source/binaries/receipts. The measured v1/v2/v3 directories and
guests were never edited during or after measurements. Final tests live in a
separate `final` copy; its production `vm.my`/`heap.my` exactly match v3.

## Reproduce the overlay, builds and qualification

Run from this worktree, using a new private scratch directory:

```bash
work="$PWD/.tmp-lox-parity-vm-replay"
compiler=/home/epentland/ai/canopy/mylang-worktrees/codex-lox-perf-audit-20261002/zig-out/bin/mylang
bash docs/audits/d9-stage3d-migrations/apply-lox.sh "$work/source" --optimized
port="$work/source/lox/benchmarks/lox/ports/mylang"
patch --fuzz=0 --batch -p1 -d "$port" -i "$PWD/experiments/lox-parity-vm-20261003/vm.patch"
mkdir -p "$work/tmp" "$work/bin"
for backend in llvm qbe; do
  options=()
  if [ "$backend" = llvm ]; then options=(--llvm-opt 3 --lto); fi
  for runtime in rc gc; do
    TMPDIR="$work/tmp" scripts/build-slot.sh build "$compiler" build "$port/main.my" \
      --project --backend "$backend" "--$runtime-runtime" --keep-symbols \
      --cache-dir "$work/cache-$backend-$runtime" -o "$work/bin/$backend-$runtime" "${options[@]}"
  done
done
python3 experiments/lox-parity-vm-20261003/qualify.py --source "$port" \
  --compiler "$compiler" --work "$work/qualification"
```

`qualify.py` runs all nine test modules and asserts exactly 75 fresh passes
per flavor, zero cached/skipped/failed tests and exact loaded test names.
Its flavors are QBE Debug/default checked RC, LLVM `--release`/default checked
RC, then each again with native tracing GC `--gc-stress`. Stress selects GC
when no runtime flag is supplied. Each test also retains its existing Lox
collector stress setting. The 1B step allowance follows the joined port's
qualification recipe, including its full-capacity stack and stress tests.
All four flavors passed: **300/300**. Every source, fixture and compiler hash
remained equal at completion. Separate native GC LLVM O3/LTO and QBE guests
also built; their paths/hashes and exact commands are in `validation.json`.
Those guests passed 64 baseline/candidate probe runs covering both backends,
VM/tree, native GC stress on/off and Lox GC stress on/off. Status, stdout,
stderr and Lox collector statistics matched exactly for open/closed upvalues
and the error after child returns. The corrected rerun explicitly supplies
`MYLANG_OPTIONS=--gc-stress` for native stress and is preserved in
`corrected-gc-probes.json`. The initial `gc-probes.json` mistakenly set
`MYLANG_GC_STRESS`, which the runtime ignores; that receipt remains immutable
but is excluded from native-stress claims. The 300/312 unit-suite CLI stress
claims are unaffected: their `--gc-stress` option propagates through the
native test launcher.

For the original counter recipe, the private measurement work contains
`binaries.json`, `tmp/`, and `reference` pointing to the pinned audited Lox
checkout. The checked-in audit harness generates inputs and verifies their
hashes and every binary hash at completion:

```bash
python3 experiments/lox-performance-audit-20261002/audit.py check \
  --work .tmp-lox-parity-vm/v3-measurements --out .tmp-lox-parity-vm/v3-measurements/check.json \
  --arms baseline-llvm,baseline-qbe,candidate-llvm,candidate-qbe \
  --engines vm,tree --tier smoke --rounds 1 --cpu 14 --stats
python3 experiments/lox-performance-audit-20261002/audit.py counters \
  --work .tmp-lox-parity-vm/v3-measurements --out .tmp-lox-parity-vm/v3-measurements/counters.json \
  --arms baseline-llvm,baseline-qbe,v2-llvm,v2-qbe,candidate-llvm,candidate-qbe \
  --engines vm --tier tree --rounds 3 --cpu 14
```

Use fresh output paths for a rerun so the sealed original receipts remain
unchanged. `validation.json` records final-source/fixture hashes, all build
argv and artifacts, and complete suite summaries. The original
`overlay-replay.json` checks all 30 final port files against a clean canonical
port with this patch applied with zero fuzz.

## Positive compiler end-to-end validation

The immutable root `joined-flat` source combines this VM patch with the flat
tree source lane. Its 37 source/metadata files and root JSON/patch hashes
remained equal before and after validation. This run uses the positive-only
ReleaseFast compiler with SHA256
`da94c579e03ffaab2e9d43a6d9119b529bbb01dab5085e7a3986a6ecd98912c6`,
compared against the original frozen checked RC controls. Root built the RC
guests; this lane separately built LLVM O3/full LTO and QBE GC guests.

The existing tree-lane `validate.py` passed **1,144 candidate observations**
with exact status, stdout, full stderr and all four Lox collector statistics.
Both backends and both engines run with Lox stress off/on. RC and ordinary GC
run all 13 smoke cases, 15 focused regression programs and 23 historical
errors per engine. Native GC stress runs all focused programs/errors and
the bounded smoke cases `closures`, `instantiation` and `properties`.
Another 24 candidate/control comparisons verify the exact error after child
returns, across all applicable runtime settings. Eight representative RC
native-stress requests refuse with the same exit 2 and `--gc-runtime`
diagnostic as the controls; these are refusal checks, not GC program passes.

Exactly 80 native-stress smoke cells remain intentionally unrun:
`binary_trees`, `equality`, `fib`, `invocation`, `method_call`,
`string_equality`, `strings`, `trees`, `zoo`, `zoo_batch`, each under
LLVM/QBE, VM/tree and Lox stress off/on. Native stress with RC is unsupported;
the runtime refuses it before `main`. The earlier 312 fresh public-test
passes used the frozen compiler; this positive-compiler matrix is a separate
end-to-end validation and does not claim a positive-compiler public-suite run.

`positive-validation.json` records exact build/validation argv, all source
hashes, executable and linked runtime archive hashes, matrix counts and the
unrun cells. `positive-validation-observations.json.gz` retains every observed
output/diagnostic/statistic and candidate/control argv/environment. Separate
return-error and RC-refusal receipts are retained alongside it. Native stress
uses `MYLANG_OPTIONS=--gc-stress`; Lox stress is the executable's independent
`--gc-stress` argument. The private workspace is
`.tmp-lox-parity-vm/positive-joined-validation`.
