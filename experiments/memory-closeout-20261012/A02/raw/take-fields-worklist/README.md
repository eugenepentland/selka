# Owned aggregate discovery after inlining

`takeFields` now discovers newly owned aggregate projections with a bounded
worklist. Its previous instruction-order scan missed a record projection when
inlining appended its producing aggregate after that projection in instruction
storage. The projection became owned only after its turn had passed, so a later
list update unnecessarily retained its child and zero-RC compilation refused.
This also affected explicit `.extend(...)` on frozen Support7, independently of
the field `+=` normalization.

The pass builds its existing use graph once, seeds eligible owners once, and
enqueues newly owned record/array reads at its four existing transfer sites.
A queued bit admits each eligible aggregate at most once. All borrowed-selection,
path, dominance, window, phi and complete-field checks are unchanged. There is no
whole-function fixed-point scan or new ownership equivalence.

The patch is based on `b6c480392732fcae8d0e67a071bea36a9e75ab77`.
The exact focused compiler SHA256 is
`e3c9738d5bb63cfd1560cfbfe0873ee252dec1f1c8e6824b4ff8e0a6455a8b54`;
source/toolchain identities, commands and logs are in `registered.json`.
The owned Support6 component pin supplies build helpers. This is interim compiler
qualification, separate from the coordinator's final package and default checks.

The registered suite passes 2/2 tests, including the inlined mut-call regression
through `+=` and `.extend`, five counted native modes, ten bounds/missing-key
trap runs and four unchanged overlap/borrow refusals. Shared admission tickets
were 1185 (focused compiler/tests) and 1194 (native matrices/diagnostics).

| Native corpus | Five checked modes | Ordinary release/debug |
| --- | --- | --- |
| Minimal inlined call followed by `+=` | 5/5 | 2/2 |
| Same call followed by `.extend` | 5/5 | 2/2 |
| Original `field_augmented` (6 public Boolean tests) | 5/5 | 2/2 |
| Original `rc_semantic_publication` (6 public Boolean tests) | 5/5 | 2/2 |

All twenty checked matrix runs have zero RC events, zero exit-live managed bytes
and no legacy RC helper references in emitted LLVM. Native outputs and assertions
pass in all 28 matrix runs. Direct destruction remains valid and is not counted
as an RC event. Raw counters, exact commands, source and binary hashes are under
`native/`; original/derived source identities are in `source-identities.json`.
Only assertion-only mains were added to the original public test bodies.

`diagnostic/` confirms that both minimized cases still contain aggregate producers
with larger instruction indices than their consuming projections, and their
post-ownership facts IR has no retain instructions. The earlier failing commands
and IR remain unchanged in `../field-augmented-prior-mut/`. No runtime, RSS or
compile-time performance claim is made from these correctness runs.
