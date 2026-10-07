# S4-F qualification checkpoint

Production source is commit `7877aa5d369f57aeb8fb850e8198c08c520b3a51`.
Later commits own measurement tools only. This checkpoint is **not yet qualified**:
the corrected real rebuild, one 31-edit counterbalanced scale run, strict450
fuzz matrix and final all46 rows remain pending. The row gate waits for the
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

Final compiler hashes (`final-guard-binaries.sha256`):

- Debug: `b1166c3c2bf1fb2cf3f359bb4c0bfd32d6de8acc47b5503d92826a6d9fd4076f`.
- ReleaseFast: `a23f5b6c41fae9b9fc04eb7a0485e548058590986209cdaa8e04ed1fcc622944`.
- Old strict oracle: `d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`.
- Old ReleaseFast timing pin: `eb354a1ad3763aa0c3851f6a96eb2bccf2ab0df94a2b983db46bdd0725c34eaf`.

`scale-05/summary.json` is the retained unqualified seven-edit uncontended run
on CPU10. Edited times are medians in seconds. Every source edit was fresh:

| Lines | Old validation | Core validation | Core complete typed |
| --- | ---: | ---: | ---: |
| 4,821 | 0.014734 | 0.013491 | 0.033858 |
| 48,101 | 0.114260 | 0.114414 | 0.185402 |
| 96,197 | 0.231057 | 0.228820 | 0.357337 |
| 192,389 | 0.467102 | 0.458571 | 0.726045 |

The 48k validation median missed old by 0.154 ms (0.13%). The 96k Core validation
median is 0.228820 s, below 0.45 s and below old. A single fresh 31-edit
counterbalanced run is queued, reporting paired variability and bootstrap
intervals; it must satisfy the exact median gate. This report does not treat
sampling uncertainty as permission to relax the gate. Cold validation times
were 0.029794 / 0.307380 / 0.626277 / 1.244887 s, approximately linear in size.
Complete typed build/test work is measured separately; the 16 MiB body retention
budget leaves additional bodies checked at large sizes, so validation numbers
must not be presented as complete typed frontend costs.

Retained failures and invalid measurements: full-old01 failed duplicate Zig
project_config ownership, corrected by `a185aa9`; full-old02 failed one old
native-test body-reuse assertion, corrected by `7877aa5`. Its prematurely queued
fuzz was aborted unqualified. Direct gate-to-build nesting dropped FD9 ownership;
that core receipt was invalidated and the gate shell now persists. Scale01
alternated old source versions and was invalidated; scale04 had contention and a
96k relative miss; scale05 retains its exact 48k miss. Scale06 was canceled before
admission for the prescribed larger counterbalanced run. Rebuild01 removed an
artifact but left the compile manifest cached, failed install and restored its
backup; rebuild02 invalidates only the private Core compile manifests as well.
The optional pre-C devloop smoke was canceled before admission and remains
aborted. No failed or aborted receipt was overwritten or promoted to green.

Shared helpers implemented in S4-M's tree are separately documented in its
`experiments/new-core-s4-20261006/tool-identity/NOTE.md`; they are outside this
frozen frontend production package and their M gates belong to the coordinator.
S4-X tooling owns fresh-edit CPU10 measurements, executable oracles, subprocess
traces, edited-unit timing, and separate 192k parallel cold reporting. Final X
measurements wait for qualified emission/object-cache packages.
