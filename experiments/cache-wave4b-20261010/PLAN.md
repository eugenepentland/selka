# Wave 4B: independent fuzz campaigns

Baseline: Wave 4A `028b7a3f7`, above main `1d202d41b`.
Branch: `codex/selka-cache-wave4b`; unchanged Zig `0.17.0-dev.1683+5ceec001b`.

Three Sol 6.1 agents own concrete differential export/replay, bounded evidence
storage, and the libFuzzer worker. The parent owns action identity, coordination,
admission, integration, documentation and independent qualification.

The completed shard is the checkpoint unit. All four active incremental/interface
targets preserve their existing oracles and legacy default command behavior.
Stable independent seeds and fixed per-shard work make shard-budget extension
possible without restoring a stateful mutation walk midway. Concrete rejected
and accepted cases are retained for replay on a changed candidate.

Coverage workers accept an explicit instrumented libFuzzer executable. They use
an immutable initial corpus per independent seed; successful completion requires
instrumentation and complete execution evidence. Raw retained inputs and original
or reproduced minimized failures are separate from target-specific success.
An external target must declare a complete deterministic input contract before
ordinary evidence reuse is enabled. A coverage-instrumented compiler entry point
and a Zig Maker backend are separate adapters, not delivered by this pass.

Qualification includes cold/warm/extended requests, exact retained replay after
target changes, target isolation, cancellation, force/failure behavior, lost and
corrupt evidence, source/config/tool changes and restored-byte edits, concurrent
publication, worker process cleanup and real compiler/libFuzzer smoke runs.
Cache lookup, snapshots and publication stay outside shared gate admission.
Operational admission durations are recorded without making isolated performance
claims. Full inventory verification and the normal Guardian commit hook finish
the pass. [REPORT.md](REPORT.md) records the final evidence.
