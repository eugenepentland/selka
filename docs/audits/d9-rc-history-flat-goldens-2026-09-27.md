# ABI3 historical native golden replay

The supplemental replay on the immutable Debug compiler from `19e16e1d` is
complete: **462/462 selected outcomes match**, 231 on QBE and 231 on LLVM
O3/full LTO. All counted executions balance allocation/retirement, ordinary
ownership and hold counts; none saturates or omits a required counter record.

The selection comprises 440 counted ABI3 executions, ten explicit legacy-sharing
GC controls and twelve CLI refusals that never start a guest. This includes
successful nonzero main returns, arena cases, file admission failures and traps.
The existing golden comparator preserves exit status, output or located failure
code as appropriate; the original expected outcomes are unchanged.

The compiler SHA-256 is
`1b705d90e58c6b2b3799c5cbe79da9adbc57913e4c72ebbfa2b54dad044c1bbe`.
Compiler, driver and declared input hashes were verified after the run. Builds
used that immutable installation while integration development continued.

This selection follows the authoritative native fixture mapping. Per backend,
27 documentation cases, 345 unmatched labels and one data entry are outside this
supplemental replay; the normal full gate covers its own declared selections.
The replay does not supersede the separately recorded augmented-field failure
at `19e16e1d`, establish the correctness of later source revisions or satisfy
WP-4 performance acceptance.

[Raw results, commands and identities](../../experiments/d9-rc-history-flat-goldens-20260927/README.md)
are committed alongside this report.
