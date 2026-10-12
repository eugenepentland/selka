# A09 handoff — preparation checkpoint

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432`.
Owned files: this evidence directory and its measurement harness only.
No production changes, shared-file requests, or old reports overwritten.

Fresh complete C0 Debug installation built successfully at
`/home/epentland/ai/canopy/mylang-memory-20261012-A09/.tmp/memory-closeout/A09/C0`.
Compiler SHA-256:
`324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
All six installed files and package manifests are pinned in
`C0-installation.json`; raw build output is `C0-build.log`.
Installation is frozen and shared read-only with all ten workers.

Build command, run with the shared environment sourced:

```sh
scripts/build-slot.sh build "$ZIG" build \
  -p "$PWD/.tmp/memory-closeout/A09/C0" \
  -j"$MYLANG_DEV_JOBS" --maxrss "$MYLANG_DEV_MAXRSS"
```

Build passed Guardian's 88 diff-scoped checks and exited zero. This is not
complete final verification. The harness passes CLI, output/exit validation,
per-process wait4 usage and timeout smoke checks. Guest baseline timing builds
are queued. No before/after timing or memory improvement is claimed yet.

`manifest.json` pins nine initial guest cases: enlarged JSON array/object lookup,
owned record unpack, and A01's same-source cheap/expensive maps at 1/2/8 workers.
Expected checksums are calculated independently. See `methodology.md` for the
fixed two-warmup/nine-measured alternating-pair procedure, affinity, noise review,
RSS limitations, compile-cache states and timing schedule.

`build-memory-observation.json` is a 16-second observed process-memory envelope
used by the coordinator for its centrally approved two-build-slot trial. Its
148,948 KiB maximum sum is **not a full-run build peak**. It double counts shared
pages and may include same-name unrelated processes. It is not RSS evidence for
compiler performance or memory savings.

Outstanding: frozen integrated candidate/default/retirement identities; A06
qualified uninstrumented application binaries; final matched measurements;
A03 allocation/RC/managed-memory results; A08 cache/scaling results; A01 scheduling
and A02 policy evidence. Final performance conclusions depend on those artifacts.
