# Bounded bias proposal; no implementation in this measured tree

The negative slowdown is explained by an actual path change: the old signed
guard admits all supplementary negative batches, while the extra endpoint sign
guard chooses the checked original. Preserve the old signed specialization.

Prefer one existing fast copy with a different positive-literal **flooring**
remainder recipe. The old planner already represents a magnitude bound as
`|x| <= coefficient * X^degree`, with `X = 2^loop.bits`. Compute the full
nonnegative mathematical bound `M` using checked u128 operations. For literal
`d > 0`, calculate `B = d * ceil(M / d)` with checked u128 operations, refusing
if `B` does not fit u64 or `M + B > MAXu64`. Then the old admitted range gives
`0 <= x + B <= MAXu64`, and B is an exact multiple of d. Therefore
`floor_mod(x,d) = unsigned_rem(x+B,d)`, for positive and negative x.

Emit the addition as wrapping 64-bit bit arithmetic, with no signed overflow
assumption. When B exceeds MAXi64, print its exact signed i64 bit pattern rather
than narrowing a mathematical value. Unsigned division consumes those bits.
All original guards, old non-remainder actions, runtime admission and checked
fallback remain. There is no runtime sign dispatch or third copy. Truncating
remainder is a different operation on negative operands and retains its old
recipe. Divisor zero/negative/unknown and proof failure retain old emission.

The precise certificate must use the **final old guard bits** and verify that
every magnitude leaf used by the dividend is already bounded by that old guard.
It must not add a new bound, recompute a narrower old plan, or infer a bound
from a node merely visited by analysis. Existing magnitude privacy/stability
requirements must apply to those dependencies, with optional refusal disabling
only this recipe. Candidate collection and bias evaluation must have explicit
work/node caps and allocation-failure cleanup; no decision may emit output.

The observed append has `coefficient=15`, `degree=1`, `bits=59`, so
`M=8646911284551352320`; for d=1009,
`B=8646911284551353149` and `M+B=17293822569102705469 < MAXu64`.
This is a general proof over the whole old admitted range, not a seed-specific
choice. It adds a bias addition per item relative to the seven-instruction
nonnegative recipe, but eliminates its new endpoint guard and checked negative
fallback. Actual backend instruction counts and effects still require inspection.

Alternatives:

- A third loop copy can preserve signed and unsigned variants, but the current
  `max_body=200` policy was designed for one extra copy. There is no existing
  aggregate budget that makes a second extra copy automatically acceptable.
  Its guard, renamed temporary and full body costs would require an explicit
  bounded policy, fallback to the old single-copy plan, and more OOM/collision
  tests. It is currently unauthorized.
- Restricting nonnegative emission to sign facts already guaranteed by an old
  guard preserves admission, but does not cover the observed dynamic seed and
  batch leaves; all their old bounds are symmetric.
- A universal sign-bit bias plus modular correction needs additional per-item
  correction arithmetic. It can support full i64 flooring semantics without
  cloning, but its actual backend cost is unknown and it is broader than the
  proposed existing-guard magnitude certificate.

Required successor tests include ±M and zero, divisors 1/powers of two/3/7/1009/
large positive values, infeasible bias, extreme i64 fallback, exact old guard
and action equivalence, escapes/caller storage, checked traps and partial output,
accounting/heap refusal, and allocation-failure replay. Start from a fresh 6cf
worktree and preserve both untimed 073e and measured 27de artifacts. No host build
or timing is authorized before review of the precise API and final source pin.
