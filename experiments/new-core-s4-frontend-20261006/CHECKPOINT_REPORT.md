# S4-F qualification checkpoint

Production source is commit `7877aa5d369f57aeb8fb850e8198c08c520b3a51`.
Later commits own measurement tools only. This checkpoint is **not yet qualified**:
the corrected real rebuild, strict450 fuzz matrix and final all46 rows remain
pending. The 31-edit counterbalanced scale run is qualified. The row gate waits for the
qualified S4-V base. No main merge or push occurred; ir.zig remains unchanged.

Changes: Session enables shared syntax/body/check-summary caching for builds and
tests, with generated production compiler/runtime/property identity and a
separate Core value-semantics contract. Project configuration, nested entries,
provider overlays, interface access and profile/work counters are exposed to
S4-M. The shared project_config import uses one Zig module identity throughout
old and Core callers. Validation-only checks may stand summaries in for bodies;
build/test always retain complete typed trees. Codecs and format versions are
unchanged. Body hydration requires an explicit Core retention flag so old native
test instrumentation keeps its previous replay/lowering counts.

Final source correctness receipts:

- `test-core-05.log`: 281/281 tests, 64 shards, 163.77 s.
- `conformance-04.log`: 1518 matching / 0 mismatching / 0 unsupported in each of
  debug and release; both leak check and facts verification enabled, 402.99 s.
- `full-old-03/summary.json`: complete and qualified. Old `test`: 3004 passed,
  115 steps, 912.69 s command; `test-qbe`: 520/520, 87.82 s;
  `test-qbe-build`: 29 steps, 3.60 s; `fmt-check`: 2 steps, 0.25 s.
  All old unit-shard RSS limits passed. Full gate source receipt is tool commit
  `7c0c589`; production source remained `7877aa5` throughout.
- `frontend-tests-06.log`: five focused frontend tests;
  `legacy-facts-regression-01.log`: four focused old regression tests.
- Whole Guardian88 and commit-hook receipts are retained in guardian logs.

Compiler hashes used for completed correctness gates (`final-guard-binaries.sha256`):

- Debug: `b1166c3c2bf1fb2cf3f359bb4c0bfd32d6de8acc47b5503d92826a6d9fd4076f`.
- ReleaseFast: `a23f5b6c41fae9b9fc04eb7a0485e548058590986209cdaa8e04ed1fcc622944`.
- Old strict oracle: `d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`.
- Old ReleaseFast timing pin: `eb354a1ad3763aa0c3851f6a96eb2bccf2ab0df94a2b983db46bdd0725c34eaf`.

Rebuild02 installed a fresh source-identical Debug executable with hash
`ded2870efe5284dc9958d41ceba11880ae5f5a4d3281a518ec0b0a237e3c507c`.
Future strict fuzz must pin the executable produced by the final successful
rebuild rather than reuse the earlier Debug hash.

`scale-05/summary.json` is the retained unqualified seven-edit uncontended run
on CPU10. Edited times are medians in seconds. Every source edit was fresh:

| Lines | Old validation | Core validation | Core complete typed |
| --- | ---: | ---: | ---: |
| 4,821 | 0.014734 | 0.013491 | 0.033858 |
| 48,101 | 0.114260 | 0.114414 | 0.185402 |
| 96,197 | 0.231057 | 0.228820 | 0.357337 |
| 192,389 | 0.467102 | 0.458571 | 0.726045 |

The 48k validation median missed old by 0.154 ms (0.13%). The 96k Core validation
median is 0.228820 s, below 0.45 s and below old. This report does not treat
sampling uncertainty as permission to relax the gate. Cold validation times
were 0.029794 / 0.307380 / 0.626277 / 1.244887 s, approximately linear in size.
Complete typed build/test work is measured separately; the 16 MiB body retention
budget leaves additional bodies checked at large sizes, so validation numbers
must not be presented as complete typed frontend costs.

`scale-07/summary.json` qualifies the prescribed single fresh 31-edit
counterbalanced run. It retains CPU10 and all build slots, uses ReleaseFast for
both compilers, and rotates the old/validation/typed command order each round.
Every size satisfies the exact Core-validation-versus-old median gate:

| Lines | Old validation | Core validation | Core complete typed |
| --- | ---: | ---: | ---: |
| 4,821 | 0.014973 | 0.013419 | 0.033564 |
| 48,101 | 0.111423 | 0.106518 | 0.180948 |
| 96,197 | 0.228014 | 0.217621 | 0.358706 |
| 192,389 | 0.462877 | 0.447559 | 0.718974 |

The paired median validation-minus-old differences are -1.517 / -4.517 /
-9.402 / -16.050 ms. Their bootstrap 95% median intervals are all below zero.
Cold validation is 0.030698 / 0.320558 / 0.618566 / 1.261293 s, approximately
linear. Complete typed cold work remains variable (0.112608 / 0.395657 /
2.078381 / 3.278833 s); retained-body store I/O dominates some large cold runs.
The validation gate does not establish equivalent complete typed build/test
frontend costs.

Retained failures and invalid measurements: full-old01 failed duplicate Zig
project_config ownership, corrected by `a185aa9`; full-old02 failed one old
native-test body-reuse assertion, corrected by `7877aa5`. Its prematurely queued
fuzz was aborted unqualified. Direct gate-to-build nesting dropped FD9 ownership;
that core receipt was invalidated and the gate shell now persists. Scale01
alternated old source versions and was invalidated; scale04 had contention and a
96k relative miss; scale05 retains its exact 48k miss. Scale06 was canceled before
admission for the prescribed larger counterbalanced run. Rebuild01 removed an
artifact but left the compile manifest cached, failed install and restored its
backup. Rebuild02 performed real compilation in 2.392 s but its command failed
when Zig replaced the object directory containing the recovery backup. Its JSON
was written before cleanup and says qualified; the whole-command receipt is
explicitly unqualified. Recovery staging now lives outside Zig-managed object
and manifest directories; rebuild03 is queued to qualify the complete command.
The optional pre-C devloop smoke was canceled before admission and remains
aborted. No failed or aborted receipt was overwritten or promoted to green.

Shared helpers implemented in S4-M's tree are separately documented in its
`experiments/new-core-s4-20261006/tool-identity/NOTE.md`; they are outside this
frozen frontend production package and their M gates belong to the coordinator.
S4-X tooling owns fresh-edit CPU10 measurements, executable oracles, subprocess
traces, edited-unit timing, and separate 192k parallel cold reporting. Final X
measurements wait for qualified emission/object-cache packages.
