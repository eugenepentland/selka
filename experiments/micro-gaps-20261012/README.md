# Four measured performance gaps

Integration branch: `codex/micro-gaps-20261012`.
Base: `399013af36d41b78610e5ede22a9102ec5b17ffe`.
Four Sol6.1 workers ran concurrently in separate sibling worktrees. The dispatch,
file ownership, pinned baseline compiler and shared admission setup are recorded
in `coordinator/dispatch.json` and each worker's `handoff.md`.

This experiment targets dictionary string-key updates, word counting, owned keyed
record sorting and local text-encoding copies. It preserves benchmark sources and
checked ownership. Explicit copies that escape remain independent. Unsupported
ownership shapes remain refusals. This is not a claim that the earlier default
promotion or legacy runtime retirement milestones have been completed.

## Validation and measurement

Workers record focused IR/native tests, managed counters and Guardian checks.
The coordinator integrates the changes and runs the complete registered
verification coordinator on frozen inputs before freezing the measured compiler.
The final gate uses the exact checked-owned component pin/archive selected by the
previous successful gate; `coordinator/component-route.json` records both inputs.
The default historical seed remains unchanged. Its native-link failure on this
host is not repaired by changing immutable seed history.

`coordinator/build_candidate.py` builds all30 checked runtime/counted micro
artifacts from unchanged sources. It retains build logs and compiler/source/native
hashes, then derives91 new paired specs from the prior campaign. The existing
`experiments/micro-ownership-20261012/tools/schedule.py` and `measure.py` execute
these specs under exclusive shared timing admission on allowed CPU8. The two arms
are frozen baseline checked ownership and the integrated candidate. Both run
again on this host, with2/3 warmup pairs,9/15 measured pairs and3 RSS probes per
arm. Counted runs are separate from timing and RSS. Kernel calibration follows
the existing bounded policy; raw limited pilots remain visible.

`coordinator/report.py` validates independent checksums, all rounds, immutable
artifact hashes, zero RC/uniqueness events and zero managed exit-live bytes. It
reports paired bootstrap intervals, traffic, managed peak and process RSS
separately. Known legacy retain/release native symbols are audited separately.
Raw sorting scratch is native storage and is not part of managed counters.

The prior foreign-language and RC receipts remain unchanged historical context;
they are not substituted for paired controls in this campaign. Compilation logs
include queue wait and are not compiler throughput measurements.

Final status and performance results will be recorded after the combined gate
and paired campaign finish. Worker-only results are not final integration proof.
