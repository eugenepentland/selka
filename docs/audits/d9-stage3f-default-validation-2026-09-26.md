# D9 stage 3f default validation candidate, 2026-09-26

The default implementation now passes correctness and the complete stage 3
performance gate. The accepted implementation is `9ab98d5f`, joined with
performance evidence at `66101ab7` on `codex/d9-stage3f-prep`. The latest
`main`, `b292660a`, is already an ancestor. Neither `main` nor the devspeed
merge branch was changed; downstream work uses validated integration commits.

The final correctness gate passed 94/94 main steps with 2,125 executed tests,
QBE 51/51 with 428 tests, native-build 29/29 and formatting 2/2. The complete
43-program-per-backend performance sweep measured 1.021851044× QBE and
1.046853543× LLVM, with every output correct and no program above 1.3×:
[final performance evidence](d9-performance43-final-2026-09-26.md).
The borrowed-inference join has its own subsequent combined gate.

## Implemented behavior

Value semantics is the default. `--legacy-sharing` provides the one-release
compatibility mode; `--value-semantics` remains an explicit selector. An explicit
flag wins over `MYLANG_VALUE_SEMANTICS=0|1`, which wins over the entry project's
`value_semantics` setting, whose default is true. The resolved mode is inherited
by child compilers and included in their cache identities. Commands with
separate-valued options before the source use their actual argument parser for
project discovery, including directory test entries.

Guest assertions, embedded Zig fixtures, the CLI suite, active guides, feature
metadata, and mutation/collection specifications describe independent values.
Tests that intentionally exercise legacy identity use explicit compatibility
scopes. Two builtin Cell guests moved to `tests/legacy`; the full gate now runs
them with `--legacy-sharing --gc-stress`. Five historical golden cases select
that mode individually, preserving their original source and expected outcome.
The other 226 replayable golden cases run with the default. No replay coverage
was removed.

The historical idiom manifest retains its shared-list baseline and changes its
required target to the independent-list result. The velocity suite adds three
explicit CPython divergences for list, nested-list and dictionary assignment;
all other disagreements remain gate failures. The
[113-probe score](evidence/d9-stage3f-default-score.json.gz) has zero undeclared
wrong answers and no stale policy declarations. The
[reproduced divergence evidence](../../velocity/suites/idioms/divergence-evidence-d9.json)
records the compiler hash, Python version and raw observations.

## Validation

All compilers were Debug builds. At `81eaf8d1`, the serialized full gate passed:

| Command | Result |
| --- | --- |
| `zig build test --summary all` | 94/94 steps; 2,108 executed Zig tests, 21,349 shard exclusions |
| `zig build test-qbe --summary all` | 51/51 steps; 428/428 tests |
| `zig build test-qbe-build --summary all` | 29/29 steps |
| `zig build fmt-check --summary all` | 2/2 steps |

The main gate includes 652/652 language guests across 113 programs, 49/49
value-specific guests, 42/42 smoke guests, and 2/2 explicit compatibility
guests. A separate forced run of all 652 language guests passed with GC stress
and no cached results. The golden replay checked all 231 reproducible cases
(175 recorded sources and 56 mapped fixtures), with zero mismatches; its 373
previously documented skips are unchanged. Documentation ran 203 examples and
checked 51 more. The original GC footprint step budget was retained.

The first default gate exposed the remaining smoke alias assertions, the
historical idiom target, and five historical goldens; those were migrated
explicitly before the successful gate. Review also reproduced the option-order
configuration bug and added a regression covering test files/directories,
build output options, and invoke function options. All whole-tree Guardian
commit hooks passed 88 checks without ratchet growth. Later guide-only wording
updates are validated separately; the full-gate source commit above is fixed.

## Commits and remaining work

Principal implementation commits are `a7a6a850` (mode default and opt-out),
`ae9ec04b` (project discovery), `0c7ab218` (guest migration), `ea6b1e66` and
`f10aa1a5` (documentation), `3bd5cf28`, `5946f5da`, `c300fb25`, `4cb429ff`,
`7c7c2759` (embedded fixtures), `482cab19` (Cell compatibility lane), and
`4a9dd406` (oracle evidence). Integration uses real two-parent merges.

