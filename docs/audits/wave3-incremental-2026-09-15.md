# Wave 3 completion — incremental compilation contract

Date: 2026-09-15
Plan: [self-hosting implementation plan](self-hosting-implementation-plan-2026-09-14.md), Wave 3

Wave 3 is complete. The incremental model now exists in the Zig (stage 0)
compiler as a tested, observable contract that the self-hosted port can
reproduce instead of inventing while chasing semantic parity.

## What landed

### Stable identities (backlog item 8)

`src/incremental.zig` derives SHA-256 identities for modules, top-level
declarations, exported interface items, nominal types/generic templates,
function bodies, generic specializations and emitted fragments. Identities never
contain source byte offsets: inserting text before a declaration leaves that
declaration's identity unchanged, and source spans remain diagnostic data. Each
declaration carries an `interface_sha256` over its observable checked interface
(types, effects, requirements, exported fields/variants and public layout), and
an `interface_identity` when exported. `project-dependencies` exposes the
manifest as `incremental-identities-v2` under `incremental`.

Evidence: `src/incremental_test.zig` (20 selected tests pass), including
whitespace/comment edits, private body vs signature, effect-bound edits,
record/union shape edits, insertion before a later declaration, specialization
key sensitivity, nominal-vs-template, and allocation-failure cleanup.

### Invalidation observability (backlog item 10)

`src/invalidation.zig` names the nine query stages, computes a canonical key for
each from a `project-dependencies-v1` receipt, and reports hits/misses with the
first changed dependency. `--explain-invalidation` emits one
`invalidation-report-v1` line on stderr; a missing baseline is nine misses with
`"no-baseline"`, a corrupt baseline is nine misses with `"corrupt-baseline"`
rather than a command failure. `--report` extends `frontend-cache-v1` with a
`stages` object of per-stage hit/miss counts. The baseline lives at
`<cache-dir>/invalidation/<entry>.json` and is not partitioned by compiler
identity, so a compiler change can be explained.

Evidence: `src/invalidation_test.zig` (10 tests, all nine stages, both baseline
failure modes, render order) and `test/integration.zig` (the cache-report parser
now finds the balanced outer JSON object; the existing project-cache test
passes).

### Cache-key completeness and generic specialization keys

`src/cache_key.zig` defines one six-dimension contract: compiler build identity,
bootstrap-language version, target, runtime ABI, effects/capabilities contract
and relevant flags. Its fingerprint is folded into the persistent syntax key,
whole-program verdict key, checked-function-body digest, generic-specialization
key and native object identity, so changing any dimension invalidates an entry
even when source bytes are identical. The persistent frontend format is now
`mylang-frontend-cache-v3`; `runtime_abi` is
`runtime-abi-v0-unfrozen` until Wave 4 freezes `runtime-abi-v1`.
`semantic_key.specializationKey` mixes template identity, ordered concrete
arguments, observed provider shape, target ABI and compiler identity.

Evidence: `src/frontend_cache_test.zig`, `src/semantic_cache_test.zig`,
`src/qbe_build_cache.zig` and `src/cache_key.zig` tests; the CLI project-cache
test still passes.

### Clean-versus-warm invalidation matrix (backlog items 9 and 10)

`src/invalidation_matrix_test.zig` runs the required matrix and asserts, per
case, identical accepted/rejected status, diagnostic JSON, checked
`language-schema-v1` interface manifest, normalized QBE for accepted programs,
and exact semantic reuse/check deltas. Cases: whitespace in and out of a body,
comments in and out of a body, private body, exported signature (accepted and
rejected), effect bound, constant value, record field shape, union shape, import
list, generic template body, specialization argument, runtime ABI, compiler
identity, and a damaged frontend entry that recomputes a clean result.

## Exit-criteria checklist

| Criterion | Status | Evidence |
| --- | --- | --- |
| matrix covers whitespace, comments, private bodies, exported signatures, effects, constants, record/union shape, imports, generic templates, specialization arguments, runtime ABI and compiler version | met | `src/invalidation_matrix_test.zig` |
| every case asserts reuse and clean-build equivalence | met | accepted status, diagnostic JSON, interface manifest, QBE and reuse deltas |
| reference compiler-shaped project meets the recorded warm-edit budget | met | `bench.my` private-body edit p95 8.6 ms vs 500 ms budget; `incremental-contract-profile.json` |
| incremental rules documented as public tooling behavior | met | `docs/experiments/incremental-contract.md`, updated `docs/tooling/caches.md`, SPEC `INCREMENTAL-ID-1`, `INVALIDATION-REPORT-1`, `INCREMENTAL-KEYS-1`, `INVALIDATION-MATRIX-1` |

## Gates run

- `zig build test-units` — 918 passed, 0 failed.
- `zig build test-cli` — 78 passed, 0 failed.
- `zig build test-doc-coverage` — 0 failures.
- `scripts/profile_development.py` on `selfhost/prototype/bench.my` — cold
  median/p95 20.4/23.2 ms, warm verdict 2.4/2.6 ms, edited check 7.6/8.6 ms
  (7 samples).

## Deviations and follow-ups

- The reference workload is the Wave 1 compiler-shaped lexer/builder prototype
  (`selfhost/prototype/bench.my`), not a full compiler project; it is the only
  versioned compiler-shaped workload available at this stage. A larger workload
  should replace it before switchover and ratchet the same budget.
- Generic and nominal reuse remains conservative: `semantic_key` still checks
  templates, constants, aliases and nominal syntax fresh. Wave 3 adds the
  specialization key primitive and the matrix cases; a full specialization reuse
  engine is deferred as the plan allows.
- The cache contract carries accurate defaults for the current single native
  target and empty flag set. Wave 4 must replace `runtime-abi-v0-unfrozen` with
  `runtime-abi-v1` and wire the frozen manifest into `Contract`.
- `--report` reports per-stage hit/miss counts; the first-changed dependency is
  carried by `invalidation-report-v1`, which `--explain-invalidation` emits.
