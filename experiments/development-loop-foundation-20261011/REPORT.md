# Development loop foundation qualification

The first parallel development-loop batch passes complete and unchanged-warm
verification at source commit `06a840ca9976e1259279125b6cee9b07a4c2fb76` on
`codex/selka-development-loop-foundation-20261011`. This qualifies the DL1 reporting
foundation, DL2 optional command deadlines and first DL3 Juice dependency boundary;
it does not complete all acceptance criteria of DL1–DL3.

The existing retained-session driver ran twice with the pinned
`0.17.0-dev.1683+5ceec001b` toolchain. Both requests and the session stop returned 0.
The inventory accounts for all 91 required actions in 44 groups, with no unknown
actions. The first request missed coordinator receipts but retained Zig/native build
artifacts: it was not a cold bootstrap. These are operational observations on a
shared machine, not isolated before/after latency or p95 measurements.

| Observation | First request | Unchanged request |
| --- | ---: | ---: |
| Reused groups | 0 | 33 |
| Selected groups | 44 | 11 |
| Build admission held | 1.758 s | 0 s |
| Gate admission held | 611.107 s | 24.393 s |
| Coordinator elapsed excluding queues | 624.148 s | 27.309 s |
| Coordinator elapsed including queues | 745.184 s | 27.581 s |
| Files hashed | 28,539 | 0 |
| Directories enumerated | 2,261 | 0 |

The complete test and formatting graph passed all 130 steps and 2,748 native tests.
The 24,819 native skips reported by the sharded binaries are excluded tests from
other shards, not omitted required coverage. Tooling passed too, including 55
coordinator tests, 28 process-supervision tests and 11 diagnostic-report tests.
The reviewed Juice partition ran 29 pure tests and nine native Runner tests; the
pure group reused its evidence on the unchanged request. The 11 freshness-required
groups still executed. Source validation remained stable for both requests.

Focused private admission checks passed all 13 tests. Readiness handshakes were
also checked with bytecode caching disabled and execution pinned to one CPU. Full
qualification caught and led to fixes for two integration boundaries: the admission
memory-settle helper must retain independent ownership, and timeout tests must
establish their fixture before starting a short execution budget. Supervision also
allows up to two seconds of normal background cache cleanup, counted within any
execution deadline; cancellation interrupts this drain. Timeouts, cancellation and
incomplete work never publish successful receipts. Hard deadlines remain opt-in.

To reproduce from the repository root, create an on-disk temporary directory and
run the existing driver; it owns admission through the coordinator:

```sh
mkdir -p .tmp/development-loop
ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache" \
ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache \
TMPDIR="$PWD/.tmp/development-loop" PYTHONPYCACHEPREFIX=/dev/null \
python3 -B experiments/cache-wave11-20261011/qualify_session.py \
  --zig /home/epentland/.local/bin/zig \
  --output /home/epentland/ai/canopy/.selka-agent-cache/selka-development-loop-20261011
```

[Cold report](verification-cold.json), [warm report](verification-warm.json),
[session result](session-summary.json) and [combined raw output](session-verification.log)
are archived beside this report with SHA-256 checksums. Log paths inside the JSON
refer to mutable working captures; use this archived combined output for history.
The subsequent evidence-only commit does not change the qualified implementation.

Per-test/action timing, calibrated action budgets, the complete edit matrix,
independent native test roots and narrower producer identities remain future work.
The self-hosting branch `codex/selka-bootstrap-20261011` continues to own compiler
porting. See the [plan](../../docs/audits/selka-development-loop-plan-2026-10-11.md),
[implementation notes](../../docs/tooling/development-loop.md) and
[bootstrap handoff](../../docs/audits/selka-development-loop-bootstrap-handoff-2026-10-11.md).