The later joined compiler/source candidate `b937d4fc` also passes all four
steps: 94/94 main steps with 2,112 executed tests (21,393 shard exclusions),
51/51 QBE steps and 428 tests, 29/29 QBE-build steps, and formatting 2/2.

The Astra merge at `17540b57` passes a third complete gate: 94/94 main
steps with 2,116 executed tests (21,437 shard exclusions), QBE 51/51 with
428 tests, QBE-build 29/29, and formatting 2/2. It includes immutable-box
path detachment and lazy projection, closed-region field transfers, private
COW scratch optimization, unused alias initialization removal, and the latest
validated external Lox source. It does not include the unfinished nested-array
callback fix. Logs are `.tmp-stage3f/astra-default-*.log` in this worktree.

The refreshed candidate at `5b663e23` passes all four gates: 94/94 main
steps with 2,122 executed tests (21,503 shard exclusions), QBE 51/51 with
428 tests, native-build 29/29 and formatting 2/2. It includes pure recursive-box
reads and the scoped nested receivers from integration `b6328bcd`, plus the
composed receiver-RHS, class-reader and late-closure source fixes at `d7f4cf85`.
Logs are `.tmp-stage3f/scopes-default-{test,test-qbe,test-qbe-build,fmt-check}.log`.
Guardian's 88 checks pass without ratchet growth. The subsequent indexed
payload-return proof and Lox setter helper are not part of this frozen gate.

The indexed candidate at `75820f45` also passes all four gates: 94/94 main
steps with 2,123 executed tests (21,514 shard exclusions), QBE 51/51 with
428 tests, native-build 29/29 and formatting 2/2. This run executes 652 language,
139 value-specific, 42 smoke and two compatibility guests with zero cached
results in those guest lanes. The frozen Debug compiler at
`.tmp-stage3f/install-indexed/bin/mylang` has SHA-256
`cdd9bed601bb0ade5705c5af8c962e7d10c55463128bba7fb57c915b271ac5cd`.
Logs are `.tmp-stage3f/indexed-default-*.log`. Its indexed proof and scoped
receivers have separate independent joined stress/legacy-IL validation.

The broader external Lox native-GC-stress failures are resolved by the
[`ref_local` liveness correction](d9-mut-reference-liveness-2026-09-26.md),
joined at `178d43dc`. Its 260 uncached port tests cover both modes and
backends; all 44 legacy IL comparisons remain identical. The historical
fixed-array counterexample establishes a pre-existing root defect, made more
visible by the later mut-record migration.

Correct liveness also exposed random-stream assertions that still expected
sharing: the previous compiler incorrectly treated the source as dead and
moved it. The [migration at `9ab98d5f`](d9-random-value-migration-2026-09-26.md)
now checks independent generator snapshots under value semantics and pins
shared streams explicitly under legacy sharing. The old compiler fails the
new snapshot tests; the corrected compiler passes both backends with native
GC stress. Generator algorithm, signature and representation are unchanged;
the only embedded `random.my` changes are comments. This final full gate
executes 656 language guests, 139 value-specific guests, 42 smoke guests and
two compatibility guests uncached. Logs are in
`d9-random-value-fix/.tmp-random/gate-*.log`; its fresh Debug compiler SHA is
`31bf2ae018160071c1395b00b7b056e3f1e9d0c0d81e578e3ef4e77f6786b0a0`.

The frozen performance compiler is `178d43dc`, SHA
`52ddd1337b4998b2a22184cac58af5ae4b0f4bc465dd449cfae3271c7451575d`.
It includes the root correction, indexed transfer proof, and final Lox
setter/hash-hoist composition. The later random migration changes only
comments, tests, specification and examples, so no measured compiler/runtime
algorithm changed between that sweep and the accepted correctness gate.
Earlier failing sweeps remain historical evidence. The formal performance
limits are satisfied without changing the workload or threshold. The tree
interpreter remains supplemental audit coverage. Reference counting and
concurrency retain their own implementation and acceptance requirements.
