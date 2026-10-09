# C: injected clock and randomness capabilities

Source capabilities, synchronous embedding providers, recoverable read results,
and transitive clock/random effects are implemented. This record describes the
initial clock/random experiment. Later milestones add [environment lookup](environment.md),
[external resources](source-resources.md), [attenuation](attenuation.md),
[arenas](../legacy/experiments/source-arenas.md), and [pools](../legacy/experiments/source-pools.md).
[Native clock/random adapters](../legacy/experiments/native-providers.md) extended the removed C backend.

## Source contract

```text
result Time { ok: i64, err: i64 }
result Random { ok: u64, err: i64 }
fn sample(clock: clock_cap, rng: random_cap) -> Time effects(clock, random) {
    let now = clock_now[Time](clock)?;
    _ = random_u64[Random](rng)?;
    return new Time.ok(now);
}
```

`clock_now[R](capability)` returns Unix-epoch nanoseconds as signed i64; it is a
wall clock, with no monotonicity guarantee. `random_u64[R](capability)` returns
an unsigned 64-bit entropy word. The declared result must have the indicated
success type and an i64 error payload. The provider is responsible for sample
quality and clock accuracy. Injected deterministic test providers are supported.

Both operations evaluate their capability operand once, then invoke one provider
callback. Short-circuit evaluation can skip the operation. Results must be handled,
propagated, transferred, or explicitly released with `_ =` under the existing rules.
Recoverable provider errors are `Unavailable = 1`, `Denied = 2`, and `Failed = 3`.
Provider `OutOfMemory` is a host failure; arithmetic and capability traps remain
separate. Failure propagation releases owned locals and unfinished operands.

An entry may request each of `clock_cap` and `random_cap` once,
as value parameters in any order. Helpers receive authority through ordinary
explicit parameters. Capabilities can be copied, returned, and wrapped; copying
does not grant another kind of authority. Numeric construction/casts cannot mint
a capability. The runtime checks both execution identity and capability kind.

## Embedding boundary

`vm.Options.external` accepts optional `Clock` and `Random` providers from
`src/external_capabilities.zig`. Each contains a context pointer and typed read
callback. Contexts are host-owned and must remain valid for the synchronous run.
All requested entry grants are checked before guest instructions execute; granting
never calls a read callback. Missing providers produce host `CapabilityUnavailable`.
Providing an unused capability does not cause a read.

The VM uses its unique, non-reused memory-store identity for external grants.
Closed, foreign, and wrong-kind grants fail before a callback can run. Guest
values contain the identity/kind, not host pointers. The public Zig adapter is a
trusted embedding API, not a sandbox against a hostile host that edits internals.

There is no fallback to global clock or random APIs. The CLI supplies neither
provider: `check` and `dump-bytecode` accept `examples/external-capabilities.selka`,
but `run` exits 2 with `CapabilityUnavailable`. Embedders supply providers to
execute such programs. No real operating-system adapter or VM CLI grant flags are
claimed by this experiment.

Provider callbacks are trusted to honor the declared operation's effects. The
compiler cannot inspect arbitrary host callback code. A successful external read
may occur before a later host allocation failure; execution is not transactional
and does not roll back external observations. Capability values themselves have
no fallible completion or external cleanup operation.

## Effects and discovery

Clock reads contribute `clock`; random reads contribute `random`. Direct and
transitive call summaries include both, even in syntactically present branches
that happen not to execute. Restrictive `effects(...)` annotations reject excluded
operations with the existing call-path diagnostics. Bytecode validation recomputes
effect summaries independently and validates each read's result shape.

`noio` excludes filesystem/network effects only. Both reads are allowed under
`noio` and `noalloc`: neither annotation establishes determinism, and `noalloc`
continues to mean guest backing allocation rather than VM result bookkeeping.
Exact duplicate discovery is `exact-v18`, retaining external operation kinds,
capability operand identities, result types, and effect contracts.

## Acceptance evidence

271 tests pass in Debug and ReleaseFast (241 core, 30 actual CLI) on Guardian's
pinned Zig snapshot. The new tests cover mixed entry ordering, wrapper forwarding,
full-range u64 and signed i64 boundaries, denied/unused grants, fabrication and
kind errors, transitive bounds, malformed emission, skipped reads, all recoverable
provider failures, host OOM with owned-buffer cleanup, and stale/foreign grants.
Allocation-failure sweeps cover compilation, provider execution, and dumps.
10,000 reads fit within 16 KiB live runtime allocation and release all storage.
The CLI fixture verifies checking, dumps, denied execution, and bound rejection
across commands. All providers used by these tests are local deterministic fakes.
