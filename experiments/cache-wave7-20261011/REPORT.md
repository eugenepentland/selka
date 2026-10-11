# Wave 7a: application memoization in Selka

Baseline `cf3578c67`, branch `codex/selka-cache-wave7`, existing pinned Zig
`0.17.0-dev.1683+5ceec001b`. The primary integration checkout is unchanged.

The first application-library milestone is implemented and qualified. The final
full gate passed **124/124 build steps and 2,667 native tests**, with formatting,
guest Debug/Release tests, fact and leak checks, documentation and developer
tooling included. All 29 native result rows report zero failures and zero actual
skips; Zig's larger skipped count reflects normal shard partitioning. The final
source manifest is [`qualified-inputs.json`](qualified-inputs.json), and the full
gate evidence is [`verification.log`](verification.log) and
[`verification.json`](verification.json).

The unchanged repeat also passed, reusing all 30 eligible action groups while
running the 11 required freshness actions. Its observed gate admission lasted
22.14 seconds, versus 484.15 seconds in the full run; end-to-end durations were
32.60 and 504.71 seconds. These are verification observations under shared-server
admission, not isolated performance measurements. See
[`verification-warm.json`](verification-warm.json) and
[`verification-warm.log`](verification-warm.log).

## Implemented contract

The embedded `memo` standard module is written in Selka. It provides explicit
bounded FIFO retention, exact integer/text/byte keys, allocation-only callbacks,
independent value snapshots, clear/count/capacity operations and hit reporting.
Zero capacity supplies the forced-execution reference. Capacity limits count
entries, not arbitrary payload bytes; lookup is linear in retained entries.

Each retained entry carries its actual function. The compiler supplies a small
`same_function` builtin for checked, process-local identity comparison; changing
the cache's callback cannot reuse a different callback's value. It compares
native function pointers without exposing their addresses. Ordinary callable
equality and hashing remain ineligible. The frontend checks concrete and generic
signatures, Core verifies only equality/inequality on callable values, and LLVM
function definitions retain significant addresses.

Creation rejects limits outside 0 through 65,536 using a typed module error.
Computation finishes before insertion, and a trap propagates normally. Results
must satisfy equality and storage requirements, excluding capabilities, owned
resources, callbacks and must-handle result obligations. Public storage fields
are implementation details maintained by the constructor and operations;
replacing `compute` is supported, manually forging cache state is not.

The installed compiler and application library require no Python. Python remains
limited to existing developer verification and report extraction.

## Independent execution-count oracle

[`callback_counts.my`](callback_counts.my) issues 100 identical requests to one
callback. A counter-instrumented native build runs once with capacity 2 and once
with capacity 0, selected through runtime arguments. Both runs sum to 3,600 and
exit successfully. The native function counter records **1 callback invocation
with retention and 100 without retention**, independently of `Lookup.reused`.
The cached run reports 99 hits and one retained entry; the forced run reports
zero hits and zero entries. Both exit with zero live managed bytes.

Raw evidence: [`cached-counters.json`](cached-counters.json),
[`forced-counters.json`](forced-counters.json), their run logs, and
[`callback-summary.json`](callback-summary.json). These are work counts, not
latency or process-memory benchmarks. No timing speedup is claimed.

Reproduce after installing the compiler:

```bash
scripts/build-slot.sh build zig-out/bin/mylang build \
  experiments/cache-wave7-20261011/callback_counts.my \
  -o .mylang-cache/cache-wave7/callback-counts --counters
MYLANG_COUNTERS=cached.json MYL_CORE_LEAKCHECK=1 \
  .mylang-cache/cache-wave7/callback-counts
MYLANG_COUNTERS=forced.json MYL_CORE_LEAKCHECK=1 \
  .mylang-cache/cache-wave7/callback-counts forced
```

## Qualification and corrections

Focused identity checks pass in Debug and Release, including runtime-selected,
returned and stored generic callbacks, distinct declarations with identical
bodies, incompatible signatures, shadowing and reference discovery. Core checks
cover pointer comparison emission and rejection of pointer ordering.

The standard-library and function documentation execute 30 examples with zero
failures. Native memo tests cover exact callback effect ceilings and captured
state, output eligibility, exact key types and propagated traps. Ten guest tests
exercise callback replacement/reversion, FIFO, limits, clear, repeated bounded
eviction and byte-key/nested-result/cache-copy mutation isolation.

Retained initial failures are qualification-fixture corrections: formatting in
the reference listing, a fixture embedded outside Zig's module root (replaced by
a bounded registered input read), a lambda missing its contextual type, the
precise diagnostic for an incompatible callback arity, and a guest entry filename
colliding with the standard module's name (renamed `memo_cache.my`). Rejection
tests assert the exact intended semantic diagnostic after successful parsing and
loading; the capture test now reaches capture checking and same-shaped host/clock
callbacks independently exercise effect admission.

The first full gate completed with 2,665 native tests passing and one failing:
the existing reference drift check found that the reference tool's separate
standard-module list omitted `memo`. The other failing step was a single extra
blank line in `memo_cache.my`. Both are corrected: `memo` is now in the reference
manifest, its count assertion is 15, and the test source is canonical. The failed
run and its stable input snapshot are retained as
[`verification-failed-integration.log`](verification-failed-integration.log),
[`verification-failed-integration.json`](verification-failed-integration.json)
and [`qualified-inputs-pre-integration-fix.json`](qualified-inputs-pre-integration-fix.json).
The separate focused memo evidence predates that whitespace-only test change;
the final full gate qualifies the formatted test and final compiler together.

Adding the missing reference module exposed an existing listing parser defect:
`parseFunctionLine` sliced every export as a function before checking its kind,
so the short nominal line for `Key` panicked. It now checks the function prefix
first. A dedicated regression checks the declared `memo::Key` type beside the
generic `memo::call` function. The failing focused run is retained in
[`reference-format-final.log`](reference-format-final.log).

The final verification command owns its admission and is not wrapped in a build
slot. Its environment and pinned compiler are:

```bash
export PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX=/dev/null
export TMPDIR="$PWD/.mylang-cache/cache-wave7/tmp"
export ZIG_LOCAL_CACHE_DIR="$PWD/.zig-cache"
export ZIG_GLOBAL_CACHE_DIR=/home/epentland/ai/canopy/.zig-global-cache
python3 scripts/verify_cache.py \
  --zig /home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig \
  --shared-cache-dir .mylang-cache/cache-wave7/shared-evidence \
  -- -j3 --maxrss 8589934592
```

## Remaining Wave 7 milestones

**7b** requires compiler-issued reachable implementation/dependency identities,
canonical argument and result encodings, schemas and compiler/runtime/target
context, then bounded persistent storage with edit/revert qualification. Local
function identity cannot be serialized into such an identity.

**7c** requires capability-checked durable publication, synchronization and run
ownership, retained journals and the crash-injected CSV pipeline qualification.
The current guest filesystem lacks the required atomic rename, sync and locking
surface. Process-crash and power-loss guarantees must be qualified separately.

This milestone therefore provides no cross-process reuse or crash restart.
The staged plan is in [`PLAN.md`](PLAN.md).
