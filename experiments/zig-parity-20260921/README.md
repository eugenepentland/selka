# Zig S-expression parity comparators

See the [results report](../../docs/audits/llvm-zig-benchmark-2026-09-21.md).
Fresh LLVM O3 is 1.98–3.16× Zig ReleaseFast elapsed time on the four matched
workloads. LTO changes little. `measurements.json` contains every timing sample
and round order; `memory.json` contains separate maximum-RSS samples;
`qualification.json` contains all 136 auxiliary correctness runs.

The primary `ReleaseFast` and secondary `ReleaseSafe` comparators were built
fresh from `experiments/sexpr-port/zig-bench` with Zig
`0.17.0-dev.1683+5ceec001b`. Both use Zig's native default target with no
explicit CPU feature override, matching the target policy used by the mylang
LLVM adapter builds.

The source closure is byte-identical to the read-only sibling EDA checkout at
revision `2a8d901174255ff8fa3e4840acd35a041e39c9a8`. Both artifacts reproduce
the expected 15,105-node and 120,840-node census results and identical width-72
render hashes. Exact hashes, build commands, inputs and outputs are recorded in
`zig-provenance.json`.

Artifacts:

- `.tmp/zig-parity-20260921/install/bin/zig-bench` — ReleaseFast primary
- `.tmp/zig-parity-20260921/install-safe/bin/zig-bench` — ReleaseSafe secondary

These executables match the S-expression census and canonical printer
workloads. No Zig implementation matching the pilot's full three-input
schematic model, validation, placement, routing and SVG output contract was
found, so they must not be presented as full schematic SVG comparators.

## Reproduce

Run from the mylang repository root. Mylang builds use the current installed
compiler; `provenance.json` records its exact hash and the source hashes for this
run. Zig build commands and toolchain hashes are in `zig-provenance.json`.

```sh
mkdir -p .tmp/zig-parity-20260921
zig-out/bin/mylang build experiments/sexpr-port/main.my --project \
  --backend llvm --llvm-opt 3 --mode ReleaseFast --keep-symbols \
  --cache-dir .tmp/zig-parity-20260921/mylang-cache --report \
  -o .tmp/zig-parity-20260921/mylang-o3
zig-out/bin/mylang build experiments/sexpr-port/main.my --project \
  --backend llvm --llvm-opt 3 --lto --mode ReleaseFast --keep-symbols \
  --cache-dir .tmp/zig-parity-20260921/mylang-cache --report \
  -o .tmp/zig-parity-20260921/mylang-o3-lto

python3 experiments/zig-parity-20260921/qualify.py \
  --binary zig=.tmp/zig-parity-20260921/install/bin/zig-bench \
  --binary zig-safe=.tmp/zig-parity-20260921/install-safe/bin/zig-bench \
  --binary mylang-o3=.tmp/zig-parity-20260921/mylang-o3 \
  --binary mylang-o3-lto=.tmp/zig-parity-20260921/mylang-o3-lto \
  --json experiments/zig-parity-20260921/qualification.json

python3 experiments/llvm-backend/measure.py \
  --work .tmp/zig-parity-20260921/measure \
  --input .tmp/runtime-audit-20260919 \
  --rounds 31 --warmups 3 --cpu 6 --sink null --no-counters \
  --arms zig,zig-safe,mylang-o3,mylang-o3-lto \
  --binary zig=.tmp/zig-parity-20260921/install/bin/zig-bench \
  --binary zig-safe=.tmp/zig-parity-20260921/install-safe/bin/zig-bench \
  --binary mylang-o3=.tmp/zig-parity-20260921/mylang-o3 \
  --binary mylang-o3-lto=.tmp/zig-parity-20260921/mylang-o3-lto \
  --reference mylang-o3 \
  --json experiments/zig-parity-20260921/measurements.json
```

The retained inputs can be reconstructed exactly as
`input.sexp = (source_bytes + b'\n') * 5` and
`input8.sexp = input.sexp * 8`, using the source path and SHA-256 in
`provenance.json`. Stop builds before timing. Reusing the build cache is fine
for runtime measurements; compilation was not part of the timed interval.

Memory samples used `/usr/bin/time -f %M -o FILE taskset -c 6 BINARY INPUT`
(append `--render` for printing), redirecting stdout to `/dev/null`, five runs
per arm/mode. `%M` is maximum RSS in KiB on this Linux host. No Guardian gate was
exercised by these standalone benchmark builds or runs.
