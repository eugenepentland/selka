# Physical borrow inference on the Astra integration

WP-4pre is accepted for integration at `f6bea5d9`, combining physical borrow
inference with the accepted stage 3 default and the random snapshot migration.
The final four-step Debug gate passes: 94/94 main steps, 2,130 executed tests
(21,585 shard exclusions), QBE 51/51 with 429 tests, native-build 29/29 and
formatting 2/2. Logs are `.tmp-physical/accepted-*.log`; the frozen compiler at
`.tmp-physical/install-accepted/bin/mylang` has SHA-256
`8c8134078fc56eeb468e65d229db2480d99c39458b044e976d604bf64de69478`.
The complete [stage 3 performance gate](d9-performance43-final-2026-09-26.md)
passes separately. `main` and the devspeed branch remain untouched.

The prerequisite adds 72 schematic borrow classifications and retains 12
conservative copies, as recorded in the
[original evidence](d9-stage4pre-borrow-closeout-2026-09-26.md). The
[independent COW audit](d9-physical-borrow-cow-review-2026-09-26.md) passes 16
explicit-GC-stress cases on both backends, including mixed fresh/borrowed
results. Physical origin is a provenance bound, not an RC owner ledger:
production RC must certify its borrowed-result entry separately. Actual
retain/release traffic reduction remains a WP-4 acceptance measurement.

## Earlier integration gates


The isolated two-parent merge `ba4a1340` joins WP-4pre `450d151a` onto
compiler integration `5bdd99ea`. It retains both the new library-check command
and imported-function ownership explanations, both independent regression tests
added at the same location, and the v3 semantic-cache fixture. It was the initial isolated
prerequisite for reference counting; its acceptance depended on the later
combined correctness and stage 3 performance gates above.

The fresh four-step Debug gate passes: 93/93 main steps with 2,119 executed
tests (23,601 including 21,482 shard skips), 51/51 QBE steps with 429 tests,
29/29 QBE-build steps and 2/2 formatting steps. Whole-tree Guardian passed
88 checks on the merge. Logs are `.tmp-physical/gate-{test,test-qbe,
test-qbe-build,fmt-check}.log` in `d9-physical-borrow-after-astra`.

The later isolated merge `bd923864` brings this prerequisite onto the current
value-default candidate `75820f45`, including scoped receivers and indexed
transfers. The ownership test reader retains both physical/logical origins and
accepts the additive copy-site JSON detail without growing its seven-field
schema. All existing transfer assertions remain.

This refreshed default preparation passes all four gates: 94/94 main steps
with 2,128 executed tests (21,563 shard exclusions), QBE 51/51 with 429 tests,
native-build 29/29 and formatting 2/2. Guardian passes 88 checks without ratchet
growth. Logs are `.tmp-physical/default-{test,test-qbe,test-qbe-build,fmt-check}.log`.
At that point it remained isolated while performance and the broader Lox
native-GC-stress investigation were open. Both were subsequently resolved
before the final combined gate above.

## Earlier matched instruction measurements

Both Debug compilers build the exact same Lox source `6d54bace`. Guest binaries
use ReleaseFast with QBE, or LLVM opt 3 and full LTO. The mandated `pc.py`
calibrated VM workloads run three times per side on CPU 2; exact output is
checked before counting. These four cases do not replace the full 43-key gate.

| VM case | WP-4pre / parent QBE | WP-4pre / parent LLVM |
| --- | ---: | ---: |
| binary trees | 1.0018 | 0.9984 |
| closures | 1.0000 | 0.9940 |
| fib | 1.0000 | 0.9862 |
| trees | 1.0005 | 0.9955 |

This prerequisite offers only small measured GC-runtime improvements here. Its
main purpose remains physical provenance for safe RC transfer classification;
actual retain/release traffic belongs to WP-4.

- Parent compiler SHA-256: `ceb38b6e1fb1a23f20d92580b3cd7f07f635f5752311f27d477f9792e388b7d5`.
- Candidate compiler SHA-256: `ebccde0d2751e695fc1bbb4f08f41ee1e277da8ab7a1c862954803534355228b`.
- [Raw instruction samples and binary hashes](evidence/d9-physical-borrow-astra-perf.json).
