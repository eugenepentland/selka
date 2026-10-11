# Fixed-array reads and comparison-chain integration

Producer commit: `f47c2d72f6105123fc3dcd1800bce12525071bb3`.

The combined Selka body checker now includes fixed-array annotations,
constructors, contextual and byte literals, indexing, length, enum table
construction, and native comparison chains. It preserves the numeric producer,
tuple temporary obligations and schema10 boundary. The static-array place
emission helpers are included; full write routing remains in progress.

The integration exposed a Debug stack crash in the existing 256-block test.
Block checking now uses a small recursive dispatcher, separate from the large
non-block statement function. The semantic depth limit remains 256. A new test
accepts 254 nested blocks followed by a return expression and refuses the next
depth; the original 256-block refusal also passes. The synthetic test now gives
the function body a distinct index instead of accidentally rewriting its shared
return-expression index.

Qualification passed with the unchanged qualified seed:

- Eight focused roots: 37 tests in normal mode and 37 in Release with fact and
  leak verification; no failures, skips or cached test verdicts.
- Producer source checking, reachable formatting and 93 body harness selftests.
- Full Guardian commit gate: 88 checks.
- Fresh schema10 installed comparison-chain matrix: 31 fixtures and 219
  operations across reference, shadow and component modes. Checks and typed
  output match exactly; successful programs run under Release/facts/leaks.
- The existing body inventory in normal mode: 458 workflows, 916 comparisons,
  30 warm deployment checks and four live-session checks; no failures or skips.
  This also passed one valid and 22 malformed transport cases, 92 forged-reply
  rejections and two expected publication host failures.

The original `profile_chained_comparison` fixture also passed nine exact
source/typed/runtime operations against the genuine schema9 chain deployment.
Its manifest now requires successful checking, typed output and result 7. The
new schema10 body matrix includes that promoted fixture. Historical schema9
evidence and identities have not been rewritten.

The installed compiler is the fresh schema10 host recorded in the
[tuple checkpoint](selka-body-tuple-checkpoint10-2026-10-11.md).
The new body key is
`15b12dac837132d75da5eefc743e79f3dd75b3553899509df0b44cfc42c3d7ee`,
with artifact SHA256
`f5196a6ee1aef0701b490968505ad9b892acc41bbf63a5cd1465d4c605548a4e`.
All seven installed identities were verified before and after each matrix.

[The evidence receipt](evidence/selka-body-array-chain-integration-20261011/receipt.json)
binds the exact reports, source closure, package receipt, commands and logs,
including the initial stack failure and intermediate fixture/command corrections.

The strict structural gate remains 30 fixtures and 222 operations, with 13
hostile structural probes pending complete array write support. The full
repository gate and Release body matrix have not been claimed by this checkpoint.
Generic specialization, broader semantic coverage and later compiler stages
remain separate work; this is not full-language or bootstrap acceptance, and
no performance improvement is claimed.
