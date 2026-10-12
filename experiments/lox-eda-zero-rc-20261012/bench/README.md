# Full application benchmark evidence

Primary historical receipts: fs-x-20261009/results/lox-runtime.json.gz (13 scripts × tree/VM, three rounds) and eda-runtime.json.gz (34 stage-1 designs, ten rounds). historical.json preserves their summaries and hashes. Their compiler versions differ from this experiment and must be labeled historical.

The specs use 26 full Lox cells, 34 EDA design-to-output cells, and a separately identified older vm-step dispatch workload. Lox substitutes the canonical engine-specific sizes.json first-line N and checks stdout against its stored oracle. EDA checks every emitted filename and byte against its golden directory. Full EDA stage-1 schematic rendering, the separate sexpr-port reader/printer, and expanded/lox_eval bytecode subset are distinct workloads.

All four competitor release artifacts survive at the historical build paths. inventory.json hashes their current bytes. The embedded Lox Go revision postdates the fs-x receipt, so path identity cannot attest identical historical binary bytes. Current source fingerprints and surviving executable fingerprints are recorded separately. Fresh execution of these existing binaries differs from rebuilding them. Go Lox implements both VM and tree engines explicitly in ports/go/cmd/lox/main.go. The current Go toolchain is ~/.local/bin/go, linked to ~/.local/opt/go1.27.0/bin/go.

Run measure.py SPEC OUTPUT through scripts/build-slot.sh timing after sourcing ~/.config/mylang/dev-env.sh. Defaults: two warmups, nine alternating forward/reverse arm rounds, three separate GNU-time RSS rounds. Runtime uses uninstrumented children. Peak RSS comes from /usr/bin/time around the executable, avoiding the Python launcher's inherited high-water mark. Input/binary hashes are checked before and after; queue wait is outside every sample.

Split long cells with --round-start, --rounds, --warmups, --rss-rounds: retain two total warmups, rounds 0–8 once, and three RSS samples per arm. Every chunk writes a new receipt and completes children before relinquishing its lease. No nested admission or historical report edits.

Add current original-source ordinary RC controls and ownership candidates only after exact source/build manifests and qualification exist. An admitted migrated-source ordinary RC control helps attribute migration costs. Allocation, cumulative bytes, managed peak, exit-live and retain/release counters are separate instrumented runs; they are not process RSS.

Wall samples measure the whole CLI invocation, including process launch and startup. This is material for millisecond EDA cells; their spread is reported and isolated tiny-cell changes should not establish a speedup claim. A progress JSONL file persists each successful oracle/warmup/runtime/RSS child before subsequent children run, preserving completed work if a later child fails.

The final aggregator requires the exact 60-cell manifest (13 tree, 13 VM, 34 EDA), the same complete arm set in every cell, and all four competitor names. The extra historical VM step workload is a separate receipt and excluded from the full-matrix aggregation.

Each guest has a recorded configurable deadline (default 120 seconds). Timeout kills its isolated process group, including any GNU-time wrapper child, and records a censored failure in the progress journal. The exact-coverage aggregator refuses to silently omit such cells.

run-counted.py executes one separately counted run per named mylang arm per cell, validates its output against the same oracle, and preserves the complete counters-v1 JSON. Its summary exposes allocations/reallocations, cumulative allocated bytes (allocation bytes plus realloc added bytes), managed peak/exit-live bytes, and separate compiler/runtime retain/release events. Those instrumented invocations supply no runtime or RSS comparison samples.
