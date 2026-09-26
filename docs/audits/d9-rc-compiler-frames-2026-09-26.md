# Experimental RC compiler frame and collection lowering

The first executing compiler slice connects the physical ownership plan to
registered frame slots, operand values, local replacement, and canonical owned
returns. The default and compatibility runtime selections remain GC.

Every tracked slot has a separate initialized-token guard. Runtime copy and take
operations commit before that guard changes or an old destination is released.
A frame registers its guarded slots for non-local trap cleanup. Returns publish
an independent owned result before clearing scopes and releasing local owners.
Read operands borrow retained local storage; explicit value copies acquire
physical ownership independently of the earlier COW copy-elision decision.

The collection lowering, supplied by the collections agent, uses the explicit
heap-aware RC mutation helpers, normalizes pop-with-default to an owned result,
and journals fresh collection constructors across later fallible work. This
slice disables GC-only aggregate move/address shortcuts, slice-key fusion, and
loop versioning in the RC lane until physical ownership proofs cover them.
The collection runtime decides whether an operation's result is borrowed or
owned; the operand journal adopts fresh runtime results exactly once.

Validation in the isolated compiler worktree:

- `zig build test-units -Dtest-filter=RC`: 46 passed, including 35 named tests.
- Debug compiler installation and whole-tree Guardian: all 88 checks passed.
- The three permanent `tests/lang/rc_owned_values.my` guests pass through actual
  `mylang test --rc-runtime` on QBE Debug and with `--release` on LLVM,
  with no cached verdicts. They cover returned-list
  lifetime, mixed fresh/parameter returns, and repeated local replacement.
- The first LLVM attempt exposed an unsupported `loadw` spelling in the new
  helpers. They now emit the supported unsigned 32-bit `loaduw` operation.

This is an integration slice, not RC acceptance. Remaining compiler work includes
RC uniqueness and receiver scopes, aggregate partial-construction ownership,
variant and propagation branch transfers, arena-boundary slot cleanup,
pre-admission unique-argument cleanup, finalized CFG edge releases, and strong
borrowed-return certificates. Broad guest correctness, traps, resource ordering,
and the matched performance/RSS gates must pass before RC can become default.
