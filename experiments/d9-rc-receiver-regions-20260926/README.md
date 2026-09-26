# Receiver allocation-region replay

`grow.my` and `stash.my` are exact golden sources. `probe.json` records the RC
before/after builds, runs, SHA-256 identities, manifest backend fields and full
ownership counters. `gc-reference.json` records GC executions of the same sources
with the joined before compiler. `measured-driver.my` preserves the exact bytes
used by the counted eight-test driver; the checked-in guest fixture later had
two excess blank lines removed.

`probe.py` records the private two-install reproduction workflow. Install paths
are `.tmp-rc/profile/install-publish-joined` and `install-arena-origin`; both are
Debug compiler installations made through `scripts/build-slot.sh build`. Run the
probe itself through that build slot. Guest LLVM builds use `--release`; the
recorded manifests were checked independently after execution.

Compressed JSON preserves all 8 arena cases in four mode/backend combinations,
75 affected RC cases per backend, and the prior constructor/iteration overlap
check (15 aggregate plus 7 iteration cases per backend). No failed or skipped
case is hidden in those summaries. The runtime C sanitizer suites and 45 focused
unit checks are described in the linked audit report.

See [the audit](../../docs/audits/d9-rc-receiver-regions-2026-09-26.md) for the
cause, correction and limits of this evidence.
