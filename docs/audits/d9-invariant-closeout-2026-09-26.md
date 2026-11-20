# D9 Q2: invariant cache and decoded values, 2026-09-26

The checked-body cache now retains functions that construct invariant-bearing
values. Copied JSON and native wire arguments validate their record and domain
invariants before an exported guest function observes them.

## Implementation

- `16f23ed8` relocates synthesized invariant operator spans and local metadata
  to the construction site. Previously, the cache rejected a retained body
  because its binary/unary operator spans still pointed to the type declaration.
- `c03fc089` compiles private per-type validation callbacks and includes their
  call dependencies in selective native builds. The codec reader validates each
  decoded record; the ordinary wire adapter validates completed argument trees
  inside the guest execution context. Recursive decoding keeps its existing
  depth limit. These callbacks do not add checks to ordinary guest calls.
- `4a459262` resets conversion-accounting state before checking a callback. A
  regression with a final one-field conversion followed by validation of a
  two-field record reproduced a checker bounds panic before the correction.

Callbacks use compiler-reserved names and remain absent from exports, test
selection and source-function caches. The host typed-JSON parser still performs
structural decoding; compiled native entry points execute the user clauses.
Invalid explicit input traps `R_INVARIANT` without publishing output or entering
the target body. Property-generated invalid input is discarded when the failure
originates in the boundary callback; invariant failures inside test bodies remain
failures. Test entry prologues retain their existing defensive checks.

## Evidence

- Cache relocation regression: failed before the fix, then passed after moving
  source declarations with a leading comment, reusing both checked bodies and
  comparing their result to a fresh check.
- Native boundary regression: valid and invalid records nested in a fixed array
  cross both ordinary and codec wire entries; the invalid second element traps
  before output publication. The invariant calls a private helper, exercising
  selective dependency retention. Codec calls also run with GC stress.
- CLI regression: invalid JSON list elements trap before the target prints;
  valid input succeeds; another invalid call over the warm native cache still
  traps. Property filtering and explicit cases-file behavior pass their focused
  CLI regression.
- Focused contracts: 21/21 selected tests passed. Native boundary selection:
  12/12 (one named regression and eleven unnamed imports). Each focused CLI
  selection passed 1/1. Whole-tree commit Guardian passed all 88 checks.

The full Debug gate passed at `cc5e5d54`: `test` 91/91 steps with 2,076
executed tests; `test-qbe` 49/49 steps with 426 tests; `test-qbe-build` 29/29
steps; and `fmt-check` 2/2 steps. Documentation coverage and doctests passed.
The four commands ran through the build-slot wrapper under the shared gate lock.
Raw logs are `.tmp-closeout/verified-{test,test-qbe,test-qbe-build,fmt-check}.log`
in the `codex-d9-invariant-closeout` worktree.

The first full run independently reproduced the preexisting NATIVE-STAGING-2
race also found by WP-3b: Zig's recursive directory creation panicked when a
concurrent build reclaimed the shared staging directory, leaving the worker
joined indefinitely. The isolated Sol fix `78ec28ba` was ported as `cc5e5d54`:
create the stable parent once, then use one mkdir and bounded retries for the
shared directory. The rerun completed without that panic. This prerequisite is
separate from the invariant implementation.

No main branch, original dirty checkout, or pending devspeed merge was changed.
