# Schematic LLVM O3 parity audit evidence — 2026-09-21

The initial audit below describes the retained **preimplementation** compiler.
The implementation and its verification are recorded separately in
[`schematic-llvm-o3-implementation-2026-09-21.md`](../../docs/audits/schematic-llvm-o3-implementation-2026-09-21.md).
Its evidence files are `implementation-*`, `combined-*`,
`backend-qualification.*`, and `dev-session-qualification.json`.
The implementation fixes the cache issue described by the original audit.

Read [the audit](../../docs/audits/schematic-llvm-o3-parity-2026-09-21.md).
These are diagnostic builds of the actual SVG guest, with ordinary collecting
GC, checks, step accounting and frame accounting retained. Production files
were not edited. The existing compiler was used, not rebuilt from the dirty
working tree. Its hash, source hashes and native runtime identity are recorded.

- `measurements.json`: 21 randomized interleaved rounds, three warmups, CPU 6;
  separate-function O3, whole-guest O3, and host bridge ablations.
- `lto-measurements.json`: a separate matched batch including runtime LTO and
  non-LTO controls. Do not subtract times across batches.
- `qualification.json`, `lto-qualification.json`: complete SVG equality, an
  independent geometry check, a changed-net input, malformed inputs, GC stress,
  instruction-budget and frame-budget failures.
- `phase-counts.json`: separately instrumented host calls per pipeline stage.
- `builds.json`, `lto-builds.json`: binary/source hashes and build provenance.
- `manifest-check.json`: every frozen-manifest function key matches the initial
  per-function O3 build. This catches accounting/other lowering differences.
- `cache-recheck.json`: changing only `MYLANG_QBE_LLVM_OPT` from O3 to O2 reused
  every O3 function object, demonstrating missing optimization-level identity.
- `source-inspection.json`: measured C object sizes and inspected source hashes.
- `counters.json`: hardware counters were unavailable (`perf_event_paranoid=4`).
  No system permissions were changed; these results are wall times, not cycles.

The timed interval includes child process startup, reading the three existing
input files, all guest work, writing SVG to a private file, and process shutdown.
It excludes the schematic host's compilation and input-copy work. Output checks
and clearing the issue file occur outside the timed interval. Every timed run
checks status, stdout, stderr, issue bytes and the entire SVG. No Zig renderer
was timed: this experiment measures mylang improvements, not a parity ratio.

`stack` uses eight zeroed stack nodes, with the original heap fallback. `prebind`
stores the seven validated bindings in execution-local state at initialization.
`both` combines them. Guest source is unchanged. These are prototypes: a general
implementation needs dynamically sized binding storage and the complete host
contract suite. The LTO pair compiles the same runtime, provider and generated
metadata C at O2, the same whole guest at O3, and links at O3 with/without `-flto`.
It retains the original native entry object. No roots or checks are removed.

Reproduce from the repository root with the pinned installed toolchain. CPU 6
must be available (or edit the harness affinity consistently). Binaries, C, IR,
manifests and receipts remain under `.tmp/schematic-parity-20260921/`:

```sh
mkdir -p .tmp/schematic-parity-20260921
MYLANG_QBE_LLVM_OPT=-O3 zig-out/bin/mylang build src/schematic/guest/main.my \
  --project --provider src/schematic/native_schematic.c \
  --qbe "$PWD/experiments/llvm-backend/qbe_llvm.py" \
  --cache-dir "$PWD/.tmp/schematic-parity-20260921/cache-o3" \
  --step-accounting --keep-symbols --report \
  -o "$PWD/.tmp/schematic-parity-20260921/unit-o3" \
  > .tmp/schematic-parity-20260921/build-o3.json

zig-out/bin/mylang emit-project-qbe src/schematic/guest/main.my --drop-debug \
  > .tmp/schematic-parity-20260921/manifest.json
zig run --dep outputs \
  -Mroot=experiments/schematic-parity-audit-20260921/metadata.zig \
  -Moutputs=src/qbe_build_outputs.zig -- .tmp/schematic-parity-20260921/manifest.json \
  > .tmp/schematic-parity-20260921/metadata.c

MYLANG_QBE_LLVM_OPT=-O3 zig-out/bin/mylang build src/schematic/guest/main.my \
  --project --provider src/schematic/native_schematic.c \
  --qbe "$PWD/experiments/llvm-backend/qbe_llvm.py" \
  --cache-dir "$PWD/.tmp/schematic-parity-20260921/cache-o3" \
  --manifest-file="$PWD/.tmp/schematic-parity-20260921/manifest.json" \
  --step-accounting --keep-symbols --report \
  -o "$PWD/.tmp/schematic-parity-20260921/manifest-check" \
  > .tmp/schematic-parity-20260921/manifest-check.json

python3 -B experiments/schematic-parity-audit-20260921/build_probes.py
python3 -B experiments/schematic-parity-audit-20260921/build_lto.py
python3 -B experiments/schematic-parity-audit-20260921/phase_counts.py
python3 -B experiments/schematic-parity-audit-20260921/measure.py
python3 -B experiments/schematic-parity-audit-20260921/measure.py --lto
```

Use a fresh cache when changing the adapter, its imported modules, flags or
toolchain. The driver currently stamps the adapter entry file rather than
hashing its dependencies and relevant environment. The cache demonstration can
be repeated by running the first command with O2, the same cache, and a different
output path, then inspecting compiled/reused counts and function keys.

An initial whole-module probe accidentally omitted frame accounting. The final
manifest was corrected and every reported timing batch rerun; the object-key
check and frame-budget differential now enforce matching. Only final matched
measurements are retained here. No project Guardian gate ran, so no Guardian
feedback entry was required.
