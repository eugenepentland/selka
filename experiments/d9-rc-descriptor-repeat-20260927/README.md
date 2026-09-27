# Descriptor identity reuse: rejected global and retained private versions

See [the report](../../docs/audits/d9-rc-descriptor-repeat-2026-09-27.md) for the
proof, exact ratios, negative evidence and limits. This is an isolated Stage 4
optimization; it is not runtime acceptance.

`global/` preserves the rejected experiment that added a checked hint to every
descriptor lookup. `ready/` preserves the final version: only scalar append
readiness opts into the private query. Both use the same immutable joined d1d8
Debug control and unchanged workload inputs. The second experiment reuses the
first experiment's exact control binaries and takes fresh interleaved samples.
The candidate binaries are independently built; no source is patched in place
behind an immutable compiler or measured executable.

Verify each archive without rebuilding or executing guests:

```sh
python3 experiments/d9-rc-descriptor-repeat-20260927/global/verify.py
python3 experiments/d9-rc-descriptor-repeat-20260927/ready/verify.py
```

Each directory contains 32 binary records with native manifests, 72 raw production
observations, 24 exact counted runs, 20 paired guest rows, executed Python drivers,
source patch, sanitizer/source identity logs, layout probes and input hashes.
`final-svg-identity.json` records the final preserved output files; the executed
measurement driver verifies the expected SVG after every individual run.
`measurements.json.gz` includes only explicit MYLANG environment overrides;
inherited host environment values are not archived.

`global/verifier-initial.log.gz` is a preserved verifier bug: it treated the
inactive hybrid atom PMU's `<not counted>` row as a measurement failure. Both
current verifiers require 100% running for the pinned CPU-core instruction event.
All raw PMU rows remain unchanged. The final focused test exits 0 and passes 12/12
while Zig prints a misleading `failed command` diagnostic; that log is retained.

Private immutable compiler and guest paths, binary hashes, source identities,
exact build commands and QBE/LLVM O3/full-LTO manifests are in the receipts.
The drivers contain the executed private paths intentionally. Select fresh
scratch/install paths before reproducing a future experiment; never overwrite
these immutable artifacts. Root owns full joined gates and Guardian feedback.
